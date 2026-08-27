//
//  PaywallStepView.swift
//  MyTrack
//

import StoreKit
import SwiftUI

private struct PaywallFeature: Identifiable {
    let id = UUID()
    let symbolName: String
    let label: LocalizedStringKey
}

private let paywallFeatures: [PaywallFeature] = [
    PaywallFeature(symbolName: "car.fill", label: "Détection automatique"),
    PaywallFeature(symbolName: "infinity", label: "Trajets illimités"),
    PaywallFeature(symbolName: "car.2.fill", label: "Véhicules illimités"),
    PaywallFeature(symbolName: "doc.text.fill", label: "Rapports PDF inclus"),
]

// TODO: remplacer par un vrai avis, mot pour mot, une fois l'app publiée et
// notée sur l'App Store — et retirer les étoiles d'ici là si aucun avis
// n'existe encore.
//
// Une citation inventée présentée sous cinq étoiles se lit comme un avis
// d'utilisateur : c'est un faux avis, interdit par la directive européenne sur
// les pratiques commerciales déloyales (transposée en France dans le code de la
// consommation) et par les règles de l'App Store. Le risque n'est pas
// théorique : les marchés visés ici sont tous européens.
private let reviewQuote: LocalizedStringKey =
    "Elle se lance toute seule quand je prends la voiture. J'ai fini par l'oublier — c'est le plus beau compliment."

struct PaywallStepView: View {
    @Binding var selectedPlan: PricingPlan
    let products: [Product]
    let isLoadingProducts: Bool
    let isPurchasing: Bool
    let isRestoring: Bool
    let hasAttemptedProductLoad: Bool
    let onPurchase: () async -> PurchaseOutcome
    let onRestore: () async -> Bool
    let onRetryLoadProducts: () async -> Void
    let onContinue: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle
    @State private var isPurchaseFailedAlertPresented = false
    @State private var isRestoreFailedAlertPresented = false
    @State private var hasPurchaseFailed = false

    /// Whether the store has had its chance and still can't sell anything here.
    /// This screen is the only way into the app, so it must never trap someone
    /// StoreKit simply can't serve — no network, a StoreKit outage, a device
    /// that can't buy. A user who is merely undecided still has to choose:
    /// this appears only once buying has actually proved impossible.
    private var isStoreUnreachable: Bool {
        (hasAttemptedProductLoad && products.isEmpty) || hasPurchaseFailed
    }

    private var annualProduct: Product? {
        products.first { $0.id == PurchaseService.annualProductID }
    }

    private var monthlyProduct: Product? {
        products.first { $0.id == PurchaseService.monthlyProductID }
    }

    private var lifetimeProduct: Product? {
        products.first { $0.id == PurchaseService.lifetimeProductID }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Tout ce bloc doit tenir sans défiler : le tarif occupant le bas de
            // l'écran, ce qui dépasse ici part sous lui et ne se voit plus —
            // les avantages, précisément ce que la paywall a à défendre. D'où
            // des tailles resserrées plutôt que confortables. Le ScrollView
            // reste, mais comme filet pour les grandes tailles de texte et les
            // petits écrans, pas comme mode de lecture normal.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Pourquoi MyTrack")
                        .font(.title.bold())

                    ReviewQuoteCard(quote: reviewQuote)

                    VStack(spacing: 12) {
                        ForEach(paywallFeatures) { feature in
                            HStack(spacing: 14) {
                                Image(systemName: feature.symbolName)
                                    .font(.body)
                                    // Largeur fixe : sans elle, chaque symbole
                                    // pousse son libellé à une abscisse
                                    // différente et la colonne de texte ondule.
                                    .frame(width: 26)
                                    .foregroundStyle(.tint)
                                Text(feature.label)
                                    .font(.subheadline)
                                Spacer()
                            }
                        }
                    }
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

                if isStoreUnreachable {
                    Button("Continuer sans abonnement") { onContinue() }
                        .font(.footnote)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }

                legalFooter
            }
            .disabled(isLoadingProducts || isPurchasing || isRestoring)
        }
        .padding()
        // The one load attempt happens at launch; if it came back empty —
        // no network at the time — this is the moment to try again, before
        // concluding the store is out of reach.
        .task {
            if products.isEmpty { await onRetryLoadProducts() }
        }
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
                hasPurchaseFailed = true
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
    /// politique de confidentialité. Le texte de reconduction ne doit pas
    /// s'afficher pour l'achat unique : il n'y a rien à reconduire.
    private var legalFooter: some View {
        VStack(spacing: 6) {
            Text(legalDisclosure)
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

    // Typé `LocalizedStringKey` : un ternaire entre deux littéraux passé
    // directement à `Text` peut se résoudre en `String`, donc sans traduction.
    private var legalDisclosure: LocalizedStringKey {
        selectedPlan == .lifetime
            ? "Paiement unique. Ni abonnement, ni reconduction."
            : "Renouvellement automatique, résiliable à tout moment depuis ton compte App Store."
    }

    /// Grisé tant que l'URL n'est pas renseignée dans `LegalLinks` : un lien
    /// mort serait pire qu'un libellé inerte.
    @ViewBuilder
    private func legalLink(_ title: LocalizedStringKey, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
        } else {
            Text(title).foregroundStyle(.tertiary)
        }
    }

    /// Les deux abonnements se partagent la largeur, l'achat unique occupe
    /// dessous celle des deux réunis. Toutes les cartes vivent dans le même
    /// GlassEffectContainer pour que leurs matériaux se fondent les uns dans
    /// les autres, au lieu d'être trois surfaces de verre indépendantes.
    private var pricingOptions: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
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

                LifetimeOptionCard(
                    isSelected: selectedPlan == .lifetime,
                    title: lifetimeTitle,
                    subtitle: lifetimeSubtitle
                ) {
                    selectedPlan = .lifetime
                }
            }
        }
    }

    /// Falls back to the static copy whenever the product hasn't loaded yet
    /// (first launch, before the fetch completes) or failed to load (no
    /// StoreKit config wired up, no network) — the paywall must never show a
    /// blank price.
    private var annualTitle: String {
        guard let offer = annualProduct?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else {
            return freeTrialDaysTitle(days: 7)
        }
        return freeTrialTitle(for: offer.period)
    }

    /// Le prix vient de l'App Store, déjà mis en forme dans la devise et le
    /// format du compte : seule la phrase autour se traduit.
    private var annualSubtitle: String {
        let price = annualProduct?.displayPrice ?? "24,99 €"
        return String(localized: "puis \(price) / an", bundle: localizationBundle, locale: locale)
    }

    private var monthlyTitle: String {
        let price = monthlyProduct?.displayPrice ?? "2,99 €"
        return String(localized: "\(price) / mois", bundle: localizationBundle, locale: locale)
    }

    private var lifetimeTitle: String {
        lifetimeProduct?.displayPrice ?? "39,99 €"
    }

    private var lifetimeSubtitle: String {
        String(localized: "achat unique, à vie", bundle: localizationBundle, locale: locale)
    }

    private func freeTrialTitle(for period: Product.SubscriptionPeriod) -> String {
        let count = period.value
        switch period.unit {
        case .day: return freeTrialDaysTitle(days: count)
        // Spelled out in days so the real product reads the same as the
        // fallback copy above ("7 jours gratuits"), not "1 semaine gratuite".
        case .week: return freeTrialDaysTitle(days: count * 7)
        case .month: return String(localized: "\(count) mois gratuits", bundle: localizationBundle, locale: locale)
        case .year: return String(localized: "\(count) ans gratuits", bundle: localizationBundle, locale: locale)
        @unknown default: return String(localized: "Essai gratuit", bundle: localizationBundle, locale: locale)
        }
    }

    /// Le singulier n'est plus un `if` collé au mot : chaque langue accorde à
    /// sa façon, et c'est le catalogue de chaînes qui porte ses règles.
    private func freeTrialDaysTitle(days: Int) -> String {
        String(localized: "\(days) jours gratuits", bundle: localizationBundle, locale: locale)
    }
}

/// La couleur du texte posé sur une carte teintée à l'accent.
///
/// Pas `.white` : l'accent est noir en thème clair mais blanc en thème sombre,
/// où du blanc sur blanc ne se lirait plus du tout. `systemBackground` est
/// exactement son inverse — blanc en clair, noir en sombre — donc le contraste
/// tient des deux côtés sans qu'on ait à connaître le thème courant.
private var onAccentColor: Color { Color(uiColor: .systemBackground) }

private struct ReviewQuoteCard: View {
    let quote: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                }
            }
            .font(.footnote)
            .foregroundStyle(.yellow)
            .accessibilityElement()
            .accessibilityLabel("5 étoiles sur 5")

            Text(quote)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                // Sans ça, une citation de trois lignes se fait tronquer par la
                // hauteur que le ScrollView propose au lieu de la réclamer.
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .appCard(padding: 18)
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
                    .foregroundStyle(isSelected ? onAccentColor : .primary)
                Text(subtitle ?? " ")
                    .font(.footnote)
                    .foregroundStyle(isSelected ? onAccentColor.opacity(0.85) : .secondary)
                    .opacity(subtitle == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        // La sélection se lit au matériau lui-même — verre teinté à l'accent
        // contre verre neutre — plutôt qu'à un liseré dessiné par-dessus.
        .glassEffect(
            isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 14)
        )
    }
}

/// L'achat unique : pleine largeur sous les deux abonnements, et distinct
/// d'eux même quand il n'est pas coché.
///
/// C'est la formule que l'écran met en avant, donc elle ne peut pas n'être
/// qu'une troisième case identique aux autres. Sa mise en avant ne passe pas
/// par une couleur de plus — l'app est en noir et blanc, une teinte inventée
/// jurerait — mais par le liseré à l'accent qu'elle garde en permanence et par
/// son étiquette. Cochée, elle se remplit d'accent comme les autres, si bien
/// que « mise en avant » et « sélectionnée » restent deux états lisibles.
private struct LifetimeOptionCard: View {
    let isSelected: Bool
    let title: String
    let subtitle: String
    let action: () -> Void

    /// La couleur du texte courant, selon que la carte est remplie d'accent ou
    /// laissée en verre clair.
    private var foreground: Color { isSelected ? onAccentColor : .primary }

    var body: some View {
        Button(action: action) {
            // Pas de coche ni de pastille : le remplissage à l'accent dit déjà
            // laquelle des trois cartes est retenue, et un second indicateur du
            // même état n'ajoute rien qu'un point de plus à regarder.
            VStack(alignment: .leading, spacing: 6) {
                badge

                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(foreground)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(foreground.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .buttonStyle(.plain)
        // Non retenue, la carte garde un gris très léger dans son verre — assez
        // pour se détacher des deux abonnements au-dessus, pas assez pour se
        // faire passer pour sélectionnée.
        .glassEffect(
            isSelected
                ? .regular.tint(.accentColor).interactive()
                : .regular.tint(Color.primary.opacity(0.07)).interactive(),
            in: .rect(cornerRadius: 14)
        )
        .overlay {
            if !isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1.5)
            }
        }
    }

    /// L'étiquette s'inverse avec la carte : fond accent sur carte claire, fond
    /// clair sur carte accent. Le contraste est maximal dans les deux sens.
    private var badge: some View {
        Text("Sans abonnement")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isSelected ? Color.accentColor : onAccentColor)
            .background(isSelected ? onAccentColor : Color.accentColor, in: .capsule)
    }
}

#Preview {
    PaywallStepView(
        selectedPlan: .constant(.lifetime),
        products: [],
        isLoadingProducts: false,
        isPurchasing: false,
        isRestoring: false,
        hasAttemptedProductLoad: true,
        onPurchase: { .success },
        onRestore: { false },
        onRetryLoadProducts: {},
        onContinue: {}
    )
    .appBackground()
}
