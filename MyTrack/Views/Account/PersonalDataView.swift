//
//  PersonalDataView.swift
//  MyTrack
//
//  Edited through local state rather than bound straight to the UserProfile
//  model: with a Save button on screen, typing must not already be committed
//  to the shared model — leaving without saving has to actually discard, which
//  binding to the @Model directly could not do.
//

import SwiftUI
import SwiftData

struct PersonalDataView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.localizationBundle) private var localizationBundle

    @State private var profile: UserProfile?
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phoneNumber = ""
    @State private var isSaveFailedAlertPresented = false

    private var isModified: Bool {
        guard let profile else { return false }
        return firstName != profile.firstName
            || lastName != profile.lastName
            || email != profile.email
            || phoneNumber != profile.phoneNumber
    }

    var body: some View {
        Form {
            Section {
                TextField("Prénom", text: $firstName)
                TextField("Nom", text: $lastName)
            }
            Section {
                TextField("Adresse mail", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Numéro de téléphone", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
        }
        .navigationTitle("Données personnelles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                // Clé explicite : « Enregistrer » veut dire deux choses
                // différentes dans l'app — sauvegarder ici, démarrer un
                // enregistrement dans l'onglet — et une clé par sens est le
                // seul moyen de les traduire différemment.
                Button(String(localized: "action.save", defaultValue: "Enregistrer", bundle: localizationBundle, locale: locale)) { save() }
                    .disabled(!isModified)
            }
        }
        .onAppear {
            guard profile == nil else { return }
            let currentProfile = appServices.userProfileService.currentProfile(in: modelContext)
            profile = currentProfile
            firstName = currentProfile.firstName
            lastName = currentProfile.lastName
            email = currentProfile.email
            phoneNumber = currentProfile.phoneNumber
        }
        .alert("Enregistrement impossible", isPresented: $isSaveFailedAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Tes informations n'ont pas pu être enregistrées. Réessaie.")
        }
    }

    private func save() {
        guard let profile else { return }
        profile.firstName = firstName
        profile.lastName = lastName
        profile.email = email
        profile.phoneNumber = phoneNumber

        // Deliberately not rolling back on failure: rollback discards every
        // pending change in the shared context, which would throw away the
        // route points of a trip being recorded in the background.
        guard modelContext.saveOrLog() else {
            isSaveFailedAlertPresented = true
            return
        }
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return NavigationStack {
        PersonalDataView()
    }
    .environment(AppServices(modelContext: container.mainContext))
    .modelContainer(container)
}
