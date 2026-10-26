import Foundation
import StoreKit
import Supabase

/// Buying, restoring and keeping Saku Plus in step with the App Store (Epic 11 US3, US4, US7). A purchase is
/// tied to the Saku account (`appAccountToken` = the auth user id), so another account on the same Apple ID
/// does not inherit it. The server copy (`apple-iap` Edge Function) is what limits are checked against; the
/// device copy only keeps Plus working offline.
@MainActor
final class PlusPurchases: ObservableObject {
    static let shared = PlusPurchases()

    enum Outcome: Equatable { case success, cancelled, pending, failed }

    @Published private(set) var products: [PlusPlan: Product] = [:]
    @Published private(set) var productsFailed = false

    private var listener: Task<Void, Never>?

    private init() {}

    // MARK: Products

    func loadProducts() async {
        do {
            let found = try await Product.products(for: [Entitlement.yearlyProductID, Entitlement.monthlyProductID])
            products = Dictionary(uniqueKeysWithValues: found.compactMap { p in Entitlement.plan(forProduct: p.id).map { ($0, p) } })
            productsFailed = products.isEmpty
        } catch {
            productsFailed = true
        }
    }

    // MARK: Buying

    func purchase(_ plan: PlusPlan) async -> Outcome {
        if products[plan] == nil { await loadProducts() }
        guard let product = products[plan], let userId = try? await SupabaseSDK.client.auth.session.user.id else { return .failed }
        do {
            switch try await product.purchase(options: [.appAccountToken(userId)]) {
            case .success(let verification):
                guard case .verified(let tx) = verification else { return .failed }
                await adopt(tx, jws: verification.jwsRepresentation, userId: userId)
                await tx.finish()
                return PlusStore.shared.isPlus ? .success : .failed
            case .userCancelled: return .cancelled
            case .pending: return .pending
            @unknown default: return .failed
            }
        } catch {
            return .failed
        }
    }

    /// US7: asks the App Store for this Apple ID's subscriptions, then re-reads them. True when Plus is open after.
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refresh()
        return PlusStore.shared.isPlus
    }

    // MARK: Staying in step

    /// Starts once at launch: renewals, refunds and purchases made elsewhere arrive here.
    func startListening() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard case .verified(let tx) = update, let self,
                      let userId = try? await SupabaseSDK.client.auth.session.user.id else { continue }
                await self.adopt(tx, jws: update.jwsRepresentation, userId: userId)
                await tx.finish()
            }
        }
    }

    /// Reads the current subscription from the App Store and makes the device and the server agree with it.
    /// Called after the profile is read, so a purchase the server has not heard of yet is not lost offline.
    func refresh() async {
        guard let userId = try? await SupabaseSDK.client.auth.session.user.id else { return }
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.appAccountToken == userId {
                await adopt(tx, jws: result.jwsRepresentation, userId: userId)
            }
        }
    }

    // MARK: Applying

    private func adopt(_ tx: StoreKit.Transaction, jws: String, userId: UUID) async {
        guard tx.appAccountToken == userId, Entitlement.plan(forProduct: tx.productID) != nil else { return }
        let status = await subscriptionStatus(for: tx.productID)
        let renewal = status?.renewalInfo
        var grace: Date?
        if case .verified(let info)? = renewal { grace = info.gracePeriodExpirationDate }
        let entitlement = Entitlement.fromStore(
            productID: tx.productID, expiresAt: tx.expirationDate,
            isFreeTrial: tx.offer?.type == .introductory && tx.offer?.paymentMode == .freeTrial,
            isRevoked: tx.revocationDate != nil, graceUntil: grace)
        // the device keeps working offline; a revoked or ended subscription takes the store's Plus away again
        PlusStore.shared.storeUntil = entitlement.isPlus() ? entitlement.until : nil
        if entitlement.isPlus() || PlusStore.shared.entitlement.status != .free {
            PlusStore.shared.apply(entitlement, isTester: PlusStore.shared.isTester)
        }
        await sendToServer(jws: jws, renewalJws: renewal?.jwsRepresentation)
    }

    private func subscriptionStatus(for productID: String) async -> Product.SubscriptionInfo.Status? {
        var product = products.values.first { $0.id == productID }
        if product == nil { product = try? await Product.products(for: [productID]).first }
        return try? await product?.subscription?.status.first
    }

    private func sendToServer(jws: String, renewalJws: String?) async {
        var body: [String: AnyJSON] = ["signedTransaction": .string(jws)]
        if let renewalJws { body["signedRenewalInfo"] = .string(renewalJws) }
        do {
            try await SupabaseSDK.client.functions.invoke("apple-iap", options: FunctionInvokeOptions(body: body))
            let session = try await SupabaseSDK.client.auth.session
            _ = try await SupabaseSDK.fetchProfile(authUserId: session.user.id)
        } catch {
            // not deployed yet or offline: the device copy stands and `refresh()` tries again at the next launch
        }
    }
}
