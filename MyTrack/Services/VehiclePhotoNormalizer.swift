//
//  VehiclePhotoNormalizer.swift
//  MyTrack
//
//  Ramène un détourage de voiture — d'où qu'il vienne — à un cadre unique.
//
//  Une voiture détourée arrive n'importe comment : mesuré sur trois essais du
//  modèle d'images, le bas des pneus tombait à 91 % de la hauteur pour un SUV et
//  à 85 % pour un coupé, soit 68 pixels d'écart. Posées telles quelles sur
//  l'accueil, deux voitures ne seraient pas à la même hauteur et la mise en page
//  bougerait de l'une à l'autre.
//
//  D'où ce passage obligé : le cadre est constant, la ligne de sol est commune,
//  et c'est la voiture qui s'y inscrit. Chacune garde ses proportions — un
//  pick-up reste large, une citadine étroite — mais toutes sont garées au même
//  endroit.
//
//  L'ombre au sol est dessinée ici plutôt que demandée au modèle : sur les mêmes
//  trois essais, il n'en a produit aucune (alpha à zéro sous les roues), et une
//  voiture sans ombre a l'air collée sur le fond.
//

import CoreGraphics
import Foundation

nonisolated enum VehiclePhotoNormalizer {
    /// Le cadre commun à toutes les photos, et à l'illustration par défaut :
    /// c'est lui qui garantit que l'accueil ne bouge pas d'un véhicule à
    /// l'autre.
    static let canvasSize = CGSize(width: 1536, height: 1024)

    /// La zone où la carrosserie doit tenir, en fractions du cadre. La
    /// contrainte qui arrive en premier gagne : un coupé bas touche les côtés,
    /// un SUV touche le haut.
    private static let safeWidth: CGFloat = 0.86
    private static let safeHeight: CGFloat = 0.80

    /// La hauteur, comptée depuis le haut, où le bas des roues se pose.
    private static let groundLine: CGFloat = 0.94

    /// Le seuil qui sépare la carrosserie du reste.
    ///
    /// Haut exprès : la lueur que les modèles ajoutent autour du véhicule varie
    /// beaucoup d'une image à l'autre — jaune vif autour d'une Lamborghini,
    /// blanche autour d'un Range Rover — et la laisser entrer dans la mesure
    /// rapetisserait les voitures les plus auréolées. Elle est dessinée quand
    /// même : elle est décorative, elle n'a pas à décider de l'échelle.
    private static let bodyAlphaThreshold: UInt8 = 128

    /// L'ombre de contact : ses proportions, sa densité, et le nombre d'anneaux
    /// qui en font le fondu.
    private static let shadowWidthRatio: CGFloat = 1.02
    private static let shadowHeightRatio: CGFloat = 0.055
    private static let shadowRings = 28
    private static let shadowOpacityPerRing: CGFloat = 0.0145

    /// La voiture, remise au cadre commun : mise à l'échelle pour tenir dans la
    /// zone utile, centrée, posée sur la ligne de sol, son ombre dessous.
    ///
    /// Rend nil quand l'image ne contient aucun pixel franc — un détourage qui
    /// n'a rien trouvé, par exemple.
    static func normalized(_ image: CGImage) -> CGImage? {
        guard let body = bodyBox(of: image) else { return nil }

        let scale = min(
            canvasSize.width * safeWidth / body.width,
            canvasSize.height * safeHeight / body.height
        )
        let drawnSize = CGSize(
            width: CGFloat(image.width) * scale,
            height: CGFloat(image.height) * scale
        )
        // Le milieu de la carrosserie se pose sur l'axe, son bas sur la ligne de
        // sol — celle-ci comptée depuis le bas, comme dessine Core Graphics.
        let origin = CGPoint(
            x: canvasSize.width / 2 - body.midX * scale,
            y: canvasSize.height * (1 - groundLine) - body.minY * scale
        )

        guard let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        drawGroundShadow(in: context, bodyWidth: body.width * scale)
        context.draw(
            image,
            in: CGRect(origin: origin, size: drawnSize)
        )
        return context.makeImage()
    }

    /// La boîte de la carrosserie, en coordonnées Core Graphics.
    ///
    /// Deux repères se croisent ici, et c'est le piège classique : le tampon
    /// d'un contexte bitmap commence par la ligne du **haut**, alors que Core
    /// Graphics dessine depuis le **bas**. Les lignes sont donc parcourues de
    /// haut en bas puis converties une bonne fois, pour que l'appelant n'ait à
    /// penser qu'à un seul sens.
    private static func bodyBox(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, maxX = -1, topRow = height, bottomRow = -1
        for row in 0..<height {
            for column in 0..<width where pixels[(row * width + column) * 4 + 3] > bodyAlphaThreshold {
                minX = min(minX, column)
                maxX = max(maxX, column)
                topRow = min(topRow, row)
                bottomRow = max(bottomRow, row)
            }
        }
        guard maxX >= minX, bottomRow >= topRow else { return nil }

        return CGRect(
            x: CGFloat(minX),
            y: CGFloat(height - 1 - bottomRow),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(bottomRow - topRow + 1)
        )
    }

    /// L'ombre de contact, en ellipses concentriques.
    ///
    /// Un `drawRadialGradient` serait le geste évident, mais il ne rend rien
    /// sous le repère aplati qu'exige une ellipse. Vingt-huit anneaux de faible
    /// opacité s'accumulent en un fondu que l'œil ne décompose pas.
    private static func drawGroundShadow(in context: CGContext, bodyWidth: CGFloat) {
        let width = bodyWidth * shadowWidthRatio
        let height = canvasSize.height * shadowHeightRatio
        let centre = CGPoint(
            x: canvasSize.width / 2,
            y: canvasSize.height * (1 - groundLine)
        )
        for ring in 0..<shadowRings {
            let factor = 1 - CGFloat(ring) / CGFloat(shadowRings)
            context.setFillColor(gray: 0, alpha: shadowOpacityPerRing)
            context.fillEllipse(
                in: CGRect(
                    x: centre.x - width * factor / 2,
                    y: centre.y - height * factor / 2,
                    width: width * factor,
                    height: height * factor
                )
            )
        }
    }
}
