//
//  SlideToConfirmButton.swift
//  MyTrack
//
//  Un bouton qu'on fait glisser au lieu de l'appuyer, dans le style des
//  glissières système d'iOS — « glisser pour éteindre », l'appel d'urgence,
//  l'arrêt d'alarme.
//
//  Trois choses font ce rendu, et il en manquerait une que ça retomberait dans
//  le fait-maison : une gélule à peine teintée qui laisse voir le fond, un
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
    /// Le libellé posé dans la gélule, que la pastille traverse.
    var title: LocalizedStringKey
    /// Le symbole SF porté par la pastille.
    var systemImage: String
    /// La teinte de l'ensemble : verte pour lancer, rouge pour arrêter.
    var tint: Color
    /// Rapporte où en est la pastille, de 0 à 1, à chaque instant du geste —
    /// y compris quand elle revient en arrière parce que le doigt recule.
    ///
    /// C'est ce qui permet à l'écran de suivre le glissement au lieu de le
    /// subir : la scène derrière le bouton avance et recule avec le pouce, et
    /// le geste devient réversible tant qu'il n'est pas allé au bout.
    ///
    /// Les retours au repos sont rapportés depuis l'intérieur de leur
    /// animation, pour que ce qui écoute reparte avec la même courbe plutôt
    /// que de sauter.
    var onProgressChange: (CGFloat) -> Void = { _ in }
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

    /// Hauteur de la gélule, donc diamètre de la pastille.
    private let height: CGFloat = 68

    /// La teinte de ce qui doit se lire : le libellé et le symbole.
    ///
    /// Les glissières système d'iOS ne vivent que sur fond noir, où le vert et
    /// le rouge ressortent d'eux-mêmes. L'app, elle, a aussi un thème clair, et
    /// ces deux couleurs y sont vives mais claires : posées sur un gris presque
    /// blanc, elles se délavent au point que le libellé disparaît. On les
    /// assombrit donc de ce côté-là seulement — le thème sombre garde la teinte
    /// pleine, qui est déjà la bonne.
    private var ink: Color {
        colorScheme == .dark ? tint : tint.mix(with: .black, by: 0.35)
    }

    /// Ce qui reste du libellé hors du balayage. Plus soutenu en thème clair,
    /// pour la même raison : un tiers d'opacité s'y lit à peine.
    private var restingTextOpacity: Double {
        colorScheme == .dark ? 0.3 : 0.5
    }

    /// Le lavis de la gélule. Un peu plus dense en clair, sinon la forme se
    /// confond avec le fond de l'app au lieu de dessiner le chemin à parcourir.
    private var trackOpacity: Double {
        colorScheme == .dark ? 0.08 : 0.14
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
        // Le retour à zéro est rapporté comme les autres. Quand l'action a
        // abouti, ce que le pouce avait parcouru a déjà été converti en pas
        // franchi de l'autre côté, et ce zéro-là n'apprend rien à personne.
        // Quand elle a échoué — une autorisation refusée, par exemple — c'est
        // au contraire ce qui ramène la scène là où elle doit être.
        .task(id: completions) {
            guard completions > 0 else { return }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.smooth) {
                offsetX = 0
                onProgressChange(0)
            }
            hasReachedEnd = false
        }
    }

    /// Le fond : une gélule à peine teintée, cerclée d'un trait très fin. Elle
    /// ne doit pas se lire comme un bouton plein — c'est la pastille qui porte
    /// la couleur, le reste n'est que le chemin à parcourir.
    private var track: some View {
        Capsule()
            .fill(tint.opacity(trackOpacity))
            .stroke(Color.primary.tertiary, lineWidth: 0.3)
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
            Text(title)
                .foregroundStyle(ink.opacity(restingTextOpacity))

            Text(title)
                .foregroundStyle(ink)
                .mask(alignment: .leading) { shimmerMask }
        }
        .font(.title3)
        .fontWeight(.medium)
        .lineLimit(1)
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
                    .glassEffect(.clear.tint(tint.opacity(0.1)), in: .circle)
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
            .offset(x: offsetX)
            .highPriorityGesture(drag(travel: travel))
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isActive) { _, active, _ in active = true }
            .onChanged { value in
                offsetX = min(max(value.translation.width, 0), travel)
                hasReachedEnd = offsetX == travel
                onProgressChange(offsetX / travel)
            }
            .onEnded { _ in
                if offsetX == travel {
                    onProgressChange(1)
                    fire()
                } else {
                    hasReachedEnd = false
                    withAnimation(.smooth) {
                        offsetX = 0
                        onProgressChange(0)
                    }
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
        SlideToConfirmButton(title: "Démarrer", systemImage: "play.fill", tint: .green) {}
        SlideToConfirmButton(title: "Arrêter", systemImage: "stop.fill", tint: .red) {}
    }
    .padding()
    .appBackground()
}
