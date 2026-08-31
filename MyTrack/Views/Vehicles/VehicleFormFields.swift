//
//  VehicleFormFields.swift
//  MyTrack
//
//  Les champs d'un véhicule, partagés par les trois écrans qui en éditent un :
//  l'étape d'onboarding, l'ajout et la modification. Un seul endroit décrit le
//  formulaire, donc les trois écrans ne peuvent plus proposer des champs
//  différents.
//
//  Ce sont des `Section` et non un `Form` : c'est l'écran qui décide de son
//  formulaire — une feuille avec sa barre de navigation, une étape d'onboarding
//  sans — et lui seul sait quelles marges lui vont.
//
//  Les lignes chiffrées suivent la mise en page des Réglages : le libellé à
//  gauche, la valeur alignée à droite, l'unité derrière en gris. L'unité change
//  avec l'énergie choisie — L/100 km devient kWh/100 km — pour qu'aucun chiffre
//  ne soit saisi dans la mauvaise unité.
//
//  Le clavier décimal n'a pas de touche de retour, et aucun bouton n'est ajouté
//  pour le refermer : il y en avait un, « Terminé », qui faisait doublon avec
//  l'« Enregistrer » de la barre juste au-dessus. Ce sont les trois écrans qui
//  posent `scrollDismissesKeyboard` sur leur formulaire — le geste d'iOS, celui
//  des Réglages : on écarte le clavier en faisant glisser la page.
//

import SwiftUI

struct VehicleFormFields: View {
    @Binding var draft: VehicleDraft

    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    var body: some View {
        Section {
            TextField("Nom du véhicule", text: $draft.name)
                .textInputAutocapitalization(.words)
            TextField("Immatriculation (optionnel)", text: $draft.licensePlate)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }

        Section {
            // Le menu ne porte que les mots : son symbole, SwiftUI le recolle
            // sans espace contre la valeur retenue une fois le menu refermé.
            // Les symboles vivent dans la liste des véhicules, où ils ont la
            // place de se poser.
            Picker(selection: $draft.energyType) {
                ForEach(VehicleEnergyType.allCases) { type in
                    Text(type.label(bundle: localizationBundle, locale: locale))
                        .tag(type)
                }
            } label: {
                Text("Énergie")
            }

            numberRow(
                "Consommation",
                text: $draft.consumption,
                unit: draft.energyType.consumptionUnitSymbol
            )
            numberRow(
                "Prix",
                text: $draft.energyPrice,
                unit: priceUnitSymbol
            )
        } footer: {
            Text("Facultatif. Sert à estimer le coût de tes trajets.")
        }
    }

    private func numberRow(
        _ title: LocalizedStringKey, text: Binding<String>, unit: String
    ) -> some View {
        HStack {
            // Le libellé et l'unité passent avant le champ dans le partage de
            // la largeur : sans ça, « Consommation » se coupe en deux lignes
            // dans le formulaire plus étroit de l'onboarding, pour laisser de
            // la place à un champ qui n'en demandait pas tant.
            Text(title)
                .lineLimit(1)
                .layoutPriority(1)
            TextField(zeroPlaceholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                // Sans ça, VoiceOver annonce le gabarit du champ (« 0 ») au
                // lieu de ce qu'on y attend.
                .accessibilityLabel(Text(title))
            Text(unit)
                .lineLimit(1)
                .layoutPriority(1)
                .foregroundStyle(.secondary)
        }
    }

    /// Le gabarit des champs chiffrés : un zéro, mis en forme dans la langue de
    /// l'app. Neutre exprès — un exemple crédible (« 6,5 ») se lirait comme une
    /// valeur déjà saisie.
    private var zeroPlaceholder: String {
        0.formatted(.number.locale(locale))
    }

    /// « €/L », « CHF/kWh » : la devise vient de la région de l'appareil, pas
    /// de la langue de l'app — un Suisse qui lit l'app en français paie en
    /// francs.
    private var priceUnitSymbol: String {
        let energyUnit = draft.energyType.energyUnitSymbol
        guard let symbol = locale.currencySymbol, !symbol.isEmpty else { return energyUnit }
        return "\(symbol)/\(energyUnit)"
    }
}

#Preview {
    @Previewable @State var draft = VehicleDraft()

    Form {
        VehicleFormFields(draft: $draft)
    }
    .appBackground()
}
