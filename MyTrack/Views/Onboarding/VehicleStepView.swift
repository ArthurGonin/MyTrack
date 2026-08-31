//
//  VehicleStepView.swift
//  MyTrack
//

import SwiftUI

struct VehicleStepView: View {
    @Binding var draft: VehicleDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Votre véhicule")
                    .font(.largeTitle.bold())
                Text("Pour associer vos trajets")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            Form {
                VehicleFormFields(draft: $draft)
            }
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

#Preview {
    @Previewable @State var draft = VehicleDraft()

    VehicleStepView(draft: $draft)
        .appBackground()
}
