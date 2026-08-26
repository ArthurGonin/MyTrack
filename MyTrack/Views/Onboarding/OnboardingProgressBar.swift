//
//  OnboardingProgressBar.swift
//  MyTrack
//
//  One capsule per onboarding step, filled up to and including the current
//  one. Uses a tinted fill rather than literal white — the onboarding
//  background is a light gradient, so white-on-white wouldn't read — with
//  the same "Stories"-style progress pattern.
//

import SwiftUI

struct OnboardingProgressBar: View {
    let stepCount: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: proxy.size.width * fillFraction(for: index))
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentIndex)
    }

    /// Vraiment le motif « Stories » : les étapes déjà franchies sont pleines,
    /// celle en cours est à moitié remplie, les suivantes sont vides. Compter
    /// l'étape courante comme franchie affichait une barre pleine à 100 % sur
    /// la paywall — qui se lit « c'est terminé » alors qu'il reste à répondre.
    private func fillFraction(for index: Int) -> CGFloat {
        if index < currentIndex { return 1 }
        if index == currentIndex { return 0.5 }
        return 0
    }
}

#Preview {
    OnboardingProgressBar(stepCount: 5, currentIndex: 2)
        .padding()
        .appBackground()
}
