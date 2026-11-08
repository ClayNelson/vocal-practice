import XCTest
@testable import VocalPractice

/// Fixtures follow Clay's lesson board as reorganized on Nov 6, 2026: "Thrive with Five" and
/// "The Dirty Dozen" routines, with summary cards that number them.
final class BoardMappingTests: XCTestCase {
    private typealias Card = BoardMapping.CardInfo

    private let board: [Card] = [
        Card(id: "pkg", name: "1st Class Package", desc: "30 Classes\n1. 8/19\n2. 8/26\n3. 9/3", listID: "nitty", listName: "The Nitty Gritty"),
        Card(id: "policy", name: "2026 Mesmerize Studio Policies", desc: "Cancellations:\nPractice Schedule:\n3 days a week", listID: "nitty", listName: "The Nitty Gritty"),
        Card(id: "rainbow", name: "Somewhere over the rainbow octave jumps", listID: "warm", listName: "Warmups", hasAudio: true),
        Card(id: "precursor", name: "Precursor to breath fire starters", listID: "warm", listName: "Warmups", hasAudio: true),
        Card(id: "bfs200", name: "BFS to 200", listID: "warm", listName: "Warmups", hasAudio: true),
        Card(id: "thrive", name: "Thrive with Five",
             desc: "Thrive with five: \n1. BFS to 300 OR Snake\n2. Super Mario\n3. Vegas road rage\n4. Up the scale\n5. Pink Panther",
             listID: "warm", listName: "Warmups"),
        Card(id: "snake", name: "Snake", listID: "warm", listName: "Warmups", hasAudio: true),
        Card(id: "bfs300", name: "BFS to 300", listID: "five", listName: "Thrive with Five", hasAudio: true),
        Card(id: "mario", name: "Super Mario Bros. x Inspector Gadget | Epic Theme Song Mashup 2026",
             desc: "https://youtube.com/watch?v=35ge5wu-EB0", listID: "five", listName: "Thrive with Five"),
        Card(id: "vegas", name: "Vegas road rage (w/ google doc)", listID: "five", listName: "Thrive with Five", hasAudio: true),
        Card(id: "scale", name: "Up the scale", desc: "BUBBLES > ROLLS> VOWELS", listID: "five", listName: "Thrive with Five", hasAudio: true),
        Card(id: "pp", name: "PP + Bond +7 (w/ google doc)", listID: "five", listName: "Thrive with Five", hasAudio: true),
        Card(id: "dozen", name: "The Dirty Dozen",
             desc: "1. BFS to 300 or Snake\n2. Super Mario medley\n3. Flexibility\n4. Bumble bees\n5. Up the scale \n6. Pink panther \n7. Vegas road rage\n8. Tiger- Phantom medley\n9. First etude\n10. Third etude\n11. Llama Mama \n12. Llama Mama 2\n",
             listID: "twelve", listName: "The Dirty Dozen"),
        Card(id: "flex", name: "Flexibility- you sing an octave below", listID: "twelve", listName: "The Dirty Dozen", hasAudio: true),
        Card(id: "mario2", name: "Super Mario Bros. x Inspector Gadget | Epic Theme Song Mashup 2026",
             desc: "https://youtube.com/watch?v=35ge5wu-EB0", listID: "twelve", listName: "The Dirty Dozen"),
        Card(id: "bees", name: "Bumble bees", desc: "BUBBLES > ROLLS > WORDS", listID: "twelve", listName: "The Dirty Dozen", hasAudio: true),
        Card(id: "tiger", name: "Tiger and phantom mashup (w/ google doc)", listID: "twelve", listName: "The Dirty Dozen", hasAudio: true),
        Card(id: "etude1", name: "First etude", listID: "twelve", listName: "The Dirty Dozen", hasAudio: true),
        Card(id: "etude3", name: "Third etude", listID: "twelve", listName: "The Dirty Dozen", hasAudio: true),
        Card(id: "llama1", name: "Llama Mama 1", listID: "twelve", listName: "The Dirty Dozen", hasAudio: true),
        Card(id: "llama2", name: "Llama Mama 2", listID: "twelve", listName: "The Dirty Dozen", hasAudio: true),
    ]

    private var kinds: [String: BoardMapping.Kind] { BoardMapping.classify(board, packageCardID: "pkg") }

    func testClassifiesCards() {
        XCTAssertEqual(kinds["pkg"], .other)
        XCTAssertEqual(kinds["policy"], .other, "No track, no link, in a list without tracks")
        XCTAssertEqual(kinds["thrive"], .routineSummary)
        XCTAssertEqual(kinds["dozen"], .routineSummary)
        XCTAssertEqual(kinds["mario"], .warmup, "A YouTube link makes it practice material")
        XCTAssertEqual(kinds["snake"], .warmup)
    }

    func testCopiedCardIsOneWarmup() {
        let canonical = BoardMapping.canonicalIDs(board, kinds: kinds)
        XCTAssertEqual(canonical["mario2"], "mario")
        XCTAssertEqual(canonical["mario"], "mario")
    }

    func testSummaryRoutinesResolveToCards() {
        let routines = BoardMapping.routines(board, kinds: kinds)
        let thrive = routines.first { $0.name == "Thrive with Five" }
        XCTAssertEqual(thrive?.slots, [["bfs300", "snake"], ["mario"], ["vegas"], ["scale"], ["pp"]])
        XCTAssertEqual(thrive?.missing, [])
        XCTAssertEqual(thrive?.fromSummary, true)

        let dozen = routines.first { $0.name == "The Dirty Dozen" }
        XCTAssertEqual(dozen?.slots, [["bfs300", "snake"], ["mario"], ["flex"], ["bees"], ["scale"], ["pp"], ["vegas"],
                                      ["tiger"], ["etude1"], ["etude3"], ["llama1"], ["llama2"]])
        XCTAssertEqual(dozen?.missing, [])
    }

    func testListsWithoutSummaryBecomeRoutines() {
        let routines = BoardMapping.routines(board, kinds: kinds)
        XCTAssertEqual(routines.map(\.name), ["Thrive with Five", "The Dirty Dozen", "Warmups"],
                       "Lists named by a summary aren't repeated")
        XCTAssertEqual(routines.last?.slots, [["rainbow"], ["precursor"], ["bfs200"], ["snake"]])
        XCTAssertEqual(routines.last?.fromSummary, false)
    }

    func testUnmatchedLinesAreReported() {
        var cards = board
        cards[cards.firstIndex { $0.id == "thrive" }!].desc = "1. Up the scale\n2. Snake\n3. Kazoo drills"
        let thrive = BoardMapping.routines(cards, kinds: BoardMapping.classify(cards, packageCardID: "pkg"))
            .first { $0.name == "Thrive with Five" }
        XCTAssertEqual(thrive?.missing, ["Kazoo drills"])
        XCTAssertEqual(thrive?.slots, [["scale"], ["snake"]])
    }

    func testAutoRoutineFollowsSessionLength() {
        let routines = BoardMapping.routines(board, kinds: kinds)
        XCTAssertEqual(BoardMapping.autoRoutine(routines, minutes: 30)?.name, "Thrive with Five")
        XCTAssertEqual(BoardMapping.autoRoutine(routines, minutes: 45)?.name, "Thrive with Five")
        XCTAssertEqual(BoardMapping.autoRoutine(routines, minutes: 60)?.name, "The Dirty Dozen")
        let plainLists = routines.filter { !$0.fromSummary }
        XCTAssertNil(BoardMapping.autoRoutine(plainLists, minutes: 30), "A plain board keeps the old rotation")
    }

    func testNotesAndLinks() {
        XCTAssertEqual(BoardMapping.notes(from: "BUBBLES > ROLLS> VOWELS"), "BUBBLES > ROLLS> VOWELS")
        XCTAssertEqual(BoardMapping.notes(from: "https://youtube.com/watch?v=35ge5wu-EB0&is=N-aMpkGogoqUO6YE"), "")
        XCTAssertEqual(BoardMapping.link(in: "Watch https://youtube.com/watch?v=35ge5wu-EB0 first")?.host, "youtube.com")
        XCTAssertNil(BoardMapping.link(in: "BUBBLES > ROLLS"))
    }

    func testCancelLineStillCountsButIsMarked() {
        let package = TrelloMapping.lessonPackage(from: "30 Classes\n5. 10/23\n6. 10/26 <Same day cancel\n7. ",
                                                  reference: Date(timeIntervalSince1970: 1_793_000_000))
        XCTAssertEqual(package.lessons.map(\.number), [5, 6])
        XCTAssertEqual(package.lessons.map(\.isCanceled), [false, true])
    }

    // MARK: Changes

    private func at(_ minute: Int) -> Date { Date(timeIntervalSince1970: 1_794_000_000 + Double(minute) * 60) }

    func testChangesReadLikeTheBoard() {
        let n = (id: "nicolette", name: "Nicolette Holman")
        let actions: [BoardMapping.Action] = [
            .init(kind: .created, date: at(1), memberID: n.id, memberName: n.name, cardID: "llama2", cardName: "Llama Mama 2", listName: "The Dirty Dozen"),
            .init(kind: .track, date: at(2), memberID: n.id, memberName: n.name, cardID: "llama2", cardName: "Llama Mama 2"),
            .init(kind: .moved, date: at(3), memberID: n.id, memberName: n.name, cardID: "bfs300", cardName: "BFS to 300", listName: "The Dirty Dozen"),
            .init(kind: .moved, date: at(4), memberID: n.id, memberName: n.name, cardID: "bfs300", cardName: "BFS to 300", listName: "Thrive with Five"),
            .init(kind: .notes, date: at(5), memberID: n.id, memberName: n.name, cardID: "scale", cardName: "Up the scale"),
            .init(kind: .comment, date: at(6), memberID: n.id, memberName: n.name, cardID: "bees", cardName: "Bumble bees", text: "Lighter on the rolls"),
            .init(kind: .notes, date: at(7), memberID: "clay", memberName: "Clay Nelson", cardID: "snake", cardName: "Snake"),
            .init(kind: .other, date: at(8), memberID: n.id, memberName: n.name, cardID: "pkg", cardName: "1st Class Package"),
        ]
        let changes = BoardMapping.changes(from: actions, excludingMember: "clay")
        XCTAssertEqual(changes.map(\.text), [
            "On Bumble bees: Lighter on the rolls",
            "Updated the notes on Up the scale",
            "Moved BFS to 300 to Thrive with Five",
            "Added Llama Mama 2 to The Dirty Dozen with a track",
        ])
        XCTAssertEqual(Set(changes.map(\.who)), ["Nicolette"])
    }

    func testAlternativesSplitOnOr() {
        XCTAssertEqual(BoardMapping.alternatives("BFS to 300 OR Snake"), ["BFS to 300", "Snake"])
        XCTAssertEqual(BoardMapping.alternatives("Bumble bees"), ["Bumble bees"])
        XCTAssertEqual(BoardMapping.alternatives("Flexibility for range"), ["Flexibility for range"], "Only the word or")
    }
}
