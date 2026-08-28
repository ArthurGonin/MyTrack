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

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                greetingHeader

                // L'ordre compte : un trajet déjà en cours garde son bouton
                // Arrêter, même sans abonnement. Celui-ci peut tomber en pleine
                // route, et il n'est pas question de laisser l'utilisateur sans
                // moyen de terminer l'enregistrement qu'il a lancé.
                if viewModel.isRecording || canRecordTrips {
                    stage
                    slideControl
                } else {
                    subscriptionRequiredView
                        .frame(maxHeight: .infinity)
                }
            }
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

    /// La bande centrale : la voiture à l'arrêt, la carte pendant un trajet.
    ///
    /// L'une prend simplement la place de l'autre. Rien ne glisse et rien ne
    /// roule : lancer un enregistrement doit afficher la carte, pas la faire
    /// entrer en scène.
    @ViewBuilder
    private var stage: some View {
        if viewModel.isRecording {
            recordingStage
        } else {
            carArtwork
        }
    }

    /// La voiture au repos, posée en bas de la bande : les roues affleurent le
    /// bouton Démarrer, et tout ce qui est au-dessus reste libre pour ce qui
    /// viendra s'y mettre.
    ///
    /// Deux images dans un même jeu, une par thème : contrairement au trait
    /// d'un dessin, une photo ne se recolore pas, donc le thème sombre a la
    /// sienne.
    private var carArtwork: some View {
        Image("HomeCar")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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

    /// Le bouton du bas, qui lance ou arrête l'enregistrement.
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
                tint: .red
            ) {
                viewModel.stopManualRecording(in: modelContext)
            }
        } else {
            SlideToConfirmButton(
                title: "Démarrer",
                systemImage: "play.fill",
                tint: .green
            ) {
                startRecording()
            }
        }
    }

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
