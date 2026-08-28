//
//  SlideToConfirmButton.swift
//  MyTrack
//

import SwiftUI

/// Un bouton qu'on fait glisser au lieu de l'appuyer.
///
/// Au repos, une pastille de verre teinté occupe l'un des deux bouts d'une
/// gélule. On la pousse vers le bout opposé : sa couleur s'étire derrière elle,
/// comme si elle s'allongeait sous le doigt, et l'action part une fois la
/// gélule remplie. Relâcher avant la fin la renvoie à sa place.
///
/// La pastille est translucide : le libellé reste lisible dessous, elle le
/// teinte au passage au lieu de le cacher.
///
/// Le sens vient de `startEdge` — depuis la gauche pour démarrer, depuis la
/// droite pour arrêter. Le geste inverse pour l'action inverse, ce qui rend
/// l'arrêt impossible à déclencher par le geste qui lance.
struct SlideToConfirmButton: View {
    /// Le libellé, centré sur la gélule entière — la pastille passe dessus, pas
    /// à côté.
    var title: LocalizedStringKey
    /// Le symbole SF porté par la pastille : le chevron qui montre où pousser.
    var systemImage: String
    /// La teinte du verre de la pastille, et en plus pâle celui de la gélule.
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
    private let height: CGFloat = 64
    /// Part de la course à franchir pour valider. Exiger la totalité
    /// obligerait à pousser le doigt au pixel près jusqu'au bord.
    private let threshold: CGFloat = 0.9

    var body: some View {
        ZStack {
            pastille
            chevron
            label
        }
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(6)
        // La zone de glissement couvre le verre en entier, marge comprise :
        // s'arrêter à la gélule intérieure ferait rater les prises un peu
        // hautes ou un peu basses.
        .contentShape(.capsule)
        .gesture(slide)
        .glassEffect(.regular.tint(tint.opacity(0.12)), in: .capsule)
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

    /// Le bord de repos, dit dans le vocabulaire des `frame`.
    private var restAlignment: Alignment { startEdge == .leading ? .leading : .trailing }

    private var label: some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    /// La pastille et la traînée qu'elle laisse sont une seule forme : une
    /// gélule ancrée au bord de repos, large d'un diamètre plus la distance
    /// parcourue. Au repos elle est donc exactement un rond, et elle s'allonge
    /// ensuite jusqu'à remplir la gélule.
    ///
    /// Du verre à demi teinté, et pas un aplat : le libellé se lit au travers
    /// au lieu d'être recouvert. Il passe d'ailleurs par-dessus et non dessous —
    /// le Liquid Glass floute ce qu'il a derrière lui, et un mot flouté n'est
    /// plus un mot.
    private var pastille: some View {
        Color.clear
            .frame(width: height + travelled, height: height)
            .glassEffect(.regular.tint(tint.opacity(0.5)).interactive(), in: .capsule)
            .frame(maxWidth: .infinity, alignment: restAlignment)
            // Elle s'aplatit d'un rien au milieu de la course, comme un
            // élastique tendu, et retrouve sa hauteur aux deux bouts.
            .scaleEffect(y: 1 - flattening)
    }

    /// Part de la course déjà faite, de 0 à 1.
    private var progress: CGFloat { min(travelled / travel, 1) }

    private var flattening: CGFloat {
        CGFloat(sin(Double(progress) * .pi)) * 0.05
    }

    private var chevron: some View {
        Image(systemName: systemImage)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: height, height: height)
            .frame(maxWidth: .infinity, alignment: restAlignment)
            .offset(x: startEdge == .leading ? travelled : -travelled)
            // Il dit « pousse ici ». Une fois qu'on pousse il n'a plus rien à
            // dire, et il s'efface avant d'arriver sur le libellé plutôt que de
            // lui passer au travers.
            .opacity(1 - min(progress / 0.3, 1))
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
            title: "Démarrer",
            systemImage: "chevron.right",
            tint: .green,
            startEdge: .leading
        ) {}

        SlideToConfirmButton(
            title: "Arrêter",
            systemImage: "chevron.left",
            tint: .red,
            startEdge: .trailing
        ) {}
    }
    .padding()
    .appBackground()
}
