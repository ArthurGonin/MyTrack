//
//  ReportProfileDraft.swift
//  MyTrack
//
//  Ce que l'étape d'onboarding tient pendant la configuration d'un rapport
//  périodique. Un brouillon plutôt qu'un `ReportProfile` inséré tout de suite,
//  pour la même raison que `VehicleDraft` : à cette étape rien n'est encore en
//  base — pas même le véhicule saisi juste avant — et `OnboardingView.finish()`
//  reste le seul endroit qui écrit. Passer l'étape n'a alors rien à défaire.
//
//  Les réglages, eux, éditent un profil déjà enregistré et sauvent à chaque
//  frappe (voir `ReportProfileEditView`) : c'est le même formulaire, mais la
//  question « et si l'utilisateur s'arrête là ? » n'y a pas la même réponse.
//

import Foundation

struct ReportProfileDraft {
    var name = ""
    /// Nil tant qu'aucune fréquence n'est choisie. C'est ce qui garde le bouton
    /// « Continuer » grisé, et ce qui distingue une étape passée d'une étape
    /// remplie.
    var periodicity: ReportPeriodicity?
    var customIntervalDays = Self.defaultCustomIntervalDays
    /// La date du tout premier rapport, quand la fréquence est personnalisée.
    var customFirstDueDate: Date

    /// Les fréquences proposées à l'onboarding. `.none` n'en fait pas partie :
    /// l'étape sert à configurer un rapport, et ne pas en vouloir se dit avec
    /// le bouton « Passer ».
    static let selectablePeriodicities = ReportPeriodicity.allCases.filter { $0 != .none }

    private static let defaultCustomIntervalDays = 30

    init() {
        customFirstDueDate = ReportPeriodBoundary.nextDueDate(
            after: .now,
            periodicity: .custom,
            customIntervalDays: Self.defaultCustomIntervalDays
        ) ?? .now
    }

    /// Une fréquence suffit : le nom arrive pré-rempli et le profil couvre tous
    /// les véhicules par défaut.
    var isValid: Bool { periodicity != nil }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// L'échéance du premier rapport. Pour une fréquence personnalisée c'est la
    /// date choisie, telle quelle ; pour les autres, la prochaine frontière de
    /// période — le 1er du mois, du trimestre, de l'année.
    var nextDueDate: Date? {
        guard let periodicity else { return nil }
        guard periodicity != .custom else { return customFirstDueDate }
        return ReportPeriodBoundary.nextDueDate(
            after: .now,
            periodicity: periodicity,
            customIntervalDays: customIntervalDays
        )
    }

    /// Le profil que ce brouillon décrit, prêt à être inséré — ou nil si
    /// l'étape a été passée.
    ///
    /// `vehicles` reste vide, ce qui veut dire « tous les véhicules » : à
    /// l'onboarding il n'y en a qu'un, et le filtre s'affine ensuite dans les
    /// réglages.
    func makeProfile() -> ReportProfile? {
        guard let periodicity else { return nil }
        return ReportProfile(
            name: trimmedName,
            periodicity: periodicity,
            customIntervalDays: customIntervalDays,
            nextDueDate: nextDueDate
        )
    }
}
