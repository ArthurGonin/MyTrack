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
    let isRequestingPermissions: Bool
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

            if isRequestingPermissions {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            VStack(spacing: 12) {
                // maxWidth goes on the label, not the button: applied to the
                // button it only widens the frame around it, leaving the
                // control itself hugging its title — which is why the two
                // buttons used to render at two different widths.
                Button { onEnable() } label: {
                    Text("Oui, activer").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button { onSkip() } label: {
                    Text("Non, peut-être plus tard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .disabled(isRequestingPermissions)
        }
        .padding()
    }
}

#Preview {
    AutoDetectionStepView(isRequestingPermissions: false, onEnable: {}, onSkip: {})
        .appBackground()
}
