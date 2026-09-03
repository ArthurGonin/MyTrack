//
//  LegalDocumentSheet.swift
//  MyTrack
//
//  Ce qui présente l'un des deux textes légaux, depuis n'importe où.
//
//  Une feuille du système et non une page web : le texte est dans l'app, il se
//  lit sans réseau, et la feuille pleine hauteur avec sa poignée est la forme
//  qu'iOS donne à un document qu'on ouvre, qu'on parcourt et qu'on referme.
//
//  Un modificateur plutôt qu'un bouton tout fait : les trois endroits qui
//  ouvrent ces documents ne se ressemblent pas — deux liens minuscules sous la
//  paywall, deux lignes de réglages avec leur icône, et la vitrine native de
//  StoreKit qui pose les siens. Chacun garde son bouton ; seule la feuille est
//  commune.
//

import SwiftUI

extension View {
    /// Présente le document désigné par la liaison, et rien tant qu'elle vaut
    /// nil.
    func legalDocumentSheet(_ kind: Binding<LegalDocument.Kind?>) -> some View {
        sheet(item: kind) { kind in
            NavigationStack {
                LegalDocumentView(kind: kind)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            // « Fermer », comme les réglages et la vitrine
                            // d'abonnement : c'est le même geste sur les trois
                            // feuilles de l'app.
                            LegalDocumentSheetCloseButton()
                        }
                    }
            }
        }
    }
}

/// Le bouton de fermeture, sorti de la feuille pour tenir son propre
/// `dismiss` : celui de la vue qui *présente* la feuille refermerait cette
/// vue-là, et non la feuille.
private struct LegalDocumentSheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Fermer") { dismiss() }
    }
}
