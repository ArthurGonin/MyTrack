//
//  SettingsRowLabel.swift
//  MyTrack
//
//  Le libellé d'une ligne de réglages : une icône teintée, puis le texte.
//
//  `Label(_:systemImage:)` teindrait les deux d'un coup — l'icône *et* le
//  texte prennent la couleur posée sur la ligne. Or c'est justement l'inverse
//  qu'on veut ici, comme dans les Réglages d'iOS : l'icône porte la couleur,
//  le texte reste celui du système (noir, ou rouge quand le bouton est
//  destructeur). D'où la forme à deux blocs.
//

import SwiftUI

struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    init(_ title: LocalizedStringKey, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}
