//
//  StatView.swift
//  MyTrack
//
//  Une valeur chiffrée en gros, son intitulé en petit et en gris dessous.
//

import SwiftUI

struct StatView<Value: View>: View {
    private let label: LocalizedStringKey
    private let value: Value

    /// La valeur est une vue et non une chaîne : un chronomètre en marche
    /// s'écrit `Text(date, style: .timer)`, que SwiftUI met à jour lui-même et
    /// qui ne peut donc pas se réduire à un `String`.
    init(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            value
                .font(.title2.weight(.semibold))
                // Sans cela, la largeur des chiffres change d'une seconde à
                // l'autre et le chronomètre tremble.
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Le rapetissement ne répond qu'à la largeur. `minimumScaleFactor`
                // obéit aussi à la hauteur qu'on propose au texte, et une pile un
                // peu serrée suffit alors à faire maigrir le nombre : le même
                // chiffre se lirait plus petit ici que là selon ce qui l'entoure,
                // alors que c'est lui qu'on vient lire. Sa hauteur est donc celle
                // de sa police, quoi qu'on lui propose ; il ne reste flexible que
                // dans le sens où une valeur peut vraiment être trop longue.
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HStack(spacing: 16) {
        StatView("Distance") { Text("12,4 km") }
        Divider().frame(height: 34)
        StatView("Durée") { Text(Date.now, style: .timer) }
    }
    .appCard()
    .padding()
    .appBackground()
}
