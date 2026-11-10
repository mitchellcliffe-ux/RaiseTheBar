import SwiftUI
import SwiftData

struct LibraryView: View {
    let profile: RunnerProfile

    private struct LibraryGroup: Identifiable {
        let title: String
        let kinds: [SessionKind]
        var id: String { title }
    }

    private let groups: [LibraryGroup] = [
        LibraryGroup(title: "Easy and long", kinds: [.easy, .strides, .longRun, .recovery, .openers]),
        LibraryGroup(title: "Threshold", kinds: [.lightThreshold, .cruise, .overUnders, .norwegianThreshold, .hillAttacks]),
        LibraryGroup(title: "VO2max and speed", kinds: [.longReps, .norwegian4x4, .vo2Reps, .thirtyFifteen, .hillRepeats, .hillSprints]),
        LibraryGroup(title: "Race specific", kinds: [.fartlek, .goalPace, .leadKick, .race]),
        LibraryGroup(title: "Tests", kinds: [.test30, .test3k]),
        LibraryGroup(title: "Strength", kinds: [.strength])
    ]

    var body: some View {
        List {
                ForEach(groups) { g in
                    Section(g.title) {
                        ForEach(g.kinds) { k in
                            NavigationLink {
                                LibraryDetail(kind: k, profile: profile)
                            } label: {
                                let info = SessionLibrary.info(k)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(info.name).font(.headline)
                                    Text("\(info.evidence.rawValue) · " + info.why)
                                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        .navigationTitle("Session library")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LibraryDetail: View {
    let kind: SessionKind
    let profile: RunnerProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanSession.date) private var sessions: [PlanSession]
    @State private var date = Date()
    @State private var added = false

    private var info: KindInfo { SessionLibrary.info(kind) }
    private var minutes: Int {
        switch kind {
        case .longRun: return 80
        case .recovery: return 30
        case .strides: return 40
        case .openers: return 30
        case .strength: return 25
        case .easy: return 45
        default: return 40
        }
    }

    var body: some View {
        let ctx = PlanHelpers.context(profile)
        let segs = SessionLibrary.segments(kind, minutes: minutes, p: 0.5, ctx: ctx)
        let paces = profile.paces(sessions: sessions)
        Form {
            Section {
                Text(info.why)
                Text("Evidence: \(info.evidence.rawValue)").font(.subheadline.bold())
                Text(info.evidenceNote).font(.footnote)
                ForEach(info.sources, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            if kind == .strength {
                Section("The circuit") { ForEach(SessionLibrary.strengthExercises, id: \.self) { Text($0) } }
            } else {
                Section("At your paces (a mid-block version)") {
                    ForEach(PlanHelpers.lines(segs, paces: paces, profile: profile)) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.title).font(.subheadline.bold())
                            Text(line.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    StepChart(steps: SessionLibrary.flatten(segs), paces: paces, miles: profile.useMiles)
                }
            }
            Section("Add to my plan") {
                DatePicker("Day", selection: $date, in: Date()..., displayedComponents: .date)
                Button(added ? "Added" : "Add as an extra session") {
                    let total = SessionLibrary.totalMinutes(kind, minutes: minutes, p: 0.5, ctx: ctx)
                    let w = PlanHelpers.week(for: date, sessions: sessions, profile: profile)
                    context.insert(PlanSession(week: w, day: PlanGenerator.dayIndex(date), date: Calendar.current.startOfDay(for: date),
                                               kind: kind, minutes: total, progress: 0.5, isExtra: true))
                    added = true
                }
                .disabled(added)
            }
        }
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
