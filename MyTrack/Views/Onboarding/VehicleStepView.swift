//
//  VehicleStepView.swift
//  MyTrack
//

import SwiftUI

struct VehicleStepView: View {
    @Binding var vehicleName: String
    @Binding var licensePlate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ton véhicule")
                    .font(.largeTitle.bold())
                Text("Pour associer tes trajets")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                TextField("Nom du véhicule", text: $vehicleName)
                    .textInputAutocapitalization(.words)
                    .padding()
                Divider()
                    .padding(.leading)
                TextField("Immatriculation (optionnel)", text: $licensePlate)
                    .textInputAutocapitalization(.characters)
                    .padding()
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding()
    }
}

#Preview {
    VehicleStepView(vehicleName: .constant(""), licensePlate: .constant(""))
        .appBackground()
}
