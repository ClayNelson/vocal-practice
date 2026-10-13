import XCTest
@testable import VocalPractice

final class PitchDetectorTests: XCTestCase {
    private let sampleRate = 48_000.0
    private var detector: PitchDetector { PitchDetector(sampleRate: sampleRate) }

    /// A voice-like tone: fundamental plus decaying harmonics, optionally with noise.
    private func tone(_ hz: Double, harmonics: [Double] = [1, 0.6, 0.4, 0.25, 0.15],
                      amplitude: Double = 0.3, noise: Double = 0) -> [Float] {
        var rng = SystemRandomNumberGenerator()
        return (0..<detector.blockSize).map { i in
            let t = Double(i) / sampleRate
            var s = 0.0
            for (k, a) in harmonics.enumerated() { s += a * sin(2 * .pi * hz * Double(k + 1) * t) }
            let n = noise > 0 ? Double.random(in: -noise...noise, using: &rng) : 0
            return Float(amplitude * s / harmonics.reduce(0, +) + n)
        }
    }

    private func assertDetects(_ hz: Double, in samples: [Float], file: StaticString = #filePath, line: UInt = #line) {
        guard let r = detector.detect(samples) else { return XCTFail("No pitch for \(hz) Hz", file: file, line: line) }
        let cents = 1200 * log2(r.frequency / hz)
        XCTAssertLessThan(abs(cents), 5, "\(hz) Hz read as \(r.frequency) Hz", file: file, line: line)
        XCTAssertGreaterThan(r.clarity, 0.85, file: file, line: line)
    }

    func testPureSinesAcrossVocalRange() {
        for hz in [82.41, 110, 196, 261.63, 440, 659.25, 987.77] {
            assertDetects(hz, in: tone(hz, harmonics: [1]))
        }
    }

    func testHarmonicRichVoiceDoesNotJumpAnOctave() {
        for hz in [98, 146.83, 220, 392] {
            assertDetects(hz, in: tone(hz))
        }
    }

    func testStrongSecondHarmonicStillReadsFundamental() {
        assertDetects(130.81, in: tone(130.81, harmonics: [0.5, 1, 0.5]))
    }

    func testNoisyNoteStillDetected() {
        assertDetects(220, in: tone(220, noise: 0.03))
    }

    func testSilenceAndNoiseReturnNothing() {
        XCTAssertNil(detector.detect([Float](repeating: 0, count: detector.blockSize)))
        let noise = (0..<detector.blockSize).map { _ in Float.random(in: -0.3...0.3) }
        if let r = detector.detect(noise) { XCTAssertLessThan(r.clarity, 0.8) }
    }

    func testNoteNaming() {
        XCTAssertEqual(Note(frequency: 440).label, "A4")
        XCTAssertEqual(Note(frequency: 261.63).label, "C4")
        XCTAssertEqual(Note(frequency: 110).label, "A2")
        XCTAssertEqual(Note(frequency: 277.18).label, "C♯4")
        XCTAssertEqual(Note(frequency: 440).cents, 0, accuracy: 0.01)
        XCTAssertEqual(Note(frequency: 440 * pow(2, 20.0 / 1200)).cents, 20, accuracy: 0.01)
    }

    func testRangeCountsOnlyHeldNotes() {
        var range = RangeTracker(holdSeconds: 0.5)
        // Scrape up to C5 for 0.2 s: doesn't count.
        range.update(midi: 72, time: 0); range.update(midi: 72, time: 0.2)
        XCTAssertNil(range.high)
        // Hold A3 then E4 long enough.
        range.update(midi: 57, time: 1); range.update(midi: 57.2, time: 1.6)
        range.update(midi: 64, time: 2); range.update(midi: 64, time: 2.6)
        XCTAssertEqual(range.low, 57)
        XCTAssertEqual(range.high, 64)
    }

    func testSmootherDropsUnclearFramesAndFollowsLeaps() {
        var s = PitchSmoother()
        XCTAssertNil(s.push(PitchReading(frequency: 220, clarity: 0.5, level: 0.1)))
        _ = s.push(PitchReading(frequency: 220, clarity: 0.95, level: 0.1))
        let leap = s.push(PitchReading(frequency: 440 * 1.5, clarity: 0.95, level: 0.1))!
        XCTAssertEqual(leap, Note(frequency: 660).midi, accuracy: 0.01, "An octave-plus leap shows immediately")
    }
}
