//
//  DetectionLogView.swift
//  MyTrack
//
//  Ce que la détection a fait, et ce qu'elle a refusé de faire.
//
//  L'écran existe pour une question précise : « pourquoi ce trajet-là ne s'est
//  pas enregistré ? ». Elle se répondait jusqu'ici avec un Mac, Console.app et
//  l'iPhone branché — c'est-à-dire jamais, puisqu'un trajet manqué ne se
//  prévoit pas. Voir `DetectionLog`.
//
//  Le contenu des lignes reste en anglais technique, comme celles de la
//  Console : c'est une donnée de diagnostic et non un texte d'interface. Ce qui
//  entoure la liste, lui, est traduit.
//

import SwiftUI

struct DetectionLogView: View {
    @Environment(AppServices.self) private var appServices

    var body: some View {
        List {
            if appServices.detectionLog.entries.isEmpty {
                ContentUnavailableView(
                    "Aucun événement",
                    systemImage: "text.page",
                    description: Text("Le journal se remplira au prochain réveil de la détection ou au prochain trajet.")
                )
            } else {
                Section {
                    // Du plus récent au plus ancien : la question qu'on se pose
                    // en ouvrant cet écran porte toujours sur ce qui vient de
                    // se passer.
                    ForEach(Array(appServices.detectionLog.entries.reversed().enumerated()), id: \.offset) { _, entry in
                        DetectionLogRow(entry: entry)
                    }
                } footer: {
                    Text("Les \(appServices.detectionLog.entries.count) derniers événements de la détection automatique et du suivi GPS.")
                }
            }
        }
        .navigationTitle("Journal de détection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: appServices.detectionLog.exportText) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        appServices.detectionLog.clear()
                    } label: {
                        Label("Effacer le journal", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .disabled(appServices.detectionLog.entries.isEmpty)
            }
        }
    }
}

private struct DetectionLogRow: View {
    let entry: DetectionLog.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.date, format: .dateTime.day().month().hour().minute().second())
                .font(.caption)
                .foregroundStyle(.secondary)
            // Une donnée technique, rendue telle quelle : ni traduite, ni
            // reformulée. `Text(verbatim:)` le dit explicitement plutôt que de
            // laisser croire à une clé de traduction manquante.
            Text(verbatim: entry.message)
                .font(.callout)
                .foregroundStyle(entry.isFailure ? Color.red : Color.primary)
        }
        .padding(.vertical, 2)
    }
}
