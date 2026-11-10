import Foundation

// MARK: - Session structure

/// One piece of a session. Pace comes from `zone` (times `mult`), so a session re-prices itself whenever the paces change.
struct Step: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var seconds: Int
    var zone: Zone
    var mult: Double = 1        // multiplies the zone pace (1.04 = 4% slower)
    var byEffort: Bool = false  // hills, tests and strides: go by feel, the pace is only a guide
    var work: Bool = false      // a hard piece, as opposed to warm-up, cool-down and recoveries
}

enum Segment {
    case single(Step)
    case reps(title: String, count: Int, steps: [Step])
}

struct BuildContext {
    var goalKm: Double
    var vdot: Double
}

struct KindInfo {
    let name: String
    let group: TrainingGroup?
    let load: Load
    let evidence: Evidence
    let why: String
    let evidenceNote: String
    let sources: [String]
}

// MARK: - Library

/// Every session, with what it is for and what the evidence does and does not show.
///
/// IMPORTANT: the evidence notes and references below are written from my knowledge of the running literature and I could not
/// open the papers while writing them. Check each one against the original before you publish the app, and fix or remove any
/// that do not say what the note claims.
enum SessionLibrary {

    static func info(_ k: SessionKind) -> KindInfo {
        switch k {
        case .easy:
            return KindInfo(name: "Easy run", group: .easy, load: .easy, evidence: .practice,
                why: "Most of your running should feel comfortable. It builds the aerobic base the hard days sit on and lets you recover between them.",
                evidenceNote: "Standard practice. Studies of how elite and well-trained endurance athletes spread their training (Seiler 2010, Stöggl and Sperlich 2014) point to a large share of easy work, but they were not run only on runners and none tests an 'easy run' as a stand-alone session.",
                sources: ["Seiler S. What is best practice for training intensity and duration distribution in endurance athletes? Int J Sports Physiol Perform, 2010", "Stöggl T, Sperlich B. Polarized training has greater impact on key endurance variables than threshold, high intensity, or high volume training. Front Physiol, 2014"])
        case .strides:
            return KindInfo(name: "Easy run with strides", group: .easy, load: .easy, evidence: .practice,
                why: "Easy running followed by short, fast, relaxed strides. They keep your legs used to speed without the cost of a hard session.",
                evidenceNote: "Coaching practice. Sprint and plyometric work is listed among methods linked to better running economy (Barnes and Kilding 2015 review), but strides as a stand-alone format have not been trialled.",
                sources: ["Barnes KR, Kilding AE. Strategies to improve running economy. Sports Med, 2015"])
        case .recovery:
            return KindInfo(name: "Recovery jog", group: nil, load: .easy, evidence: .practice,
                why: "Very easy time on your feet when you want to keep the habit but a normal run would cost too much.",
                evidenceNote: "Standard practice. No trial needed, and walking instead is fine.",
                sources: [])
        case .longRun:
            return KindInfo(name: "Long run", group: .easy, load: .easy, evidence: .practice,
                why: "The longest run of your week. It builds endurance, tendon and muscle resilience, and practice at fuelling.",
                evidenceNote: "Standard practice. How fast long runs and weekly distance can safely grow is not settled: Nielsen and colleagues found more injuries after sharp jumps in weekly distance, but the often-quoted '10% rule' has little direct support.",
                sources: ["Nielsen RO et al. Excessive progression in weekly running distance and risk of running-related injuries. J Orthop Sports Phys Ther, 2014"])
        case .openers:
            return KindInfo(name: "Pre-race openers", group: nil, load: .easy, evidence: .practice,
                why: "A short easy run with a few strides the day before a race or test so the legs feel sharp without being tired.",
                evidenceNote: "Standard pre-race practice.",
                sources: [])
        case .lightThreshold:
            return KindInfo(name: "Light threshold", group: .threshold, load: .medium, evidence: .practice,
                why: "Two blocks a touch under threshold pace. It builds the same ability as a threshold day at about half the dose, which suits the start of a plan.",
                evidenceNote: "Standard coaching format (Daniels). No trial of this exact session.",
                sources: ["Daniels J. Daniels' Running Formula"])
        case .cruise:
            return KindInfo(name: "Cruise intervals", group: .threshold, load: .medium, evidence: .practice,
                why: "Several 5 to 6 minute blocks at threshold pace with a one minute jog. The short breaks let you spend more total time at threshold than a single hard run would.",
                evidenceNote: "A Daniels staple. Described in coaching texts, not trialled in this exact form.",
                sources: ["Daniels J. Daniels' Running Formula"])
        case .overUnders:
            return KindInfo(name: "Over-unders", group: .threshold, load: .medium, evidence: .practice,
                why: "Alternating two minutes just under threshold pace with one minute just over it, with no rest. It teaches you to keep running well straight after a surge.",
                evidenceNote: "Coaching practice. I know of no trial of over-unders in runners, so treat them as a race-feel swap for a threshold day, not a proven better one.",
                sources: [])
        case .norwegianThreshold:
            return KindInfo(name: "Norwegian-style threshold", group: .threshold, load: .medium, evidence: .practice,
                why: "Longer reps held slightly under threshold with a one minute jog. The point is control: you should finish feeling you could do another rep.",
                evidenceNote: "Based on the published description of the Norwegian threshold approach (lactate-guided, high volume, mostly sub-threshold). The evidence is descriptive and from elite athletes. This version uses pace and effort because most runners have no lactate meter.",
                sources: ["Casado A, Foster C, Bakken M, Tjelta LI. Does lactate-guided threshold interval training within a high-volume low-intensity approach represent the next step in the evolution of distance running training? Int J Environ Res Public Health, 2023"])
        case .hillAttacks:
            return KindInfo(name: "Hill attacks", group: .threshold, load: .medium, evidence: .practice,
                why: "Hold threshold effort up a hill, then surge over the top. It trains the exact moment a hilly race gets decided.",
                evidenceNote: "Coaching practice, no trial.",
                sources: [])
        case .longReps:
            return KindInfo(name: "Long reps (Seiler style)", group: .vo2, load: .hard, evidence: .practice,
                why: "Three or four 8 minute reps just above threshold. It builds a lot of time near VO2max without the all-out feel of shorter reps.",
                evidenceNote: "Popularised by Stephen Seiler from work with rowers and cross-country skiers. I know of no trial of this exact format in runners, so the paces here are cautious and the last rep should be the hardest.",
                sources: ["Seiler S. What is best practice for training intensity and duration distribution in endurance athletes? Int J Sports Physiol Perform, 2010"])
        case .norwegian4x4:
            return KindInfo(name: "4 × 4 min (Norwegian)", group: .vo2, load: .hard, evidence: .study,
                why: "Four 4 minute reps at a hard but even pace with 3 minute jogs. A classic way to raise VO2max.",
                evidenceNote: "Helgerud and colleagues (2007) compared 4 × 4 min at 90 to 95% of max heart rate with other formats and found a bigger VO2max gain. It was a short study in young, healthy, moderately trained men, so it does not prove the same for every runner.",
                sources: ["Helgerud J et al. Aerobic high-intensity intervals improve VO2max more than moderate training. Med Sci Sports Exerc, 2007"])
        case .vo2Reps:
            return KindInfo(name: "VO2max reps", group: .vo2, load: .hard, evidence: .practice,
                why: "Several 3 minute reps at roughly 3K to 5K race effort with a jog of about the same length. They raise the top end of your aerobic engine.",
                evidenceNote: "Standard format (Daniels, Billat). Reviews of interval programming support hard intervals in general, but do not single out 3 minute reps as best.",
                sources: ["Buchheit M, Laursen PB. High-intensity interval training, solutions to the programming puzzle. Sports Med, 2013", "Billat VL. Interval training for performance: a scientific and empirical practice. Sports Med, 2001"])
        case .thirtyFifteen:
            return KindInfo(name: "30/15 intervals", group: .vo2, load: .hard, evidence: .practice,
                why: "30 seconds fast, 15 seconds easy, repeated. The short breaks keep you close to VO2max for a long total time while each effort stays manageable.",
                evidenceNote: "Short intervals like these are well covered in the interval-training literature (Buchheit and Laursen 2013, Billat 2001). This exact set and rep count is my own design, not a published protocol.",
                sources: ["Buchheit M, Laursen PB. High-intensity interval training, solutions to the programming puzzle. Sports Med, 2013", "Billat VL. Interval training for performance: a scientific and empirical practice. Sports Med, 2001"])
        case .hillRepeats:
            return KindInfo(name: "Hill repeats", group: .vo2, load: .hard, evidence: .practice,
                why: "Hard two minute efforts up a hill with a jog down. The hill builds strength and power while limiting the pounding of fast flat running.",
                evidenceNote: "Coaching practice. Hill training is often recommended for running economy but I know of no trial of this exact session.",
                sources: ["Barnes KR, Kilding AE. Strategies to improve running economy. Sports Med, 2015"])
        case .hillSprints:
            return KindInfo(name: "Hill sprints", group: nil, load: .medium, evidence: .practice,
                why: "Very short all-out sprints up a steep hill with a full walk back. They build power and running economy with very little fatigue.",
                evidenceNote: "Coaching practice, backed in general terms by the sprint and plyometric evidence for running economy (Barnes and Kilding 2015). Not trialled in this exact form.",
                sources: ["Barnes KR, Kilding AE. Strategies to improve running economy. Sports Med, 2015"])
        case .fartlek:
            return KindInfo(name: "40 minute fartlek", group: nil, load: .hard, evidence: .practice,
                why: "Forty minutes with a pace floor you never drop below and a surge every five minutes. It is a stand-in for the stop-start middle of a race.",
                evidenceNote: "My own design from standard fartlek practice. Not a published protocol.",
                sources: [])
        case .goalPace:
            return KindInfo(name: "Goal-pace blocks", group: nil, load: .hard, evidence: .practice,
                why: "Blocks at the pace you want to race at, with short easy breaks. Specificity: you learn what the pace feels like on tired legs.",
                evidenceNote: "Standard race-specific practice, no trial of its own.",
                sources: [])
        case .leadKick:
            return KindInfo(name: "Lead-out and kick", group: nil, load: .hard, evidence: .practice,
                why: "Two minutes at threshold, then a 20 second kick, five times. It rehearses a race finish: sprinting after someone has already taken something out of you.",
                evidenceNote: "Coaching practice, my own layout.",
                sources: [])
        case .test30:
            return KindInfo(name: "30 minute time trial", group: nil, load: .hard, evidence: .practice,
                why: "Run as far as you can in 30 minutes at an even effort. Your result tells the app how fit you are, so it can set your paces.",
                evidenceNote: "A benchmark, not training. Compare it with your own last one, not with anyone else's.",
                sources: ["Friel J. The Triathlete's Training Bible (30 minute test)"])
        case .test3k:
            return KindInfo(name: "3 km time trial", group: nil, load: .hard, evidence: .practice,
                why: "A flat 3 km at the best even pace you can hold. A shorter benchmark of your top-end speed.",
                evidenceNote: "A benchmark, not training. Warm up well and pace it evenly.",
                sources: [])
        case .race:
            return KindInfo(name: "Race", group: nil, load: .hard, evidence: .practice,
                why: "Nothing trains racing like racing. Treat a race as your hard session for the week.",
                evidenceNote: "Specificity.",
                sources: [])
        case .strength:
            return KindInfo(name: "Strength for runners", group: nil, load: .easy, evidence: .study,
                why: "A short session of single-leg strength, calves and a little jumping. It supports running economy and helps your legs cope with the load.",
                evidenceNote: "A systematic review of strength training in distance runners (Blagrove and colleagues 2018) found improvements in running economy and performance. It is a review of many different programmes, not one trial of this circuit.",
                sources: ["Blagrove RC, Howatson G, Hayes PR. Effects of strength training on the physiological determinants of middle- and long-distance running performance: a systematic review. Sports Med, 2018"])
        }
    }

    static var strengthExercises: [String] {
        ["Single-leg squat to a box, 3 × 8 each side",
         "Single-leg calf raise (straight and bent knee), 3 × 12 each side",
         "Single-leg glute bridge, 3 × 10 each side",
         "Step-ups, 3 × 8 each side",
         "Side plank, 2 × 30 s each side",
         "Pogo hops, 3 × 20 (skip if you have achilles or calf niggles)"]
    }

    // MARK: building

    private static func lerp(_ a: Int, _ b: Int, _ p: Double) -> Int {
        Int((Double(a) + (Double(b) - Double(a)) * p).rounded())
    }
    private static func warm(_ m: Int) -> Segment { .single(Step(label: "Warm-up jog", seconds: m * 60, zone: .easy)) }
    private static func cool(_ m: Int = 8) -> Segment { .single(Step(label: "Cool-down jog", seconds: m * 60, zone: .easy)) }
    private static func work(_ label: String, _ sec: Int, _ zone: Zone, mult: Double = 1, effort: Bool = false) -> Step {
        Step(label: label, seconds: sec, zone: zone, mult: mult, byEffort: effort, work: true)
    }
    private static func rest(_ sec: Int, _ label: String = "Easy jog") -> Step {
        Step(label: label, seconds: sec, zone: .recovery)
    }

    /// The structure of a session. `p` (0 to 1) is how far through its block it sits, which sets rep counts.
    static func segments(_ k: SessionKind, minutes: Int, p: Double, ctx: BuildContext) -> [Segment] {
        switch k {
        case .easy:
            return [.single(Step(label: "Easy run", seconds: minutes * 60, zone: .easy))]
        case .recovery:
            return [.single(Step(label: "Recovery jog", seconds: minutes * 60, zone: .recovery))]
        case .longRun:
            if ctx.goalKm >= 10 && p >= 0.5 && minutes >= 60 {
                let fin = min(20, minutes / 4)
                return [.single(Step(label: "Easy running", seconds: (minutes - fin) * 60, zone: .easy)),
                        .single(Step(label: "Steady finish", seconds: fin * 60, zone: .steady))]
            }
            return [.single(Step(label: "Long easy run", seconds: minutes * 60, zone: .easy))]
        case .strides:
            let tail = 8
            return [.single(Step(label: "Easy run", seconds: max(10, minutes - tail) * 60, zone: .easy)),
                    .reps(title: "Strides", count: 6, steps: [work("Stride, fast and relaxed", 20, .repetition, effort: true), rest(60, "Walk or jog back")])]
        case .openers:
            return [.single(Step(label: "Easy run", seconds: max(10, minutes - 6) * 60, zone: .easy)),
                    .reps(title: "Strides", count: 4, steps: [work("Stride", 20, .repetition, effort: true), rest(60, "Walk or jog back")])]
        case .lightThreshold:
            let d = lerp(10, 15, p)
            return [warm(12), .reps(title: "Light threshold", count: 2, steps: [work("Just under threshold", d * 60, .threshold, mult: 1.04), rest(180)]), cool()]
        case .cruise:
            let n = lerp(3, 5, p), d = p < 0.5 ? 5 : 6
            return [warm(12), .reps(title: "Cruise intervals", count: n, steps: [work("Threshold", d * 60, .threshold), rest(60)]), cool()]
        case .overUnders:
            let k = lerp(3, 4, p)
            var segs: [Segment] = [warm(12)]
            for i in 0..<3 {
                segs.append(.reps(title: "Set \(i + 1)", count: k, steps: [work("Under", 120, .threshold, mult: 1.05), work("Over", 60, .threshold, mult: 0.96)]))
                if i < 2 { segs.append(.single(rest(180))) }
            }
            segs.append(cool())
            return segs
        case .norwegianThreshold:
            let n = lerp(4, 6, p)
            return [warm(12), .reps(title: "Controlled threshold", count: n, steps: [work("Just under threshold", 360, .threshold, mult: 1.03), rest(60)]), cool()]
        case .hillAttacks:
            let n = lerp(3, 4, p)
            return [warm(12), .reps(title: "Hill attacks", count: n, steps: [work("Threshold effort uphill", 300, .threshold, effort: true), work("Surge over the top", 30, .repetition, effort: true), rest(180)]), cool()]
        case .longReps:
            let n = lerp(3, 4, p)
            return [warm(12), .reps(title: "Long reps", count: n, steps: [work("Just above threshold", 480, .interval, mult: 1.06), rest(180)]), cool()]
        case .norwegian4x4:
            let n = lerp(3, 4, p)
            return [warm(12), .reps(title: "4 × 4", count: n, steps: [work("Hard and even", 240, .interval, mult: 1.03), rest(180)]), cool()]
        case .vo2Reps:
            let n = lerp(4, 6, p)
            return [warm(12), .reps(title: "VO2max reps", count: n, steps: [work("Hard, 3K to 5K effort", 180, .interval), rest(150)]), cool()]
        case .thirtyFifteen:
            let sets = p < 0.5 ? 2 : 3
            var segs: [Segment] = [warm(12)]
            for i in 0..<sets {
                segs.append(.reps(title: "Set \(i + 1)", count: 13, steps: [work("30 s fast", 30, .interval), rest(15, "15 s easy")]))
                if i < sets - 1 { segs.append(.single(rest(180))) }
            }
            segs.append(cool())
            return segs
        case .hillRepeats:
            let n = lerp(5, 8, p)
            return [warm(15), .reps(title: "Hill repeats", count: n, steps: [work("Hard uphill, by effort", 120, .interval, effort: true), rest(120, "Jog back down")]), cool()]
        case .hillSprints:
            let n = lerp(6, 10, p)
            return [warm(15), .reps(title: "Hill sprints", count: n, steps: [work("All-out sprint, steep hill", 8, .repetition, effort: true), rest(90, "Walk back down")]), cool()]
        case .fartlek:
            let n = lerp(6, 8, p)
            return [warm(10), .reps(title: "5 minute blocks", count: n, steps: [work("Floor pace", 210, .threshold, mult: 1.06), work("Surge", 30, .interval), work("Floor pace", 60, .threshold, mult: 1.06)]), cool()]
        case .goalPace:
            var count = 4, secs = 240, gap = 120
            if ctx.goalKm <= 5.5 { count = lerp(4, 6, p); secs = 240; gap = 120 }
            else if ctx.goalKm <= 11 { count = lerp(3, 5, p); secs = 480; gap = 120 }
            else if ctx.goalKm <= 22 { count = 3; secs = lerp(10, 14, p) * 60; gap = 120 }
            else { count = lerp(2, 3, p); secs = lerp(15, 25, p) * 60; gap = 180 }
            return [warm(12), .reps(title: "Goal-pace blocks", count: count, steps: [work("At goal pace", secs, .goal), rest(gap)]), cool()]
        case .leadKick:
            return [warm(12), .reps(title: "Lead-out and kick", count: 5, steps: [work("Threshold", 120, .threshold), work("Kick", 20, .repetition, effort: true), rest(180)]), cool()]
        case .test30:
            return [warm(12), .single(work("30 minute time trial, even effort", 1800, .threshold, mult: 0.99, effort: true)), cool(10)]
        case .test3k:
            let est = Int(PaceEngine.predictSeconds(vdot: ctx.vdot, distanceM: 3000))
            return [warm(15), .single(work("3 km time trial, even effort", est, .interval, mult: 1.02, effort: true)), cool(10)]
        case .race:
            let est = Int(PaceEngine.predictSeconds(vdot: ctx.vdot, distanceM: ctx.goalKm * 1000))
            return [warm(15), .single(work("Race", est, .goal, effort: true)), cool(10)]
        case .strength:
            return [.single(Step(label: "Strength circuit (see the list)", seconds: minutes * 60, zone: .recovery))]
        }
    }

    static func flatten(_ segments: [Segment]) -> [Step] {
        var out: [Step] = []
        for s in segments {
            switch s {
            case .single(let st): out.append(st)
            case .reps(_, let count, let steps):
                for _ in 0..<count { out.append(contentsOf: steps) }
            }
        }
        return out
    }

    static func totalSeconds(_ segments: [Segment]) -> Int {
        flatten(segments).reduce(0) { $0 + $1.seconds }
    }

    /// Session length in whole minutes, rounded to 5.
    static func totalMinutes(_ k: SessionKind, minutes: Int, p: Double, ctx: BuildContext) -> Int {
        let m = Int((Double(totalSeconds(segments(k, minutes: minutes, p: p, ctx: ctx))) / 60.0 / 5.0).rounded()) * 5
        return max(m, 5)
    }

    /// Short text a runner can paste into a watch app or notes.
    static func text(_ k: SessionKind, segments: [Segment], paces: Paces, miles: Bool) -> String {
        var lines = [info(k).name]
        func line(_ s: Step) -> String {
            let p = s.zone == .recovery && !s.work ? "" : " @ " + Fmt.pace(paces.pace(s.zone, mult: s.mult), miles: miles) + (s.byEffort ? " (by effort)" : "")
            return Fmt.seconds(s.seconds) + " " + s.label.lowercased() + p
        }
        for seg in segments {
            switch seg {
            case .single(let s): lines.append(line(s))
            case .reps(let title, let count, let steps):
                lines.append("\(count) × \(title.lowercased()):")
                for s in steps { lines.append("  " + line(s)) }
            }
        }
        return lines.joined(separator: "\n")
    }
}
