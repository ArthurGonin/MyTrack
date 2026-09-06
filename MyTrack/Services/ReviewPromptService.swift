//
//  ReviewPromptService.swift
//  MyTrack
//
//  Décide *quand* MyTrack demande un avis sur l'App Store — jamais comment.
//  Le popup, ses cinq étoiles et son « Pas maintenant » appartiennent à iOS,
//  qui les pose lui-même et les traduit dans les six langues de l'app : rien
//  de tout cela ne se dessine ni ne passe par le catalogue de chaînes (voir
//  `ReviewPromptModifier`, qui tient l'autre bout).
//
//  Reste ce qu'Apple ne fait pas : reconnaître le moment où l'app vient de
//  tenir sa promesse, et ne le dépenser qu'une fois. Dans UserDefaults, comme
//  OnboardingService — c'est un réglage de l'app, pas une donnée de
//  l'utilisateur.
//

import Foundation
import Observation

@Observable
final class ReviewPromptService {
    /// Les moments où MyTrack vient de rendre le service pour lequel on la paie.
    ///
    /// Chacun est un écran qu'on *referme* content : la trace du trajet qu'on
    /// vient de regarder, le PDF qu'on vient de lire. Et non pas la fin de
    /// l'enregistrement, qui serait pourtant le moment le plus juste — elle
    /// arrive le téléphone dans la poche, app en arrière-plan, et un popup ne
    /// s'affiche pas là. L'appel serait parti dans le vide sans que rien ne le
    /// dise : `requestReview` ne rend aucun résultat, jamais, et il n'existe
    /// aucun moyen de savoir si les étoiles se sont affichées.
    enum Milestone: String {
        /// Le détail d'un trajet, refermé après l'avoir regardé.
        case tripReviewed
        /// Un rapport PDF, refermé après l'avoir lu.
        case reportRead
    }

    /// Le jalon atteint dont le popup n'est pas encore parti.
    ///
    /// Volontairement en mémoire seule, et jamais sur le disque : un jalon vaut
    /// pour la minute qui suit, pas pour le lancement d'après. Retrouvé trois
    /// jours plus tard, il poserait les étoiles sur un écran d'accueil qui n'a
    /// rien à voir avec ce qui les avait méritées.
    private(set) var pendingMilestone: Milestone?

    /// Combien de temps il faut être resté sur l'écran pour qu'il compte.
    ///
    /// Ouvrir un trajet et le refermer dans la seconde, c'est s'être trompé de
    /// ligne : ni carte regardée, ni plaisir pris, rien à célébrer. Cinq
    /// secondes suffisent à lire sa distance, sa durée et son coût, et écartent
    /// la fausse manœuvre.
    static let minimumDwell: TimeInterval = 5

    /// Au plus deux demandes dans toute la vie de l'app.
    ///
    /// Apple en plafonne trois par tranche de 365 jours, ne dit jamais combien
    /// il en reste, ni même si le popup s'est affiché. Deux laisse donc une
    /// marge sous son plafond, et suffit : la première tombe sur le premier
    /// moment de plaisir, la seconde rattrape ceux qui avaient fermé sans
    /// répondre.
    private static let maxRequests = 2

    /// Et jamais deux coup sur coup.
    ///
    /// Les deux jalons tiennent dans le même après-midi — enregistrer un
    /// trajet, le regarder, puis sortir un rapport ponctuel dessus. Sans ce
    /// délai, MyTrack demanderait deux fois en dix minutes, ce qu'aucune des
    /// deux limites ci-dessus n'aurait empêché.
    private static let minimumInterval: TimeInterval = 90 * 24 * 3600

    private static let requestCountKey = "reviewRequestCount"
    private static let lastRequestDateKey = "lastReviewRequestDate"

    private var requestCount: Int {
        didSet { UserDefaults.standard.set(requestCount, forKey: Self.requestCountKey) }
    }

    private var lastRequestDate: Date? {
        didSet { UserDefaults.standard.set(lastRequestDate, forKey: Self.lastRequestDateKey) }
    }

    init() {
        requestCount = UserDefaults.standard.integer(forKey: Self.requestCountKey)
        lastRequestDate = UserDefaults.standard.object(forKey: Self.lastRequestDateKey) as? Date
    }

    /// Note qu'un écran de satisfaction vient d'être refermé, et arme le popup
    /// si le moment s'y prête.
    ///
    /// Appelé au *retour* et non à l'ouverture, ce qui est tout le principe :
    /// les étoiles ne doivent jamais se poser sur la carte qu'on regarde. Elles
    /// attendent que l'écran soit refermé et que la liste soit revenue.
    ///
    /// `dwell` est le temps passé sur l'écran ; c'est lui qui distingue « il a
    /// regardé son trajet » de « il a touché la mauvaise ligne ».
    func milestoneReached(_ milestone: Milestone, dwell: TimeInterval) {
        guard pendingMilestone == nil, dwell >= Self.minimumDwell, canRequest else { return }
        pendingMilestone = milestone
    }

    /// Prend le jalon armé, s'il y en a un, et le marque dépensé — en un seul
    /// geste.
    ///
    /// Deux chemins peuvent vouloir tirer en même temps (le jalon qui s'arme,
    /// et le retour au premier plan qui le rattrape) : rendre le jalon et
    /// l'effacer séparément laissait passer deux popups d'affilée.
    func takeArmedMilestone() -> Milestone? {
        guard let milestone = pendingMilestone, canRequest else {
            pendingMilestone = nil
            return nil
        }
        pendingMilestone = nil
        requestCount += 1
        lastRequestDate = .now
        return milestone
    }

    /// Remet l'app dans l'état d'avant sa première demande, comme les autres
    /// services le font pour un compte supprimé.
    ///
    /// Sans danger : Apple plafonne de son côté, donc repartir de zéro ici ne
    /// permet pas d'insister — au pire le popup se représente une fois à
    /// quelqu'un qui a effacé son compte et continue d'utiliser l'app.
    func resetToDefaults() {
        pendingMilestone = nil
        requestCount = 0
        lastRequestDate = nil
    }

    private var canRequest: Bool {
        guard requestCount < Self.maxRequests else { return false }
        guard let lastRequestDate else { return true }
        return Date.now.timeIntervalSince(lastRequestDate) >= Self.minimumInterval
    }
}
