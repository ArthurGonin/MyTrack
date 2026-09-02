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
//  Elle se pose écran par écran (`.vehiclePhotoToast()`) et non une fois pour
//  toutes à la racine, parce qu'une feuille présentée par-dessus couvrirait une
//  pastille posée dessous : SwiftUI empile les présentations, et une
//  surimpression ne traverse pas une feuille. Les trois surfaces d'où l'on peut
//  lancer une photo, ou revenir après en avoir pris une, la posent donc chacune.
//

import SwiftUI

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
    /// La pastille de détourage, posée en haut de cet écran.
    ///
    /// À mettre sur le contenu *sous* la barre de navigation quand il y en a
    /// une : posée sur la pile entière, la gélule viendrait se lire par-dessus
    /// le titre.
    func vehiclePhotoToast() -> some View {
        modifier(VehiclePhotoToastModifier())
    }
}

private struct VehiclePhotoToastModifier: ViewModifier {
    @Environment(AppServices.self) private var appServices

    func body(content: Content) -> some View {
        let state = appServices.vehiclePhotoProcessingService.state
        content
            .overlay(alignment: .top) {
                if let state {
                    VehiclePhotoToast(state: state)
                        .padding(.top, 8)
                        // Elle informe, elle ne sert à rien d'autre : tout ce
                        // qui est dessous doit continuer de répondre au doigt.
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.35), value: state)
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
