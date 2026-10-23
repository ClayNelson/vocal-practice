import Foundation

/// A song's dated plan toward a goal, matching docs/SONG_PLAN.md field for field.
/// Foundation only, so the format, validator, and planners are unit testable.
struct SongPlan: Codable, Equatable {
    var schemaVersion = 1
    var song: PlanSong
    var goal: PlanGoal
    var sections: [PlanSection] = []
    var phases: [PlanPhase] = []
    var checkpoints: [PlanCheckpoint] = []
    var questionsForTeacher: [String] = []
    var myOpsPath: String?
    var generatedBy: String?
    var generatedAt: String?
    var assessment: PlanAssessment?
    /// Why maintenance phases exist (holidays, travel).
    var blockedRanges: [PlanBlockedRange]?

    static func decode(_ data: Data) throws -> SongPlan {
        try JSONDecoder().decode(SongPlan.self, from: data)
    }

    /// Sorted keys and pretty printing, so exports diff cleanly in MyOps.
    static func encode(_ plan: SongPlan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(plan)
    }
}

struct PlanSong: Codable, Equatable {
    var title: String
    var artist: String = ""
    var reference: String?
    var originalKey: String = ""
    /// Keys under consideration; the first is the current pick.
    var keyOptions: [String] = []
    var range: PlanRange?
    var tempoBPM: Int?
    var minutesPerPass: Int = 6
}

struct PlanRange: Codable, Equatable {
    var low: String?
    var high: String?
}

struct PlanGoal: Codable, Equatable {
    var type: GoalType
    var label: String
    var date: PlanDate
    var dateIsApprox = false
}

struct PlanSection: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var difficulty: Difficulty
    var focus: String = ""
}

struct PlanPhase: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var start: PlanDate
    var end: PlanDate
    var songBlock: SongBlock
    var focusSections: [String] = []
    var notes: String?

    var days: Int { start.daysUntil(end) + 1 }
}

struct PlanCheckpoint: Codable, Equatable {
    var title: String
    var due: PlanDate
    var done = false
}

struct PlanAssessment: Codable, Equatable {
    /// The honest read, one paragraph.
    var summary: String?
    var keyRecommendation: String?
    var sources: [PlanSource]?
}

struct PlanSource: Codable, Equatable {
    var title: String
    var url: String
}

struct PlanBlockedRange: Codable, Equatable {
    var start: PlanDate
    var end: PlanDate
    var label: String
}

// MARK: Enums

/// What the song item is in a session during a phase.
public enum SongBlock: String, CaseIterable, Codable, Sendable {
    case listen, sections, fullRun, maintenance, taper

    public init(from decoder: Decoder) throws { self = try decodePlanEnum(decoder) }
}

enum GoalType: String, CaseIterable, Codable {
    case showcase, recording, lesson, none

    init(from decoder: Decoder) throws { self = try decodePlanEnum(decoder) }

    var label: String {
        switch self {
        case .showcase: "Showcase"
        case .recording: "Recording"
        case .lesson: "Lesson"
        case .none: "None"
        }
    }
}

enum Difficulty: String, CaseIterable, Codable {
    case high, medium, low

    init(from decoder: Decoder) throws { self = try decodePlanEnum(decoder) }

    /// High first when sorting.
    var rank: Int {
        switch self { case .high: 0; case .medium: 1; case .low: 2 }
    }
}

/// How a section take felt, recorded after each section take.
enum SectionRating: String, CaseIterable {
    case free, pressed, cracked
    var label: String { rawValue.capitalized }
}

/// Decodes a String enum with an error that lists the allowed values.
private func decodePlanEnum<E: RawRepresentable & CaseIterable>(_ decoder: Decoder) throws -> E where E.RawValue == String {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self)
    guard let value = E(rawValue: raw) else {
        let allowed = E.allCases.map(\.rawValue).joined(separator: ", ")
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "'\(raw)' must be one of \(allowed)")
    }
    return value
}

// MARK: Lenient decoding
// Optional-in-practice fields default instead of failing, so the validator can name what's missing.

extension SongPlan {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        song = try c.decode(PlanSong.self, forKey: .song)
        goal = try c.decode(PlanGoal.self, forKey: .goal)
        sections = try c.decodeIfPresent([PlanSection].self, forKey: .sections) ?? []
        phases = try c.decodeIfPresent([PlanPhase].self, forKey: .phases) ?? []
        checkpoints = try c.decodeIfPresent([PlanCheckpoint].self, forKey: .checkpoints) ?? []
        questionsForTeacher = try c.decodeIfPresent([String].self, forKey: .questionsForTeacher) ?? []
        myOpsPath = try c.decodeIfPresent(String.self, forKey: .myOpsPath)
        generatedBy = try c.decodeIfPresent(String.self, forKey: .generatedBy)
        generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt)
        assessment = try c.decodeIfPresent(PlanAssessment.self, forKey: .assessment)
        blockedRanges = try c.decodeIfPresent([PlanBlockedRange].self, forKey: .blockedRanges)
    }
}

extension PlanSong {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        reference = try c.decodeIfPresent(String.self, forKey: .reference)
        originalKey = try c.decodeIfPresent(String.self, forKey: .originalKey) ?? ""
        keyOptions = try c.decodeIfPresent([String].self, forKey: .keyOptions) ?? []
        range = try c.decodeIfPresent(PlanRange.self, forKey: .range)
        tempoBPM = try c.decodeIfPresent(Int.self, forKey: .tempoBPM)
        minutesPerPass = try c.decodeIfPresent(Int.self, forKey: .minutesPerPass) ?? 0
    }
}

extension PlanGoal {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(GoalType.self, forKey: .type)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        date = try c.decode(PlanDate.self, forKey: .date)
        dateIsApprox = try c.decodeIfPresent(Bool.self, forKey: .dateIsApprox) ?? false
    }
}

extension PlanSection {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        difficulty = try c.decode(Difficulty.self, forKey: .difficulty)
        focus = try c.decodeIfPresent(String.self, forKey: .focus) ?? ""
    }
}

extension PlanPhase {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decode(PlanDate.self, forKey: .start)
        end = try c.decode(PlanDate.self, forKey: .end)
        songBlock = try c.decode(SongBlock.self, forKey: .songBlock)
        focusSections = try c.decodeIfPresent([String].self, forKey: .focusSections) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }
}

extension PlanCheckpoint {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        due = try c.decode(PlanDate.self, forKey: .due)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}

// MARK: PlanDate

/// A calendar day with no time or time zone. Plans compare and count days with this, never with
/// `Date` in UTC, so phase boundaries can't drift by a day across time zones or DST changes.
struct PlanDate: Hashable, Comparable, Codable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    /// Parses "YYYY-MM-DD"; nil for anything else, including days that don't exist.
    init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let candidate = PlanDate(year: y, month: m, day: d)
        guard (1...12).contains(m), (1...31).contains(d), candidate.adding(days: 0) == candidate else { return nil }
        self = candidate
    }

    /// The calendar day `date` falls on in `calendar` (its time zone decides).
    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    static func today(calendar: Calendar = .current) -> PlanDate { PlanDate(.now, calendar: calendar) }

    /// Start of this day in `calendar`.
    func date(in calendar: Calendar) -> Date {
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return calendar.startOfDay(for: noon)
    }

    func adding(days n: Int) -> PlanDate {
        PlanDate(Self.utc.date(byAdding: .day, value: n, to: utcNoon)!, calendar: Self.utc)
    }

    /// Whole days from this day to `other`; negative when `other` is earlier.
    func daysUntil(_ other: PlanDate) -> Int {
        Self.utc.dateComponents([.day], from: utcNoon, to: other.utcNoon).day!
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (a: PlanDate, b: PlanDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // Day arithmetic happens in UTC at noon, where every day is exactly 24 hours.
    private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private var utcNoon: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = PlanDate(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "'\(raw)' is not a date like 2027-01-25")
        }
        self = date
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
