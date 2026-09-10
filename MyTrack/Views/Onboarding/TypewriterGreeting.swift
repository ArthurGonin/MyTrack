//
//  TypewriterGreeting.swift
//  MyTrack
//
//  Le mot d'accueil de la toute première page, tapé lettre à lettre comme au
//  clavier, effacé, puis retapé dans la langue suivante — les six que l'app
//  parle, en boucle.
//
//  Il fait défiler *toutes* les langues, et pas seulement celle de l'iPhone,
//  parce que c'est ce qui dit sans un mot que l'app en parle six : celui dont
//  le téléphone n'est pas dans sa langue voit la sienne passer, et comprend
//  que le menu juste en dessous sert à la retenir. Le cycle commence par la
//  langue de l'utilisateur — l'accueil doit d'abord accueillir — mais il ne
//  décide de rien : ce qui est *sélectionné* reste ce que
//  `WelcomeLanguageStepView` tient, et le défilé n'y touche jamais.
//
//  L'ordre du mot complet est posé avant le premier caractère : les six mots
//  sont empilés invisibles derrière, pour que la hauteur du bloc soit d'emblée
//  celle du plus haut d'entre eux. Sans ça « Le damos la bienvenida » passerait
//  sur deux lignes en cours de frappe et ferait descendre le menu, puis
//  remonter — à chaque tour.
//

import SwiftUI

struct TypewriterGreeting: View {
    /// La langue qui ouvre le cycle, et non celle qui le limite.
    let startingLanguage: AppLanguage

    /// Le réglage d'iOS « Réduire les animations ». Une boucle qui ne s'arrête
    /// jamais est exactement ce qu'il vise : le mot s'affiche alors d'un coup,
    /// dans la langue retenue, et plus rien ne bouge.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le rang du mot en cours dans `greetings`.
    @State private var wordIndex = 0
    /// Combien de ses caractères sont déjà tapés.
    @State private var typedCount = 0
    /// Le curseur, allumé pendant la frappe et clignotant pendant la pause.
    @State private var isCursorVisible = true

    /// Le curseur est une *espace* peinte en fond, et non un caractère plein
    /// comme « ▌ ». C'est ce qui le sort de la mise en page : une espace en fin
    /// de ligne ne compte pas dans le centrage, donc le mot se centre sans elle
    /// et la barre déborde à droite sans rien pousser. Un caractère visible,
    /// lui, décale le mot de la moitié de sa largeur — et sur deux lignes,
    /// décale la ligne qui le porte par rapport à l'autre.
    private static let cursor = " "

    var body: some View {
        Group {
            if reduceMotion {
                Text("Bienvenue")
            } else {
                animatedGreeting
            }
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.5)
        // VoiceOver lit le mot une fois, dans la langue de l'app, plutôt que
        // de suivre un texte qui se réécrit sans fin.
        .accessibilityElement()
        .accessibilityLabel(Text("Bienvenue"))
        .task(id: startingLanguage) {
            // Choisir une langue dans le menu relance le défilé sur elle :
            // c'est le retour qui confirme le choix.
            wordIndex = 0
            typedCount = 0
            isCursorVisible = true
            guard !reduceMotion else { return }
            try? await runTypewriter()
        }
    }

    private var animatedGreeting: some View {
        ZStack {
            // Les six mots, invisibles, qui réservent la place du plus haut.
            // Voir l'en-tête du fichier.
            ForEach(AppLanguage.allCases) { language in
                Text(language.greeting).hidden()
            }

            typedLine
        }
    }

    /// Ce qui est tapé, suivi du curseur.
    ///
    /// Les deux ne font qu'un seul `Text` plutôt que deux posés côte à côte
    /// dans un `HStack` : c'est la seule façon que le curseur suive la fin du
    /// mot quand celui-ci passe à la ligne, au lieu de se planter à droite du
    /// bloc entier. Et il ne s'en va pas en clignotant, son fond devient
    /// transparent — retiré, il ferait osciller la ligne à chaque battement.
    ///
    /// L'assemblage passe par une `AttributedString` et non par `Text + Text`,
    /// déprécié depuis iOS 26. L'interpolation qui le remplace ferait de la
    /// ligne une `LocalizedStringKey`, donc une clé cherchée dans le catalogue :
    /// ici le contenu est déjà traduit, il ne doit surtout pas repasser par là.
    ///
    /// Deux autres façons de garder le mot centré ont été essayées et mesurées
    /// avant celle-ci, au cas où l'idée reviendrait : décaler le bloc d'un
    /// demi-curseur ne rattrape que la dernière ligne et laisse la première de
    /// travers de 26 pt en espagnol ; annuler l'avance du curseur par un
    /// crénage négatif centre bien tout, mais ramène du même coup le glyphe sur
    /// la dernière lettre, où il devient invisible. L'espace en fond n'a besoin
    /// ni de l'un ni de l'autre.
    private var typedLine: Text {
        var line = AttributedString(currentWord.prefix(typedCount))
        var cursor = AttributedString(Self.cursor)
        cursor.backgroundColor = isCursorVisible ? .primary : .clear
        line.append(cursor)
        return Text(line)
    }

    /// Les six accueils, celui de l'utilisateur en tête.
    private var greetings: [String] {
        let languages = AppLanguage.allCases
        guard let start = languages.firstIndex(of: startingLanguage) else {
            return languages.map(\.greeting)
        }
        return (languages[start...] + languages[..<start]).map(\.greeting)
    }

    private var currentWord: String {
        greetings[min(wordIndex, greetings.count - 1)]
    }

    /// La boucle qui tape, marque un temps, efface, et passe à la langue
    /// suivante. Sans fin : c'est `.task(id:)` qui l'annule, en quittant
    /// l'écran ou en changeant de langue, et l'annulation ressort par le
    /// `Task.sleep` qui lance — d'où le `throws` plutôt qu'un `try?` posé sur
    /// chaque attente, qui laisserait la boucle tourner à vide une fois
    /// annulée.
    private func runTypewriter() async throws {
        while true {
            let word = greetings[wordIndex]

            // La frappe. L'intervalle n'est pas constant : une main qui tape
            // n'est pas un métronome, et c'est ce léger désordre qui fait la
            // différence entre « tapé » et « déroulé ».
            for count in stride(from: 1, through: word.count, by: 1) {
                try await Task.sleep(for: .milliseconds(Int.random(in: 85...145)))
                typedCount = count
            }

            // Le mot reste lisible, curseur clignotant comme au terminal.
            for _ in 0..<4 {
                try await Task.sleep(for: .milliseconds(700))
                isCursorVisible.toggle()
            }
            isCursorVisible = true

            // L'effacement, plus vif que la frappe : c'est la touche retour
            // tenue enfoncée, pas une seconde main qui écrit. Plus vif, mais
            // pas expédié — à en faire un clignement, on ne voit plus le mot
            // partir, seulement le titre disparaître.
            for count in stride(from: word.count - 1, through: 0, by: -1) {
                try await Task.sleep(for: .milliseconds(55))
                typedCount = count
            }

            // Le blanc avant la langue suivante : sans lui, le premier
            // caractère du mot d'après tombe sur le dernier de celui d'avant.
            try await Task.sleep(for: .milliseconds(500))
            wordIndex = (wordIndex + 1) % greetings.count
        }
    }
}

private extension AppLanguage {
    /// Le mot d'accueil dans cette langue, lu dans son propre bundle.
    ///
    /// C'est la même clé de catalogue que le reste de l'app, mais résolue
    /// langue par langue au lieu de suivre celle de l'environnement : ici on
    /// veut les six traductions en même temps. Aucune n'est écrite en dur —
    /// elles restent celles du catalogue, et se corrigent avec lui.
    var greeting: String {
        String(localized: "Bienvenue", bundle: bundle)
    }
}

#Preview {
    TypewriterGreeting(startingLanguage: .french)
        .font(.system(size: 56, weight: .bold))
        .padding()
        .appBackground()
}
