//
//  AccountButton.swift
//  MyTrack
//
//  Liquid Glass avatar button: a glass circle wrapping a smaller tinted
//  circle showing the user's initial.
//

import SwiftUI

struct AccountButton: View {
    let initial: String
    /// Pastille rouge : rappel permanent, visible depuis tous les onglets, que
    /// quelque chose ne tourne plus — aujourd'hui, l'abonnement.
    var hasWarning: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.accentColor.gradient)
                .overlay {
                    Text(initial)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                .padding(6)
                .overlay(alignment: .topTrailing) {
                    if hasWarning {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                    }
                }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        // Without this VoiceOver just reads the initial letter.
        .accessibilityLabel(
            hasWarning
                ? Text("Compte et réglages, abonnement inactif")
                : Text("Compte et réglages")
        )
    }
}

#Preview {
    VStack {
        AccountButton(initial: "A", action: {})
        AccountButton(initial: "A", hasWarning: true, action: {})
    }
    .padding()
}
