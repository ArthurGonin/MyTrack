//
//  UnitStepView.swift
//  MyTrack
//

import SwiftUI

struct UnitStepView: View {
    @Binding var distanceUnit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tes distances")
                    .font(.largeTitle.bold())
                Text("En kilomètres ou en miles ?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            OnboardingChoiceList(options: DistanceUnit.allCases, selection: $distanceUnit) {
                Text($0.label)
            }

            Spacer()
        }
        .padding()
    }
}

#Preview {
    @Previewable @State var unit: DistanceUnit = .kilometers

    UnitStepView(distanceUnit: $unit)
        .appBackground()
}
