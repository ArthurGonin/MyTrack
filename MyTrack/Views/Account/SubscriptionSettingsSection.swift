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
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    @State private var isManageSubscriptionsPresented = false
    @State private var isStorePresented = false
    @State private var restoreOutcome: RestoreOutcome?

    private enum RestoreOutcome {
        case restoredSubscription
        case restoredLifetime
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
            switch purchaseService.entitlement {
            case .lifetime:
                LabeledContent("Formule", value: planName(.lifetime))
                // Rien à gérer côté StoreKit pour un non-consommable : la
                // feuille système de gestion d'abonnement n'a pas de prise sur
                // lui, donc pas de bouton "Gérer l'abonnement" ici.

            case .subscription(let subscription):
                LabeledContent("Formule", value: planName(subscription.plan))

                Button("Gérer l'abonnement") {
                    isManageSubscriptionsPresented = true
                }

            case nil:
                // Rappel visible depuis les réglages, en plus de l'écran
                // Enregistrer : c'est ici qu'on vient chercher pourquoi.
                Label {
                    Text(warningTitle)
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
        .task { await purchaseService.refreshEntitlement() }
        .manageSubscriptionsSheet(isPresented: $isManageSubscriptionsPresented)
        // La feuille système ne dit rien de ce que l'utilisateur y a fait, et un
        // changement de formule différé ne produit aucune transaction : sans
        // cette relecture à la fermeture, la ligne Formule reste sur l'ancienne
        // valeur jusqu'à la prochaine ouverture des réglages.
        .onChange(of: isManageSubscriptionsPresented) { _, isPresented in
            guard !isPresented else { return }
            Task { await purchaseService.refreshEntitlement() }
        }
        .sheet(isPresented: $isStorePresented) {
            SubscriptionStoreSheet(isPresented: $isStorePresented)
        }
        // L'achat fait dans la feuille App Store remonte par
        // Transaction.updates, pas par un retour de fonction : c'est le
        // changement d'entitlement qui referme la feuille — pour un
        // abonnement comme pour l'achat unique.
        .onChange(of: purchaseService.hasEntitlement) { _, hasEntitlement in
            if hasEntitlement { isStorePresented = false }
        }
        .alert(
            restoreTitle,
            isPresented: Binding(
                get: { restoreOutcome != nil },
                set: { if !$0 { restoreOutcome = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage)
        }
    }

    // Typés `LocalizedStringKey` : un ternaire entre deux littéraux passé
    // directement à `Text` peut se résoudre en `String`, donc sans traduction.
    private var warningTitle: LocalizedStringKey {
        purchaseService.hasBillingIssue ? "Problème de paiement" : "Aucun abonnement actif"
    }

    private var restoreTitle: LocalizedStringKey {
        switch restoreOutcome {
        case .restoredSubscription: "Abonnement restauré"
        case .restoredLifetime: "Achat restauré"
        case .notFound, .none: "Aucun abonnement trouvé"
        }
    }

    private var restoreMessage: LocalizedStringKey {
        switch restoreOutcome {
        case .restoredSubscription: "Ton abonnement a été retrouvé sur ce compte App Store."
        case .restoredLifetime: "Ton achat unique a été retrouvé sur ce compte App Store."
        case .notFound, .none: "Aucun abonnement actif n'est associé à ce compte App Store."
        }
    }

    /// Traduit par l'app, et non repris de `Product.displayName` : celui-ci
    /// vient d'App Store Connect et suit la langue du système, ce qui affichait
    /// « Annuel » en français au milieu d'un écran en allemand. Les deux noms
    /// sont les nôtres, autant les tenir dans la même langue que le reste.
    ///
    /// Clés explicites : « Annuel » désigne ici une formule d'abonnement et
    /// ailleurs une fréquence de rapport — deux sens que plusieurs langues ne
    /// rendent pas par le même mot.
    private func planName(_ plan: PricingPlan) -> String {
        switch plan {
        case .annual: String(localized: "plan.annual", defaultValue: "Annuel", bundle: localizationBundle, locale: locale)
        case .monthly: String(localized: "plan.monthly", defaultValue: "Mensuel", bundle: localizationBundle, locale: locale)
        case .lifetime: String(localized: "plan.lifetime", defaultValue: "Achat unique", bundle: localizationBundle, locale: locale)
        }
    }

    /// Reconduction et fin d'abonnement sont deux informations différentes, et
    /// c'est la seule que l'utilisateur cherche vraiment ici : est-ce que je
    /// vais être débité, et quand.
    private var statusFooter: String {
        switch purchaseService.entitlement {
        case nil:
            return purchaseService.hasBillingIssue
                ? String(localized: "Ton abonnement n'a pas pu être renouvelé : aucun nouveau trajet n'est enregistré. Tes trajets et rapports déjà enregistrés restent accessibles.", bundle: localizationBundle, locale: locale)
                : String(localized: "Sans abonnement actif, aucun nouveau trajet n'est enregistré. Tes trajets et rapports déjà enregistrés restent accessibles.", bundle: localizationBundle, locale: locale)

        case .lifetime:
            return String(localized: "Achat unique. Accès à vie à MyTrack, sans abonnement ni reconduction.", bundle: localizationBundle, locale: locale)

        case .subscription(let subscription):
            guard let date = subscription.expirationDate else {
                return String(localized: "Abonnement actif.", bundle: localizationBundle, locale: locale)
            }
            let formattedDate = TripFormatting.longDate(date, locale: locale)

            // Avant tout le reste : c'est la seule phrase qui explique pourquoi
            // la ligne au-dessus affiche encore l'ancienne formule.
            if let pendingPlan = subscription.pendingPlan {
                let name = planName(pendingPlan)
                return String(
                    localized: "Passe à la formule \(name) le \(formattedDate).",
                    bundle: localizationBundle,
                    locale: locale
                )
            }

            if subscription.isInFreeTrial {
                return subscription.willAutoRenew == false
                    ? String(localized: "Essai gratuit jusqu'au \(formattedDate). Aucune reconduction : l'accès s'arrêtera à cette date.", bundle: localizationBundle, locale: locale)
                    : String(localized: "Essai gratuit jusqu'au \(formattedDate), puis reconduction automatique.", bundle: localizationBundle, locale: locale)
            }

            return switch subscription.willAutoRenew {
            case true: String(localized: "Se renouvelle automatiquement le \(formattedDate).", bundle: localizationBundle, locale: locale)
            case false: String(localized: "Actif jusqu'au \(formattedDate), sans reconduction.", bundle: localizationBundle, locale: locale)
            case nil: String(localized: "Actif jusqu'au \(formattedDate).", bundle: localizationBundle, locale: locale)
            }
        }
    }

    /// Même règle que dans la paywall : tant que l'URL n'est pas renseignée
    /// dans `LegalLinks`, un libellé inerte vaut mieux qu'un lien mort.
    @ViewBuilder
    private func legalLink(_ title: LocalizedStringKey, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
        } else {
            Text(title).foregroundStyle(.tertiary)
        }
    }

    private func restore() {
        Task {
            await purchaseService.restorePurchases()
            switch purchaseService.entitlement {
            case .subscription: restoreOutcome = .restoredSubscription
            case .lifetime: restoreOutcome = .restoredLifetime
            case nil: restoreOutcome = .notFound
            }
        }
    }
}
