import Foundation

/// Pure reading of a whole lesson board: which cards are warmups, which cards define a routine,
/// how a routine's lines resolve to warmup cards, and what changed on the board. No networking or SwiftData.
public enum BoardMapping {
    public struct CardInfo: Equatable, Sendable {
        public var id: String
        public var name: String
        public var desc: String
        public var listID: String
        public var listName: String
        public var hasAudio: Bool

        public init(id: String, name: String, desc: String = "", listID: String, listName: String, hasAudio: Bool = false) {
            self.id = id; self.name = name; self.desc = desc
            self.listID = listID; self.listName = listName; self.hasAudio = hasAudio
        }
    }

    public enum Kind: Equatable, Sendable {
        /// Something to practice: it has a track or a link, or sits in a list of tracks.
        case warmup
        /// A card whose description numbers a routine ("1. BFS to 300 OR Snake").
        case routineSummary
        /// Everything else: the package card, studio policies.
        case other
    }

    /// Cards in board order (lists left to right, cards top to bottom).
    public static func classify(_ cards: [CardInfo], packageCardID: String?) -> [String: Kind] {
        let listsWithAudio = Set(cards.filter(\.hasAudio).map(\.listID))
        var kinds: [String: Kind] = [:]
        for card in cards {
            if card.id == packageCardID {
                kinds[card.id] = .other
            } else if !card.hasAudio && numberedItems(card.desc).count >= 3 && link(in: card.desc) == nil {
                kinds[card.id] = .routineSummary
            } else if card.hasAudio || link(in: card.desc) != nil || listsWithAudio.contains(card.listID) {
                kinds[card.id] = .warmup
            } else {
                kinds[card.id] = .other
            }
        }
        return kinds
    }

    /// Numbered lines of a description, without their numbers: "1. Super Mario" becomes "Super Mario".
    public static func numberedItems(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let r = line.range(of: #"^\s*\d+[.)]\s*"#, options: .regularExpression) else { return nil }
            let item = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
    }

    /// The first web link in a card description, like a YouTube video.
    public static func link(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.url.flatMap { ["http", "https"].contains($0.scheme) ? $0 : nil }
    }

    /// A description as practice notes: links removed, blank lines dropped.
    public static func notes(from desc: String) -> String {
        var text = desc
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                if let r = Range(match.range, in: text) { text.removeSubrange(r) }
            }
        }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: Routines

    /// A practice set from the board. Each slot is one item; a slot with two cards ("BFS to 300 OR Snake")
    /// alternates between them.
    public struct Routine: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// Card ids, one array per numbered line.
        public var slots: [[String]]
        /// Lines on the summary card that no card matched.
        public var missing: [String]
        /// True when a numbered summary card defines it; false for a plain list.
        public var fromSummary: Bool

        public init(id: String, name: String, slots: [[String]], missing: [String] = [], fromSummary: Bool) {
            self.id = id; self.name = name; self.slots = slots; self.missing = missing; self.fromSummary = fromSummary
        }
    }

    /// Cards that repeat a card earlier on the board (same name) point at that first card,
    /// so a copied card doesn't become a second warmup.
    public static func canonicalIDs(_ cards: [CardInfo], kinds: [String: Kind]) -> [String: String] {
        var firstByName: [String: String] = [:]
        var result: [String: String] = [:]
        for card in cards where kinds[card.id] == .warmup {
            let key = TrelloMapping.normalize(card.name)
            if let first = firstByName[key] { result[card.id] = first } else { firstByName[key] = card.id; result[card.id] = card.id }
        }
        return result
    }

    /// Routines from summary cards first (in board order), then any list of warmups that no summary
    /// already names, with its cards in order.
    public static func routines(_ cards: [CardInfo], kinds: [String: Kind]) -> [Routine] {
        let canonical = canonicalIDs(cards, kinds: kinds)
        let warmups = cards.filter { kinds[$0.id] == .warmup && canonical[$0.id] == $0.id }
        var result: [Routine] = []

        for summary in cards where kinds[summary.id] == .routineSummary {
            var used = Set<String>()
            var slots: [[String]] = []
            var missing: [String] = []
            for line in numberedItems(summary.desc) {
                var slot: [String] = []
                for phrase in alternatives(line) {
                    if let card = match(phrase, in: warmups, avoiding: used) {
                        slot.append(card.id)
                        used.insert(card.id)
                    }
                }
                if slot.isEmpty { missing.append(line) } else { slots.append(slot) }
            }
            if !slots.isEmpty {
                result.append(Routine(id: "summary:\(summary.id)", name: summary.name, slots: slots,
                                      missing: missing, fromSummary: true))
            }
        }

        let named = Set(result.map { TrelloMapping.normalize($0.name) })
        var listOrder: [String] = []
        var byList: [String: [CardInfo]] = [:]
        for card in cards where kinds[card.id] == .warmup {
            if byList[card.listID] == nil { listOrder.append(card.listID) }
            byList[card.listID, default: []].append(card)
        }
        for listID in listOrder {
            guard let listCards = byList[listID], let name = listCards.first?.listName,
                  !named.contains(TrelloMapping.normalize(name)) else { continue }
            var seen = Set<String>()
            let slots = listCards.compactMap { canonical[$0.id] }.filter { seen.insert($0).inserted }.map { [$0] }
            result.append(Routine(id: "list:\(listID)", name: name, slots: slots, fromSummary: false))
        }
        return result
    }

    /// "BFS to 300 OR Snake" is two choices.
    static func alternatives(_ line: String) -> [String] {
        line.replacingOccurrences(of: #"\s+or\s+"#, with: "\u{1F}", options: [.regularExpression, .caseInsensitive])
            .split(separator: "\u{1F}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static let filler: Set<String> = ["the", "a", "an", "and", "w", "with", "google", "doc", "medley", "mashup", "x"]

    private static func words(_ s: String) -> [String] {
        TrelloMapping.normalize(s).split(separator: " ").map(String.init).filter { !filler.contains($0) }
    }

    /// The warmup card a summary line means. Scores by how many of the line's words the card name has;
    /// an abbreviation on the card counts too ("PP" for "Pink panther"). Needs half the line's words.
    /// Ties go to the card with fewer extra words, then one not used yet in this routine, then board order.
    static func match(_ phrase: String, in cards: [CardInfo], avoiding used: Set<String>) -> CardInfo? {
        let want = words(phrase)
        guard !want.isEmpty else { return nil }
        let initials = String(want.compactMap(\.first))
        var best: (card: CardInfo, matched: Int, extra: Int, used: Bool)?
        for card in cards {
            let have = words(card.name)
            var matched = want.filter { have.contains($0) }.count
            if matched < want.count, want.count >= 2, have.contains(initials) { matched = want.count }
            guard matched * 2 >= want.count, matched > 0 else { continue }
            let extra = have.count - min(matched, have.count)
            let isUsed = used.contains(card.id)
            if let b = best {
                let better = matched > b.matched
                    || (matched == b.matched && (b.used && !isUsed))
                    || (matched == b.matched && b.used == isUsed && extra < b.extra)
                if !better { continue }
            }
            best = (card, matched, extra, isUsed)
        }
        return best?.card
    }

    /// With no choice made, longer sessions use the biggest numbered routine and shorter ones the smallest.
    /// Boards without numbered routines keep the old rotation (nil).
    public static func autoRoutine(_ routines: [Routine], minutes: Int) -> Routine? {
        let numbered = routines.filter(\.fromSummary)
        guard !numbered.isEmpty else { return nil }
        let bySize = numbered.enumerated().sorted { ($0.element.slots.count, $0.offset) < ($1.element.slots.count, $1.offset) }
        return (minutes >= 60 ? bySize.last : bySize.first)?.element
    }

    // MARK: What changed

    public struct Action: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case created, moved, renamed, notes, track, comment, archived, other }
        public var kind: Kind
        public var date: Date
        public var memberID: String
        public var memberName: String
        public var cardID: String?
        public var cardName: String?
        public var listName: String?
        public var text: String?

        public init(kind: Kind, date: Date, memberID: String, memberName: String, cardID: String? = nil,
                    cardName: String? = nil, listName: String? = nil, text: String? = nil) {
            self.kind = kind; self.date = date; self.memberID = memberID; self.memberName = memberName
            self.cardID = cardID; self.cardName = cardName; self.listName = listName; self.text = text
        }
    }

    public struct Change: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var date: Date
        public var who: String
        public var text: String
        public var cardID: String?
    }

    /// One plain line per card, newest first: "Added Llama Mama 2 with a track", "Moved BFS to 300 to Thrive with Five".
    /// Comments are their own lines. Your own edits are left out.
    public static func changes(from actions: [Action], excludingMember me: String?) -> [Change] {
        let theirs = actions.filter { $0.memberID != me && $0.kind != .other }
        var result: [Change] = []
        var cardOrder: [String] = []
        var byCard: [String: [Action]] = [:]
        for action in theirs {
            if action.kind == .comment, let text = action.text, let card = action.cardName {
                let firstName = action.memberName.split(separator: " ").first.map(String.init) ?? action.memberName
                result.append(Change(id: "comment:\(action.cardID ?? card):\(action.date.timeIntervalSince1970)",
                                     date: action.date, who: firstName, text: "On \(card): \(text)", cardID: action.cardID))
                continue
            }
            guard let id = action.cardID else { continue }
            if byCard[id] == nil { cardOrder.append(id) }
            byCard[id, default: []].append(action)
        }
        for id in cardOrder {
            guard let group = byCard[id], let newest = group.max(by: { $0.date < $1.date }) else { continue }
            let kinds = Set(group.map(\.kind))
            let name = newest.cardName ?? group.compactMap(\.cardName).last ?? "a card"
            let list = group.sorted { $0.date < $1.date }.compactMap(\.listName).last
            let text: String
            if kinds.contains(.archived) {
                text = "Archived \(name)"
            } else if kinds.contains(.created) {
                text = "Added \(name)" + (list.map { " to \($0)" } ?? "") + (kinds.contains(.track) ? " with a track" : "")
            } else if kinds.contains(.moved), let list {
                text = "Moved \(name) to \(list)"
            } else if kinds.contains(.track) {
                text = "New track for \(name)"
            } else if kinds.contains(.notes) {
                text = "Updated the notes on \(name)"
            } else if kinds.contains(.renamed) {
                text = "Renamed a card to \(name)"
            } else {
                continue
            }
            let firstName = newest.memberName.split(separator: " ").first.map(String.init) ?? newest.memberName
            result.append(Change(id: "card:\(id):\(newest.date.timeIntervalSince1970)", date: newest.date,
                                 who: firstName, text: text, cardID: id))
        }
        return result.sorted { $0.date > $1.date }
    }
}
