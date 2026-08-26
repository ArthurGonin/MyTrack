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
        case .autoDetection:
            return true
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            stepContent(for: currentStep)

            if currentStep != .autoDetection {
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
                onEnable: enableAutoDetectionAndFinish,
                onSkip: finish
            )
        }
    }

    /// Requests Motion first, then location (When In Use, then the Always
    /// upgrade) — staying on this step, with both buttons disabled, for as
    /// long as any of those prompts is still awaiting an answer. Moves on
    /// only once the whole chain has settled, whatever the outcome, rather
    /// than racing ahead of the system dialogs.
    private func enableAutoDetectionAndFinish() {
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
                finish()
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
