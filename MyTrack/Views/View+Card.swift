//
//  View+Card.swift
//  MyTrack
//
//  La surface de contenu de l'app : un rectangle opaque à grands coins
//  arrondis, posé sur le gris de `appBackground()`.
//
//  Opaque, et non en Liquid Glass, volontairement : Apple réserve le verre à
//  la couche qui flotte *au-dessus* du contenu — boutons, barre d'onglets,
//  bouton de compte — et déconseille de l'employer pour le contenu lui-même.
//  Une liste entière de cartes en verre se brouille au défilement, chacune
//  reprenant ce qui passe dessous. Le verre reste donc sur les contrôles
//  (`AccountButton`, `PricingOptionCard`, la barre d'onglets native), et les
//  cartes portent le contenu.
//

import SwiftUI

extension View {
    /// - Parameters:
    ///   - cornerRadius: rayon des coins.
    ///   - padding: marge intérieure. Passer 0 pour un contenu qui gère déjà
    ///     la sienne — une carte remplie bord à bord par une carte, par exemple.
    func appCard(cornerRadius: CGFloat = 22, padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
    }

    /// La même carte, mais pour une ligne de `List`.
    ///
    /// Passer par `listRowBackground` plutôt que refaire la liste à la main
    /// dans un `ScrollView` : les actions de balayage (`onDelete`,
    /// `swipeActions`) n'existent que dans une `List`, et les perdre pour
    /// gagner des coins arrondis serait un mauvais échange.
    ///
    /// Les marges se répartissent entre les deux : `listRowInsets` écarte le
    /// contenu du bord de la ligne, le fond se rétracte de 16 pt en largeur et
    /// de 6 pt en hauteur. Ce qui reste entre les deux — 16 pt de chaque côté,
    /// 12 pt en haut et en bas — est la marge intérieure de la carte, et les
    /// 12 pt de fond retirés forment l'écart entre deux cartes.
    func appCardRow(cornerRadius: CGFloat = 20) -> some View {
        listRowInsets(EdgeInsets(top: 18, leading: 32, bottom: 18, trailing: 32))
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            )
    }
}
