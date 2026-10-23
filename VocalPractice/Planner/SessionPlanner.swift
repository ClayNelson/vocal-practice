import Foundation

/// Pure planning logic, independent of SwiftData and UIKit so it can be unit tested anywhere.

public enum SongStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case seam, learning, polishing, performanceReady, recorded, retired
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .seam: "Seam"
        case .learning: "Learning"
        case .polishing: "Polishing"
        case .performanceReady: "Performance ready"
        case .recorded: "Recorded"
        case .retired: "Retired"
        }
    }

    /// Songs in these states get practice time.
    public var isPracticeEligible: Bool {
        switch self {
        case .learning, .polishing, .performanceReady: true
        default: false
        }
    }
}

public struct WarmupSnapshot: Equatable, Sendable {
    public var id: UUID
    public var title: String
    /// Warmups sharing a ladder group form a progression; only the current rung is scheduled.
    public var ladderGroup: String?
    public var ladderLevel: Int
    public var minutes: Int
    public var isSolid: Bool
    public var lastPracticed: Date?

    public init(id: UUID = UUID(), title: String, ladderGroup: String? = nil, ladderLevel: Int = 0,
                minutes: Int, isSolid: Bool = false, lastPracticed: Date? = nil) {
        self.id = id; self.title = title; self.ladderGroup = ladderGroup; self.ladderLevel = ladderLevel
        self.minutes = minutes; self.isSolid = isSolid; self.lastPracticed = lastPracticed
    }
}

public struct SongSnapshot: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var status: SongStatus
    public var minutes: Int
    public var showcase: Bool
    public var lastPracticed: Date?
    public var goalDate: Date?
    /// Set when the song has a plan and today falls inside one of its phases.
    public var planContext: SongPlanContext?

    public init(id: UUID = UUID(), title: String, status: SongStatus, minutes: Int,
                showcase: Bool = false, lastPracticed: Date? = nil,
                goalDate: Date? = nil, planContext: SongPlanContext? = nil) {
        self.id = id; self.title = title; self.status = status; self.minutes = minutes
        self.showcase = showcase; self.lastPracticed = lastPracticed
        self.goalDate = goalDate; self.planContext = planContext
    }
}

/// What today's phase of a song's plan asks for.
public struct SongPlanContext: Equatable, Sendable {
    public var block: SongBlock
    public var minutesPerPass: Int
    /// The phase's focus sections, in plan order.
    public var focusSections: [SectionSnapshot]
    public var fullRunsThisWeek: Int

    public init(block: SongBlock, minutesPerPass: Int, focusSections: [SectionSnapshot] = [], fullRunsThisWeek: Int = 0) {
        self.block = block; self.minutesPerPass = minutesPerPass
        self.focusSections = focusSections; self.fullRunsThisWeek = fullRunsThisWeek
    }
}

public struct SectionSnapshot: Equatable, Sendable {
    public var id: String
    public var title: String
    public var focus: String
    /// high, medium, or low
    public var difficulty: String
    public var order: Int
    /// free, pressed, or cracked
    public var lastRating: String?
    public var lastPracticed: Date?

    public init(id: String, title: String, focus: String = "", difficulty: String = "medium", order: Int = 0,
                lastRating: String? = nil, lastPracticed: Date? = nil) {
        self.id = id; self.title = title; self.focus = focus; self.difficulty = difficulty; self.order = order
        self.lastRating = lastRating; self.lastPracticed = lastPracticed
    }
}

/// How a song item is practiced in a session, from its plan's current phase.
public enum SongMode: Equatable, Sendable {
    case normal
    case listen
    case section(id: String, title: String, focus: String)
    case fullRun
    case taper

    /// Shown under the song title on Today; nil for an unplanned song.
    public var label: String? {
        switch self {
        case .normal: nil
        case .listen: "Listen"
        case .section(_, let title, _): "Section: \(title)"
        case .fullRun: "Full run"
        case .taper: "Taper run"
        }
    }
}

public enum PlanItem: Equatable, Sendable {
    case warmup(WarmupSnapshot)
    case song(SongSnapshot, SongMode = .normal)

    public var id: UUID {
        switch self { case .warmup(let w): w.id; case .song(let s, _): s.id }
    }
    public var title: String {
        switch self { case .warmup(let w): w.title; case .song(let s, _): s.title }
    }
    public var minutes: Int {
        switch self { case .warmup(let w): w.minutes; case .song(let s, _): s.minutes }
    }
    public var songMode: SongMode? {
        if case .song(_, let mode) = self { mode } else { nil }
    }
}

public struct SessionPlan: Equatable, Sendable {
    public var targetMinutes: Int
    public var warmups: [PlanItem]
    public var songs: [PlanItem]
    public var items: [PlanItem] { warmups + songs }
    public var plannedMinutes: Int { items.reduce(0) { $0 + $1.minutes } }
}

public enum SessionPlanner {
    /// Studio policy: 3 days x 60, 4 days x 45, 5 days x 30.
    public static func defaultMinutes(daysPerWeek: Int) -> Int {
        switch daysPerWeek {
        case ...3: 60
        case 4: 45
        default: 30
        }
    }

    /// Builds a session: first half warmups, second half songs (studio policy).
    /// - Parameter voiceCondition: 1 (rough) to 5 (great). At 1 or 2 the song block is halved
    ///   and ladders step back one rung so the voice is not pushed.
    public static func plan(minutes: Int,
                            warmups: [WarmupSnapshot],
                            songs: [SongSnapshot],
                            voiceCondition: Int = 3) -> SessionPlan {
        let gentle = voiceCondition <= 2
        let warmupBudget = minutes / 2
        let songBudget = gentle ? (minutes - warmupBudget) / 2 : minutes - warmupBudget

        let warmupItems = fill(budget: warmupBudget,
                               from: warmupCandidates(warmups, gentle: gentle).map(PlanItem.warmup))
        let songItems = fill(budget: songBudget,
                             from: songItems(songCandidates(songs), gentle: gentle))
        return SessionPlan(targetMinutes: minutes, warmups: warmupItems, songs: songItems)
    }

    /// One current rung per ladder, plus every standalone warmup, ordered least recently practiced first.
    /// Ladders come before standalones so progression work is never crowded out.
    static func warmupCandidates(_ warmups: [WarmupSnapshot], gentle: Bool) -> [WarmupSnapshot] {
        var ladders: [WarmupSnapshot] = []
        let grouped = Dictionary(grouping: warmups.filter { $0.ladderGroup != nil }, by: { $0.ladderGroup! })
        for group in grouped.keys.sorted() {
            let rungs = grouped[group]!.sorted { $0.ladderLevel < $1.ladderLevel }
            guard let currentIndex = rungs.firstIndex(where: { !$0.isSolid }) ?? rungs.indices.last else { continue }
            let index = gentle ? max(0, currentIndex - 1) : currentIndex
            ladders.append(rungs[index])
        }
        let standalone = warmups.filter { $0.ladderGroup == nil }.sorted(by: leastRecent)
        return ladders.sorted(by: leastRecent) + standalone
    }

    /// Songs with an active plan first (nearest goal first), then showcase songs, then Learning,
    /// then least recently practiced. A planned song is practiced whatever its status, unless retired.
    static func songCandidates(_ songs: [SongSnapshot]) -> [SongSnapshot] {
        songs.filter { $0.status.isPracticeEligible || ($0.planContext != nil && $0.status != .retired) }.sorted { a, b in
            let aPlanned = a.planContext != nil, bPlanned = b.planContext != nil
            if aPlanned != bPlanned { return aPlanned }
            if aPlanned, a.goalDate != b.goalDate {
                return (a.goalDate ?? .distantFuture) < (b.goalDate ?? .distantFuture)
            }
            if a.showcase != b.showcase { return a.showcase }
            let aLearning = a.status == .learning, bLearning = b.status == .learning
            if aLearning != bLearning { return aLearning }
            return leastRecent(a.lastPracticed, b.lastPracticed)
        }
    }

    /// Turns each song into a session item following its plan's phase. Maintenance songs drop out
    /// after 3 full runs in the week; taper songs drop out on a rough voice.
    static func songItems(_ songs: [SongSnapshot], gentle: Bool) -> [PlanItem] {
        songs.compactMap { song in
            guard let context = song.planContext else { return .song(song, .normal) }
            var item = song
            item.minutes = context.minutesPerPass
            switch context.block {
            case .listen:
                return .song(item, .listen)
            case .sections:
                guard let section = pickSection(context.focusSections) else { return .song(item, .fullRun) }
                return .song(item, .section(id: section.id, title: section.title, focus: section.focus))
            case .fullRun:
                item.minutes = context.minutesPerPass * 2
                return .song(item, .fullRun)
            case .maintenance:
                return context.fullRunsThisWeek < 3 ? .song(item, .fullRun) : nil
            case .taper:
                return gentle ? nil : .song(item, .taper)
            }
        }
    }

    /// The hardest unresolved section: cracked, then pressed, then never practiced, then oldest.
    /// Ties go to difficulty (high first), then plan order.
    static func pickSection(_ sections: [SectionSnapshot]) -> SectionSnapshot? {
        func bucket(_ s: SectionSnapshot) -> Int {
            switch s.lastRating {
            case "cracked": 0
            case "pressed": 1
            default: s.lastPracticed == nil ? 2 : 3
            }
        }
        func difficulty(_ s: SectionSnapshot) -> Int {
            switch s.difficulty { case "high": 0; case "medium": 1; default: 2 }
        }
        return sections.min { a, b in
            if bucket(a) != bucket(b) { return bucket(a) < bucket(b) }
            if bucket(a) == 3, let da = a.lastPracticed, let db = b.lastPracticed, da != db { return da < db }
            if difficulty(a) != difficulty(b) { return difficulty(a) < difficulty(b) }
            return a.order < b.order
        }
    }

    /// Greedy fill in priority order; skips items that don't fit, never splits one.
    /// Always includes the first candidate so a short budget still yields a session.
    static func fill(budget: Int, from candidates: [PlanItem]) -> [PlanItem] {
        var result: [PlanItem] = []
        var used = 0
        for item in candidates where used + item.minutes <= budget || result.isEmpty {
            result.append(item)
            used += item.minutes
        }
        return result
    }

    private static func leastRecent(_ a: WarmupSnapshot, _ b: WarmupSnapshot) -> Bool {
        leastRecent(a.lastPracticed, b.lastPracticed)
    }

    /// Never-practiced items sort first, then oldest.
    private static func leastRecent(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): false
        case (nil, _): true
        case (_, nil): false
        case let (a?, b?): a < b
        }
    }
}

public enum WeeklyProgress {
    /// Distinct days with a completed session in the week containing `now` (weeks start Monday).
    public static func daysPracticed(sessionDates: [Date], now: Date = .now, calendar: Calendar = .practiceCalendar) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let days = sessionDates.filter { week.contains($0) }.map { calendar.startOfDay(for: $0) }
        return Set(days).count
    }
}

public extension Calendar {
    static var practiceCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        return cal
    }
}

public enum PracticeReview {
    /// Sessions after the most recent lesson. With no lesson logged yet, every session counts.
    public static func sinceLastLesson<S>(_ sessions: [S], date: (S) -> Date, lastLesson: Date?) -> [S] {
        guard let lastLesson else { return sessions }
        return sessions.filter { date($0) > lastLesson }
    }
}
