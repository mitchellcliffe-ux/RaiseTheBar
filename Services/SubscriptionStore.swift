import Foundation
import Combine
import StoreKit

/// The few values you must change before release. Everything else about the subscription
/// (prices, the free trial length, the names shown) is set in App Store Connect, not here.
enum AppConfig {
    /// These must match the Product IDs of the two auto-renewable subscriptions you create in App Store Connect.
    static let monthlyID = "raisethebar.sub.monthly"
    static let yearlyID = "raisethebar.sub.yearly"
    static let productIDs: [String] = [yearlyID, monthlyID]

    /// CHANGE THIS to the public address of your own privacy policy. Apple will reject the app without a real one.
    static let privacyURL = URL(string: "https://example.com/privacy")!
    /// Apple's standard licence agreement. Swap for your own terms if you write some.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// Loads the subscriptions from the App Store, sells them and keeps track of whether this person has access.
/// Apple handles the payment, the free trial, renewals, refunds and cancelling. No account or server of your own is needed.
@MainActor
final class SubscriptionStore: ObservableObject {

    enum Access { case checking, subscribed, notSubscribed }

    @Published private(set) var access: Access = .checking
    @Published private(set) var products: [Product] = []
    @Published private(set) var trialEligible = false
    @Published private(set) var activeProductID: String?
    @Published private(set) var periodEnds: Date?
    @Published private(set) var busy = false
    @Published private(set) var loadFailed = false
    @Published var message = ""

    private var updates: Task<Void, Never>?

    init() {
        // Renewals, refunds, family approvals and purchases made outside the app all arrive here.
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { [weak self] in
            await self?.refresh()
            await self?.loadProducts()
        }
    }

    /// Works out access from what Apple says this Apple Account is entitled to. Works offline from Apple's own cache.
    func refresh() async {
        var found: StoreKit.Transaction?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if AppConfig.productIDs.contains(transaction.productID) && transaction.revocationDate == nil {
                found = transaction
            }
        }
        activeProductID = found?.productID
        periodEnds = found?.expirationDate
        access = (found == nil) ? .notSubscribed : .subscribed
    }

    func loadProducts() async {
        do {
            let found = try await Product.products(for: AppConfig.productIDs)
            products = found.sorted { $0.price > $1.price }      // yearly first
            loadFailed = found.isEmpty
            if let subscription = found.first?.subscription {
                trialEligible = await subscription.isEligibleForIntroOffer
            }
        } catch {
            loadFailed = true
        }
    }

    func buy(_ product: Product) async {
        busy = true
        message = ""
        defer { busy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refresh()
                } else {
                    message = "The App Store could not confirm that purchase, so access has not been turned on. Please try again."
                }
            case .pending:
                message = "The purchase is waiting for approval. Access starts as soon as it is approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase did not go through. Please try again."
        }
    }

    /// For someone who has already paid, on a new phone or after reinstalling.
    func restore() async {
        busy = true
        message = ""
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        if access != .subscribed {
            message = "No active subscription was found for this Apple Account."
        }
    }

    #if DEBUG
    /// Test builds only, so the app can be looked at in the simulator before the products exist. Never in a release build.
    func unlockForTesting() { access = .subscribed }
    #endif
}

// MARK: - Wording helpers

enum SubscriptionText {
    static func unit(_ u: Product.SubscriptionPeriod.Unit) -> String {
        switch u {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }

    /// "month", "3 months", "year"
    static func every(_ p: Product.SubscriptionPeriod) -> String {
        p.value == 1 ? unit(p.unit) : "\(p.value) \(unit(p.unit))s"
    }

    /// "7 days", "1 week"
    static func length(_ p: Product.SubscriptionPeriod) -> String {
        "\(p.value) \(unit(p.unit))\(p.value == 1 ? "" : "s")"
    }

    /// "£39.99 a year"
    static func price(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        return "\(product.displayPrice) a \(every(period))"
    }

    /// The length of the free trial set in App Store Connect, if this product has one.
    static func trial(_ product: Product) -> String? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        return length(offer.period)
    }
}
