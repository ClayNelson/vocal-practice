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

    func testSinceLastLessonKeepsOnlyLaterSessions() {
        let t = { Date(timeIntervalSince1970: $0) }
        let dates = [t(500), t(1_000), t(1_500)]
        XCTAssertEqual(PracticeReview.sinceLastLesson(dates, date: { $0 }, lastLesson: t(1_000)), [t(1_500)])
        XCTAssertEqual(PracticeReview.sinceLastLesson(dates, date: { $0 }, lastLesson: nil), dates)
    }

    // MARK: Song plans

    private func planned(_ block: SongBlock, sections: [SectionSnapshot] = [], fullRuns: Int = 0,
                         goal: Date = .now.addingTimeInterval(86_400 * 30)) -> SongSnapshot {
        SongSnapshot(title: "Pretty Woman", status: .learning, minutes: 5, goalDate: goal,
                     planContext: SongPlanContext(block: block, minutesPerPass: 6, focusSections: sections,
                                                  fullRunsThisWeek: fullRuns))
    }

    private func songPlan(_ songs: [SongSnapshot], voice: Int = 3) -> SessionPlan {
        SessionPlanner.plan(minutes: 60, warmups: [], songs: songs, voiceCondition: voice)
    }

    func testPhaseBlocksSetModeAndMinutes() {
        let top = SectionSnapshot(id: "top", title: "Top phrases", focus: "Free, not loud", difficulty: "high")
        let listen = planned(.listen)
        XCTAssertEqual(songPlan([listen]).songs, [.song(listen.with(minutes: 6), .listen)])
        XCTAssertEqual(songPlan([planned(.sections, sections: [top])]).songs.first?.songMode,
                       .section(id: "top", title: "Top phrases", focus: "Free, not loud"))
        XCTAssertEqual(songPlan([planned(.fullRun)]).songs.first?.minutes, 12)
        XCTAssertEqual(songPlan([planned(.fullRun)]).songs.first?.songMode, .fullRun)
        XCTAssertEqual(songPlan([planned(.taper)]).songs.first?.songMode, .taper)
        XCTAssertEqual(songPlan([planned(.taper)]).songs.first?.minutes, 6)
    }

    func testSectionPickOrder() {
        let old = Date(timeIntervalSince1970: 1_000), older = Date(timeIntervalSince1970: 500)
        func pick(_ s: [SectionSnapshot]) -> String? { SessionPlanner.pickSection(s)?.id }
        let free = SectionSnapshot(id: "free", title: "A", difficulty: "high", order: 0, lastRating: "free", lastPracticed: older)
        let fresh = SectionSnapshot(id: "fresh", title: "B", difficulty: "low", order: 1)
        let pressed = SectionSnapshot(id: "pressed", title: "C", difficulty: "low", order: 2, lastRating: "pressed", lastPracticed: old)
        let cracked = SectionSnapshot(id: "cracked", title: "D", difficulty: "low", order: 3, lastRating: "cracked", lastPracticed: old)
        XCTAssertEqual(pick([free, fresh, pressed, cracked]), "cracked")
        XCTAssertEqual(pick([free, fresh, pressed]), "pressed")
        XCTAssertEqual(pick([free, fresh]), "fresh", "Never practiced beats practiced and free")
        let freeNewer = SectionSnapshot(id: "newer", title: "E", difficulty: "high", order: 4, lastRating: "free", lastPracticed: old)
        XCTAssertEqual(pick([freeNewer, free]), "free", "Oldest practiced first")

        // Ties: difficulty, then plan order.
        let medium = SectionSnapshot(id: "medium", title: "F", difficulty: "medium", order: 0)
        let highLater = SectionSnapshot(id: "high-later", title: "G", difficulty: "high", order: 5)
        let highFirst = SectionSnapshot(id: "high-first", title: "H", difficulty: "high", order: 1)
        XCTAssertEqual(pick([medium, highLater, highFirst]), "high-first")
    }

    func testRatingFreeMovesToTheOtherFocusSection() {
        var top = SectionSnapshot(id: "top-phrases", title: "Top phrases", difficulty: "high", order: 0)
        let bridge = SectionSnapshot(id: "bridge-climb", title: "Bridge climb", difficulty: "high", order: 2)
        XCTAssertEqual(SessionPlanner.pickSection([top, bridge])?.id, "top-phrases")
        top.lastRating = "free"; top.lastPracticed = .now
        XCTAssertEqual(SessionPlanner.pickSection([top, bridge])?.id, "bridge-climb")
    }

    func testMaintenanceCapsAtThreeFullRunsAWeek() {
        XCTAssertEqual(songPlan([planned(.maintenance, fullRuns: 2)]).songs.first?.songMode, .fullRun)
        XCTAssertEqual(songPlan([planned(.maintenance, fullRuns: 2)]).songs.first?.minutes, 6)
        XCTAssertTrue(songPlan([planned(.maintenance, fullRuns: 3)]).songs.isEmpty)
    }

    func testTaperSkippedOnRoughVoice() {
        XCTAssertTrue(songPlan([planned(.taper)], voice: 2).songs.isEmpty)
        XCTAssertEqual(songPlan([planned(.taper)], voice: 3).songs.count, 1)
    }

    func testPlannedSongOrdersAheadOfShowcaseSong() {
        let showcase = SongSnapshot(title: "Showcase", status: .performanceReady, minutes: 5, showcase: true)
        var later = planned(.fullRun, goal: .now.addingTimeInterval(86_400 * 60)); later.title = "Later goal"
        var sooner = planned(.listen, goal: .now.addingTimeInterval(86_400 * 10)); sooner.title = "Sooner goal"
        XCTAssertEqual(songPlan([showcase, later, sooner]).songs.map(\.title), ["Sooner goal", "Later goal", "Showcase"])
    }

    func testPlannedSongIsPracticedWhateverItsStatus() {
        var seam = planned(.listen); seam.status = .seam
        XCTAssertEqual(songPlan([seam]).songs.count, 1)
        var retired = planned(.listen); retired.status = .retired
        XCTAssertTrue(songPlan([retired]).songs.isEmpty)
    }

    func testUnplannedSongUnchanged() {
        let song = SongSnapshot(title: "Good Ol' Boys", status: .learning, minutes: 5)
        XCTAssertEqual(songPlan([song]).songs, [.song(song, .normal)])
        XCTAssertEqual(songPlan([song]).songs, [.song(song)])
    }
}

private extension SongSnapshot {
    func with(minutes: Int) -> SongSnapshot { var s = self; s.minutes = minutes; return s }
}
