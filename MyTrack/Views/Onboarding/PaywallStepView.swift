//
//  PaywallStepView.swift
//  MyTrack
//

import StoreKit
import SwiftUI

private enum ComparisonRating {
    case yes
    case no
    case unclear

    var symbolName: String {
        switch self {
        case .yes: "checkmark"
        case .no: "xmark"
        case .unclear: "minus"
        }
    }

    var color: Color {
        switch self {
        case .yes: .green
        case .no: .red
        case .unclear: .orange
        }
    }
}

private struct ComparisonRow: Identifiable {
    let id = UUID()
    let label: String
    let competitorRating: ComparisonRating
}

private let comparisonRows: [ComparisonRow] = [
    ComparisonRow(label: "Sécurité des données", competitorRating: .unclear),
    ComparisonRow(label: "Trajets illimités", competitorRating: .no),
    ComparisonRow(label: "Véhicules illimités", competitorRating: .no),
    ComparisonRow(label: "Rapports PDF inclus", competitorRating: .unclear),
    ComparisonRow(label: "Détection automatique", competitorRating: .unclear),
    ComparisonRow(label: "Prix honnête*", competitorRating: .no),
]

struct PaywallStepView: View {
    @Binding var selectedPlan: PricingPlan
    let products: [Product]
    let isLoadingProducts: Bool
    let isPurchasing: Bool
    let isRestoring: Bool
    let onPurchase: () async -> PurchaseOutcome
    let onRestore: () async -> Bool
    let onContinue: () -> Void

    @State private var isPurchaseFailedAlertPresented = false
    @State private var isRestoreFailedAlertPresented = false

    private var annualProduct: Product? {
        products.first { $0.id == PurchaseService.annualProductID }
    }

    private var monthlyProduct: Product? {
        products.first { $0.id == PurchaseService.monthlyProductID }
    }

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Pourquoi MyTrack")
                        .font(.largeTitle.bold())

                    comparisonTable

                    Text("* Certaines apps concurrentes facturent en fonction du kilométrage parcouru.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isLoadingProducts || isPurchasing || isRestoring {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            VStack(spacing: 8) {
                // Le tarif reste hors du ScrollView, avec le bouton d'achat :
                // c'est ce sur quoi l'écran demande de se prononcer, donc ça ne
                // doit jamais dépendre d'un défilement. Seul l'argumentaire
                // défile.
                pricingOptions
                    .padding(.bottom, 4)

                // maxWidth belongs on the label — on the button it only widens
                // the surrounding frame and leaves the control hugging "J'y vais".
                Button { purchase() } label: {
                    Text("J'y vais").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Restaurer les achats") { restore() }
                    .font(.footnote)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                legalFooter
            }
            .disabled(isLoadingProducts || isPurchasing || isRestoring)
        }
        .padding()
        .alert("Achat impossible", isPresented: $isPurchaseFailedAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("L'achat n'a pas pu être finalisé. Réessaie plus tard.")
        }
        .alert("Aucun abonnement trouvé", isPresented: $isRestoreFailedAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nous n'avons trouvé aucun abonnement actif à restaurer pour ce compte.")
        }
    }

    private func purchase() {
        Task {
            switch await onPurchase() {
            case .success:
                onContinue()
            case .userCancelled, .pending:
                break
            case .failed:
                isPurchaseFailedAlertPresented = true
            }
        }
    }

    private func restore() {
        Task {
            if await onRestore() {
                onContinue()
            } else {
                isRestoreFailedAlertPresented = true
            }
        }
    }

    /// Exigé par la règle App Review 3.1.2 : durée et reconduction annoncées
    /// en clair, plus un lien vers les conditions d'utilisation et la
    /// politique de confidentialité.
    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text("Renouvellement automatique, résiliable à tout moment depuis ton compte App Store. Sans résiliation au moins 24 h avant la fin de l'essai, l'abonnement devient payant.")
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                legalLink("Conditions d'utilisation", url: LegalLinks.termsOfUse)
                Text("·")
                legalLink("Confidentialité", url: LegalLinks.privacyPolicy)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    /// Grisé tant que l'URL n'est pas renseignée dans `LegalLinks` : un lien
    /// mort serait pire qu'un libellé inerte.
    @ViewBuilder
    private func legalLink(_ title: String, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
        } else {
            Text(title).foregroundStyle(.tertiary)
        }
    }

    private var comparisonTable: some View {
        Grid(alignment: .center, horizontalSpacing: 12, verticalSpacing: 16) {
            GridRow {
                Text("")
                Text("MyTrack")
                    .font(.subheadline.bold())
                    .foregroundStyle(.tint)
                Text("Autres apps")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(comparisonRows) { row in
                GridRow {
                    Text(row.label)
                        .font(.subheadline)
                        .gridColumnAlignment(.leading)
                    ComparisonBadge(rating: .yes)
                    ComparisonBadge(rating: row.competitorRating)
                }
            }
        }
    }

    private var pricingOptions: some View {
        HStack(spacing: 12) {
            PricingOptionCard(
                isSelected: selectedPlan == .annual,
                title: annualTitle,
                subtitle: annualSubtitle
            ) {
                selectedPlan = .annual
            }

            PricingOptionCard(
                isSelected: selectedPlan == .monthly,
                title: monthlyTitle,
                subtitle: nil
            ) {
                selectedPlan = .monthly
            }
        }
    }

    /// Falls back to the static copy whenever the product hasn't loaded yet
    /// (first launch, before the fetch completes) or failed to load (no
    /// StoreKit config wired up, no network) — the paywall must never show a
    /// blank price.
    private var annualTitle: String {
        guard let offer = annualProduct?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else {
            return "7 jours gratuits"
        }
        return freeTrialTitle(for: offer.period)
    }

    private var annualSubtitle: String {
        guard let annualProduct else { return "puis 24,99 € / an" }
        return "puis \(annualProduct.displayPrice) / an"
    }

    private var monthlyTitle: String {
        guard let monthlyProduct else { return "2,99 € / mois" }
        return "\(monthlyProduct.displayPrice) / mois"
    }

    private func freeTrialTitle(for period: Product.SubscriptionPeriod) -> String {
        let count = period.value
        switch period.unit {
        case .day: return "\(count) jour\(count > 1 ? "s" : "") gratuit\(count > 1 ? "s" : "")"
        // Spelled out in days so the real product reads the same as the
        // fallback copy above ("7 jours gratuits"), not "1 semaine gratuite".
        case .week: return "\(count * 7) jours gratuits"
        case .month: return "\(count) mois gratuit\(count > 1 ? "s" : "")"
        case .year: return "\(count) an\(count > 1 ? "s" : "") gratuit\(count > 1 ? "s" : "")"
        @unknown default: return "Essai gratuit"
        }
    }
}

private struct ComparisonBadge: View {
    let rating: ComparisonRating

    var body: some View {
        Image(systemName: rating.symbolName)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(rating.color, in: Circle())
    }
}

private struct PricingOptionCard: View {
    let isSelected: Bool
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle ?? " ")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(subtitle == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallStepView(
        selectedPlan: .constant(.annual),
        products: [],
        isLoadingProducts: false,
        isPurchasing: false,
        isRestoring: false,
        onPurchase: { .success },
        onRestore: { false },
        onContinue: {}
    )
    .appBackground()
}
