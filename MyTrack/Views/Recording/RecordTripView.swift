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
    @Environment(\.localizationBundle) private var localizationBundle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    /// L'opacité de ce que porte la feuille, pilotée à part de son ouverture.
    /// Part de 1 pour que l'app relancée en plein trajet montre la feuille
    /// pleine tout de suite, sans rien à révéler.
    @State private var sheetContentOpacity: Double = 1
    /// Celle de la carte seule, pour son propre aller-retour quand on replie.
    @State private var mapOpacity: Double = 1
    /// La gélule de la barre d'onglets, quand on a pu la mesurer : c'est elle
    /// que le bouton Démarrer épouse au repos. `nil` tant qu'on ne l'a pas lue
    /// — ou si elle est introuvable, auquel cas le bouton garde sa pleine
    /// taille, celle qu'il avait avant.
    /// La taille du grand nombre. `@ScaledMetric` plutôt qu'une constante :
    /// une taille en points ne suit pas les réglages d'accessibilité, et ce
    /// nombre-là est ce qu'on vient lire.
    @ScaledMetric(relativeTo: .largeTitle) private var odometerSize: CGFloat = 64

    /// Celle des chiffres des tuiles. Même raison qu'au-dessus : une taille en
    /// points ne suivrait pas les réglages d'accessibilité.
    @ScaledMetric(relativeTo: .title) private var tileValueSize: CGFloat = 32

    @State private var tabBarSize: CGSize?
    /// La hauteur des trois tuiles, relevée sur elles : c'est jusque-là que la
    /// feuille repliée doit descendre pour les cacher.
    @State private var tilesHeight: CGFloat = 0
    /// La largeur que le bouton prend en trajet, relevée sur la feuille.
    @State private var fullButtonWidth: CGFloat?
    /// De combien la feuille est descendue vers la barre d'onglets : tout au
    /// repos, rien en trajet.
    ///
    /// Recopié de `isRecording` dans son propre `withAnimation` plutôt que lu
    /// directement, et pour la même raison que `displayedTitle` dans le bouton :
    /// le ressort qui ouvre la feuille dépasse sa cible de deux points avant de
    /// s'y poser, et une valeur lue directement hériterait de ce ressort-là —
    /// c'est le même changement d'état qui déclenche les deux. Ce dépassement
    /// est ce qu'on veut d'une feuille qui s'ouvre ; appliqué en plus à un
    /// déplacement de dix-huit points, il fait rebondir le libellé du bouton au
    /// moment même où il se transforme, et c'est le seul texte de l'écran :
    /// l'œil ne suit que lui. Isolé ici, ce trajet-là suit la courbe qu'on lui
    /// donne, et la feuille garde son rebond.
    @State private var sheetDrop: CGFloat = RecordTripView.restingDrop

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
                    // Une pile de calques et non une colonne : la feuille passe
                    // par-dessus le décor au lieu de lui prendre sa place. Les
                    // cases et la voiture restent donc exactement où elles
                    // étaient quand un trajet démarre — c'est elles qu'on voit
                    // se déformer à travers le verre, et sans elles il n'y
                    // aurait rien à réfracter.
                    ZStack(alignment: .bottom) {
                        VStack(spacing: Self.decorSpacing) {
                            // Ce qui reste de hauteur se met tout en haut, sous
                            // la salutation : le reste de l'écran est plein, et
                            // c'est là que l'écart se voit le moins.
                            Spacer(minLength: 0)
                            monthlyHeader
                            carIllustration
                            monthlyTiles
                            // La place que le bouton occupe au repos, gardée
                            // vide : la voiture s'arrête juste au-dessus de lui
                            // au lieu de passer dessous. Toujours celle du
                            // repos, même en trajet — le décor ne doit pas
                            // bouger d'un point pendant que la feuille s'ouvre.
                            Color.clear.frame(height: restingSheetHeight)
                        }
                        // Une marge négative et non un décalage : le bouton
                        // change vraiment de place dans la pile, il ne se
                        // contente pas de se dessiner plus bas.
                        recordingSheet
                            .padding(.bottom, -sheetDrop)
                    }
                } else {
                    subscriptionRequiredView
                        .frame(maxHeight: .infinity)
                }
            }
            // Aligné en bas : quand le ressort dépasse sa cible, la pile est
            // un instant plus haute que la place disponible, et ce qui
            // déborde doit partir par le haut. Centré — ce qu'il ferait sans
            // ça — le dépassement se partagerait entre les deux bouts et
            // pousserait le bouton vers le bas, qui est précisément ce qui ne
            // doit pas bouger.
            .frame(maxHeight: .infinity, alignment: .bottom)
            // L'ouverture et la fermeture de la feuille, en un seul endroit :
            // c'est le même changement d'état qui la fait grandir depuis le
            // bouton et qui retourne celui-ci.
            .animation(Self.sheetAnimation, value: viewModel.isRecording)
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
                    // Le même bouton que dans la liste des trajets, au mot près :
                    // voir `VehicleToolbarButton`.
                    VehicleToolbarButton(vehicle: selectedVehicle, placeholder: "Aucun véhicule") {
                        isPresentingVehiclePicker = true
                    }
                }
            }
            .accountToolbar()
            // La barre d'onglets est mesurée à l'affichage, puis relue chaque
            // fois qu'elle peut avoir changé de largeur : ses libellés sont ce
            // qui la dimensionne, et ils changent avec la langue comme avec le
            // corps de texte. Relu au tour de boucle suivant — au moment où
            // SwiftUI signale le changement, UIKit n'a pas encore remis la
            // barre en page et on lirait l'ancienne largeur.
            .onAppear {
                refreshTabBarSize()
                // L'app relancée en plein trajet s'ouvre déjà sur la feuille :
                // le bouton y est en haute position, sans avoir eu à y monter.
                sheetDrop = viewModel.isRecording ? 0 : Self.restingDrop
            }
            .onChange(of: locale) { _, _ in Task { refreshTabBarSize() } }
            .onChange(of: dynamicTypeSize) { _, _ in Task { refreshTabBarSize() } }
            // Une nouvelle course s'ouvre toujours sur la carte : c'est ce
            // qu'on vient voir. Ce qu'on avait replié la fois d'avant ne la
            // suit pas.
            .onChange(of: viewModel.isRecording) { _, isRecording in
                // Le bouton monte vers sa place de trajet, ou redescend contre
                // la barre d'onglets — dans sa propre animation, pour la raison
                // détaillée à `sheetDrop`.
                withAnimation(Self.dropAnimation) {
                    sheetDrop = isRecording ? 0 : Self.restingDrop
                }
                guard isRecording else {
                    // À l'arrêt, le contenu s'en va d'un coup et la feuille se
                    // referme sur un bouton qui n'a plus rien derrière lui.
                    sheetContentOpacity = 0
                    return
                }
                isSheetCollapsed = false
                mapOpacity = 1
                sheetContentOpacity = 0
                withAnimation(Self.contentReveal) { sheetContentOpacity = 1 }
            }
            .onChange(of: isSheetCollapsed) { _, isCollapsed in
                // Au repli, la carte quitte la pile d'un coup et la feuille se
                // referme sur les chiffres. Au retour, elle attend que la
                // place soit refaite, pour la même raison qu'à l'ouverture.
                guard !isCollapsed else { return }
                mapOpacity = 0
                withAnimation(Self.contentReveal) { mapOpacity = 1 }
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
                Text("Autorisez l'accès à la position dans Réglages pour enregistrer un trajet.")
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

    /// Le kilométrage du mois : sa période en pastille, le chiffre en grand,
    /// et l'écart avec le mois d'avant dessous.
    ///
    /// Le nombre et son unité sont deux textes et non un seul : c'est le nombre
    /// qu'on lit d'un coup d'œil, le « km » n'est là que pour le qualifier.
    private var monthlyHeader: some View {
        VStack(spacing: 6) {
            Text("Ce mois-ci")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(monthlyDistance.value)
                    .font(.system(size: odometerSize, weight: .light))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(monthlyDistance.symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            monthlyChangeLine
        }
    }

    /// « ↗ 12 % par rapport à août ».
    ///
    /// Rien du tout tant qu'il n'y a pas de mois précédent à comparer : un
    /// écart de 0 % annoncé au premier lancement serait faux, et un « +100 % »
    /// contre un mois vide ne voudrait rien dire.
    ///
    /// La flèche porte le sens, le nombre reste en valeur absolue. Le vert ne
    /// salue que la hausse : rouler moins n'est pas une faute, et le rouge de
    /// l'app est réservé à ce qui ne tourne plus.
    @ViewBuilder
    private var monthlyChangeLine: some View {
        if let change = monthlyChange {
            let isUp = change.ratio >= 0
            HStack(spacing: 5) {
                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(isUp ? Color.green : Color.secondary)
                Text(
                    String(
                        localized: "\(formattedPercent(change.ratio)) par rapport à \(change.month)",
                        bundle: localizationBundle,
                        locale: locale
                    )
                )
                .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
    }

    /// Les trois tuiles du mois, sous la voiture. En verre : elles se posent
    /// sur le dégradé mais aussi, en trajet, sous la feuille — c'est la même
    /// matière que le bouton qu'elles bordent.
    ///
    /// La rangée est rentrée de quelques points par rapport à la marge de
    /// l'écran : les tuiles s'affinent, et la voiture au-dessus, qui déborde,
    /// n'en paraît que plus large.
    private var monthlyTiles: some View {
        HStack(spacing: Self.tileSpacing) {
            tile("road.lanes", label: "trajets") {
                tileValue(monthlyTrips.count.formatted(.number.locale(locale)))
            }
            tile("clock", label: "temps de conduite") {
                tileValue(monthlyDrivingTime)
            }
            tile("point.topleft.down.curvedto.point.bottomright.up", label: "distance moyenne") {
                if let average = monthlyAverageDistance {
                    tileValue(average.value, unit: average.symbol)
                } else {
                    tileValue(Self.noValue)
                }
            }
        }
        .padding(.horizontal, Self.tileRowInset)
        // Relevée plutôt que calculée : la hauteur d'une tuile dépend des
        // polices du système, qui changent avec les réglages d'accessibilité.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tilesHeight = $0 }
    }

    /// Une tuile : son symbole dans une pastille ronde, le chiffre, son
    /// intitulé. Les trois font la même largeur — la rangée du bas doit rester
    /// régulière quelle que soit la longueur des nombres.
    private func tile<Value: View>(
        _ symbolName: String,
        label: LocalizedStringKey,
        @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(spacing: Self.tileContentSpacing) {
            Image(systemName: symbolName)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: Self.tileSymbolDiameter, height: Self.tileSymbolDiameter)
                .background(Color(uiColor: .tertiarySystemFill), in: .circle)
                .accessibilityHidden(true)
            value()
            // Une seule ligne, et petit : c'est le chiffre qu'on vient lire,
            // l'intitulé ne fait que le nommer. « temps de conduite » est le
            // plus long des trois et c'est lui qui fixe la taille — les deux
            // autres la suivent pour que les trois se lisent pareil.
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Self.tileVerticalPadding)
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.tileCornerRadius, style: .continuous))
    }

    /// Le chiffre d'une tuile : grand, et son unité posée plus petite à côté —
    /// la même partition que le grand compteur au-dessus de la voiture. C'est
    /// ce qui permet au nombre de rester lisible dans une tuile étroite : lui
    /// seul occupe la place, l'unité ne la lui prend pas.
    private func tileValue(_ value: String, unit: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(size: tileValueSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit {
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }

    /// Les trajets d'un mois donné, pour le véhicule choisi.
    ///
    /// Les trajets confirmés seulement : un trajet détecté que personne n'a
    /// encore validé n'en est pas encore un, et un trajet supprimé n'en est
    /// plus un. Sans véhicule sélectionné il n'y a rien à distinguer, et le
    /// compte additionne alors tout ce qui a roulé.
    private func confirmedTrips(inMonthContaining date: Date) -> [Trip] {
        guard let month = Calendar.current.dateInterval(of: .month, for: date) else { return [] }
        return trips.filter { trip in
            trip.confirmationStatus == .confirmed
                && (selectedVehicle == nil || trip.vehicle === selectedVehicle)
                && month.contains(trip.startDate)
        }
    }

    private var monthlyTrips: [Trip] { confirmedTrips(inMonthContaining: Date()) }

    private var monthlyDistanceMeters: Double {
        monthlyTrips.reduce(0) { $0 + $1.distanceMeters }
    }

    private var monthlyDistance: (value: String, symbol: String) {
        TripFormatting.distanceParts(
            meters: monthlyDistanceMeters,
            unit: appServices.unitSettingsService.distanceUnit,
            locale: locale
        )
    }

    /// Le temps passé au volant ce mois-ci. Un trajet en cours compte jusqu'à
    /// maintenant, comme partout ailleurs dans l'app.
    private var monthlyDrivingTime: String {
        let now = Date()
        let total = monthlyTrips.reduce(0.0) { total, trip in
            total + (trip.endDate ?? now).timeIntervalSince(trip.startDate)
        }
        return TripFormatting.clockDuration(total, locale: locale)
    }

    /// La longueur du trajet moyen. Nil sans trajet : une moyenne sur rien
    /// n'existe pas, et zéro se lirait comme des trajets de zéro kilomètre.
    private var monthlyAverageDistance: (value: String, symbol: String)? {
        guard !monthlyTrips.isEmpty else { return nil }
        return TripFormatting.distanceParts(
            meters: monthlyDistanceMeters / Double(monthlyTrips.count),
            unit: appServices.unitSettingsService.distanceUnit,
            locale: locale,
            fractionDigits: 1
        )
    }

    /// L'écart avec le mois d'avant, et le nom de ce mois-là.
    ///
    /// Nil quand il n'y a rien à comparer : sans kilomètre le mois précédent,
    /// toute proportion serait une division par zéro.
    private var monthlyChange: (ratio: Double, month: String)? {
        guard let lastMonthDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())
        else { return nil }
        let reference = confirmedTrips(inMonthContaining: lastMonthDate)
            .reduce(0) { $0 + $1.distanceMeters }
        guard reference > 0 else { return nil }
        return (
            (monthlyDistanceMeters - reference) / reference,
            lastMonthDate.formatted(.dateTime.month(.wide).locale(locale))
        )
    }

    /// « 12 % » : la valeur absolue, la flèche disant déjà le sens. Le
    /// formateur de Foundation place l'espace avant le signe là où la langue
    /// le demande — « 12 % » en français, « 12% » en anglais.
    private func formattedPercent(_ ratio: Double) -> String {
        abs(ratio).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// La voiture du véhicule choisi si elle a été photographiée, le dessin
    /// sinon. Les deux sortent du même normalisateur, donc du même cadre : le
    /// bloc garde sa hauteur et rien ne saute en changeant de véhicule.
    private var carImage: Image {
        if let data = selectedVehicle?.photoData, let photo = UIImage(data: data) {
            return Image(uiImage: photo)
        }
        return Image("HomeCar")
    }

    /// La voiture, en dessin plutôt qu'en photo de fond : elle est un objet de
    /// l'écran, posée entre les cases et le bouton, et non un décor derrière
    /// tout le reste. Le PNG est détouré, donc c'est le dégradé de l'app qu'on
    /// voit autour d'elle.
    ///
    /// Elle déborde des marges de l'écran de quelques points : une voiture
    /// coupée par le bord a l'air posée devant l'écran plutôt que dedans.
    private var carIllustration: some View {
        carImage
            .resizable()
            .scaledToFit()
            // Une largeur, pas de hauteur : la voiture prend celle que ses
            // proportions lui donnent, et rien de plus. Lui laisser la hauteur
            // disponible lui ferait garder le vide pour elle, alors que c'est
            // aux cases de le remplir. `scaledToFit` la fait quand même
            // rapetisser sur un écran trop court, au lieu de déborder.
            .frame(maxWidth: .infinity)
            .padding(.horizontal, -Self.carBleed)
            // Servie avant les cases : elle prend la hauteur que sa largeur lui
            // donne, et c'est ce qu'elle laisse qui revient à la grille.
            .layoutPriority(1)
            .accessibilityHidden(true)
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
                VStack(spacing: 16) {
                    grabber
                    // Repliée, la feuille est bien plus haute que ses deux
                    // chiffres : ces ressorts les posent au milieu du verre
                    // plutôt que collés sous la poignée.
                    if isSheetCollapsed {
                        Spacer(minLength: 0)
                    }
                    liveStats
                    if isSheetCollapsed {
                        Spacer(minLength: 0)
                    }
                    if !isSheetCollapsed {
                        LiveTripMapView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(mapOpacity)
                            // L'arrondi des cartes de l'app (`appCard`), et non
                            // celui, concentrique, de la feuille : la carte
                            // flotte au milieu d'elle, loin de ses coins, et
                            // `.concentric` n'a rien à quoi se raccorder là —
                            // il retombe sur des coins droits.
                            .clipShape(.rect(cornerRadius: 22, style: .continuous))
                    }
                }
                .opacity(sheetContentOpacity)
                // Aucune transition : c'est l'opacité au-dessus qui fait
                // entrer et sortir ce contenu. Une transition ferait la même
                // chose, mais son animation à elle déteint sur ce qui l'entoure
                // — le libellé du bouton se met à rejoindre sa place en
                // glissant, et on le voit passer au-dessus de la gélule.
                .transition(.identity)
            }
            slideControl
                // Servi en premier : le temps que la feuille s'ouvre, elle est
                // plus courte que ce qu'elle contient, et une pile trop serrée
                // rogne ses éléments et les déplace. Le bouton, lui, garde sa
                // taille et sa place quoi qu'il arrive au-dessus de lui.
                .layoutPriority(1)
        }
        // Repliée, elle descend jusqu'à couvrir les trois tuiles — voir
        // `collapsedSheetContentHeight`. Une hauteur ferme et non un minimum :
        // les ressorts qui centrent les chiffres prendraient sinon toute la
        // hauteur proposée, et la feuille couvrirait la voiture avec.
        .frame(height: collapsedSheetContentHeight)
        // La feuille garde toute la largeur dans les deux états. Au repos elle
        // est invisible — verre éteint, fond transparent — et c'est le bouton
        // seul qui rétrécit ; sans ça, elle se refermerait sur lui et la carte
        // n'aurait plus de largeur d'où s'ouvrir.
        .frame(maxWidth: .infinity)
        // Ce que le bouton mesure quand rien ne le contraint. Le relever plutôt
        // que le recalculer, c'est ce qui permet de donner au bouton une
        // largeur chiffrée dans les deux états : entre deux nombres l'ouverture
        // s'interpole, alors qu'un passage à « prends toute la place » se ferait
        // d'un coup.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullButtonWidth = $0 }
        // La marge est là dans les deux états, y compris quand la feuille est
        // éteinte et qu'on ne voit que le bouton. C'est ce qui fait qu'il ne
        // bouge pas d'un point à l'ouverture, et ce qui laisse à sa pastille
        // la place de grossir sous le doigt sans que le rognage la coupe.
        .padding(Self.sheetPadding)
        // Rogné à la forme de la feuille : le temps qu'elle grandisse, elle est
        // plus courte que ce qu'elle contient, et une pile trop serrée laisse
        // ses éléments se chevaucher et sortir. Sans ça, les chiffres et la
        // carte se voient un instant flotter sur la photo.
        .clipShape(.rect(cornerRadius: sheetCornerRadius, style: .continuous))
        .glassEffect(
            viewModel.isRecording ? .regular : .identity,
            in: .rect(cornerRadius: sheetCornerRadius, style: .continuous)
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
    ///
    /// Au repos, il a très exactement la taille de la barre d'onglets sous lui
    /// — deux gélules l'une au-dessus de l'autre, du même gabarit, plutôt
    /// qu'une grosse barre verte posée sur une petite. Il ne reprend sa pleine
    /// taille qu'une fois lancé, quand la feuille s'ouvre autour de lui.
    private var slideControl: some View {
        // Typé : un ternaire entre deux littéraux peut se résoudre en `String`,
        // qui ne passerait pas par la traduction.
        let title: LocalizedStringKey = viewModel.isRecording ? "Arrêter" : "Démarrer"
        return SlideToConfirmButton(
            title: title,
            systemImage: viewModel.isRecording ? "stop.fill" : "play.fill",
            // Du verre au repos, comme la barre d'onglets qu'il surplombe :
            // démarrer un trajet est le geste ordinaire de cet écran, il n'a
            // pas à s'annoncer par une couleur. Arrêter, si — c'est le geste
            // qu'on cherche des yeux, et le seul qui soit irréversible.
            style: viewModel.isRecording ? .tinted(.red) : .glass,
            height: buttonHeight
        ) {
            if viewModel.isRecording {
                viewModel.stopManualRecording(in: modelContext)
            } else {
                startRecording()
            }
        }
        .frame(width: buttonWidth)
    }

    private var buttonHeight: CGFloat {
        guard !viewModel.isRecording, let tabBarSize else { return SlideToConfirmButton.fullHeight }
        return tabBarSize.height
    }

    /// La hauteur que la feuille prend quand la carte est rangée.
    ///
    /// Assez pour cacher les trois tuiles, pas assez pour mordre sur la
    /// voiture : la place du bouton, l'écart qui la sépare des tuiles, les
    /// tuiles elles-mêmes, et six points pour finir dans le vide qui les
    /// surmonte. Les marges de la feuille sont retranchées parce que la mesure
    /// porte sur son contenu, avant qu'elles ne s'ajoutent autour.
    ///
    /// Nil hors de ce cas : la feuille ouverte prend toute la hauteur, et au
    /// repos elle se réduit au bouton.
    private var collapsedSheetContentHeight: CGFloat? {
        guard viewModel.isRecording, isSheetCollapsed, tilesHeight > 0 else { return nil }
        return restingSheetHeight + Self.decorSpacing + tilesHeight
            + Self.tileCoverMargin - 2 * Self.sheetPadding
    }

    /// Ce que la feuille occupe au repos, une fois descendue contre la barre
    /// d'onglets : la hauteur du bouton, ses deux marges, moins ce qu'elle
    /// descend. Lue sur la barre d'onglets comme le bouton lui-même, et jamais
    /// sur l'état en cours — c'est la place à garder sous la voiture, et elle
    /// ne doit pas changer parce qu'un trajet a démarré.
    private var restingSheetHeight: CGFloat {
        (tabBarSize?.height ?? SlideToConfirmButton.fullHeight)
            + 2 * Self.sheetPadding - Self.restingDrop
    }

    /// `nil` seulement à la toute première image, avant que la feuille ait été
    /// mesurée : le bouton prend alors la largeur qu'on lui propose, qui est
    /// celle qu'il aura de toute façon en trajet.
    private var buttonWidth: CGFloat? {
        guard !viewModel.isRecording, let tabBarSize else { return fullButtonWidth }
        return tabBarSize.width
    }

    /// Relit la gélule de la barre d'onglets et la garde si la lecture échoue :
    /// un `nil` passager renverrait le bouton en pleine largeur le temps d'une
    /// image, ce qui se verrait bien plus qu'une mesure d'un point périmée.
    private func refreshTabBarSize() {
        tabBarSize = TabBarMetrics.floatingBarSize ?? tabBarSize
    }

    /// L'ouverture et la fermeture de la feuille.
    ///
    /// `bouncy` plutôt que `smooth` : un ressort qui dépasse un peu sa cible
    /// avant de s'y poser, comme les feuilles du système. Sans ce dépassement,
    /// le verre arrive à sa place et s'arrête net — ça se voit.
    ///
    /// Le rebond reste petit, et ça n'est pas qu'une affaire de goût : la
    /// feuille ouverte occupe déjà toute la hauteur disponible, donc tout ce
    /// qu'elle dépasse en plus déborde de l'écran et pousse ce qui l'entoure.
    /// Quelques points suffisent à faire ressort ; dix fois plus ferait sauter
    /// la salutation au-dessus.
    private static let sheetAnimation: Animation = .bouncy(duration: 0.5, extraBounce: 0.03)

    /// Le repli et le retour de la carte. Le même ressort en plus court : le
    /// chemin l'est aussi.
    private static let collapseAnimation: Animation = .bouncy(duration: 0.4, extraBounce: 0.03)

    /// La descente du bouton vers la barre d'onglets, et sa remontée. Le
    /// ressort de la feuille sans son rebond — `smooth` est exactement ça — et
    /// la même durée, pour que les deux se posent ensemble.
    private static let dropAnimation: Animation = .smooth(duration: 0.5)

    /// L'arrivée du contenu dans la feuille, en retard sur elle.
    ///
    /// Il ne se montre qu'une fois la place faite : pendant que la feuille
    /// s'ouvre, elle est plus courte que ce qu'elle porte, la pile se tasse et
    /// MapKit recadre pour suivre — on verrait la moitié de la France défiler
    /// en un quart de seconde. Le retard couvre exactement ce moment-là.
    private static let contentReveal: Animation = .easeOut(duration: 0.2).delay(0.22)

    /// La marge entre le bord de la feuille et ce qu'elle contient — le
    /// bouton compris, qu'elle borde donc de dix points, y compris au repos où
    /// elle est le seul écart entre lui et le bord d'une feuille invisible.
    private static let sheetPadding: CGFloat = 10

    /// De combien le bouton descend au repos, pour se ranger contre la barre
    /// d'onglets au lieu de flotter au-dessus d'elle.
    ///
    /// La cible n'est pas ce nombre, c'est l'écart qu'il laisse : 8 points,
    /// celui que le système met lui-même entre la barre et une
    /// `tabViewBottomAccessory` — la gélule flottante qu'il sait poser
    /// au-dessus d'elle. Relevé sur cet accessoire plutôt que choisi à l'œil.
    /// Au repos le bouton en est à 26 (la marge de l'écran, 16, plus celle de
    /// la feuille, 10), d'où ces 18.
    private static let restingDrop: CGFloat = 18

    /// L'arrondi de la feuille : celui de la gélule du bouton (sa demi-hauteur)
    /// plus la marge qui l'en sépare. C'est ce qui fait que le bas de la
    /// feuille épouse le bouton au lieu de le recouper — et comme le bouton
    /// n'a pas la même hauteur au repos qu'en trajet, l'arrondi le suit.
    private var sheetCornerRadius: CGFloat { buttonHeight / 2 + Self.sheetPadding }

    /// La marge de l'écran, celle que `padding()` pose. Reprise ici en négatif
    /// par l'arc, qui doit toucher les deux bords.
    private static let pageMargin: CGFloat = 16

    /// L'écart entre les trois tuiles, ce dont la rangée se retire des marges
    /// de l'écran, et l'arrondi de leurs coins.
    private static let tileSpacing: CGFloat = 12
    /// La rangée ne se retire presque plus des marges : l'intitulé tient sur
    /// une ligne, et chaque point de largeur gagné est un point qu'il n'a pas
    /// à rapetisser.
    private static let tileRowInset: CGFloat = 6
    private static let tileCornerRadius: CGFloat = 22

    /// Ce qui donne aux tuiles leur hauteur : le symbole, le chiffre, les deux
    /// lignes de l'intitulé, et ces trois écarts-là. Resserré autant que le
    /// texte le permet — la tuile ne doit pas prendre la moitié de la place que
    /// la voiture laisse.
    private static let tileVerticalPadding: CGFloat = 12
    private static let tileContentSpacing: CGFloat = 6
    private static let tileSymbolDiameter: CGFloat = 30

    /// Ce que la feuille repliée dépasse le haut des tuiles : juste de quoi ne
    /// pas laisser un liseré dépasser, et pas de quoi atteindre les roues.
    private static let tileCoverMargin: CGFloat = 6

    /// Ce qui sépare les trois étages du décor : le chiffre, la voiture, les
    /// tuiles. Serré : les trois doivent tenir entre la salutation et le
    /// bouton, y compris sur un petit écran.
    private static let decorSpacing: CGFloat = 14

    /// Ce qui s'écrit à la place d'un chiffre qu'on ne peut pas calculer. Un
    /// tiret et non un zéro : « rien de connu » n'est pas « rien parcouru ».
    private static let noValue = "—"

    /// Ce que la voiture déborde de chaque côté, au-delà de la marge de
    /// l'écran.
    ///
    /// Le PNG porte sa lueur avec lui, et la carrosserie n'en occupe que 85 %
    /// de la largeur : ce débord-là est celui de la lueur, qui sort du cadre
    /// pendant que la voiture, elle, va d'un bord à l'autre de l'écran.
    private static let carBleed: CGFloat = 28


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
            ? "Votre abonnement n'a pas pu être renouvelé : vos trajets ne sont plus enregistrés. Vos trajets et rapports restent accessibles."
            : "L'enregistrement des trajets nécessite un abonnement actif. Vos trajets et rapports déjà enregistrés restent accessibles."
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
