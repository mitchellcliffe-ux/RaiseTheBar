import SwiftUI
import SwiftData

struct PlanView: View {
    @Bindable var profile: RunnerProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanSession.date) private var sessions: [PlanSession]
    @StateObject private var health = HealthKitService()

    @State private var week: Int = 0
    @State private var showDesign = false
    @State private var showOverview = false
    @State private var showLibrary = false
    @State private var message: String = ""

    private var weeks: [Int] { Array(Set(sessions.map { $0.week })).sorted() }
    private var thisWeekSessions: [PlanSession] { sessions.filter { $0.week == week } }

    private var weekStart: Date? {
        thisWeekSessions.map { PlanGenerator.mondayOf($0.date) }.min()
    }

    private func currentWeek() -> Int {
        let monday = PlanGenerator.mondayOf(Date())
        if let s = sessions.first(where: { PlanGenerator.mondayOf($0.date) == monday }) { return s.week }
        if let next = sessions.first(where: { $0.date > Date() }) { return next.week }
        return sessions.last?.week ?? 1
    }

    var body: some View {
        NavigationStack {
            List {
                if week == currentWeek() { todaySection }
                weekNav
                if !message.isEmpty {
                    Section { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                }
                ForEach(0..<7, id: \.self) { d in
                    daySection(d)
                }
                if weekEnded {
                    Section {
                        Button("Start the next 12 weeks") { startNext() }
                    } footer: {
                        Text("Builds a new plan from what you actually ran. Update your benchmark first if you have done a test.")
                    }
                }
            }
            .navigationTitle("Week \(week)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showDesign = true } label: { Label("Design a session", systemImage: "wand.and.stars") }
                        Button { showOverview = true } label: { Label("Next 12 weeks", systemImage: "list.bullet") }
                        Button { showLibrary = true } label: { Label("Session library", systemImage: "books.vertical") }
                        Button { Task { await importRuns() } } label: { Label("Import runs from Apple Health", systemImage: "heart.text.square") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showDesign) { DesignSessionView(profile: profile, week: week) }
            .sheet(isPresented: $showOverview) { OverviewView(profile: profile) }
            .sheet(isPresented: $showLibrary) {
                NavigationStack {
                    LibraryView(profile: profile)
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { showLibrary = false } } }
                }
            }
            .onAppear { if week == 0 { week = currentWeek() } }
        }
    }

    private var weekEnded: Bool {
        guard let last = weeks.last, week == last, let end = sessions.map({ $0.date }).max() else { return false }
        return end < Date()
    }

    /// Today's run first, so the thing most people open the app for is one tap away.
    private var todaySection: some View {
        let today = sessions.filter { Calendar.current.isDateInToday($0.date) }
        return Section("Today") {
            if today.isEmpty {
                Text("Rest day. Nothing planned.").foregroundStyle(.secondary)
            } else {
                ForEach(today) { s in
                    NavigationLink {
                        SessionView(session: s, profile: profile)
                    } label: {
                        SessionRow(session: s)
                    }
                }
            }
        }
    }

    private var weekNav: some View {
        Section {
            HStack {
                Button("Previous") { if let i = weeks.firstIndex(of: week), i > 0 { week = weeks[i - 1] } }
                    .disabled(weeks.first == week)
                Spacer()
                Button("This week") { week = currentWeek() }
                Spacer()
                Button("Next") { if let i = weeks.firstIndex(of: week), i < weeks.count - 1 { week = weeks[i + 1] } }
                    .disabled(weeks.last == week)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            let total = thisWeekSessions.filter { $0.kind != .strength }.reduce(0) { $0 + $1.plannedMinutes }
            let hard = thisWeekSessions.filter { SessionLibrary.info($0.kind).load == .hard }.count
            Text("Planned \(Fmt.minutes(total)) of running, \(hard) hard session\(hard == 1 ? "" : "s").")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func daySection(_ d: Int) -> some View {
        let items = thisWeekSessions.filter { $0.day == d }.sorted { $0.date < $1.date }
        let date = weekStart.flatMap { Calendar.current.date(byAdding: .day, value: d, to: $0) }
        Section {
            if items.isEmpty {
                Text("Rest day").foregroundStyle(.secondary)
            } else {
                ForEach(items) { s in
                    NavigationLink {
                        SessionView(session: s, profile: profile)
                    } label: {
                        SessionRow(session: s)
                    }
                }
                .onDelete { idx in
                    for i in idx where items[i].isExtra { context.delete(items[i]) }
                }
            }
        } header: {
            Text(date.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? "")
        }
    }

    private func importRuns() async {
        let n = await health.importRuns(profile: profile, sessions: sessions, context: context)
        message = n == 0 ? (health.status.isEmpty ? "No new runs found in Apple Health." : health.status)
                         : "Brought in \(n) run\(n == 1 ? "" : "s"). Open each one and add your effort rating."
    }

    private func startNext() {
        let new = PlanGenerator.startNextPlan(profile: profile, sessions: sessions)
        for s in new { context.insert(s) }
        week = (new.first?.week) ?? week
    }
}

struct SessionRow: View {
    let session: PlanSession

    var body: some View {
        let info = SessionLibrary.info(session.kind)
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if info.load == .hard { Text("HARD").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.brand.opacity(0.18)).clipShape(Capsule()) }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var t = Fmt.minutes(session.status == .done ? (session.actualMinutes ?? session.plannedMinutes) : session.plannedMinutes)
        if session.isExtra { t += " · extra" }
        if session.status == .done {
            if let r = session.rpe { t += " · effort \(r)" } else { t += " · needs a rating" }
        }
        if session.status == .skipped { t += " · skipped" }
        return t
    }
    private var icon: String {
        switch session.status {
        case .done: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle"
        case .planned: return session.kind == .strength ? "dumbbell" : "figure.run"
        }
    }
    private var color: Color {
        switch session.status {
        case .done: return session.rpe == nil ? .orange : .green
        case .skipped: return .secondary
        case .planned: return Color.brand
        }
    }
}

/// The whole plan at a glance.
struct OverviewView: View {
    let profile: RunnerProfile
    @Query(sort: \PlanSession.date) private var sessions: [PlanSession]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(Set(sessions.map { $0.week })).sorted(), id: \.self) { w in
                    let items = sessions.filter { $0.week == w }
                    let mins = items.filter { $0.kind != .strength }.reduce(0) { $0 + $1.plannedMinutes }
                    let hard = items.filter { SessionLibrary.info($0.kind).load == .hard }
                        .map { SessionLibrary.info($0.kind).name }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Week \(w) · \(Fmt.minutes(mins))").font(.headline)
                        Text(hard.isEmpty ? "No hard sessions" : hard.joined(separator: ", "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Next 12 weeks")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

/// Pick the time you have and what you want from it. The app builds a session from the library at your paces.
struct DesignSessionView: View {
    let profile: RunnerProfile
    let week: Int
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlanSession.date) private var sessions: [PlanSession]

    enum Focus: String, CaseIterable, Identifiable {
        case easy = "Easy", threshold = "Threshold", vo2 = "VO2max", hills = "Hills", speed = "Speed and strides", racePace = "Goal pace"
        var id: String { rawValue }
    }

    @State private var date = Date()
    @State private var minutes = 45
    @State private var focus: Focus = .easy
    @State private var designed: (kind: SessionKind, progress: Double, total: Int)?

    var body: some View {
        NavigationStack {
            Form {
                Section("What you want") {
                    DatePicker("Day", selection: $date, in: Date()..., displayedComponents: .date)
                    Stepper("Time available: \(Fmt.minutes(minutes))", value: $minutes, in: 30...180, step: 5)
                    Picker("Focus", selection: $focus) {
                        ForEach(Focus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Button("Design it") { design() }
                }
                if let d = designed {
                    let info = SessionLibrary.info(d.kind)
                    let ctx = PlanHelpers.context(profile)
                    let segs = SessionLibrary.segments(d.kind, minutes: minutes, p: d.progress, ctx: ctx)
                    let paces = profile.paces(sessions: sessions)
                    Section(info.name) {
                        Text("About \(Fmt.minutes(d.total)). " + info.why)
                        ForEach(PlanHelpers.lines(segs, paces: paces, profile: profile)) { line in
                            VStack(alignment: .leading) {
                                Text(line.title).font(.subheadline.bold())
                                Text(line.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        StepChart(steps: SessionLibrary.flatten(segs), paces: paces, miles: profile.useMiles)
                    }
                    Section {
                        Button("Add to my plan") { add(d) }
                        Button("Not this one", role: .cancel) { designed = nil }
                    }
                }
            }
            .navigationTitle("Design a session")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
    }

    /// Pick a session for the focus, then the rep count that gets closest to the time available.
    private func design() {
        let kind: SessionKind
        switch focus {
        case .easy: kind = minutes >= 75 ? .longRun : .easy
        case .threshold: kind = profile.style == .norwegian ? .norwegianThreshold : (minutes < 50 ? .lightThreshold : .cruise)
        case .vo2: kind = minutes >= 60 ? .vo2Reps : .thirtyFifteen
        case .hills: kind = .hillRepeats
        case .speed: kind = .strides
        case .racePace: kind = .goalPace
        }
        let ctx = PlanHelpers.context(profile)
        var best: (Double, Int) = (0, 0)
        var bestGap = Int.max
        for p in [0.0, 0.34, 0.67, 1.0] {
            let total = SessionLibrary.totalMinutes(kind, minutes: minutes, p: p, ctx: ctx)
            let gap = abs(total - minutes)
            if gap < bestGap { bestGap = gap; best = (p, total) }
        }
        designed = (kind, best.0, best.1)
    }

    private func add(_ d: (kind: SessionKind, progress: Double, total: Int)) {
        let w = PlanHelpers.week(for: date, sessions: sessions, profile: profile)
        let s = PlanSession(week: w, day: PlanGenerator.dayIndex(date), date: Calendar.current.startOfDay(for: date),
                            kind: d.kind, minutes: d.total, progress: d.progress, isExtra: true)
        context.insert(s)
        dismiss()
    }
}
