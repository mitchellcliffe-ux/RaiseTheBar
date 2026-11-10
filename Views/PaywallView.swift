import SwiftUI
import StoreKit

/// Shown after setup when there is no active subscription: a new runner starting the free trial,
/// or someone whose subscription has ended. The plan and log stay on the phone either way.
struct PaywallView: View {
    let profile: RunnerProfile
    @EnvironmentObject private var store: SubscriptionStore
    @State private var selectedID: String = AppConfig.yearlyID

    private var selected: Product? {
        store.products.first { $0.id == selectedID } ?? store.products.first
    }

    /// The trial only applies to people Apple says have not had one before.
    private var trialLength: String? {
        guard store.trialEligible, let product = selected else { return nil }
        return SubscriptionText.trial(product)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    benefits
                    if store.products.isEmpty {
                        loading
                    } else {
                        plans
                        subscribeButton
                    }
                    if !store.message.isEmpty {
                        Text(store.message).font(.subheadline).foregroundStyle(.orange)
                    }
                    smallPrint
                }
                .padding(20)
            }
            .navigationTitle("Raise The Bar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") { Task { await store.restore() } }
                        .disabled(store.busy)
                }
            }
        }
    }

    // MARK: pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(profile.name.isEmpty ? "Your plan is ready" : "Your plan is ready, \(profile.name)")
                .font(.title.bold())
            Text(trialLength != nil
                 ? "Try everything free for \(trialLength ?? ""). Cancel any time before it ends and you pay nothing."
                 : "Subscribe to open your plan. Your plan and every run you have logged are still saved on this phone.")
                .foregroundStyle(.secondary)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefit("calendar", "A 12 week plan built around your days and your goal")
            benefit("speedometer", "Paces that adjust to how your runs really feel")
            benefit("applewatch", "Sessions sent to your Apple Watch")
            benefit("chart.line.uptrend.xyaxis", "Progress and a plain summary of what your ratings say")
        }
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.brand).frame(width: 26)
            Text(text)
        }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.loadFailed {
                Text("The subscription options could not be loaded. Check your connection and try again.")
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await store.loadProducts() } }
                    .buttonStyle(.bordered)
            } else {
                ProgressView()
            }
        }
    }

    private var plans: some View {
        VStack(spacing: 10) {
            ForEach(store.products, id: \.id) { product in
                let isOn = product.id == selected?.id
                Button {
                    selectedID = product.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName).font(.headline)
                            Text(SubscriptionText.price(product)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isOn ? Color.brand : Color.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isOn ? Color.brand : Color.secondary.opacity(0.35), lineWidth: isOn ? 2 : 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private var subscribeButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if let product = selected { Task { await store.buy(product) } }
            } label: {
                Text(store.busy ? "One moment…" : (trialLength != nil ? "Start free trial" : "Subscribe"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.brand)
            .disabled(store.busy || selected == nil)

            if let product = selected {
                Text(trialLength != nil
                     ? "Free for \(trialLength ?? ""), then \(SubscriptionText.price(product)). It renews automatically until you cancel."
                     : "\(SubscriptionText.price(product)). It renews automatically until you cancel.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var smallPrint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Payment is taken from your Apple Account. Cancel at least a day before the renewal date in Settings, under your name, then Subscriptions.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 18) {
                Link("Terms of Use", destination: AppConfig.termsURL)
                Link("Privacy Policy", destination: AppConfig.privacyURL)
            }
            .font(.footnote)
            #if DEBUG
            Button("Carry on without subscribing (test builds only)") { store.unlockForTesting() }
                .font(.footnote)
            #endif
        }
    }
}
