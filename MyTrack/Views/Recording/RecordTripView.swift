//
//  RecordTripView.swift
//  MyTrack
//

import SwiftUI
import SwiftData
import StoreKit
import CoreLocation

struct RecordTripView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query private var vehicles: [Vehicle]
    @Query private var userProfiles: [UserProfile]
    @State private var isPermissionDeniedAlertPresented = false
    @State private var isPresentingVehiclePicker = false
    /// Set when the start slider could only raise the location prompt, so the
    /// answer — whenever it comes — resumes what the user actually asked for.
    @State private var isAwaitingLocationPermission = false
    @State private var isSubscriptionStorePresented = false
    @State private var isManageSubscriptionsPresented = false

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.isSelected }
    }

    private var viewModel: RecordTripViewModel {
        RecordTripViewModel(
            tripRecorder: appServices.tripRecorder,
            locationService: appServices.locationService,
            vehicleService: appServices.vehicleService,
            drivingDetector: appServices.drivingDetector,
            purchaseService: appServices.purchaseService
        )
    }

    private var canRecordTrips: Bool { appServices.purchaseService.canRecordTrips }

    /// Où en est la scène : 0 la voiture est garée, 1 la carte est en place.
    ///
    /// Piloté par le glissement plutôt que par `isRecording`, et c'est tout
    /// l'intérêt : tant que le pouce n'est pas allé au bout, il peut revenir en
    /// arrière et la voiture recule avec lui. Le déduire de `isRecording`
    /// n'aurait donné que deux positions, et un saut entre les deux.
    @State private var stageProgress: CGFloat = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                greetingHeader

                // L'ordre compte : un trajet déjà en cours garde son bouton
                // Arrêter, même sans abonnement. Celui-ci peut tomber en pleine
                // route, et il n'est pas question de laisser l'utilisateur sans
                // moyen de terminer l'enregistrement qu'il a lancé.
                if viewModel.isRecording || canRecordTrips {
                    // La scène vit ici, en dehors du test sur `isRecording` :
                    // dedans, SwiftUI la détruirait et la reconstruirait au
                    // basculement, et la voiture comme la carte sauteraient au
                    // lieu de finir leur course. Seul le bouton change.
                    stage
                    slideControl
                } else {
                    subscriptionRequiredView
                        .frame(maxHeight: .infinity)
                }
            }
            .animation(.smooth(duration: 0.45), value: viewModel.isRecording)
            .padding()
            .appBackground()
            // Cet écran n'a pas de `navigationTitle` — le sélecteur de véhicule
            // occupe le centre de la barre. Sans titre, le mode reste
            // `.automatic`, donc « grand titre » : la barre réservait une
            // cinquantaine de points pour un titre qui n'existe pas, et tout le
            // contenu commençait d'autant plus bas. En `.inline`, cette réserve
            // disparaît et l'en-tête remonte sous la barre.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        isPresentingVehiclePicker = true
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                // `??` produirait un `String`, que SwiftUI rendrait
                                // tel quel : le texte de remplacement resterait en
                                // français. Le nom du véhicule, lui, est une donnée.
                                Group {
                                    if let name = selectedVehicle?.name {
                                        Text(name)
                                    } else {
                                        Text("Aucun véhicule")
                                    }
                                }
                                    .font(.headline)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            if let plate = selectedVehicle?.licensePlate {
                                Text(plate)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .accountToolbar()
            // The system prompt is answered long after the tap that raised it
            // returned. Watching the status here is what turns that answer back
            // into the recording the user asked for — LocationService's
            // onAuthorizationChange callback is a single slot, already held by
            // DrivingDetector.
            .onChange(of: appServices.locationService.authorizationStatus) { _, status in
                guard isAwaitingLocationPermission, status != .notDetermined else { return }
                startRecording()
            }
            .alert("Localisation refusée", isPresented: $isPermissionDeniedAlertPresented) {
                Button("Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Autorise l'accès à la position dans Réglages pour enregistrer un trajet.")
            }
            .sheet(isPresented: $isPresentingVehiclePicker) {
                VehiclePickerView(selectedVehicle: selectedVehicle) { vehicle in
                    viewModel.selectVehicle(vehicle, in: modelContext)
                }
            }
            .sheet(isPresented: $isSubscriptionStorePresented) {
                SubscriptionStoreSheet(isPresented: $isSubscriptionStorePresented)
            }
            .manageSubscriptionsSheet(isPresented: $isManageSubscriptionsPresented)
        }
    }

    /// Le prénom est une donnée saisie : il se rend tel quel, alors que le
    /// « Bon retour » au-dessus se traduit. Rien ne s'affiche tant qu'il n'y a
    /// pas de prénom — une salutation adressée à personne ne vaut pas la place
    /// qu'elle prend.
    @ViewBuilder
    private var greetingHeader: some View {
        if let firstName = accountFirstName {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bon retour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(firstName)
                        .font(.title2.bold())
                }
                Spacer()
            }
        }
    }

    private var accountFirstName: String? {
        let name = userProfiles.first?.firstName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    /// Les deux chiffres qui comptent pendant un trajet, côte à côte dans une
    /// carte, puis la carte lisant la trace en direct.
    @ViewBuilder
    /// La scène : la voiture et la carte se relaient sur la même bande, l'une
    /// sortant par la droite pendant que l'autre entre par la gauche.
    ///
    /// La voiture est dessinée par-dessus la carte, et non l'inverse : elle
    /// s'en va *devant*, la carte apparaissant dans son dos. Les deux glissent
    /// d'une largeur d'écran pleine, marges comprises, pour sortir franchement
    /// du cadre au lieu de s'arrêter au bord du contenu.
    private var stage: some View {
        GeometryReader { proxy in
            let width = proxy.size.width + Self.screenInset * 2

            // Aligné à gauche, et pas au centre : la voiture est plus large que
            // l'écran, et un ZStack centré aurait fait déborder son surplus des
            // deux côtés — l'arrière se serait fait couper autant que l'avant.
            ZStack(alignment: .leading) {
                // Montée seulement quand elle a commencé à entrer : la carte
                // fait tourner son propre suivi de position, et ça n'a pas à
                // vivre en fond d'écran d'accueil tant que rien ne bouge.
                if stageProgress > 0 {
                    recordingStage
                        // Largeur imposée : le ZStack prend celle de son plus
                        // grand enfant, ici la voiture qui déborde exprès, et
                        // sans ça la carte s'étirait jusque-là et sortait du
                        // cadre par la droite.
                        .frame(width: proxy.size.width)
                        .offset(x: -(1 - stageProgress) * width)
                }

                carArtwork(availableWidth: width)
                    .offset(x: stageProgress * width)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        // Un trajet peut aussi démarrer sans que personne n'ait touché au
        // bouton — la détection automatique s'en charge. La scène suit alors
        // l'état plutôt que le pouce.
        .onChange(of: viewModel.isRecording) { _, isRecording in
            withAnimation(.smooth(duration: 0.45)) {
                stageProgress = isRecording ? 1 : 0
            }
        }
        .onAppear { stageProgress = viewModel.isRecording ? 1 : 0 }
    }

    /// La voiture au repos : garée à gauche, l'avant déjà sorti du cadre.
    ///
    /// Elle est plus large que l'écran et alignée à gauche, si bien qu'on n'en
    /// voit que l'arrière et le flanc — assez pour la reconnaître, assez peu
    /// pour qu'elle ait l'air d'être sur le point de partir. Le décalage annule
    /// la marge de l'écran : le trait doit toucher le bord, pas s'arrêter avant.
    ///
    /// En template : le trait prend `primary`, donc noir en thème clair et blanc
    /// en thème sombre, sans qu'on ait à fournir deux images.
    private func carArtwork(availableWidth: CGFloat) -> some View {
        // Dimensions posées à la main plutôt que `scaledToFit` : le dessin
        // touche les deux bords de son image (aucune marge transparente), donc
        // `scaledToFit` le ramenait sagement dans la largeur disponible — soit
        // exactement ce qu'on ne veut pas ici, où il doit déborder.
        let carWidth = availableWidth * Self.carWidthRatio

        return Image("CarLineArt")
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(.primary)
            // Le pare-chocs arrière est à l'abscisse zéro du dessin, donc poser
            // ce cadre au bord gauche suffit à montrer l'arrière en entier : la
            // voiture est garée là, complète, et c'est son avant qui déborde.
            .frame(width: carWidth, height: carWidth / Self.carAspectRatio)
    }

    /// Ce qui remplace la voiture pendant un trajet : les compteurs et la
    /// carte, d'un seul tenant. Ils arrivent ensemble parce qu'ils sont une
    /// seule chose — l'écran de trajet en cours — et que les faire entrer l'un
    /// après l'autre ferait bouger la hauteur de la carte en pleine course.
    private var recordingStage: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                StatView("Distance") {
                    Text(formattedDistance(viewModel.currentDistanceMeters))
                }
                Divider().frame(height: 34)
                StatView("Durée") {
                    if let start = viewModel.currentStartDate {
                        Text(start, style: .timer)
                    } else {
                        Text(verbatim: "—")
                    }
                }
            }
            .appCard()

            LiveTripMapView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // La carte dessine ses propres bords : elle est rognée à la
                // forme de la carte plutôt que posée dessus.
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
        }
    }

    /// Le bouton du bas, seul élément à changer entre les deux états.
    ///
    /// Les deux pilotent la même scène en sens inverse : démarrer la pousse
    /// vers la carte, arrêter la ramène vers la voiture. D'où le `1 - progress`
    /// d'un côté, qui fait reculer la carte à mesure que le pouce avance.
    ///
    /// Un glissement et pas un appui, dans les deux sens : couper un
    /// enregistrement en cours est irréversible pour la portion de trajet qui
    /// reste, et ça ne doit pas pouvoir se faire d'un doigt posé par mégarde.
    @ViewBuilder
    private var slideControl: some View {
        if viewModel.isRecording {
            SlideToConfirmButton(
                title: "Arrêter",
                systemImage: "stop.fill",
                tint: .red,
                onProgressChange: { stageProgress = 1 - $0 }
            ) {
                viewModel.stopManualRecording(in: modelContext)
            }
        } else {
            SlideToConfirmButton(
                title: "Démarrer",
                systemImage: "play.fill",
                tint: .green,
                onProgressChange: { stageProgress = $0 }
            ) {
                startRecording()
            }
        }
    }

    /// La marge que `padding()` pose autour du contenu de l'écran. Répétée ici
    /// parce que la voiture doit précisément en sortir.
    private static let screenInset: CGFloat = 16

    /// Combien de largeurs d'écran la voiture occupe. Au-delà de 1, l'avant
    /// passe le bord droit : c'est ce dépassement qui fait qu'on n'en voit que
    /// l'arrière, et qu'elle a l'air prête à partir.
    private static let carWidthRatio: CGFloat = 1.35

    /// Les proportions du dessin, 1774 × 887.
    private static let carAspectRatio: CGFloat = 2

    /// Prend toute la place du bouton Démarrer plutôt que de s'ajouter à côté
    /// de lui : le bouton ne ferait plus rien de toute façon, et c'est cet
    /// écran-là qu'on ouvre en pensant que ses trajets sont enregistrés. C'est
    /// donc ici que le dire compte le plus.
    private var subscriptionRequiredView: some View {
        ContentUnavailableView {
            Label {
                Text(blockedTitle)
            } icon: {
                // Rouge, et pas le gris par défaut d'un écran vide : ce n'est
                // pas « il n'y a rien ici », c'est « ça ne tourne plus ».
                Image(systemName: hasBillingIssue
                    ? "creditcard.trianglebadge.exclamationmark"
                    : "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        } description: {
            Text(blockedDescription)
        } actions: {
            // Un paiement qui échoue n'est pas une résiliation : proposer une
            // nouvelle formule à quelqu'un qui n'a rien annulé ne réglerait pas
            // son problème. Ce qu'il lui faut, c'est sa carte.
            Button(blockedActionTitle) {
                if hasBillingIssue {
                    isManageSubscriptionsPresented = true
                } else {
                    isSubscriptionStorePresented = true
                }
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(Color.onAccent)
            .controlSize(.large)
        }
    }

    private var hasBillingIssue: Bool { appServices.purchaseService.hasBillingIssue }

    // Typés `LocalizedStringKey` : un ternaire entre deux littéraux passé
    // directement à `Text` peut se résoudre en `String` — donc sans traduction.
    // Le type explicite lève le doute.
    private var blockedTitle: LocalizedStringKey {
        hasBillingIssue ? "Problème de paiement" : "Abonnement inactif"
    }

    private var blockedDescription: LocalizedStringKey {
        hasBillingIssue
            ? "Ton abonnement n'a pas pu être renouvelé : tes trajets ne sont plus enregistrés. Tes trajets et rapports restent accessibles."
            : "L'enregistrement des trajets nécessite un abonnement actif. Tes trajets et rapports déjà enregistrés restent accessibles."
    }

    private var blockedActionTitle: LocalizedStringKey {
        hasBillingIssue ? "Mettre à jour le paiement" : "Se réabonner"
    }

    /// A first tap on a fresh install can only raise the location prompt and
    /// return — nothing is recorded yet. Remembering that lets the same call
    /// run again once the status settles, so granting access starts the trip
    /// instead of leaving the user in front of a button that did nothing.
    private func startRecording() {
        switch viewModel.startManualRecording(in: modelContext) {
        case .started:
            isAwaitingLocationPermission = false
        case .permissionRequested:
            isAwaitingLocationPermission = true
        case .permissionDenied:
            isAwaitingLocationPermission = false
            isPermissionDeniedAlertPresented = true
        case .subscriptionRequired:
            // L'écran a déjà remplacé le bouton par l'avertissement : il n'y a
            // rien de plus à dire, et surtout pas une alerte par-dessus.
            isAwaitingLocationPermission = false
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        TripFormatting.distance(
            meters: meters,
            unit: appServices.unitSettingsService.distanceUnit,
            locale: locale,
            fractionDigits: 2
        )
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return RecordTripView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
