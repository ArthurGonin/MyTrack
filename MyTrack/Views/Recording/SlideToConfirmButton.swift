//
//  SlideToConfirmButton.swift
//  MyTrack
//

import SwiftUI

/// Un bouton qu'on fait glisser au lieu de l'appuyer.
///
/// Au repos, une pastille de couleur occupe l'un des deux bouts d'une gélule en
/// verre. On la pousse vers le bout opposé : elle laisse sa couleur derrière
/// elle, comme si elle s'étirait sous le doigt, et l'action part une fois la
/// gélule remplie. Relâcher avant la fin la renvoie à sa place.
///
/// Le sens vient de `startEdge` — depuis la gauche pour démarrer, depuis la
/// droite pour arrêter. Le geste inverse pour l'action inverse, ce qui rend
/// l'arrêt impossible à déclencher par le geste qui lance.
struct SlideToConfirmButton: View {
    /// Le libellé au centre de la gélule. Il passe en blanc au fur et à mesure
    /// que la couleur le recouvre.
    var title: LocalizedStringKey
    /// Le symbole SF porté par la pastille : le chevron qui montre où pousser.
    var systemImage: String
    /// La couleur de la pastille et de la traînée qu'elle laisse.
    var tint: Color
    /// Le bord où la pastille se repose, donc le sens du glissement.
    var startEdge: HorizontalEdge
    /// Appelée une fois la gélule remplie.
    var action: () -> Void

    /// Distance parcourue par la pastille depuis son bord de repos, en points.
    @State private var travelled: CGFloat = 0
    /// Largeur mesurée de la gélule, d'où se déduit la course de la pastille.
    @State private var width: CGFloat = 0
    /// Vrai dès que le doigt est allé assez loin pour valider en relâchant.
    @State private var isAtEnd = false
    /// Compte les glissements menés à terme. C'est un déclencheur : ce qui
    /// compte est qu'il change, pas ce qu'il vaut.
    @State private var completions = 0

    /// Hauteur de la gélule, donc diamètre de la pastille.
    private let height: CGFloat = 52
    /// Part de la course à franchir pour valider. Exiger la totalité
    /// obligerait à pousser le doigt au pixel près jusqu'au bord.
    private let threshold: CGFloat = 0.9

    var body: some View {
        ZStack {
            label(color: .secondary)
            trail
            // Le même libellé en blanc, découpé à la forme de la traînée : le
            // texte se recolore donc au passage de la couleur, sans qu'il y ait
            // deux textes à garder alignés à la main — c'est le même, dessiné
            // deux fois.
            label(color: .white)
                .mask(alignment: restAlignment) {
                    Capsule().frame(width: height + travelled)
                }
            knob
        }
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(6)
        // La zone de glissement couvre le verre en entier, marge comprise :
        // s'arrêter à la gélule intérieure ferait rater les prises un peu
        // hautes ou un peu basses.
        .contentShape(.capsule)
        .gesture(slide)
        .glassEffect(.regular.tint(tint.opacity(0.15)).interactive(), in: .capsule)
        // Un coup sec quand le doigt atteint le point de validation : on sait
        // qu'on peut relâcher sans regarder l'écran.
        .sensoryFeedback(.impact(weight: .light), trigger: isAtEnd) { _, atEnd in atEnd }
        .sensoryFeedback(.success, trigger: completions)
        // VoiceOver ne fait pas glisser : sans action explicite, le bouton
        // serait hors de portée.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { fire() }
        // La gélule reste pleine le temps que l'écran change de contenu, puis
        // se vide. Ce retour ne se voit que si on est encore là — c'est-à-dire
        // quand l'action n'a rien changé à l'écran, par exemple parce qu'elle a
        // buté sur une autorisation refusée.
        .task(id: completions) {
            guard completions > 0 else { return }
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.snappy(duration: 0.3, extraBounce: 0.1)) { travelled = 0 }
        }
    }

    /// La course de la pastille : la largeur de la gélule moins la pastille
    /// elle-même, qui occupe déjà un diamètre au repos. Jamais nulle, pour ne
    /// pas diviser par zéro à la première image, avant la mesure.
    private var travel: CGFloat { max(width - height, 1) }

    /// Le bord de repos, dit dans le vocabulaire des `frame` et des `mask`.
    private var restAlignment: Alignment { startEdge == .leading ? .leading : .trailing }

    /// Le libellé, centré dans la place que la pastille ne prend pas : centré
    /// sur la gélule entière, il paraîtrait poussé vers la pastille.
    private func label(color: some ShapeStyle) -> some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(startEdge == .leading ? .leading : .trailing, height)
    }

    /// La traînée : la trace que la pastille laisse derrière elle. Au repos
    /// elle se réduit à un disque — une gélule aussi large que haute — pile
    /// sous la pastille, puis s'allonge jusqu'à remplir la gélule.
    private var trail: some View {
        Capsule()
            .fill(tint.gradient)
            .frame(width: height + travelled)
            .frame(maxWidth: .infinity, alignment: restAlignment)
            // Elle s'aplatit d'un rien au milieu de la course, comme un
            // élastique tendu, et retrouve sa hauteur aux deux bouts.
            .scaleEffect(y: 1 - flattening)
    }

    private var flattening: CGFloat {
        let progress = min(travelled / travel, 1)
        return CGFloat(sin(Double(progress) * .pi)) * 0.05
    }

    /// La pastille, redessinée par-dessus le bout arrondi de la traînée qu'elle
    /// recouvre exactement — même couleur, même hauteur, donc même dégradé, qui
    /// va de haut en bas et ne dépend pas de la largeur. Elle sert à masquer le
    /// libellé recoloré : sans elle, le texte blanc traverserait la pastille et
    /// se confondrait avec le chevron.
    private var knob: some View {
        Circle()
            .fill(tint.gradient)
            .overlay {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: height, height: height)
            .frame(maxWidth: .infinity, alignment: restAlignment)
            .offset(x: startEdge == .leading ? travelled : -travelled)
            // Le même aplatissement que la traînée : sans lui la pastille
            // dépasserait d'un cheveu en haut et en bas au milieu de la course.
            .scaleEffect(y: 1 - flattening)
    }

    private var slide: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Le geste va toujours du bord de repos vers l'autre : vers la
                // droite pour une pastille à gauche, vers la gauche sinon.
                let pushed = startEdge == .leading
                    ? value.translation.width
                    : -value.translation.width
                travelled = min(max(pushed, 0), travel)
                isAtEnd = travelled >= travel * threshold
            }
            .onEnded { _ in
                if isAtEnd {
                    withAnimation(.snappy(duration: 0.2, extraBounce: 0)) { travelled = travel }
                    fire()
                } else {
                    withAnimation(.snappy(duration: 0.3, extraBounce: 0.15)) { travelled = 0 }
                }
                isAtEnd = false
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
        SlideToConfirmButton(
            title: "Glisser pour démarrer",
            systemImage: "chevron.right",
            tint: .green,
            startEdge: .leading
        ) {}

        SlideToConfirmButton(
            title: "Glisser pour arrêter",
            systemImage: "chevron.left",
            tint: .red,
            startEdge: .trailing
        ) {}
    }
    .padding()
    .appBackground()
}
