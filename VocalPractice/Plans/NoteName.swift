import Foundation

/// Parses note and key names written in plans ("F#4", "F♯4", "Bb3", "E♭3", key "Ab").
/// Formatting goes through `Note.label(midi:)`, which uses ♯ and ♭.
enum NoteName {
    private static let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

    /// Key names for transposed suggestions, matching how plans write keys ("Ab", not "A♭").
    static let keyNames = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    /// MIDI number for a note in scientific pitch (C4 = 60, A4 = 69), or nil if it isn't one.
    static func midi(_ text: String) -> Int? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard let (offset, rest) = letterAndAccidental(s) else { return nil }
        let digits = rest.hasPrefix("-") ? rest.dropFirst() : Substring(rest)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let octave = Int(rest), (-1...9).contains(octave) else { return nil }
        return (octave + 1) * 12 + offset
    }

    /// A key like "A", "Ab", or "F#m" as a pitch class (0 is C) and whatever follows the root ("m").
    static func key(_ text: String) -> (pitchClass: Int, suffix: String)? {
        let s = text.trimmingCharacters(in: .whitespaces)
        guard let (offset, rest) = letterAndAccidental(s), !rest.contains(where: \.isNumber) else { return nil }
        return (((offset % 12) + 12) % 12, rest)
    }

    static func keyName(pitchClass: Int, suffix: String = "") -> String {
        keyNames[((pitchClass % 12) + 12) % 12] + suffix
    }

    /// Moves a key down by `semitones`, keeping its suffix. Nil if the key doesn't parse.
    static func key(_ text: String, down semitones: Int) -> String? {
        guard let (pc, suffix) = key(text) else { return nil }
        return keyName(pitchClass: pc - semitones, suffix: suffix)
    }

    static func label(midi: Int) -> String { Note.label(midi: midi) }

    /// Semitone offset of the letter plus accidental from C (Cb is -1, B# is 12), and the rest of the text.
    private static func letterAndAccidental(_ s: String) -> (Int, String)? {
        guard let first = s.first, let base = letters[Character(first.uppercased())] else { return nil }
        var rest = s.dropFirst()
        var offset = base
        if let accidental = rest.first {
            switch accidental {
            case "#", "♯": offset += 1; rest = rest.dropFirst()
            case "b", "♭": offset -= 1; rest = rest.dropFirst()
            default: break
            }
        }
        return (offset, String(rest))
    }
}
