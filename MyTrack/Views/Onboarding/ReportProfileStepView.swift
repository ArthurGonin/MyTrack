//
//  ReportProfileStepView.swift
//  MyTrack
//
//  Configure le premier rapport périodique. Mêmes champs que les réglages
//  (`ReportProfileEditView`) moins la sélection de véhicules : à cette étape il
//  n'y en a qu'un, celui de l'étape précédente, et un profil sans filtre les
//  couvre déjà tous.
//
//  Aucune fréquence n'est cochée au départ — d'où la sélection optionnelle du
//  `Picker`. `OnboardingChoiceList` n'était pas réutilisable telle quelle pour
//  ça : elle exige une sélection non optionnelle, et ne sait pas héberger les
//  lignes qui n'apparaissent que pour « Personnalisé ».
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
                    Picker("Fréquence", selection: $draft.periodicity) {
                        ForEach(ReportProfileDraft.selectablePeriodicities, id: \.self) { periodicity in
                            Text(periodicity.label).tag(Optional(periodicity))
                        }
                    }
                    .pickerStyle(.inline)

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
