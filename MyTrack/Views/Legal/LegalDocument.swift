//
//  LegalDocument.swift
//  MyTrack
//
//  Les deux textes légaux de l'app — conditions d'utilisation et politique de
//  confidentialité — décrits comme des données plutôt qu'écrits dans une vue.
//
//  Des données, parce que les deux se rendent avec le même écran, se traduisent
//  par le même catalogue, et sont réclamés depuis trois endroits : la paywall
//  d'onboarding, les réglages, et la vitrine native de StoreKit. Écrits en dur
//  dans une vue, ils auraient été à recopier trois fois.
//
//  Dans l'app plutôt que derrière une adresse web, et c'est un choix : ce que
//  l'app fait de vos données se lit là où elle est installée, sans réseau, et
//  ne peut pas changer sous vos pieds entre deux versions. Une page distante,
//  elle, peut être réécrite le lendemain de l'installation.
//
//  Attention toutefois : App Store Connect réclame *en plus* une URL de
//  politique de confidentialité dans la fiche de l'app. Cette exigence-là est
//  côté métadonnées et aucun écran embarqué ne la remplace — il faudra publier
//  ce même texte quelque part avant de soumettre.
//

import SwiftUI

struct LegalDocument {
    /// Lequel des deux. C'est lui qu'on passe d'écran en écran, et lui qui
    /// pilote la feuille : `.sheet(item:)` réclame une identité, que le
    /// document entier n'a pas de raison de porter.
    enum Kind: String, Identifiable, CaseIterable {
        case termsOfUse
        case privacyPolicy

        var id: String { rawValue }

        var document: LegalDocument {
            switch self {
            case .termsOfUse: .termsOfUse
            case .privacyPolicy: .privacyPolicy
            }
        }
    }

    /// Un titre et ce qu'il annonce. Les paragraphes sont séparés plutôt que
    /// réunis en une chaîne à retours à la ligne : c'est la mise en page qui
    /// doit décider de l'écart entre deux paragraphes, pas le texte, et une
    /// phrase courte se traduit mieux qu'une page entière.
    struct Section {
        let heading: LocalizedStringKey
        let paragraphs: [LocalizedStringKey]
    }

    /// Le titre de la barre de navigation. Une `LocalizationValue` et non une
    /// `LocalizedStringKey` : il passe par `localizedNavigationTitle`, qui le
    /// résout lui-même pour suivre la langue choisie dans l'app.
    let title: String.LocalizationValue
    let sections: [Section]
    /// Ce que dit la section de contact, quand il y a une adresse où écrire.
    /// Portée par le document et non par la vue : c'est la seule phrase qui
    /// change d'un texte à l'autre — « sur ce texte » ici, « sur ces
    /// conditions » là.
    let contactParagraph: LocalizedStringKey

    /// La date de la version en vigueur, commune aux deux documents : ils ont
    /// été écrits ensemble et ils évolueront ensemble.
    ///
    /// Une `Date` et non une chaîne : elle se rend dans la langue de l'app,
    /// avec l'ordre des jours et des mois du pays qui lit.
    static let lastUpdated: Date = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026, month: 9, day: 3
    ).date ?? .distantPast
}
