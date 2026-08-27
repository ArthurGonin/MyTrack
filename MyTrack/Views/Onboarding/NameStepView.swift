//
//  NameStepView.swift
//  MyTrack
//

import SwiftUI

struct NameStepView: View {
    @Binding var firstName: String
    @Binding var lastName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Comment tu t'appelles ?")
                    .font(.largeTitle.bold())
                Text("Ton prénom et ton nom")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            // Un `Form`, comme dans les Réglages : les champs y prennent la
            // hauteur, le retrait et le fond des cellules système, et le
            // clavier qui monte fait défiler le champ visé au lieu de le
            // recouvrir. Le `Form` occupe aussi la place restante, ce qui rend
            // inutile le `Spacer` qui poussait le contenu vers le haut.
            Form {
                Section {
                    TextField("Prénom", text: $firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                    TextField("Nom", text: $lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                }
            }
            .contentMargins(.top, 8, for: .scrollContent)
        }
    }
}

#Preview {
    NameStepView(firstName: .constant(""), lastName: .constant(""))
        .appBackground()
}
