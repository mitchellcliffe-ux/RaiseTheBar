import SwiftUI
import SwiftData
import UIKit

struct SessionView: View {
    @Bindable var session: PlanSession
    let profile: RunnerProfile
    @Query(sort: \PlanSession.date) private var all: [PlanSession]

    @State private var noteTask: Task<Void, Never>?
    @State private var exportMessage = ""

    private let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    private var info: KindInfo { SessionLibrary.info(session.kind) }
    private var ctx: BuildContext { PlanHelpers.context(profile) }
    private var segments: [Segment] {
        SessionLibrary.segments(session.kind, minutes: session.plannedMinutes, p: session.progress, ctx: ctx)
    }
    private var steps: [Step] { SessionLibrary.flatten(segments) }
    private var paces: Paces { profile.paces(sessions: all) }

    var body: some View {
        Form {
            headerSection
            stepsSection
            fuelSection
            evidenceSection
            logSection
            if session.kind == .test30 || session.kind == .test3k || session.kind == .race {
                BenchmarkSection(session: session, profile: profile)
            }
            moreSection
        }
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: session.status) { _, new in
            if new == .done && session.actualMinutes == nil { session.actualMinutes = session.plannedMinutes }
        }
    }

    // MARK: sections

    private var headerSection: some View {
        Section {
            HStack {
                Text(session.date.formatted(date: .complete, time: .omitted))
                Spacer()
                Text(info.evidence.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(info.evidence == .study ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .clipShape(Capsule())
            }
            Text(info.why)
            if session.kind != .strength {
                let km = PlanHelpers.estimatedKm(steps, paces: paces)
                Text("About \(Fmt.minutes(session.plannedMinutes)), roughly \(Fmt.distance(km, miles: profile.useMiles)).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stepsSection: some View {
        Section("The session") {
            if session.kind == .strength {
                ForEach(SessionLibrary.strengthExercises, id: \.self) { Text($0) }
            } else {
                ForEach(PlanHelpers.lines(segments, paces: paces, profile: profile)) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.title).font(.subheadline.bold())
                        Text(line.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                StepChart(steps: steps, paces: paces, miles: profile.useMiles)
                if steps.contains(where: { $0.byEffort }) {
                    Text("Hills, strides and tests go by effort. The pace shown is only a guide.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var fuelSection: some View {
        Section("Fuel") {
            let f = FuelPlan.advice(kind: session.kind, minutes: session.plannedMinutes, weightKg: profile.weightKg,
                                    gut: profile.gut, caffeine: profile.usesCaffeine)
            VStack(alignment: .leading, spacing: 4) {
                Text("Before").font(.subheadline.bold())
                Text(f.before)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("During").font(.subheadline.bold())
                Text(f.during)
            }
            if let c = f.caffeine {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Caffeine").font(.subheadline.bold())
                    Text(c)
                }
            }
            Text(f.note).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var evidenceSection: some View {
        Section {
            DisclosureGroup("Evidence: \(info.evidence.rawValue)") {
                Text(info.evidenceNote).font(.footnote)
                ForEach(info.sources, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var logSection: some View {
        Section("How did it go?") {
            Picker("Status", selection: $session.status) {
                Text("Planned").tag(SessionStatus.planned)
                Text("Done").tag(SessionStatus.done)
                Text("Skipped").tag(SessionStatus.skipped)
            }
            .pickerStyle(.segmented)

            if session.status == .done {
                HStack {
                    Text("Time (minutes)")
                    Spacer()
                    TextField("min", value: $session.actualMinutes, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                }
                HStack {
                    Text("Distance (km)")
                    Spacer()
                    TextField("km", value: $session.actualKm, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                }
                HStack {
                    Text("Average heart rate")
                    Spacer()
                    TextField("optional", value: $session.avgHR, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("How hard did it feel? (1 easy, 10 flat out)").font(.subheadline.bold())
                    RPEPicker(value: $session.rpe)
                    if session.rpe == nil {
                        Text("Rate it so the plan can learn from it.").font(.footnote).foregroundStyle(.secondary)
                    } else if let g = session.group {
                        Text("A \(info.name.lowercased()) should feel around \(String(format: "%.1f", Adaptation.expectedRPE(session) ?? g.targetRPE)).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Toggle("Something hurt", isOn: $session.pain)
                if session.pain {
                    Text("Back off if something hurts, and see a physio or doctor if it carries on. The plan does not adapt around pain.")
                        .font(.footnote).foregroundStyle(.orange)
                }
                noteField
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(.subheadline.bold())
            TextField("How did it feel? Did you have to slow down? Anything outside the plan, like sleep, heat or food?",
                      text: $session.note, axis: .vertical)
                .lineLimit(3...6)
            noteReadout
        }
        .onChange(of: session.note) { _, _ in scheduleRead() }
    }

    @ViewBuilder
    private var noteReadout: some View {
        let t = session.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            if let r = session.feedback, r.text == t {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: session.noteIgnored ? "slash.circle" : "text.magnifyingglass")
                    Text(session.noteIgnored ? "Ignored. This note will not change your plan." : "What the plan took from this: " + r.summary)
                }
                .font(.footnote)
                Toggle("Ignore this note", isOn: $session.noteIgnored)
            } else {
                Text("Reading your note…").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var moreSection: some View {
        Section("More") {
            Menu("Swap for another session") {
                ForEach(SessionKind.allCases.filter { $0 != session.kind }) { k in
                    Button(SessionLibrary.info(k).name) { swap(to: k) }
                }
            }
            .disabled(session.status != .planned)

            Menu("Move to another day") {
                ForEach(0..<7, id: \.self) { d in
                    Button(dayNames[d]) { move(to: d) }
                }
            }

            if session.kind != .strength {
                Button("Copy the session as text") {
                    UIPasteboard.general.string = SessionLibrary.text(session.kind, segments: segments, paces: paces, miles: profile.useMiles)
                    exportMessage = "Copied. Paste it into a watch app or your notes."
                }
                #if canImport(WorkoutKit)
                Button("Send to Apple Watch") { Task { await sendToWatch() } }
                #endif
            }
            if !exportMessage.isEmpty {
                Text(exportMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: actions

    private func swap(to k: SessionKind) {
        session.kind = k
        session.plannedMinutes = SessionLibrary.totalMinutes(k, minutes: session.plannedMinutes, p: session.progress, ctx: ctx)
    }

    private func move(to d: Int) {
        let monday = PlanGenerator.mondayOf(session.date)
        if let newDate = Calendar.current.date(byAdding: .day, value: d, to: monday) {
            session.date = newDate
            session.day = d
        }
    }

    /// Read the note a moment after the runner stops typing, so the keyboard is never interrupted.
    private func scheduleRead() {
        noteTask?.cancel()
        let t = session.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { session.feedback = nil; return }
        let zone = steps.first(where: { $0.work })?.zone ?? .easy
        let base = paces.pace(zone) * (profile.useMiles ? 1.609344 : 1)
        let fbContext = FeedbackContext(basePaceSec: base, miles: profile.useMiles)
        noteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            session.feedback = FeedbackReader.read(t, context: fbContext)
        }
    }

    #if canImport(WorkoutKit)
    private func sendToWatch() async {
        do {
            try await WatchExport.schedule(name: info.name, segments: segments, on: session.date, outdoor: profile.surface != .treadmill)
            exportMessage = "Sent. Open the Workout app on your watch, it is under today's plan."
        } catch {
            exportMessage = error.localizedDescription
        }
    }
    #endif
}

/// Enter a test or race result and see what it would change before you accept it.
struct BenchmarkSection: View {
    @Bindable var session: PlanSession
    let profile: RunnerProfile
    @Environment(\.modelContext) private var context

    @State private var km: Double = 0
    @State private var seconds: Double = 0
    @State private var saved = false

    init(session: PlanSession, profile: RunnerProfile) {
        self.session = session
        self.profile = profile
        switch session.kind {
        case .test30: _seconds = State(initialValue: 1800)
        case .test3k: _km = State(initialValue: 3)
        default: _km = State(initialValue: profile.goalDistanceKm)
        }
    }

    private var newVDOT: Double? {
        guard km > 0, seconds > 0 else { return nil }
        let v = PaceEngine.vdot(distanceM: km * 1000, seconds: seconds)
        return (v > 15 && v < 90) ? v : nil
    }

    var body: some View {
        Section {
            HStack {
                Text("Distance (km)")
                Spacer()
                TextField("km", value: $km, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            }
            HStack {
                Text("Time")
                Spacer()
                TimeField(seconds: $seconds)
            }
            if let v = newVDOT {
                let oldT = PaceEngine.secPerKm(vdot: profile.vdot, fraction: PaceEngine.fraction(of: .threshold))
                let newT = PaceEngine.secPerKm(vdot: v, fraction: PaceEngine.fraction(of: .threshold))
                Text("Fitness score \(String(format: "%.1f", v)) (now \(String(format: "%.1f", profile.vdot))). Threshold pace would go from \(Fmt.pace(oldT, miles: profile.useMiles)) to \(Fmt.pace(newT, miles: profile.useMiles)).")
                    .font(.footnote)
                Button(saved ? "Paces updated" : "Update my paces") {
                    profile.vdot = v
                    profile.benchmarkKnown = true
                    profile.benchmarkDistanceM = km * 1000
                    profile.benchmarkSeconds = seconds
                    profile.adaptFrom = Date()      // the percentages now sit on a new base, so start them again
                    context.insert(BenchmarkEntry(date: session.date, distanceM: km * 1000, seconds: seconds, vdot: v, source: SessionLibrary.info(session.kind).name))
                    saved = true
                }
                .disabled(saved)
            }
        } header: {
            Text("Result")
        } footer: {
            Text("Nothing changes until you tap the button. Only update from an all-out, evenly paced effort.")
        }
    }
}
