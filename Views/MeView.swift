import SwiftUI
import SwiftData
import StoreKit

/// Paces, subscription, details, Health import, and the reset and disclaimer bits.
struct MeView: View {
    @Bindable var profile: RunnerProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanSession.date) private var sessions: [PlanSession]
    @StateObject private var health = HealthKitService()
    @EnvironmentObject private var store: SubscriptionStore

    @State private var importMessage = ""
    @State private var confirmStartAgain = false
    @State private var showManage = false

    var body: some View {
        NavigationStack {
            Form {
                pacesSection

                Section {
                    NavigationLink("My details") { DetailsView(profile: profile) }
                    NavigationLink("Session library") { LibraryView(profile: profile) }
                }

                Section {
                    Button("Import runs from Apple Health") { Task { await importRuns() } }
                    if !importMessage.isEmpty {
                        Text(importMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Read-only. The app looks at your running workouts and fills in the time, distance and heart rate. It never writes to Health. Strava runs appear here if Strava writes to Health on your phone.")
                }

                Section {
                    Text(subscriptionLine)
                    Button("Manage or cancel subscription") { showManage = true }
                    Button("Restore purchases") { Task { await store.restore() } }
                    if !store.message.isEmpty {
                        Text(store.message).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Subscription")
                } footer: {
                    Text("Billing is handled by Apple. You can also cancel in Settings, under your name, then Subscriptions.")
                }

                Section {
                    Button("Start again", role: .destructive) { confirmStartAgain = true }
                } header: {
                    Text("Start again")
                } footer: {
                    Text("Clears the plan and every logged run on this phone and takes you back to setup with your details filled in. Your subscription is not affected.")
                }

                Section("About") {
                    Text("Raise The Bar is training guidance, not medical advice. If you feel chest pain, dizziness or pain that does not settle, stop and see a doctor.")
                    Text("Paces come from one recent race or time trial using the Daniels and Gilbert running model. Predicted times are estimates.")
                    Text("Your details and logs are stored only on this phone.")
                    Link("Privacy Policy", destination: AppConfig.privacyURL)
                    Link("Terms of Use", destination: AppConfig.termsURL)
                }
                .font(.footnote)
            }
            .navigationTitle("Me")
            .manageSubscriptionsSheet(isPresented: $showManage)
            .confirmationDialog("Clear the plan and all logged runs?", isPresented: $confirmStartAgain, titleVisibility: .visible) {
                Button("Clear and start again", role: .destructive) { startAgain() }
            }
        }
    }

    private var subscriptionLine: String {
        let name = store.products.first { $0.id == store.activeProductID }?.displayName ?? "Subscription"
        if let ends = store.periodEnds {
            return "\(name) active. Current period ends \(ends.formatted(date: .abbreviated, time: .omitted))."
        }
        return "\(name) active."
    }

    // MARK: paces

    private var pacesSection: some View {
        let paces = profile.paces(sessions: sessions)
        let zones: [Zone] = [.recovery, .easy, .steady, .goal, .threshold, .interval, .repetition]
        return Section {
            HStack {
                Text("Fitness score")
                Spacer()
                Text(String(format: "%.1f", profile.vdot)).foregroundStyle(.secondary)
            }
            ForEach(zones) { z in
                PaceRow(zone: z, shown: paces.pace(z), profile: profile)
            }
        } header: {
            Text("Your paces")
        } footer: {
            Text("These include the small changes the plan has made from your effort ratings. Set your own pace for a zone if you know better. A pace you set is used as it is and the plan stops adjusting that zone.")
        }
    }

    // MARK: actions

    private func importRuns() async {
        let n = await health.importRuns(profile: profile, sessions: sessions, context: context)
        importMessage = n == 0 ? (health.status.isEmpty ? "No new runs found in Apple Health." : health.status)
                               : "Brought in \(n) run\(n == 1 ? "" : "s"). Open each one on the Plan tab and add your effort rating."
    }

    private func startAgain() {
        try? context.delete(model: PlanSession.self)
        try? context.delete(model: BenchmarkEntry.self)
        profile.setupDone = false
        profile.readinessAccepted = false
        profile.weekOffset = 0
        profile.adaptFrom = Date.distantPast
        profile.overridesJSON = ""
        profile.planStart = Date()
    }
}

/// One zone's pace. A stepper in 5 second steps keeps it simple and avoids typing a time.
private struct PaceRow: View {
    let zone: Zone
    let shown: Double               // seconds per km as the plan would use it now
    @Bindable var profile: RunnerProfile

    private var custom: Double? { profile.overrides[zone] }

    /// The stepper works in the runner's own unit (per km or per mile).
    private var factor: Double { profile.useMiles ? 1.609344 : 1 }

    private var binding: Binding<Double> {
        Binding(
            get: { (custom ?? shown) * factor },
            set: { newValue in
                var o = profile.overrides
                o[zone] = max(120, newValue) / factor
                profile.overrides = o
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Stepper(value: binding, in: 120...900, step: 5) {
                HStack {
                    Text(zone.label)
                    Spacer()
                    Text(Fmt.pace(custom ?? shown, miles: profile.useMiles))
                        .monospacedDigit()
                        .foregroundStyle(custom == nil ? Color.secondary : Color.brand)
                }
            }
            if custom != nil {
                Button("Use the calculated pace again") {
                    var o = profile.overrides
                    o[zone] = nil
                    profile.overrides = o
                }
                .font(.footnote)
            }
        }
    }
}

/// Every detail the runner can change, one tap down from Me so the tab itself stays short.
struct DetailsView: View {
    @Bindable var profile: RunnerProfile

    var body: some View {
        Form {
            ProfileForm(profile: profile)
            Section {
                Text("Changing your details does not rebuild the plan by itself. Use Start again on the Me tab for a fresh plan.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("My details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
