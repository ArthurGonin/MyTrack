//
//  LegalDocumentView.swift
//  MyTrack
//
//  L'un des deux textes légaux, rendu à lire.
//
//  Pas de `NavigationStack` ici, et c'est délibéré : cette vue est servie de
//  deux façons. En feuille, `legalDocumentSheet` lui pose une pile et son bouton
//  de fermeture ; poussée depuis la vitrine native de StoreKit
//  (`subscriptionStorePolicyDestination`), elle arrive dans la pile de la
//  vitrine, où une seconde pile ferait une seconde barre de navigation et un
//  bouton « Fermer » qui refermerait l'achat en cours.
//

import SwiftUI

struct LegalDocumentView: View {
    let kind: LegalDocument.Kind

    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    private var document: LegalDocument { kind.document }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                updatedLine
                // Une carte par section : c'est la surface de contenu de l'app
                // (`appCard`), et elle donne au texte ce dont une page de
                // conditions a le plus besoin — de quoi s'y repérer d'un coup
                // d'œil, sans lire.
                ForEach(document.sections.indices, id: \.self) { index in
                    card(document.sections[index])
                }
                contactCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .appBackground()
        .localizedNavigationTitle(document.title)
    }

    /// La date de la version en vigueur, avant tout le reste : c'est ce qu'on
    /// vient vérifier en rouvrant un tel document.
    private var updatedLine: some View {
        Text(
            String(
                localized: "Dernière mise à jour : \(formattedUpdate)",
                bundle: localizationBundle,
                locale: locale
            )
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    /// Rendue par le formateur plutôt qu'écrite à la main : l'ordre du jour et
    /// du mois n'est pas le même d'une langue à l'autre.
    private var formattedUpdate: String {
        LegalDocument.lastUpdated.formatted(
            .dateTime.day().month(.wide).year().locale(locale)
        )
    }

    private func card(_ section: LegalDocument.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.heading)
                .font(.headline)
            ForEach(section.paragraphs.indices, id: \.self) { index in
                Text(section.paragraphs[index])
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    /// La dernière carte, et seulement s'il y a vraiment une boîte aux lettres
    /// derrière — voir `LegalContact`.
    @ViewBuilder
    private var contactCard: some View {
        if let email = LegalContact.email {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nous écrire")
                    .font(.headline)
                Text(document.contactParagraph)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                // L'adresse ne passe pas par le catalogue : elle s'écrit
                // pareil dans les six langues. Un lien plutôt qu'un texte,
                // pour que le courrier parte d'un appui.
                if let mailto = URL(string: "mailto:\(email)") {
                    Link(destination: mailto) {
                        Text(verbatim: email)
                            .font(.callout.weight(.medium))
                    }
                } else {
                    Text(verbatim: email)
                        .font(.callout.weight(.medium))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard()
        }
    }
}

#Preview("Confidentialité") {
    NavigationStack {
        LegalDocumentView(kind: .privacyPolicy)
    }
}

#Preview("Conditions") {
    NavigationStack {
        LegalDocumentView(kind: .termsOfUse)
    }
}
