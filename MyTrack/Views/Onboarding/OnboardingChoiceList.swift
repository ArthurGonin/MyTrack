//
//  OnboardingChoiceList.swift
//  MyTrack
//
//  La carte de choix des étapes d'onboarding : une ligne par option, cochée
//  quand elle est retenue. Partagée par l'étape de langue et celle des unités
//  pour que les deux ne divergent pas à la première retouche.
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
        VStack(spacing: 0) {
            ForEach(options) { option in
                row(option)

                if option != options.last {
                    Divider()
                        .padding(.leading)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
            .padding()
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
        .padding()
        .appBackground()
}
