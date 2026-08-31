//
//  UnitStepView.swift
//  MyTrack
//

import SwiftUI

struct UnitStepView: View {
    @Binding var distanceUnit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Vos distances")
                    .font(.largeTitle.bold())
                Text("En kilomètres ou en miles ?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            OnboardingChoiceList(options: DistanceUnit.allCases, selection: $distanceUnit) {
                Text($0.label)
            }
        }
    }
}

#Preview {
    @Previewable @State var unit: DistanceUnit = .kilometers

    UnitStepView(distanceUnit: $unit)
        .appBackground()
}
