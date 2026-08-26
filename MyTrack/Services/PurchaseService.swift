//
//  PurchaseService.swift
//  MyTrack
//
//  Wraps StoreKit 2: loads the two subscription Products, drives a purchase
//  through to a finished Transaction, and keeps isSubscribed in sync with
//  Transaction.currentEntitlements — including entitlement changes StoreKit
//  reports outside of a purchase made this session (renewal, refund, a
//  purchase made on another device). Nothing in the app gates on
//  isSubscribed yet; it's exposed so a future feature-gate has a single
//  source of truth to read.
//

import Foundation
import Observation
import OSLog
import StoreKit

enum PricingPlan: Equatable {
    case annual
    case monthly
}

enum PurchaseOutcome: Equatable {
    case success
    case userCancelled
    /// Awaiting approval (e.g. Ask to Buy) — not a failure, and not
    /// entitled yet either, so the paywall shouldn't advance or alert.
    case pending
    case failed
}

@MainActor
@Observable
final class PurchaseService {
    static let annualProductID = "KiwiJuice.MyTrack.annual"
    static let monthlyProductID = "KiwiJuice.MyTrack.monthly"
    private static let orderedProductIDs = [annualProductID, monthlyProductID]

    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false

    /// True once a load attempt has run to completion, whatever it produced.
    /// Lets the paywall tell "the prices are still coming" apart from "this
    /// device can't reach the store" — the difference between waiting and
    /// offering a way past a screen that is otherwise the only door into the
    /// app.
    private(set) var hasAttemptedProductLoad = false

    /// True once a currently-entitled transaction exists for either
    /// product. Not consumed anywhere yet — see file header.
    private(set) var isSubscribed = false

    /// Kept alive for the app's lifetime so it also reacts to entitlement
    /// changes it didn't cause directly this session.
    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(updatedTransaction: result)
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.updateEntitlements()
        }
    }

    func product(for plan: PricingPlan) -> Product? {
        let id = switch plan {
        case .annual: Self.annualProductID
        case .monthly: Self.monthlyProductID
        }
        return products.first { $0.id == id }
    }

    /// No-op once products are loaded — called eagerly from init so pricing
    /// is already there by the time onboarding reaches the paywall step, and
    /// callable again to retry an attempt that came back empty (no network at
    /// launch, StoreKit not ready yet).
    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer {
            isLoadingProducts = false
            hasAttemptedProductLoad = true
        }
        do {
            let loaded = try await Product.products(for: Self.orderedProductIDs)
            products = loaded.sorted { lhs, rhs in
                let lhsIndex = Self.orderedProductIDs.firstIndex(of: lhs.id) ?? .max
                let rhsIndex = Self.orderedProductIDs.firstIndex(of: rhs.id) ?? .max
                return lhsIndex < rhsIndex
            }
            AppLog.purchases.info("Loaded \(self.products.count, privacy: .public) product(s).")
        } catch {
            AppLog.purchases.error("Failed to load products: \(error.localizedDescription, privacy: .public)")
        }
    }

    func purchase(_ plan: PricingPlan) async -> PurchaseOutcome {
        guard let product = product(for: plan) else {
            AppLog.purchases.error("Purchase requested before products finished loading.")
            return .failed
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateEntitlements()
                return .success
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed
            }
        } catch {
            AppLog.purchases.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// AppStore.sync() re-authenticates and re-downloads the App Store
    /// receipt — what actually surfaces a purchase made on another device
    /// or after a reinstall. currentEntitlements alone only reflects what's
    /// already known on this device.
    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            AppLog.purchases.error("Restore failed: \(error.localizedDescription, privacy: .public)")
        }
        await updateEntitlements()
    }

    private func handle(updatedTransaction result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        await transaction.finish()
        await updateEntitlements()
    }

    private func updateEntitlements() async {
        var subscribed = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if Self.orderedProductIDs.contains(transaction.productID) {
                subscribed = true
            }
        }
        isSubscribed = subscribed
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
