//
//  NameStepView.swift
//  MyTrack
//

import SwiftUI

struct NameStepView: View {
    @Binding var firstName: String
    @Binding var lastName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Comment tu t'appelles ?")
                    .font(.largeTitle.bold())
                Text("Ton prénom et ton nom")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                TextField("Prénom", text: $firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .padding()
                Divider()
                    .padding(.leading)
                TextField("Nom", text: $lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    .padding()
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
        .padding()
    }
}

#Preview {
    NameStepView(firstName: .constant(""), lastName: .constant(""))
        .appBackground()
}
