//
//  ReviewPromptModifier.swift
//  MyTrack
//
//  L'autre bout de `ReviewPromptService` : celui qui pose vraiment les
//  étoiles. Posé une seule fois, à la racine des onglets, parce que le popup
//  d'iOS se dessine dans sa propre fenêtre et n'appartient donc à aucun écran
//  en particulier — le poser sur chacun ferait partir plusieurs demandes pour
//  un seul jalon.
//

import SwiftUI
import OSLog
import StoreKit
import UIKit

extension View {
    /// Laisse iOS demander un avis quand `ReviewPromptService` juge le moment
    /// venu. À poser une seule fois, à la racine.
    func reviewPrompt() -> some View {
        modifier(ReviewPromptModifier())
    }
}

private struct ReviewPromptModifier: ViewModifier {
    @Environment(AppServices.self) private var appServices
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    /// Le temps qu'on laisse à l'écran de se reposer avant de poser le popup.
    ///
    /// Sans lui, les étoiles arrivent dans le même souffle que le doigt qui
    /// vient de refermer le trajet, et se lisent comme la réponse à ce geste —
    /// ce qu'Apple demande précisément d'éviter (« not appropriate for use from
    /// a button or any other user action », SKStoreReviewController.h). Une
    /// seconde et demie suffit : la transition de navigation est finie, la
    /// liste est revenue, et le popup arrive dans le calme.
    private static let settleDelay: Duration = .seconds(1.5)

    func body(content: Content) -> some View {
        content
            .onChange(of: appServices.reviewPromptService.pendingMilestone) { _, milestone in
                guard milestone != nil else { return }
                askAfterSettling()
            }
            // Le filet. Un jalon peut s'armer juste avant que l'app parte en
            // arrière-plan — le popup ne s'affiche pas là, et rien ne
            // préviendrait. Il repart donc au retour, et le jalon n'aura pas
            // été dépensé entre-temps (voir la relecture après l'attente).
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                askAfterSettling()
            }
    }

    private func askAfterSettling() {
        let service = appServices.reviewPromptService
        guard service.pendingMilestone != nil else { return }
        // Un avis se demande à quelqu'un que l'app sert encore. Sans
        // abonnement, l'écran qu'il vient de refermer était celui d'un trajet
        // qu'il ne peut plus refaire, et la dernière chose qu'il a lue est
        // qu'il faut payer : ce n'est pas le moment.
        guard appServices.purchaseService.canRecordTrips else { return }

        Task {
            try? await Task.sleep(for: Self.settleDelay)

            // Relu maintenant, et à la source plutôt que dans `scenePhase` :
            // celui-ci a été capturé par la tâche à sa création et vaudrait
            // encore `.active` alors que l'app est passée en arrière-plan
            // depuis. Une demande dépensée là partirait dans le vide — et il
            // n'en reste que deux dans toute la vie de l'app.
            guard UIApplication.shared.applicationState == .active else { return }
            guard let milestone = service.takeArmedMilestone() else { return }

            // Ce que la Console dira, et la seule trace qui existera jamais de
            // cette demande : `requestReview` ne rend rien, et personne ne peut
            // savoir si les étoiles se sont affichées ni ce qu'on y a répondu.
            AppLog.purchases.notice("Avis demandé après le jalon \(milestone.rawValue, privacy: .public).")
            requestReview()
        }
    }
}
