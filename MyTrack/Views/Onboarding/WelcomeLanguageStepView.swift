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

            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { language in
                    languageRow(language)

                    if language != AppLanguage.allCases.last {
                        Divider()
                            .padding(.leading)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding()
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        Button {
            selectedLanguage = language
        } label: {
            HStack {
                Text(language.nativeName)
                    .foregroundStyle(.primary)
                Spacer()
                if language == selectedLanguage {
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
        .accessibilityAddTraits(language == selectedLanguage ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var language: AppLanguage = .systemDefault

    WelcomeLanguageStepView(selectedLanguage: $language)
        .appBackground()
}
