//
//  RecordTripView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct RecordTripView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Query private var vehicles: [Vehicle]
    @State private var isPermissionDeniedAlertPresented = false
    @State private var isPresentingVehiclePicker = false

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.isSelected }
    }

    private var viewModel: RecordTripViewModel {
        RecordTripViewModel(
            tripRecorder: appServices.tripRecorder,
            locationService: appServices.locationService,
            vehicleService: appServices.vehicleService,
            drivingDetector: appServices.drivingDetector,
            notificationService: appServices.notificationService
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.isRecording {
                    VStack {
                        Text(formattedDistance(viewModel.currentDistanceMeters))
                            .font(.largeTitle)
                        if let start = viewModel.currentStartDate {
                            Text(start, style: .timer)
                                .font(.title2)
                                .monospacedDigit()
                        }
                    }

                    LiveTripMapView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Button(viewModel.isRecording ? "Arrêter" : "Démarrer") {
                    if viewModel.isRecording {
                        viewModel.stopManualRecording(in: modelContext)
                    } else if viewModel.startManualRecording(in: modelContext) == .permissionDenied {
                        isPermissionDeniedAlertPresented = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.isRecording ? .red : .accentColor)
            }
            .padding()
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        isPresentingVehiclePicker = true
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Text(selectedVehicle?.name ?? "Aucun véhicule")
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
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBellButton()
                }
            }
            .accountToolbar()
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
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        TripFormatting.distance(
            meters: meters,
            unit: appServices.unitSettingsService.distanceUnit,
            fractionDigits: 2
        )
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, AppNotification.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return RecordTripView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
