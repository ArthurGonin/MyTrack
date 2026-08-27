//
//  OnboardingView.swift
//  MyTrack
//
//  First-launch onboarding. Steps are driven by OnboardingStep so future
//  pages can be added by extending the enum and its switch below, without
//  touching the navigation/button logic.
//

import CoreLocation
import StoreKit
import SwiftData
import SwiftUI
import UIKit

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case name
    case units
    case vehicle
    case autoDetection
    /// Skipped when auto-detection wasn't just enabled — see `isStepVisible`.
    case tripConfirmation
    case paywall
}

struct OnboardingView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @State private var currentStepIndex = 0
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var vehicleName = ""
    @State private var licensePlate = ""
    @State private var isPermissionDeniedAlertPresented = false
    @State private var isRequestingAutoDetectionPermissions = false
    /// L'achat unique est proposé en premier : c'est la formule que la paywall
    /// met en avant, et celle qu'on retrouve donc déjà cochée en y arrivant.
    @State private var selectedPricingPlan: PricingPlan = .lifetime

    private var currentStep: OnboardingStep {
        OnboardingStep.allCases[currentStepIndex]
    }

    private var canContinue: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .name:
            return !firstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
        case .units:
            return true
        case .vehicle:
            return !vehicleName.trimmingCharacters(in: .whitespaces).isEmpty
        case .autoDetection, .tripConfirmation, .paywall:
            return true
        }
    }

    /// Steps with their own action button (auto-detection's yes/no,
    /// trip-confirmation's two choices, the paywall's "J'y vais") hide the
    /// shared bottom button instead of using it, since a single "Continuer"
    /// wouldn't fit what they need.
    private var showsGenericContinueButton: Bool {
        switch currentStep {
        case .welcome, .name, .units, .vehicle:
            return true
        case .autoDetection, .tripConfirmation, .paywall:
            return false
        }
    }

    /// Hidden (not just disabled) on the first step, and disabled while a
    /// step's own async work is in flight — going back mid permission-request
    /// or mid-purchase would leave that work racing an unrelated step.
    private var canGoBack: Bool {
        guard currentStepIndex > 0 else { return false }
        if isRequestingAutoDetectionPermissions { return false }
        if appServices.purchaseService.isPurchasing || appServices.purchaseService.isRestoring { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                OnboardingProgressBar(
                    stepCount: OnboardingStep.allCases.count,
                    currentIndex: currentStepIndex
                )

                HStack {
                    backButton
                        .opacity(currentStepIndex > 0 ? 1 : 0)
                        .disabled(!canGoBack)
                    Spacer()
                }
            }

            stepContent(for: currentStep)

            if showsGenericContinueButton {
                Button {
                    advanceStep()
                } label: {
                    Text("Continuer").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinue)
            }
        }
        .padding()
        .appBackground()
        .alert("Localisation refusée", isPresented: $isPermissionDeniedAlertPresented) {
            Button("Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Autorise l'accès à la position dans Réglages pour activer le suivi automatique.")
        }
    }

    /// Sized to match AccountButton's glass bubble (28pt content + 6pt
    /// padding) so the two floating glass controls in the app read as the
    /// same control, not two different sizes.
    private var backButton: some View {
        Button {
            retreatStep()
        } label: {
            Image(systemName: "chevron.backward")
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
                .padding(6)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Retour")
    }

    @ViewBuilder
    private func stepContent(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            @Bindable var languageService = appServices.languageService
            WelcomeLanguageStepView(selectedLanguage: $languageService.language)
        case .name:
            NameStepView(firstName: $firstName, lastName: $lastName)
        case .units:
            @Bindable var unitSettings = appServices.unitSettingsService
            UnitStepView(distanceUnit: $unitSettings.distanceUnit)
        case .vehicle:
            VehicleStepView(vehicleName: $vehicleName, licensePlate: $licensePlate)
        case .autoDetection:
            AutoDetectionStepView(
                isRequestingPermissions: isRequestingAutoDetectionPermissions,
                onEnable: enableAutoDetectionAndContinue,
                onSkip: { advanceStep() }
            )
        case .tripConfirmation:
            TripConfirmationStepView(
                onChooseConfirmation: {
                    appServices.drivingDetector.requiresTripConfirmation = true
                    advanceStep()
                },
                onChooseAutomatic: {
                    appServices.drivingDetector.requiresTripConfirmation = false
                    advanceStep()
                }
            )
        case .paywall:
            PaywallStepView(
                selectedPlan: $selectedPricingPlan,
                products: appServices.purchaseService.products,
                isLoadingProducts: appServices.purchaseService.isLoadingProducts,
                isPurchasing: appServices.purchaseService.isPurchasing,
                isRestoring: appServices.purchaseService.isRestoring,
                hasAttemptedProductLoad: appServices.purchaseService.hasAttemptedProductLoad,
                onPurchase: purchaseSelectedPlan,
                onRestore: restoreAndCheckSubscribed,
                onRetryLoadProducts: { await appServices.purchaseService.loadProducts() },
                onContinue: finish
            )
            // Someone who is already entitled — reinstalling, or coming from
            // another device — must not be asked to pay a second time, so the
            // paywall closes itself as soon as StoreKit confirms the
            // entitlement (which may land after the step is already on screen).
            .task(id: appServices.purchaseService.hasEntitlement) {
                if appServices.purchaseService.hasEntitlement {
                    finish()
                }
            }
        }
    }

    /// Whether `step` should actually be shown. Everything is visible except
    /// `.tripConfirmation`, which only makes sense once auto-detection is on —
    /// used by `advanceStep()`/`retreatStep()` so both directions skip over it
    /// the same way, instead of the forward path jumping past it explicitly
    /// while the back button stumbles into it.
    private func isStepVisible(_ step: OnboardingStep) -> Bool {
        switch step {
        case .tripConfirmation: appServices.drivingDetector.isEnabled
        default: true
        }
    }

    private func advanceStep() {
        var next = currentStepIndex + 1
        while next < OnboardingStep.allCases.count, !isStepVisible(OnboardingStep.allCases[next]) {
            next += 1
        }
        currentStepIndex = next
    }

    private func retreatStep() {
        var previous = currentStepIndex - 1
        while previous > 0, !isStepVisible(OnboardingStep.allCases[previous]) {
            previous -= 1
        }
        currentStepIndex = previous
    }

    private func purchaseSelectedPlan() async -> PurchaseOutcome {
        await appServices.purchaseService.purchase(selectedPricingPlan)
    }

    private func restoreAndCheckSubscribed() async -> Bool {
        await appServices.purchaseService.restorePurchases()
        return appServices.purchaseService.hasEntitlement
    }

    /// Reste sur l'étape, boutons désactivés, tant qu'une fenêtre système
    /// attend encore une réponse — `requestActivation()` ne rend la main qu'une
    /// fois toute la chaîne retombée, plutôt que de courir devant les
    /// dialogues.
    ///
    /// Le résultat décide de la suite. La position refusée est le seul cas qui
    /// retient : sans elle la détection ne peut rien faire, et le dire ici vaut
    /// mieux que de laisser croire que c'est actif. On ne bloque pas pour
    /// autant — « Non, peut-être plus tard » reste juste à côté. Les autres cas
    /// laissent passer : l'abonnement se règle à l'étape suivante, et un
    /// appareil sans capteur de mouvement n'a rien à accorder.
    private func enableAutoDetectionAndContinue() {
        isRequestingAutoDetectionPermissions = true
        Task {
            let status = await appServices.drivingDetector.requestActivation()
            isRequestingAutoDetectionPermissions = false

            if status == .needsAlwaysLocation {
                isPermissionDeniedAlertPresented = true
            } else {
                advanceStep()
            }
        }
    }

    /// Idempotent: a successful purchase both returns `.success` and flips
    /// `hasEntitlement`, so two callers can reach this in the same run loop —
    /// without the guard that would insert the vehicle twice.
    private func finish() {
        guard !appServices.onboardingService.hasCompletedOnboarding else { return }

        let profile = appServices.userProfileService.currentProfile(in: modelContext)
        profile.firstName = firstName.trimmingCharacters(in: .whitespaces)
        profile.lastName = lastName.trimmingCharacters(in: .whitespaces)

        let trimmedPlate = licensePlate.trimmingCharacters(in: .whitespaces)
        let vehicle = Vehicle(
            name: vehicleName.trimmingCharacters(in: .whitespaces),
            licensePlate: trimmedPlate.isEmpty ? nil : trimmedPlate,
            isSelected: true
        )
        modelContext.insert(vehicle)

        modelContext.saveOrLog()

        // Requested here — once, at the true end of onboarding — rather than
        // tied to the auto-detection step, since more steps may still follow
        // it and notifications are also used for report-ready alerts.
        //
        // Détaché : la réponse n'a rien à décider ici, l'onboarding se termine
        // qu'elle soit oui ou non. Les réglages portent la ligne qui permettra
        // de revenir dessus.
        Task { await appServices.notificationService.requestAuthorization() }

        appServices.onboardingService.hasCompletedOnboarding = true
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return OnboardingView()
        .environment(AppServices(modelContext: container.mainContext))
}
