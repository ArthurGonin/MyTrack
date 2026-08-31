//
//  VehiclePickerView.swift
//  MyTrack
//
//  Reusable "pick a vehicle" sheet. What selecting a row actually means is
//  left to the caller via `onSelect` — RecordTripView uses it to change the
//  globally active vehicle, TripDetailView uses it to reassign a single past
//  trip, and neither has to know about the other's meaning of "selected".
//
//  Chaque ligne porte aussi ce qu'on sait du véhicule — énergie, consommation,
//  prix — et le bouton ⓘ ouvre sa fiche pour le modifier. C'est la disposition
//  des Réglages (le Wi-Fi, par exemple) : toucher la ligne choisit, le bouton
//  au bout ouvre les détails. Les deux sens tiennent ainsi dans une seule
//  liste, sans qu'un appui destiné à l'un déclenche l'autre.
//

import SwiftUI
import SwiftData

struct VehiclePickerView: View {
    let selectedVehicle: Vehicle?
    /// Fournie par les écrans où « aucun véhicule » veut dire « tous » — la
    /// liste des trajets, qui filtre. Une ligne « Tous les véhicules » s'ouvre
    /// alors en tête. Ailleurs — l'accueil, un trajet à réattribuer — ce mot
    /// n'aurait rien derrière lui, et la ligne n'existe pas.
    ///
    /// Déclarée avant `onSelect` pour que la fermeture finale des appels
    /// continue de se rattacher à celui-ci.
    var onSelectAllVehicles: (() -> Void)?
    let onSelect: (Vehicle) -> Void

    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle
    @Query(sort: \Vehicle.name) private var vehicles: [Vehicle]
    @State private var isPresentingAddVehicle = false
    @State private var vehicleBeingEdited: Vehicle?

    private var viewModel: VehicleListViewModel {
        VehicleListViewModel(vehicleService: appServices.vehicleService)
    }

    var body: some View {
        NavigationStack {
            Group {
                if vehicles.isEmpty {
                    ContentUnavailableView(
                        "Aucun véhicule",
                        systemImage: "car",
                        description: Text("Ajoutez un véhicule pour l'associer à vos trajets.")
                    )
                } else {
                    List {
                        if let onSelectAllVehicles {
                            allVehiclesRow(onSelectAllVehicles)
                        }
                        ForEach(vehicles) { vehicle in
                            row(vehicle)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                viewModel.deleteVehicle(vehicles[index], in: modelContext)
                            }
                        }
                    }
                }
            }
            .appBackground()
            .localizedNavigationTitle("Véhicules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingAddVehicle = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter un véhicule")
                }
            }
            .sheet(isPresented: $isPresentingAddVehicle) {
                AddVehicleView(viewModel: viewModel)
            }
            .sheet(item: $vehicleBeingEdited) { vehicle in
                EditVehicleView(vehicle: vehicle)
            }
        }
    }

    /// « Tous les véhicules » : la ligne du haut, sans ⓘ — il n'y a pas de
    /// fiche à ouvrir derrière. Son symbole reste dans la même colonne que ceux
    /// des véhicules pour que les noms s'alignent tous.
    private func allVehiclesRow(_ action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "car.2")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text("Tous les véhicules")
                Spacer()
                if selectedVehicle == nil {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Deux boutons côte à côte plutôt qu'un bouton dans un bouton : imbriqués,
    /// c'est la ligne entière qui répondrait au ⓘ.
    private func row(_ vehicle: Vehicle) -> some View {
        HStack(spacing: 12) {
            Button {
                onSelect(vehicle)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    // L'énergie du véhicule, d'un coup d'œil. Largeur fixée
                    // pour que les trois symboles — pompe, éclair, voiture —
                    // alignent les noms qui les suivent malgré leurs chasses
                    // différentes.
                    Image(systemName: vehicle.energyType.symbolName)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vehicle.name)
                        ForEach(detailLines(for: vehicle), id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if vehicle === selectedVehicle {
                        Image(systemName: "checkmark")
                    }
                }
                // Sans ça, seul le texte est tapable : la ligne entière doit
                // répondre, y compris l'espace vide à droite.
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button {
                vehicleBeingEdited = vehicle
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Modifier le véhicule")
        }
    }

    /// Ce que la ligne dit du véhicule sous son nom : son identité
    /// (« AB-123-CD · Thermique ») puis ses chiffres (« 6,5 L/100 km ·
    /// 1,85 €/L »). Deux lignes plutôt qu'une seule : tout bout à bout, un
    /// véhicule entièrement renseigné débordait et repassait à la ligne
    /// n'importe où.
    ///
    /// Ce qui manque disparaît, la ligne entière comprise quand il n'en reste
    /// rien. L'énergie, elle, est toujours là : un véhicule en a forcément une.
    private func detailLines(for vehicle: Vehicle) -> [String] {
        let identity = [
            vehicle.licensePlate,
            vehicle.energyType.label(bundle: localizationBundle, locale: locale),
        ]
        let figures = [
            vehicle.formattedConsumption(locale: locale),
            vehicle.formattedEnergyPrice(locale: locale),
        ]
        return [identity, figures]
            .map { $0.compactMap { $0 }.joined(separator: " · ") }
            .filter { !$0.isEmpty }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return VehiclePickerView(selectedVehicle: nil, onSelect: { _ in })
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
