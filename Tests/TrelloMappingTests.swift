import XCTest
@testable import VocalPractice

final class TrelloMappingTests: XCTestCase {
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: Ladder parsing (card names from the real board)

    func testBreathFireStarterRungs() {
        let cases: [(String, Int)] = [
            ("Precursor to breath fire starters", 0),
            ("Breath fire starter to 125", 125),
            ("Breath fire starter to 150", 150),
            ("BFS to 175", 175),
            ("BFS to 200", 200),
        ]
        for (name, level) in cases {
            let shape = TrelloMapping.warmupShape(forCardName: name)
            XCTAssertEqual(shape.ladderGroup, TrelloMapping.breathLadder, name)
            XCTAssertEqual(shape.ladderLevel, level, name)
        }
    }

    func testOtherWarmupsAreStandalone() {
        for name in ["Breath fire starter to F consonant", "Waltz of the flowers", "Vegas road rage",
                     "Somewhere over the rainbow octave jumps",
                     "Super Mario Bros. x Inspector Gadget | Epic Theme Song Mashup 2026"] {
            XCTAssertNil(TrelloMapping.warmupShape(forCardName: name).ladderGroup, name)
        }
    }

    func testRungMatchesSeededLadderGroup() {
        // Seeded ladder warmups use the same group name, so sync adopts them instead of duplicating.
        XCTAssertEqual(TrelloMapping.breathLadder, "Breath fire starter")
    }

    func testNormalizeMatchesSeededTitles() {
        XCTAssertEqual(TrelloMapping.normalize("Somewhere Over the Rainbow octave jumps"),
                       TrelloMapping.normalize("Somewhere over the rainbow octave jumps"))
        XCTAssertEqual(TrelloMapping.normalize("Vegas  Road-Rage!"), "vegas road rage")
    }

    func testAudioDetection() {
        XCTAssertTrue(TrelloMapping.isAudio(name: "BFS+to+200.m4a", mimeType: "audio/mp4"))
        XCTAssertTrue(TrelloMapping.isAudio(name: "warmup.mp3", mimeType: nil))
        XCTAssertFalse(TrelloMapping.isAudio(name: "notes.pdf", mimeType: "application/pdf"))
    }

    // MARK: Lesson package card

    private let packageText = """
    30 Classes +   ~~1 Gifted Lesson <~~ used to cover 9/11 same day cancel

    1. 8/19
    2. 8/26
    3. 9/3
    4. 10/16
    5.
    """

    func testPackageParsesSizeLessonsAndGifted() {
        let package = TrelloMapping.lessonPackage(from: packageText, reference: date(2026, 10, 23), calendar: calendar)
        XCTAssertEqual(package.packageSize, 30)
        let regular = package.lessons.filter { !$0.isGifted }
        XCTAssertEqual(regular.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(regular.last?.date, date(2026, 10, 16))
        XCTAssertEqual(package.lessons.filter(\.isGifted).map(\.date), [date(2026, 9, 11)])
    }

    func testDatesAfterReferenceRollBackAYear() {
        // A December lesson read in January belongs to last year.
        let package = TrelloMapping.lessonPackage(from: "7. 12/18", reference: date(2027, 1, 10), calendar: calendar)
        XCTAssertEqual(package.lessons.first?.date, date(2026, 12, 18))
    }

    func testExplicitYearIsKept() {
        let package = TrelloMapping.lessonPackage(from: "1. 1/5/27", reference: date(2026, 10, 23), calendar: calendar)
        XCTAssertEqual(package.lessons.first?.date, date(2027, 1, 5))
    }

    func testPackageDetection() {
        XCTAssertTrue(TrelloMapping.looksLikePackage(name: "1st Class Package", description: ""))
        XCTAssertTrue(TrelloMapping.looksLikePackage(name: "Lessons", description: "1. 8/19\n2. 8/26"))
        XCTAssertFalse(TrelloMapping.looksLikePackage(name: "2026 Mesmerize Studio Policies",
                                                      description: "Please put in 3-5 days a week of practice"))
    }

    // MARK: Sign-in

    func testTokenFromCallbackFragment() {
        let token = String(repeating: "a1", count: 32)
        let url = URL(string: "vocalpractice://trello-auth#token=\(token)")!
        XCTAssertEqual(TrelloMapping.token(fromCallback: url), token)
    }

    func testDeniedCallbackHasNoToken() {
        let url = URL(string: "vocalpractice://trello-auth#token=&error=Token%20request%20rejected")!
        XCTAssertNil(TrelloMapping.token(fromCallback: url))
    }

    func testPastedTokenIsTrimmedAndValidated() {
        let token = "ATTA" + String(repeating: "f0", count: 30)
        XCTAssertEqual(TrelloMapping.cleanToken("  \(token)\n"), token)
        XCTAssertNil(TrelloMapping.cleanToken("not a token"))
    }
}
