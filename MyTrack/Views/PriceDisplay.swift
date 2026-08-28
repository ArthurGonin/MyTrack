//
//  PriceDisplay.swift
//  MyTrack
//

import StoreKit

/// Ce qu'on affiche à la place d'un prix qu'on ne connaît pas encore.
///
/// Un prix ne s'invente pas. `displayPrice` arrive de l'App Store déjà mis en
/// forme dans la devise du client — francs en Suisse, dollars aux États-Unis —
/// donc écrire un montant en dur en attendant, c'était annoncer un prix faux à
/// tous ceux qui ne sont pas dans la zone euro. Et comme le montant était
/// crédible, rien ne signalait que la boutique n'avait rien chargé : une
/// paywall parfaitement inutilisable avait l'air en parfait état.
enum PriceDisplay {
    /// Le gabarit qui tient la place du prix tant qu'il manque.
    ///
    /// Il n'est jamais lu : les vues le passent à
    /// `redacted(reason: .placeholder)`, qui le remplace par la barre grise
    /// standard d'iOS. Il ne sert qu'à donner sa largeur à cette barre, d'où
    /// des chiffres neutres et pas de devise — celle-ci varie d'un pays à
    /// l'autre, et la deviner serait retomber dans le travers qu'on corrige.
    static let placeholder = "00,00"

    /// Le prix du produit, ou le gabarit quand le produit n'est pas chargé.
    ///
    /// Les appelants regardent `product == nil` de leur côté pour décider s'ils
    /// masquent le résultat : la chaîne seule ne dit pas si c'en est un vrai.
    static func price(of product: Product?) -> String {
        product?.displayPrice ?? placeholder
    }
}
