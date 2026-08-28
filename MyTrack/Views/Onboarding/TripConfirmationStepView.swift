//
//  TripConfirmationStepView.swift
//  MyTrack
//
//  Shown only when the previous step just enabled auto-detection — asks
//  whether each detected trip should wait for a yes/no answer or be saved
//  right away. Same two-button layout as AutoDetectionStepView, no shared
//  bottom "Continuer": picking either answer both records it and advances.
//

import SwiftUI

struct TripConfirmationStepView: View {
    let onChooseConfirmation: () -> Void
    let onChooseAutomatic: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirmation des trajets")
                    .font(.largeTitle.bold())
                Text("Quand MyTrack détecte un trajet, veux-tu le confirmer avant qu'il soit enregistré, ou préfères-tu qu'il soit accepté automatiquement ?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button { onChooseConfirmation() } label: {
                    Text("Me demander à chaque fois").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.onAccent)
                .controlSize(.large)

                Button { onChooseAutomatic() } label: {
                    Text("Accepter automatiquement").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding()
    }
}

#Preview {
    TripConfirmationStepView(onChooseConfirmation: {}, onChooseAutomatic: {})
        .appBackground()
}
