//
//  LegalDocument+TermsOfUse.swift
//  MyTrack
//
//  Les conditions d'utilisation, qui tiennent aussi lieu de contrat de licence
//  utilisateur final — c'est l'« EULA » que la règle App Review 3.1.2 exige d'un
//  écran d'achat.
//
//  Deux sections ne sont pas décoratives et ne doivent pas disparaître à la
//  relecture. « Ce que l'app mesure » est ce qui rend l'app honnête : un carnet
//  de trajets sert à des notes de frais et à des déductions, et promettre une
//  exactitude que le GPS ne tient pas serait le pire mensonge que cette app
//  puisse faire. « Le rôle d'Apple » reprend les clauses minimales qu'Apple
//  impose à tout contrat de licence maison (annexe 1 de l'accord du programme
//  développeur) : sans elles, la revue peut refuser l'app.
//

import SwiftUI

extension LegalDocument {
    static let termsOfUse = LegalDocument(
        title: "Conditions d'utilisation",
        sections: [
            Section(
                heading: "En bref",
                paragraphs: [
                    "MyTrack est un carnet de trajets automatique. Vous payez pour enregistrer de nouveaux trajets ; ce que vous avez déjà enregistré vous reste acquis. Vos données sont sur votre appareil et vous appartiennent.",
                    "L'app mesure et vous aide à tenir vos comptes, elle ne les certifie pas. Ce qu'elle produit reste à vérifier avant tout usage professionnel ou fiscal.",
                ]
            ),
            Section(
                heading: "Qui vous fournit l'app",
                paragraphs: [
                    "MyTrack est éditée et fournie par KiwiJuice, en Suisse, et distribuée par l'App Store d'Apple. Ces conditions forment le contrat entre vous et KiwiJuice.",
                ]
            ),
            Section(
                heading: "Votre accord",
                paragraphs: [
                    "En installant ou en utilisant MyTrack, vous acceptez ces conditions. Si vous ne les acceptez pas, n'utilisez pas l'app.",
                ]
            ),
            Section(
                heading: "Ce que vous avez le droit de faire",
                paragraphs: [
                    "KiwiJuice vous accorde un droit d'usage personnel, non exclusif et non transférable de MyTrack sur les appareils Apple que vous possédez ou contrôlez, dans les limites des règles d'usage de l'App Store.",
                    "Vous ne pouvez ni revendre l'app, ni la louer, ni la décompiler, ni en extraire le code, ni contourner les limites du service de photo, ni vous en servir à d'autres fins que celles prévues ici.",
                ]
            ),
            Section(
                heading: "Ce qu'il faut pour que ça marche",
                paragraphs: [
                    "Un iPhone et une version d'iOS prise en charge. Le suivi automatique demande en plus l'accès à la position réglé sur « Toujours » et l'accès à Motion et forme : sans eux, seuls les trajets que vous démarrez vous-même sont enregistrés.",
                ]
            ),
            Section(
                heading: "Abonnements et achat unique",
                paragraphs: [
                    "MyTrack se paie de trois façons : un abonnement mensuel, un abonnement annuel, ou un achat unique qui ouvre l'accès définitivement. Les prix sont affichés dans l'app, dans votre devise, avant tout paiement.",
                    "Les abonnements se reconduisent automatiquement. Votre compte App Store est débité dans les vingt-quatre heures qui précèdent chaque échéance, sauf résiliation au moins vingt-quatre heures avant celle-ci. La reconduction se gère et se résilie dans les réglages de votre compte App Store, jamais depuis KiwiJuice.",
                    "Quand l'offre annuelle comporte un essai gratuit, sa durée est annoncée sur l'écran d'achat. Souscrire un abonnement pendant un essai en cours met fin à la partie non utilisée de cet essai.",
                    "L'achat unique ne se reconduit pas et n'expire pas.",
                    "Payer ouvre l'enregistrement de nouveaux trajets. Si votre accès prend fin, vos trajets, véhicules et rapports déjà enregistrés restent consultables et exportables.",
                    "Les paiements et les remboursements sont traités par Apple : une demande de remboursement se fait auprès de l'assistance Apple, selon ses conditions.",
                ]
            ),
            Section(
                heading: "Ce que l'app mesure, et ce qu'elle ne garantit pas",
                paragraphs: [
                    "Les distances et les tracés sont calculés à partir du GPS de l'iPhone. Leur précision dépend du signal : un tunnel, un parking souterrain ou une rue étroite entre de hauts immeubles dégradent la mesure, et un trajet peut s'en trouver plus court ou plus long qu'il ne l'a été.",
                    "La détection automatique repose sur les capteurs de mouvement. Elle peut manquer un trajet, en couper un en deux, ou en détecter un alors que vous étiez passager, dans un bus ou dans un train. C'est pour cela que l'app vous demande de confirmer, et c'est à vous de corriger ce qu'elle propose.",
                    "Les coûts affichés sont des estimations, calculées à partir de la consommation et du prix de l'énergie que vous saisissez vous-même.",
                    "MyTrack n'est ni un conseil fiscal, ni un conseil comptable, et ses rapports ne sont pas des pièces certifiées. Si vous vous en servez pour une note de frais, une déduction ou un contrôle, vous restez seul responsable de leur exactitude et de leur conformité aux règles qui vous concernent.",
                ]
            ),
            Section(
                heading: "Au volant",
                paragraphs: [
                    "Réglez ce que vous avez à régler avant de partir. Ne manipulez pas l'app en conduisant, et respectez le code de la route du pays où vous roulez : il passe toujours avant MyTrack.",
                ]
            ),
            Section(
                heading: "Ce que vous mettez dans l'app",
                paragraphs: [
                    "Les photos, les noms de véhicules, les plaques et les informations de votre profil restent les vôtres. En prenant une photo de véhicule, vous autorisez sa transmission au prestataire de détourage pour ce seul traitement, décrit dans la politique de confidentialité.",
                    "Ne photographiez que ce que vous avez le droit de photographier, et n'envoyez rien d'illicite. Le service de photo est plafonné à quelques images par jour et peut être interrompu : l'app reste utilisable sans lui.",
                ]
            ),
            Section(
                heading: "Ce qui appartient à KiwiJuice",
                paragraphs: [
                    "L'app, son nom, son icône, ses textes et ses dessins appartiennent à KiwiJuice. Rien dans ces conditions ne vous en transfère la propriété.",
                ]
            ),
            Section(
                heading: "Garantie et responsabilité",
                paragraphs: [
                    "MyTrack est fournie en l'état et selon sa disponibilité. Dans les limites permises par le droit applicable, KiwiJuice ne répond pas des dommages indirects, d'une perte de données ni d'un manque à gagner résultant de l'usage de l'app.",
                    "Rien ici n'écarte la responsabilité en cas de faute grave ou intentionnelle, ni en cas d'atteinte à la vie ou à l'intégrité corporelle. Si vous êtes consommateur, les droits que la loi de votre pays vous reconnaît restent entiers.",
                ]
            ),
            Section(
                heading: "Vos données, et qui en est le gardien",
                paragraphs: [
                    "MyTrack ne garde aucune copie de vos trajets ailleurs que sur votre appareil. Un iPhone perdu, cassé ou effacé sans sauvegarde emporte donc vos trajets avec lui : sauvegardez votre appareil si ces données comptent pour vous.",
                ]
            ),
            Section(
                heading: "Résiliation",
                paragraphs: [
                    "Vous pouvez cesser d'utiliser MyTrack à tout moment en supprimant l'app ; la résiliation d'un abonnement se fait, elle, dans les réglages de votre compte App Store. KiwiJuice peut cesser de proposer l'app ou l'une de ses fonctions, en vous prévenant dans un délai raisonnable lorsque c'est possible.",
                ]
            ),
            Section(
                heading: "Le rôle d'Apple",
                paragraphs: [
                    "Ces conditions vous lient à KiwiJuice et non à Apple : Apple n'est pas partie à ce contrat et n'est responsable ni de MyTrack, ni de son contenu. Apple n'est tenue à aucune obligation d'assistance ni de maintenance sur l'app.",
                    "Si l'app se révélait non conforme à une garantie applicable, vous pouvez le signaler à Apple, qui vous en remboursera le prix d'achat ; au-delà de ce remboursement, Apple n'assume aucune autre obligation. Toute réclamation relative à l'app — responsabilité du fait du produit, conformité réglementaire, propriété intellectuelle — relève de KiwiJuice. Apple et ses filiales sont tiers bénéficiaires de ces conditions et peuvent s'en prévaloir.",
                ]
            ),
            Section(
                heading: "Modifications",
                paragraphs: [
                    "Ces conditions peuvent évoluer. La date indiquée en haut désigne la version en vigueur, et c'est toujours celle que vous lisez dans l'app qui s'applique.",
                ]
            ),
            Section(
                heading: "Droit applicable",
                paragraphs: [
                    "Ces conditions sont régies par le droit suisse, et les tribunaux du siège de KiwiJuice sont compétents. Si vous êtes consommateur, cela ne vous prive ni de la protection des dispositions impératives du droit de votre pays de résidence, ni de la possibilité d'agir devant les tribunaux de ce pays.",
                ]
            ),
        ],
        contactParagraph: "Pour toute question sur ces conditions, écrivez-nous."
    )
}
