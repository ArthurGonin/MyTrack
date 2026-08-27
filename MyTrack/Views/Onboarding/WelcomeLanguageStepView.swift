//
//  WelcomeLanguageStepView.swift
//  MyTrack
//

import SwiftUI

struct WelcomeLanguageStepView: View {
    @Binding var selectedLanguage: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bienvenue")
                    .font(.largeTitle.bold())
                Text("Choisissez la langue")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            OnboardingChoiceList(options: AppLanguage.allCases, selection: $selectedLanguage) {
                // Chaque langue s'annonce dans sa propre langue : ce libellé ne
                // passe donc pas par le catalogue de traductions.
                Text($0.nativeName)
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    @Previewable @State var language: AppLanguage = .systemDefault

    WelcomeLanguageStepView(selectedLanguage: $language)
        .appBackground()
}
