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
