import Foundation

/// Pure parsing for Trello content: no networking, no SwiftData, so it is unit tested like the planner.
public enum TrelloMapping {
    public static let breathLadder = "Breath fire starter"

    // MARK: Warmups

    public struct WarmupShape: Equatable, Sendable {
        public var ladderGroup: String?
        public var ladderLevel: Int
    }

    /// Reads a ladder rung from a card name.
    /// "Precursor to breath fire starters" is rung 0; "Breath fire starter to 150" and "BFS to 200" are rungs 150 and 200.
    /// Breath fire starters without a number ("to F consonant") are standalone warmups.
    public static func warmupShape(forCardName name: String) -> WarmupShape {
        let n = name.lowercased()
        let isBreath = n.contains("breath fire") || n.range(of: #"\bbfs\b"#, options: .regularExpression) != nil
        guard isBreath else { return WarmupShape(ladderGroup: nil, ladderLevel: 0) }
        if n.contains("precursor") { return WarmupShape(ladderGroup: breathLadder, ladderLevel: 0) }
        if let r = n.range(of: #"\bto\s+\d{2,3}\b"#, options: .regularExpression),
           let level = Int(n[r].filter(\.isNumber)) {
            return WarmupShape(ladderGroup: breathLadder, ladderLevel: level)
        }
        return WarmupShape(ladderGroup: nil, ladderLevel: 0)
    }

    /// Lowercased letters and digits only, single spaces. Used to match seeded or hand-added warmups to cards.
    public static func normalize(_ s: String) -> String {
        let kept = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    public static func isAudio(name: String, mimeType: String?) -> Bool {
        if let m = mimeType?.lowercased(), m.hasPrefix("audio/") { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["m4a", "mp3", "wav", "aac", "aif", "aiff", "caf"].contains(ext)
    }

    // MARK: Lessons

    public struct LessonEntry: Equatable, Sendable {
        public var number: Int
        public var date: Date
        public var isGifted: Bool
    }

    public struct LessonPackage: Equatable, Sendable {
        public var packageSize: Int?
        public var lessons: [LessonEntry]
    }

    /// Parses a lesson package card description, for example:
    ///
    ///     30 Classes + ~~1 Gifted Lesson <~~ used to cover 9/11 same day cancel
    ///     1. 8/19
    ///     2. 8/26
    ///     5.
    ///
    /// Numbered lines with a date are lessons; a line mentioning "gifted" with a date is a gifted lesson.
    /// Dates without a year take the most recent year that does not put them after `reference`.
    public static func lessonPackage(from text: String, reference: Date, calendar: Calendar = .current) -> LessonPackage {
        var size: Int?
        if let r = text.range(of: #"\d+\s+(classes|lessons)"#, options: [.regularExpression, .caseInsensitive]) {
            size = Int(text[r].prefix { $0.isNumber })
        }
        var entries: [LessonEntry] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if line.lowercased().contains("gifted") {
                if let date = firstDate(in: line, reference: reference, calendar: calendar) {
                    entries.append(LessonEntry(number: 0, date: date, isGifted: true))
                }
                continue
            }
            guard line.range(of: #"^\s*\d+\.\s+\d{1,2}/\d{1,2}"#, options: .regularExpression) != nil else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let digits = trimmed.prefix(while: { $0.isNumber })
            let rest = trimmed.dropFirst(digits.count + 1)   // skip the number and its "."
            guard let number = Int(digits),
                  let date = firstDate(in: String(rest), reference: reference, calendar: calendar)
            else { continue }
            entries.append(LessonEntry(number: number, date: date, isGifted: false))
        }
        return LessonPackage(packageSize: size, lessons: entries)
    }

    /// A card looks like a lesson package if it is named that way or its description lists dated lessons.
    public static func looksLikePackage(name: String, description: String) -> Bool {
        if name.lowercased().contains("package") { return true }
        return !lessonPackage(from: description, reference: .now).lessons.filter { !$0.isGifted }.isEmpty
    }

    static func firstDate(in s: String, reference: Date, calendar: Calendar) -> Date? {
        guard let re = try? NSRegularExpression(pattern: #"(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?"#) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> Int? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : Int(ns.substring(with: r))
        }
        guard let month = group(1), let day = group(2), (1...12).contains(month), (1...31).contains(day) else { return nil }
        if let y = group(3) {
            return calendar.date(from: DateComponents(year: y < 100 ? 2000 + y : y, month: month, day: day))
        }
        let year = calendar.component(.year, from: reference)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        if date > reference {
            return calendar.date(from: DateComponents(year: year - 1, month: month, day: day))
        }
        return date
    }

    // MARK: Sign-in

    /// Reads the token from Trello's redirect, which carries it in the fragment: `#token=...`.
    /// A denied request comes back as `#token=&error=...`, which returns nil.
    public static func token(fromCallback url: URL) -> String? {
        guard let fragment = url.fragment, !fragment.isEmpty else { return nil }
        var components = URLComponents()
        components.query = fragment
        guard let token = components.queryItems?.first(where: { $0.name == "token" })?.value else { return nil }
        return cleanToken(token)
    }

    /// Accepts a pasted token if it looks like one (long and alphanumeric), trimming stray whitespace.
    public static func cleanToken(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 32, t.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return t
    }
}
