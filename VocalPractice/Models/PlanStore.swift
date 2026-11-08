import CoreTransferable
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// An exported plan file for ShareLink.
struct PlanExport: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let url = FileManager.default.temporaryDirectory.appending(path: export.fileName)
            try export.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

struct PlanError: LocalizedError {
    let messages: [String]
    var errorDescription: String? { messages.joined(separator: "\n") }
}

/// The only place that writes plan data to songs. Every plan is validated before anything is
/// written, so a bad file never half-applies.
@MainActor
enum PlanStore {
    /// Applies `plan` to `song`. Section ratings carry over by section id; checkpoint done states
    /// carry over by title. Sections no longer in the plan are removed, but their takes stay.
    static func apply(_ plan: SongPlan, to song: Song, in context: ModelContext, calendar: Calendar = .current) throws {
        let errors = PlanValidator.validate(plan)
        guard errors.isEmpty else { throw PlanError(messages: errors) }
        let json = String(decoding: try SongPlan.encode(plan), as: UTF8.self)

        song.planJSON = json
        song.goalType = plan.goal.type.rawValue
        song.goalLabel = plan.goal.label
        song.goalDate = plan.goal.date.date(in: calendar)
        song.goalDateIsApprox = plan.goal.dateIsApprox
        song.originalKey = plan.song.originalKey
        song.keyOptionsRaw = plan.song.keyOptions.joined(separator: ",")
        song.rangeLowMidi = plan.song.range?.low.flatMap(NoteName.midi)
        song.rangeHighMidi = plan.song.range?.high.flatMap(NoteName.midi)

        let keep = Set(plan.sections.map(\.id))
        let removed = song.sections.filter { !keep.contains($0.sectionID) }
        song.sections.removeAll { !keep.contains($0.sectionID) }
        removed.forEach(context.delete)
        for (order, planned) in plan.sections.enumerated() {
            if let existing = song.sections.first(where: { $0.sectionID == planned.id }) {
                existing.title = planned.title
                existing.focus = planned.focus
                existing.difficulty = planned.difficulty.rawValue
                existing.order = order
            } else {
                let section = SongSection(sectionID: planned.id, title: planned.title,
                                          difficulty: planned.difficulty.rawValue, focus: planned.focus, order: order)
                context.insert(section)
                section.song = song
            }
        }

        let doneTitles = Set(song.checkpoints.filter(\.done).map(\.title))
        let oldCheckpoints = song.checkpoints
        song.checkpoints.removeAll()
        oldCheckpoints.forEach(context.delete)
        for planned in plan.checkpoints {
            let checkpoint = Checkpoint(title: planned.title, due: planned.due.date(in: calendar),
                                        done: planned.done || doneTitles.contains(planned.title))
            context.insert(checkpoint)
            checkpoint.song = song
        }

        if song.key.isEmpty { song.key = plan.song.keyOptions.first ?? plan.song.originalKey }
        if plan.goal.type == .showcase { song.showcase = true }
        try? context.save()
    }

    nonisolated static func currentPlan(for song: Song) -> SongPlan? {
        guard let json = song.planJSON else { return nil }
        return try? SongPlan.decode(Data(json.utf8))
    }

    /// The stored plan with the app's checkpoint done states and section edits written back in.
    static func exportPlan(for song: Song) -> SongPlan? {
        guard var plan = currentPlan(for: song) else { return nil }
        let done = Dictionary(song.checkpoints.map { ($0.title, $0.done) }, uniquingKeysWith: { a, b in a || b })
        for i in plan.checkpoints.indices {
            if let isDone = done[plan.checkpoints[i].title] { plan.checkpoints[i].done = isDone }
        }
        let sections = Dictionary(song.sections.map { ($0.sectionID, $0) }, uniquingKeysWith: { a, _ in a })
        for i in plan.sections.indices {
            guard let model = sections[plan.sections[i].id] else { continue }
            plan.sections[i].title = model.title
            plan.sections[i].focus = model.focus
            plan.sections[i].difficulty = Difficulty(rawValue: model.difficulty) ?? plan.sections[i].difficulty
        }
        return plan
    }

    /// The export as `<title-kebab>.plan.json`, ready for the share sheet.
    static func export(for song: Song) -> PlanExport? {
        guard let plan = exportPlan(for: song), let data = try? SongPlan.encode(plan) else { return nil }
        let name = PlanFormat.kebab(plan.song.title)
        return PlanExport(data: data, fileName: "\(name.isEmpty ? "song" : name).plan.json")
    }

    /// Clears the plan, its sections, and checkpoints. The song and its takes stay.
    static func removePlan(from song: Song, in context: ModelContext) {
        song.planJSON = nil
        song.goalType = nil
        song.goalLabel = nil
        song.goalDate = nil
        song.goalDateIsApprox = false
        song.originalKey = nil
        song.keyOptionsRaw = ""
        song.rangeLowMidi = nil
        song.rangeHighMidi = nil
        let sections = song.sections, checkpoints = song.checkpoints
        song.sections.removeAll()
        song.checkpoints.removeAll()
        sections.forEach(context.delete)
        checkpoints.forEach(context.delete)
        try? context.save()
    }

    /// Imports a plan file, attaching it to the song with the same title and artist or creating one.
    @discardableResult
    static func importPlan(_ data: Data, in context: ModelContext) throws -> Song {
        let (plan, errors) = PlanValidator.check(data)
        guard let plan else { throw PlanError(messages: errors) }
        let songs = (try? context.fetch(FetchDescriptor<Song>())) ?? []
        let title = TrelloMapping.normalize(plan.song.title), artist = TrelloMapping.normalize(plan.song.artist)
        let song: Song
        if let match = songs.first(where: { TrelloMapping.normalize($0.title) == title && TrelloMapping.normalize($0.artist) == artist }) {
            song = match
        } else {
            song = Song(title: plan.song.title, artist: plan.song.artist, myOpsPath: plan.myOpsPath ?? "")
            song.minutes = plan.song.minutesPerPass
            context.insert(song)
        }
        try apply(plan, to: song, in: context)
        return song
    }

    /// Reads a file picked in Files, which needs security-scoped access.
    nonisolated static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}

extension Song {
    /// The planner's view of this song on `date`, with its plan phase when one is active.
    func snapshot(on date: Date, fullRunsThisWeek: Int, calendar: Calendar = .current) -> SongSnapshot {
        var result = snapshot
        result.goalDate = goalDate
        guard let plan = PlanStore.currentPlan(for: self),
              let phase = PhaseResolver.current(plan: plan, on: date, calendar: calendar) else { return result }
        let byID = Dictionary(sections.map { ($0.sectionID, $0) }, uniquingKeysWith: { a, _ in a })
        let focus = phase.focusSections.compactMap { byID[$0]?.snapshot }.sorted { $0.order < $1.order }
        result.planContext = SongPlanContext(block: phase.songBlock, minutesPerPass: plan.song.minutesPerPass,
                                             focusSections: focus, fullRunsThisWeek: fullRunsThisWeek)
        return result
    }
}
