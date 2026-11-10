import Foundation

/// Builds a 12-week plan from the runner's details: three blocks of four weeks (build, raise the ceiling, race ready),
/// at most two hard sessions a week, a lighter fourth week in each block with a test at the end, and a taper if there is a race date.
enum PlanGenerator {

    // MARK: calendar helpers

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    /// The Monday on or after a date. Plans always start on a Monday.
    static func mondayOnOrAfter(_ d: Date) -> Date {
        let cal = calendar
        let start = cal.startOfDay(for: d)
        let sinceMonday = (cal.component(.weekday, from: start) + 5) % 7     // Mon 0 ... Sun 6
        return sinceMonday == 0 ? start : (cal.date(byAdding: .day, value: 7 - sinceMonday, to: start) ?? start)
    }

    /// 0 = Monday ... 6 = Sunday
    static func dayIndex(_ d: Date) -> Int { (calendar.component(.weekday, from: d) + 5) % 7 }

    /// The Monday that starts the week a date falls in.
    static func mondayOf(_ d: Date) -> Date {
        let cal = calendar
        return cal.date(byAdding: .day, value: -dayIndex(d), to: cal.startOfDay(for: d)) ?? d
    }

    private static func dist(_ a: Int, _ b: Int) -> Int { let d = abs(a - b); return min(d, 7 - d) }

    // MARK: limits by goal distance

    private static func weeklyCap(_ goalKm: Double) -> Double {
        if goalKm <= 5.5 { return 300 }
        if goalKm <= 11 { return 360 }
        if goalKm <= 22 { return 420 }
        return 540
    }
    private static func longCap(_ goalKm: Double) -> Double {
        if goalKm <= 5.5 { return 90 }
        if goalKm <= 11 { return 105 }
        if goalKm <= 22 { return 135 }
        return 180
    }

    // MARK: choosing days

    /// Spread the runs through the week, always keeping the long run day.
    static func chooseRunDays(available: [Int], longDay: Int, wanted: Int) -> (days: [Int], long: Int) {
        var avail = Array(Set(available.filter { (0...6).contains($0) })).sorted()
        if avail.isEmpty { avail = [1, 3, 5, 6] }
        let long = avail.contains(longDay) ? longDay : (avail.last ?? 6)
        let target = min(max(wanted, 2), avail.count)
        var chosen = [long]
        while chosen.count < target {
            let rest = avail.filter { !chosen.contains($0) }
            func gap(_ x: Int) -> Int { chosen.map { dist(x, $0) }.min() ?? 0 }
            guard let next = rest.max(by: { gap($0) < gap($1) }) else { break }
            chosen.append(next)
        }
        return (chosen.sorted(), long)
    }

    /// Hard days: never the long run day, never next to it, never next to each other if it can be avoided.
    static func qualityDays(runDays: [Int], longDay: Int, count: Int) -> [Int] {
        var cands = runDays.filter { $0 != longDay && dist($0, longDay) > 1 }
        if cands.isEmpty { cands = runDays.filter { $0 != longDay } }
        var out: [Int] = []
        while out.count < count {
            let rest = cands.filter { c in !out.contains(c) && out.allSatisfy { dist(c, $0) > 1 } }
            func gap(_ x: Int) -> Int { ([longDay] + out).map { dist(x, $0) }.min() ?? 0 }
            guard let pick = rest.max(by: { gap($0) < gap($1) }) else { break }
            out.append(pick)
        }
        return out.sorted()
    }

    // MARK: which sessions

    private static func quality(week w: Int, runs: Int) -> [SessionKind] {
        let block = (w - 1) / 4
        let pos = (w - 1) % 4
        var list: [SessionKind]
        switch block {
        case 0:
            let t: [[SessionKind]] = [[.lightThreshold], [.cruise], [.lightThreshold], [.test30]]
            list = t[pos]
        case 1:
            let t: [[SessionKind]] = [[.cruise, .vo2Reps], [.overUnders, .thirtyFifteen], [.cruise, .norwegian4x4], [.test3k]]
            list = t[pos]
        default:
            let t: [[SessionKind]] = [[.goalPace, .hillRepeats], [.goalPace, .fartlek], [.goalPace, .longReps], [.test30]]
            list = t[pos]
        }
        var q = runs >= 5 ? 2 : ((runs == 4 && block >= 1) ? 2 : 1)
        if pos == 3 { q = 1 }                                   // test weeks keep a single hard session
        if block == 0 && runs >= 5 && (pos == 1 || pos == 2) { list.append(.hillSprints) }
        return Array(list.prefix(q))
    }

    private static func substitute(_ k: SessionKind, style: TrainingStyle) -> SessionKind {
        switch style {
        case .balanced:
            return k
        case .polarised:
            switch k {
            case .cruise: return .vo2Reps
            case .overUnders: return .longReps
            case .norwegianThreshold: return .thirtyFifteen
            default: return k
            }
        case .norwegian:
            switch k {
            case .vo2Reps: return .norwegianThreshold
            case .thirtyFifteen: return .cruise
            case .longReps: return .norwegianThreshold
            case .hillRepeats: return .hillAttacks
            default: return k
            }
        }
    }

    // MARK: the plan

    static func generate(for p: RunnerProfile) -> [PlanSession] {
        let cal = calendar
        let start = mondayOnOrAfter(p.planStart)
        let goalKm = max(p.goalDistanceKm, 1)
        let ctx = BuildContext(goalKm: goalKm, vdot: p.vdot)

        // Length of the plan, and the race week if the race falls inside it
        var weeks = 12
        var raceWeek: Int?
        var raceDay = 0
        if p.hasRaceDate {
            let days = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: p.raceDate)).day ?? -1
            if days >= 0 && days < 84 {
                raceWeek = days / 7 + 1
                weeks = days / 7 + 1
                raceDay = dayIndex(p.raceDate)
            }
        }

        // Weekly running time: up about 7% a week, a lighter fourth week in each block, a taper before a race
        let base = min(max(Double(p.weeklyMinutes) * (p.recentBreak ? 0.7 : 1.0), 60), 420)
        let cap = weeklyCap(goalKm)
        var level = base
        var vol = [Double](repeating: 0, count: weeks + 2)
        for w in 1...weeks {
            if (w - 1) % 4 == 3 {
                vol[w] = level * 0.78
            } else {
                if w > 1 { level = min(level * 1.07, cap, base * 1.6) }
                vol[w] = level
            }
        }
        if let rw = raceWeek {
            if rw >= 3 { vol[rw - 2] *= 0.9 }
            if rw >= 2 { vol[rw - 1] *= 0.75 }
            vol[rw] *= 0.5
        }

        let (runDays, longDay) = chooseRunDays(available: p.availableDays, longDay: p.longRunDay, wanted: p.runsPerWeekWanted)
        var out: [PlanSession] = []

        for w in 1...weeks {
            let weekStart = cal.date(byAdding: .day, value: (w - 1) * 7, to: start) ?? start
            let pos = (w - 1) % 4
            let prog = Double(pos) / 3.0

            func add(_ d: Int, _ k: SessionKind, _ mins: Int) {
                let date = cal.date(byAdding: .day, value: d, to: weekStart) ?? weekStart
                let total = SessionLibrary.totalMinutes(k, minutes: mins, p: prog, ctx: ctx)
                out.append(PlanSession(week: p.weekOffset + w, day: d, date: date, kind: k, minutes: total, progress: prog))
            }

            // Race week: a couple of short runs, openers the day before, then the race
            if let rw = raceWeek, w == rw {
                add(raceDay, .race, 0)
                if raceDay >= 1 { add(raceDay - 1, .openers, 25) }
                for d in runDays.filter({ $0 <= raceDay - 2 }).prefix(2) { add(d, .easy, 30) }
                continue
            }

            // Hard sessions
            var kinds = quality(week: w, runs: runDays.count).map { substitute($0, style: p.style) }
            if !p.benchmarkKnown && w == 1 && !kinds.isEmpty { kinds[0] = .test30 }
            let qDays = qualityDays(runDays: runDays, longDay: longDay, count: kinds.count)
            let usable = min(kinds.count, qDays.count)
            var hardMinutes = 0
            for i in 0..<usable {
                hardMinutes += SessionLibrary.totalMinutes(kinds[i], minutes: 40, p: prog, ctx: ctx)
                add(qDays[i], kinds[i], 40)
            }

            // Long run: grows gradually from the longest recent run
            let longFrac = runDays.count <= 3 ? 0.36 : 0.30
            var longMin = min(longCap(goalKm), vol[w] * longFrac)
            longMin = min(longMin, Double(p.longestRunMinutes) + 8.0 * Double(w))
            longMin = max(longMin, 35)
            let longRounded = Int((longMin / 5).rounded()) * 5
            add(longDay, .longRun, longRounded)

            // Easy runs fill what is left; one gets strides from week 2
            let easyDays = runDays.filter { $0 != longDay && !qDays.prefix(usable).contains($0) }.sorted()
            if !easyDays.isEmpty {
                let remaining = max(vol[w] - Double(longRounded) - Double(hardMinutes), 0)
                let each = min(max(remaining / Double(easyDays.count), 25), 70)
                let base5 = Int((each / 5).rounded()) * 5
                var stridesDone = false
                for d in easyDays {
                    let before = (d + 6) % 7
                    let dayAfterHard = qDays.prefix(usable).contains(before) || before == longDay
                    var m = base5
                    if dayAfterHard { m = max(25, m - 5) }
                    if w >= 2 && !stridesDone && !dayAfterHard && pos != 3 {
                        add(d, .strides, max(m, 30))
                        stridesDone = true
                    } else {
                        add(d, .easy, m)
                    }
                }
            }

            // Strength on days off, never the day before a hard session
            if p.doesStrength {
                var n = 0
                for d in 0...6 where n < 2 && !runDays.contains(d) && !qDays.prefix(usable).contains((d + 1) % 7) {
                    add(d, .strength, 25)
                    n += 1
                }
            }
        }
        return out
    }

    /// Start the next 12 weeks from what was really run. Call after the last week; the caller inserts the result.
    static func startNextPlan(profile p: RunnerProfile, sessions: [PlanSession]) -> [PlanSession] {
        let done = sessions.filter { $0.status == .done }.sorted { $0.date < $1.date }
        if let last = sessions.map({ $0.date }).max() {
            p.planStart = mondayOnOrAfter(calendar.date(byAdding: .day, value: 1, to: last) ?? last)
        }
        p.weekOffset = (sessions.map { $0.week }.max() ?? 0)
        let recent = done.suffix(12)
        if !recent.isEmpty {
            let mins = recent.compactMap { $0.actualMinutes }.reduce(0, +)
            let weekly = Double(mins) / max(1.0, Double(Set(recent.map { $0.week }).count))
            if weekly > 30 { p.weeklyMinutes = Int(weekly.rounded()) }
            if let longest = recent.compactMap({ $0.actualMinutes }).max() { p.longestRunMinutes = longest }
        }
        return generate(for: p)
    }
}
