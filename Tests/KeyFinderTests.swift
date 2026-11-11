import XCTest
@testable import VocalPractice

final class KeyFinderTests: XCTestCase {
    /// Feeds held notes at 50 readings a second: (MIDI note, seconds held), with a short gap after each.
    private func sing(_ notes: [(Int, Double)], into finder: inout KeyFinder, repeats: Int = 1) {
        var t = 0.0
        for _ in 0..<repeats {
            for (midi, seconds) in notes {
                let end = t + seconds
                while t < end { finder.update(midi: Double(midi), time: t); t += 0.02 }
                finder.update(midi: nil, time: t); t += 0.1
            }
        }
    }

    // Scale degrees in A major and A minor, leaning on tonic and fifth like a tune does. No real melodies.
    private let aMajor: [(Int, Double)] = [(57, 1.0), (61, 0.5), (64, 1.0), (62, 0.5), (61, 0.5), (59, 0.5),
                                           (57, 1.0), (64, 0.7), (66, 0.4), (68, 0.3), (69, 1.0)]
    private let aMinor: [(Int, Double)] = [(57, 1.0), (60, 0.6), (64, 1.0), (62, 0.5), (60, 0.5), (59, 0.4),
                                           (56, 0.4), (57, 1.0), (64, 0.7), (65, 0.4), (64, 0.5), (57, 1.0)]

    func testFindsAMajor() {
        var finder = KeyFinder()
        sing(aMajor, into: &finder, repeats: 3)
        XCTAssertEqual(finder.candidates.first?.name, "A major")
        XCTAssertEqual(finder.candidates.first?.planKey, "A")
        guard case .settled(let key) = finder.verdict else { return XCTFail("\(finder.verdict)") }
        XCTAssertEqual(key.name, "A major")
    }

    func testFindsAMinor() {
        var finder = KeyFinder()
        sing(aMinor, into: &finder, repeats: 3)
        XCTAssertEqual(finder.candidates.first?.name, "A minor")
        XCTAssertEqual(finder.candidates.first?.planKey, "Am")
    }

    func testTransposedTuneFindsTransposedKey() {
        var finder = KeyFinder()
        sing(aMajor.map { ($0.0 - 1, $0.1) }, into: &finder, repeats: 3)
        XCTAssertEqual(finder.candidates.first?.name, "A♭ major")
        XCTAssertEqual(finder.candidates.first?.planKey, "Ab")
    }

    func testListensBeforeGuessing() {
        var finder = KeyFinder()
        sing(Array(aMajor.prefix(3)), into: &finder)
        XCTAssertEqual(finder.verdict, .listening)
        XCTAssertEqual(finder.seconds, 2.5, accuracy: 0.1)
    }

    func testShortNotesDontCount() {
        var finder = KeyFinder()
        sing([(61, 0.1), (63, 0.1), (66, 0.12)], into: &finder, repeats: 10)
        XCTAssertEqual(finder.seconds, 0, "Scoops and passing notes under 0.15 s are ignored")
        XCTAssertEqual(finder.candidates, [])
    }

    func testHeldNoteCountsFromItsStart() {
        var finder = KeyFinder()
        sing([(57, 1.0)], into: &finder)
        XCTAssertEqual(finder.weights[9], 1.0, accuracy: 0.03)
    }

    func testRelativeKeysTooCloseAreBothShown() {
        var finder = KeyFinder()
        // Every note of A major (and F♯ minor) for the same time: the melody can't tell them apart.
        sing([57, 59, 61, 62, 64, 66, 68].map { ($0, 1.0) }, into: &finder, repeats: 2)
        guard case .relatives(let a, let b) = finder.verdict else { return XCTFail("\(finder.verdict)") }
        XCTAssertEqual(Set([a.name, b.name]), ["A major", "F♯ minor"])
    }

    func testResetClears() {
        var finder = KeyFinder()
        sing(aMajor, into: &finder)
        finder.reset()
        XCTAssertEqual(finder.seconds, 0)
        XCTAssertEqual(finder.verdict, .listening)
    }

    func testScaleAndNames() {
        XCTAssertEqual(KeyFinder.scale(tonic: 9, isMinor: false), [9, 11, 1, 2, 4, 6, 8])
        XCTAssertEqual(KeyFinder.name(tonic: 6, isMinor: true), "F♯ minor")
        XCTAssertEqual(KeyFinder.name(tonic: 1, isMinor: false), "D♭ major")
    }

    // MARK: Fit

    /// Pretty Woman: E3 to F♯4 in A, trying A, Ab, and G.
    func testKeyFitForPrettyWoman() {
        let options = KeyFit.options(originalKey: "A", keys: ["A", "Ab", "G"], songLow: 52, songHigh: 66,
                                     userLow: 48, userHigh: 65)
        XCTAssertEqual(options.map(\.shift), [0, -1, -2])
        XCTAssertEqual(options.map(\.high), [66, 65, 64])
        XCTAssertEqual(options.map(\.fits), [false, true, true])
        XCTAssertEqual(options[0].summary(userHigh: 65), "Top note F♯4 is 1 semitone above your high.")
        XCTAssertEqual(options[1].summary(userHigh: 65), "Fits: E♭3 to F4, right at your high.")
        XCTAssertEqual(options[2].summary(userHigh: 65), "Fits: D3 to E4, 1 semitone of room up top.")
    }

    func testKeyFitLowNoteAndShiftDirection() {
        let options = KeyFit.options(originalKey: "A", keys: ["C", "E", "A", "nope"], songLow: 52, songHigh: 66,
                                     userLow: 50, userHigh: 72)
        XCTAssertEqual(options.map(\.key), ["C", "E", "A"], "Unparseable keys are skipped")
        XCTAssertEqual(options.map(\.shift), [3, -5, 0], "Shifts take the nearer direction")
        XCTAssertEqual(options[1].underLow, 3, "In E the low note drops to B2, 3 below D3")
        XCTAssertFalse(options[1].fits)
    }
}
