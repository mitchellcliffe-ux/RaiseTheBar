import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The "What your ratings say" summary. Plain rules over the runner's own log, no AI needed.
enum CoachSummary {

    static func window(_ sessions: [PlanSession], days: Int?) -> [PlanSession] {
        let today = Calendar.current.startOfDay(for: Date())
        let from = days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) } ?? Date.distantPast
        let end = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return sessions.filter { $0.date >= from && $0.date < end }.sorted { $0.date < $1.date }
    }

    static func lines(sessions: [PlanSession], profile: RunnerProfile, days: Int?) -> [String] {
        let w = window(sessions, days: days).filter { $0.kind != .strength }
        if w.isEmpty { return ["Nothing planned or logged in this window yet."] }

        let done = w.filter { $0.status == .done }
        let skipped = w.filter { $0.status == .skipped }
        var out: [String] = []
        out.append("\(done.count) of \(w.count) runs done" + (skipped.isEmpty ? "." : ", \(skipped.count) skipped."))

        let mins = done.compactMap { $0.actualMinutes }.reduce(0, +)
        if mins > 0 { out.append("About \(Fmt.minutes(mins)) of running logged.") }

        for g in TrainingGroup.allCases {
            let rated = done.filter { $0.group == g && $0.rpe != nil }
            guard !rated.isEmpty else { continue }
            let avg = Double(rated.compactMap { $0.rpe }.reduce(0, +)) / Double(rated.count)
            let expected = rated.compactMap { Adaptation.expectedRPE($0) }.reduce(0, +) / Double(rated.count)
            let gap = avg - expected
            let verdict = gap > 0.75 ? "harder than planned" : (gap < -0.75 ? "easier than planned" : "about right")
            out.append("\(g.label): average effort \(String(format: "%.1f", avg)) against \(String(format: "%.1f", expected)) expected, \(verdict).")
        }

        let unrated = done.filter { $0.rpe == nil }
        if !unrated.isEmpty { out.append("\(unrated.count) finished run\(unrated.count == 1 ? " has" : "s have") no effort rating yet, so the plan has not learned from \(unrated.count == 1 ? "it" : "them").") }

        let pain = w.filter { $0.pain }
        if !pain.isEmpty { out.append("You flagged pain on \(pain.count) run\(pain.count == 1 ? "" : "s"). If it carries on, see a physio or doctor. The plan does not adapt around pain.") }

        let adj = Adaptation.compute(sessions: sessions, since: profile.adaptFrom)
        for g in TrainingGroup.allCases {
            if let a = adj[g], a.n > 0, abs(a.off) >= 0.05 {
                out.append("\(g.label) are currently \(a.off > 0 ? "up" : "down") \(String(format: "%.1f", abs(a.off)))% from the base pace.")
            }
        }
        return out
    }

    /// The runner's own data as text, for the on-device model.
    static func context(sessions: [PlanSession], profile: RunnerProfile, days: Int?) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM"
        var rows: [String] = []
        for s in window(sessions, days: days) {
            var r = "\(df.string(from: s.date)): \(SessionLibrary.info(s.kind).name), planned \(s.plannedMinutes) min, \(s.status.rawValue)"
            if let m = s.actualMinutes { r += ", ran \(m) min" }
            if let rpe = s.rpe { r += ", effort \(rpe)/10" }
            if s.pain { r += ", PAIN FLAGGED" }
            let note = s.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty { r += ", note: \"\(note)\"" }
            rows.append(r)
        }
        let goal = profile.goalSeconds > 0 ? ", goal \(Fmt.clock(profile.goalSeconds))" : ""
        return "Goal distance \(Int(profile.goalDistanceKm)) km\(goal).\n" + rows.joined(separator: "\n")
    }
}

/// Optional chat with Apple's on-device language model (iOS 26 and later, on devices that support Apple Intelligence).
/// Nothing leaves the phone. Where it is not available the coach page still shows the rule-based summary.
enum CoachService {

    static var onDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func ask(_ question: String, context: String) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), onDeviceAvailable {
            do {
                let session = LanguageModelSession(instructions: """
                You are a careful running coach inside a training app. Answer only from the runner's own logged data given in the message. \
                If the data does not answer the question, say so. Keep answers under 120 words. Never give medical advice. \
                If the runner mentions pain, tell them to back off and see a physio or doctor.
                """)
                let response = try await session.respond(to: "Runner's data:\n\(context)\n\nQuestion: \(question)")
                return response.content
            } catch {
                return "The on-device coach could not answer that just now. Try again, or use the summary above."
            }
        }
        #endif
        return "The on-device coach is not available on this device. The summary above comes straight from your log."
    }
}
