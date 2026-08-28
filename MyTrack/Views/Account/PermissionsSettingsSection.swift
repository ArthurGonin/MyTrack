//
//  PermissionsSettingsSection.swift
//  MyTrack
//
//  La section « Autorisations » des réglages : ce que le suivi automatique
//  attend d'iOS, et où en est chaque demande.
//
//  iOS ne pose sa question qu'une fois. Tant qu'elle n'a jamais été posée, la
//  demande fait bien apparaître la fenêtre système ; une fois répondue, la même
//  demande ne fait plus rien du tout — silencieusement. Une ligne qui
//  appellerait toujours `request…` laisserait donc l'utilisateur taper dans le
//  vide sans rien comprendre. C'est pourquoi chaque ligne lit son état avant
//  d'agir : elle ne pose la question système que la première fois, et mène aux
//  Réglages d'iOS dans tous les autres cas — pour lever un refus comme pour
//  relire ou reprendre ce qui a déjà été accordé. Seule une autorisation que
//  l'appareil ne peut pas rendre reste inerte.
//

import CoreLocation
import CoreMotion
import SwiftUI
import UIKit
import UserNotifications

struct PermissionsSettingsSection: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.scenePhase) private var scenePhase

    /// Ni CoreMotion ni les notifications ne préviennent quand leur
    /// autorisation change — il n'y a pas de délégué à écouter, seulement une
    /// lecture à refaire. D'où ces deux copies relues à la main : à
    /// l'affichage, après chaque demande, et au retour au premier plan, seul
    /// moment où l'app peut s'apercevoir qu'on vient de changer quelque chose
    /// dans les Réglages d'iOS. La position, elle, est observable et se met à
    /// jour toute seule.
    @State private var motionStatus: CMAuthorizationStatus = .notDetermined
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Section {
            PermissionRow(
                title: "Localisation",
                systemImage: "location.square.fill",
                tint: .blue,
                state: locationState,
                action: requestLocation
            )
            // `figure.walk.motion` serait le symbole propre à l'activité
            // physique — c'est celui de CoreMotion et de la rubrique
            // « Mouvement et forme » des Réglages d'iOS. Mais Apple n'en
            // publie aucune variante `.square.fill`, et tout l'écran tient sur
            // cette forme-là. Le cœur, métaphore de la santé chez Apple, dit
            // presque la même chose et laisse l'écran d'un seul tenant.
            PermissionRow(
                title: "Activité physique",
                systemImage: "heart.square.fill",
                tint: .pink,
                state: motionState,
                action: requestMotion
            )
            PermissionRow(
                title: "Notifications",
                systemImage: "bell.square.fill",
                tint: .red,
                state: notificationState,
                action: requestNotifications
            )
        } header: {
            Text("Autorisations")
        } footer: {
            Text("Le suivi automatique a besoin de la position réglée sur « Toujours » pour réveiller l'app au départ d'un trajet, et de l'activité physique pour reconnaître la conduite. Les notifications servent à confirmer un trajet détecté et à prévenir qu'un rapport est prêt. Une autorisation refusée ne peut plus se rétablir que dans les Réglages d'iOS.")
        }
        .task { await refreshStatuses() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshStatuses() }
        }
    }

    // MARK: - État

    /// « Pendant l'utilisation » compte comme une demande encore possible et
    /// non comme un refus : iOS accepte de proposer le passage à « Toujours »,
    /// et c'est ce palier-là qui manque au suivi automatique.
    private var locationState: PermissionState {
        switch appServices.locationService.authorizationStatus {
        case .authorizedAlways: .satisfied("Toujours")
        // Passe par les Réglages plutôt que par `requestAlwaysAuthorization()`.
        // iOS ne propose ce passage à « Toujours » qu'une seule fois : qui l'a
        // refusé une fois taperait ensuite sur une ligne qui n'ouvre plus rien,
        // sans le moindre message. Or c'est précisément la ligne qu'on vient
        // chercher pour réparer un refus.
        case .authorizedWhenInUse: .blocked("Pendant l'utilisation")
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

    /// `.provisional` compte comme accordée : les notifications passent, en
    /// silence, ce qui suffit à ce que l'app en fait — poser une question et
    /// annoncer un rapport. La présenter comme un refus enverrait réparer
    /// quelque chose qui fonctionne.
    private var notificationState: PermissionState {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: .satisfied("Autorisé")
        case .notDetermined: .askable("Autoriser")
        default: .blocked("Refusé")
        }
    }

    // MARK: - Actions

    /// Demander n'a de sens qu'à la toute première fois. Ensuite, seuls les
    /// Réglages d'iOS peuvent encore changer quoi que ce soit — y compris pour
    /// monter de « Pendant l'utilisation » à « Toujours ».
    ///
    /// La fenêtre native de passage à « Toujours » n'est pas perdue pour
    /// autant : c'est `DrivingDetector.enable()` qui la déclenche, au moment où
    /// l'utilisateur active le suivi automatique. Cette section-ci répare, et
    /// pour réparer il faut un chemin qui marche à tous les coups.
    private func requestLocation() {
        guard appServices.locationService.authorizationStatus == .notDetermined else {
            openSystemSettings()
            return
        }
        // `LocationService` est observable : la ligne se met à jour toute seule
        // quand la réponse arrive.
        appServices.locationService.requestWhenInUseAuthorization()
    }

    private func requestMotion() {
        guard motionStatus == .notDetermined else {
            openSystemSettings()
            return
        }
        Task {
            await appServices.motionActivityService.requestAuthorization()
            await refreshStatuses()
            // Le mouvement est l'une des conditions de la surveillance :
            // l'accorder ici doit l'armer, sans quoi elle attendrait le
            // prochain passage au premier plan pour s'en apercevoir.
            appServices.drivingDetector.refresh()
        }
    }

    private func requestNotifications() {
        guard notificationStatus == .notDetermined else {
            openSystemSettings()
            return
        }
        Task {
            await appServices.notificationService.requestAuthorization()
            await refreshStatuses()
        }
    }

    private func refreshStatuses() async {
        motionStatus = appServices.motionActivityService.authorizationStatus
        notificationStatus = await appServices.notificationService.authorizationStatus()
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
    /// Accordée. Il n'y a plus rien à demander, mais la ligne reste vivante et
    /// mène aux Réglages d'iOS : c'est là qu'on va relire ce qu'on a accordé à
    /// l'app, ou le reprendre. Une ligne inerte obligeait à ressortir de l'app
    /// et à retrouver MyTrack à la main dans une liste de tout ce qui est
    /// installé.
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
        case .askable, .blocked, .satisfied: true
        // Pas de capteur sur l'appareil : les Réglages n'ont pas de ligne à
        // montrer pour quelque chose qui n'existe pas ici.
        case .unavailable: false
        }
    }

    /// Vrai quand toucher la ligne fait *sortir* de l'app pour les Réglages
    /// d'iOS, et non apparaître une fenêtre système par-dessus l'app.
    ///
    /// C'est ce qui décide de la flèche oblique : elle ne doit annoncer qu'un
    /// vrai départ. Une ligne qui se contente de poser la question du système
    /// ne quitte rien et n'en porte donc pas.
    var opensSystemSettings: Bool {
        switch self {
        case .blocked, .satisfied: true
        case .askable, .unavailable: false
        }
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let state: PermissionState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                SettingsRowLabel(title, systemImage: systemImage, tint: tint)
                    .foregroundStyle(.primary)
                Spacer()
                // Gris quand c'est acquis, à l'accent quand il reste quelque
                // chose à faire : la couleur est ce qui distingue un état d'une
                // invitation à agir, avant même de lire le mot.
                Text(state.value)
                    .foregroundStyle(state.isSatisfied ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                if state.opensSystemSettings {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
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
