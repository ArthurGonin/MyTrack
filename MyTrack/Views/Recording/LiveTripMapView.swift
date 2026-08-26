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
/// N'utilise pas `LocationService` : `UserAnnotation` s'appuie sur le
/// `CLLocationManager` interne de MapKit. `LocationService.onLocationUpdate`
/// est un slot unique déjà pris par `TripRecorder` pendant un enregistrement,
/// s'y brancher ici casserait l'enregistrement.
struct LiveTripMapView: View {
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            UserAnnotation()
        }
        .mapControls {}
        .clipShape(.rect(cornerRadius: 10))
    }
}

#Preview {
    LiveTripMapView()
        .frame(height: 300)
        .padding()
}
