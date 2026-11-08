import XCTest
@testable import VocalPractice

final class SongPlanTests: XCTestCase {
    private var prettyWoman: SongPlan { SamplePlans.prettyWoman }

    private func day(_ s: String) -> PlanDate { PlanDate(s)! }

    /// Pretty Woman as JSON with one edit applied, for validator failure cases.
    private func editedJSON(_ edit: (inout [String: Any]) -> Void) -> Data {
        var object = try! JSONSerialization.jsonObject(with: Data(SamplePlans.prettyWomanJSON.utf8)) as! [String: Any]
        edit(&object)
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func errors(_ edit: (inout SongPlan) -> Void) -> [String] {
        var plan = prettyWoman
        edit(&plan)
        return PlanValidator.validate(plan)
    }

    // MARK: Format

    func testDecodesPrettyWoman() {
        let plan = prettyWoman
        XCTAssertEqual(plan.song.title, "Oh, Pretty Woman")
        XCTAssertEqual(plan.song.keyOptions, ["A", "Ab", "G"])
        XCTAssertEqual(plan.song.minutesPerPass, 6)
        XCTAssertEqual(plan.goal.type, .showcase)
        XCTAssertEqual(plan.goal.date, PlanDate(year: 2027, month: 1, day: 25))
        XCTAssertTrue(plan.goal.dateIsApprox)
        XCTAssertEqual(plan.sections.count, 4)
        XCTAssertEqual(plan.phases.count, 6)
        XCTAssertEqual(plan.phases.map(\.songBlock), [.listen, .sections, .sections, .maintenance, .fullRun, .taper])
        XCTAssertEqual(plan.checkpoints.count, 3)
        XCTAssertEqual(PlanValidator.validate(plan), [])
    }

    func testEncodeDecodeRoundTrips() throws {
        var plan = prettyWoman
        plan.assessment = PlanAssessment(summary: "Within reach.", keyRecommendation: "Try Ab.",
                                         sources: [PlanSource(title: "Live 1988", url: "https://example.com/a")])
        plan.blockedRanges = [PlanBlockedRange(start: day("2026-12-21"), end: day("2027-01-03"), label: "Holidays")]
        let data = try SongPlan.encode(plan)
        XCTAssertEqual(try SongPlan.decode(data), plan)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"date\" : \"2027-01-25\""), "Dates encode as YYYY-MM-DD")
        XCTAssertTrue(text.contains("https://example.com/a"), "Slashes are not escaped")
    }

    // MARK: Validator, one failing case per rule

    func testRejectsWrongSchemaVersion() {
        XCTAssertEqual(errors { $0.schemaVersion = 2 }, ["schemaVersion must be 1"])
    }

    func testRequiresSongFields() {
        XCTAssertEqual(errors { $0.song.title = "" }, ["song.title is required"])
        XCTAssertEqual(errors { $0.song.artist = "" }, ["song.artist is required"])
        XCTAssertEqual(errors { $0.song.originalKey = "" }, ["song.originalKey is required"])
        XCTAssertEqual(errors { $0.song.minutesPerPass = 0 }, ["song.minutesPerPass is required"])
    }

    func testRejectsRangeThatIsNotANote() {
        XCTAssertEqual(errors { $0.song.range?.high = "H4" }, ["song.range.high 'H4' is not a note like E3 or F#4"])
    }

    func testRejectsInvalidGoalType() {
        let result = PlanValidator.check(editedJSON { plan in
            var goal = plan["goal"] as! [String: Any]; goal["type"] = "party"; plan["goal"] = goal
        })
        XCTAssertNil(result.plan)
        XCTAssertEqual(result.errors, ["goal.type 'party' must be one of showcase, recording, lesson, none"])
    }

    func testRejectsInvalidDifficulty() {
        let result = PlanValidator.check(editedJSON { plan in
            var sections = plan["sections"] as! [[String: Any]]; sections[1]["difficulty"] = "extreme"; plan["sections"] = sections
        })
        XCTAssertNil(result.plan)
        XCTAssertEqual(result.errors, ["sections.1.difficulty 'extreme' must be one of high, medium, low"])
    }

    func testRejectsInvalidSongBlock() {
        let result = PlanValidator.check(editedJSON { plan in
            var phases = plan["phases"] as! [[String: Any]]; phases[0]["songBlock"] = "karaoke"; plan["phases"] = phases
        })
        XCTAssertNil(result.plan)
        XCTAssertEqual(result.errors, ["phases.0.songBlock 'karaoke' must be one of listen, sections, fullRun, maintenance, taper"])
    }

    func testRejectsGapsAndOverlaps() {
        XCTAssertEqual(errors { $0.phases[1].start = self.day("2026-11-10") },
                       ["phase build-top: starts 2026-11-10, expected 2026-11-09 (gap or overlap)"])
        XCTAssertEqual(errors { $0.phases[2].start = self.day("2026-11-29") },
                       ["phase character: starts 2026-11-29, expected 2026-11-30 (gap or overlap)"])
    }

    func testRejectsPhaseEndingBeforeItStarts() {
        let errs = errors { $0.phases[0].end = self.day("2026-10-25") }
        XCTAssertTrue(errs.contains("phase absorb: ends before it starts"), "\(errs)")
    }

    func testRejectsUnknownFocusSection() {
        XCTAssertEqual(errors { $0.phases[1].focusSections.append("chorus") }, ["phase build-top: unknown section 'chorus'"])
    }

    func testRequiresTaperLastEndingOnGoal() {
        XCTAssertEqual(errors { $0.phases[5].songBlock = .fullRun }, ["last phase must be a taper"])
        XCTAssertEqual(errors { $0.goal.date = self.day("2027-01-26") }, ["last phase must end on goal.date"])
    }

    func testRequiresAPhase() {
        XCTAssertEqual(errors { $0.phases = [] }, ["at least one phase is required"])
    }

    func testRejectsBadDate() {
        let result = PlanValidator.check(editedJSON { plan in
            var goal = plan["goal"] as! [String: Any]; goal["date"] = "2027-02-30"; plan["goal"] = goal
        })
        XCTAssertEqual(result.errors, ["goal.date '2027-02-30' is not a date like 2027-01-25"])
    }

    func testRejectsNonJSON() {
        XCTAssertEqual(PlanValidator.check(Data("not json".utf8)).errors, ["The file isn't valid plan JSON."])
    }

    // MARK: Notes

    func testParsesNoteNames() {
        XCTAssertEqual(NoteName.midi("E3"), 52)
        XCTAssertEqual(NoteName.midi("F#4"), 66)
        XCTAssertEqual(NoteName.midi("F♯4"), 66)
        XCTAssertEqual(NoteName.midi("Bb3"), 58)
        XCTAssertEqual(NoteName.midi("E♭3"), 51)
        XCTAssertEqual(NoteName.midi("C4"), 60)
        XCTAssertEqual(NoteName.midi("Cb4"), 59)
        XCTAssertNil(NoteName.midi("H4"))
        XCTAssertNil(NoteName.midi("C"))
        XCTAssertNil(NoteName.midi("C+4"))
        XCTAssertEqual(NoteName.label(midi: 66), "F♯4")
    }

    func testTransposesKeysDown() {
        XCTAssertEqual(NoteName.key("A", down: 1), "Ab")
        XCTAssertEqual(NoteName.key("A", down: 2), "G")
        XCTAssertEqual(NoteName.key("C", down: 1), "B")
        XCTAssertEqual(NoteName.key("F#m", down: 1), "Fm")
        XCTAssertNil(NoteName.key("X", down: 1))
    }

    // MARK: PlanDate

    func testPlanDateParsing() {
        XCTAssertEqual(PlanDate("2027-01-25"), PlanDate(year: 2027, month: 1, day: 25))
        XCTAssertNil(PlanDate("2027-1-25"))
        XCTAssertNil(PlanDate("2027-02-29"))
        XCTAssertNotNil(PlanDate("2028-02-29"))
        XCTAssertEqual(PlanDate(year: 2026, month: 3, day: 7).description, "2026-03-07")
    }

    func testPlanDateArithmeticAcrossYearEnd() {
        let dec31 = day("2026-12-31")
        XCTAssertEqual(dec31.adding(days: 1), day("2027-01-01"))
        XCTAssertEqual(day("2027-01-03").adding(days: -3), dec31)
        XCTAssertEqual(day("2026-10-26").daysUntil(day("2027-01-25")), 91)
        XCTAssertEqual(day("2027-01-25").daysUntil(day("2026-10-26")), -91)
        XCTAssertLessThan(dec31, day("2027-01-01"))
    }

    func testPlanDateAcrossDSTChange() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Chicago")!
        // US clocks spring forward on 2027-03-14.
        XCTAssertEqual(day("2027-03-13").daysUntil(day("2027-03-15")), 2)
        XCTAssertEqual(day("2027-03-13").adding(days: 1), day("2027-03-14"))
        for s in ["2027-03-13", "2027-03-14", "2027-03-15", "2026-11-01"] {
            XCTAssertEqual(PlanDate(day(s).date(in: cal), calendar: cal), day(s), s)
        }
        // Late evening stays on its own day in local time, even though it's the next day in UTC.
        let lateEvening = cal.date(from: DateComponents(year: 2027, month: 3, day: 13, hour: 23, minute: 30))!
        XCTAssertEqual(PlanDate(lateEvening, calendar: cal), day("2027-03-13"))
    }

    // MARK: Phases and countdown

    func testPhaseResolverBoundaries() {
        let plan = prettyWoman
        XCTAssertNil(PhaseResolver.current(plan: plan, on: day("2026-10-25")))
        XCTAssertEqual(PhaseResolver.current(plan: plan, on: day("2026-10-26"))?.id, "absorb")
        XCTAssertEqual(PhaseResolver.current(plan: plan, on: day("2026-11-08"))?.id, "absorb")
        XCTAssertEqual(PhaseResolver.current(plan: plan, on: day("2026-11-09"))?.id, "build-top")
        XCTAssertEqual(PhaseResolver.current(plan: plan, on: day("2027-01-25"))?.id, "taper")
        XCTAssertNil(PhaseResolver.current(plan: plan, on: day("2027-01-26")))
    }

    func testCountdown() {
        XCTAssertEqual(PlanFormat.countdown(from: day("2026-10-23"), to: day("2027-01-25"), approx: false), "13 weeks, 3 days")
        XCTAssertEqual(PlanFormat.countdown(from: day("2027-01-11"), to: day("2027-01-25"), approx: true), "about 2 weeks")
        XCTAssertEqual(PlanFormat.countdown(from: day("2027-01-24"), to: day("2027-01-25"), approx: false), "1 day")
        XCTAssertEqual(PlanFormat.countdown(from: day("2027-01-25"), to: day("2027-01-25"), approx: false), "Today")
    }
}
