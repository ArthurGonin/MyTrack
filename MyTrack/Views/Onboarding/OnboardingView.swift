//
//  OnboardingView.swift
//  MyTrack
//
//  First-launch onboarding. Steps are driven by OnboardingStep so future
//  pages can be added by extending the enum and its switch below, without
//  touching the navigation/button logic.
//

import CoreLocation
import StoreKit
import SwiftData
import SwiftUI
import UIKit

/// Ce qui manque encore au suivi automatique une fois les fenêtres système
/// passées — donc ce que l'alerte de l'étape doit nommer, et où envoyer
/// l'utilisateur le réparer.
private enum MissingAutoDetectionPermission {
    case location
    case motion
    case both

    var message: LocalizedStringKey {
        switch self {
        case .location:
            "Réglez l'accès à la position sur « Toujours » dans Réglages pour activer le suivi automatique."
        case .motion:
            "Autorisez l'accès à l'activité physique dans Réglages pour activer le suivi automatique."
        case .both:
            "Réglez la position sur « Toujours » et autorisez l'activité physique dans Réglages pour activer le suivi automatique."
        }
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case name
    case units
    case vehicle
    /// Skippable: see `showsSkipButton`.
    case vehiclePhoto
    /// Skippable: see `showsSkipButton`.
    case reportProfile
    case autoDetection
    /// Skipped when auto-detection wasn't just enabled — see `isStepVisible`.
    case tripConfirmation
    case paywall
}

struct OnboardingView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    /// Pendant l'onboarding, un véhicule en base ne peut venir que d'une
    /// session abandonnée après l'étape de la photo : rien d'autre dans l'app
    /// n'en crée avant la fin. On l'adopte donc plutôt que de le doubler.
    @Query private var existingVehicles: [Vehicle]
    @State private var currentStepIndex = 0
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var vehicleDraft = VehicleDraft()
    @State private var reportProfileDraft = ReportProfileDraft()
    /// Non nil quand l'alerte est à l'écran, et porte ce qu'elle a à dire.
    @State private var missingPermission: MissingAutoDetectionPermission?
    @State private var isRequestingAutoDetectionPermissions = false
    /// L'achat unique est proposé en premier : c'est la formule que la paywall
    /// met en avant, et celle qu'on retrouve donc déjà cochée en y arrivant.
    @State private var selectedPricingPlan: PricingPlan = .lifetime
    /// Le véhicule inséré pour porter la photo, quand l'étape a servi.
    @State private var photoVehicle: Vehicle?
    /// Celui que l'appareil photo est en train de viser, ou nil quand la carte
    /// est rangée — voir `VehiclePhotoCaptureView`.
    @State private var vehicleBeingPhotographed: Vehicle?
    /// Vrai quand le déclencheur a été pressé pendant que la carte était
    /// ouverte : c'est ce qui distingue une photo prise d'une carte refermée.
    @State private var hasJustCaptured = false

    private var currentStep: OnboardingStep {
        OnboardingStep.allCases[currentStepIndex]
    }

    private var canContinue: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .name:
            return !firstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
        case .units:
            return true
        case .vehicle:
            return vehicleDraft.isValid
        case .vehiclePhoto:
            return true
        case .reportProfile:
            return reportProfileDraft.isValid
        case .autoDetection, .tripConfirmation, .paywall:
            return true
        }
    }

    /// Steps with their own action button (auto-detection's yes/no,
    /// trip-confirmation's two choices, the paywall's buy button) hide the
    /// shared bottom button instead of using it, since a single "Continuer"
    /// wouldn't fit what they need — the paywall's own button carries the same
    /// label but starts a purchase rather than turning the page.
    private var showsGenericContinueButton: Bool {
        switch currentStep {
        case .welcome, .name, .units, .vehicle, .reportProfile:
            return true
        case .vehiclePhoto, .autoDetection, .tripConfirmation, .paywall:
            return false
        }
    }

    /// Hidden (not just disabled) on the first step, and disabled while a
    /// step's own async work is in flight — going back mid permission-request
    /// or mid-purchase would leave that work racing an unrelated step.
    private var canGoBack: Bool {
        guard currentStepIndex > 0 else { return false }
        if isRequestingAutoDetectionPermissions { return false }
        if appServices.purchaseService.isPurchasing || appServices.purchaseService.isRestoring { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                OnboardingProgressBar(
                    stepCount: OnboardingStep.allCases.count,
                    currentIndex: currentStepIndex
                )

                HStack {
                    backButton
                        .opacity(currentStepIndex > 0 ? 1 : 0)
                        .disabled(!canGoBack)
                    Spacer()
                    if showsSkipButton {
                        skipButton
                    }
                }
            }

            stepContent(for: currentStep)

            if showsGenericContinueButton {
                Button {
                    advanceStep()
                } label: {
                    Text("Continuer").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                // `Color.onAccent` n'a de sens que sur le fond de l'accent :
                // désactivé, le bouton passe au gris clair et un libellé forcé
                // en blanc y devient invisible. On rend alors la main au
                // système, qui grise le texte de façon lisible.
                .foregroundStyle(canContinue ? Color.onAccent : Color.secondary)
                .glassEffect(.clear.interactive())
                .controlSize(.large)
                .disabled(!canContinue)
            }
        }
        .padding()
        .appBackground()
        // La carte se pose au bas de l'écran entier, et non dans les marges de
        // l'onboarding : ses coins du bas doivent toucher ceux du téléphone —
        // voir `VehiclePhotoCaptureView`.
        .overlay(alignment: .bottom) {
            if let vehicle = vehicleBeingPhotographed {
                VehiclePhotoCaptureView(
                    vehicle: vehicle,
                    onCapture: { hasJustCaptured = true },
                    onClose: closeCamera
                )
            }
        }
        .alert(
            "Suivi automatique inactif",
            isPresented: Binding(
                get: { missingPermission != nil },
                set: { if !$0 { missingPermission = nil } }
            ),
            presenting: missingPermission
        ) { _ in
            Button("Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: { missing in
            Text(missing.message)
        }
        // Une autorisation accordée après coup ne doit pas laisser à l'écran
        // une alerte qui dit le contraire. L'étape n'attend les fenêtres
        // système qu'un temps borné (voir
        // `DrivingDetector.waitForAuthorizationSettled`) et il y en a deux à
        // lire : qui prend son temps sur celle de « Toujours » peut répondre
        // après que l'étape a renoncé à l'attendre, et découvrir une alerte
        // posée sous la fenêtre à laquelle il vient justement de dire oui.
        // L'alerte se remet donc à jour sur la réponse tardive — et disparaît,
        // l'étape reprenant son cours, s'il ne manque plus rien.
        .onChange(of: appServices.locationService.authorizationStatus) { _, _ in
            guard missingPermission != nil else { return }
            missingPermission = missingAutoDetectionPermission
            if missingPermission == nil {
                advanceStep()
            }
        }
    }

    /// Sized to match AccountButton's glass bubble (28pt content + 6pt
    /// padding) so the two floating glass controls in the app read as the
    /// same control, not two different sizes.
    private var backButton: some View {
        Button {
            retreatStep()
        } label: {
            Image(systemName: "chevron.backward")
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
                .padding(6)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Retour")
    }

    /// La photo et les rapports se passent : les autres étapes sont soit
    /// obligatoires, soit déjà pourvues de leur propre échappatoire (« Non,
    /// peut-être plus tard » pour le suivi automatique).
    private var showsSkipButton: Bool {
        currentStep == .vehiclePhoto || currentStep == .reportProfile
    }

    /// Le verre de `backButton` et d'`AccountButton`, à la même hauteur (28pt de
    /// contenu + 6pt de marge) — en gélule plutôt qu'en cercle parce qu'il porte
    /// un mot et non un chevron.
    private var skipButton: some View {
        Button {
            // Passer les rapports, c'est ne rien créer : le brouillon repart
            // à neuf pour que `finish()` n'ait aucun drapeau à consulter.
            // Passer la photo ne demande rien — il suffit de ne pas en prendre.
            if currentStep == .reportProfile {
                reportProfileDraft = ReportProfileDraft()
            }
            advanceStep()
        } label: {
            Text("Passer")
                .font(.body.weight(.semibold))
                .frame(height: 28)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    @ViewBuilder
    private func stepContent(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            @Bindable var languageService = appServices.languageService
            WelcomeLanguageStepView(selectedLanguage: $languageService.language)
        case .name:
            NameStepView(firstName: $firstName, lastName: $lastName)
        case .units:
            @Bindable var unitSettings = appServices.unitSettingsService
            UnitStepView(distanceUnit: $unitSettings.distanceUnit)
        case .vehicle:
            VehicleStepView(draft: $vehicleDraft)
        case .vehiclePhoto:
            VehiclePhotoStepView(onTakePhoto: openCamera)
        case .reportProfile:
            ReportProfileStepView(draft: $reportProfileDraft)
        case .autoDetection:
            AutoDetectionStepView(
                isRequestingPermissions: isRequestingAutoDetectionPermissions,
                onEnable: enableAutoDetectionAndContinue,
                onSkip: { advanceStep() }
            )
        case .tripConfirmation:
            TripConfirmationStepView(
                onChooseConfirmation: {
                    appServices.drivingDetector.requiresTripConfirmation = true
                    advanceStep()
                },
                onChooseAutomatic: {
                    appServices.drivingDetector.requiresTripConfirmation = false
                    advanceStep()
                }
            )
        case .paywall:
            PaywallStepView(
                selectedPlan: $selectedPricingPlan,
                products: appServices.purchaseService.products,
                isLoadingProducts: appServices.purchaseService.isLoadingProducts,
                isPurchasing: appServices.purchaseService.isPurchasing,
                isRestoring: appServices.purchaseService.isRestoring,
                hasAttemptedProductLoad: appServices.purchaseService.hasAttemptedProductLoad,
                onPurchase: purchaseSelectedPlan,
                onRestore: restoreAndCheckSubscribed,
                onRetryLoadProducts: { await appServices.purchaseService.loadProducts() },
                onContinue: finish
            )
            // Someone who is already entitled — reinstalling, or coming from
            // another device — must not be asked to pay a second time, so the
            // paywall closes itself as soon as StoreKit confirms the
            // entitlement (which may land after the step is already on screen).
            .task(id: appServices.purchaseService.hasEntitlement) {
                if appServices.purchaseService.hasEntitlement {
                    finish()
                }
            }
        }
    }

    /// Whether `step` should actually be shown. Everything is visible except
    /// `.tripConfirmation`, which only makes sense once auto-detection is on —
    /// used by `advanceStep()`/`retreatStep()` so both directions skip over it
    /// the same way, instead of the forward path jumping past it explicitly
    /// while the back button stumbles into it.
    private func isStepVisible(_ step: OnboardingStep) -> Bool {
        switch step {
        case .tripConfirmation: appServices.drivingDetector.isEnabled
        default: true
        }
    }

    private func advanceStep() {
        var next = currentStepIndex + 1
        while next < OnboardingStep.allCases.count, !isStepVisible(OnboardingStep.allCases[next]) {
            next += 1
        }
        currentStepIndex = next
    }

    private func retreatStep() {
        var previous = currentStepIndex - 1
        while previous > 0, !isStepVisible(OnboardingStep.allCases[previous]) {
            previous -= 1
        }
        currentStepIndex = previous
    }

    private func openCamera() {
        hasJustCaptured = false
        let vehicle = vehicleForPhoto()
        withAnimation(VehiclePhotoCaptureView.motion) { vehicleBeingPhotographed = vehicle }
    }

    private func closeCamera() {
        withAnimation(VehiclePhotoCaptureView.motion) {
            vehicleBeingPhotographed = nil
            // Une photo prise tourne la page : le détourage court tout seul et
            // se raconte dans la pastille, il n'y a plus rien à attendre ici.
            // Refermer sans avoir déclenché laisse l'étape en place.
            if hasJustCaptured { advanceStep() }
        }
    }

    /// Le véhicule sur lequel la photo viendra se poser.
    ///
    /// Inséré ici et non à la fin de l'onboarding, parce que le détourage écrit
    /// sur une ligne de la base : c'est ce qui lui permet de courir pendant les
    /// étapes suivantes, et à la voiture d'être déjà là en arrivant sur
    /// l'accueil. `finish()` reprend celui-ci plutôt que d'en insérer un second.
    private func vehicleForPhoto() -> Vehicle {
        if let vehicle = photoVehicle ?? existingVehicles.first {
            // Le nom a pu changer depuis : on repasse le brouillon dessus.
            vehicleDraft.apply(to: vehicle)
            vehicle.isSelected = true
            modelContext.saveOrLog()
            photoVehicle = vehicle
            return vehicle
        }
        let vehicle = vehicleDraft.makeVehicle(isSelected: true)
        modelContext.insert(vehicle)
        modelContext.saveOrLog()
        photoVehicle = vehicle
        return vehicle
    }

    private func purchaseSelectedPlan() async -> PurchaseOutcome {
        await appServices.purchaseService.purchase(selectedPricingPlan)
    }

    private func restoreAndCheckSubscribed() async -> Bool {
        await appServices.purchaseService.restorePurchases()
        return appServices.purchaseService.hasEntitlement
    }

    /// Reste sur l'étape, boutons désactivés, tant qu'une fenêtre système
    /// attend encore une réponse — `requestActivation()` ne rend la main qu'une
    /// fois toute la chaîne retombée, plutôt que de courir devant les
    /// dialogues.
    ///
    /// Ce qui décide de la suite, ce sont les autorisations elles-mêmes et non
    /// `DrivingDetector.status` : celui-ci nomme l'abonnement avant les
    /// permissions — c'est la cause la plus actionnable une fois l'app en
    /// service — et la paywall n'est pas encore passée à cette étape. Il
    /// répondait donc `.needsSubscription` quoi que l'utilisateur vienne
    /// d'accorder ou de refuser, et l'étape avançait sans un mot sur un refus,
    /// alors qu'elle croyait le signaler.
    ///
    /// On ne bloque pas pour autant : l'alerte nomme ce qui manque et mène aux
    /// Réglages, « Non, peut-être plus tard » reste juste à côté, et la section
    /// Autorisations des réglages porte les mêmes lignes pour y revenir plus
    /// tard.
    private func enableAutoDetectionAndContinue() {
        isRequestingAutoDetectionPermissions = true
        Task {
            await appServices.drivingDetector.requestActivation()
            isRequestingAutoDetectionPermissions = false

            if let missing = missingAutoDetectionPermission {
                missingPermission = missing
            } else {
                advanceStep()
            }
        }
    }

    /// Ce qui manque au suivi automatique pour tourner vraiment, lu sur les
    /// autorisations au moment où on le demande.
    ///
    /// Nil sur un appareil sans capteur de mouvement — le simulateur, par
    /// exemple : la détection ne peut pas y fonctionner de toute façon, et il
    /// n'y a rien à y accorder. Réclamer une autorisation qui ne servirait à
    /// rien ne ferait qu'égarer.
    private var missingAutoDetectionPermission: MissingAutoDetectionPermission? {
        guard appServices.motionActivityService.isAvailable else { return nil }

        // « Pendant l'utilisation » ne suffit pas : sans « Toujours » l'app
        // n'est jamais réveillée au départ d'un trajet.
        let needsLocation = appServices.locationService.authorizationStatus != .authorizedAlways
        let needsMotion = !appServices.motionActivityService.isAuthorized

        switch (needsLocation, needsMotion) {
        case (true, true): return .both
        case (true, false): return .location
        case (false, true): return .motion
        case (false, false): return nil
        }
    }

    /// Idempotent: a successful purchase both returns `.success` and flips
    /// `hasEntitlement`, so two callers can reach this in the same run loop —
    /// without the guard that would insert the vehicle twice.
    private func finish() {
        guard !appServices.onboardingService.hasCompletedOnboarding else { return }

        let profile = appServices.userProfileService.currentProfile(in: modelContext)
        profile.firstName = firstName.trimmingCharacters(in: .whitespaces)
        profile.lastName = lastName.trimmingCharacters(in: .whitespaces)

        // Le véhicule a pu être inséré dès l'étape de la photo, pour que le
        // détourage ait une ligne où écrire pendant que l'onboarding continue.
        // On le reprend alors — son nom a pu changer depuis, en revenant en
        // arrière — plutôt que d'en créer un second.
        if let vehicle = photoVehicle ?? existingVehicles.first {
            vehicleDraft.apply(to: vehicle)
            vehicle.isSelected = true
        } else {
            modelContext.insert(vehicleDraft.makeVehicle(isSelected: true))
        }

        // Nil quand l'étape a été passée — il n'y a alors aucun profil à créer.
        let reportProfile = reportProfileDraft.makeProfile()
        if let reportProfile {
            modelContext.insert(reportProfile)
        }

        modelContext.saveOrLog()

        // Lues avant le `Task` : un `@Model` n'est pas `Sendable`, et de toute
        // façon seules ces trois valeurs y servent.
        let reportProfileID = reportProfile?.id
        let reportProfileName = reportProfile?.name
        let reportProfileDueDate = reportProfile?.nextDueDate

        // Requested here — once, at the true end of onboarding — rather than
        // tied to the auto-detection step, since more steps may still follow
        // it and notifications are also used for report-ready alerts.
        //
        // Détaché : la réponse n'a rien à décider ici, l'onboarding se termine
        // qu'elle soit oui ou non. Les réglages portent la ligne qui permettra
        // de revenir dessus.
        //
        // Le rappel du premier rapport ne peut se poser qu'après cette réponse,
        // et seulement si elle est oui. Refusée, il ne manque rien d'essentiel :
        // `RootTabView.generatePeriodicReportsIfDue()` génère le rapport au
        // lancement suivant l'échéance, notification ou pas.
        Task {
            let granted = await appServices.notificationService.requestAuthorization()
            guard granted,
                  let reportProfileID,
                  let reportProfileName,
                  let reportProfileDueDate
            else { return }
            appServices.notificationService.scheduleReportReadyNotification(
                for: reportProfileDueDate,
                profileID: reportProfileID,
                profileName: reportProfileName
            )
        }

        appServices.onboardingService.hasCompletedOnboarding = true
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return OnboardingView()
        .environment(AppServices(modelContext: container.mainContext))
}
