//
//  OnboardingView.swift
//  MyTrack
//
//  First-launch onboarding. Steps are driven by OnboardingStep so future
//  pages can be added by extending the enum and its switch below, without
//  touching the navigation/button logic.
//

import SwiftData
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case name
    case vehicle
}

struct OnboardingView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @State private var currentStepIndex = 0
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var vehicleName = ""
    @State private var licensePlate = ""

    private var currentStep: OnboardingStep {
        OnboardingStep.allCases[currentStepIndex]
    }

    private var isLastStep: Bool {
        currentStepIndex == OnboardingStep.allCases.count - 1
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
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            stepContent(for: currentStep)

            Button(isLastStep ? "Commencer" : "Continuer") {
                if isLastStep {
                    finish()
                } else {
                    currentStepIndex += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canContinue)
        }
        .padding()
        .appBackground()
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
