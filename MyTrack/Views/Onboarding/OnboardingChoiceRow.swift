//
//  OnboardingChoiceRow.swift
//  MyTrack
//
//  Une ligne de choix d'onboarding : le libellé, et une coche quand l'option
//  est retenue.
//
//  Extraite d'`OnboardingChoiceList` le jour où l'étape des rapports a eu
//  besoin de la ligne sans pouvoir prendre la liste entière — sa section a un
//  titre, des lignes qui n'apparaissent que pour « Personnalisé », et une
//  sélection encore vide au départ. Les deux écrans partagent donc la ligne, et
//  chacun garde son formulaire.
//
//  Le libellé arrive en `Text` plutôt qu'en chaîne : un nom de langue s'écrit
//  toujours dans sa propre langue et se rend tel quel, alors qu'une unité ou une
//  fréquence est du texte d'interface, qui se traduit.
//

import SwiftUI

struct OnboardingChoiceRow: View {
    let label: Text
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                label
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            // Sans ça, seul le texte est tapable : la ligne entière doit
            // répondre, y compris l'espace vide à droite.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    Form {
        Section {
            OnboardingChoiceRow(label: Text("Mensuel"), isSelected: true) {}
            OnboardingChoiceRow(label: Text("Annuel"), isSelected: false) {}
        } header: {
            Text("Fréquence")
        }
    }
}
