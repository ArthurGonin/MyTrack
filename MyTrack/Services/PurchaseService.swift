//
//  PurchaseService.swift
//  MyTrack
//
//  Wraps StoreKit 2: loads the two subscription Products plus the one-time
//  lifetime Product, drives a purchase through to a finished Transaction, and
//  keeps `entitlement` in sync with Transaction.currentEntitlements —
//  including entitlement changes StoreKit reports outside of a purchase made
//  this session (renewal, refund, a purchase made on another device). L'app
//  entière est payante : cet état est la source de vérité unique, lue par la
//  paywall d'onboarding et par la section Abonnement des réglages.
//

import Foundation
import Observation
import OSLog
import StoreKit

enum PricingPlan: Equatable {
    case annual
    case monthly
    /// Achat unique, non-consommable : pas de groupe d'abonnement, pas de
    /// reconduction, pas d'expiration.
    case lifetime
}

enum PurchaseOutcome: Equatable {
    case success
    case userCancelled
    /// Awaiting approval (e.g. Ask to Buy) — not a failure, and not
    /// entitled yet either, so the paywall shouldn't advance or alert.
    case pending
    /// L'achat n'a pas abouti, mais rien ne dit qu'il n'aboutirait pas au coup
    /// suivant : réseau coupé, StoreKit qui hoquette, paiement à corriger.
    case failed
    /// Cet appareil ne peut pas conclure d'achat, et le réessayer n'y changera
    /// rien : achats restreints par un contrôle parental, produit absent de la
    /// boutique du pays.
    ///
    /// Distinct de `.failed` parce que la paywall en fait deux choses
    /// différentes : elle propose de recommencer dans un cas, et une porte de
    /// sortie dans l'autre — voir `PaywallStepView.isStoreUnreachable`.
    case unavailable
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

/// Ce que possède l'utilisateur : soit un abonnement (avec toute l'info de
/// `SubscriptionSummary`), soit un achat unique à vie, qui n'a ni expiration
/// ni reconduction ni essai gratuit — le forcer dans `SubscriptionSummary`
/// aurait laissé ces champs à nil sans que ce nil veuille dire la même chose
/// que pour un abonnement résilié.
enum PurchaseEntitlement: Equatable {
    case subscription(SubscriptionSummary)
    case lifetime
}

@MainActor
@Observable
final class PurchaseService {
    static let annualProductID = "KiwiJuice.MyTrack.annual"
    static let monthlyProductID = "KiwiJuice.MyTrack.monthly"
    static let lifetimeProductID = "KiwiJuice.MyTrack.lifetime"

    /// Tout ce que l'app vend, dans l'ordre d'affichage : ce que
    /// `loadProducts()` charge, et ce que les cartes maison de la paywall
    /// d'onboarding parcourent.
    static let orderedProductIDs = [annualProductID, monthlyProductID, lifetimeProductID]

    /// Seulement les deux abonnements, du même groupe — la seule liste que
    /// `SubscriptionStoreView` sait présenter : cette vue native n'a aucune
    /// notion d'achat non-consommable.
    static let subscriptionProductIDs = [annualProductID, monthlyProductID]

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

    /// Ce que l'utilisateur possède actuellement, ou nil si rien.
    private(set) var entitlement: PurchaseEntitlement?

    var hasEntitlement: Bool { entitlement != nil }

    /// L'abonnement en cours, s'il y en a un — y compris quand l'achat à vie
    /// l'emporte sur lui dans `entitlement`.
    ///
    /// Acheter l'accès à vie ne résilie pas l'abonnement : App Store continue
    /// de le reconduire, et seul l'utilisateur peut y mettre fin. Sans le
    /// garder ici, l'app perdrait sa trace au moment même de l'achat — plus
    /// rien à quoi accrocher le bouton qui mène à sa résiliation, et quelqu'un
    /// qui paie deux fois la même chose sans que rien ne le lui dise.
    private(set) var activeSubscription: SubscriptionSummary?

    /// Vrai quand l'abonnement n'a pas été résilié mais que le renouvellement
    /// échoue (carte expirée, plafond atteint). L'utilisateur n'a rien annulé :
    /// lui présenter une nouvelle formule serait à côté de la plaque, ce qu'il
    /// lui faut c'est la feuille de gestion d'abonnement.
    private(set) var hasBillingIssue = false

    /// Ce que l'abonnement achète : produire du *nouveau*. Enregistrer un
    /// trajet, le détecter, générer un rapport — ponctuel comme périodique.
    ///
    /// Tout ce qui existe déjà reste accessible sans abonnement : la liste des
    /// trajets, celle des rapports, et les PDF eux-mêmes s'ouvrent. On ne prend
    /// pas en otage des données déjà créées.
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

    /// Kept alive for the app's lifetime so it also reacts to entitlement
    /// changes it didn't cause directly this session.
    private var transactionUpdatesTask: Task<Void, Never>?

    /// Le chargement en cours, s'il y en a un — voir `loadProducts()`.
    private var productLoadTask: Task<Void, Never>?

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
        case .lifetime: Self.lifetimeProductID
        }
        return products.first { $0.id == id }
    }

    private static func plan(for productID: String) -> PricingPlan? {
        switch productID {
        case annualProductID: .annual
        case monthlyProductID: .monthly
        case lifetimeProductID: .lifetime
        default: nil
        }
    }

    /// Relit l'entitlement en cours, en s'assurant d'abord que les produits
    /// sont chargés (sans eux, pas d'info de reconduction). Appelé à
    /// l'ouverture des réglages : un abonnement a pu se renouveler, expirer ou
    /// être résilié depuis le lancement de l'app.
    func refreshEntitlement() async {
        await loadProducts()
        await updateEntitlements()
    }

    /// No-op once products are loaded — called eagerly from init so pricing
    /// is already there by the time onboarding reaches the paywall step, and
    /// callable again to retry an attempt that came back empty (no network at
    /// launch, StoreKit not ready yet).
    /// Un appel qui tombe pendant qu'un chargement est en vol l'attend, au lieu
    /// de repartir les mains vides.
    ///
    /// C'était un `guard !isLoadingProducts else { return }`, qui rendait la main
    /// aussitôt : la relecture que `purchase()` tente quand le produit manque
    /// retombait alors sur la même liste vide et l'achat échouait en « produit
    /// jamais chargé », pour un chargement qui aboutissait dans la seconde. Et
    /// comme la paywall compte un achat échoué comme une boutique injoignable,
    /// cela ouvrait au passage le « Continuer sans abonnement ».
    func loadProducts() async {
        guard products.isEmpty else { return }
        if let inFlight = productLoadTask {
            await inFlight.value
            return
        }
        let task = Task { await performProductLoad() }
        productLoadTask = task
        await task.value
        productLoadTask = nil
    }

    private func performProductLoad() async {
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
        // Un achat demandé alors que le produit manque ne doit pas échouer sans
        // avoir retenté : au premier lancement sans réseau, la seule tentative
        // de chargement a échoué et l'utilisateur se retrouvait devant « Achat
        // impossible » pour une raison qui n'a rien à voir avec son achat.
        if product(for: plan) == nil {
            await loadProducts()
        }

        guard let product = product(for: plan) else {
            AppLog.purchases.error("Purchase requested but \(String(describing: plan), privacy: .public) never loaded.")
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
                await updateEntitlements(including: transaction)
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
            return Self.isDefinitiveRefusal(error) ? .unavailable : .failed
        }
    }

    /// Les refus qu'il ne sert à rien de retenter.
    ///
    /// La distinction compte parce que la paywall est la seule porte d'entrée de
    /// l'app : quelqu'un dont l'appareil ne *peut pas* acheter doit pouvoir la
    /// franchir, sinon l'app ne s'ouvre jamais pour lui — et une app qui ne
    /// s'ouvre pas se fait refuser à la revue. Mais cette porte ne doit pas
    /// s'ouvrir sur un échec ordinaire, sans quoi il suffit de faire échouer un
    /// achat une fois pour passer.
    ///
    /// Un paiement refusé n'est pas ici : il se répare, et l'utilisateur a la
    /// main dessus. Le réseau non plus, pour la même raison.
    private static func isDefinitiveRefusal(_ error: Error) -> Bool {
        if let error = error as? Product.PurchaseError {
            switch error {
            case .purchaseNotAllowed, .productUnavailable: return true
            default: return false
            }
        }
        if let error = error as? StoreKitError {
            switch error {
            case .notAvailableInStorefront: return true
            default: return false
            }
        }
        return false
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
        await updateEntitlements(including: transaction)
    }

    /// - Parameter justPurchased: une transaction qu'on vient d'obtenir en
    ///   main propre, à compter en plus de ce que dit `currentEntitlements`.
    ///
    ///   Elle n'est pas redondante : `currentEntitlements` est alimenté de
    ///   façon asynchrone et ne contient pas encore, dans la foulée immédiate
    ///   d'un `purchase()`, la transaction que ce `purchase()` vient tout juste
    ///   de rendre. Sans elle, l'app relisait une liste vide et laissait
    ///   `entitlement` à nil : l'achat réussissait, la paywall se fermait, et
    ///   l'écran d'enregistrement annonçait « Abonnement inactif » à quelqu'un
    ///   qui venait de payer. Ça se réparait au lancement suivant, ce qui rend
    ///   le défaut d'autant plus déroutant.
    private func updateEntitlements(including justPurchased: Transaction? = nil) async {
        // Le non-consommable et les abonnements n'appartiennent pas au même
        // groupe, donc les deux peuvent apparaître ensemble parmi les
        // entitlements (quelqu'un qui a un abonnement en cours achète l'accès
        // à vie, par exemple). Le rachat à vie prime alors sur l'abonnement :
        // c'est l'entitlement définitif, celui qui restera vrai même si
        // l'abonnement expire ensuite.
        //
        // Entre deux abonnements du même groupe, qui eux peuvent coexister le
        // temps d'un changement de formule, prendre le dernier arrivé dans la
        // boucle rendait l'affichage dépendant de l'ordre d'itération ; c'est
        // l'achat le plus récent qui fait foi.
        var lifetimeTransaction: Transaction?
        var subscriptionTransaction: Transaction?

        // Retenir une transaction, d'où qu'elle vienne. Les deux garde-fous
        // valent surtout pour `justPurchased` : `currentEntitlements` écarte
        // déjà de lui-même ce qui est remboursé ou périmé, mais une
        // transaction reçue par `Transaction.updates` peut très bien être
        // justement une révocation, et l'injecter rendrait l'accès à
        // quelqu'un à qui on vient de le retirer.
        func consider(_ transaction: Transaction) {
            guard transaction.revocationDate == nil,
                  transaction.expirationDate.map({ $0 > .now }) ?? true,
                  let plan = Self.plan(for: transaction.productID) else { return }
            if plan == .lifetime {
                lifetimeTransaction = transaction
            } else if subscriptionTransaction == nil || subscriptionTransaction!.purchaseDate < transaction.purchaseDate {
                subscriptionTransaction = transaction
            }
        }

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            consider(transaction)
        }
        if let justPurchased { consider(justPurchased) }

        // Le résumé se construit dès qu'un abonnement existe, sans regarder
        // l'achat à vie : c'est ce qui permet à `activeSubscription` de
        // survivre au rachat, là où `entitlement` bascule sur `.lifetime` et
        // perd l'abonnement de vue.
        var subscription: SubscriptionSummary?
        if let subscriptionTransaction, let plan = Self.plan(for: subscriptionTransaction.productID) {
            let renewal = await renewalState(for: plan)
            let pendingPlan = renewal?.autoRenewProductID.flatMap(Self.plan(for:))
            subscription = SubscriptionSummary(
                plan: plan,
                pendingPlan: pendingPlan == plan ? nil : pendingPlan,
                expirationDate: subscriptionTransaction.expirationDate,
                isInFreeTrial: subscriptionTransaction.offer?.type == .introductory,
                willAutoRenew: renewal?.willAutoRenew
            )
        }
        activeSubscription = subscription

        var found: PurchaseEntitlement?
        if lifetimeTransaction != nil {
            found = .lifetime
        } else if let subscription {
            found = .subscription(subscription)
        }
        entitlement = found
        hasBillingIssue = found == nil ? await isInBillingRetry() : false
        applyAccessChange()
    }

    /// Un abonnement en échec de paiement n'apparaît plus dans les
    /// entitlements — de l'extérieur ça ressemble à une résiliation. Seul
    /// l'état du groupe d'abonnement fait la différence, et cette différence
    /// change tout ce que l'app doit dire à l'utilisateur.
    private func isInBillingRetry() async -> Bool {
        // L'annuel nommément, et non `products.first` : l'achat à vie n'a pas de
        // `subscription`, et le jour où l'ordre d'affichage changerait, cette
        // lecture rendrait `false` sans que rien ne le signale — un problème de
        // paiement se lirait alors comme une résiliation.
        guard let subscriptionInfo = product(for: .annual)?.subscription,
              let statuses = try? await subscriptionInfo.status else { return false }
        return statuses.contains { $0.state == .inBillingRetryPeriod }
    }

    /// Ne prévient que sur un vrai changement : appelée à chaque relecture des
    /// entitlements, elle ne doit pas re-notifier une perte d'accès déjà
    /// annoncée.
    private func applyAccessChange() {
        let hasAccess = hasEntitlement
        let hadAccess = canRecordTrips
        guard hadAccess != hasAccess else { return }

        // Une perte d'accès annoncée par un StoreKit qui n'a rien pu charger
        // n'est pas une perte d'accès. `currentEntitlements` revient vide dans
        // plusieurs cas où rien n'a expiré : une app restaurée depuis une
        // sauvegarde, dont les préférences reviennent avant que les transactions
        // du compte ne soient resynchronisées ; un changement de compte App
        // Store ; StoreKit indisponible. Sans cette garde, quelqu'un qui vient
        // de payer recevait « Vos trajets ne sont plus enregistrés » et voyait
        // la détection s'éteindre.
        //
        // La bascule n'est pas consommée pour autant — ni l'accès écrit sur le
        // disque, ni la notification envoyée : la prochaine relecture, celle qui
        // aura les produits en main, la traitera pour de bon. Entre les deux
        // l'accès reste ouvert, ce qui est le bon sens de l'erreur : mieux vaut
        // enregistrer un trajet de trop que de couper l'app à quelqu'un dont
        // l'abonnement court toujours.
        if hadAccess, !hasAccess, products.isEmpty {
            AppLog.purchases.notice(
                "Accès perdu selon StoreKit, mais aucun produit n'a pu être chargé — décision reportée."
            )
            return
        }

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
