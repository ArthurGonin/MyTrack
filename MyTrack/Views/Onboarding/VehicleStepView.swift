//
//  VehicleStepView.swift
//  MyTrack
//

import SwiftUI

struct VehicleStepView: View {
    @Binding var vehicleName: String
    @Binding var licensePlate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ton véhicule")
                    .font(.largeTitle.bold())
                Text("Pour associer tes trajets")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Form {
                Section {
                    TextField("Nom du véhicule", text: $vehicleName)
                        .textInputAutocapitalization(.words)
                    TextField("Immatriculation (optionnel)", text: $licensePlate)
                        .textInputAutocapitalization(.characters)
                }
            }
            .contentMargins(.top, 8, for: .scrollContent)
        }
    }
}

#Preview {
    VehicleStepView(vehicleName: .constant(""), licensePlate: .constant(""))
        .appBackground()
}
