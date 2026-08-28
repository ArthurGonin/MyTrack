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
    @State private var isPurchaseFailedAlertPresented = false
    @State private var isCancelReminderPresented = false

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
                legalLink(
                    "Conditions d'utilisation",
                    systemImage: "info.square.fill",
                    tint: .gray,
                    url: LegalLinks.termsOfUse
                )
                legalLink(
                    "Confidentialité",
                    systemImage: "hand.raised.square.fill",
                    tint: .blue,
                    url: LegalLinks.privacyPolicy
                )
            }
        }
    }

    private var subscriptionSection: some View {
        Section {
            switch purchaseService.entitlement {
            case .lifetime:
                LabeledContent {
                    Text(planName(.lifetime))
                } label: {
                    SettingsRowLabel("Formule", systemImage: "tag.square.fill", tint: .indigo)
                }
                // Rien à gérer côté StoreKit pour un non-consommable : la
                // feuille système de gestion d'abonnement n'a pas de prise sur
                // lui. Sauf si un abonnement court encore — acheté avant
                // celui-ci et que l'achat n'a pas résilié : c'est alors le seul
                // bouton qui compte, celui qui mène à sa résiliation.
                if purchaseService.activeSubscription != nil {
                    Button {
                        isManageSubscriptionsPresented = true
                    } label: {
                        SettingsRowLabel("Gérer l'abonnement", systemImage: "arrow.up.right.square.fill", tint: .gray)
                    }
                }

            case .subscription(let subscription):
                LabeledContent {
                    Text(planName(subscription.plan))
                } label: {
                    SettingsRowLabel("Formule", systemImage: "tag.square.fill", tint: .indigo)
                }

                Button {
                    isManageSubscriptionsPresented = true
                } label: {
                    SettingsRowLabel("Gérer l'abonnement", systemImage: "arrow.up.right.square.fill", tint: .gray)
                }

                lifetimeUpgradeButton

            case nil:
                // Rappel visible depuis les réglages, en plus de l'écran
                // Enregistrer : c'est ici qu'on vient chercher pourquoi.
                Label {
                    Text(warningTitle)
                } icon: {
                    // Un seul glyphe pour les deux cas, comme le reste de
                    // l'écran : c'est le libellé — « Problème de paiement » ou
                    // « Aucun abonnement actif » — qui dit lequel des deux.
                    Image(systemName: "exclamationmark.square.fill")
                }
                .foregroundStyle(.red)

                // Un paiement qui échoue n'est pas une résiliation : ce qu'il
                // faut à quelqu'un qui n'a rien annulé, c'est sa carte, pas une
                // nouvelle formule.
                if purchaseService.hasBillingIssue {
                    Button {
                        isManageSubscriptionsPresented = true
                    } label: {
                        SettingsRowLabel(
                            "Mettre à jour le paiement",
                            systemImage: "arrow.up.right.square.fill",
                            tint: .gray
                        )
                    }
                } else {
                    Button {
                        isStorePresented = true
                    } label: {
                        SettingsRowLabel(
                            "Voir les formules",
                            systemImage: "tag.square.fill",
                            tint: .indigo
                        )
                    }
                }
            }

            Button {
                restore()
            } label: {
                HStack {
                    SettingsRowLabel(
                        "Restaurer les achats",
                        systemImage: "arrow.clockwise.square.fill",
                        tint: .blue
                    )
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
        .task {
            await purchaseService.refreshEntitlement()
            // Le bouton d'achat unique affiche son prix, qui vient du catalogue
            // App Store. Quelqu'un qui n'a jamais ouvert la paywall de cette
            // session n'a rien de chargé : sans ça, le bouton n'apparaîtrait
            // jamais.
            if purchaseService.products.isEmpty {
                await purchaseService.loadProducts()
            }
        }
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
        .alert("Achat impossible", isPresented: $isPurchaseFailedAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("L'achat n'a pas pu être finalisé. Réessaie plus tard.")
        }
        // App Store ne résilie rien tout seul : sans cette alerte, l'achat
        // réussirait en silence et l'abonnement continuerait de prélever à
        // côté, pour un accès déjà acquis.
        .alert("Accès à vie activé", isPresented: $isCancelReminderPresented) {
            Button("Gérer l'abonnement") { isManageSubscriptionsPresented = true }
            Button("Plus tard", role: .cancel) {}
        } message: {
            Text("Ton abonnement n'est pas résilié pour autant : App Store continuera de le reconduire tant que tu ne l'auras pas fait toi-même.")
        }
    }

    /// Le seul chemin, depuis l'app, pour passer d'un abonnement à l'achat
    /// unique. Il n'existait nulle part : la paywall d'onboarding ne se revoit
    /// pas, et la feuille App Store qui le propose ne s'ouvrait que faute
    /// d'abonnement actif — donc jamais pour quelqu'un qui en a un.
    ///
    /// Absent tant que le produit n'est pas chargé : un bouton d'achat sans
    /// prix n'est pas un bouton d'achat.
    @ViewBuilder
    private var lifetimeUpgradeButton: some View {
        if let product = purchaseService.product(for: .lifetime) {
            Button {
                buyLifetime()
            } label: {
                HStack {
                    SettingsRowLabel(
                        "Passer à l'achat unique",
                        systemImage: "arrow.up.square.fill",
                        tint: .yellow
                    )
                    Spacer()
                    if purchaseService.isPurchasing {
                        ProgressView()
                    } else {
                        // Le prix vient de l'App Store, déjà mis en forme dans
                        // la devise et le format du compte.
                        Text(product.displayPrice)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(purchaseService.isPurchasing)
        }
    }

    private func buyLifetime() {
        // Lu avant l'achat : celui-ci fait basculer `entitlement` sur
        // `.lifetime`, après quoi on ne saurait plus dire s'il y avait un
        // abonnement à résilier.
        let hadSubscription = purchaseService.activeSubscription != nil
        Task {
            switch await purchaseService.purchase(.lifetime) {
            case .success:
                if hadSubscription { isCancelReminderPresented = true }
            case .failed:
                isPurchaseFailedAlertPresented = true
            // Comme dans la paywall : un achat annulé n'a rien à annoncer, et
            // un achat en attente d'approbation remontera de lui-même par
            // Transaction.updates le jour où il sera validé.
            case .userCancelled, .pending:
                break
            }
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
            // « Sans abonnement ni reconduction » devient un mensonge tant que
            // l'abonnement d'avant court encore — et un mensonge qui coûte de
            // l'argent à qui le croit.
            guard purchaseService.activeSubscription == nil else {
                return String(localized: "Ton accès à vie est acquis. Ton abonnement, lui, court toujours et sera reconduit : résilie-le pour ne pas payer deux fois.", bundle: localizationBundle, locale: locale)
            }
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
    ///
    /// La flèche oblique annonce ce que la ligne fait vraiment : quitter l'app
    /// pour le navigateur. Sans elle, la ligne ressemble à toutes celles qui
    /// poussent un écran, et le départ vers Safari surprend.
    @ViewBuilder
    private func legalLink(
        _ title: LocalizedStringKey,
        systemImage: String,
        tint: Color,
        url: URL?
    ) -> some View {
        if let url {
            Link(destination: url) {
                HStack {
                    SettingsRowLabel(title, systemImage: systemImage, tint: tint)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
        } else {
            // Ligne inerte : l'icône s'éteint avec le texte plutôt que de
            // garder sa couleur, qui donnerait l'air d'un lien cliquable.
            Label(title, systemImage: systemImage).foregroundStyle(.tertiary)
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
