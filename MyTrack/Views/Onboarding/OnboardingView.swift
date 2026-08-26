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
}

struct OnboardingView: View {
    @Environment(AppServices.self) private var appServices
    @State private var currentStepIndex = 0

    private var currentStep: OnboardingStep {
        OnboardingStep.allCases[currentStepIndex]
    }

    private var isLastStep: Bool {
        currentStepIndex == OnboardingStep.allCases.count - 1
    }

    var body: some View {
        VStack(spacing: 24) {
            stepContent(for: currentStep)

            Button(isLastStep ? "Commencer" : "Continuer") {
                if isLastStep {
                    appServices.onboardingService.hasCompletedOnboarding = true
                } else {
                    currentStepIndex += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .appBackground()
    }

    @ViewBuilder
    private func stepContent(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            WelcomeLanguageStepView(selectedLanguage: appServices.onboardingService.selectedLanguage)
        }
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
