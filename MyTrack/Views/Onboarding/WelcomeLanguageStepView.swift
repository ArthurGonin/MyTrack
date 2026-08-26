//
//  WelcomeLanguageStepView.swift
//  MyTrack
//

import SwiftUI

struct WelcomeLanguageStepView: View {
    let selectedLanguage: String

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
                HStack {
                    Text("Français")
                    Spacer()
                    if selectedLanguage == "fr" {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .padding()
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding()
    }
}

#Preview {
    WelcomeLanguageStepView(selectedLanguage: "fr")
        .appBackground()
}
