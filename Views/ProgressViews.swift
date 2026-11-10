import SwiftUI
import SwiftData
import Charts

struct ProgressTabView: View {
    @Bindable var profile: RunnerProfile
    @Query(sort: \PlanSession.date) private var sessions: [PlanSession]
    @Query(sort: \BenchmarkEntry.date) private var benchmarks: [BenchmarkEntry]

    private struct WeekPoint: Identifiable { let id = UUID(); let week: Int; let minutes: Int }
    private struct EffortPoint: Identifiable { let id = UUID(); let date: Date; let rpe: Int; let group: String }

    private var weekly: [WeekPoint] {
        var d: [Int: Int] = [:]
        for s in sessions where s.status == .done && s.kind != .strength {
            d[s.week, default: 0] += s.actualMinutes ?? s.plannedMinutes
        }
        return d.keys.sorted().map { WeekPoint(week: $0, minutes: d[$0] ?? 0) }
    }

    private var efforts: [EffortPoint] {
        sessions.compactMap { s in
            guard s.status == .done, let r = s.rpe, let g = s.group, g != .easy else { return nil }
            return EffortPoint(date: s.date, rpe: r, group: g.label)
        }
    }

    private var upToToday: [PlanSession] {
        sessions.filter { $0.date < Date() && $0.kind != .strength }
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                Section("Weekly running time") {
                    if weekly.isEmpty {
                        Text("Nothing logged yet.").foregroundStyle(.secondary)
                    } else {
                        Chart(weekly) { p in
                            BarMark(x: .value("Week", "W\(p.week)"), y: .value("Minutes", p.minutes))
                                .foregroundStyle(Color.brand)
                        }
                        .frame(height: 170)
                    }
                }
                Section("Effort on hard sessions") {
                    if efforts.count < 2 {
                        Text("Rate a couple of hard sessions to see the trend.").foregroundStyle(.secondary)
                    } else {
                        Chart(efforts) { p in
                            PointMark(x: .value("Date", p.date), y: .value("Effort", p.rpe))
                                .foregroundStyle(by: .value("Type", p.group))
                        }
                        .chartYScale(domain: 1...10)
                        .frame(height: 170)
                    }
                }
                Section("Fitness score") {
                    if benchmarks.count < 2 {
                        Text("Do a test at the end of a block and your score will be charted here.").foregroundStyle(.secondary)
                    } else {
                        Chart(benchmarks) { b in
                            LineMark(x: .value("Date", b.date), y: .value("Score", b.vdot))
                            PointMark(x: .value("Date", b.date), y: .value("Score", b.vdot))
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 170)
                    }
                }
                Section {
                    NavigationLink("What your ratings say") { CoachView(profile: profile) }
                    NavigationLink("How the plan is adapting") { AdaptingView(profile: profile) }
                }
            }
            .navigationTitle("Progress")
        }
    }

    private var summarySection: some View {
        Section("Where you are") {
            let doneCount = upToToday.filter { $0.status == .done }.count
            Text("\(doneCount) of \(upToToday.count) sessions done so far.")

            let predicted = PaceEngine.predictSeconds(vdot: profile.vdot, distanceM: profile.goalDistanceKm * 1000)
            Text("At your current fitness a \(distanceName) would take about \(Fmt.clock(predicted)).")
            if profile.goalSeconds > 0 {
                let gap = profile.goalSeconds - predicted
                Text(gap >= 0
                     ? "Your goal of \(Fmt.clock(profile.goalSeconds)) is within reach of where you are now."
                     : "Your goal of \(Fmt.clock(profile.goalSeconds)) is \(Fmt.clock(-gap)) faster than your current fitness suggests.")
                    .foregroundStyle(.secondary)
            }
            if profile.hasRaceDate {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: profile.raceDate)).day ?? 0
                if days >= 0 { Text("\(days / 7) weeks and \(days % 7) days to the race.") }
            }
            Text("A predicted time is an estimate from one benchmark. It is a guide, not a promise.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var distanceName: String {
        switch profile.goalDistanceKm {
        case ..<6: return "5K"
        case ..<12: return "10K"
        case ..<25: return "half marathon"
        default: return "marathon"
        }
    }
}

struct AdaptingView: View {
    @Bindable var profile: RunnerProfile
    @Query(sort: \PlanSession.date) private var sessions: [PlanSession]
    @State private var confirmReset = false

    var body: some View {
        let adj = Adaptation.compute(sessions: sessions, since: profile.adaptFrom)
        List {
            ForEach(TrainingGroup.allCases) { g in
                let a = adj[g] ?? GroupAdjustment()
                Section(g.label) {
                    Text(Adaptation.describe(g, a))
                    Text(String(format: "Limits: up to %.0f%% slower and %.0f%% faster than the base pace.", g.capDown, g.capUp))
                        .font(.footnote).foregroundStyle(.secondary)
                    let recent = sessions
                        .filter { $0.group == g && $0.status == .done && $0.rpe != nil && !$0.pain && $0.date >= profile.adaptFrom }
                        .suffix(5)
                    ForEach(Array(recent), id: \.id) { s in
                        let dev = Adaptation.deviation(s) ?? 0
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ": effort \(s.rpe ?? 0)")
                                .font(.subheadline)
                            Text(String(format: "Expected %.1f, gap %+.1f", Adaptation.expectedRPE(s) ?? 0, dev)
                                 + (Adaptation.noteEffect(s).on ? ", note counted" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Reset adaptation", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Puts every group back on its base pace. Your logged runs stay.")
            }
        }
        .navigationTitle("How the plan is adapting")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset all adjustments?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { profile.adaptFrom = Date() }
        }
    }
}
