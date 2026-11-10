import SwiftUI
import SwiftData

@main
struct RaiseTheBarApp: App {
    @StateObject private var store = SubscriptionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
        // Everything is stored on the device. To sync between a runner's own devices later, add the iCloud capability
        // and CloudKit support to the container (every stored property already has a default value, which CloudKit needs).
        .modelContainer(for: [RunnerProfile.self, PlanSession.self, BenchmarkEntry.self])
    }
}

/// Setup first, so a new runner sees what they are getting. Then the subscription check. Then the app.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: SubscriptionStore
    @Query private var profiles: [RunnerProfile]

    var body: some View {
        content
            .onChange(of: scenePhase) { _, phase in
                // Picks up a subscription that ended, or was bought, while the app was in the background.
                if phase == .active { Task { await store.refresh() } }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let profile = profiles.first {
            if !profile.setupDone {
                SetupView(profile: profile)
            } else {
                switch store.access {
                case .checking:
                    ProgressView()
                case .subscribed:
                    MainTabs(profile: profile)
                case .notSubscribed:
                    PaywallView(profile: profile)
                }
            }
        } else {
            ProgressView()
                .task { context.insert(RunnerProfile()) }
        }
    }
}

/// Three tabs. The session library sits in the Plan menu and on Me; the coach summary sits in Progress.
struct MainTabs: View {
    @Bindable var profile: RunnerProfile

    var body: some View {
        TabView {
            PlanView(profile: profile)
                .tabItem { Label("Plan", systemImage: "calendar") }
            ProgressTabView(profile: profile)
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            MeView(profile: profile)
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
        }
        .tint(Color.brand)
    }
}
