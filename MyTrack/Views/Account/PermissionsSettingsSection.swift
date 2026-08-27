//
//  PermissionsSettingsSection.swift
//  MyTrack
//
//  La section « Autorisations » des réglages : ce que le suivi automatique
//  attend d'iOS, et où en est chaque demande.
//
//  iOS ne pose sa question qu'une fois. Tant qu'elle n'a jamais été posée, la
//  demande fait bien apparaître la fenêtre système ; une fois refusée, la même
//  demande ne fait plus rien du tout — silencieusement. Une ligne qui
//  appellerait toujours `request…` laisserait donc l'utilisateur taper dans le
//  vide sans rien comprendre. C'est pourquoi chaque ligne lit son état avant
//  d'agir : elle demande quand le système répondra encore, et ouvre les
//  Réglages d'iOS quand c'est le seul chemin qui reste.
//

import CoreLocation
import CoreMotion
import SwiftUI
import UIKit

struct PermissionsSettingsSection: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.scenePhase) private var scenePhase

    /// CoreMotion ne prévient personne quand son autorisation change et
    /// `MotionActivityService` n'est pas observable : l'état est relu à la
    /// main. À l'ouverture, après chaque demande, et au retour au premier plan
    /// — revenir des Réglages d'iOS est le seul moment où l'app peut
    /// s'apercevoir qu'on vient d'y changer quelque chose.
    @State private var motionStatus: CMAuthorizationStatus = .notDetermined

    var body: some View {
        Section {
            PermissionRow(
                title: "Localisation",
                systemImage: "location",
                state: locationState,
                action: requestLocation
            )
            PermissionRow(
                title: "Activité physique",
                systemImage: "figure.walk.motion",
                state: motionState,
                action: requestMotion
            )
        } header: {
            Text("Autorisations")
        } footer: {
            Text("Le suivi automatique a besoin de la position réglée sur « Toujours » pour réveiller l'app au départ d'un trajet, et de l'activité physique pour reconnaître la conduite. Une autorisation refusée ne peut plus se rétablir que dans les Réglages d'iOS.")
        }
        .onAppear { refreshMotionStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshMotionStatus() }
        }
    }

    // MARK: - État

    /// « Pendant l'utilisation » compte comme une demande encore possible et
    /// non comme un refus : iOS accepte de proposer le passage à « Toujours »,
    /// et c'est ce palier-là qui manque au suivi automatique.
    private var locationState: PermissionState {
        switch appServices.locationService.authorizationStatus {
        case .authorizedAlways: .satisfied("Toujours")
        case .authorizedWhenInUse: .askable("Pendant l'utilisation")
        case .notDetermined: .askable("Autoriser")
        default: .blocked("Refusé")
        }
    }

    private var motionState: PermissionState {
        guard appServices.motionActivityService.isAvailable else { return .unavailable }
        switch motionStatus {
        case .authorized: return .satisfied("Autorisé")
        case .notDetermined: return .askable("Autoriser")
        default: return .blocked("Refusé")
        }
    }

    // MARK: - Actions

    private func requestLocation() {
        switch appServices.locationService.authorizationStatus {
        case .notDetermined:
            // `LocationService` est observable : la ligne se met à jour toute
            // seule quand la réponse arrive.
            appServices.locationService.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            appServices.locationService.requestAlwaysAuthorization()
        default:
            openSystemSettings()
        }
    }

    private func requestMotion() {
        guard motionStatus == .notDetermined else {
            openSystemSettings()
            return
        }
        Task {
            await appServices.motionActivityService.requestAuthorization()
            refreshMotionStatus()
        }
    }

    private func refreshMotionStatus() {
        motionStatus = appServices.motionActivityService.authorizationStatus
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Ce qu'il reste à faire pour une autorisation, plutôt que l'état brut rendu
/// par iOS : c'est ce qui décide à la fois du libellé de droite et de ce que
/// fait la ligne quand on la touche.
private enum PermissionState {
    /// Accordée — il n'y a plus rien à demander, la ligne ne réagit plus.
    case satisfied(LocalizedStringKey)
    /// Jamais demandée, ou demandée à un palier inférieur : le système
    /// répondra encore par sa fenêtre.
    case askable(LocalizedStringKey)
    /// Refusée : seuls les Réglages d'iOS peuvent encore la lever.
    case blocked(LocalizedStringKey)
    /// L'appareil n'a pas le capteur — rien à accorder ici.
    case unavailable

    var value: LocalizedStringKey {
        switch self {
        case .satisfied(let value), .askable(let value), .blocked(let value): value
        case .unavailable: "Indisponible"
        }
    }

    var isSatisfied: Bool {
        if case .satisfied = self { return true }
        return false
    }

    var isActionable: Bool {
        switch self {
        case .askable, .blocked: true
        case .satisfied, .unavailable: false
        }
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let state: PermissionState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                // Gris quand c'est acquis, à l'accent quand il reste quelque
                // chose à faire : la couleur est ce qui distingue un état d'une
                // invitation à agir, avant même de lire le mot.
                Text(state.value)
                    .foregroundStyle(state.isSatisfied ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                if state.isActionable {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            // Sans ça, seul le texte est tapable : la ligne entière doit
            // répondre, y compris l'espace vide au milieu.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!state.isActionable)
    }
}
