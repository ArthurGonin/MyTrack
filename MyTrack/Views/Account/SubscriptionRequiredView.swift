//
//  SubscriptionRequiredView.swift
//  MyTrack
//
//  Ce qu'un écran montre à la place de ce qu'il ne peut plus faire, faute
//  d'abonnement actif.
//
//  Deux écrans s'en servent — l'accueil, qui n'enregistre plus, et la feuille de
//  nouveau rapport, qui n'en génère plus — et ils doivent le dire de la même
//  façon : même glyphe, même titre, même bouton, même distinction entre un
//  abonnement expiré et un paiement qui échoue. Seule la phrase du milieu change,
//  parce qu'elle nomme ce qui est perdu, et que ce n'est pas la même chose ici et
//  là.
//
//  Rouge, et pas le gris d'un écran vide : ce n'est pas « il n'y a rien ici »,
//  c'est « ça ne tourne plus ».
//
//  Un paiement qui échoue n'est pas une résiliation : proposer une nouvelle
//  formule à quelqu'un qui n'a rien annulé ne réglerait pas son problème. Ce
//  qu'il lui faut, c'est sa carte — d'où la feuille de gestion d'abonnement
//  plutôt que la vitrine.
//

import StoreKit
import SwiftUI

struct SubscriptionRequiredView: View {
    /// Ce que l'écran ne peut plus faire, dans ses propres termes.
    let description: LocalizedStringKey
    /// La même chose, quand le renouvellement a échoué au lieu d'expirer.
    let billingIssueDescription: LocalizedStringKey

    @Environment(AppServices.self) private var appServices
    @State private var isSubscriptionStorePresented = false
    @State private var isManageSubscriptionsPresented = false

    private var hasBillingIssue: Bool { appServices.purchaseService.hasBillingIssue }

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(hasBillingIssue ? "Problème de paiement" : "Abonnement inactif")
            } icon: {
                Image(systemName: hasBillingIssue
                    ? "creditcard.trianglebadge.exclamationmark"
                    : "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } description: {
            Text(hasBillingIssue ? billingIssueDescription : description)
        } actions: {
            Button(hasBillingIssue ? "Mettre à jour le paiement" : "Se réabonner") {
                if hasBillingIssue {
                    isManageSubscriptionsPresented = true
                } else {
                    isSubscriptionStorePresented = true
                }
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color.onAccent)
            .controlSize(.large)
        }
        .sheet(isPresented: $isSubscriptionStorePresented) {
            SubscriptionStoreSheet(isPresented: $isSubscriptionStorePresented)
        }
        .manageSubscriptionsSheet(isPresented: $isManageSubscriptionsPresented)
    }
}

#Preview {
    SubscriptionRequiredView(
        description: "L'enregistrement des trajets nécessite un abonnement actif. Vos trajets et rapports déjà enregistrés restent accessibles.",
        billingIssueDescription: "Votre abonnement n'a pas pu être renouvelé : vos trajets ne sont plus enregistrés. Vos trajets et rapports restent accessibles."
    )
    .appBackground()
}
