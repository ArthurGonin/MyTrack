//
//  OnboardingChoiceList.swift
//  MyTrack
//
//  La liste de choix des étapes d'onboarding : une ligne par option, cochée
//  quand elle est retenue. Partagée par l'étape de langue et celle des unités
//  pour que les deux ne divergent pas à la première retouche.
//
//  C'est un `Form`, comme l'écran des Réglages, et non une pile de lignes
//  dessinée à la main : les séparateurs, leur retrait, la hauteur des lignes et
//  le fond des cellules viennent alors du système et suivront ses évolutions,
//  au lieu d'être des valeurs recopiées ici qui s'en écarteront.
//
//  Le libellé arrive en `Text` plutôt qu'en chaîne : un nom de langue s'écrit
//  toujours dans sa propre langue et se rend tel quel, alors qu'une unité est
//  du texte d'interface, qui se traduit.
//

import SwiftUI

struct OnboardingChoiceList<Option: Identifiable & Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> Text

    var body: some View {
        Form {
            Section {
                ForEach(options) { option in
                    row(option)
                }
            }
        }
        // Un `Form` réserve une marge en haut pour se détacher d'une barre de
        // navigation, qu'il n'y a pas ici : sans ça, le titre de l'étape et la
        // première ligne se retrouvent trop loin l'un de l'autre.
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private func row(_ option: Option) -> some View {
        Button {
            selection = option
        } label: {
            HStack {
                label(option)
                    .foregroundStyle(.primary)
                Spacer()
                if option == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            // Sans ça, seul le texte est tapable : la ligne entière doit
            // répondre, y compris l'espace vide à droite.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option == selection ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var unit: DistanceUnit = .kilometers

    OnboardingChoiceList(options: DistanceUnit.allCases, selection: $unit) { Text($0.label) }
        .appBackground()
}
