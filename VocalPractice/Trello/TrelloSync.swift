import AVFoundation
import Foundation
import SwiftData

/// Pull-only sync from the student's lesson board. Never writes to Trello.
///
/// - Warmups list: one warmup per card, matched by card ID (or, the first time, by title to adopt
///   warmups that were seeded or added by hand). Titles and ladder rungs follow the card; solid flags,
///   practice history, and takes are never touched. The card's audio attachment is downloaded when new or changed.
/// - Package card: dated lessons and the package size.
/// - Nothing is deleted. Warmups whose cards are archived stay until the student removes them.
@MainActor
enum TrelloSync {
    struct Report {
        var added = 0
        var updated = 0
        var tracks = 0
        var lessons = 0

        var summary: String {
            let parts = [
                added > 0 ? "\(added) new warmup\(added == 1 ? "" : "s")" : nil,
                updated > 0 ? "\(updated) updated" : nil,
                tracks > 0 ? "\(tracks) track\(tracks == 1 ? "" : "s") downloaded" : nil,
                lessons > 0 ? "\(lessons) lesson\(lessons == 1 ? "" : "s") added" : nil,
            ].compactMap { $0 }
            return parts.isEmpty ? "Up to date" : parts.joined(separator: ", ")
        }
    }

    nonisolated static var isConnected: Bool {
        TrelloConfig.isConfigured && Keychain.get(TrelloConfig.tokenAccount) != nil
    }

    /// Runs a sync if connected and the last one is older than `interval`. Errors are swallowed; used on launch.
    static func syncIfStale(context: ModelContext, interval: TimeInterval = 6 * 3600) async {
        let last = UserDefaults.standard.double(forKey: Prefs.trelloLastSync)
        guard isConnected, Date.now.timeIntervalSince1970 - last > interval else { return }
        _ = try? await run(context: context)
    }

    @discardableResult
    static func run(context: ModelContext) async throws -> Report {
        guard TrelloConfig.isConfigured else { throw TrelloError.notConfigured }
        guard let client = TrelloClient.current() else { throw TrelloError.notConnected }
        let defaults = UserDefaults.standard
        guard let listID = defaults.string(forKey: Prefs.trelloListID), !listID.isEmpty else { throw TrelloError.notSetUp }
        let boardName = defaults.string(forKey: Prefs.trelloBoardName) ?? "lesson board"

        var report = Report()
        let cards = try await client.cards(list: listID)
        var existing = try context.fetch(FetchDescriptor<Warmup>())

        for card in cards {
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

            if let attachment = card.audioAttachment,
               attachment.id != warmup.trelloAttachmentID || !hasTrack(warmup) {
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
            }
        }

        if let cardID = defaults.string(forKey: Prefs.trelloPackageCardID), !cardID.isEmpty {
            let card = try await client.card(cardID)
            let package = TrelloMapping.lessonPackage(from: card.desc ?? "", reference: .now)
            if let size = package.packageSize { defaults.set(size, forKey: Prefs.packageSize) }
            let lessons = try context.fetch(FetchDescriptor<Lesson>())
            let calendar = Calendar.current
            for entry in package.lessons {
                let known = lessons.contains {
                    calendar.isDate($0.date, inSameDayAs: entry.date)
                        || (!entry.isGifted && !$0.isGifted && $0.number == entry.number)
                }
                guard !known else { continue }
                context.insert(Lesson(date: entry.date, number: entry.number,
                                      notes: entry.isGifted ? "Gifted lesson (from Trello)" : "",
                                      isGifted: entry.isGifted))
                report.lessons += 1
            }
        }

        try context.save()
        defaults.set(Date.now.timeIntervalSince1970, forKey: Prefs.trelloLastSync)
        return report
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
