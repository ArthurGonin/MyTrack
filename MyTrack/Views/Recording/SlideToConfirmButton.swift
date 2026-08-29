//
//  SlideToConfirmButton.swift
//  MyTrack
//
//  Un bouton qu'on fait glisser au lieu de l'appuyer, dans le style des
//  glissières système d'iOS — « glisser pour éteindre », l'appel d'urgence,
//  l'arrêt d'alarme.
//
//  Trois choses font ce rendu, et il en manquerait une que ça retomberait dans
//  le fait-maison : une gélule discrète qui laisse voir le fond — du verre ou
//  un lavis de couleur selon ce qu'elle commande, voir `Style` — un
//  balayage lumineux qui traverse le libellé en boucle pour dire « ça se
//  glisse » sans l'écrire, et surtout une pastille qui se comporte en lentille
//  — le texte se déforme derrière elle quand elle passe dessus. C'est ce
//  dernier point qui ne s'obtient pas en SwiftUI seul : il demande le shader
//  `liquidLens`, dans LiquidLens.metal à côté.
//
//  D'après LiquidGlassSlider de Balaji Venkatesh (Kavsoft).
//

import SwiftUI

struct SlideToConfirmButton: View {
    /// L'habillage du bouton.
    enum Style {
        /// Du verre neutre, la matière même de la barre d'onglets : la gélule
        /// laisse voir ce qu'il y a derrière, le libellé et le symbole
        /// prennent la couleur du texte. Pour l'action qui n'a pas à crier —
        /// démarrer un trajet, c'est le geste ordinaire de cet écran.
        case glass
        /// Une gélule teintée, pour l'action qui doit se voir de loin.
        case tinted(Color)

        var isGlass: Bool {
            if case .glass = self { return true }
            return false
        }
    }

    /// Le libellé posé dans la gélule, que la pastille traverse.
    var title: LocalizedStringKey
    /// Le symbole SF porté par la pastille.
    var systemImage: String
    /// De quoi le bouton est fait : du verre, ou une teinte.
    var style: Style
    /// Hauteur de la gélule, donc diamètre de la pastille. Elle se règle de
    /// l'extérieur parce que le bouton n'a pas la même taille selon ce qu'il
    /// commande : au repos il se cale sur la barre d'onglets, en trajet il
    /// prend la pleine taille (voir `RecordTripView`).
    var height: CGFloat = Self.fullHeight
    /// Appelée une fois la pastille menée jusqu'au bout.
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Vrai tant que le doigt est sur la pastille. Pilote le grossissement,
    /// qui est aussi ce qui change la focale de la lentille.
    @GestureState private var isActive = false
    /// Distance parcourue par la pastille depuis le bord gauche, en points.
    @State private var offsetX: CGFloat = 0
    /// Compte les glissements menés à terme. C'est un déclencheur : ce qui
    /// compte est qu'il change, pas ce qu'il vaut.
    @State private var completions = 0
    /// Vrai quand la pastille est allée jusqu'au bout et n'en est pas encore
    /// revenue. Sert au retour haptique, une seule fois par passage.
    @State private var hasReachedEnd = false
    /// Ce que `label` affiche vraiment. `title` change au milieu du ressort
    /// qui ouvre la feuille, et un `.animation(value:)` posé directement sur
    /// le texte hérite quand même de ce ressort-là — c'est le même
    /// changement d'état qui déclenche les deux. En recopiant `title` ici
    /// nous-mêmes, dans un `withAnimation` séparé (voir `onChange` plus
    /// bas), ce texte-là ne suit plus que la courbe qu'on lui donne.
    @State private var displayedTitle: LocalizedStringKey

    /// La hauteur du bouton quand rien ne le contraint — celle qu'il prend en
    /// pleine feuille, et celle des glissières système dont il s'inspire.
    static let fullHeight: CGFloat = 68

    init(
        title: LocalizedStringKey,
        systemImage: String,
        style: Style,
        height: CGFloat = SlideToConfirmButton.fullHeight,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.height = height
        self.action = action
        self._displayedTitle = State(initialValue: title)
    }

    /// La teinte de ce qui doit se lire : le libellé et le symbole.
    ///
    /// En verre, c'est la couleur du texte — et `.primary` plutôt qu'un noir
    /// écrit en dur, pour que le thème sombre la retourne comme il retourne
    /// celle des libellés de la barre d'onglets juste en dessous.
    ///
    /// Teinté, c'est la teinte elle-même. Les glissières système d'iOS ne
    /// vivent que sur fond noir, où le rouge ressort de lui-même. L'app, elle,
    /// a aussi un thème clair, et cette couleur y est vive mais claire : posée
    /// sur un gris presque blanc, elle se délave au point que le libellé
    /// disparaît. On l'assombrit donc de ce côté-là seulement — le thème sombre
    /// garde la teinte pleine, qui est déjà la bonne.
    private var ink: Color {
        switch style {
        case .glass:
            .primary
        case .tinted(let tint):
            colorScheme == .dark ? tint : tint.mix(with: .black, by: 0.35)
        }
    }

    /// Ce qui reste du libellé hors du balayage.
    ///
    /// En verre, presque plein : le libellé doit se lire comme celui d'un
    /// onglet juste en dessous, et un gris à mi-chemin trahirait tout de suite
    /// que ce n'en est pas un. Le balayage n'y passe alors plus qu'un reflet,
    /// et c'est assez — la gélule et la pastille disent déjà que ça se glisse.
    ///
    /// Teinté, il peut rester sourd : la couleur suffit à désigner le libellé,
    /// et le balayage a de quoi le révéler pour de bon. Plus soutenu en thème
    /// clair dans les deux cas — un tiers d'opacité s'y lit à peine.
    private var restingTextOpacity: Double {
        switch style {
        case .glass: colorScheme == .dark ? 0.75 : 0.8
        case .tinted: colorScheme == .dark ? 0.3 : 0.5
        }
    }

    /// Le verre de la pastille. Teinté comme le reste quand le bouton l'est,
    /// incolore quand il est déjà de verre — une teinte de plus par-dessus le
    /// verre du fond ne ferait que le troubler.
    private var knobGlass: Glass {
        switch style {
        case .glass: .clear
        case .tinted(let tint): .clear.tint(tint.opacity(0.1))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - height, 1)

            ZStack(alignment: .leading) {
                track
                label
                knob(travel: travel)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isActive)
        }
        .frame(height: height)
        // Un coup sec au moment où la pastille atteint le bout : on sait qu'on
        // peut relâcher sans regarder l'écran.
        .sensoryFeedback(.impact(weight: .light), trigger: hasReachedEnd) { _, reached in reached }
        .sensoryFeedback(.success, trigger: completions)
        // VoiceOver ne fait pas glisser : sans action explicite, le bouton
        // serait hors de portée.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { fire() }
        // La gélule reste remplie le temps que l'écran change de contenu, puis
        // se vide. Ce retour ne se voit que si on est encore là — c'est-à-dire
        // quand l'action n'a rien changé à l'écran, par exemple parce qu'elle a
        // buté sur une autorisation refusée.
        .task(id: completions) {
            guard completions > 0 else { return }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.smooth) { offsetX = 0 }
            hasReachedEnd = false
        }
        // Rejoue chaque changement de `title` dans son propre `withAnimation`,
        // pour la raison détaillée à `displayedTitle` : ignorer le ressort
        // ambiant de la feuille qui s'ouvre autour du bouton.
        .onChange(of: title) { _, newTitle in
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedTitle = newTitle
            }
        }
    }

    /// Le fond, c'est-à-dire le chemin à parcourir. Dans les deux habillages il
    /// reste discret : ce n'est pas un bouton plein, et rien n'y doit crier.
    ///
    /// En verre, c'est le matériau d'Apple, celui-là même dont est faite la
    /// barre d'onglets sous le bouton — et c'est tout l'intérêt : les deux
    /// gélules se lisent alors comme une paire, pas comme un bouton posé sur
    /// une barre. Teinté, un lavis cerclé d'un trait très fin, un peu plus
    /// dense en thème clair sinon la forme se confond avec le fond de l'app.
    ///
    /// Une seule gélule pour les deux, et non une par habillage : entre deux
    /// vues, SwiftUI détruit l'une et construit l'autre, et le fondu qui les
    /// relie passe par un creux où ni l'une ni l'autre ne se voit — au beau
    /// milieu de l'ouverture, le bouton s'effaçait. Ici rien n'est remplacé,
    /// seules changent des valeurs : le lavis et le cerne sont des couleurs,
    /// qui s'interpolent, et le verre s'éteint comme celui de la feuille
    /// s'allume, au même instant et par le même chemin.
    private var track: some View {
        Capsule()
            .fill(trackWash)
            .glassEffect(style.isGlass ? .regular : .identity, in: .capsule)
            // Le cerne du lavis, dont le verre n'a pas besoin : il porte déjà
            // son propre bord.
            .overlay {
                Capsule()
                    .stroke(Color.primary.tertiary, lineWidth: 0.3)
                    .opacity(style.isGlass ? 0 : 1)
            }
    }

    /// Le lavis de la gélule : rien sous le verre, un voile de teinte sinon.
    private var trackWash: Color {
        switch style {
        case .glass: .clear
        case .tinted(let tint): tint.opacity(colorScheme == .dark ? 0.08 : 0.14)
        }
    }

    /// Le libellé en deux exemplaires superposés : une version sourde, et
    /// par-dessus la même en pleine teinte, révélée seulement par une bande
    /// oblique et floue qui la traverse en boucle. C'est le balayage des
    /// glissières système, et il dit « ça se glisse » sans avoir à l'écrire.
    ///
    /// L'effet de lentille porte sur ce bloc-là uniquement, et non sur la
    /// gélule entière : c'est le texte qui doit se déformer sous la pastille,
    /// pas le contour qui la contient.
    private var label: some View {
        ZStack(alignment: .leading) {
            Text(displayedTitle)
                .foregroundStyle(ink.opacity(restingTextOpacity))

            Text(displayedTitle)
                .foregroundStyle(ink)
                .mask(alignment: .leading) { shimmerMask }
        }
        .font(.title3)
        .fontWeight(.medium)
        .lineLimit(1)
        // Fait glisser les lettres qui changent à la place du mot entier,
        // qui lui ne bouge pas — le remplacement des glissières système.
        .contentTransition(.numericText())
        // Une largeur de pastille réservée à chaque bout, et le libellé qui
        // rétrécit plutôt que d'y entrer. La gélule au repos fait la taille de
        // la barre d'onglets, et aux corps de texte accessibilité « Démarrer »
        // y devient assez large pour passer sous la pastille posée à gauche.
        // La marge est symétrique : elle borne la place du libellé sans le
        // décentrer, et ne se voit qu'aux tailles où il n'y tenait plus.
        .minimumScaleFactor(0.5)
        .padding(.horizontal, height)
        // Centré sur la gélule entière, et non sur ce qu'il en reste une fois
        // la pastille au repos retirée : c'est la forme qu'on voit, donc c'est
        // par rapport à elle que le libellé doit être au milieu. La pastille
        // lui passe dessus, elle ne lui prend pas sa place.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .visualEffect { [isActive, offsetX, height] content, proxy in
            // La pastille grossit sous le doigt, et la lentille grossit avec
            // elle : c'est le même rectangle qui décrit les deux.
            let scale: CGFloat = isActive ? 1.15 : 0.9
            let lens = CGRect(x: offsetX, y: 0, width: height, height: height)
                .insetBy(dx: height * (1 - scale) / 2, dy: height * (1 - scale) / 2)

            return content.layerEffect(
                ShaderLibrary.liquidLens(
                    .float2(lens.size),
                    .float(lens.minX),
                    // Combien le texte se courbe en passant sous le verre.
                    .float(12),
                    // Sur quelle épaisseur depuis le bord la courbure s'étale.
                    .float(height / 4)
                ),
                maxSampleOffset: proxy.size
            )
        }
    }

    private var shimmerMask: some View {
        GeometryReader { proxy in
            let bandWidth: CGFloat = 30
            Rectangle()
                .frame(width: bandWidth)
                .blur(radius: 5)
                .rotationEffect(.degrees(15))
                .offset(x: -bandWidth)
                .keyframeAnimator(initialValue: CGFloat.zero, repeating: true) { content, offset in
                    content.offset(x: offset)
                } keyframes: { _ in
                    LinearKeyframe(proxy.size.width + bandWidth * 2, duration: 3)
                }
        }
    }

    /// La pastille : le symbole posé sur un disque de verre dont seul le bord
    /// est rendu. Le centre reste vide exprès — c'est par là qu'on voit le
    /// texte déformé, et un disque plein n'aurait rien d'une lentille.
    private func knob(travel: CGFloat) -> some View {
        Image(systemName: systemImage)
            .font(.title3)
            .foregroundStyle(ink)
            .frame(width: height, height: height)
            .clipShape(.circle)
            .background {
                Circle()
                    .fill(.clear)
                    .glassEffect(knobGlass, in: .circle)
                    // Masque inversé : on perce le disque pour ne garder que
                    // son liseré.
                    .mask {
                        Rectangle().overlay {
                            Circle()
                                .padding(2)
                                .blur(radius: 2)
                                .blendMode(.destinationOut)
                        }
                    }
            }
            .contentShape(.circle)
            .scaleEffect(isActive ? 1.15 : 0.9)
            // Borné à la course du moment : la gélule rétrécit quand la feuille
            // s'ouvre autour d'elle, et la pastille — restée au bout le temps
            // que l'écran change — dépasserait sinon du bord droit.
            .offset(x: min(offsetX, travel))
            .highPriorityGesture(drag(travel: travel))
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isActive) { _, active, _ in active = true }
            .onChanged { value in
                offsetX = min(max(value.translation.width, 0), travel)
                hasReachedEnd = offsetX == travel
            }
            .onEnded { _ in
                if offsetX == travel {
                    fire()
                } else {
                    hasReachedEnd = false
                    withAnimation(.smooth) { offsetX = 0 }
                }
            }
    }

    /// Une seule porte de sortie vers l'action, que le geste vienne du doigt ou
    /// de VoiceOver.
    private func fire() {
        completions += 1
        action()
    }
}

#Preview {
    VStack(spacing: 24) {
        SlideToConfirmButton(title: "Démarrer", systemImage: "play.fill", style: .glass) {}
        SlideToConfirmButton(title: "Arrêter", systemImage: "stop.fill", style: .tinted(.red)) {}
    }
    .padding()
    .appBackground()
}
