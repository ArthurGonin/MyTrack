//
//  OnboardingProgressBar.swift
//  MyTrack
//
//  One capsule per onboarding step, filled up to and including the current
//  one, in the "Stories" progress pattern. Both colours are adaptive rather
//  than literal black or white: the accent for the steps already done, and
//  a faint `primary` for the ones left. Whichever theme is on, the two stay
//  on opposite sides of the background.
//

import SwiftUI

struct OnboardingProgressBar: View {
    let stepCount: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= currentIndex ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentIndex)
    }
}

#Preview {
    OnboardingProgressBar(stepCount: 6, currentIndex: 2)
        .padding()
        .appBackground()
}
