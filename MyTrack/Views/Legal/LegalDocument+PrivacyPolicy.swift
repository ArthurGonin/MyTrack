//
//  LegalDocument+PrivacyPolicy.swift
//  MyTrack
//
//  La politique de confidentialité.
//
//  Elle décrit ce que le code fait, et rien d'autre : chaque phrase se vérifie
//  dans un fichier de ce dépôt. Les trois sources à relire quand quelque chose
//  change de ce côté-là sont `TripRecorder` et `LocationService` pour ce qui est
//  relevé, `VehiclePhotoService` et `Server/studio-cutout/worker.ts` pour le seul
//  envoi que fait l'app, et `AppServices.eraseAllData` pour ce que « supprimer
//  le compte » efface vraiment.
//

import SwiftUI

extension LegalDocument {
    static let privacyPolicy = LegalDocument(
        // « Confidentialité » et non « Politique de confidentialité » : c'est
        // le mot sur lequel on appuie dans la paywall comme dans les réglages,
        // et un grand titre de barre de navigation ne va pas à la ligne — le
        // nom long s'y coupait à « Politique de confidenti… ».
        title: "Confidentialité",
        sections: [
            Section(
                heading: "En bref",
                paragraphs: [
                    "MyTrack enregistre vos trajets sur votre iPhone, et ils y restent. L'app n'a pas de compte à créer, pas de serveur où vos trajets seraient recopiés, aucune publicité et aucun traceur.",
                    "Une seule chose quitte votre appareil, et seulement si vous la demandez : la photo de votre véhicule, envoyée pour être détourée. Tout le reste — positions, distances, véhicules, rapports — ne sort jamais de l'iPhone.",
                ]
            ),
            Section(
                heading: "Qui édite MyTrack",
                paragraphs: [
                    "MyTrack est éditée par KiwiJuice, en Suisse. C'est KiwiJuice qui répond du traitement décrit ici.",
                ]
            ),
            Section(
                heading: "Ce qui est enregistré sur votre appareil",
                paragraphs: [
                    "Vos trajets : date, durée, distance, points de départ et d'arrivée, et le tracé relevé pendant le trajet. Vos véhicules : nom, plaque si vous la renseignez, énergie, consommation, prix de l'énergie, et la photo si vous en prenez une.",
                    "Votre profil : prénom, nom, e-mail et téléphone, tels que vous les saisissez ; ils figurent en en-tête de vos rapports et ne sont transmis nulle part. Vos rapports PDF, produits sur l'appareil. Enfin vos réglages : langue, unité de distance, préférences d'enregistrement.",
                    "Tout cela vit dans une base locale, sur votre iPhone. Elle n'est synchronisée ni avec iCloud, ni avec un serveur.",
                ]
            ),
            Section(
                heading: "La position",
                paragraphs: [
                    "Pendant un trajet, MyTrack relève votre position pour tracer l'itinéraire et calculer la distance. Ces points sont écrits dans la base locale et n'en sortent pas.",
                    "L'accès « Toujours » n'est demandé que si vous activez le suivi automatique : c'est ce qui permet à iOS de réveiller l'app au début d'un trajet. Sans lui, seuls les trajets que vous démarrez vous-même peuvent être enregistrés.",
                ]
            ),
            Section(
                heading: "Le mouvement",
                paragraphs: [
                    "Avec votre autorisation, MyTrack lit l'activité de mouvement mesurée par iOS — marche, course, voiture — pour reconnaître le début et la fin d'un trajet. Cette activité est lue sur le moment ; elle n'est ni enregistrée, ni transmise.",
                ]
            ),
            Section(
                heading: "La photo de votre véhicule",
                paragraphs: [
                    "Si vous photographiez votre véhicule, la photo est envoyée à un relais opéré par KiwiJuice, qui la transmet à OpenAI pour la détourer et la nettoyer. C'est le seul envoi que fait l'app, et il n'a lieu qu'au moment où vous prenez une photo.",
                    "Le relais ne conserve pas la photo : il la transmet et vous renvoie le résultat. Il garde seulement un compteur — l'identifiant que votre appareil donne à l'éditeur, et la date du jour — pour limiter le service à cinq photos quotidiennes. Ce compteur s'efface au bout de vingt-six heures, et cet identifiant change si vous supprimez puis réinstallez l'app.",
                    "OpenAI traite la photo aux États-Unis pour produire l'image et, selon la politique de son interface de programmation, peut la conserver un temps limité à des fins de sécurité, sans s'en servir pour entraîner ses modèles.",
                    "Photographiez votre voiture, pas les gens autour d'elle. Et si vous préférez ne rien envoyer, ne prenez pas de photo : l'app fonctionne très bien avec le dessin de voiture par défaut.",
                ]
            ),
            Section(
                heading: "Ce que MyTrack ne fait pas",
                paragraphs: [
                    "Pas de compte, pas de mot de passe, pas d'identifiant publicitaire. Aucun outil de mesure d'audience, aucun kit tiers, aucune trace envoyée à quiconque lorsque vous ouvrez l'app ou appuyez sur un bouton.",
                    "Vos données ne sont ni vendues, ni louées, ni partagées, et ne servent à établir aucun profil.",
                ]
            ),
            Section(
                heading: "Les notifications",
                paragraphs: [
                    "Si vous les autorisez, MyTrack vous prévient qu'un trajet détecté attend votre confirmation, qu'un rapport est prêt, ou que votre abonnement a expiré. Ces notifications sont préparées et déclenchées sur votre appareil ; aucune n'arrive d'un serveur.",
                ]
            ),
            Section(
                heading: "Les achats",
                paragraphs: [
                    "Les abonnements et l'achat unique passent par l'App Store. C'est Apple qui encaisse et qui connaît votre moyen de paiement : KiwiJuice n'y a pas accès et ne reçoit ni votre nom, ni votre adresse, ni votre numéro de carte.",
                    "L'app se contente de demander à iOS si votre accès est actif, et jusqu'à quand.",
                ]
            ),
            Section(
                heading: "Combien de temps, et comment tout effacer",
                paragraphs: [
                    "Vos données restent tant que vous gardez l'app. Rien n'expire et rien n'est effacé dans votre dos.",
                    "Dans Réglages, « Supprimer le compte » efface définitivement vos trajets, vos véhicules, vos rapports, votre profil et vos réglages. Supprimer l'app depuis l'écran d'accueil emporte la base avec elle.",
                ]
            ),
            Section(
                heading: "Les sauvegardes",
                paragraphs: [
                    "Si vous sauvegardez votre iPhone, dans iCloud ou sur un ordinateur, la base de MyTrack fait partie de la sauvegarde. Elle est alors protégée par Apple, selon vos réglages de sauvegarde, et non par MyTrack.",
                ]
            ),
            Section(
                heading: "Les enfants",
                paragraphs: [
                    "MyTrack s'adresse à des conducteurs. L'app n'est pas destinée aux enfants et ne recueille sciemment aucune donnée les concernant.",
                ]
            ),
            Section(
                heading: "Vos droits",
                paragraphs: [
                    "La loi fédérale suisse sur la protection des données s'applique, ainsi que le règlement général sur la protection des données si vous résidez dans l'Union européenne : accès, rectification, effacement, portabilité et opposition.",
                    "Ces droits sont ici d'un exercice direct : puisque vos données sont sur votre appareil et nulle part ailleurs, c'est vous qui les consultez, les modifiez et les supprimez, dans l'app, sans avoir à en demander la permission. Pour la seule photo qui transite par le relais, écrivez-nous.",
                ]
            ),
            Section(
                heading: "Modifications",
                paragraphs: [
                    "Si ce texte change, la date indiquée en haut change avec lui, et la version qui vous engage est toujours celle que vous lisez dans l'app.",
                ]
            ),
        ],
        contactParagraph: "Pour toute question sur ce texte ou sur vos données, écrivez-nous."
    )
}
