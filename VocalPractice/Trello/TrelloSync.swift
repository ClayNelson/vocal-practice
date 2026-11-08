import AVFoundation
import Foundation
import SwiftData

/// Pull-only sync from the student's lesson board. Never writes to Trello.
///
/// - Every list is read. Cards with a track or a link (or in a list of tracks) are warmups, matched by card ID
///   (or, the first time, by title to adopt warmups that were seeded or added by hand). Titles, ladder rungs,
///   and notes follow the card; solid flags, practice history, and takes are never touched. A card copied into
///   a second list stays one warmup. The card's audio attachment is downloaded when new or changed.
/// - Numbered summary cards ("Thrive with Five: 1. BFS to 300 OR Snake ...") become routines, and so does each
///   list of warmups that no summary names.
/// - The board's history since the last sync becomes plain change lines for "New from your teacher".
/// - Package card: dated lessons, cancels, and the package size.
/// - Nothing is deleted. Warmups whose cards are archived stay until the student removes them.
@MainActor
enum TrelloSync {
    struct Report {
        var added = 0
        var updated = 0
        var tracks = 0
        var lessons = 0
        var failedTracks = 0
        var newChanges: [BoardMapping.Change] = []

        var summary: String {
            let parts = [
                added > 0 ? "\(added) new warmup\(added == 1 ? "" : "s")" : nil,
                updated > 0 ? "\(updated) updated" : nil,
                tracks > 0 ? "\(tracks) track\(tracks == 1 ? "" : "s") downloaded" : nil,
                lessons > 0 ? "\(lessons) lesson\(lessons == 1 ? "" : "s") added" : nil,
                failedTracks > 0 ? "\(failedTracks) track\(failedTracks == 1 ? "" : "s") failed, will retry" : nil,
            ].compactMap { $0 }
            return parts.isEmpty ? "Up to date" : parts.joined(separator: ", ")
        }
    }

    nonisolated static var isConnected: Bool {
        TrelloConfig.isConfigured && Keychain.get(TrelloConfig.tokenAccount) != nil
    }

    /// Runs a sync if connected and the last one is older than `interval`. Errors are swallowed; used on launch.
    static func syncIfStale(context: ModelContext, interval: TimeInterval = 3600) async {
        let last = UserDefaults.standard.double(forKey: Prefs.trelloLastSync)
        guard isConnected, Date.now.timeIntervalSince1970 - last > interval else { return }
        _ = try? await run(context: context)
    }

    /// Prevents a launch sync and a manual sync from overlapping and adding the same card twice.
    private static var isRunning = false

    @discardableResult
    static func run(context: ModelContext) async throws -> Report {
        guard !isRunning else { return Report() }
        isRunning = true
        defer { isRunning = false }
        guard TrelloConfig.isConfigured else { throw TrelloError.notConfigured }
        guard let client = TrelloClient.current() else { throw TrelloError.notConnected }
        let defaults = UserDefaults.standard
        guard let boardID = defaults.string(forKey: Prefs.trelloBoardID), !boardID.isEmpty else { throw TrelloError.notSetUp }
        let boardName = defaults.string(forKey: Prefs.trelloBoardName) ?? "lesson board"
        let packageID = defaults.string(forKey: Prefs.trelloPackageCardID)

        var report = Report()
        async let fetchedLists = client.lists(board: boardID)
        async let fetchedCards = client.cardsWithAttachments(board: boardID)
        let lists = try await fetchedLists
        let listIndex = Dictionary(lists.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let listNames = Dictionary(lists.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        // Board order: lists left to right, then cards top to bottom. Cards in archived lists are left out.
        let cards = try await fetchedCards
            .filter { listIndex[$0.idList ?? ""] != nil }
            .sorted { (listIndex[$0.idList ?? ""] ?? 0, $0.pos ?? 0) < (listIndex[$1.idList ?? ""] ?? 0, $1.pos ?? 0) }
        let infos = cards.map {
            BoardMapping.CardInfo(id: $0.id, name: $0.name, desc: $0.desc ?? "", listID: $0.idList ?? "",
                                  listName: listNames[$0.idList ?? ""] ?? "", hasAudio: $0.audioAttachment != nil)
        }
        let kinds = BoardMapping.classify(infos, packageCardID: packageID)
        let canonical = BoardMapping.canonicalIDs(infos, kinds: kinds)
        var existing = try context.fetch(FetchDescriptor<Warmup>())

        for card in cards where kinds[card.id] == .warmup && canonical[card.id] == card.id {
            let shape = TrelloMapping.warmupShape(forCardName: card.name)
            let warmup: Warmup
            if let match = existing.first(where: { $0.trelloCardID == card.id })
                ?? existing.first(where: { $0.trelloCardID == nil
                    && TrelloMapping.normalize($0.title) == TrelloMapping.normalize(card.name) }) {
                warmup = match
                if match.trelloCardID == nil || match.title != card.name
                    || match.ladderGroup != shape.ladderGroup || match.ladderLevel != shape.ladderLevel {
                    report.updated += 1
                }
                match.title = card.name
            } else {
                warmup = Warmup(title: card.name, minutes: 4, source: "Trello: \(boardName)")
                context.insert(warmup)
                existing.append(warmup)
                report.added += 1
            }
            warmup.trelloCardID = card.id
            warmup.ladderGroup = shape.ladderGroup
            warmup.ladderLevel = shape.ladderLevel
            warmup.boardNotes = BoardMapping.notes(from: card.desc ?? "")
            warmup.isHidden = false
            if let link = BoardMapping.link(in: card.desc ?? "") { warmup.linkURL = link.absoluteString }

            if let attachment = card.audioAttachment,
               attachment.id != warmup.trelloAttachmentID || !hasTrack(warmup) {
                do {
                    let name = try await client.download(attachment, into: AudioStorage.warmups)
                    if let old = warmup.audioFileName, old != name {
                        try? FileManager.default.removeItem(at: AudioStorage.warmups.appending(path: old))
                    }
                    warmup.audioFileName = name
                    warmup.trelloAttachmentID = attachment.id
                    if let minutes = practiceMinutes(for: AudioStorage.warmups.appending(path: name)) {
                        warmup.minutes = minutes
                    }
                    report.tracks += 1
                } catch TrelloError.unauthorized {
                    throw TrelloError.unauthorized
                } catch {
                    // One bad download shouldn't stop the rest; the next sync retries it.
                    report.failedTracks += 1
                }
            }
        }

        // A summary card synced as a warmup by an older version is hidden, not deleted.
        let summaryIDs = Set(infos.filter { kinds[$0.id] == .routineSummary }.map(\.id))
        for warmup in existing where warmup.trelloCardID.map(summaryIDs.contains) == true { warmup.isHidden = true }
        BoardStore.routines = BoardMapping.routines(infos, kinds: kinds)

        if let packageID, !packageID.isEmpty {
            let card = try await client.card(packageID)
            let package = TrelloMapping.lessonPackage(from: card.desc ?? "", reference: .now)
            if let size = package.packageSize { defaults.set(size, forKey: Prefs.packageSize) }
            let lessons = try context.fetch(FetchDescriptor<Lesson>())
            let calendar = Calendar.current
            for entry in package.lessons {
                // Match by day only: a new package restarts numbering at 1.
                if let known = lessons.first(where: { calendar.isDate($0.date, inSameDayAs: entry.date) }) {
                    if entry.isCanceled && !known.wasCanceled { known.wasCanceled = true }
                    continue
                }
                let lesson = Lesson(date: entry.date, number: entry.number,
                                    notes: entry.isGifted ? "Gifted lesson (from Trello)"
                                        : entry.isCanceled ? "Canceled (from Trello)" : "",
                                    isGifted: entry.isGifted)
                lesson.wasCanceled = entry.isCanceled
                context.insert(lesson)
                report.lessons += 1
            }
        }

        report.newChanges = try await fetchChanges(client: client, boardID: boardID)

        try context.save()
        defaults.set(Date.now.timeIntervalSince1970, forKey: Prefs.trelloLastSync)
        return report
    }

    /// The teacher's edits since the last look. The first sync on a board only sets the starting point,
    /// so a new install isn't flooded with the board's whole history.
    private static func fetchChanges(client: TrelloClient, boardID: String) async throws -> [BoardMapping.Change] {
        let defaults = UserDefaults.standard
        var since = defaults.double(forKey: Prefs.trelloActivitySince)
        if since == 0 { since = defaults.double(forKey: Prefs.trelloLastSync) }
        let now = Date.now
        guard since > 0 else {
            defaults.set(now.timeIntervalSince1970, forKey: Prefs.trelloActivitySince)
            return []
        }
        if defaults.string(forKey: Prefs.trelloMemberID) == nil {
            defaults.set(try await client.me().id, forKey: Prefs.trelloMemberID)
        }
        let actions = try await client.actions(board: boardID, since: Date(timeIntervalSince1970: since))
        let changes = BoardMapping.changes(from: actions.compactMap(\.mapped),
                                           excludingMember: defaults.string(forKey: Prefs.trelloMemberID))
        BoardStore.add(changes)
        defaults.set(now.timeIntervalSince1970, forKey: Prefs.trelloActivitySince)
        return changes
    }

    private static func hasTrack(_ warmup: Warmup) -> Bool {
        guard let name = warmup.audioFileName else { return false }
        return FileManager.default.fileExists(atPath: AudioStorage.warmups.appending(path: name).path())
    }

    /// Track length rounded up, plus a minute to reset between passes.
    private static func practiceMinutes(for url: URL) -> Int? {
        guard let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else { return nil }
        return max(2, Int((player.duration / 60).rounded(.up)) + 1)
    }
}
