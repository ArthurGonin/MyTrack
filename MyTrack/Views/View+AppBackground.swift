//
//  View+AppBackground.swift
//  MyTrack
//

import SwiftUI

extension View {
    /// Le fond de l'app : le gris `systemGroupedBackground`, assombri vers le
    /// bas. Les cartes (`appCard()`) s'y posent en clair par-dessus — c'est le
    /// couple `systemGroupedBackground` / `secondarySystemGroupedBackground`
    /// d'iOS, qui garde le bon contraste dans les deux thèmes : gris clair +
    /// cartes blanches en clair, noir + cartes gris foncé en sombre.
    ///
    /// Le dégradé se fait en superposant du `primary` translucide plutôt qu'en
    /// visant une seconde couleur fixe : `primary` est noir en thème clair et
    /// blanc en thème sombre, donc le bas s'assombrit d'un côté et s'éclaircit
    /// de l'autre — dans les deux cas il s'écarte du fond, et dans les deux cas
    /// il reste en deçà des cartes, qui doivent rester la surface la plus
    /// détachée. Une couleur fixe comme `systemGray4` ne peut pas tenir les
    /// deux : assez grise en clair, elle passe en sombre au-dessus des cartes.
    ///
    /// S'étend à tout l'écran même si le contenu (ex. un VStack sans Spacer)
    /// est plus petit, et masque le fond opaque propre à List/Form pour laisser
    /// voir le gris.
    func appBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .background(
                Color(uiColor: .systemGroupedBackground)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Color.primary.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
    }
}
