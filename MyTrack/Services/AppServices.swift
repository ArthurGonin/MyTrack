//
//  AppServices.swift
//  MyTrack
//
//  Composition root: holds one shared instance of each service, injected
//  into the SwiftUI environment from MyTrackApp. Built with the app's single
//  ModelContext so writes made outside the view hierarchy (e.g. by
//  TripRecorder or DrivingDetector while the app is backgrounded) are
//  visible to @Query views.
//

import Foundation
import SwiftData
import Observation

@Observable
final class AppServices {
    let vehicleService = VehicleService()
    let userProfileService = UserProfileService()
    let reportProfileService = ReportProfileService()
    let unitSettingsService = UnitSettingsService()
    let tripCostSnapshotService = TripCostSnapshotService()
    let onboardingService = OnboardingService()
    let reviewPromptService = ReviewPromptService()
    let languageService = LanguageService()
    let detectionLog = DetectionLog()
    let motionActivityService = MotionActivityService()
    let vehiclePhotoService = VehiclePhotoService()
    let feedbackService = FeedbackService()
    let locationService: LocationService
    let vehiclePhotoProcessingService: VehiclePhotoProcessingService
    let reportGenerationService: ReportGenerationService
    let notificationService: NotificationService
    let purchaseService = PurchaseService()
    let tripRecorder: TripRecorder
    let drivingDetector: DrivingDetector

    init(modelContext: ModelContext) {
        // Le journal d'abord : trois services écrivent dedans, et il se lit au
        // démarrage — y compris celui d'un processus relancé en arrière-plan,
        // qui est justement celui dont on veut garder la trace.
        locationService = LocationService(detectionLog: detectionLog)

        // Le détourage survit à l'écran qui l'a lancé, donc il vit ici : la
        // vue de l'appareil photo se ferme à l'instant du déclenchement.
        vehiclePhotoProcessingService = VehiclePhotoProcessingService(
            photoService: vehiclePhotoService, modelContext: modelContext
        )
        reportGenerationService = ReportGenerationService(
            userProfileService: userProfileService,
            unitSettingsService: unitSettingsService,
            languageService: languageService
        )
        notificationService = NotificationService(
            modelContext: modelContext,
            unitSettingsService: unitSettingsService,
            languageService: languageService
        )
        tripRecorder = TripRecorder(
            locationService: locationService, detectionLog: detectionLog, modelContext: modelContext
        )
        drivingDetector = DrivingDetector(
            motionActivityService: motionActivityService,
            tripRecorder: tripRecorder,
            vehicleService: vehicleService,
            notificationService: notificationService,
            locationService: locationService,
            detectionLog: detectionLog,
            modelContext: modelContext,
            hasRecordingAccess: purchaseService.canRecordTrips
        )

        // L'abonnement paie l'enregistrement de nouveaux trajets. Quand il
        // tombe, la détection doit s'arrêter — sinon elle continuerait de
        // consommer de la batterie en arrière-plan pour des trajets que
        // personne n'enregistre — et l'utilisateur doit l'apprendre tout de
        // suite, y compris app fermée : c'est précisément là que le silence
        // lui coûterait un trajet.
        purchaseService.onAccessChange = { [weak self] canRecordTrips, didJustLapse in
            guard let self else { return }
            drivingDetector.setRecordingAccess(canRecordTrips)
            guard didJustLapse else { return }
            notificationService.notifySubscriptionLapsed(hasBillingIssue: purchaseService.hasBillingIssue)
            // Un « ton rapport est prêt » qui arriverait maintenant serait un
            // mensonge : plus aucun rapport périodique n'est généré.
            notificationService.cancelReportReadyNotifications()
        }

        tripRecorder.cleanUpOrphanedTrips(requiresConfirmation: drivingDetector.requiresTripConfirmation)
    }

    /// Les préférences qui ne sont portées par aucun service et qu'il faut donc
    /// nommer ici. Écrites en clair plutôt que reprises d'une constante : celles
    /// des services le sont chez eux, et une clé de plus se remarque mieux dans
    /// cette liste courte que noyée dans un `dictionaryRepresentation`, qui
    /// emporterait au passage les réglages d'iOS eux-mêmes.
    private static let strayPreferenceKeys = ["tripSortOrder", "hadRecordingAccess"]

    /// Wipes every trace of the user's data — trips, vehicles, generated report
    /// PDFs, profile and report settings — and stops background monitoring, so
    /// the app comes back looking like a fresh install. `UserProfile` and
    /// `ReportSettings` aren't recreated here: their services fetch-or-create
    /// on next access, so deleting the existing rows is enough.
    ///
    /// Returns whether the deletion actually reached the store. This is a
    /// privacy promise, so a failed save must not be reported as done: the
    /// deletes would look applied for the rest of the session and everything
    /// would come back at the next launch.
    @discardableResult
    func eraseAllData(in context: ModelContext) -> Bool {
        if tripRecorder.isRecording {
            tripRecorder.discard()
        }
        drivingDetector.disable()
        drivingDetector.resetToDefaults()
        notificationService.cancelAllNotifications()
        // Le journal dit à quelle heure la détection s'est déclenchée, et donc
        // quand la personne conduisait. La promesse d'effacement l'emporte.
        detectionLog.clear()
        onboardingService.resetToDefaults()
        reviewPromptService.resetToDefaults()
        languageService.resetToSystemDefault()
        // La région de l'appareil, et non les kilomètres en dur : l'alerte
        // promet une app d'avant le premier lancement, et un premier lancement
        // aux États-Unis propose des miles.
        unitSettingsService.distanceUnit = .systemDefault
        // Les réglages qui vivent hors des services, et qu'un compte supprimé
        // laissait derrière lui : l'ordre de tri de la liste des trajets, et
        // l'accès que PurchaseService garde sur le disque pour s'armer au
        // réveil en arrière-plan.
        for key in Self.strayPreferenceKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        if let reports = try? context.fetch(FetchDescriptor<GeneratedReport>()) {
            for report in reports {
                reportGenerationService.deleteReport(report, in: context)
            }
        }
        if let trips = try? context.fetch(FetchDescriptor<Trip>()) {
            for trip in trips {
                context.delete(trip)
            }
        }
        if let vehicles = try? context.fetch(FetchDescriptor<Vehicle>()) {
            for vehicle in vehicles {
                context.delete(vehicle)
            }
        }
        if let profiles = try? context.fetch(FetchDescriptor<UserProfile>()) {
            for profile in profiles {
                context.delete(profile)
            }
        }
        if let profiles = try? context.fetch(FetchDescriptor<ReportProfile>()) {
            for profile in profiles {
                context.delete(profile)
            }
        }

        return context.saveOrLog()
    }
}
