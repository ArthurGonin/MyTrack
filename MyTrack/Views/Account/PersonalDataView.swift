//
//  PersonalDataView.swift
//  MyTrack
//

import SwiftUI
import SwiftData

struct PersonalDataView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var profile: UserProfile?
    @State private var originalFirstName = ""
    @State private var originalLastName = ""
    @State private var originalEmail = ""
    @State private var originalPhoneNumber = ""

    private var isModified: Bool {
        guard let profile else { return false }
        return profile.firstName != originalFirstName
            || profile.lastName != originalLastName
            || profile.email != originalEmail
            || profile.phoneNumber != originalPhoneNumber
    }

    var body: some View {
        Form {
            if let profile {
                @Bindable var profile = profile

                Section {
                    TextField("Prénom", text: $profile.firstName)
                    TextField("Nom", text: $profile.lastName)
                }
                Section {
                    TextField("Adresse mail", text: $profile.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Numéro de téléphone", text: $profile.phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
            }
        }
        .navigationTitle("Données personnelles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save() }
                    .disabled(!isModified)
            }
        }
        .onAppear {
            if profile == nil {
                let currentProfile = appServices.userProfileService.currentProfile(in: modelContext)
                profile = currentProfile
                captureSnapshot(of: currentProfile)
            }
        }
    }

    private func captureSnapshot(of profile: UserProfile) {
        originalFirstName = profile.firstName
        originalLastName = profile.lastName
        originalEmail = profile.email
        originalPhoneNumber = profile.phoneNumber
    }

    private func save() {
        guard let profile else { return }
        try? modelContext.save()
        captureSnapshot(of: profile)
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
