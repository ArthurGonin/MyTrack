//
//  PhotoAnalysisOverlay.swift
//  MyTrack
//
//  Le voile posé sur la photo pendant que l'IA la travaille.
//
//  Une grille de points bleus qu'une bande parcourt de haut en bas : un point
//  s'allume quand elle passe sur lui, s'éteint derrière elle, et scintille un
//  peu entre-temps. C'est ce qui donne à l'attente l'air d'un examen plutôt que
//  d'un temps mort — et l'attente est réelle, dix à trente secondes le temps
//  que le modèle réponde.
//
//  Un `Canvas` dans un `TimelineView` plutôt qu'un nuage de vues animées :
//  quelques centaines de points redessinés à chaque image coûtent une passe de
//  dessin, là où autant de `Circle` coûteraient autant de vues à disposer. Et
//  l'animation s'arrête d'elle-même quand la vue disparaît, sans minuterie à
//  invalider.
//

import SwiftUI

struct PhotoAnalysisOverlay: View {
    /// L'écart entre deux points, et leur diamètre.
    private let spacing: CGFloat = 26
    private let dotDiameter: CGFloat = 4

    /// Le temps que la bande met à traverser l'image, et sa hauteur : assez
    /// large pour que plusieurs rangées s'allument ensemble.
    private let sweepDuration: TimeInterval = 2.2
    private let bandHeight: CGFloat = 140

    private let dotColor = Color(red: 0.25, green: 0.65, blue: 1)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let progress = time.truncatingRemainder(dividingBy: sweepDuration) / sweepDuration
                // La bande part au-dessus de l'image et finit en dessous : sans
                // ce débord, elle apparaîtrait et disparaîtrait d'un coup sur
                // les bords.
                let band = size.height * (progress * 1.4 - 0.2)

                for row in stride(from: spacing / 2, to: size.height, by: spacing) {
                    let closeness = max(0, 1 - abs(row - band) / bandHeight)
                    for column in stride(from: spacing / 2, to: size.width, by: spacing) {
                        // Un déphasage tiré des coordonnées : les points ne
                        // scintillent pas tous ensemble, et rien n'a besoin
                        // d'être tiré au sort ni mémorisé d'une image à l'autre.
                        let phase = Double(row * 0.07 + column * 0.13)
                        let twinkle = 0.5 + 0.5 * sin(time * 3 + phase)
                        let opacity = 0.06 + 0.8 * Double(closeness) * twinkle
                        context.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: column - dotDiameter / 2,
                                    y: row - dotDiameter / 2,
                                    width: dotDiameter,
                                    height: dotDiameter
                                )
                            ),
                            with: .color(dotColor.opacity(opacity))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ZStack {
        Color.gray
        PhotoAnalysisOverlay()
    }
    .ignoresSafeArea()
}
