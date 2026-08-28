//
//  Color+OnAccent.swift
//  MyTrack
//

import SwiftUI

extension Color {
    /// La couleur d'un contenu posé sur une surface teintée à l'accent.
    ///
    /// Pas `.white` : l'accent de l'app n'est pas une teinte, c'est un noir pur
    /// qui devient blanc pur en thème sombre. Du blanc posé dessus disparaît
    /// donc complètement une fois le thème inversé. `systemBackground` est
    /// exactement l'inverse de l'accent — blanc en clair, noir en sombre — donc
    /// le contraste tient des deux côtés sans qu'on ait à connaître le thème
    /// courant.
    ///
    /// À poser explicitement sur les boutons `.borderedProminent` : contrairement
    /// à ce qu'on pourrait attendre, SwiftUI ne recalcule pas la couleur du
    /// libellé en fonction de la luminance de la teinte. Il le laisse blanc, et
    /// un bouton proéminent en thème sombre est alors une pastille blanche vide.
    static var onAccent: Color { Color(uiColor: .systemBackground) }
}
