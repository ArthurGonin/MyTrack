//
//  AutoDetectionStepView.swift
//  MyTrack
//
//  Last onboarding step. Has its own two buttons instead of the shared
//  bottom "Continuer" — a plain yes/no reads better here than a single
//  advance button — so OnboardingView hides the generic one for this step.
//

import SwiftUI

struct AutoDetectionStepView: View {
    let onEnable: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Suivi automatique")
                    .font(.largeTitle.bold())
                Text("MyTrack peut détecter et enregistrer tes trajets en voiture automatiquement, sans que tu aies à y penser.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Oui, activer") { onEnable() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button("Non, peut-être plus tard") { onSkip() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }
}

#Preview {
    AutoDetectionStepView(onEnable: {}, onSkip: {})
        .appBackground()
}
