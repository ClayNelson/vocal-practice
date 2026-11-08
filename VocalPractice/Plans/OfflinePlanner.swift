import Foundation

/// Everything the planners need to build a plan. M2's ClaudePlanner fills `assessment`.
struct PlanRequest {
    var title: String
    var artist: String = ""
    var goalType: GoalType = .showcase
    var goalLabel: String
    var goalDate: PlanDate
    var goalDateIsApprox = false
    var start: PlanDate = .today()
    var originalKey: String?
    var keyOptions: [String] = []
    var rangeLow: String?
    var rangeHigh: String?
    var minutesPerPass = 6
    /// Empty means the default sections.
    var sections: [PlanSection] = []
    var blocked: [PlanBlockedRange] = []
    var questionsForTeacher: [String] = []
    var assessment: PlanAssessment?
    /// From range history (M2), optional.
    var userHighMidi: Int?
}

/// Builds a plan with no network: phases sized to the time left, blocked days turned into
/// maintenance, and dated checkpoints. Pure and deterministic.
enum OfflinePlanner {
    static let defaultSections = [
        PlanSection(id: "hardest-phrase", title: "Hardest phrase", difficulty: .high,
                    focus: "The spot that pushes your range. Half volume first, then build."),
        PlanSection(id: "ending", title: "Ending", difficulty: .medium,
                    focus: "Land the last line with breath to spare."),
    ]

    static func makePlan(_ r: PlanRequest) -> SongPlan {
        let start = min(r.start, r.goalDate)
        let total = start.daysUntil(r.goalDate) + 1
        let sections = r.sections.isEmpty ? defaultSections : r.sections

        let segments = allocate(days: total)
        let runs = applyBlocks(segments: segments, start: start, total: total, blocked: r.blocked)

        var phases: [PlanPhase] = []
        var usedIDs: [String: Int] = [:]
        var day = start
        for run in runs {
            let end = day.adding(days: run.length - 1)
            let baseID: String
            var phase: PlanPhase
            switch run.slot {
            case .blocked(let label):
                baseID = "maintenance"
                phase = PlanPhase(id: "", title: label, start: day, end: end, songBlock: .maintenance,
                                  notes: "Two or three full runs a week. No new changes.")
            case .segment(let index):
                let kind = segments[index].kind
                baseID = kind.id
                phase = PlanPhase(id: "", title: kind.title, start: day, end: end, songBlock: kind.block,
                                  focusSections: focus(for: kind, sections: sections), notes: kind.notes)
            }
            let count = usedIDs[baseID, default: 0] + 1
            usedIDs[baseID] = count
            phase.id = count == 1 ? baseID : "\(baseID)-\(count)"
            phases.append(phase)
            day = end.adding(days: 1)
        }

        let originalKey = r.originalKey.flatMap { $0.isEmpty ? nil : $0 } ?? r.keyOptions.first ?? ""
        var range: PlanRange?
        if r.rangeLow?.isEmpty == false || r.rangeHigh?.isEmpty == false {
            range = PlanRange(low: r.rangeLow?.nilIfEmpty, high: r.rangeHigh?.nilIfEmpty)
        }

        return SongPlan(
            song: PlanSong(title: r.title, artist: r.artist, originalKey: originalKey, keyOptions: r.keyOptions,
                           range: range, minutesPerPass: r.minutesPerPass),
            goal: PlanGoal(type: r.goalType, label: r.goalLabel, date: r.goalDate, dateIsApprox: r.goalDateIsApprox),
            sections: sections,
            phases: phases,
            checkpoints: checkpoints(phases: phases, start: start, request: r),
            questionsForTeacher: r.questionsForTeacher,
            generatedBy: "Vocal Practice offline planner",
            generatedAt: start.description,
            assessment: r.assessment ?? rangeAssessment(r, originalKey: originalKey),
            blockedRanges: r.blocked.isEmpty ? nil : r.blocked)
    }

    // MARK: Phase allocation

    enum Kind: Equatable {
        case listen, build, character, sections, fullRun, taper

        var block: SongBlock {
            switch self {
            case .listen: .listen
            case .build, .character, .sections: .sections
            case .fullRun: .fullRun
            case .taper: .taper
            }
        }
        var id: String {
            switch self {
            case .listen: "absorb"
            case .build: "build"
            case .character: "character"
            case .sections: "sections"
            case .fullRun: "performance"
            case .taper: "taper"
            }
        }
        var title: String {
            switch self {
            case .listen: "Absorb and key"
            case .build: "Build the hard spots"
            case .character: "Character and story"
            case .sections: "Sections"
            case .fullRun: "Performance mode"
            case .taper: "Taper"
            }
        }
        var notes: String {
            switch self {
            case .listen: "Daily listening to the reference. Map breath points. Speak in rhythm. Test keys."
            case .build: "Half volume first, then build. Record each section take."
            case .character: "Every section, with the story in it. Keep the top free, not loud."
            case .sections: "The hardest unresolved section each day. Half volume first."
            case .fullRun: "Standing, start to finish, no stopping."
            case .taper: "Short runs, nothing new, rest the day before."
            }
        }
    }

    struct Segment: Equatable {
        var kind: Kind
        var days: Int
    }

    /// Phase lengths for `days` from start to goal, inclusive (the table in IMPLEMENTATION_PLAN.md M1.3).
    static func allocate(days d: Int) -> [Segment] {
        switch d {
        case 70...:
            let rest = d - 14 - 14 - 7
            return [Segment(kind: .listen, days: 14), Segment(kind: .build, days: rest - rest / 2),
                    Segment(kind: .character, days: rest / 2), Segment(kind: .fullRun, days: 14),
                    Segment(kind: .taper, days: 7)]
        case 28...69:
            let full = d < 49 ? 7 : 14
            // One sections phase: it keeps the "hard spots" name but focuses every section.
            return [Segment(kind: .listen, days: 7), Segment(kind: .build, days: d - 7 - full - 7),
                    Segment(kind: .fullRun, days: full), Segment(kind: .taper, days: 7)]
        case 7...27:
            let full = max(3, d / 4)
            return [Segment(kind: .sections, days: d - full - 3), Segment(kind: .fullRun, days: full),
                    Segment(kind: .taper, days: 3)]
        case 2...6:
            return [Segment(kind: .fullRun, days: d - 1), Segment(kind: .taper, days: 1)]
        default:
            return [Segment(kind: .taper, days: 1)]
        }
    }

    enum Slot: Equatable {
        case segment(Int)
        case blocked(String)

        var isBlocked: Bool { if case .blocked = self { true } else { false } }
    }

    struct Run: Equatable {
        var slot: Slot
        var length: Int
    }

    /// Blocked days outside the taper become maintenance. The block uses up those days; nothing
    /// moves later. Adjacent maintenance merges, and a split remnant under 3 days joins it.
    static func applyBlocks(segments: [Segment], start: PlanDate, total: Int, blocked: [PlanBlockedRange]) -> [Run] {
        var days: [Slot] = segments.enumerated().flatMap { index, segment in
            Array(repeating: Slot.segment(index), count: segment.days)
        }
        for block in blocked.sorted(by: { $0.start < $1.start }) {
            for offset in 0..<total {
                let day = start.adding(days: offset)
                guard block.start <= day, day <= block.end, case .segment(let index) = days[offset],
                      segments[index].kind != .taper else { continue }
                days[offset] = .blocked(block.label)
            }
        }

        var runs = group(days)
        var changed = true
        while changed {
            changed = false
            for i in runs.indices {
                guard case .segment(let index) = runs[i].slot,
                      runs[i].length < segments[index].days, runs[i].length < 3 else { continue }
                let neighbor = [i - 1, i + 1].first { runs.indices.contains($0) && runs[$0].slot.isBlocked }
                if let neighbor {
                    runs[i].slot = runs[neighbor].slot
                    changed = true
                }
            }
            if changed { runs = group(runs.flatMap { Array(repeating: $0.slot, count: $0.length) }) }
        }
        return runs
    }

    /// Consecutive days with the same slot form a run. Adjacent maintenance merges under the first label.
    private static func group(_ days: [Slot]) -> [Run] {
        var runs: [Run] = []
        for slot in days {
            if let last = runs.last, last.slot == slot || (last.slot.isBlocked && slot.isBlocked) {
                runs[runs.count - 1].length += 1
            } else {
                runs.append(Run(slot: slot, length: 1))
            }
        }
        return runs
    }

    /// "Build the hard spots" in a plan with two section phases works the high-difficulty sections
    /// (or all, if none is high). Every other section phase works all of them.
    private static func focus(for kind: Kind, sections: [PlanSection]) -> [String] {
        switch kind {
        case .build:
            let high = sections.filter { $0.difficulty == .high }
            return (high.isEmpty ? sections : high).map(\.id)
        case .character, .sections:
            return sections.map(\.id)
        default:
            return []
        }
    }

    // MARK: Checkpoints

    private static func checkpoints(phases: [PlanPhase], start: PlanDate, request r: PlanRequest) -> [PlanCheckpoint] {
        var result: [PlanCheckpoint] = []
        let keyTitle = r.keyOptions.count > 1 ? "Lock key (\(PlanFormat.list(r.keyOptions)))" : "Lock key"
        if let listen = phases.last(where: { $0.songBlock == .listen }) {
            result.append(PlanCheckpoint(title: keyTitle, due: listen.end))
        } else {
            result.append(PlanCheckpoint(title: keyTitle, due: start.adding(days: 3)))
        }
        if let fullRun = phases.first(where: { $0.songBlock == .fullRun }) {
            result.append(PlanCheckpoint(title: "Lock arrangement", due: fullRun.start.adding(days: -1)))
        }
        if r.goalDateIsApprox {
            var due = start.adding(days: 14)
            if let taper = phases.last(where: { $0.songBlock == .taper }) { due = min(due, taper.start.adding(days: -1)) }
            result.append(PlanCheckpoint(title: "Confirm date", due: due))
        }
        // Stable: equal dates keep the order above.
        return result.enumerated()
            .filter { $0.element.due >= start }
            .sorted { ($0.element.due, $0.offset) < ($1.element.due, $1.offset) }
            .map(\.element)
    }

    // MARK: Range check

    /// When the song's top note is above the singer's recent high, suggest lower keys.
    static func rangeAssessment(_ r: PlanRequest, originalKey: String) -> PlanAssessment? {
        guard let high = r.rangeHigh, let songHigh = NoteName.midi(high), let userHigh = r.userHighMidi,
              songHigh > userHigh else { return nil }
        let over = songHigh - userHigh
        let semitones = over == 1 ? "1 semitone" : "\(over) semitones"
        let keys = [over, over + 1].compactMap { NoteName.key(originalKey, down: $0) }
        let suggestion = keys.isEmpty ? "Try a lower key." : "Try \(PlanFormat.list(keys))."
        return PlanAssessment(keyRecommendation: "The top note \(high) is \(semitones) above your recent high. \(suggestion)")
    }
}

extension PlanRequest {
    /// A request that reproduces `plan` when re-run, for edits that change the goal date or blocked days.
    /// Starts from the plan's first day so past phases stay put.
    init(editing plan: SongPlan) {
        self.init(title: plan.song.title, artist: plan.song.artist, goalType: plan.goal.type,
                  goalLabel: plan.goal.label, goalDate: plan.goal.date, goalDateIsApprox: plan.goal.dateIsApprox,
                  start: plan.phases.first?.start ?? .today(), originalKey: plan.song.originalKey,
                  keyOptions: plan.song.keyOptions, rangeLow: plan.song.range?.low, rangeHigh: plan.song.range?.high,
                  minutesPerPass: plan.song.minutesPerPass, sections: plan.sections,
                  blocked: plan.blockedRanges ?? [], questionsForTeacher: plan.questionsForTeacher,
                  assessment: plan.assessment)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
