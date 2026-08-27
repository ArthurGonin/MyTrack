//
//  WelcomeLanguageStepView.swift
//  MyTrack
//

import SwiftUI

struct WelcomeLanguageStepView: View {
    @Binding var selectedLanguage: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bienvenue")
                    .font(.largeTitle.bold())
                Text("Choisissez la langue")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // La liste occupe la place restante — le `Spacer` qui poussait le
            // contenu vers le haut n'a plus lieu d'être.
            OnboardingChoiceList(options: AppLanguage.allCases, selection: $selectedLanguage) {
                // Chaque langue s'annonce dans sa propre langue : ce libellé ne
                // passe donc pas par le catalogue de traductions.
                Text($0.nativeName)
            }
        }
    }
}

#Preview {
    @Previewable @State var language: AppLanguage = .systemDefault

    WelcomeLanguageStepView(selectedLanguage: $language)
        .appBackground()
}
