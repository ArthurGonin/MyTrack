//
//  SubscriptionSettingsSection.swift
//  MyTrack
//
//  La section « Abonnement » des réglages. Jusqu'ici, tout ce qui touchait à
//  l'abonnement vivait dans la paywall d'onboarding, écran vu une seule fois :
//  après ça, plus aucun moyen de voir son abonnement, de le résilier, de le
//  restaurer après une réinstallation, ni de relire les conditions. Restaurer
//  ses achats et atteindre les deux pages légales depuis l'app sont exigés par
//  App Review (règles 3.1.1 et 3.1.2) ; le reste est ce qu'un utilisateur
//  s'attend à trouver dans des réglages iOS.
//

import StoreKit
import SwiftUI

struct SubscriptionSettingsSection: View {
    @Environment(AppServices.self) private var appServices

    @State private var isManageSubscriptionsPresented = false
    @State private var isStorePresented = false
    @State private var restoreOutcome: RestoreOutcome?

    private enum RestoreOutcome {
        case restored
        case notFound
    }

    private var purchaseService: PurchaseService { appServices.purchaseService }

    var body: some View {
        // Les modificateurs vivent sur la section elle-même, pas sur le
        // Group : un Group applique ce qu'on lui pose à *chacun* de ses
        // enfants, ce qui lancerait deux fois la tâche et brancherait deux
        // fois la même feuille.
        Group {
            subscriptionSection

            Section {
                legalLink("Conditions d'utilisation", url: LegalLinks.termsOfUse)
                legalLink("Confidentialité", url: LegalLinks.privacyPolicy)
            }
        }
    }

    private var subscriptionSection: some View {
        Section {
            if let subscription = purchaseService.subscription {
                LabeledContent("Formule", value: planName(subscription.plan))

                Button("Gérer l'abonnement") {
                    isManageSubscriptionsPresented = true
                }
            } else {
                // Rappel visible depuis les réglages, en plus de l'écran
                // Enregistrer : c'est ici qu'on vient chercher pourquoi.
                Label {
                    Text(purchaseService.hasBillingIssue ? "Problème de paiement" : "Aucun abonnement actif")
                } icon: {
                    Image(systemName: purchaseService.hasBillingIssue
                        ? "creditcard.trianglebadge.exclamationmark"
                        : "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)

                // Un paiement qui échoue n'est pas une résiliation : ce qu'il
                // faut à quelqu'un qui n'a rien annulé, c'est sa carte, pas une
                // nouvelle formule.
                if purchaseService.hasBillingIssue {
                    Button("Mettre à jour le paiement") {
                        isManageSubscriptionsPresented = true
                    }
                } else {
                    Button("Voir les formules") {
                        isStorePresented = true
                    }
                }
            }

            Button {
                restore()
            } label: {
                HStack {
                    Text("Restaurer les achats")
                    if purchaseService.isRestoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(purchaseService.isRestoring)
        } header: {
            Text("Abonnement")
        } footer: {
            Text(statusFooter)
        }
        // Un abonnement a pu se renouveler, expirer ou être résilié depuis le
        // lancement de l'app : ces réglages ne doivent pas afficher l'état
        // qu'avait StoreKit au démarrage.
        .task { await purchaseService.refreshSubscription() }
        .manageSubscriptionsSheet(isPresented: $isManageSubscriptionsPresented)
        .sheet(isPresented: $isStorePresented) {
            SubscriptionStoreSheet(isPresented: $isStorePresented)
        }
        // L'achat fait dans la feuille App Store remonte par
        // Transaction.updates, pas par un retour de fonction : c'est le
        // changement d'entitlement qui referme la feuille.
        .onChange(of: purchaseService.isSubscribed) { _, isSubscribed in
            if isSubscribed { isStorePresented = false }
        }
        .alert(
            restoreOutcome == .restored ? "Abonnement restauré" : "Aucun abonnement trouvé",
            isPresented: Binding(
                get: { restoreOutcome != nil },
                set: { if !$0 { restoreOutcome = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                restoreOutcome == .restored
                    ? "Ton abonnement a été retrouvé sur ce compte App Store."
                    : "Aucun abonnement actif n'est associé à ce compte App Store."
            )
        }
    }

    /// Le nom vient du produit App Store quand il est chargé — c'est lui qui
    /// est localisé et qui fait foi. Le repli couvre le cas « pas de réseau »,
    /// où la section doit quand même savoir nommer la formule en cours.
    private func planName(_ plan: PricingPlan) -> String {
        if let product = purchaseService.product(for: plan) {
            return product.displayName
        }
        return switch plan {
        case .annual: "Annuel"
        case .monthly: "Mensuel"
        }
    }

    /// Reconduction et fin d'abonnement sont deux informations différentes, et
    /// c'est la seule que l'utilisateur cherche vraiment ici : est-ce que je
    /// vais être débité, et quand.
    private var statusFooter: String {
        guard let subscription = purchaseService.subscription else {
            return purchaseService.hasBillingIssue
                ? "Ton abonnement n'a pas pu être renouvelé : aucun nouveau trajet n'est enregistré. Tes trajets et rapports déjà enregistrés restent accessibles."
                : "Sans abonnement actif, aucun nouveau trajet n'est enregistré. Tes trajets et rapports déjà enregistrés restent accessibles."
        }

        guard let date = subscription.expirationDate else {
            return "Abonnement actif."
        }
        let formattedDate = date.formatted(date: .long, time: .omitted)

        if subscription.isInFreeTrial {
            return subscription.willAutoRenew == false
                ? "Essai gratuit jusqu'au \(formattedDate). Aucune reconduction : l'accès s'arrêtera à cette date."
                : "Essai gratuit jusqu'au \(formattedDate), puis reconduction automatique."
        }

        return switch subscription.willAutoRenew {
        case true: "Se renouvelle automatiquement le \(formattedDate)."
        case false: "Actif jusqu'au \(formattedDate), sans reconduction."
        case nil: "Actif jusqu'au \(formattedDate)."
        }
    }

    /// Même règle que dans la paywall : tant que l'URL n'est pas renseignée
    /// dans `LegalLinks`, un libellé inerte vaut mieux qu'un lien mort.
    @ViewBuilder
    private func legalLink(_ title: String, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
        } else {
            Text(title).foregroundStyle(.tertiary)
        }
    }

    private func restore() {
        Task {
            await purchaseService.restorePurchases()
            restoreOutcome = purchaseService.isSubscribed ? .restored : .notFound
        }
    }
}
