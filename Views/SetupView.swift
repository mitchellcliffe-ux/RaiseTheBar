import SwiftUI
import SwiftData

/// All the details a runner can enter. Used by the setup screen and by the Me tab, so they stay in step.
struct ProfileForm: View {
    @Bindable var profile: RunnerProfile
    /// First launch shows only what the plan needs. The Me tab shows everything.
    var essentialsOnly: Bool = false

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private func dayBinding(_ d: Int) -> Binding<Bool> {
        Binding(
            get: { profile.availableDays.contains(d) },
            set: { on in
                var set = Set(profile.availableDays)
                if on { set.insert(d) } else { set.remove(d) }
                profile.availableDays = Array(set).sorted()
            })
    }

    private var goalMinutes: Binding<Double> {
        Binding(get: { profile.goalSeconds / 60 }, set: { profile.goalSeconds = max(0, $0) * 60 })
    }

    private var benchmarkKm: Binding<Double> {
        Binding(get: { profile.benchmarkDistanceM / 1000 }, set: { profile.benchmarkDistanceM = max(0, $0) * 1000 })
    }

    var body: some View {
        Section("Basics") {
            TextField("Name", text: $profile.name)
            Stepper("Age: \(profile.age)", value: $profile.age, in: 18...90)
            if !essentialsOnly {
                HStack {
                    Text("Weight (kg)")
                    Spacer()
                    TextField("kg", value: $profile.weightKg, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
                HStack {
                    Text("Height (cm)")
                    Spacer()
                    TextField("cm", value: $profile.heightCm, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
            }
            Toggle("Show miles instead of kilometres", isOn: $profile.useMiles)
        }

        if !essentialsOnly {
            Section {
                HStack {
                    Text("Max heart rate")
                    Spacer()
                    TextField("optional", value: $profile.maxHR, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
                HStack {
                    Text("Resting heart rate")
                    Spacer()
                    TextField("optional", value: $profile.restingHR, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
            } header: {
                Text("Heart rate (optional)")
            } footer: {
                Text("Leave these at 0 if you do not train with heart rate. A measured max is far better than 220 minus your age, which can be out by 10 beats or more.")
            }
        }

        Section("Experience") {
            Stepper("Years running: \(profile.yearsRunning.formatted())", value: $profile.yearsRunning, in: 0...50, step: 0.5)
            Stepper("Runs per week now: \(profile.currentRunsPerWeek)", value: $profile.currentRunsPerWeek, in: 0...7)
            Stepper("Weekly running time now: \(Fmt.minutes(profile.weeklyMinutes))", value: $profile.weeklyMinutes, in: 0...600, step: 15)
            Stepper("Longest run in the last 4 weeks: \(Fmt.minutes(profile.longestRunMinutes))", value: $profile.longestRunMinutes, in: 0...300, step: 5)
            Toggle("I have had a break of more than 4 weeks recently", isOn: $profile.recentBreak)
        }

        Section("Goal") {
            Picker("Race distance", selection: $profile.goalDistanceKm) {
                Text("5K").tag(5.0)
                Text("10K").tag(10.0)
                Text("Half marathon").tag(21.0975)
                Text("Marathon").tag(42.195)
            }
            HStack {
                Text("Goal time (minutes, 0 for none)")
                Spacer()
                TextField("0", value: goalMinutes, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            }
            Toggle("I have a race date", isOn: $profile.hasRaceDate)
            if profile.hasRaceDate {
                DatePicker("Race date", selection: $profile.raceDate, in: Date()..., displayedComponents: .date)
            }
        }

        Section {
            Toggle("I have a recent race or time trial", isOn: $profile.benchmarkKnown)
            if profile.benchmarkKnown {
                HStack {
                    Text("Distance (km)")
                    Spacer()
                    TextField("km", value: benchmarkKm, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
                HStack {
                    Text("Time")
                    Spacer()
                    TimeField(seconds: $profile.benchmarkSeconds)
                }
            }
        } header: {
            Text("Current fitness")
        } footer: {
            Text(profile.benchmarkKnown
                 ? "A race in the last couple of months, or a hard 30 minute time trial (enter the distance you covered and 0:30:00)."
                 : "No problem. The app makes a cautious estimate and puts a 30 minute time trial in week 1 to set your paces properly.")
        }

        Section {
            Stepper("Runs per week: \(profile.runsPerWeekWanted)", value: $profile.runsPerWeekWanted, in: 2...6)
            ForEach(0..<7, id: \.self) { d in
                Toggle("Can run on \(dayNames[d])", isOn: dayBinding(d))
            }
            Picker("Long run day", selection: $profile.longRunDay) {
                ForEach(0..<7, id: \.self) { Text(dayNames[$0]).tag($0) }
            }
            Toggle("I work shifts or an irregular rota", isOn: $profile.hasShiftWork)
        } header: {
            Text("Availability")
        } footer: {
            Text("Any session can be moved to another day later, so a changing rota is fine.")
        }

        Section("Training style") {
            Picker("Style", selection: $profile.style) {
                ForEach(TrainingStyle.allCases) { Text($0.label).tag($0) }
            }
        }

        Section("Where and extras") {
            Picker("Where you mostly run", selection: $profile.surface) {
                ForEach(Surface.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Add two short strength sessions a week", isOn: $profile.doesStrength)
        }

        if !essentialsOnly {
            Section("Fuel") {
                Picker("Stomach", selection: $profile.gut) {
                    ForEach(Gut.allCases) { Text($0.label).tag($0) }
                }
                Toggle("I use caffeine", isOn: $profile.usesCaffeine)
                TextField("Dietary needs and what you use (gels, chews, real food)", text: $profile.diet, axis: .vertical)
            }
        }

        Section {
            TextField("Current niggles, past injuries, anything else", text: $profile.injuries, axis: .vertical)
        } header: {
            Text("Injuries and health")
        } footer: {
            Text("Training guidance only, not medical advice. If you have a health condition or any pain when you run, see a doctor or physio first.")
        }
    }
}

/// First launch: details, a short readiness screen, then the plan.
struct SetupView: View {
    @Bindable var profile: RunnerProfile
    @Environment(\.modelContext) private var context

    @State private var chestPain = false
    @State private var dizzy = false
    @State private var doctorLimit = false
    @State private var cleared = false

    private var anyYes: Bool { chestPain || dizzy || doctorLimit }
    private var canBuild: Bool {
        profile.readinessAccepted && (!anyYes || cleared) && profile.availableDays.count >= 2 && profile.age >= 18
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Raise The Bar builds a 12 week running plan from your details, then adjusts it to how your runs really feel. Everything you enter stays on this phone.")
                }
                ProfileForm(profile: profile, essentialsOnly: true)

                Section {
                    Text("Heart rate and fuelling details can be added later on the Me tab. The plan works without them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Chest pain when you are active?", isOn: $chestPain)
                    Toggle("Lose balance from dizziness, or ever faint?", isOn: $dizzy)
                    Toggle("Told by a doctor to only exercise as advised?", isOn: $doctorLimit)
                    if anyYes {
                        Text("Please check with a doctor before you start. You can carry on once you have.")
                            .foregroundStyle(.orange)
                        Toggle("I have checked with a doctor", isOn: $cleared)
                    }
                    Toggle("I understand this is training guidance, not medical advice, and that I am 18 or over", isOn: $profile.readinessAccepted)
                } header: {
                    Text("Before you start")
                }

                Section {
                    DatePicker("Start on or after", selection: $profile.planStart, in: Date()..., displayedComponents: .date)
                    Button("Build my plan") { build() }
                        .disabled(!canBuild)
                } footer: {
                    Text("Plans always start on a Monday, so any other day moves to the next Monday.")
                }
            }
            .navigationTitle("Raise The Bar")
        }
    }

    private func build() {
        let known = profile.benchmarkKnown && profile.benchmarkSeconds > 0 && profile.benchmarkDistanceM > 0
        if !known { profile.benchmarkKnown = false }
        profile.vdot = known
            ? PaceEngine.vdot(distanceM: profile.benchmarkDistanceM, seconds: profile.benchmarkSeconds)
            : PaceEngine.estimatedVDOT(yearsRunning: profile.yearsRunning, weeklyMinutes: profile.weeklyMinutes)
        if known {
            context.insert(BenchmarkEntry(date: Date(), distanceM: profile.benchmarkDistanceM, seconds: profile.benchmarkSeconds,
                                          vdot: profile.vdot, source: "Entered at setup"))
        }
        profile.weekOffset = 0
        profile.adaptFrom = Date.distantPast
        for s in PlanGenerator.generate(for: profile) { context.insert(s) }
        profile.setupDone = true
    }
}
