//
//  TabBarMetrics.swift
//  MyTrack
//
//  La taille de la barre d'onglets, pour les vues qui doivent s'aligner
//  dessus.
//
//  Elle ne se déduit pas. Depuis iOS 26 la barre n'occupe plus le bas de
//  l'écran : c'est une gélule de verre posée au-dessus du contenu, et sa
//  largeur suit celle de ses onglets — donc les libellés, donc la langue et le
//  corps de texte choisis. « Enregistrer / Trajets / Rapports » ne demande pas
//  la même place que « Aufzeichnen / Fahrten / Berichte ». Rien dans SwiftUI ne
//  publie cette taille, et il n'y a aucune règle à recopier : on va donc la
//  lire là où elle existe pour de bon, sur la `UITabBar` que SwiftUI installe
//  dans la fenêtre.
//

import UIKit

enum TabBarMetrics {
    /// La taille de la gélule flottante, ou `nil` si elle est introuvable.
    ///
    /// `nil` n'est pas une erreur : l'écran peut très bien s'afficher hors
    /// d'un `TabView` (une prévisualisation, une feuille présentée par-dessus),
    /// et une version d'iOS peut remanier cette hiérarchie de vues, qui n'est
    /// promise nulle part. C'est à l'appelant de retomber sur sa mise en page
    /// habituelle — jamais sur une taille devinée.
    static var floatingBarSize: CGSize? {
        guard let window = activeWindow, let bar = tabBar(in: window) else { return nil }
        // La gélule est une sous-vue de la barre : celle-ci s'étend sur toute
        // la largeur de l'écran, la gélule n'en occupe que le centre. C'est
        // exactement ce qui les distingue, et c'est plus sûr que de nommer une
        // classe privée qu'Apple peut renommer.
        let platter = bar.subviews
            .filter { !$0.isHidden && $0.alpha > 0 && $0.bounds.width < bar.bounds.width }
            .max { $0.bounds.width < $1.bounds.width }
        guard let size = platter?.bounds.size, size.width > 0, size.height > 0 else { return nil }
        return size
    }

    /// La fenêtre où l'app s'affiche.
    ///
    /// Aucun filtre sur « scène active » : au premier affichage de l'écran,
    /// la scène est encore `foregroundInactive`, et c'est précisément là qu'on
    /// veut mesurer — avant que l'utilisateur voie quoi que ce soit.
    private static var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState != .background && $0.activationState != .unattached }
            .lazy
            .compactMap { $0.keyWindow ?? $0.windows.first }
            .first
    }

    private static func tabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for subview in view.subviews {
            if let bar = tabBar(in: subview) { return bar }
        }
        return nil
    }
}
