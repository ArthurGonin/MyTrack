//
//  WelcomeLanguageStepView.swift
//  MyTrack
//
//  La toute première page de l'app : le mot d'accueil en grand, tapé au
//  clavier et repris dans les six langues (voir `TypewriterGreeting`), au-dessus
//  d'un menu qui retient celle qu'on veut lire.
//
//  Le cycle commence par la langue de l'iPhone — ou l'anglais si l'app ne parle
//  pas la sienne, voir `AppLanguage.systemDefault` — et c'est elle que le menu
//  affiche d'emblée : le défilé montre ce que l'app sait dire, il ne choisit
//  rien.
//
//  D'où la forme de l'écran. La liste de six langues qui occupait la page
//  posait une question à laquelle l'app avait déjà répondu, et le premier mot
//  de l'app était le nom d'un réglage. C'est désormais un accueil, avec la
//  langue en second plan : un menu discret sous le titre, pour ceux dont
//  l'iPhone n'est pas dans leur langue. En changer relance le défilé sur elle,
//  ce qui confirme le choix sans avoir à l'annoncer.
//

import SwiftUI

struct WelcomeLanguageStepView: View {
    @Binding var selectedLanguage: AppLanguage

    /// La taille du mot d'accueil. `@ScaledMetric` plutôt qu'une constante :
    /// une taille en points ne suivrait pas les réglages d'accessibilité, et
    /// c'est le texte que toute la page donne à lire.
    @ScaledMetric(relativeTo: .largeTitle) private var welcomeSize: CGFloat = 56

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            // Le mot ne se contente pas de s'afficher : il se tape, s'efface,
            // et repart dans la langue suivante. Les bornes de mise en page —
            // deux lignes puis le rapetissement, « Le damos la bienvenida »
            // faisant trois fois la longueur de « Welcome » — sont dans le
            // composant, qui doit les appliquer aussi à ses mots fantômes.
            TypewriterGreeting(startingLanguage: selectedLanguage)
                .font(.system(size: welcomeSize, weight: .bold))

            languageMenu

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// Le sélecteur de langue : la gélule de verre du « Passer » et du bouton
    /// retour, pour que les commandes flottantes de l'onboarding se
    /// ressemblent.
    ///
    /// Un `Picker` dans le menu plutôt qu'une suite de boutons — comme le tri
    /// des trajets : c'est lui qui coche la langue en cours, et son intitulé
    /// devient l'en-tête du menu qui s'ouvre.
    ///
    /// Le globe est là pour qui ne lit pas la langue affichée : sans lui, le
    /// nom d'une langue inconnue posé sur un bouton n'annonce pas qu'on peut
    /// en changer.
    private var languageMenu: some View {
        Menu {
            Picker(selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    // Chaque langue s'annonce dans la sienne : ce libellé ne
                    // passe donc pas par le catalogue de traductions.
                    Text(language.nativeName).tag(language)
                }
            } label: {
                Text("Choisissez la langue")
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                Text(selectedLanguage.nativeName)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.body.weight(.semibold))
            .frame(height: 28)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Choisissez la langue")
        .accessibilityValue(selectedLanguage.nativeName)
    }
}

#Preview {
    @Previewable @State var language: AppLanguage = .systemDefault

    WelcomeLanguageStepView(selectedLanguage: $language)
        .padding()
        .appBackground()
}
