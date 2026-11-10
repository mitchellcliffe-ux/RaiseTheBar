import XCTest
import SwiftData
@testable import RaiseTheBar

// The expected numbers in the pace tests were worked out from the Daniels and Gilbert equations in a separate script,
// not copied from the app, so these tests check the app's maths against an independent calculation.

// MARK: - Paces

final class PaceEngineTests: XCTestCase {

    func testVDOTFromA5KOf1957IsAboutFifty() {
        XCTAssertEqual(PaceEngine.vdot(distanceM: 5000, seconds: 19 * 60 + 57), 49.95, accuracy: 0.1)
    }

    func testVDOTFromA40MinuteTenK() {
        XCTAssertEqual(PaceEngine.vdot(distanceM: 10_000, seconds: 2400), 51.9, accuracy: 0.2)
    }

    func testVDOTFromA30MinuteTimeTrial() {
        XCTAssertEqual(PaceEngine.vdot(distanceM: 7500, seconds: 1800), 51.0, accuracy: 0.2)
    }

    func testZonePacesAtVDOT50() {
        func pace(_ z: Zone) -> Double { PaceEngine.secPerKm(vdot: 50, fraction: PaceEngine.fraction(of: z)) }
        XCTAssertEqual(pace(.threshold), 255.2, accuracy: 2)       // about 4:15 per km
        XCTAssertEqual(pace(.easy), 321.8, accuracy: 3)            // about 5:22 per km
        XCTAssertEqual(pace(.interval), 230.1, accuracy: 2)        // about 3:50 per km
        XCTAssertEqual(pace(.repetition), 213.0, accuracy: 2)      // about 3:33 per km
    }

    func testZonesGetFasterAsIntensityRises() {
        let order: [Zone] = [.recovery, .easy, .steady, .threshold, .interval, .repetition]
        let paces = order.map { PaceEngine.secPerKm(vdot: 45, fraction: PaceEngine.fraction(of: $0)) }
        XCTAssertEqual(paces, paces.sorted(by: >), "each zone should be faster than the one before it")
    }

    func testPredictedTimes() {
        XCTAssertEqual(PaceEngine.predictSeconds(vdot: 50, distanceM: 5000), 1196, accuracy: 3)
        XCTAssertEqual(PaceEngine.predictSeconds(vdot: 50, distanceM: 10_000), 2480, accuracy: 5)
        XCTAssertEqual(PaceEngine.predictSeconds(vdot: 50, distanceM: 21_097.5), 5491, accuracy: 10)
        XCTAssertEqual(PaceEngine.predictSeconds(vdot: 50, distanceM: 42_195), 11_440, accuracy: 20)
    }

    func testPredictionRoundTrips() {
        let t = PaceEngine.predictSeconds(vdot: 43.7, distanceM: 10_000)
        XCTAssertEqual(PaceEngine.vdot(distanceM: 10_000, seconds: t), 43.7, accuracy: 0.01)
    }

    func testFitterRunnerIsFaster() {
        XCTAssertLessThan(PaceEngine.predictSeconds(vdot: 60, distanceM: 10_000), PaceEngine.predictSeconds(vdot: 50, distanceM: 10_000))
    }

    func testStartingEstimateIsCautiousAndStepsUp() {
        XCTAssertEqual(PaceEngine.estimatedVDOT(yearsRunning: 0.5, weeklyMinutes: 100), 30)
        XCTAssertEqual(PaceEngine.estimatedVDOT(yearsRunning: 2, weeklyMinutes: 100), 34)
        XCTAssertEqual(PaceEngine.estimatedVDOT(yearsRunning: 5, weeklyMinutes: 100), 38)
        XCTAssertEqual(PaceEngine.estimatedVDOT(yearsRunning: 5, weeklyMinutes: 300), 40)
    }

    func testAdjustmentsAndOverridesReachThePaces() {
        let base = Paces.make(vdot: 50, goalPaceSecPerKm: 250)
        let faster = Paces.make(vdot: 50, goalPaceSecPerKm: 250, adjustments: [.threshold: 2])
        XCTAssertEqual(faster.pace(.threshold), base.pace(.threshold) / 1.02, accuracy: 0.01)
        XCTAssertEqual(faster.pace(.easy), base.pace(.easy), accuracy: 0.001, "only the adapted group moves")

        let own = Paces.make(vdot: 50, goalPaceSecPerKm: 250, adjustments: [.easy: 3], overrides: [.easy: 330])
        XCTAssertEqual(own.pace(.easy), 330, "a pace the runner sets is used as it is")
        XCTAssertEqual(own.pace(.goal), 250)
    }

    func testFormatting() {
        XCTAssertEqual(Fmt.clock(255.4), "4:15")
        XCTAssertEqual(Fmt.clock(3725), "1:02:05")
        XCTAssertEqual(Fmt.pace(255.4, miles: false), "4:15 /km")
        XCTAssertEqual(Fmt.pace(300, miles: true), "8:03 /mi")
        XCTAssertEqual(Fmt.minutes(45), "45 min")
        XCTAssertEqual(Fmt.minutes(90), "1 h 30 min")
        XCTAssertEqual(Fmt.distance(10, miles: false), "10.0 km")
        XCTAssertEqual(Fmt.distance(10, miles: true), "6.2 mi")
    }
}

// MARK: - Adaptation

@MainActor
final class AdaptationTests: XCTestCase {

    private func session(_ kind: SessionKind, planned: Int = 40, actual: Int? = nil, rpe: Int?, daysAgo: Int = 3,
                         pain: Bool = false, note: String = "") -> PlanSession {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let s = PlanSession(week: 1, day: 0, date: day, kind: kind, minutes: planned, progress: 0.5)
        s.status = .done
        s.rpe = rpe
        s.actualMinutes = actual ?? planned
        s.pain = pain
        s.note = note
        return s
    }

    func testStepTable() {
        XCTAssertEqual(Adaptation.stepFor(-3), 3)
        XCTAssertEqual(Adaptation.stepFor(-2), 2)
        XCTAssertEqual(Adaptation.stepFor(-1), 1)
        XCTAssertEqual(Adaptation.stepFor(0), 0)
        XCTAssertEqual(Adaptation.stepFor(0.75), 0)
        XCTAssertEqual(Adaptation.stepFor(1.2), -1)
        XCTAssertEqual(Adaptation.stepFor(2), -2)
        XCTAssertEqual(Adaptation.stepFor(3), -3)
    }

    func testExpectedEffort() {
        XCTAssertEqual(Adaptation.expectedRPE(session(.lightThreshold, rpe: 6)) ?? 0, 6.5, accuracy: 0.001)
        XCTAssertEqual(Adaptation.expectedRPE(session(.easy, planned: 45, rpe: 3)) ?? 0, 3.5, accuracy: 0.001)
        XCTAssertEqual(Adaptation.expectedRPE(session(.vo2Reps, rpe: 8)) ?? 0, 8, accuracy: 0.001)
        // running a lot longer than planned should be expected to feel harder (+0.5 for the last 30 minutes beyond the grace)
        XCTAssertEqual(Adaptation.expectedRPE(session(.lightThreshold, planned: 40, actual: 100, rpe: 7)) ?? 0, 7.0, accuracy: 0.001)
        XCTAssertNil(Adaptation.expectedRPE(session(.strength, rpe: 5)), "strength is not in an adapting group")
    }

    func testEasyFeelingEffortSpeedsTheGroupUpToTheCap() {
        let logs = [session(.cruise, rpe: 4, daysAgo: 9), session(.cruise, rpe: 4, daysAgo: 6), session(.cruise, rpe: 4, daysAgo: 3)]
        let adj = Adaptation.compute(sessions: logs, since: .distantPast)
        XCTAssertEqual(adj[.threshold]?.off ?? 0, 3, accuracy: 0.001, "three easy-feeling sessions hit the +3% cap and stop there")
        XCTAssertEqual(adj[.threshold]?.n, 3)
        XCTAssertEqual(adj[.easy]?.n, 0, "other groups are untouched")
        XCTAssertEqual(adj[.vo2]?.off ?? 0, 0, accuracy: 0.001)
    }

    func testHardFeelingEffortSlowsTheGroup() {
        let adj = Adaptation.compute(sessions: [session(.vo2Reps, rpe: 10)], since: .distantPast)
        XCTAssertLessThan(adj[.vo2]?.off ?? 0, 0)
        XCTAssertGreaterThanOrEqual(adj[.vo2]?.off ?? 0, -6, "never past the slow-down cap")
    }

    func testEasyRunsMoveInHalfSteps() {
        let adj = Adaptation.compute(sessions: [session(.easy, planned: 45, rpe: 1)], since: .distantPast)
        XCTAssertEqual(adj[.easy]?.off ?? 0, 1.5, accuracy: 0.001, "a +3 step on the easy group is halved")
    }

    func testPainIsNeverUsed() {
        let adj = Adaptation.compute(sessions: [session(.cruise, rpe: 10, pain: true)], since: .distantPast)
        XCTAssertEqual(adj[.threshold]?.n, 0)
        XCTAssertEqual(adj[.threshold]?.off ?? 1, 0, accuracy: 0.001)
    }

    func testUnratedAndSkippedAreIgnored() {
        let unrated = session(.cruise, rpe: nil)
        let skipped = session(.cruise, rpe: 9)
        skipped.status = .skipped
        let adj = Adaptation.compute(sessions: [unrated, skipped], since: .distantPast)
        XCTAssertEqual(adj[.threshold]?.n, 0)
    }

    func testResettingStartsAgainFromTodayOnward() {
        let logs = [session(.cruise, rpe: 4, daysAgo: 3)]
        XCTAssertEqual(Adaptation.compute(sessions: logs, since: Date())[.threshold]?.n, 0, "runs before the reset do not count")
        XCTAssertEqual(Adaptation.compute(sessions: logs, since: .distantPast)[.threshold]?.n, 1)
    }

    func testANoteBlamingSleepHalvesAHardGap() {
        let withNote = session(.cruise, rpe: 9, note: "Slept badly, felt rubbish")
        withNote.feedback = FeedbackReader.read(withNote.note, context: FeedbackContext(basePaceSec: 300, miles: false))
        let plain = session(.cruise, rpe: 9)
        let a = Adaptation.deviation(withNote) ?? 0
        let b = Adaptation.deviation(plain) ?? 0
        XCTAssertGreaterThan(b, 0)
        XCTAssertLessThan(a, b, "when the note blames something outside the plan the hard gap counts for less")
    }

    func testAnIgnoredOrEditedNoteAddsNothing() {
        let s = session(.cruise, rpe: 9, note: "Failed to finish the last two reps")
        s.feedback = FeedbackReader.read(s.note, context: FeedbackContext(basePaceSec: 300, miles: false))
        let counted = Adaptation.noteEffect(s)
        XCTAssertTrue(counted.on)
        s.noteIgnored = true
        XCTAssertFalse(Adaptation.noteEffect(s).on)
        s.noteIgnored = false
        s.note = "Failed to finish the last two reps, and then some"      // edited after it was read
        XCTAssertFalse(Adaptation.noteEffect(s).on, "a stale reading is never used")
    }

    func testRatingsReachTheDisplayedPaces() {
        let profile = RunnerProfile()
        profile.vdot = 50
        let before = profile.paces(sessions: []).pace(.threshold)
        let after = profile.paces(sessions: [session(.cruise, rpe: 4, daysAgo: 3)]).pace(.threshold)
        XCTAssertLessThan(after, before, "an easy-feeling threshold session makes threshold pace faster")
    }
}

// MARK: - Reading a note

final class FeedbackReaderTests: XCTestCase {
    private let ctx = FeedbackContext(basePaceSec: 300, miles: false)
    private func read(_ s: String) -> FeedbackRead { FeedbackReader.read(s, context: ctx) }

    func testNothingSaidChangesNothing() {
        XCTAssertEqual(read("ok").dev, 0)
        XCTAssertEqual(read("Easy run, felt fine").dev, 0)
        XCTAssertEqual(read("ok").summary, "Nothing here changes the plan.")
    }

    func testAPaceCutIsMeasured() {
        let r = read("Had to drop from 4:10 to 4:40 per km, legs were dead")
        XCTAssertEqual(r.cutFromSec, 250)
        XCTAssertEqual(r.cutToSec, 280)
        XCTAssertEqual(r.cutPct ?? 0, 30.0 / 280.0, accuracy: 0.001)
        XCTAssertEqual(r.dev, 1.5)
        XCTAssertTrue(r.ease)
    }

    func testFailingToFinishIsTheBiggestSignal() {
        let r = read("Failed to finish the last two reps")
        XCTAssertTrue(r.fail)
        XCTAssertEqual(r.dev, 1.5)
    }

    func testFeelingGreatPointsTheOtherWay() {
        XCTAssertEqual(read("Felt great, could have gone harder").dev, -0.5)
    }

    func testNegationIsRespected() {
        XCTAssertEqual(read("It wasn't too easy").dev, 0.5)
    }

    func testOutsideCausesAreSpotted() {
        let sleep = read("Slept badly, felt rubbish")
        XCTAssertEqual(sleep.cause, "sleep")
        XCTAssertTrue(sleep.off)
        XCTAssertEqual(sleep.dev, 0.5)

        let weather = read("Ran in the rain with a strong headwind")
        XCTAssertEqual(weather.cause, "weather")
        XCTAssertEqual(weather.dev, 0, "a cause on its own is not a reason to change the plan")
    }

    func testResultIsAlwaysBounded() {
        for text in ["terrible awful brutal struggled grim failed to finish gave up bonked", "way too easy piece of cake", String(repeating: "legs heavy ", count: 80)] {
            let r = read(text)
            XCTAssertGreaterThanOrEqual(r.dev, -1)
            XCTAssertLessThanOrEqual(r.dev, 1.5)
        }
    }
}

// MARK: - The plan

final class PlanGeneratorTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d)) ?? Date()
    }

    private func profile(planStart: Date? = nil) -> RunnerProfile {
        let p = RunnerProfile()
        p.vdot = 45
        p.weeklyMinutes = 150
        p.longestRunMinutes = 60
        p.goalDistanceKm = 10
        p.availableDays = [1, 3, 5, 6]
        p.longRunDay = 6
        p.runsPerWeekWanted = 4
        p.planStart = planStart ?? date(2026, 11, 9)     // a Monday
        return p
    }

    func testCalendarHelpers() {
        XCTAssertEqual(PlanGenerator.dayIndex(date(2026, 11, 9)), 0, "Monday")
        XCTAssertEqual(PlanGenerator.dayIndex(date(2026, 11, 15)), 6, "Sunday")
        XCTAssertEqual(PlanGenerator.mondayOnOrAfter(date(2026, 11, 9)), date(2026, 11, 9))
        XCTAssertEqual(PlanGenerator.mondayOnOrAfter(date(2026, 11, 10)), date(2026, 11, 16))
        XCTAssertEqual(PlanGenerator.mondayOf(date(2026, 11, 14)), date(2026, 11, 9))
    }

    func testRunDaysKeepTheLongRunAndSpreadTheRest() {
        let r = PlanGenerator.chooseRunDays(available: [0, 1, 2, 3, 4, 5, 6], longDay: 6, wanted: 4)
        XCTAssertEqual(r.days.count, 4)
        XCTAssertTrue(r.days.contains(6))
        XCTAssertEqual(r.long, 6)
        XCTAssertEqual(PlanGenerator.chooseRunDays(available: [2, 4], longDay: 6, wanted: 4).days, [2, 4], "never more days than the runner can run")
        XCTAssertEqual(PlanGenerator.chooseRunDays(available: [2, 4], longDay: 6, wanted: 4).long, 4, "a long run day that is not available moves to the last day that is")
    }

    func testHardDaysAvoidTheLongRun() {
        let q = PlanGenerator.qualityDays(runDays: [1, 3, 5, 6], longDay: 6, count: 2)
        XCTAssertEqual(q, [1, 3])
        XCTAssertFalse(q.contains(5), "Saturday is the day before the long run")
    }

    func testTwelveWeeksOnTheRightDays() {
        let p = profile()
        let plan = PlanGenerator.generate(for: p)
        XCTAssertEqual(Set(plan.map { $0.week }), Set(1...12))
        let start = date(2026, 11, 9)
        let end = cal.date(byAdding: .day, value: 84, to: start) ?? start
        for s in plan {
            XCTAssertGreaterThanOrEqual(s.date, start)
            XCTAssertLessThan(s.date, end)
            XCTAssertEqual(s.day, PlanGenerator.dayIndex(s.date), "the stored day must match the date")
            XCTAssertTrue(p.availableDays.contains(s.day), "runs only on days the runner can run")
        }
    }

    func testEachWeekHasOneLongRunAndAtMostTwoHardSessions() {
        let plan = PlanGenerator.generate(for: profile())
        for w in 1...12 {
            let week = plan.filter { $0.week == w }
            XCTAssertEqual(week.filter { $0.kind == .longRun }.count, 1, "week \(w)")
            XCTAssertEqual(week.filter { $0.kind == .longRun }.first?.day, 6, "week \(w) long run on Sunday")
            let hard = week.filter { SessionLibrary.info($0.kind).load == .hard }
            XCTAssertLessThanOrEqual(hard.count, 2, "week \(w)")
            for h in hard {
                XCTAssertFalse([5, 6].contains(h.day), "week \(w): no hard session on the long run or the day before it")
            }
        }
    }

    func testEveryFourthWeekHasATest() {
        let plan = PlanGenerator.generate(for: profile())
        for w in [4, 8, 12] {
            let kinds = plan.filter { $0.week == w }.map { $0.kind }
            XCTAssertTrue(kinds.contains(.test30) || kinds.contains(.test3k), "week \(w) has a test")
        }
    }

    func testWithoutABenchmarkWeekOneStartsWithATimeTrial() {
        let p = profile()
        p.benchmarkKnown = false
        let kinds = PlanGenerator.generate(for: p).filter { $0.week == 1 }.map { $0.kind }
        XCTAssertTrue(kinds.contains(.test30))
    }

    func testPlanShortensToARaceAndEndsOnIt() {
        let p = profile()
        p.hasRaceDate = true
        p.raceDate = cal.date(byAdding: .day, value: 75, to: date(2026, 11, 9)) ?? Date()     // a Saturday in week 11
        let plan = PlanGenerator.generate(for: p)
        XCTAssertEqual(plan.map { $0.week }.max(), 11)
        let race = plan.filter { $0.kind == .race }
        XCTAssertEqual(race.count, 1)
        XCTAssertEqual(race.first?.date, p.raceDate)
        XCTAssertTrue(plan.contains { $0.kind == .openers && $0.week == 11 }, "openers the day before")
    }

    func testStrengthOnlyWhenAskedFor() {
        XCTAssertFalse(PlanGenerator.generate(for: profile()).contains { $0.kind == .strength })
        let p = profile()
        p.doesStrength = true
        let plan = PlanGenerator.generate(for: p)
        XCTAssertTrue(plan.contains { $0.kind == .strength })
        XCTAssertLessThanOrEqual(Dictionary(grouping: plan.filter { $0.kind == .strength }, by: { $0.week }).values.map { $0.count }.max() ?? 0, 2)
    }

    func testTheNextPlanContinuesTheWeekNumbers() {
        let p = profile()
        let first = PlanGenerator.generate(for: p)
        for s in first.prefix(30) { s.status = .done; s.actualMinutes = s.plannedMinutes }
        let next = PlanGenerator.startNextPlan(profile: p, sessions: first)
        XCTAssertEqual(p.weekOffset, 12)
        XCTAssertEqual(Set(next.map { $0.week }), Set(13...24))
        XCTAssertEqual(PlanGenerator.dayIndex(p.planStart), 0, "the next plan starts on a Monday")
        XCTAssertGreaterThan(p.planStart, first.map { $0.date }.max() ?? .distantFuture)
    }
}

// MARK: - The session library

final class SessionLibraryTests: XCTestCase {

    func testEverySessionHasAnExplanationAndAnHonestEvidenceNote() {
        for k in SessionKind.allCases {
            let i = SessionLibrary.info(k)
            XCTAssertFalse(i.name.isEmpty, "\(k)")
            XCTAssertFalse(i.why.isEmpty, "\(k)")
            XCTAssertFalse(i.evidenceNote.isEmpty, "\(k)")
        }
    }

    func testSessionsBuildAndAddUp() {
        let ctx = BuildContext(goalKm: 10, vdot: 45)
        for k in SessionKind.allCases where k != .strength && k != .race {
            let segs = SessionLibrary.segments(k, minutes: 45, p: 0.5, ctx: ctx)
            XCTAssertFalse(segs.isEmpty, "\(k)")
            let total = SessionLibrary.totalMinutes(k, minutes: 45, p: 0.5, ctx: ctx)
            XCTAssertEqual(Double(total), Double(SessionLibrary.totalSeconds(segs)) / 60, accuracy: 2.6, "\(k) (lengths are rounded to 5 minutes)")
        }
    }
}
