import XCTest
@testable import VocalPractice

final class SessionPlannerTests: XCTestCase {
    private let ladder = [
        WarmupSnapshot(title: "Precursor", ladderGroup: "BFS", ladderLevel: 0, minutes: 3, isSolid: true),
        WarmupSnapshot(title: "BFS 125", ladderGroup: "BFS", ladderLevel: 125, minutes: 4, isSolid: true),
        WarmupSnapshot(title: "BFS 150", ladderGroup: "BFS", ladderLevel: 150, minutes: 4),
        WarmupSnapshot(title: "BFS 175", ladderGroup: "BFS", ladderLevel: 175, minutes: 4),
    ]
    private let standalone = [
        WarmupSnapshot(title: "Octave jumps", minutes: 4, lastPracticed: .now),
        WarmupSnapshot(title: "Waltz", minutes: 4, lastPracticed: nil),
        WarmupSnapshot(title: "Vegas Road Rage", minutes: 4, lastPracticed: .now.addingTimeInterval(-86_400 * 3)),
    ]

    func testDefaultMinutesFollowStudioPolicy() {
        XCTAssertEqual(SessionPlanner.defaultMinutes(daysPerWeek: 3), 60)
        XCTAssertEqual(SessionPlanner.defaultMinutes(daysPerWeek: 4), 45)
        XCTAssertEqual(SessionPlanner.defaultMinutes(daysPerWeek: 5), 30)
    }

    func testLadderSchedulesOnlyCurrentRung() {
        let plan = SessionPlanner.plan(minutes: 60, warmups: ladder + standalone, songs: [])
        let titles = plan.warmups.map(\.title)
        XCTAssertTrue(titles.contains("BFS 150"))
        XCTAssertFalse(titles.contains("BFS 125"))
        XCTAssertFalse(titles.contains("BFS 175"))
        XCTAssertEqual(titles.first, "BFS 150", "Ladder work comes before standalone warmups")
    }

    func testStandaloneWarmupsRotateLeastRecentFirst() {
        let plan = SessionPlanner.plan(minutes: 60, warmups: standalone, songs: [])
        XCTAssertEqual(plan.warmups.map(\.title), ["Waltz", "Vegas Road Rage", "Octave jumps"])
    }

    func testHalfWarmupsHalfSongs() {
        let songs = (1...6).map { SongSnapshot(title: "Song \($0)", status: .learning, minutes: 5) }
        let plan = SessionPlanner.plan(minutes: 30, warmups: ladder + standalone, songs: songs)
        XCTAssertLessThanOrEqual(plan.warmups.reduce(0) { $0 + $1.minutes }, 15)
        XCTAssertEqual(plan.songs.reduce(0) { $0 + $1.minutes }, 15)
    }

    func testSongPriorityShowcaseThenLearning() {
        let songs = [
            SongSnapshot(title: "Polish", status: .polishing, minutes: 5, lastPracticed: nil),
            SongSnapshot(title: "Learn", status: .learning, minutes: 5, lastPracticed: .now),
            SongSnapshot(title: "Showcase", status: .performanceReady, minutes: 5, showcase: true, lastPracticed: .now),
            SongSnapshot(title: "Seam", status: .seam, minutes: 5),
        ]
        let plan = SessionPlanner.plan(minutes: 60, warmups: [], songs: songs)
        XCTAssertEqual(plan.songs.map(\.title), ["Showcase", "Learn", "Polish"])
    }

    func testGentleSessionStepsBackOneRungAndHalvesSongs() {
        let songs = (1...6).map { SongSnapshot(title: "Song \($0)", status: .learning, minutes: 5) }
        let plan = SessionPlanner.plan(minutes: 60, warmups: ladder, songs: songs, voiceCondition: 1)
        XCTAssertEqual(plan.warmups.map(\.title), ["BFS 125"])
        XCTAssertEqual(plan.songs.reduce(0) { $0 + $1.minutes }, 15)
    }

    func testFullySolidLadderKeepsTopRung() {
        let solid = ladder.map { var w = $0; w.isSolid = true; return w }
        let plan = SessionPlanner.plan(minutes: 30, warmups: solid, songs: [])
        XCTAssertEqual(plan.warmups.map(\.title), ["BFS 175"])
    }

    func testOversizedFirstItemStillScheduled() {
        let long = [SongSnapshot(title: "Epic", status: .learning, minutes: 20)]
        let plan = SessionPlanner.plan(minutes: 30, warmups: [], songs: long)
        XCTAssertEqual(plan.songs.map(\.title), ["Epic"])
    }

    func testWeeklyProgressCountsDistinctDays() {
        var cal = Calendar.practiceCalendar
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        let wed = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 20))!
        let dates = [
            cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!,   // Mon
            cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 19))!,  // Mon again
            cal.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9))!,   // Tue
            cal.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 9))!,   // previous Sun
        ]
        XCTAssertEqual(WeeklyProgress.daysPracticed(sessionDates: dates, now: wed, calendar: cal), 2)
    }
}
