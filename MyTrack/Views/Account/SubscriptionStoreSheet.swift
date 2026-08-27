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
///
/// `SubscriptionStoreView` ne sait présenter qu'un groupe d'abonnement — pas
/// l'achat unique, qui n'en fait pas partie — d'où le bouton à part, ancré en
/// bas, plutôt qu'une troisième carte dans la vitrine native elle-même.
struct SubscriptionStoreSheet: View {
    @Binding var isPresented: Bool

    @Environment(AppServices.self) private var appServices
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle
    @State private var isLifetimePurchaseFailedAlertPresented = false

    private var purchaseService: PurchaseService { appServices.purchaseService }

    private var lifetimeProduct: Product? {
        purchaseService.products.first { $0.id == PurchaseService.lifetimeProductID }
    }

    var body: some View {
        NavigationStack {
            SubscriptionStoreView(productIDs: PurchaseService.subscriptionProductIDs) {
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
            .safeAreaInset(edge: .bottom) {
                lifetimeOption
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { isPresented = false }
                }
            }
            .task {
                if purchaseService.products.isEmpty { await purchaseService.loadProducts() }
            }
            .alert("Achat impossible", isPresented: $isLifetimePurchaseFailedAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("L'achat n'a pas pu être finalisé. Réessaie plus tard.")
            }
        }
    }

    /// Achat unique, en plus des deux abonnements de la vitrine native
    /// au-dessus. La fermeture de la feuille au succès n'est pas gérée ici :
    /// comme pour un abonnement, c'est le changement d'entitlement, plus haut
    /// dans `SubscriptionSettingsSection`, qui s'en charge.
    private var lifetimeOption: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                purchaseLifetime()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Achat unique")
                            .font(.subheadline.bold())
                        Text(lifetimePriceCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if purchaseService.isPurchasing {
                        ProgressView()
                    } else {
                        Text("Acheter")
                            .font(.subheadline.bold())
                    }
                }
                .padding()
            }
            .buttonStyle(.plain)
            .disabled(purchaseService.isPurchasing || purchaseService.isRestoring)
        }
        .background(.regularMaterial)
    }

    private var lifetimePriceCaption: String {
        let price = lifetimeProduct?.displayPrice ?? "39,99 €"
        return String(localized: "\(price), une seule fois — accès à vie", bundle: localizationBundle, locale: locale)
    }

    private func purchaseLifetime() {
        Task {
            switch await purchaseService.purchase(.lifetime) {
            case .success, .userCancelled, .pending:
                break
            case .failed:
                isLifetimePurchaseFailedAlertPresented = true
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
