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
//  La ligne elle-même vit dans `OnboardingChoiceRow`, parce que l'étape des
//  rapports en a besoin sans pouvoir prendre cette liste-ci.
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
                    OnboardingChoiceRow(label: label(option), isSelected: option == selection) {
                        selection = option
                    }
                }
            }
        }
        // Un `Form` réserve une marge en haut pour se détacher d'une barre de
        // navigation, qu'il n'y a pas ici : sans ça, le titre de l'étape et la
        // première ligne se retrouvent trop loin l'un de l'autre.
        .contentMargins(.top, 8, for: .scrollContent)
    }
}

#Preview {
    @Previewable @State var unit: DistanceUnit = .kilometers

    OnboardingChoiceList(options: DistanceUnit.allCases, selection: $unit) { Text($0.label) }
        .appBackground()
}
