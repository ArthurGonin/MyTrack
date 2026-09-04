//
//  VehiclePhotoImage.swift
//  MyTrack
//
//  La photo détourée d'un véhicule, décodée une fois plutôt qu'à chaque rendu.
//
//  `Image(uiImage: UIImage(data: …))` écrit directement dans un corps de vue a
//  l'air anodin et ne l'est pas. Le PNG que `VehiclePhotoNormalizer` produit fait
//  1536 × 1024 en RGBA : un mégaoctet et demi sur le disque, six une fois
//  décodé. Or SwiftUI réévalue un corps à chaque changement observé — sur
//  l'accueil, c'est à chaque point GPS reçu pendant un enregistrement, et dans
//  la liste des véhicules, c'est une fois par ligne et par rendu. Le décodage
//  était donc refait des dizaines de fois pour une image qui ne bouge pas.
//
//  Il se fait ici, une fois, et le résultat tient jusqu'à ce que la photo
//  change. La comparaison des données brutes que fait `task(id:)` est un
//  `memcmp` d'un mégaoctet et demi — quelques dizaines de microsecondes, contre
//  la dizaine de millisecondes que coûte le décodage qu'elle évite.
//
//  L'image et son remplacement sont laissés à l'appelant : les trois écrans qui
//  s'en servent l'habillent différemment — pleine largeur sur l'accueil,
//  vignette de 44 points dans la liste, bande de 110 points dans la fiche — et
//  ce qu'ils montrent en son absence n'est pas la même chose non plus.
//

import SwiftUI

struct VehiclePhotoImage<Content: View, Placeholder: View>: View {
    let photoData: Data?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var photo: UIImage?

    var body: some View {
        Group {
            if let photo {
                content(Image(uiImage: photo))
            } else {
                placeholder()
            }
        }
        .task(id: photoData) {
            photo = photoData.flatMap(UIImage.init(data:))
        }
    }
}
