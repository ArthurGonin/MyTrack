//
//  PaywallStepView.swift
//  MyTrack
//

import StoreKit
import SwiftUI

/// La couleur de mise en avant de l'écran : le ruban « Meilleure offre », le
/// liseré de la carte à vie, l'étiquette d'économie de l'annuel.
///
/// Le bleu système, et non l'accent : l'accent de l'app est un noir qui devient
/// blanc (voir `Color.onAccent`), et il dit déjà « ce que tu as choisi » sur le
/// bouton et sur la coche. Dire « ce qu'on te recommande » avec la même couleur
/// rendrait les deux états impossibles à distinguer. `.blue` s'adapte au thème,
/// là où le bleu figé de la maquette resterait pâle sur fond sombre.
private let highlightColor = Color.blue

/// Le rayon des cartes de formule, partagé par le fond, le liseré et la zone
/// tactile — les trois doivent décrire exactement la même forme.
private let planCornerRadius: CGFloat = 20

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

    private var isBusy: Bool { isPurchasing || isRestoring }

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
        // La page ne défile pas : comme les six autres étapes de l'onboarding,
        // elle tient d'un seul tenant. Tout ce qui dépasserait passerait sous
        // le bouton et ne se verrait plus — à commencer par la formule mise en
        // avant, la dernière des trois. C'est ce qui explique les tailles
        // serrées de tout ce qui suit : elles sont calées pour que l'écran
        // entier tienne sur un iPhone 17, marge du ruban comprise.
        VStack(spacing: 14) {
            header
            plans
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 4)
        // The one load attempt happens at launch; if it came back empty —
        // no network at the time — this is the moment to try again, before
        // concluding the store is out of reach.
        .task {
            if products.isEmpty { await onRetryLoadProducts() }
        }
        .alert("Achat impossible", isPresented: $isPurchaseFailedAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("L'achat n'a pas pu être finalisé. Réessayez plus tard.")
        }
        .alert("Aucun abonnement trouvé", isPresented: $isRestoreFailedAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nous n'avons trouvé aucun abonnement actif à restaurer pour ce compte.")
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Image("AppMark")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .accessibilityHidden(true)

            // Le nom de l'app ne se traduit pas : `verbatim` pour qu'il ne
            // devienne pas une clé de plus dans le catalogue de chaînes.
            Text(verbatim: "MyTrack")
                .font(.largeTitle.bold())

            Text("Passez à la vitesse supérieure.")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("Choisissez le plan qui vous convient et débloquez tout le potentiel de MyTrack.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        // Sans ça, un titre de trois lignes — une langue plus longue, un grand
        // corps de texte — se fait tronquer par la hauteur qu'on lui propose au
        // lieu de la réclamer.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var plans: some View {
        VStack(spacing: 10) {
            PlanOptionCard(
                symbolName: "calendar",
                title: "Mensuel",
                subtitle: localized("Accès complet, résiliable à tout moment."),
                price: PriceDisplay.price(of: monthlyProduct),
                priceCaption: "/ mois",
                isPriceKnown: monthlyProduct != nil,
                savingsLabel: nil,
                isRecommended: false,
                isSelected: selectedPlan == .monthly
            ) {
                selectedPlan = .monthly
            }

            PlanOptionCard(
                symbolName: "calendar.badge.clock",
                title: "Annuel",
                subtitle: annualSubtitle,
                price: PriceDisplay.price(of: annualProduct),
                priceCaption: "/ an",
                isPriceKnown: annualProduct != nil,
                savingsLabel: annualSavingsLabel,
                isRecommended: false,
                isSelected: selectedPlan == .annual
            ) {
                selectedPlan = .annual
            }

            PlanOptionCard(
                symbolName: "infinity",
                title: "À vie",
                subtitle: localized("Un seul paiement, pour toujours."),
                price: PriceDisplay.price(of: lifetimeProduct),
                priceCaption: "paiement unique",
                isPriceKnown: lifetimeProduct != nil,
                savingsLabel: nil,
                isRecommended: true,
                isSelected: selectedPlan == .lifetime
            ) {
                selectedPlan = .lifetime
            }
            // La place que le ruban vient occuper à cheval sur le bord haut de
            // la carte, pour qu'il ne vienne pas mordre la carte du dessus.
            .padding(.top, 10)
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPlan)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            // maxWidth belongs on the label — on the button it only widens
            // the surrounding frame and leaves the control hugging its title.
            Button { purchase() } label: {
                Group {
                    if isBusy {
                        ProgressView().tint(Color.onAccent)
                    } else {
                        Text("Continuer")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color.onAccent)
            .glassEffect(.clear.interactive())
            .controlSize(.large)

            if isStoreUnreachable {
                Button("Continuer sans abonnement") { onContinue() }
                    .font(.footnote)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            legalFooter
        }
        .disabled(isLoadingProducts || isBusy)
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
        VStack(spacing: 8) {
            Text(legalDisclosure)
                .font(.caption2)
                .multilineTextAlignment(.center)

            // Les trois liens tiennent sur une ligne, comme dans la maquette.
            // `minimumScaleFactor` est la soupape des langues plus longues que
            // le français : mieux vaut un point de moins que trois liens
            // tronqués.
            HStack(spacing: 6) {
                Button("Restaurer mes achats") { restore() }
                    .buttonStyle(.plain)
                Text(verbatim: "·").accessibilityHidden(true)
                legalLink("Conditions d'utilisation", url: LegalLinks.termsOfUse)
                Text(verbatim: "·").accessibilityHidden(true)
                legalLink("Confidentialité", url: LegalLinks.privacyPolicy)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.secondary)
    }

    // Typé `LocalizedStringKey` : un ternaire entre deux littéraux passé
    // directement à `Text` peut se résoudre en `String`, donc sans traduction.
    private var legalDisclosure: LocalizedStringKey {
        selectedPlan == .lifetime
            ? "Paiement unique. Ni abonnement, ni reconduction."
            : "Renouvellement automatique, résiliable à tout moment depuis votre compte App Store."
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

    /// Une chaîne du catalogue, résolue dans la langue que l'app s'est choisie.
    ///
    /// Les sous-titres des cartes sont des `String` et non des
    /// `LocalizedStringKey` — l'annuel compose le sien à partir de la durée
    /// d'essai — et une chaîne construite hors de SwiftUI ne passe pas d'elle-
    /// même par le bundle de langue de l'app : sans ces deux arguments, elle
    /// retomberait dans la langue du système.
    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: localizationBundle, locale: locale)
    }

    /// Ce que dit la carte annuelle sous son titre : l'essai gratuit quand le
    /// produit en porte un, la promesse d'économie sinon.
    ///
    /// L'essai est ce que la formule a de plus fort à offrir, et il se lit sur
    /// l'offre attachée au produit — jamais écrit en dur. Tant que StoreKit n'a
    /// rien livré, on ne sait pas s'il y en a un : la carte s'en tient alors à
    /// l'engagement annuel plutôt que d'annoncer des jours gratuits qu'on ne
    /// pourrait pas tenir.
    private var annualSubtitle: String {
        guard let offer = annualProduct?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else {
            return localized("Économisez avec un engagement annuel.")
        }
        let trial = freeTrialTitle(for: offer.period)
        return localized("\(trial), puis engagement annuel.")
    }

    private func freeTrialTitle(for period: Product.SubscriptionPeriod) -> String {
        let count = period.value
        switch period.unit {
        case .day: return freeTrialDaysTitle(days: count)
        // Spelled out in days so a seven-day trial reads "7 jours gratuits"
        // rather than "1 semaine gratuite".
        case .week: return freeTrialDaysTitle(days: count * 7)
        case .month: return localized("\(count) mois gratuits")
        case .year: return localized("\(count) ans gratuits")
        @unknown default: return localized("Essai gratuit")
        }
    }

    /// Le singulier n'est plus un `if` collé au mot : chaque langue accorde à
    /// sa façon, et c'est le catalogue de chaînes qui porte ses règles.
    private func freeTrialDaysTitle(days: Int) -> String {
        localized("\(days) jours gratuits")
    }

    /// Ce que l'annuel fait économiser sur douze mensualités, calculé sur les
    /// prix réels de la boutique.
    ///
    /// Jamais écrit en dur : un « 30 % » figé dans le code deviendrait faux à
    /// la première grille tarifaire retouchée, et une remise annoncée à tort
    /// est exactement le genre de mention que l'App Store refuse. Nil tant que
    /// les deux prix ne sont pas connus — il n'y a alors rien à comparer.
    private var annualSavingsLabel: String? {
        guard let annual = annualProduct, let monthly = monthlyProduct else { return nil }
        let twelveMonths = monthly.price * 12
        guard twelveMonths > 0, annual.price < twelveMonths else { return nil }

        let saved = (twelveMonths - annual.price) / twelveMonths
        let percent = saved.formatted(.percent.precision(.fractionLength(0)).locale(locale))
        return String(localized: "Économisez \(percent)", bundle: localizationBundle, locale: locale)
    }
}

/// Une des trois formules.
///
/// Tout le rectangle est le bouton, pas seulement son texte : le fond, le
/// liseré et le `contentShape` décrivent la même forme, si bien qu'un doigt
/// posé n'importe où sur la carte — sur l'icône, dans le blanc entre le titre
/// et le prix, sur le rond — la sélectionne.
private struct PlanOptionCard: View {
    let symbolName: String
    let title: LocalizedStringKey
    /// Déjà traduit par l'appelant : celui de l'annuel se compose autour de la
    /// durée d'essai, qui ne se connaît qu'à l'exécution.
    let subtitle: String
    let price: String
    let priceCaption: LocalizedStringKey
    /// Faux tant que StoreKit n'a pas livré le produit. Ici seul le montant en
    /// sort — le titre, la description et la mention de durée restent vrais
    /// sans lui — donc la barre grise ne couvre que cette ligne-là.
    let isPriceKnown: Bool
    /// L'étiquette d'économie, quand elle est calculable ; nil sinon.
    let savingsLabel: String?
    /// La formule que l'écran met en avant : ruban, fond teinté et liseré, même
    /// quand elle n'est pas cochée.
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: planCornerRadius, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                symbol
                details
                Spacer(minLength: 6)
                priceColumn
                selectionIndicator
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background {
                shape
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay {
                        if isRecommended { shape.fill(highlightColor.opacity(0.08)) }
                    }
            }
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1.5)
            }
            .overlay(alignment: .top) {
                if isRecommended { recommendedRibbon.offset(y: -11) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Le liseré porte les deux états à lui seul : l'accent quand la carte est
    /// cochée, le bleu de recommandation sinon — jamais les deux, sans quoi
    /// « choisie » et « conseillée » se confondraient.
    private var borderColor: Color {
        if isSelected { return .accentColor }
        return isRecommended ? highlightColor.opacity(0.45) : .clear
    }

    private var symbol: some View {
        Image(systemName: symbolName)
            .font(.system(size: 19))
            .foregroundStyle(.secondary)
            .frame(width: 42, height: 42)
            .background(Color(uiColor: .tertiarySystemFill), in: .circle)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let savingsLabel {
                Text(savingsLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(highlightColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(highlightColor.opacity(0.12), in: .capsule)
                    .padding(.top, 2)
            }
        }
    }

    /// `layoutPriority` : sans elle, c'est le montant qui se fait comprimer
    /// quand la description du dessus est longue — « 24,99 € » finirait tronqué
    /// pour laisser de la place à une phrase secondaire.
    private var priceColumn: some View {
        VStack(spacing: 1) {
            Text(price)
                .font(.title3.bold())
                .redacted(reason: isPriceKnown ? [] : .placeholder)
            Text(priceCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }

    /// Le rond de sélection. Il n'est pas un bouton à lui seul : c'est la carte
    /// entière qui coche, il ne fait que montrer laquelle l'est.
    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
    }

    /// Le ruban est posé à cheval sur le bord haut de la carte. Blanc sur bleu
    /// dans les deux thèmes : le bleu système reste assez soutenu pour ça,
    /// contrairement à l'accent qui, lui, s'inverse.
    private var recommendedRibbon: some View {
        Text("Meilleure offre")
            .textCase(.uppercase)
            .font(.caption2.weight(.bold))
            .kerning(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(highlightColor, in: .capsule)
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
    .padding()
    .appBackground()
}
