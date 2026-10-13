import Accelerate
import Foundation

/// One pitch estimate from a block of audio.
struct PitchReading: Equatable {
    /// Fundamental frequency in Hz.
    var frequency: Double
    /// 0 to 1. How periodic the block was; above ~0.85 is a clean sung note.
    var clarity: Double
    /// Loudness of the block (RMS, 0 to 1).
    var level: Double

    var note: Note { Note(frequency: frequency) }
}

/// A musical note with its distance from the nearest equal-tempered pitch (A4 = 440 Hz).
struct Note: Equatable {
    static let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    /// Continuous MIDI number: 69 is A4, 60 is middle C. 60.5 is a quarter tone above C4.
    let midi: Double

    init(midi: Double) { self.midi = midi }
    init(frequency: Double) { midi = 69 + 12 * log2(frequency / 440) }

    var nearest: Int { Int(midi.rounded()) }
    /// Cents from the nearest note, -50 (flat) to +50 (sharp).
    var cents: Double { (midi - Double(nearest)) * 100 }
    var name: String { Note.names[((nearest % 12) + 12) % 12] }
    var octave: Int { Int(floor(Double(nearest) / 12)) - 1 }
    /// e.g. "A4", "C♯3".
    var label: String { "\(name)\(octave)" }
    var frequency: Double { 440 * pow(2, (midi - 69) / 12) }

    static func label(midi: Int) -> String { Note(midi: Double(midi)).label }
}

/// YIN pitch detector (de Cheveigné & Kawahara, 2002), tuned for singing voice.
///
/// Pure Swift plus Accelerate, no audio APIs, so it can be unit tested with synthetic signals.
struct PitchDetector {
    var sampleRate: Double
    /// Lowest pitch to look for. 60 Hz is below a low bass B1.
    var minFrequency: Double = 60
    /// Highest pitch to look for. 1,400 Hz is above a soprano F6.
    var maxFrequency: Double = 1_400
    /// YIN absolute threshold. Lower is stricter (fewer false notes, more dropouts).
    var threshold: Double = 0.15
    /// Blocks quieter than this RMS are treated as silence.
    var silenceLevel: Double = 0.01

    var maxLag: Int { Int(sampleRate / minFrequency) }
    var minLag: Int { max(2, Int(sampleRate / maxFrequency)) }
    /// Samples needed per call: two periods of the lowest pitch plus a margin.
    var blockSize: Int {
        var n = 1
        while n < maxLag * 3 { n <<= 1 }
        return n
    }

    func detect(_ samples: [Float]) -> PitchReading? {
        let tauMax = maxLag
        let window = samples.count - tauMax
        guard window >= tauMax, tauMax > minLag else { return nil }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        guard Double(rms) >= silenceLevel else { return nil }

        // Step 1-2: difference function d(tau) = sum over the window of (x[i] - x[i + tau])^2.
        var diff = [Float](repeating: 0, count: tauMax + 1)
        samples.withUnsafeBufferPointer { x in
            let base = x.baseAddress!
            for tau in 1...tauMax {
                var d: Float = 0
                vDSP_distancesq(base, 1, base + tau, 1, &d, vDSP_Length(window))
                diff[tau] = d
            }
        }

        // Step 3: cumulative mean normalized difference.
        var cmnd = [Float](repeating: 1, count: tauMax + 1)
        var running: Float = 0
        for tau in 1...tauMax {
            running += diff[tau]
            cmnd[tau] = running > 0 ? diff[tau] * Float(tau) / running : 1
        }

        // Step 4: first dip under the threshold, walked down to its local minimum.
        // Taking the first dip (not the global one) is what avoids octave-low errors.
        var tau = minLag
        var found: Int?
        while tau < tauMax {
            if Double(cmnd[tau]) < threshold {
                while tau + 1 < tauMax, cmnd[tau + 1] < cmnd[tau] { tau += 1 }
                found = tau
                break
            }
            tau += 1
        }
        guard let best = found else { return nil }

        // Step 5: parabolic interpolation for sub-sample accuracy.
        let refined: Double
        if best > 1, best < tauMax {
            let s0 = Double(cmnd[best - 1]), s1 = Double(cmnd[best]), s2 = Double(cmnd[best + 1])
            let denom = s0 - 2 * s1 + s2
            refined = denom != 0 ? Double(best) + 0.5 * (s0 - s2) / denom : Double(best)
        } else {
            refined = Double(best)
        }

        return PitchReading(frequency: sampleRate / refined,
                            clarity: max(0, 1 - Double(cmnd[best])),
                            level: Double(rms))
    }
}

/// Smooths raw readings: median of the last few voiced frames, and holds a short gap
/// so a consonant or breath doesn't break the line.
struct PitchSmoother {
    var window = 5
    var minClarity = 0.8
    private var recent: [Double] = []

    mutating func push(_ reading: PitchReading?) -> Double? {
        guard let reading, reading.clarity >= minClarity else {
            recent.removeAll()
            return nil
        }
        let midi = reading.note.midi
        // A jump of more than 7 semitones restarts the median so real leaps register at once.
        if let last = recent.last, abs(last - midi) > 7 { recent.removeAll() }
        recent.append(midi)
        if recent.count > window { recent.removeFirst() }
        return recent.sorted()[recent.count / 2]
    }
}

/// Tracks the lowest and highest notes held cleanly for a minimum duration.
/// This is the range test: a note only counts if you sustain it, not if you scrape past it.
struct RangeTracker {
    var holdSeconds = 0.5
    private(set) var low: Int?
    private(set) var high: Int?
    private var current: Int?
    private var heldSince: Double?

    mutating func update(midi: Double?, time: Double) {
        guard let midi else { current = nil; heldSince = nil; return }
        let n = Int(midi.rounded())
        if n != current { current = n; heldSince = time; return }
        guard let start = heldSince, time - start >= holdSeconds else { return }
        low = min(low ?? n, n)
        high = max(high ?? n, n)
    }

    mutating func reset() { self = RangeTracker(holdSeconds: holdSeconds) }
}
