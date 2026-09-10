//
//  DetectionLog.swift
//  MyTrack
//
//  Le journal de la détection automatique, lisible depuis l'iPhone seul.
//
//  Il existe parce que la détection décide en arrière-plan, souvent dans un
//  processus qu'iOS a lancé puis tué sans que personne le voie, et que rien
//  n'en restait ensuite. Un trajet manqué n'avait aucune cause consultable :
//  il fallait un Mac, Console.app et l'appareil branché — c'est-à-dire qu'il
//  fallait avoir prévu le trajet raté avant qu'il ait lieu.
//
//  `OSLogStore` ne répond pas à ça sur iOS. Une app sans droit particulier ne
//  peut ouvrir que `.currentProcessIdentifier`, donc uniquement les lignes du
//  processus courant ; celles du processus qui a raté le trajet sont perdues
//  avec lui, et `OSLogStore.local()` demande un droit qu'Apple n'accorde pas
//  sur l'App Store. Un écran bâti là-dessus montrerait exactement ce qui ne
//  sert à rien. Le journal doit donc être écrit par l'app, et survivre au
//  processus qui l'écrit.
//

import Foundation
import OSLog

@Observable
final class DetectionLog {
    struct Entry: Codable {
        let date: Date
        let message: String
        /// Un événement qui décrit une panne plutôt qu'une décision. Il choisit
        /// le niveau dans la Console, et la couleur dans la liste : c'est la
        /// ligne qu'on cherche des yeux quand on ouvre le journal.
        let isFailure: Bool
    }

    /// Du plus ancien au plus récent, comme un journal se lit — la vue
    /// l'inverse pour l'affichage.
    private(set) var entries: [Entry] = []

    /// Combien d'événements on garde.
    ///
    /// Deux cents, soit plusieurs jours d'usage ordinaire : la détection
    /// n'écrit que sur des événements — un réveil, un verdict, une fin de
    /// trajet — et pas sur le temps qui passe. Assez pour qu'un trajet raté
    /// hier soit encore là demain, assez peu pour que le fichier tienne dans
    /// quelques dizaines de kilo-octets.
    private static let capacity = 200

    private static let fileName = "detection-log.json"

    init() {
        entries = Self.loadFromDisk()
    }

    /// Journalise **et** logue, pour qu'il n'y ait pas deux sources à tenir à
    /// jour. Ce qui passe ici part aussi dans la Console, où il reste lisible
    /// avec tout le reste et sans la limite des deux cents lignes.
    func record(_ message: String, isFailure: Bool = false) {
        if isFailure {
            AppLog.recording.error("\(message, privacy: .public)")
        } else {
            AppLog.recording.notice("\(message, privacy: .public)")
        }
        // Un message identique au précédent remplace le précédent au lieu de
        // s'empiler dessus. Les messages qui se répètent mot pour mot sont les
        // messages d'état — « Motion & Fitness isn't granted », « Always
        // location isn't granted » — et `refresh()` les produit à chaque retour
        // au premier plan : trois lignes identiques par ouverture d'app
        // chasseraient du journal les événements qu'on y cherche. Ce qui
        // compte, pour un état, c'est la dernière fois qu'il était vrai.
        if entries.last?.message == message {
            entries.removeLast()
        }
        entries.append(Entry(date: .now, message: message, isFailure: isFailure))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
        saveToDisk()
    }

    func clear() {
        entries = []
        saveToDisk()
    }

    /// Le journal en texte brut, du plus récent au plus ancien — ce que le
    /// bouton de partage envoie. Les dates en ISO 8601 plutôt qu'en format
    /// local : c'est un document technique, destiné à être relu et comparé.
    var exportText: String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return entries.reversed()
            .map { "\(formatter.string(from: $0.date))  \($0.message)" }
            .joined(separator: "\n")
    }

    // MARK: - Disque

    /// Réécrit à chaque événement, et non par lots.
    ///
    /// C'est le prix à payer pour que le journal serve : en arrière-plan, iOS
    /// suspend l'app entre deux instants quelconques et ne prévient pas. Un
    /// tampon vidé « plus tard » serait vide précisément quand le rattrapage
    /// vient d'échouer, c'est-à-dire au seul moment qui compte. Quelques
    /// dizaines de kilo-octets écrits sur un événement rare ne se voient pas.
    private func saveToDisk() {
        guard let url = Self.fileURL() else { return }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            // Sans passer par `record`, qui rappellerait ici : un disque plein
            // écrirait alors une ligne par tentative d'écrire une ligne.
            AppLog.recording.error(
                "Could not write the detection log: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func loadFromDisk() -> [Entry] {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    /// Dans Application Support et non dans Documents : c'est une donnée
    /// interne, que l'utilisateur lit par l'écran prévu pour et non en fouillant
    /// l'app Fichiers.
    private static func fileURL() -> URL? {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}
