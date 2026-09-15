//
//  PendingTripsReviewView.swift
//  MyTrack
//
//  « Avez-vous fait ce trajet ? », posé dans l'app plutôt que dans une
//  notification : au lancement, à chaque retour au premier plan, à la fin d'un
//  enregistrement, et sur l'appui d'une notification qu'on n'a pas voulu
//  trancher depuis l'écran verrouillé — voir
//  `RootTabView.presentPendingReviewIfNeeded`. Les trajets en attente y passent
//  un par un, du plus ancien au plus récent.
//
//  La trace vient avant les chiffres, et c'est le fond de l'affaire : une date
//  et une distance ne suffisent pas à reconnaître un trajet parmi ceux de la
//  journée — un tracé, si. C'est aussi la seule surface de cet écran où le
//  verre a quelque chose à réfracter, d'où la pastille du compteur posée
//  dessus (voir `SlideToConfirmButton.knobWash` : sur le gris uni de l'app, le
//  verre ne se voit pas).
//

import SwiftUI
import SwiftData

struct PendingTripsReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var appServices
    @Environment(\.locale) private var locale

    // Le filtre « en attente seulement » se fait en Swift : SwiftData refuse un
    // prédicat sur une propriété d'énumération (voir `TripConfirmationStatus`,
    // qui porte la mesure). Lus par `@Query` et non sur un instantané : le même
    // trajet peut être tranché depuis les boutons de la notification pendant
    // que cet écran est ouvert, et la file doit s'en apercevoir.
    @Query(sort: \Trip.startDate, order: .forward) private var allTrips: [Trip]

    /// Combien de trajets attendaient quand l'écran s'est ouvert, pour pouvoir
    /// dire « 2 sur 3 » plutôt qu'un décompte qui rétrécit sans rien apprendre.
    ///
    /// `max` et non une affectation : un trajet peut se terminer pendant qu'on
    /// répond — l'app est ouverte, la détection tourne — et la file grandirait
    /// alors au-delà du total annoncé, ce qui donnerait un rang négatif.
    @State private var batchSize = 0

    /// Deux déclencheurs de retour haptique : ce qui compte est qu'ils
    /// changent, pas ce qu'ils valent (même idiome que
    /// `SlideToConfirmButton.completions`).
    @State private var confirmations = 0
    @State private var discards = 0

    /// Les trajets qui attendent une réponse.
    ///
    /// Terminés seulement : un trajet automatique naît `.pendingConfirmation`
    /// et le reste pendant tout l'enregistrement (voir `Trip.init`), et sans
    /// cette condition l'écran demandait de confirmer le trajet en cours de
    /// route, distance et durée grandissant sous les boutons.
    private var pendingTrips: [Trip] {
        allTrips.filter { $0.confirmationStatus == .pendingConfirmation && !$0.isActive }
    }

    private var viewModel: PendingTripsReviewViewModel {
        PendingTripsReviewViewModel(notificationService: appServices.notificationService)
    }

    var body: some View {
        // Relevés une fois pour ce rendu, puis passés de main en main : chaque
        // lecture de `pendingTrips` refiltre toute la table, et le corps, la
        // carte et le compteur en ont besoin — même geste que
        // `TripListView.body`.
        let pending = pendingTrips
        return NavigationStack {
            Group {
                if let trip = pending.first {
                    review(of: trip, waiting: pending.count)
                        // L'identité suit le trajet : la carte tient sa position
                        // de caméra en `@State`, et sans ce changement d'identité
                        // elle resterait cadrée sur le trajet d'avant.
                        .id(trip.id)
                        .transition(.opacity)
                } else {
                    // Le temps d'une animation seulement : `onChange` ci-dessous
                    // referme la feuille dès qu'il n'y a plus rien. Mais elle
                    // doit se voir, sinon le dernier « Oui » laisse un écran
                    // vide le temps que la feuille parte.
                    ContentUnavailableView("Tout est à jour", systemImage: "checkmark.circle")
                }
            }
            .animation(.smooth, value: pending.first?.id)
            .appBackground()
            .localizedNavigationTitle("Trajets en attente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Une sortie franche, plutôt que le seul glissement vers le
                    // bas : la carte occupe le haut de la feuille, et même
                    // rendue insensible au doigt elle n'invite pas à la tirer.
                    // Ce qu'on laisse reviendra à la prochaine ouverture de
                    // l'app.
                    Button("Plus tard") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: confirmations)
        .sensoryFeedback(.impact(weight: .medium), trigger: discards)
        .onChange(of: pending.count, initial: true) { _, count in
            batchSize = max(batchSize, count)
        }
        .onChange(of: pending.isEmpty) { _, isEmpty in
            if isEmpty {
                dismiss()
            }
        }
    }

    private func review(of trip: Trip, waiting: Int) -> some View {
        VStack(spacing: 18) {
            map(of: trip, waiting: waiting)
            figures(of: trip)
            Text("Voulez-vous enregistrer ce trajet ?")
                .font(.headline)
                .multilineTextAlignment(.center)
                // Sans ça la question reste sur une ligne et finit en points de
                // suspension aux gros caractères : dans une pile, un `Text`
                // reçoit d'abord la hauteur d'une ligne et s'y tient.
                .fixedSize(horizontal: false, vertical: true)
            actions(for: trip)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    /// La trace du trajet, qui prend toute la hauteur que les chiffres et les
    /// boutons lui laissent — jusqu'à un plancher, sous lequel un tracé ne
    /// s'identifie plus.
    ///
    /// Non interactive : c'est une vignette qu'on regarde le temps de répondre,
    /// et une carte qui prend le geste retiendrait la feuille au lieu de la
    /// laisser se refermer.
    private func map(of trip: Trip, waiting: Int) -> some View {
        TripRouteMapView(routePoints: trip.routePoints, interactionModes: [])
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if batchSize > 1 {
                    counter(waiting: waiting)
                        .padding(12)
                }
            }
    }

    /// « 2 sur 3 » : où l'on en est dans la file. Posé sur la carte, seule
    /// surface de l'écran où le verre a de quoi vivre.
    private func counter(waiting: Int) -> some View {
        Text("\(batchSize - waiting + 1) sur \(batchSize)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
    }

    /// La date et le véhicule en tête, les trois chiffres dessous. Une carte
    /// opaque et non du verre : c'est du contenu, et le verre appartient à la
    /// couche qui flotte au-dessus (voir `View+Card`).
    private func figures(of trip: Trip) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(TripFormatting.dateAndTime(trip.startDate, locale: locale))
                Spacer(minLength: 8)
                vehicleLabel(of: trip)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            HStack(spacing: 12) {
                StatView("Distance") {
                    Text(trip.formattedDistance(
                        in: appServices.unitSettingsService.distanceUnit, locale: locale
                    ))
                }
                Divider().frame(height: 34)
                StatView("Durée") {
                    Text(trip.formattedDuration(locale: locale))
                }
                // Le coût n'existe que si le véhicule porte sa consommation et
                // le prix de son énergie : la colonne disparaît plutôt que de
                // montrer un tiret, et les deux autres prennent la place.
                if let cost = trip.formattedEnergyCost(locale: locale) {
                    Divider().frame(height: 34)
                    StatView("Coût") { Text(cost) }
                }
            }
        }
        .appCard()
    }

    /// Le nom du véhicule est une donnée saisie : il se rend tel quel. Rien
    /// quand le trajet n'en a pas — la ligne n'a alors rien à dire, et l'écran
    /// de détail est là pour lui en donner un.
    @ViewBuilder
    private func vehicleLabel(of trip: Trip) -> some View {
        if let name = trip.vehicle?.name {
            HStack(spacing: 4) {
                Image(systemName: "car.fill")
                Text(name)
            }
        }
    }

    /// Les deux réponses, en verre — le matériau qu'iOS réserve aux contrôles
    /// posés sur le contenu. Les styles sont ceux du système
    /// (`.glass` / `.glassProminent`) et non un habillage maison : la gélule
    /// leur vient de `buttonBorderShape` posé à la racine de l'app, et la
    /// teinte de la proéminence est l'accent.
    ///
    /// `Color.onAccent` sur le libellé du bouton plein, comme partout ailleurs :
    /// l'accent de l'app est un noir pur qui devient blanc pur en thème sombre,
    /// et SwiftUI ne recalcule pas la couleur du texte posé dessus.
    private func actions(for trip: Trip) -> some View {
        HStack(spacing: 12) {
            Button {
                discards += 1
                viewModel.discard(trip, in: modelContext)
            } label: {
                Text("Non").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)

            Button {
                confirmations += 1
                viewModel.confirm(trip, in: modelContext)
            } label: {
                Text("Oui, enregistrer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .foregroundStyle(Color.onAccent)
        }
        .controlSize(.large)
        .font(.body.weight(.semibold))
        // « Oui, enregistrer » est le plus long des six langues et il n'a qu'une
        // demi-largeur : il rapetisse plutôt que de passer à la ligne ou de se
        // couper.
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let vehicle = Vehicle(name: "Ma voiture")
    container.mainContext.insert(vehicle)
    for offset in 0..<2 {
        let start = Date.now.addingTimeInterval(-1800 - Double(offset) * 7200)
        let trip = Trip(startDate: start, source: .automatic, vehicle: vehicle)
        trip.endDate = start.addingTimeInterval(1380)
        trip.distanceMeters = 8300
        trip.routePoints = [
            RoutePoint(latitude: 46.5197, longitude: 6.6323, timestamp: start),
            RoutePoint(latitude: 46.5240, longitude: 6.6410, timestamp: start.addingTimeInterval(400)),
            RoutePoint(latitude: 46.5301, longitude: 6.6522, timestamp: start.addingTimeInterval(900)),
            RoutePoint(latitude: 46.5360, longitude: 6.6688, timestamp: start.addingTimeInterval(1380))
        ]
        container.mainContext.insert(trip)
    }
    return PendingTripsReviewView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
