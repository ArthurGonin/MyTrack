//
//  RootTabView.swift
//  MyTrack
//

import SwiftUI
import OSLog
import SwiftData

struct RootTabView: View {
    private enum RootTab: Hashable {
        case record
        case trips
        case reports
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var appServices
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allReports: [GeneratedReport]
    @State private var selectedTab: RootTab = .record
    @State private var isPendingReviewPresented = false
    @State private var isGeneratingPeriodicReports = false

    /// Drives the badge on the Rapports tab. Filtered in Swift rather than in
    /// the query so the same `allReports` fetch stays reusable, and because the
    /// number of reports is small by nature.
    private var unopenedReportCount: Int {
        allReports.filter { $0.openedAt == nil }.count
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Enregistrer", systemImage: "car.fill", value: RootTab.record) {
                RecordTripView()
            }
            Tab("Trajets", systemImage: "list.bullet", value: RootTab.trips) {
                TripListView()
            }
            Tab("Rapports", systemImage: "doc.text", value: RootTab.reports) {
                ReportsView()
            }
            .badge(unopenedReportCount)
        }
        // La pastille du détourage de photo, installée ici et nulle part
        // ailleurs : le travail survit à l'écran qui l'a lancé, et il doit
        // pouvoir se raconter n'importe où dans l'app. Elle se dessine dans
        // une fenêtre à elle, donc au-dessus même des feuilles d'où l'on
        // photographie — voir `vehiclePhotoToast()`.
        //
        // Ici et non à la racine de l'app, bien que l'onboarding photographie
        // lui aussi : c'est précisément là qu'on n'en veut pas. La pastille y
        // recouvrirait la barre de progression, et surtout elle annoncerait la
        // voiture que l'accueil doit révéler. Le détourage court quand même —
        // il ne dépend pas de cette fenêtre — et la voiture est simplement là
        // en arrivant.
        .vehiclePhotoToast()
        // Les étoiles d'iOS, quand ReviewPromptService juge le moment venu.
        // Ici et pas plus bas : le popup ne tient à aucun onglet, et posé sur
        // chacun il partirait plusieurs fois pour un seul jalon.
        .reviewPrompt()
        .onAppear {
            // A notification tapped on a cold launch is handled by the delegate
            // before this view is ever on screen, so the flags have to be
            // checked here too and not only in onChange.
            openReportsTabIfRequested()
            presentPendingReviewIfRequested()
            // Puis, notification ou pas : un trajet peut attendre une réponse
            // sans qu'on soit arrivé par elle.
            presentPendingReviewIfNeeded()
            // Deliberately a plain Task rather than .task: report generation
            // must not be cancelled by leaving the tab, or a PDF could be
            // written with no matching record ever created for it.
            Task { await generatePeriodicReportsIfDue() }
            // Une fois par lancement : les trajets d'avant le calcul du coût y
            // gagnent les chiffres de leur véhicule, et cessent donc de suivre
            // ses prix futurs (voir TripCostSnapshotService).
            appServices.tripCostSnapshotService.freezeMissingFigures(in: modelContext)
        }
        .sheet(isPresented: $isPendingReviewPresented) {
            PendingTripsReviewView()
        }
        // Handled once here, at the tab root, rather than in a per-tab
        // listener: TabView keeps every tab alive, so the same flag would
        // otherwise be consumed several times over.
        .onChange(of: appServices.notificationService.shouldOpenReportsTab) { _, _ in
            openReportsTabIfRequested()
        }
        .onChange(of: appServices.notificationService.shouldOpenPendingTripsReview) { _, _ in
            presentPendingReviewIfRequested()
        }
        // A report coming due while the app merely sits in the background used
        // to wait for the next cold launch — which on a daily-use app can be
        // weeks away. The user would tap "your report is ready", land on the
        // Rapports tab and find nothing there. Launch can reach this too, on
        // the .inactive -> .active transition, so it may run alongside the
        // onAppear call; generatePeriodicReportsIfDue guards against that.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Le retour au premier plan, et non `onAppear` : celui-ci ne se
            // rejoue pas pour une vue qui n'a jamais quitté l'écran, et une app
            // seulement endormie en arrière-plan — l'état ordinaire de
            // celle-ci, qu'iOS réveille pour enregistrer — n'en sort jamais.
            // Le trajet détecté pendant ce temps posait donc sa notification,
            // et rouvrir l'app sans y toucher ne demandait rien : il restait en
            // attente, invisible dans la liste, qui ne montre que les trajets
            // confirmés.
            presentPendingReviewIfNeeded()
            Task { await generatePeriodicReportsIfDue() }
            // Motion & Fitness can be granted from the Settings app, which
            // CoreMotion reports to nobody. Coming back is the only moment the
            // app can notice, and start watching for drives at last.
            appServices.drivingDetector.refresh()
            // Un abonnement peut aussi être changé ou résilié depuis l'App
            // Store, hors de l'app : le retour au premier plan est le seul
            // moment où elle peut s'en apercevoir.
            Task { await appServices.purchaseService.refreshEntitlement() }
        }
        // Un trajet qui se termine alors que l'app est sous les yeux. La
        // notification s'affiche bien en bannière — voir
        // `NotificationService.willPresent` — mais une bannière que personne ne
        // touche ne laisse rien derrière elle, et le retour au premier plan
        // ci-dessus n'a pas lieu puisqu'on n'est jamais parti.
        //
        // `isRecording` plutôt qu'un signal du détecteur : il retombe dans
        // `TripRecorder.finalize`, donc avant que `DrivingDetector.finalizeTrip`
        // ait décidé du statut du trajet, mais `onChange` ne se joue qu'au tour
        // de boucle suivant — quand il en a fini. Un trajet manuel, lui, naît
        // confirmé : la revue ne s'ouvre alors que s'il restait autre chose en
        // attente, ce qui est justement le moment de le demander.
        .onChange(of: appServices.tripRecorder.isRecording) { wasRecording, isRecording in
            guard wasRecording, !isRecording else { return }
            presentPendingReviewIfNeeded()
        }
    }

    /// Y a-t-il encore un trajet *terminé* qui attend une réponse ?
    ///
    /// Terminé, c'est-à-dire pourvu d'une date de fin. Un trajet automatique
    /// naît `.pendingConfirmation` et le reste pendant tout l'enregistrement
    /// (voir `Trip.init`) : sans cette condition, la revue s'ouvrait en pleine
    /// route et demandait de confirmer un trajet dont la distance grandissait
    /// encore sous les boutons.
    ///
    /// Le filtre est en Swift, comme partout ailleurs dans l'app : `#Predicate`
    /// ne sait pas comparer une propriété d'énumération à un cas, et ce n'est
    /// plus une prudence mais une mesure — voir `TripConfirmationStatus`, qui
    /// porte les deux erreurs relevées. Le fetch ramène donc toute la table, ce
    /// qui n'est pas gratuit sur une longue histoire de trajets, mais il n'a
    /// lieu qu'aux moments où l'app peut poser la question : lancement, retour
    /// au premier plan, fin d'un enregistrement, appui sur une notification. Un
    /// `fetchCount` avec prédicat, lui, jetterait — et le `try?` d'à côté
    /// rendrait `0` sans un mot : l'écran de revue ne s'ouvrirait plus jamais.
    private var hasPendingTrips: Bool {
        let descriptor = FetchDescriptor<Trip>()
        return ((try? modelContext.fetch(descriptor)) ?? [])
            .contains { $0.confirmationStatus == .pendingConfirmation && !$0.isActive }
    }

    /// Ouvre la revue s'il y a quelque chose à confirmer, et la referme s'il n'y
    /// a plus rien.
    ///
    /// Une affectation plutôt qu'une garde : remettre `true` sur une feuille
    /// déjà ouverte ne fait rien, et le `false` de l'autre branche rattrape une
    /// feuille restée ouverte sur un trajet tranché ailleurs — depuis les
    /// boutons de la notification, par exemple. Une garde
    /// `!isPendingReviewPresented`, elle, coincerait l'écran pour de bon le jour
    /// où la feuille ne s'ouvrirait pas : le drapeau resterait `true` sans rien
    /// à l'écran, et plus rien ne le remettrait à zéro.
    private func presentPendingReviewIfNeeded() {
        isPendingReviewPresented = hasPendingTrips
    }

    /// Opens the review screen after the user taps a "did you make this trip?"
    /// notification. Checked against the trips actually waiting: the tapped
    /// trip may already have been resolved from the notification's own
    /// actions, and a review screen with nothing to review only traps them.
    private func presentPendingReviewIfRequested() {
        guard appServices.notificationService.shouldOpenPendingTripsReview else { return }
        appServices.notificationService.shouldOpenPendingTripsReview = false
        presentPendingReviewIfNeeded()
    }

    /// Brings the user to the Rapports tab after they tap a "your report is
    /// ready" notification. The report they were told about is generated by
    /// `generatePeriodicReportsIfDue` on this same launch and shows up at the
    /// top of the list, unopened, as soon as it exists.
    private func openReportsTabIfRequested() {
        guard appServices.notificationService.shouldOpenReportsTab else { return }
        selectedTab = .reports
        appServices.notificationService.shouldOpenReportsTab = false
    }

    /// Bounded so that a due date corrupted into the distant past can't spin
    /// generating reports forever.
    private static let maxCatchUpReportsPerProfile = 24

    /// Checks every periodic report profile independently, generating one report per
    /// period that came due — not just one per launch, so reopening the app after a
    /// long gap doesn't take several launches to produce the reports that were missed
    /// meanwhile. A profile that fails is left alone and simply retried next launch,
    /// without affecting the others.
    private func generatePeriodicReportsIfDue() async {
        // Launch and the first foreground transition can both ask for this at
        // once. Two runs racing on the same profile would each see the period
        // as still due — nextDueDate only advances once generation finishes —
        // and produce the same report twice.
        guard !isGeneratingPeriodicReports else { return }
        isGeneratingPeriodicReports = true
        defer { isGeneratingPeriodicReports = false }

        // Générer un rapport fait partie de ce que l'abonnement paie. Sans
        // abonnement, les périodes échues sont passées plutôt que mises en
        // attente : reprendre son abonnement six mois plus tard ne doit pas
        // déverser six PDF portant sur des mois où rien n'a été enregistré.
        let canGenerate = appServices.purchaseService.canRecordTrips

        for profile in appServices.reportProfileService.allProfiles(in: modelContext) {
            var generatedCount = 0
            while generatedCount < Self.maxCatchUpReportsPerProfile,
                  let period = appServices.reportProfileService.periodDueForGeneration(profile: profile, now: .now) {
                guard canGenerate else {
                    appServices.reportProfileService.skipPeriod(
                        profile: profile, through: period.periodEnd, in: modelContext
                    )
                    // Reprogrammé ici aussi, et pas seulement après une
                    // génération réussie : l'abonnement tombé a annulé tous les
                    // rappels en attente (voir `AppServices`), et sans cette
                    // ligne le reprendre ne les ramenait jamais — l'utilisateur
                    // n'était plus prévenu qu'un rapport l'attend.
                    appServices.notificationService.scheduleReportReadyNotifications(for: profile)
                    generatedCount += 1
                    continue
                }
                guard await generateReport(for: profile, over: period) else { break }
                generatedCount += 1
            }
        }
    }

    /// Returns false when generation failed, leaving `nextDueDate` untouched on
    /// purpose so the period is retried rather than skipped.
    private func generateReport(
        for profile: ReportProfile,
        over period: (periodStart: Date, periodEnd: Date)
    ) async -> Bool {
        let periodStart = period.periodStart
        let periodEnd = period.periodEnd
        let descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.startDate >= periodStart && $0.startDate < periodEnd }
        )
        var tripsInPeriod = (try? modelContext.fetch(descriptor)) ?? []
        if !profile.vehicles.isEmpty {
            let vehicleIDs = Set(profile.vehicles.map(\.persistentModelID))
            tripsInPeriod = tripsInPeriod.filter { trip in
                guard let vehicle = trip.vehicle else { return false }
                return vehicleIDs.contains(vehicle.persistentModelID)
            }
        }
        let confirmedTrips = tripsInPeriod.filter { $0.confirmationStatus == .confirmed }
        // Trips still awaiting an answer can't be counted, but their absence
        // has to be visible: the report is a document of record, and this
        // period is never generated again once nextDueDate moves on.
        let pendingTripCount = tripsInPeriod.filter { $0.confirmationStatus == .pendingConfirmation }.count

        do {
            _ = try await appServices.reportGenerationService.generateReport(
                trips: confirmedTrips,
                periodStart: periodStart,
                periodEnd: periodEnd,
                source: .periodic,
                profileName: profile.name,
                includedVehicles: profile.vehicles,
                pendingTripCount: pendingTripCount,
                in: modelContext
            )
        } catch {
            AppLog.reports.error(
                "Periodic report failed for \(profile.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            // Dit à l'écran des rapports quoi afficher : sans ça, quelqu'un qui
            // vient d'appuyer sur « votre rapport est prêt » arrive sur une
            // liste inchangée et n'apprend jamais pourquoi.
            appServices.reportGenerationService.recordPeriodicFailure(profileName: profile.name)
            return false
        }
        appServices.reportGenerationService.clearPeriodicFailure()

        appServices.reportProfileService.advanceAfterGeneration(
            profile: profile, generatedThrough: periodEnd, in: modelContext
        )
        appServices.notificationService.scheduleReportReadyNotifications(for: profile)
        return true
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return RootTabView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
