import Foundation

/// Board-derived state kept between syncs: the routines read from the board and the recent changes,
/// with how far the student has read. Small enough for UserDefaults; rebuilt on every sync.
enum BoardStore {
    private static let defaults = UserDefaults.standard
    private static let keepChanges = 50

    static var routines: [BoardMapping.Routine] {
        get { decode(Prefs.trelloRoutines) ?? [] }
        set { encode(newValue, Prefs.trelloRoutines) }
    }

    /// Newest first.
    static var changes: [BoardMapping.Change] {
        get { decode(Prefs.trelloChanges) ?? [] }
        set { encode(Array(newValue.prefix(keepChanges)), Prefs.trelloChanges) }
    }

    /// Changes newer than the last "Got it".
    static var unseen: [BoardMapping.Change] {
        let seen = defaults.double(forKey: Prefs.trelloChangesSeen)
        return changes.filter { $0.date.timeIntervalSince1970 > seen }
    }

    static func markSeen() {
        defaults.set(changes.first?.date.timeIntervalSince1970 ?? Date.now.timeIntervalSince1970, forKey: Prefs.trelloChangesSeen)
    }

    /// Adds changes, skipping ones already kept.
    static func add(_ new: [BoardMapping.Change]) {
        let known = Set(changes.map(\.id))
        changes = (new.filter { !known.contains($0.id) } + changes).sorted { $0.date > $1.date }
    }

    /// The routine to plan from: the one chosen on Today if it still exists, else the automatic pick.
    static func routine(choice: String, minutes: Int, in routines: [BoardMapping.Routine]) -> BoardMapping.Routine? {
        if !choice.isEmpty, let chosen = routines.first(where: { $0.id == choice }) { return chosen }
        return BoardMapping.autoRoutine(routines, minutes: minutes)
    }

    static func clear() {
        for key in [Prefs.trelloRoutines, Prefs.trelloChanges, Prefs.trelloChangesSeen, Prefs.trelloActivitySince,
                    Prefs.trelloMemberID, Prefs.routineChoice] {
            defaults.removeObject(forKey: key)
        }
    }

    private static func decode<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
