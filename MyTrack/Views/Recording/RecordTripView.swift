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

    /// Le pas franchi : 0 la voiture est garée, 1 la carte est en place, 2 la
    /// voiture est revenue se garer. Il ne redescend jamais.
    ///
    /// C'est un voyage et non un aller-retour, parce qu'une voiture n'arrive
    /// pas en marche arrière : elle sort par la droite au premier pas, et
    /// revient par la gauche au second. Compter les pas plutôt que basculer
    /// entre deux états est ce qui permet de le dire.
    @State private var journeyStep = 0

    /// Ce que le pouce a parcouru dans la transition en cours, de 0 à 1.
    ///
    /// Séparé du pas pour que le geste reste réversible : tant qu'il n'est pas
    /// allé au bout, revenir en arrière ramène la scène avec lui.
    @State private var slideProgress: CGFloat = 0

    /// La position sur le voyage, pas franchi et geste en cours réunis.
    private var journey: CGFloat { CGFloat(journeyStep) + slideProgress }

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
    /// La scène : la voiture et la carte se relaient sur la même bande.
    ///
    /// Les deux vont toujours vers la droite, jamais en arrière. La voiture
    /// s'en va par la droite pendant que la carte entre par la gauche dans son
    /// dos ; à l'arrêt, la carte poursuit sa route et sort à droite tandis que
    /// la voiture réapparaît à gauche et avance jusqu'à se regarer. Personne ne
    /// fait de marche arrière, sauf le pouce quand il revient sur ses pas.
    ///
    /// La voiture est dessinée par-dessus la carte, et non l'inverse : elle
    /// part *devant*, la carte apparaissant derrière elle.
    private var stage: some View {
        GeometryReader { proxy in
            let contentWidth = proxy.size.width
            let fullWidth = contentWidth + Self.screenInset * 2
            let carWidth = fullWidth * Self.carWidthRatio
            let mapPosition = cyclePosition(journey - 1)

            ZStack(alignment: .leading) {
                // Montée seulement quand elle est en vue : la carte fait
                // tourner son propre suivi de position, et ça n'a pas à vivre
                // en fond d'écran d'accueil tant qu'elle est hors champ.
                if abs(mapPosition) < 1 {
                    recordingStage
                        // Largeur imposée : le ZStack prend celle de son plus
                        // grand enfant, ici la voiture qui déborde exprès, et
                        // sans ça la carte s'étirait jusque-là et sortait du
                        // cadre par la droite.
                        .frame(width: contentWidth)
                        .offset(x: mapPosition * fullWidth)
                }

                carArtwork(width: carWidth)
                    .offset(x: carOffset(fullWidth: fullWidth, carWidth: carWidth))
            }
            .frame(width: contentWidth, height: proxy.size.height, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        // Un trajet peut aussi démarrer ou finir sans que personne n'ait touché
        // au bouton — la détection automatique s'en charge.
        .onChange(of: viewModel.isRecording) { _, _ in advanceJourney() }
        .onAppear { journeyStep = viewModel.isRecording ? 1 : 0 }
    }

    /// La place d'un élément sur son cycle : 0 en place, +1 sorti par la
    /// droite, -1 en attente à gauche.
    ///
    /// Le cycle fait deux pas, et c'est ce qui interdit la marche arrière : à
    /// +1 l'élément vient de sortir par la droite, et le pas suivant le reprend
    /// à -1 pour le faire entrer par la gauche. Le saut entre les deux tombe
    /// pile au moment où il est hors champ des deux façons à la fois, donc il
    /// ne se voit pas.
    private func cyclePosition(_ step: CGFloat) -> CGFloat {
        let wrapped = step.truncatingRemainder(dividingBy: 2)
        let positive = wrapped < 0 ? wrapped + 2 : wrapped
        return positive <= 1 ? positive : positive - 2
    }

    /// Le décalage de la voiture, qui n'a pas la même route à faire selon le
    /// sens où elle va.
    ///
    /// Pour sortir par la droite, une largeur d'écran suffit : elle part du
    /// bord gauche, donc au bout d'un écran il n'en reste rien. C'est aussi ce
    /// que parcourt la carte, si bien que les deux avancent du même pas — la
    /// carte suit la voiture au lieu de traîner loin derrière.
    ///
    /// Pour revenir par la gauche il lui faut sa propre largeur, presque deux
    /// écrans : plus courte, l'attente se ferait à moitié visible au bord.
    private func carOffset(fullWidth: CGFloat, carWidth: CGFloat) -> CGFloat {
        let position = cyclePosition(journey)
        return position >= 0 ? position * fullWidth : position * carWidth
    }

    /// Franchit le pas suivant.
    ///
    /// Quand le geste vient d'aboutir, ce que le pouce avait parcouru devient
    /// le pas franchi : la somme ne bouge pas d'un pixel, donc rien ne saute et
    /// il n'y a rien à animer. Quand le trajet a démarré tout seul, il n'y a
    /// aucun geste derrière et c'est l'animation qui fait le chemin.
    private func advanceJourney() {
        if slideProgress > 0 {
            journeyStep += 1
            slideProgress = 0
        } else {
            withAnimation(.smooth(duration: 0.45)) { journeyStep += 1 }
        }
    }

    /// La voiture au repos : garée à gauche, tout l'avant déjà hors du cadre.
    ///
    /// Elle est bien plus large que l'écran et posée au bord gauche, si bien
    /// qu'on n'en voit que l'arrière et le début de l'habitacle — assez pour la
    /// reconnaître, assez peu pour qu'elle ait l'air d'être déjà en partance.
    ///
    /// En template : le trait prend `primary`, donc noir en thème clair et
    /// blanc en thème sombre, sans qu'on ait à fournir deux images.
    ///
    /// Dimensions posées à la main plutôt que `scaledToFit` : le dessin touche
    /// les deux bords de son image, sans marge transparente, donc `scaledToFit`
    /// le ramenait sagement dans la largeur disponible — exactement ce qu'on ne
    /// veut pas ici, où il doit déborder.
    private func carArtwork(width: CGFloat) -> some View {
        Image("CarLineArt")
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(.primary)
            // Le pare-chocs arrière est à l'abscisse zéro du dessin, donc poser
            // ce cadre au bord gauche suffit à montrer l'arrière en entier.
            .frame(width: width, height: width / Self.carAspectRatio)
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
    /// Les deux rapportent leur geste de la même façon : c'est le voyage qui
    /// sait ce que ça veut dire, selon le pas où il en est. Démarrer et arrêter
    /// poussent donc la scène dans le même sens, ce qui est bien ce qu'on voit
    /// à l'écran — tout part toujours vers la droite.
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
                onProgressChange: { slideProgress = $0 }
            ) {
                viewModel.stopManualRecording(in: modelContext)
            }
        } else {
            SlideToConfirmButton(
                title: "Démarrer",
                systemImage: "play.fill",
                tint: .green,
                onProgressChange: { slideProgress = $0 }
            ) {
                startRecording()
            }
        }
    }

    /// La marge que `padding()` pose autour du contenu de l'écran. Répétée ici
    /// parce que la voiture doit précisément en sortir.
    private static let screenInset: CGFloat = 16

    /// Combien de largeurs d'écran la voiture occupe. C'est ce dépassement qui
    /// décide de ce qu'on en voit : à 1,9 l'écran s'arrête vers le milieu de la
    /// vitre avant, donc l'arrière et l'habitacle, rien du capot.
    private static let carWidthRatio: CGFloat = 1.9

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
