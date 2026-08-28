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
    @Query private var trips: [Trip]
    @Query private var userProfiles: [UserProfile]
    @State private var isPermissionDeniedAlertPresented = false
    @State private var isPresentingVehiclePicker = false
    /// Set when the start slider could only raise the location prompt, so the
    /// answer — whenever it comes — resumes what the user actually asked for.
    @State private var isAwaitingLocationPermission = false
    @State private var isSubscriptionStorePresented = false
    @State private var isManageSubscriptionsPresented = false
    /// Vrai quand la feuille a été tirée vers le bas : la carte est
    /// rangée, les deux chiffres et le bouton restent.
    @State private var isSheetCollapsed = false
    /// La taille du grand nombre du compteur. `@ScaledMetric` plutôt
    /// qu'une constante : une taille en points ne suit pas les réglages
    /// d'accessibilité, et ce nombre-là est ce qu'on vient lire.
    @ScaledMetric(relativeTo: .largeTitle) private var odometerSize: CGFloat = 64

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
                    // Au repos, le compteur en haut et la photo derrière lui.
                    // Pendant un trajet, la feuille prend toute la place :
                    // elle s'ouvre jusque sous le « Bon retour », et il n'y a
                    // plus rien entre les deux.
                    if !viewModel.isRecording {
                        odometer
                    }
                    // Ce qui pousse la feuille en bas quand elle n'y arrive
                    // pas d'elle-même. Pas de ressort tant que la carte est
                    // là : elle est déjà élastique, et les deux se
                    // partageraient la place au lieu de la lui laisser.
                    if !viewModel.isRecording || isSheetCollapsed {
                        Spacer(minLength: 0)
                    }
                    recordingSheet
                } else {
                    subscriptionRequiredView
                        .frame(maxHeight: .infinity)
                }
            }
            // L'ouverture et la fermeture de la feuille, en un seul endroit :
            // c'est le même changement d'état qui la fait grandir depuis le
            // bouton, effacer le compteur et retourner le bouton.
            .animation(.smooth(duration: 0.42), value: viewModel.isRecording)
            .padding()
            // La photo se glisse entre le contenu et le fond de l'app : elle
            // apporte son propre décor, qui recouvre le gris sans le remplacer.
            // Elle reste là pendant un trajet, sous la feuille — c'est elle
            // qu'on voit à travers le verre, et sans elle il n'y aurait rien à
            // réfracter. Seul l'écran d'abonnement expiré s'en passe : il ne
            // parle plus que de ça.
            .background {
                if canRecordTrips {
                    carBackdrop.ignoresSafeArea()
                }
            }
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
            // Une nouvelle course s'ouvre toujours sur la carte : c'est ce
            // qu'on vient voir. Ce qu'on avait replié la fois d'avant ne la
            // suit pas.
            .onChange(of: viewModel.isRecording) { _, isRecording in
                if isRecording { isSheetCollapsed = false }
            }
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

    /// Le compteur : tout ce que la voiture a parcouru, écrit en grand
    /// au-dessus d'elle.
    ///
    /// Le nombre et son unité sont deux textes et non un seul, parce qu'ils
    /// n'ont pas la même taille — c'est le nombre qu'on lit d'un coup d'œil, le
    /// « km » n'est là que pour le qualifier.
    private var odometer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Distance totale")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(totalDistance.value)
                    .font(.system(size: odometerSize, weight: .light))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(totalDistance.symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalDistance: (value: String, symbol: String) {
        TripFormatting.distanceParts(
            meters: totalDistanceMeters,
            unit: appServices.unitSettingsService.distanceUnit,
            locale: locale
        )
    }

    /// Ce que le véhicule sélectionné a parcouru depuis toujours.
    ///
    /// Les trajets confirmés seulement : un trajet détecté que personne n'a
    /// encore validé n'en est pas encore un, et un trajet supprimé n'en est
    /// plus un. Sans véhicule sélectionné il n'y a rien à distinguer, et le
    /// compteur additionne alors tout ce qui a été parcouru.
    private var totalDistanceMeters: Double {
        trips.reduce(0) { total, trip in
            guard trip.confirmationStatus == .confirmed else { return total }
            guard selectedVehicle == nil || trip.vehicle === selectedVehicle else { return total }
            return total + trip.distanceMeters
        }
    }

    /// La photo de la voiture, peinte en fond d'écran.
    ///
    /// Le cadrage se calcule au lieu de se régler à l'œil, parce que ce qu'on
    /// place est la voiture et non l'image : la photo est bien plus grande
    /// qu'elle, et la marge autour change d'une photo à l'autre. Les deux
    /// réglages qui comptent portent donc sur la voiture — la largeur qu'elle
    /// occupe et la hauteur où ses roues se posent — et l'image s'en déduit.
    private var carBackdrop: some View {
        GeometryReader { proxy in
            let imageWidth = proxy.size.width * Self.carWidthRatio / Self.carWidthInImage
            let imageHeight = imageWidth * Self.carImageAspectRatio
            let wheels = proxy.size.height * Self.carBaseline

            // Le gris de la photo, étendu au-delà d'elle : selon la taille de
            // l'écran, le cadrage peut la laisser plus courte, et cette
            // couleur-là fait que le raccord ne se voit pas. Elle est rangée
            // dans le catalogue à côté de l'image parce qu'elle est la sienne :
            // les deux se remplacent ensemble.
            Color("HomeCarPaper")
                .overlay(alignment: .topLeading) {
                    Image("HomeCar")
                        .resizable()
                        .frame(width: imageWidth, height: imageHeight)
                        .offset(
                            x: (proxy.size.width - imageWidth) / 2,
                            y: wheels - Self.carBottomInImage * imageHeight
                        )
                }
                .clipped()
        }
    }

    /// La feuille qui s'ouvre autour du bouton le temps d'un trajet.
    ///
    /// Une feuille et non un écran : elle s'ouvre *par-dessus* l'accueil, qui
    /// reste dessous. La photo de la voiture ne s'en va pas, elle passe
    /// derrière le verre — et c'est bien elle qu'on y voit se déformer.
    ///
    /// Le bouton en fait partie et n'en bouge pas : il est le bas de la
    /// feuille, et c'est de lui qu'elle sort. Rien ne le remplace au
    /// démarrage, il change seulement de libellé, de symbole et de couleur —
    /// d'où un seul `SlideToConfirmButton` pour les deux états plutôt qu'un par
    /// état, que SwiftUI détruirait et reconstruirait au basculement. Il finit
    /// donc de se vider tranquillement pendant que la feuille s'ouvre.
    ///
    /// Le verre est celui d'Apple (`glassEffect`), et `Glass.identity` est ce
    /// qui l'éteint au repos : la même vue, sans matériau. Il n'y a donc rien
    /// à faire apparaître ni disparaître — le verre se matérialise de lui-même
    /// quand l'état change, et la feuille grandit parce que la carte pousse le
    /// haut de la pile pendant que le bouton, lui, tient le bas.
    ///
    /// Pas de `GlassEffectContainer` autour : il sert à faire fusionner les
    /// surfaces de verre proches, et la pastille du bouton en est une. Elle
    /// doit rester une lentille posée *sur* la feuille, pas se fondre dedans.
    private var recordingSheet: some View {
        VStack(spacing: 16) {
            if viewModel.isRecording {
                grabber
                liveStats
                if !isSheetCollapsed {
                    LiveTripMapView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // L'arrondi des cartes de l'app (`appCard`), et non
                        // celui, concentrique, de la feuille : la carte flotte
                        // au milieu d'elle, loin de ses coins, et `.concentric`
                        // n'a rien à quoi se raccorder là — il retombe sur des
                        // coins droits.
                        .clipShape(.rect(cornerRadius: 22, style: .continuous))
                }
            }
            slideControl
        }
        .padding(viewModel.isRecording ? Self.sheetPadding : 0)
        .glassEffect(
            viewModel.isRecording ? .regular : .identity,
            in: .rect(cornerRadius: Self.sheetCornerRadius, style: .continuous)
        )
        .gesture(collapseDrag)
        .sensoryFeedback(.impact(weight: .light), trigger: isSheetCollapsed)
    }

    /// La barre grise en haut de la feuille : elle dit que ça se prend et que
    /// ça se replie, comme sur les feuilles du système.
    ///
    /// Le trait fait 36 × 5 comme celui d'iOS, mais la zone qui l'entoure est
    /// bien plus haute : c'est elle qu'on attrape, et cinq points de haut ne
    /// s'attrapent pas. Elle répond aussi à l'appui, qui est le geste que
    /// beaucoup essaient en premier.
    private var grabber: some View {
        let label: LocalizedStringKey = isSheetCollapsed ? "Afficher la carte" : "Masquer la carte"
        return Capsule()
            .fill(.tertiary)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity, minHeight: 22)
            // Remonté dans la marge de la feuille : posée telle quelle, la
            // barre serait trop bas pour se lire comme le haut de la feuille.
            .padding(.top, -6)
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(Self.collapseAnimation) { isSheetCollapsed.toggle() }
            }
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    /// Le glissement qui range la carte et la ramène.
    ///
    /// Il se décide au relâchement plutôt que de suivre le doigt : la carte est
    /// une vue MapKit, et la redimensionner à chaque image du geste coûte cher
    /// pour ce que ça rapporte. `predictedEndTranslation` enlève ce que ça
    /// pourrait avoir de sec — un coup vif vers le bas suffit, sans avoir à
    /// faire tout le chemin.
    private var collapseDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                let travel = value.predictedEndTranslation.height
                guard abs(travel) > 40 else { return }
                withAnimation(Self.collapseAnimation) { isSheetCollapsed = travel > 0 }
            }
    }

    /// Les deux chiffres qui comptent pendant un trajet, en haut de la feuille.
    ///
    /// Posés à même le verre, sans carte sous eux : la feuille est déjà la
    /// surface, et une carte dessus ferait une surface sur une surface.
    private var liveStats: some View {
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
        .padding(.horizontal, 10)
    }

    /// Le bouton du bas, qui lance ou arrête l'enregistrement.
    ///
    /// Un glissement et pas un appui, dans les deux sens : couper un
    /// enregistrement en cours est irréversible pour la portion de trajet qui
    /// reste, et ça ne doit pas pouvoir se faire d'un doigt posé par mégarde.
    private var slideControl: some View {
        // Typé : un ternaire entre deux littéraux peut se résoudre en `String`,
        // qui ne passerait pas par la traduction.
        let title: LocalizedStringKey = viewModel.isRecording ? "Arrêter" : "Démarrer"
        return SlideToConfirmButton(
            title: title,
            systemImage: viewModel.isRecording ? "stop.fill" : "play.fill",
            tint: viewModel.isRecording ? .red : .green
        ) {
            if viewModel.isRecording {
                viewModel.stopManualRecording(in: modelContext)
            } else {
                startRecording()
            }
        }
    }

    /// Le repli et le retour de la carte. Le même que l'ouverture de la
    /// feuille, en un peu plus court : le chemin l'est aussi.
    private static let collapseAnimation: Animation = .smooth(duration: 0.35)

    /// La marge entre le bord de la feuille et ce qu'elle contient — le
    /// bouton compris, qu'elle vient donc border de dix points.
    private static let sheetPadding: CGFloat = 10

    /// L'arrondi de la feuille : celui de la gélule du bouton (34, sa
    /// demi-hauteur) plus la marge qui l'en sépare. C'est ce qui fait que le
    /// bas de la feuille épouse le bouton au lieu de le recouper.
    private static let sheetCornerRadius: CGFloat = 44

    /// Les proportions de la photo, 1024 × 1536.
    private static let carImageAspectRatio: CGFloat = 1536.0 / 1024.0

    /// La place de la voiture dans la photo, relevée dessus : elle en occupe un
    /// peu plus des trois quarts en largeur, et ses roues touchent le sol à
    /// 58 % de la hauteur. Deux nombres à reprendre en même temps que l'image.
    private static let carWidthInImage: CGFloat = 0.758
    private static let carBottomInImage: CGFloat = 0.581

    /// Combien de largeurs d'écran la voiture occupe. Au-delà de 1 les deux
    /// pare-chocs sortent du cadre, et c'est bien ce qu'on veut : une voiture
    /// qui déborde a l'air posée devant l'écran plutôt que dedans.
    private static let carWidthRatio: CGFloat = 1.4

    /// La hauteur d'écran où les roues se posent, comptée depuis le haut :
    /// juste au-dessus du bouton Démarrer.
    private static let carBaseline: CGFloat = 0.74

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
