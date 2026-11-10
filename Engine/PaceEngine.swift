import Foundation

/// One recent race or time trial sets every pace. The maths is the published Daniels and Gilbert
/// oxygen cost and %VO2max-by-duration equations ("VDOT"). The fractions used for each zone below are my
/// approximations of Daniels' published zones, so treat them as a starting point and let the runner override any pace.
enum PaceEngine {

    // MARK: equations

    /// Oxygen cost of running at a speed, in ml/kg/min. Speed in metres per minute.
    static func oxygenCost(velocity v: Double) -> Double {
        -4.60 + 0.182258 * v + 0.000104 * v * v
    }

    /// The share of VO2max a runner can hold for a given time in minutes.
    static func fractionOfMax(minutes t: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
    }

    /// Fitness score from one race or time trial.
    static func vdot(distanceM: Double, seconds: Double) -> Double {
        guard distanceM > 0, seconds > 0 else { return 0 }
        let t = seconds / 60
        return oxygenCost(velocity: distanceM / t) / fractionOfMax(minutes: t)
    }

    /// The speed (metres per minute) that costs a given amount of oxygen.
    static func velocity(forOxygen x: Double) -> Double {
        let a = 0.000104, b = 0.182258, c = -4.60 - x
        return (-b + (b * b - 4 * a * c).squareRoot()) / (2 * a)
    }

    static func secPerKm(vdot: Double, fraction: Double) -> Double {
        let v = velocity(forOxygen: fraction * vdot)
        return 1000.0 / v * 60.0
    }

    /// How long a runner with this score would take over a distance (bisection).
    static func predictSeconds(vdot target: Double, distanceM: Double) -> Double {
        var lo = 120.0, hi = 36_000.0
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if vdot(distanceM: distanceM, seconds: mid) > target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    static func racePace(vdot: Double, distanceKm: Double) -> Double {
        predictSeconds(vdot: vdot, distanceM: distanceKm * 1000) / distanceKm
    }

    /// Cautious starting score for someone who does not know their fitness. The plan then puts a 30 minute test in week 1.
    static func estimatedVDOT(yearsRunning: Double, weeklyMinutes: Int) -> Double {
        var v = yearsRunning < 1 ? 30.0 : (yearsRunning < 3 ? 34.0 : 38.0)
        if weeklyMinutes >= 240 { v += 2 }
        return v
    }

    // MARK: zones

    static func fraction(of zone: Zone) -> Double {
        switch zone {
        case .recovery: return 0.60
        case .easy: return 0.66
        case .steady: return 0.75
        case .goal: return 0.82       // not used, goal pace comes from the goal or the race prediction
        case .threshold: return 0.88
        case .interval: return 1.00
        case .repetition: return 1.10
        }
    }

    /// Rough heart rate bands as a share of max HR. Heart rate lags effort and drifts in heat, so these are a guide only.
    static func hrBand(_ zone: Zone) -> (Double, Double)? {
        switch zone {
        case .recovery: return (0.60, 0.70)
        case .easy: return (0.68, 0.78)
        case .steady: return (0.78, 0.85)
        case .threshold: return (0.86, 0.91)
        case .interval: return (0.92, 0.98)
        default: return nil
        }
    }
}

/// Seconds per km for each zone, with the plan's adaptation and any runner overrides already applied.
struct Paces {
    var secPerKm: [Zone: Double]

    func pace(_ z: Zone, mult: Double = 1) -> Double { (secPerKm[z] ?? 360) * mult }

    /// adjustments: percent of speed per group. Positive = faster than base.
    static func make(vdot: Double,
                     goalPaceSecPerKm: Double,
                     adjustments: [TrainingGroup: Double] = [:],
                     overrides: [Zone: Double] = [:]) -> Paces {
        var d: [Zone: Double] = [:]
        for z in Zone.allCases where z != .goal {
            d[z] = PaceEngine.secPerKm(vdot: vdot, fraction: PaceEngine.fraction(of: z))
        }
        d[.goal] = goalPaceSecPerKm

        func adjust(_ z: Zone, _ g: TrainingGroup) {
            if let off = adjustments[g], let base = d[z] { d[z] = base / (1 + off / 100) }
        }
        adjust(.recovery, .easy); adjust(.easy, .easy); adjust(.steady, .easy)
        adjust(.threshold, .threshold)
        adjust(.interval, .vo2); adjust(.repetition, .vo2)

        for (z, v) in overrides where v > 0 { d[z] = v }
        return Paces(secPerKm: d)
    }
}

extension RunnerProfile {
    /// Pace the goal needs, from the goal time if there is one, otherwise from the current fitness.
    var goalPaceSecPerKm: Double {
        if goalSeconds > 0 { return goalSeconds / goalDistanceKm }
        return PaceEngine.racePace(vdot: vdot, distanceKm: goalDistanceKm)
    }

    func paces(sessions: [PlanSession]) -> Paces {
        let adj = Adaptation.compute(sessions: sessions, since: adaptFrom)
        var offs: [TrainingGroup: Double] = [:]
        for (g, a) in adj { offs[g] = a.off }
        return Paces.make(vdot: vdot, goalPaceSecPerKm: goalPaceSecPerKm, adjustments: offs, overrides: overrides)
    }
}

// MARK: - Formatting

enum Fmt {
    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func pace(_ secPerKm: Double, miles: Bool) -> String {
        let s = miles ? secPerKm * 1.609344 : secPerKm
        return clock(s) + (miles ? " /mi" : " /km")
    }

    static func paceRange(_ secPerKm: Double, upTo mult: Double, miles: Bool) -> String {
        let a = miles ? secPerKm * 1.609344 : secPerKm
        return clock(a) + "–" + clock(a * mult) + (miles ? " /mi" : " /km")
    }

    static func distance(_ km: Double, miles: Bool) -> String {
        let v = miles ? km / 1.609344 : km
        return String(format: "%.1f %@", v, miles ? "mi" : "km")
    }

    static func minutes(_ m: Int) -> String {
        m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    static func seconds(_ s: Int) -> String {
        if s < 90 { return "\(s) s" }
        let m = s / 60, r = s % 60
        return r == 0 ? "\(m) min" : "\(m):" + String(format: "%02d", r) + " min"
    }
}
