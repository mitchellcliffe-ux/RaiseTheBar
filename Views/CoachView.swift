import SwiftUI
import SwiftData

/// "What your ratings say": a plain-rules summary of the runner's own log, plus an optional chat with Apple's
/// on-device model where the phone supports it. Nothing here leaves the phone.
struct CoachView: View {
    let profile: RunnerProfile
    @Query(sort: \PlanSession.date) private var sessions: [PlanSession]

    private enum Span: String, CaseIterable, Identifiable {
        case week = "7 days", month = "4 weeks", all = "All"
        var id: String { rawValue }
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 28
            case .all: return nil
            }
        }
    }

    @State private var window: Span = .week
    @State private var question = ""
    @State private var answer = ""
    @State private var asking = false

    var body: some View {
        Form {
                Section {
                    Picker("Look back", selection: $window) {
                        ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("What your ratings say") {
                    let lines = CoachSummary.lines(sessions: sessions, profile: profile, days: window.days)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }

                Section {
                    if CoachService.onDeviceAvailable {
                        TextField("Ask about your training", text: $question, axis: .vertical)
                            .lineLimit(1...4)
                        Button(asking ? "Thinking…" : "Ask") { ask() }
                            .disabled(asking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !answer.isEmpty { Text(answer) }
                    } else {
                        Text("Chat needs a phone with Apple Intelligence on iOS 26 or later. The summary above works on every phone.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Ask the coach")
                } footer: {
                    Text("Answers come from your own log, on this phone. It is a guide, not medical advice. If something hurts, back off and see a physio or doctor.")
                }
            }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        asking = true
        let ctx = CoachSummary.context(sessions: sessions, profile: profile, days: window.days)
        Task { @MainActor in
            answer = await CoachService.ask(q, context: ctx)
            asking = false
        }
    }
}
