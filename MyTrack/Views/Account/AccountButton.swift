//
//  AccountButton.swift
//  MyTrack
//
//  Liquid Glass avatar button: a glass circle wrapping a smaller tinted
//  circle showing the user's initial.
//

import SwiftUI

struct AccountButton: View {
    let initial: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.accentColor.gradient)
                .overlay {
                    Text(initial)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 28, height: 28)
                .padding(6)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

#Preview {
    AccountButton(initial: "A", action: {})
        .padding()
}
