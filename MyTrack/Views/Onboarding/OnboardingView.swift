//
//  OnboardingView.swift
//  MyTrack
//
//  First-launch onboarding. Steps are driven by OnboardingStep so future
//  pages can be added by extending the enum and its switch below, without
//  touching the navigation/button logic.
//

import CoreLocation
import SwiftData
import SwiftUI
import UIKit

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case name
    case vehicle
    case autoDetection
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
    @State private var selectedPricingPlan: PricingPlan = .annual

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
        case .vehicle:
            return !vehicleName.trimmingCharacters(in: .whitespaces).isEmpty
        case .autoDetection, .paywall:
            return true
        }
    }

    /// Steps with their own action button (auto-detection's yes/no,
    /// the paywall's "J'y vais") hide the shared bottom button instead of
    /// using it, since a single "Continuer" wouldn't fit what they need.
    private var showsGenericContinueButton: Bool {
        switch currentStep {
        case .welcome, .name, .vehicle:
            return true
        case .autoDetection, .paywall:
            return false
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            OnboardingProgressBar(
                stepCount: OnboardingStep.allCases.count,
                currentIndex: currentStepIndex
            )

            stepContent(for: currentStep)

            if showsGenericContinueButton {
                Button("Continuer") {
                    currentStepIndex += 1
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

    @ViewBuilder
    private func stepContent(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            WelcomeLanguageStepView(selectedLanguage: appServices.onboardingService.selectedLanguage)
        case .name:
            NameStepView(firstName: $firstName, lastName: $lastName)
        case .vehicle:
            VehicleStepView(vehicleName: $vehicleName, licensePlate: $licensePlate)
        case .autoDetection:
            AutoDetectionStepView(
                isRequestingPermissions: isRequestingAutoDetectionPermissions,
                onEnable: enableAutoDetectionAndContinue,
                onSkip: { currentStepIndex += 1 }
            )
        case .paywall:
            PaywallStepView(selectedPlan: $selectedPricingPlan, onContinue: finish)
        }
    }

    /// Requests Motion first, then location (When In Use, then the Always
    /// upgrade) — staying on this step, with both buttons disabled, for as
    /// long as any of those prompts is still awaiting an answer. Moves on
    /// only once the whole chain has settled, whatever the outcome, rather
    /// than racing ahead of the system dialogs.
    private func enableAutoDetectionAndContinue() {
        switch appServices.locationService.authorizationStatus {
        case .denied, .restricted:
            isPermissionDeniedAlertPresented = true
        default:
            isRequestingAutoDetectionPermissions = true
            Task {
                await appServices.motionActivityService.requestAuthorization()
                appServices.drivingDetector.enable()
                await appServices.drivingDetector.waitForAuthorizationSettled()
                isRequestingAutoDetectionPermissions = false
                currentStepIndex += 1
            }
        }
    }

    private func finish() {
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
        appServices.notificationService.requestAuthorization()

        // TODO: hand off to the real purchase flow for selectedPricingPlan
        // once it exists; for now "J'y vais" just completes onboarding.
        appServices.onboardingService.hasCompletedOnboarding = true
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, AppNotification.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return OnboardingView()
        .environment(AppServices(modelContext: container.mainContext))
}
