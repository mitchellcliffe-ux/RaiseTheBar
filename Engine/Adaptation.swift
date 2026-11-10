import Foundation

/// How far one group of sessions has been nudged so far, as a % of speed. Positive = faster than the base pace.
struct GroupAdjustment {
    var off: Double = 0
    var n: Int = 0
    var lastStep: Double = 0
    var lastDev: Double = 0
    var lastSd: Double = 0
}

/// The adaptation model, ported from the cycling planner.
///
/// After each rated run the gap between how hard it felt (RPE) and how hard it should have felt is smoothed
/// (60% latest, 40% the one before) and turned into a small step of 0 to 3% of speed, scaled by group and clamped
/// to firm caps. The note the runner wrote adds to the gap (see FeedbackReader), so words can move the plan too.
enum Adaptation {

    static func stepFor(_ sd: Double) -> Double {
        if sd <= -2.5 { return 3 }
        if sd < -1.5 { return 2 }
        if sd < -0.75 { return 1 }
        if sd <= 0.75 { return 0 }
        if sd <= 1.5 { return -1 }
        if sd < 2.5 { return -2 }
        return -3
    }

    /// How hard the run should have felt, allowing for running longer than planned (about +0.5 RPE per extra half hour, capped at +1.5).
    static func expectedRPE(_ s: PlanSession) -> Double? {
        guard let g = s.group else { return nil }
        let grace: Double = g == .easy ? 15 : 25
        var extra = 0.0
        if let m = s.actualMinutes, m > 0, s.plannedMinutes > 0 {
            extra = max(0, Double(m - s.plannedMinutes) - grace)
        }
        return g.targetRPE + min(1.5, (extra / 30.0 * 2.0).rounded() / 4.0)
    }

    /// What the note adds. A note that was edited after it was read, or that the runner switched off, adds nothing.
    static func noteEffect(_ s: PlanSession) -> (add: Double, off: Bool, on: Bool) {
        let t = s.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = s.feedback, !t.isEmpty, !s.noteIgnored, r.text == t else { return (0, false, false) }
        return (min(max(r.dev, -1), 1.5), r.off, true)
    }

    /// The effort gap with the note counted in. If the note blames something outside the plan, the harder-than-planned part counts at half weight.
    static func deviation(_ s: PlanSession, useNote: Bool = true) -> Double? {
        guard let rpe = s.rpe, let expected = expectedRPE(s) else { return nil }
        let e: (add: Double, off: Bool, on: Bool) = useNote ? noteEffect(s) : (0, false, false)
        var dev = Double(rpe) - expected + e.add
        if e.off && dev > 0 { dev *= 0.5 }
        return dev
    }

    static func compute(sessions: [PlanSession], since: Date) -> [TrainingGroup: GroupAdjustment] {
        var out: [TrainingGroup: GroupAdjustment] = [:]
        for g in TrainingGroup.allCases { out[g] = GroupAdjustment() }

        let logs = sessions
            .filter { $0.status == .done && $0.rpe != nil && $0.group != nil && !$0.pain && $0.date >= since }
            .sorted { $0.date < $1.date }

        var previous: [TrainingGroup: Double] = [:]
        for s in logs {
            guard let g = s.group, let dev = deviation(s), var adj = out[g] else { continue }
            let sd: Double
            if let p = previous[g] { sd = 0.6 * dev + 0.4 * p } else { sd = dev }
            let step = stepFor(sd) * g.stepScale
            adj.off = min(max(adj.off + step, -g.capDown), g.capUp)
            adj.n += 1
            adj.lastStep = step
            adj.lastSd = sd
            adj.lastDev = dev
            out[g] = adj
            previous[g] = dev
        }
        return out
    }

    /// Plain-English line for the "How the plan is adapting" page.
    static func describe(_ g: TrainingGroup, _ a: GroupAdjustment) -> String {
        if a.n == 0 { return "No rated sessions yet, so nothing has changed." }
        let dir: String
        if a.off > 0.05 { dir = String(format: "%.1f%% faster than the base pace", a.off) }
        else if a.off < -0.05 { dir = String(format: "%.1f%% slower than the base pace", -a.off) }
        else { dir = "on the base pace" }
        var why = ""
        if a.lastStep > 0 { why = " Your last one felt easier than it should have, so the next ones nudge up." }
        else if a.lastStep < 0 { why = " Your last one felt harder than it should have, so the next ones ease off." }
        else { why = " Your last one felt about right, so nothing moved." }
        return "These sessions are now \(dir), after \(a.n) rated.\(why)"
    }
}
