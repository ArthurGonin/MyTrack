//
//  ReportProfileStepView.swift
//  MyTrack
//
//  Configure le premier rapport périodique. Mêmes champs que les réglages
//  (`ReportProfileEditView`) moins la sélection de véhicules : à cette étape il
//  n'y en a qu'un, celui de l'étape précédente, et un profil sans filtre les
//  couvre déjà tous.
//
//  Les fréquences sont des lignes à cocher — les mêmes qu'aux étapes de langue
//  et d'unités, via `OnboardingChoiceRow` — et non un `Picker`. Un picker en
//  style `.inline` posait son propre libellé « Fréquence » comme une ligne de
//  plus dans le tableau, à côté de « Mensuel » et « Annuel », donc comme un
//  choix possible. C'est un titre : il est passé en en-tête de section, où le
//  système le rend comme partout ailleurs dans iOS.
//
//  Aucune fréquence n'est cochée au départ, d'où la sélection optionnelle du
//  brouillon. `OnboardingChoiceList` ne pouvait pas servir telle quelle : elle
//  exige une sélection non optionnelle, n'a pas d'en-tête, et ne sait pas
//  héberger les lignes qui n'apparaissent que pour « Personnalisé ».
//

import SwiftUI

struct ReportProfileStepView: View {
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    @Binding var draft: ReportProfileDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Vos rapports")
                    .font(.largeTitle.bold())
                Text("Recevez automatiquement un PDF de vos trajets")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Form {
                Section {
                    TextField("Nom du profil", text: $draft.name)
                }
                Section {
                    ForEach(ReportProfileDraft.selectablePeriodicities, id: \.self) { periodicity in
                        OnboardingChoiceRow(
                            label: Text(periodicity.label),
                            isSelected: draft.periodicity == periodicity
                        ) {
                            draft.periodicity = periodicity
                        }
                    }

                    if draft.periodicity == .custom {
                        Stepper(
                            "Tous les \(draft.customIntervalDays) jours",
                            value: $draft.customIntervalDays,
                            in: 1...365
                        )
                        DatePicker(
                            "Premier rapport",
                            selection: $draft.customFirstDueDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    } else if let nextDueDate = draft.nextDueDate {
                        Text("Le prochain rapport sera envoyé le \(TripFormatting.longDate(nextDueDate, locale: locale))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Fréquence")
                } footer: {
                    Text("Ce rapport couvre tous vos véhicules. Vous pourrez le modifier dans les réglages.")
                }
            }
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
        }
        // Le nom est une donnée, pas du texte d'interface : il est résolu une
        // fois ici — comme le fait `ReportSettingsView.addProfile()` — et ne
        // suivra donc pas un changement de langue ultérieur.
        .task {
            guard draft.name.isEmpty else { return }
            draft.name = String(
                localized: "Nouveau rapport périodique",
                bundle: localizationBundle,
                locale: locale
            )
        }
    }
}

#Preview {
    @Previewable @State var draft = ReportProfileDraft()

    ReportProfileStepView(draft: $draft)
        .appBackground()
}
