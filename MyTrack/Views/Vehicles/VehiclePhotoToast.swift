//
//  VehiclePhotoToast.swift
//  MyTrack
//
//  La pastille qui dit où en est le détourage d'une photo de véhicule.
//
//  Une gélule de verre en haut de l'écran, et rien de plus : le travail dure
//  dix à trente secondes, et pendant ce temps l'app doit rester utilisable —
//  d'où une pastille qui ne prend pas la main plutôt qu'un écran d'attente.
//  Elle ne reçoit donc aucun toucher : ce qui est dessous continue de répondre.
//
//  « En cours » ne part pas toute seule ; ce qui est fini s'efface après
//  quelques secondes. Les deux délais sont dans `VehiclePhotoProcessingService`,
//  avec l'état qu'ils gouvernent.
//
//  Une seule pastille pour toute l'app, et elle vit dans sa propre fenêtre.
//  Elle a d'abord été posée écran par écran, parce qu'une surimpression ne
//  traverse pas une feuille : celle de la racine se serait retrouvée cachée par
//  la liste des véhicules, d'où l'on photographie. Mais une feuille ne monte
//  pas jusqu'en haut de l'écran, et on en voyait donc deux à la fois — celle de
//  la feuille, et celle de la racine qui dépassait au-dessus, chacune avec sa
//  propre animation. Une fenêtre à part règle les deux d'un coup : elle est
//  au-dessus de tout ce que l'app présente, feuilles comprises, donc une seule
//  suffit.
//

import SwiftUI
import UIKit

struct VehiclePhotoToast: View {
    let state: VehiclePhotoProcessingService.State

    var body: some View {
        HStack(spacing: 9) {
            symbol
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .capsule)
        // Sans ça, VoiceOver lit la roue et le texte comme deux éléments, et
        // l'annonce arrive coupée en deux.
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var symbol: some View {
        switch state {
        case .processing:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    /// Trois mots, pas une phrase : la gélule tient sur une ligne, et un échec
    /// n'a rien à expliquer ici — reprendre la photo se fait d'un appui sur la
    /// vignette du véhicule, et c'est le seul geste qu'il y ait à faire.
    private var title: LocalizedStringKey {
        switch state {
        case .processing: "Traitement de la photo…"
        case .succeeded: "Photo prête"
        case .failed(.notConfigured): "Retouche photo indisponible"
        case .failed(.unavailable): "Le service n'a pas répondu"
        case .failed(.quotaReached): "Limite de photos atteinte"
        case .failed(.processing): "Photo non traitée"
        }
    }
}

extension View {
    /// La pastille de détourage, installée pour toute l'app.
    ///
    /// À poser une seule fois, à la racine : elle ne se dessine pas dans cet
    /// écran-ci mais dans une fenêtre à elle, au-dessus de tout ce que l'app
    /// présente. Peu importe donc où on la pose et ce qui s'ouvre par-dessus —
    /// et il n'y a plus aucune raison de la poser ailleurs.
    func vehiclePhotoToast() -> some View {
        modifier(VehiclePhotoToastModifier())
    }
}

private struct VehiclePhotoToastModifier: ViewModifier {
    @Environment(AppServices.self) private var appServices
    @Environment(\.scenePhase) private var scenePhase
    @State private var presenter = VehiclePhotoToastPresenter()

    func body(content: Content) -> some View {
        content
            .onAppear { presenter.install(appServices) }
            // Deuxième chance : si l'écran paraît avant que sa scène soit
            // rattachée, il n'y a pas encore de fenêtre où en ajouter une.
            // L'installation ne se fait de toute façon qu'une fois.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                presenter.install(appServices)
            }
    }
}

/// La fenêtre où la pastille se dessine, et ce qui la tient en vie.
///
/// Une fenêtre à part est le seul endroit d'où l'on voit tout : dans la
/// hiérarchie de l'app, une surimpression reste sous les feuilles que celle-ci
/// présente, et SwiftUI n'a pas de « par-dessus la feuille ». Elle ne reçoit
/// aucun toucher (voir `PassthroughWindow`) et ne devient jamais la fenêtre
/// principale : l'app dessous continue de vivre comme si elle n'était pas là.
///
/// Installée à la première demande et gardée jusqu'à la fin : vide, elle ne
/// montre rien et ne coûte rien, alors que la retirer entre deux photos
/// couperait l'animation de sortie de la pastille.
final class VehiclePhotoToastPresenter {
    private var window: UIWindow?

    func install(_ appServices: AppServices) {
        guard window == nil, let scene = Self.activeScene else { return }

        let host = UIHostingController(rootView: VehiclePhotoToastLayer(appServices: appServices))
        // Sans ça, la vue du contrôleur peint un fond opaque, et c'est toute
        // l'app qui disparaît derrière.
        host.view.backgroundColor = .clear

        let window = PassthroughWindow(windowScene: scene)
        window.rootViewController = host
        window.backgroundColor = .clear
        // Juste au-dessus des fenêtres ordinaires : il en faut assez pour
        // passer devant les feuilles de l'app — qui vivent dans la sienne — et
        // rien de plus. La barre d'état et le clavier sont bien plus haut, et
        // doivent le rester.
        window.windowLevel = .normal + 1
        // `isHidden` et non `makeKeyAndVisible` : la fenêtre se montre sans
        // prendre la main. La principale reste la principale, avec son clavier
        // et son premier répondant.
        window.isHidden = false
        self.window = window
    }

    /// La scène où l'app s'affiche.
    ///
    /// Aucun filtre sur « active » : au tout premier affichage la scène est
    /// encore `foregroundInactive`, et c'est déjà là qu'il faut installer.
    /// Comme dans `TabBarMetrics`, on n'écarte que ce qui n'est pas à l'écran.
    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState != .background && $0.activationState != .unattached }
    }
}

/// Une fenêtre que le doigt traverse.
///
/// La pastille informe, elle ne sert à rien d'autre. Sans ça, sa fenêtre
/// couvrant l'écran entier, elle avalerait tous les touchers de l'app.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}

/// Ce que la fenêtre porte : la pastille en haut, et rien autour.
private struct VehiclePhotoToastLayer: View {
    let appServices: AppServices

    var body: some View {
        let state = appServices.vehiclePhotoProcessingService.state

        Color.clear
            .overlay(alignment: .top) {
                if let state {
                    VehiclePhotoToast(state: state)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.35), value: state)
            // Cette fenêtre est hors de la hiérarchie SwiftUI de l'app : rien
            // ne lui descend, pas même la langue choisie. Elle la reprend donc
            // ici, à la source, sans quoi la pastille parlerait celle du
            // système.
            .environment(\.locale, appServices.languageService.locale)
            .environment(\.localizationBundle, appServices.languageService.bundle)
    }
}

#Preview {
    VStack(spacing: 16) {
        VehiclePhotoToast(state: .processing)
        VehiclePhotoToast(state: .succeeded)
        VehiclePhotoToast(state: .failed(.quotaReached))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.blue.gradient)
}
