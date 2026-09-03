//
//  FeedbackView.swift
//  MyTrack
//
//  La feuille depuis laquelle on nous écrit : un titre, un message, et voilà.
//
//  Deux champs et rien de plus, volontairement. Une adresse de réponse, une
//  catégorie, une capture d'écran : chacune se défend, et chacune est une
//  raison de plus de refermer la feuille sans rien envoyer. Ce que le message
//  emporte en plus — version de l'app, d'iOS, modèle de l'appareil — est
//  annoncé sous le champ plutôt que glissé en douce : voir `FeedbackService`.
//
//  Un échec ne vide jamais les champs. Quelqu'un qui vient d'écrire trois
//  paragraphes dans un train sans réseau doit les retrouver intacts.
//

import SwiftData
import SwiftUI

struct FeedbackView: View {
    @Environment(AppServices.self) private var appServices
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var hasSent = false
    @State private var isFailureAlertPresented = false
    @State private var failure: FeedbackError?

    private var canSend: Bool {
        !isSending
            && !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasSent {
                    confirmation
                } else {
                    form
                }
            }
            .appBackground()
            // « Nous écrire » et non « Envoyer un commentaire », qui est le
            // libellé de la ligne : un grand titre de barre de navigation ne va
            // pas à la ligne, et celui-là se coupait à « Envoyer un commenta… ».
            .localizedNavigationTitle("Nous écrire")
            .toolbar {
                // Plus rien à annuler ni à envoyer une fois le message parti :
                // la feuille se referme d'elle-même.
                if !hasSent {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSending {
                            ProgressView()
                        } else {
                            Button("Envoyer") { send() }
                                .disabled(!canSend)
                        }
                    }
                }
            }
            .alert("Envoi impossible", isPresented: $isFailureAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failureMessage)
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Titre", text: $subject)
            }
            Section {
                // Le champ grandit avec ce qu'on y écrit, à partir de six
                // lignes : un commentaire tient rarement sur une, et un champ
                // d'une ligne donne à croire qu'on n'en attend pas plus.
                TextField("Votre message", text: $message, axis: .vertical)
                    .lineLimit(6...)
            } footer: {
                Text("Le message part avec la version de MyTrack, celle d'iOS et le modèle de votre iPhone, de quoi situer ce que vous décrivez. Aucun de vos trajets n'est joint.")
            }
        }
        .disabled(isSending)
    }

    /// Ce qui remplace le formulaire une fois le message parti, le temps de le
    /// lire. La feuille se referme ensuite toute seule : rester là à regarder
    /// une coche n'apprend plus rien.
    private var confirmation: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Message envoyé")
                .font(.title2.bold())
            Text("Merci, c'est lu.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var failureMessage: LocalizedStringKey {
        switch failure {
        case .notConfigured:
            "L'envoi de commentaires n'est pas disponible dans cette version."
        default:
            "Le message n'a pas pu être envoyé. Réessayez plus tard."
        }
    }

    private func send() {
        isSending = true
        Task {
            do {
                try await appServices.feedbackService.send(subject: subject, message: message)
                isSending = false
                withAnimation { hasSent = true }
                try? await Task.sleep(for: .seconds(1.6))
                dismiss()
            } catch {
                isSending = false
                failure = error as? FeedbackError ?? .serviceUnavailable
                isFailureAlertPresented = true
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Trip.self, Vehicle.self, UserProfile.self, ReportProfile.self, GeneratedReport.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    return FeedbackView()
        .environment(AppServices(modelContext: container.mainContext))
        .modelContainer(container)
}
