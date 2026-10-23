import XCTest
@testable import VocalPractice

final class OfflinePlannerTests: XCTestCase {
    private func day(_ s: String) -> PlanDate { PlanDate(s)! }

    private func request(start: String, goal: String, approx: Bool = false,
                         blocked: [PlanBlockedRange] = [], sections: [PlanSection] = []) -> PlanRequest {
        PlanRequest(title: "Oh, Pretty Woman", artist: "Roy Orbison", goalType: .showcase, goalLabel: "Vocal showcase",
                    goalDate: day(goal), goalDateIsApprox: approx, start: day(start), originalKey: "A",
                    keyOptions: ["A", "Ab", "G"], rangeLow: "E3", rangeHigh: "F#4", sections: sections, blocked: blocked)
    }

    private let prettyWomanSections = SamplePlans.prettyWoman.sections

    /// Pretty Woman with the holiday block: the answer checked by hand in IMPLEMENTATION_PLAN.md.
    func testGoldenPrettyWomanWithHolidayBlock() {
        let holidays = PlanBlockedRange(start: day("2026-12-21"), end: day("2027-01-03"), label: "Holiday maintenance")
        let plan = OfflinePlanner.makePlan(request(start: "2026-10-26", goal: "2027-01-25", approx: true,
                                                   blocked: [holidays], sections: prettyWomanSections))
        XCTAssertEqual(PlanValidator.validate(plan), [])

        let expected: [(SongBlock, String, String, String, Int)] = [
            (.listen, "Absorb and key", "2026-10-26", "2026-11-08", 14),
            (.sections, "Build the hard spots", "2026-11-09", "2026-12-07", 29),
            (.sections, "Character and story", "2026-12-08", "2026-12-20", 13),
            (.maintenance, "Holiday maintenance", "2026-12-21", "2027-01-04", 15),
            (.fullRun, "Performance mode", "2027-01-05", "2027-01-18", 14),
            (.taper, "Taper", "2027-01-19", "2027-01-25", 7),
        ]
        XCTAssertEqual(plan.phases.count, expected.count)
        for (phase, (block, title, start, end, days)) in zip(plan.phases, expected) {
            XCTAssertEqual(phase.songBlock, block, title)
            XCTAssertEqual(phase.title, title)
            XCTAssertEqual(phase.start, day(start), title)
            XCTAssertEqual(phase.end, day(end), title)
            XCTAssertEqual(phase.days, days, title)
        }

        XCTAssertEqual(plan.checkpoints.map(\.due), [day("2026-11-08"), day("2026-11-09"), day("2027-01-04")])
        XCTAssertEqual(plan.checkpoints.map(\.title), ["Lock key (A, Ab, or G)", "Confirm date", "Lock arrangement"])
        XCTAssertEqual(plan.blockedRanges, [holidays])

        // Hard spots work the high sections; character works all of them.
        XCTAssertEqual(plan.phases[1].focusSections, ["top-phrases", "bridge-climb"])
        XCTAssertEqual(plan.phases[2].focusSections, prettyWomanSections.map(\.id))
        XCTAssertEqual(plan.phases[3].focusSections, [])
    }

    func testEveryLengthMakesAValidPlan() {
        let start = day("2026-10-26")
        for d in 1...150 {
            let goal = start.adding(days: d - 1).description
            let blocks = [
                [],
                [PlanBlockedRange(start: start.adding(days: d / 3), end: start.adding(days: d / 3 + 9), label: "Travel")],
                [PlanBlockedRange(start: start.adding(days: -5), end: start.adding(days: 1), label: "Away"),
                 PlanBlockedRange(start: start.adding(days: d / 2), end: start.adding(days: d / 2 + 1), label: "Cold")],
            ]
            for blocked in blocks {
                let plan = OfflinePlanner.makePlan(request(start: start.description, goal: goal, approx: true, blocked: blocked))
                XCTAssertEqual(PlanValidator.validate(plan), [], "D=\(d), blocks=\(blocked.map(\.label))")
                XCTAssertEqual(plan.phases.reduce(0) { $0 + $1.days }, d, "D=\(d)")
                XCTAssertEqual(Set(plan.phases.map(\.id)).count, plan.phases.count, "Phase ids are unique, D=\(d)")
                XCTAssertEqual(plan.checkpoints.map(\.due), plan.checkpoints.map(\.due).sorted(), "D=\(d)")
                XCTAssertTrue(plan.checkpoints.allSatisfy { $0.due >= start }, "D=\(d)")
                XCTAssertTrue(plan.phases.allSatisfy { $0.days > 0 }, "D=\(d)")
            }
        }
    }

    func testPhaseAllocationTable() {
        func blocks(_ d: Int) -> [SongBlock] {
            let start = day("2026-10-26")
            return OfflinePlanner.makePlan(request(start: start.description, goal: start.adding(days: d - 1).description))
                .phases.map(\.songBlock)
        }
        XCTAssertEqual(blocks(1), [.taper])
        XCTAssertEqual(blocks(6), [.fullRun, .taper])
        XCTAssertEqual(blocks(20), [.sections, .fullRun, .taper])
        XCTAssertEqual(blocks(45), [.listen, .sections, .fullRun, .taper])
        XCTAssertEqual(blocks(92), [.listen, .sections, .sections, .fullRun, .taper])
        XCTAssertEqual(OfflinePlanner.allocate(days: 48).map(\.days), [7, 27, 7, 7])
        XCTAssertEqual(OfflinePlanner.allocate(days: 49).map(\.days), [7, 21, 14, 7])
        XCTAssertEqual(OfflinePlanner.allocate(days: 20).map(\.days), [12, 5, 3])
        XCTAssertEqual(OfflinePlanner.allocate(days: 7).map(\.days), [1, 3, 3])
    }

    func testBlockInsideTaperLeavesTaperAlone() {
        let block = PlanBlockedRange(start: day("2027-01-20"), end: day("2027-01-30"), label: "Trip")
        let blocked = OfflinePlanner.makePlan(request(start: "2026-10-26", goal: "2027-01-25", blocked: [block]))
        let plain = OfflinePlanner.makePlan(request(start: "2026-10-26", goal: "2027-01-25"))
        XCTAssertEqual(blocked.phases, plain.phases)
    }

    func testBlockStraddlingTaperOnlyTakesDaysBeforeIt() {
        let block = PlanBlockedRange(start: day("2027-01-15"), end: day("2027-01-22"), label: "Trip")
        let plan = OfflinePlanner.makePlan(request(start: "2026-10-26", goal: "2027-01-25", blocked: [block]))
        XCTAssertEqual(plan.phases.suffix(2).map(\.songBlock), [.maintenance, .taper])
        XCTAssertEqual(plan.phases.last?.start, day("2027-01-19"))
        XCTAssertEqual(PlanValidator.validate(plan), [])
    }

    func testAdjacentBlocksMergeIntoOneMaintenancePhase() {
        let a = PlanBlockedRange(start: day("2026-12-01"), end: day("2026-12-05"), label: "Travel")
        let b = PlanBlockedRange(start: day("2026-12-06"), end: day("2026-12-10"), label: "Cold")
        let plan = OfflinePlanner.makePlan(request(start: "2026-10-26", goal: "2027-01-25", blocked: [a, b]))
        let maintenance = plan.phases.filter { $0.songBlock == .maintenance }
        XCTAssertEqual(maintenance.count, 1)
        XCTAssertEqual(maintenance.first?.title, "Travel")
        XCTAssertEqual(maintenance.first?.days, 10)
    }

    func testDefaultSectionsAndFocus() {
        let plan = OfflinePlanner.makePlan(request(start: "2026-10-26", goal: "2027-01-25"))
        XCTAssertEqual(plan.sections.map(\.id), ["hardest-phrase", "ending"])
        XCTAssertEqual(plan.phases[1].focusSections, ["hardest-phrase"])
        XCTAssertEqual(plan.phases[2].focusSections, ["hardest-phrase", "ending"])

        let noHigh = [PlanSection(id: "verse", title: "Verse", difficulty: .medium),
                      PlanSection(id: "outro", title: "Outro", difficulty: .low)]
        let easy = OfflinePlanner.makePlan(request(start: "2026-10-26", goal: "2027-01-25", sections: noHigh))
        XCTAssertEqual(easy.phases[1].focusSections, ["verse", "outro"], "No high sections: focus all")

        let short = OfflinePlanner.makePlan(request(start: "2026-10-26", goal: "2026-11-14"))
        XCTAssertEqual(short.phases[0].focusSections, ["hardest-phrase", "ending"], "A single section phase works all")
    }

    func testCheckpointsWithoutListenPhase() {
        let plan = OfflinePlanner.makePlan(request(start: "2026-10-26", goal: "2026-11-14", approx: false))
        XCTAssertEqual(plan.checkpoints.map(\.title), ["Lock key (A, Ab, or G)", "Lock arrangement"])
        XCTAssertEqual(plan.checkpoints.first?.due, day("2026-10-29"))
    }

    func testRangeCheckRecommendsLowerKeysOnlyWhenNeeded() {
        var r = request(start: "2026-10-26", goal: "2027-01-25")
        r.userHighMidi = 65  // F4, one below F#4
        XCTAssertEqual(OfflinePlanner.makePlan(r).assessment?.keyRecommendation,
                       "The top note F#4 is 1 semitone above your recent high. Try Ab or G.")

        r.userHighMidi = 66
        XCTAssertNil(OfflinePlanner.makePlan(r).assessment, "Within range: no recommendation")

        r.userHighMidi = nil
        XCTAssertNil(OfflinePlanner.makePlan(r).assessment, "Unknown range: no recommendation")

        r.userHighMidi = 63
        r.assessment = PlanAssessment(summary: "From Claude.")
        XCTAssertEqual(OfflinePlanner.makePlan(r).assessment, PlanAssessment(summary: "From Claude."),
                       "Never overwrite a supplied assessment")
    }

    func testEditingRequestReproducesPlan() {
        let plan = OfflinePlanner.makePlan(request(start: "2026-10-26", goal: "2027-01-25", approx: true))
        var again = OfflinePlanner.makePlan(PlanRequest(editing: plan))
        again.generatedAt = plan.generatedAt
        XCTAssertEqual(again, plan)
    }
}
