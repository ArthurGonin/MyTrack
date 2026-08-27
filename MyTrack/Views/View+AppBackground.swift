//
//  View+AppBackground.swift
//  MyTrack
//

import SwiftUI

extension View {
    /// Fond discret : presque blanc en haut, gris clair en bas. S'étend à
    /// tout l'écran même si le contenu (ex. un VStack sans Spacer) est plus
    /// petit, et masque le fond opaque propre à List/Form pour laisser voir
    /// le dégradé.
    func appBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [Color(uiColor: .systemBackground), Color(uiColor: .systemGray4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}
