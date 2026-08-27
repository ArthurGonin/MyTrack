//
//  PurchaseService.swift
//  MyTrack
//
//  Wraps StoreKit 2: loads the two subscription Products, drives a purchase
//  through to a finished Transaction, and keeps `subscription` in sync with
//  Transaction.currentEntitlements — including entitlement changes StoreKit
//  reports outside of a purchase made this session (renewal, refund, a
//  purchase made on another device). L'app entière est payante : cet état
//  est la source de vérité unique, lue par la paywall d'onboarding et par la
//  section Abonnement des réglages.
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

/// Ce que l'app sait de l'abonnement en cours. Regroupé en un seul état
/// plutôt qu'en booléens séparés, parce que les réglages doivent pouvoir dire
/// *quelle* formule, jusqu'à quand, et si elle se reconduit — trois réponses
/// qui viennent toutes de la même transaction.
struct SubscriptionSummary: Equatable {
    let plan: PricingPlan
    /// La formule qui prendra le relais à la prochaine échéance, quand elle
    /// diffère de celle en cours. Passer d'annuel à mensuel ne s'applique pas
    /// tout de suite : l'abonnement annuel court jusqu'à son terme, et c'est
    /// seulement au renouvellement que le mensuel prend la suite. Sans cette
    /// information, l'app affiche « Annuel » à quelqu'un qui vient de choisir
    /// « Mensuel » et a toutes les raisons de croire que rien n'a marché.
    let pendingPlan: PricingPlan?
    let expirationDate: Date?
    let isInFreeTrial: Bool
    /// nil quand StoreKit n'a pas pu livrer l'info de reconduction (produits
    /// pas encore chargés, pas de réseau). On affiche alors « Actif » sans
    /// annoncer une date qu'on ne sait pas tenir.
    let willAutoRenew: Bool?
}

@MainActor
@Observable
final class PurchaseService {
    static let annualProductID = "KiwiJuice.MyTrack.annual"
    static let monthlyProductID = "KiwiJuice.MyTrack.monthly"
    /// Ordre d'affichage, et la liste que `SubscriptionStoreView` réclame
    /// pour présenter les mêmes formules que la paywall.
    static let orderedProductIDs = [annualProductID, monthlyProductID]

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

    /// L'abonnement en cours, ou nil si aucun.
    private(set) var subscription: SubscriptionSummary?

    var isSubscribed: Bool { subscription != nil }

    /// Vrai quand l'abonnement n'a pas été résilié mais que le renouvellement
    /// échoue (carte expirée, plafond atteint). L'utilisateur n'a rien annulé :
    /// lui présenter une nouvelle formule serait à côté de la plaque, ce qu'il
    /// lui faut c'est la feuille de gestion d'abonnement.
    private(set) var hasBillingIssue = false

    /// Ce que l'abonnement achète : enregistrer de *nouveaux* trajets. Tout ce
    /// qui existe déjà — trajets, rapports, export — reste accessible sans
    /// abonnement, parce qu'on ne prend pas en otage des données déjà créées.
    ///
    /// Stocké plutôt que calculé, et amorcé depuis UserDefaults : au réveil en
    /// arrière-plan (changement significatif de position), la détection doit
    /// pouvoir s'armer tout de suite, sans attendre la réponse de StoreKit qui
    /// la corrigera de toute façon dans la seconde.
    private(set) var canRecordTrips = UserDefaults.standard.bool(forKey: PurchaseService.lastKnownAccessKey)

    /// Prévenu à chaque changement d'accès. `didJustLapse` distingue « il vient
    /// de le perdre » — le seul cas qui mérite une notification — d'un état
    /// simplement relu au lancement.
    var onAccessChange: ((_ canRecordTrips: Bool, _ didJustLapse: Bool) -> Void)?

    /// Persisté pour que la perte d'accès soit détectable même quand elle
    /// survient app fermée : au lancement suivant, l'écart entre ce qui est sur
    /// le disque et ce que dit StoreKit *est* la bascule.
    private static let lastKnownAccessKey = "hadRecordingAccess"

    #if DEBUG
    private static let debugBypassKey = "debugBypassesPaywall"

    /// Ce que pose le bouton « Ignorer (debug) » de la paywall. Sans lui, un
    /// build de développement qui saute l'onboarding se retrouve dans une app
    /// où plus rien ne s'enregistre. Compilé hors du build de release.
    private(set) var debugBypassesPaywall = UserDefaults.standard.bool(forKey: PurchaseService.debugBypassKey)

    func grantDebugAccess() {
        debugBypassesPaywall = true
        UserDefaults.standard.set(true, forKey: Self.debugBypassKey)
        applyAccessChange()
    }
    #endif

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

    private static func plan(for productID: String) -> PricingPlan? {
        switch productID {
        case annualProductID: .annual
        case monthlyProductID: .monthly
        default: nil
        }
    }

    /// Relit l'entitlement en cours, en s'assurant d'abord que les produits
    /// sont chargés (sans eux, pas d'info de reconduction). Appelé à
    /// l'ouverture des réglages : un abonnement a pu se renouveler, expirer ou
    /// être résilié depuis le lancement de l'app.
    func refreshSubscription() async {
        await loadProducts()
        await updateEntitlements()
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
        // Deux entitlements du même groupe peuvent coexister le temps d'un
        // changement de formule. Prendre le dernier arrivé dans la boucle
        // rendait l'affichage dépendant de l'ordre d'itération ; c'est l'achat
        // le plus récent qui fait foi.
        var current: Transaction?
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  Self.plan(for: transaction.productID) != nil else { continue }
            if let latest = current, latest.purchaseDate >= transaction.purchaseDate { continue }
            current = transaction
        }

        var found: SubscriptionSummary?
        if let current, let plan = Self.plan(for: current.productID) {
            let renewal = await renewalState(for: plan)
            let pendingPlan = renewal?.autoRenewProductID.flatMap(Self.plan(for:))
            found = SubscriptionSummary(
                plan: plan,
                pendingPlan: pendingPlan == plan ? nil : pendingPlan,
                expirationDate: current.expirationDate,
                isInFreeTrial: current.offer?.type == .introductory,
                willAutoRenew: renewal?.willAutoRenew
            )
        }
        subscription = found
        hasBillingIssue = found == nil ? await isInBillingRetry() : false
        applyAccessChange()
    }

    /// Un abonnement en échec de paiement n'apparaît plus dans les
    /// entitlements — de l'extérieur ça ressemble à une résiliation. Seul
    /// l'état du groupe d'abonnement fait la différence, et cette différence
    /// change tout ce que l'app doit dire à l'utilisateur.
    private func isInBillingRetry() async -> Bool {
        guard let subscriptionInfo = products.first?.subscription,
              let statuses = try? await subscriptionInfo.status else { return false }
        return statuses.contains { $0.state == .inBillingRetryPeriod }
    }

    /// Ne prévient que sur un vrai changement : appelée à chaque relecture des
    /// entitlements, elle ne doit pas re-notifier une perte d'accès déjà
    /// annoncée.
    private func applyAccessChange() {
        var hasAccess = isSubscribed
        #if DEBUG
        hasAccess = hasAccess || debugBypassesPaywall
        #endif

        let hadAccess = canRecordTrips
        guard hadAccess != hasAccess else { return }

        canRecordTrips = hasAccess
        UserDefaults.standard.set(hasAccess, forKey: Self.lastKnownAccessKey)
        onAccessChange?(hasAccess, hadAccess && !hasAccess)
    }

    private struct RenewalState {
        let willAutoRenew: Bool
        /// L'identifiant du produit qui sera reconduit — pas forcément celui en
        /// cours, justement quand un changement de formule est programmé.
        let autoRenewProductID: String?
    }

    /// `currentEntitlements` dit qu'un abonnement est actif et jusqu'à quand,
    /// mais ni s'il sera reconduit, ni avec quelle formule : ça, seul le
    /// renewalInfo du groupe d'abonnement le sait. C'est toute la différence
    /// entre « renouvellement le 12 septembre » et « se termine le
    /// 12 septembre » — et entre « annuel » et « annuel, puis mensuel ».
    private func renewalState(for plan: PricingPlan) async -> RenewalState? {
        guard let product = product(for: plan),
              let statuses = try? await product.subscription?.status else { return nil }
        for status in statuses {
            guard let renewalInfo = try? checkVerified(status.renewalInfo) else { continue }
            return RenewalState(
                willAutoRenew: renewalInfo.willAutoRenew,
                autoRenewProductID: renewalInfo.autoRenewPreference
            )
        }
        return nil
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
