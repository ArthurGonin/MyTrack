//
//  SubscriptionStoreSheet.swift
//  MyTrack
//
//  La vitrine d'abonnement présentée hors onboarding : depuis les réglages, et
//  depuis l'onglet Enregistrer quand l'abonnement n'est plus actif.
//

import StoreKit
import SwiftUI

/// La vitrine native de StoreKit plutôt qu'une reprise de `PaywallStepView` :
/// celle-ci attend tout son état de l'onboarding, et Apple fournit déjà
/// l'écran d'achat, avec ses prix, son essai gratuit et ses mentions légales.
struct SubscriptionStoreSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            SubscriptionStoreView(productIDs: PurchaseService.orderedProductIDs) {
                VStack(spacing: 12) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text("MyTrack")
                        .font(.largeTitle.bold())
                    Text("Trajets illimités, véhicules illimités, détection automatique et rapports PDF.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
            }
            .subscriptionStoreControlStyle(.prominentPicker)
            .storeButton(.visible, for: .restorePurchases)
            .modifier(LegalPolicyDestinations())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { isPresented = false }
                }
            }
        }
    }
}

/// Les deux liens légaux ne peuvent être branchés que si les URL existent —
/// d'où un modificateur à part, plutôt qu'un `if let` au milieu de la vitrine.
private struct LegalPolicyDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modifier(OptionalPolicyDestination(url: LegalLinks.termsOfUse, policy: .termsOfService))
            .modifier(OptionalPolicyDestination(url: LegalLinks.privacyPolicy, policy: .privacyPolicy))
    }
}

private struct OptionalPolicyDestination: ViewModifier {
    let url: URL?
    let policy: SubscriptionStorePolicyKind

    @ViewBuilder
    func body(content: Content) -> some View {
        if let url {
            content.subscriptionStorePolicyDestination(url: url, for: policy)
        } else {
            content
        }
    }
}
