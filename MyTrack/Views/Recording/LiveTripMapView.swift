//
//  LiveTripMapView.swift
//  MyTrack
//

import SwiftUI
import MapKit

/// Carte affichée pendant un enregistrement : suit la position de l'utilisateur
/// en direct. Volontairement non interactive — c'est un indicateur visuel, pas
/// une carte à explorer.
///
/// Ne rogne pas ses coins : c'est à qui la pose de le faire, selon la surface
/// où elle se pose. Elle le faisait, et son arrondi à elle — le plus petit —
/// l'emportait sur celui demandé au-dehors, qui n'a donc jamais rien donné.
///
/// N'utilise pas `LocationService` : `UserAnnotation` s'appuie sur le
/// `CLLocationManager` interne de MapKit. `LocationService.onLocationUpdate`
/// est un slot unique déjà pris par `TripRecorder` pendant un enregistrement,
/// s'y brancher ici casserait l'enregistrement.
struct LiveTripMapView: View {
    /// Le parcours déjà enregistré, du départ jusqu'au dernier point. Vide
    /// pendant les deux premières secondes d'un trajet — le lissage retient un
    /// point le temps qu'arrive son voisin de droite — et c'est sans
    /// conséquence : une polyligne demande deux points de toute façon.
    let route: [CLLocationCoordinate2D]

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            // Le bleu et l'épaisseur de `TripRouteMapView`, délibérément : c'est
            // la même trace, vue avant et après la fin du trajet, et elle n'a
            // pas à changer d'apparence entre les deux. C'est aussi la couleur
            // du point de position juste en dessous, que MapKit dessine
            // par-dessus les tracés quel que soit l'ordre de déclaration.
            if route.count >= 2 {
                MapPolyline(coordinates: route)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            UserAnnotation()
        }
        .mapControls {}
        // Le bleu de Plans, posé explicitement sur la carte.
        //
        // `UserAnnotation` n'a pas de couleur à elle : elle prend la teinte de
        // l'environnement, et celle de l'app est un noir pur qui devient blanc
        // pur en thème sombre (voir `Color.onAccent`). Le point de position se
        // dessinait donc en noir au milieu de sa propre trace bleue — un
        // accident, et non un choix : c'est le seul élément de l'app qui
        // appartienne à Plans et non à MyTrack, et il doit rester celui que
        // tout le monde reconnaît.
        .tint(.blue)
    }
}

#Preview {
    LiveTripMapView(route: [
        CLLocationCoordinate2D(latitude: 46.5197, longitude: 6.6323),
        CLLocationCoordinate2D(latitude: 46.5205, longitude: 6.6340),
        CLLocationCoordinate2D(latitude: 46.5218, longitude: 6.6351),
    ])
    .frame(height: 300)
    .clipShape(.rect(cornerRadius: 22, style: .continuous))
    .padding()
}
