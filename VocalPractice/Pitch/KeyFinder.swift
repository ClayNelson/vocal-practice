import Foundation

/// Finds the key you're singing in: a tally of held notes by pitch class, weighted by how long
/// each is held, scored against the Krumhansl-Kessler key profiles. Foundation only, unit tested.
struct KeyFinder {
    struct Candidate: Equatable {
        /// Pitch class of the tonic, 0 is C.
        var tonic: Int
        var isMinor: Bool
        /// Correlation with the key's profile, -1 to 1.
        var score: Double

        /// "A major", "F♯ minor".
        var name: String { KeyFinder.name(tonic: tonic, isMinor: isMinor) }
        /// How plans write keys: "A", "Ab", "F#m".
        var planKey: String { NoteName.keyName(pitchClass: tonic, suffix: isMinor ? "m" : "") }
        /// The major or minor key with the same notes (A major and F♯ minor).
        var relative: (tonic: Int, isMinor: Bool) { isMinor ? ((tonic + 3) % 12, false) : ((tonic + 9) % 12, true) }
    }

    enum Verdict: Equatable {
        /// Not enough held notes yet.
        case listening
        /// A best guess that could still change.
        case leaning(Candidate)
        /// A clear winner after enough singing.
        case settled(Candidate)
        /// A key and its relative are too close to call from the melody alone.
        case relatives(Candidate, Candidate)
    }

    /// Seconds a note must be held before it counts, so scoops and passing notes don't.
    var minHold = 0.15
    /// Seconds of held notes before a guess is shown, and before it can settle.
    var guessAfter = 6.0
    var settleAfter = 15.0

    private(set) var weights = [Double](repeating: 0, count: 12)
    private var note: Int?
    private var heldSince: Double?
    private var lastTime: Double?

    init(minHold: Double = 0.15, guessAfter: Double = 6, settleAfter: Double = 15) {
        self.minHold = minHold; self.guessAfter = guessAfter; self.settleAfter = settleAfter
    }

    /// Seconds of held singing counted so far.
    var seconds: Double { weights.reduce(0, +) }

    mutating func update(midi: Double?, time: Double) {
        guard let midi else { note = nil; heldSince = nil; lastTime = nil; return }
        let n = Int(midi.rounded())
        guard n == note, let start = heldSince, let last = lastTime else {
            note = n; heldSince = time; lastTime = time
            return
        }
        let pc = ((n % 12) + 12) % 12
        if time - start >= minHold {
            // The moment a note qualifies, it counts from its start.
            weights[pc] += last - start < minHold ? time - start : time - last
        }
        lastTime = time
    }

    mutating func reset() { self = KeyFinder(minHold: minHold, guessAfter: guessAfter, settleAfter: settleAfter) }

    /// All 24 keys, best first.
    var candidates: [Candidate] {
        guard seconds > 0 else { return [] }
        var result: [Candidate] = []
        for tonic in 0..<12 {
            for isMinor in [false, true] {
                let profile = isMinor ? Self.minorProfile : Self.majorProfile
                let rotated = (0..<12).map { profile[(($0 - tonic) % 12 + 12) % 12] }
                result.append(Candidate(tonic: tonic, isMinor: isMinor, score: Self.correlation(weights, rotated)))
            }
        }
        return result.sorted { $0.score > $1.score }
    }

    var verdict: Verdict {
        let ranked = candidates
        guard seconds >= guessAfter, let best = ranked.first, ranked.count > 1 else { return .listening }
        let relative = best.relative
        if let rel = ranked.first(where: { $0.tonic == relative.tonic && $0.isMinor == relative.isMinor }),
           best.score - rel.score < 0.05 {
            return .relatives(best, rel)
        }
        // The runner-up that isn't the relative key decides how clear the winner is.
        let rival = ranked.dropFirst().first { !($0.tonic == relative.tonic && $0.isMinor == relative.isMinor) }
        let gap = best.score - (rival?.score ?? -1)
        return seconds >= settleAfter && gap >= 0.08 ? .settled(best) : .leaning(best)
    }

    /// Pitch classes of a key's scale (natural minor for minor keys).
    static func scale(tonic: Int, isMinor: Bool) -> Set<Int> {
        let steps = isMinor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
        return Set(steps.map { (tonic + $0) % 12 })
    }

    static func name(tonic: Int, isMinor: Bool) -> String {
        let names = isMinor ? minorNames : majorNames
        return "\(names[((tonic % 12) + 12) % 12]) \(isMinor ? "minor" : "major")"
    }

    /// Note names as a key would spell them.
    static let majorNames = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    static let minorNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "G♯", "A", "B♭", "B"]

    // Krumhansl and Kessler (1982), from listener ratings of how well each note fits a key.
    static let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<12 {
            num += (a[i] - ma) * (b[i] - mb)
            da += (a[i] - ma) * (a[i] - ma)
            db += (b[i] - mb) * (b[i] - mb)
        }
        return da == 0 || db == 0 ? 0 : num / (da * db).squareRoot()
    }
}

/// Which key options suit your voice: shifts the song's range into each key and compares it
/// with the range you held. Foundation only, unit tested.
enum KeyFit {
    struct Option: Equatable {
        var key: String
        /// Semitones from the original key, -6 to +5.
        var shift: Int
        var low: Int
        var high: Int
        /// Semitones above your highest held note (0 if it fits).
        var overHigh: Int
        /// Semitones below your lowest held note (0 if it fits).
        var underLow: Int

        var fits: Bool { overHigh == 0 && underLow == 0 }

        /// "Top note F♯4 is 1 semitone above your high." or "Fits: E3 to F♯4, 2 semitones of room up top."
        func summary(userHigh: Int) -> String {
            let top = Note.label(midi: high), bottom = Note.label(midi: low)
            if overHigh > 0 { return "Top note \(top) is \(semitones(overHigh)) above your high." }
            if underLow > 0 { return "Low note \(bottom) is \(semitones(underLow)) below your low." }
            let room = userHigh - high
            return room == 0 ? "Fits: \(bottom) to \(top), right at your high." : "Fits: \(bottom) to \(top), \(semitones(room)) of room up top."
        }

        private func semitones(_ n: Int) -> String { n == 1 ? "1 semitone" : "\(n) semitones" }
    }

    /// One option per key, in the order given. Keys that don't parse are skipped.
    static func options(originalKey: String, keys: [String], songLow: Int, songHigh: Int,
                        userLow: Int?, userHigh: Int) -> [Option] {
        guard let original = NoteName.key(originalKey) else { return [] }
        var seen = Set<String>()
        return keys.compactMap { key in
            guard seen.insert(key).inserted, let target = NoteName.key(key) else { return nil }
            var shift = ((target.pitchClass - original.pitchClass) % 12 + 12) % 12
            if shift > 5 { shift -= 12 }
            let low = songLow + shift, high = songHigh + shift
            return Option(key: key, shift: shift, low: low, high: high,
                          overHigh: max(0, high - userHigh), underLow: max(0, (userLow ?? low) - low))
        }
    }
}
