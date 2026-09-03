//
//  TripListView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var appServices

    // SwiftData's #Predicate macro doesn't support comparing enum-typed properties
    // directly (it can't build a key path to a plain enum case), so the confirmed-only
    // filter is applied in Swift instead of in the query.
    @Query(sort: \Trip.startDate, order: .reverse)
    private var allTrips: [Trip]

    /// L'ordre de tri choisi, gardé d'un lancement à l'autre : une liste rangée
    /// par coût ne doit pas se remettre d'elle-même dans l'ordre des dates
    /// pendant qu'on regarde ailleurs. `@AppStorage` plutôt qu'un service à
    /// part — comme la langue ou l'unité — parce que ce réglage-là ne concerne
    /// que cet écran et que personne d'autre n'a besoin de le lire.
    @AppStorage("tripSortOrder") private var sortOrder: TripSortOrder = .default

    /// Le véhicule qu'on regarde, ou nil pour tous — l'état de départ à chaque
    /// lancement. Dans la vue et non dans les réglages, contrairement à l'ordre
    /// de tri : un tri retrouvé au lancement se voit, un filtre retrouvé se
    /// confond avec des trajets disparus.
    @State private var filterVehicle: Vehicle?

    /// Ce que la feuille des véhicules vient faire quand elle s'ouvre : filtrer
    /// la liste, ou donner son véhicule aux trajets cochés.
    ///
    /// Un seul état pour les deux, et une seule feuille : deux
    /// `.sheet(isPresented:)` posés sur la même vue se marchent dessus.
    private enum VehiclePickerPurpose: Identifiable {
        case filter
        case selection

        var id: Self { self }
    }

    @State private var vehiclePicker: VehiclePickerPurpose?

    /// Le mode sélection, ouvert par le crayon.
    ///
    /// Un mode à nous plutôt que l'`EditMode` d'une `List`, pour deux raisons
    /// que le mode natif ne laissait pas régler. Ses cases à cocher se posent
    /// *à côté* de la ligne, dans la marge — or les lignes de cette app portent
    /// une carte, et la coche tombait donc sur le gris, à gauche d'elle, comme
    /// détachée de ce qu'elle cochait. Et une liste qui sait supprimer montre en
    /// édition ses boutons rouges : l'un d'eux apparaissait le temps d'une image
    /// au moment d'entrer en sélection, avant que le retrait de `onDelete` ne le
    /// chasse.
    ///
    /// La coche est donc dessinée dans la ligne, au début de la carte, avec le
    /// symbole et la couleur qui cochent déjà partout ailleurs dans l'app (voir
    /// `ReportExportView`).
    @State private var isSelecting = false

    /// Les lignes cochées.
    @State private var selection = Set<Trip.ID>()

    /// Le chemin de la pile, tenu ici parce que les lignes ne sont plus des
    /// `NavigationLink` mais des boutons (voir `row(for:)`).
    ///
    /// Tout ce qui s'ouvre depuis cette liste y passe, la corbeille comprise :
    /// un lien qui pousserait son écran de son côté marcherait sans doute, mais
    /// il serait le seul, et rien ne permettrait de le vérifier autrement qu'en
    /// y touchant.
    @State private var path = NavigationPath()

    /// Ce qui s'empile au-dessus de la liste sans être un trajet.
    private enum Destination: Hashable {
        case trash
    }

    @Query(sort: \Vehicle.name) private var vehicles: [Vehicle]

    /// Le filtre effectivement appliqué. Il retombe sur « tous » quand le
    /// véhicule filtré n'existe plus : la feuille permet de le supprimer alors
    /// qu'on filtre dessus, ce qui laisserait sinon une liste vide filtrée sur
    /// un véhicule effacé.
    private var activeVehicle: Vehicle? {
        guard let filterVehicle, vehicles.contains(where: { $0 === filterVehicle }) else {
            return nil
        }
        return filterVehicle
    }

    /// Les trajets confirmés, tous véhicules confondus : ce qui distingue une
    /// liste vide d'un filtre qui ne rend rien.
    private var confirmedTrips: [Trip] {
        allTrips.filter { $0.confirmationStatus == .confirmed }
    }

    private var trips: [Trip] {
        let filtered = activeVehicle.map { vehicle in
            confirmedTrips.filter { $0.vehicle === vehicle }
        } ?? confirmedTrips
        return viewModel.sorted(filtered, by: sortOrder)
    }

    private var deletedTripsCount: Int {
        allTrips.filter { $0.confirmationStatus == .deleted }.count
    }

    /// Les trajets cochés, dans l'ordre de la liste.
    ///
    /// Filtrés sur ce qu'elle montre, et non pris dans toute la base : changer
    /// de véhicule pendant la sélection laisserait des identifiants qui ne
    /// désignent plus rien d'affiché, et supprimer des trajets qu'on ne voit
    /// pas serait agir à l'aveugle.
    private var selectedTrips: [Trip] {
        trips.filter { selection.contains($0.id) }
    }

    /// Fusionner demande au moins deux trajets, et aucun en cours : la distance
    /// d'un trajet qui roule encore grandit, alors que le trajet fusionné fige
    /// la sienne au moment de la fusion (voir `Trip+Merge`).
    private var canMerge: Bool {
        selectedTrips.count >= 2 && selectedTrips.allSatisfy { !$0.isActive }
    }

    /// Le balayage qui envoie une ligne à la corbeille, ou rien pendant la
    /// sélection : le doigt y sert à cocher, et un balayage de trop enverrait à
    /// la corbeille un trajet qu'on voulait seulement choisir.
    private var swipeToTrash: ((IndexSet) -> Void)? {
        guard !isSelecting else { return nil }
        return { indexSet in
            for index in indexSet {
                viewModel.moveToTrash(trips[index], in: modelContext)
            }
        }
    }

    private let viewModel = TripListViewModel()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if confirmedTrips.isEmpty && deletedTripsCount == 0 {
                    ContentUnavailableView(
                        "Aucun trajet",
                        systemImage: "map",
                        description: Text("Les trajets enregistrés apparaîtront ici.")
                    )
                } else {
                    List {
                        if !trips.isEmpty {
                            Section {
                                ForEach(trips) { trip in
                                    row(for: trip)
                                        .appCardRow()
                                }
                                .onDelete(perform: swipeToTrash)
                            }
                        } else if !confirmedTrips.isEmpty {
                            // Un filtre qui ne rend rien le dit sur place plutôt
                            // que de renvoyer à l'écran vide : la corbeille et le
                            // sélecteur de véhicule doivent rester à portée.
                            Section {
                                Text("Aucun trajet pour ce véhicule")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .appCardRow()
                            }
                        }
                        // Rangée pendant la sélection : on y coche des
                        // trajets, et une ligne qui mène ailleurs n'a rien à
                        // faire au milieu de cases à cocher.
                        if !isSelecting {
                            Section {
                                Button {
                                    path.append(Destination.trash)
                                } label: {
                                    HStack(spacing: 12) {
                                        Label("Trajets supprimés", systemImage: "trash")
                                        Spacer()
                                        if deletedTripsCount > 0 {
                                            // `format:` plutôt qu'une interpolation :
                                            // le séparateur de milliers suit alors la
                                            // langue de l'app.
                                            Text(deletedTripsCount, format: .number)
                                                .foregroundStyle(.secondary)
                                        }
                                        chevron
                                    }
                                    .foregroundStyle(.primary)
                                }
                                .buttonStyle(TripRowButtonStyle())
                                .appCardRow()
                            }
                        }
                    }
                    // Les lignes portent elles-mêmes leur carte : le style de
                    // liste ne doit pas en dessiner une seconde autour d'elles.
                    .listStyle(.plain)
                    // Le tri se rejoue à chaque changement d'ordre : sans ça les
                    // lignes sautent d'un rang à l'autre sans transition.
                    .animation(.default, value: sortOrder)
                }
            }
            .appBackground()
            // Le titre reste posé bien qu'invisible — le sélecteur de véhicule
            // prend sa place au centre : c'est lui qui nomme le bouton de retour
            // des écrans poussés depuis cette liste.
            .localizedNavigationTitle("Trajets")
            // Même raison que sur l'accueil : sans `.inline`, la barre réserve
            // la hauteur d'un grand titre que le sélecteur remplace déjà.
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
            .navigationDestination(for: Destination.self) { _ in
                DeletedTripsView()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isSelecting {
                        // Ce que les trois points prendront pour cible, écrit à
                        // la place du filtre : un menu d'actions qui ne dit pas
                        // sur quoi il agit ne s'ouvre qu'à contrecœur.
                        selectionTitle
                    } else {
                        // Le même bouton que sur l'accueil, au mot près : voir
                        // `VehicleToolbarButton`. Ici il filtre au lieu de choisir.
                        VehicleToolbarButton(vehicle: activeVehicle, placeholder: "Tous les véhicules") {
                            vehiclePicker = .filter
                        }
                    }
                }
                if isSelecting {
                    ToolbarItem(placement: .primaryAction) {
                        selectionMenu
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Terminé") { withAnimation { leaveSelection() } }
                    }
                // Rien à trier ni à sélectionner tant qu'il n'y a pas de trajet :
                // les boutons n'apparaissent qu'avec la liste.
                } else if !trips.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        selectButton
                    }
                    ToolbarItem(placement: .primaryAction) {
                        sortMenu
                    }
                }
            }
            .sheet(item: $vehiclePicker) { purpose in
                switch purpose {
                case .filter:
                    VehiclePickerView(
                        selectedVehicle: activeVehicle,
                        onSelectAllVehicles: { filterVehicle = nil }
                    ) { vehicle in
                        filterVehicle = vehicle
                    }
                case .selection:
                    // Sans la ligne « Tous les véhicules » : elle voudrait dire
                    // ici « aucun véhicule », ce qui n'est pas ce qu'on vient
                    // faire — et détacher des trajets de leur voiture leur
                    // ôterait leur coût sans le dire.
                    VehiclePickerView(selectedVehicle: selectionVehicle) { vehicle in
                        assignToSelection(vehicle)
                    }
                }
            }
            .accountToolbar()
        }
    }

    /// Une ligne de la liste : elle ouvre le trajet, ou le coche pendant la
    /// sélection.
    ///
    /// Un bouton dans les deux cas, jamais un `NavigationLink` qu'on
    /// remplacerait par un bouton en entrant en sélection : changer le type de
    /// la vue fait fondre l'ancienne ligne dans la nouvelle, et le texte se
    /// voyait en double, décalé, le temps de l'animation. Un seul type dont
    /// seul le contenu change laisse au contraire la coche s'insérer et le
    /// texte glisser à sa place.
    ///
    /// La navigation passe donc par le chemin de la pile, et le chevron se
    /// dessine ici — ce qui permet de le retirer pendant la sélection, où il
    /// promettrait une navigation qui n'a plus lieu d'être.
    private func row(for trip: Trip) -> some View {
        Button {
            if isSelecting {
                toggleSelection(of: trip)
            } else {
                path.append(trip)
            }
        } label: {
            HStack(spacing: 12) {
                TripRow(
                    trip: trip,
                    distanceUnit: appServices.unitSettingsService.distanceUnit,
                    isSelected: isSelecting ? selection.contains(trip.id) : nil
                )
                if !isSelecting {
                    chevron
                }
            }
        }
        .buttonStyle(TripRowButtonStyle())
    }

    /// Le chevron que `NavigationLink` posait pour nous, à la même taille et de
    /// la même couleur, puisque les lignes n'en sont plus.
    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func toggleSelection(of trip: Trip) {
        if selection.contains(trip.id) {
            selection.remove(trip.id)
        } else {
            selection.insert(trip.id)
        }
    }

    /// Le crayon qui fait passer la liste en sélection. Comme le tri juste à
    /// côté, il tient son verre et sa forme de la barre elle-même.
    private var selectButton: some View {
        Button {
            withAnimation { isSelecting = true }
        } label: {
            Image(systemName: "pencil")
        }
        .accessibilityLabel("Sélectionner des trajets")
    }

    /// Ce qui remplace le sélecteur de véhicule pendant la sélection : le compte
    /// des trajets cochés, ou l'invitation à en cocher tant qu'il n'y en a
    /// aucun — comme le fait Mail.
    ///
    /// Court, et sans redire « trajets » : le centre de la barre est ce qui
    /// reste une fois les trois points et « Terminé » posés à droite, et un
    /// titre plus long y finissait en « 2 trajets sélection… ».
    @ViewBuilder
    private var selectionTitle: some View {
        Group {
            if selectedTrips.isEmpty {
                Text("Sélectionner")
            } else {
                Text("\(selectedTrips.count) sélectionnés")
            }
        }
        .font(.headline)
    }

    /// Les trois points, et ce qu'on peut faire des trajets cochés.
    ///
    /// Les actions restent visibles mais éteintes quand la sélection ne s'y
    /// prête pas : un menu dont les lignes apparaissent et disparaissent selon
    /// ce qui est coché n'apprend à personne ce qu'il sait faire.
    private var selectionMenu: some View {
        Menu {
            Button {
                vehiclePicker = .selection
            } label: {
                Label("Changer de véhicule", systemImage: "car")
            }
            .disabled(selectedTrips.isEmpty)
            Button {
                mergeSelection()
            } label: {
                Label("Fusionner", systemImage: "arrow.triangle.merge")
            }
            .disabled(!canMerge)
            Button(role: .destructive) {
                deleteSelection()
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .disabled(selectedTrips.isEmpty)
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Agir sur les trajets sélectionnés")
    }

    /// Envoie les trajets cochés à la corbeille, d'où ils peuvent revenir —
    /// c'est la même suppression que par balayage, prise en une fois.
    private func deleteSelection() {
        let selected = selectedTrips
        guard !selected.isEmpty else { return }
        withAnimation {
            for trip in selected {
                viewModel.moveToTrash(trip, in: modelContext)
            }
            leaveSelection()
        }
    }

    /// Le véhicule que la feuille montre coché : celui des trajets sélectionnés
    /// quand ils l'ont tous en commun, aucun sinon — en cocher un que la moitié
    /// seulement porte donnerait à croire qu'il n'y a rien à changer.
    private var selectionVehicle: Vehicle? {
        Trip.commonVehicle(of: selectedTrips)
    }

    /// Donne le même véhicule à tous les trajets cochés.
    ///
    /// Par `assignVehicle` et non par une écriture directe : c'est lui qui fige
    /// sur chaque trajet les chiffres du véhicule au moment où on le lui donne,
    /// et qui passe la consigne aux composants d'un trajet fusionné — sans quoi
    /// le trajet porterait un nom et une addition qui ne vont pas ensemble
    /// (voir `Trip+Cost`).
    private func assignToSelection(_ vehicle: Vehicle) {
        let selected = selectedTrips
        guard !selected.isEmpty else { return }
        for trip in selected {
            trip.assignVehicle(vehicle)
        }
        modelContext.saveOrLog()
        withAnimation { leaveSelection() }
    }

    /// Remplace les trajets cochés par le trajet qu'ils forment ensemble.
    private func mergeSelection() {
        let selected = selectedTrips
        guard selected.count >= 2 else { return }
        withAnimation {
            Trip.merge(selected, in: modelContext)
            leaveSelection()
        }
    }

    /// Referme la sélection. Les cases se décochent en même temps : les rouvrir
    /// sur les trajets de la fois d'avant ferait agir sur un choix qu'on ne se
    /// rappelle pas avoir fait.
    private func leaveSelection() {
        isSelecting = false
        selection.removeAll()
    }

    /// Le bouton de tri, en haut à droite. Le verre et la forme viennent de la
    /// barre elle-même — comme pour le « + » des rapports, il n'y a pas de
    /// `glassEffect` à poser à la main.
    private var sortMenu: some View {
        Menu {
            // Un `Picker` plutôt qu'une suite de boutons : c'est lui qui coche
            // l'ordre en cours, et son intitulé devient l'en-tête de la carte
            // qui s'ouvre. `inline` pour que les huit choix se posent
            // directement dans le menu, au lieu d'un sous-menu à rouvrir.
            Picker(selection: $sortOrder) {
                ForEach(TripSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            } label: {
                Text("Trier par")
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Trier les trajets")
    }
}

/// Le retour au toucher d'une ligne : elle s'estompe sous le doigt.
///
/// `.buttonStyle(.plain)` n'en donne aucun, et une ligne qui ouvre un écran
/// sans rien répondre au doigt se lit comme une ligne morte. Le style natif de
/// liste, lui, est hors d'atteinte : il teinte le fond de la ligne, que
/// `appCardRow()` pose en dehors du bouton.
private struct TripRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TripRow: View {
    let trip: Trip
    let distanceUnit: DistanceUnit

    /// Cochée, décochée, ou nil quand la liste ne sélectionne pas — la case
    /// n'existe alors pas du tout, et la ligne retrouve toute sa largeur.
    ///
    /// Dans la ligne, et non posée par la `List` : c'est ce qui la met dans la
    /// carte plutôt que sur le gris à côté (voir `TripListView.isSelecting`).
    /// Le symbole et la couleur sont ceux qui cochent déjà ailleurs dans l'app.
    var isSelected: Bool?

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.startDate, style: .date)
                    .font(.subheadline.weight(.semibold))
                vehicleName
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(trip.formattedDistance(in: distanceUnit, locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                // Le coût se pose à côté de la durée plutôt que sur une
                // troisième ligne : la ligne reste haute de deux lignes, comme
                // celles des trajets dont on ne sait pas le coût.
                HStack(spacing: 4) {
                    Text(trip.formattedDuration(locale: locale))
                    if let cost = trip.formattedEnergyCost(locale: locale) {
                        Text(verbatim: "·").accessibilityHidden(true)
                        Text(cost)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    /// Le nom d'un véhicule est une donnée saisie par l'utilisateur : il se
    /// rend tel quel, alors que le texte de remplacement, lui, se traduit.
    @ViewBuilder
    private var vehicleName: some View {
        if let name = trip.vehicle?.name {
            Text(name)
        } else {
            Text("Aucun véhicule")
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return TripListView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
