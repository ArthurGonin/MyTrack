# Ce qu'il reste à faire

État au 6 septembre 2026, après la passe de revue complète du code et le croisement avec
l'état réel du dépôt. Rangé par ce qui bloque quoi, et non par difficulté.

---

## Bloquant pour une soumission App Store — dans le code

- [ ] **Retirer le bloc `TEMP-PREDICATE-TEST`** (`MyTrack/MyTrackApp.swift`). Il vérifiait si
      `#Predicate` sait comparer une propriété d'énumération à un cas. Plus gênant qu'il n'en a
      l'air : seul le *semis* est gardé par la clé `seedPredicateTest`, mais le `fetch` de toute
      la table `Trip` et la ligne de journal, eux, tournent à **chaque lancement** — y compris
      en production, pour rien.
- [ ] **Commiter le travail en cours.** Le plan de migration, le popup d'avis et le reste vivent
      dans l'arbre de travail, pas dans l'historique.
- [x] **Renseigner `LegalContact.email`** — vaut `contact@kiwijuice.dev`. Les conditions
      d'utilisation et la politique de confidentialité affichent donc leur section de contact,
      que le RGPD et la nLPD attendent.
- [x] **Écrire un `SchemaMigrationPlan`.** `MyTrackSchemaV1` fige la V1.0.0 sur les cinq modèles
      (`Trip`, `Vehicle`, `UserProfile`, `ReportProfile`, `GeneratedReport`) et
      `MyTrackMigrationPlan` la porte ; `MyTrackApp.makeContainer` ouvre le magasin à travers
      lui. Restait à faire **avant** la première version publique, et ça l'est — voir la section
      « Une fois publié » pour ce que ça engage ensuite.
- [x] **Vérifier la déclaration de chiffrement.** `ITSAppUsesNonExemptEncryption = false` est
      dans l'`Info.plist` : l'app n'emploie que HTTPS, qui relève de l'exemption. À reconfirmer
      si un jour elle chiffre autre chose elle-même.

## Bloquant pour une soumission — dans App Store Connect

Rien de ce qui suit n'est du code, et c'est précisément pourquoi ça s'oublie.

- [ ] **Publier la politique de confidentialité à une URL.** App Store Connect la réclame dans
      les métadonnées de la fiche, et le texte embarqué dans l'app ne l'en dispense pas. C'est
      le même texte : voir `LegalDocument+PrivacyPolicy.swift`.
- [ ] **Créer les trois produits d'achat**, aux identifiants exacts que `PurchaseService`
      demande : `KiwiJuice.MyTrack.monthly`, `KiwiJuice.MyTrack.annual`,
      `KiwiJuice.MyTrack.lifetime`. Ils sont examinés **avec** la première version : oubliés, la
      soumission part sans rien à vendre, et l'app entière est payante.
- [ ] **Écrire les notes de revue (App Review Information).** Le plus gros risque de rejet, et
      il n'a rien à voir avec le code. L'app est entièrement payante et son cœur — la détection
      automatique — ne se déclenche qu'en voiture ; l'examinateur est assis dans un bureau et
      verrait une paywall, puis une app qui « ne fait rien ». Lui dire : d'acheter en bac à
      sable, d'utiliser le bouton **Démarrer** manuel pour voir un trajet s'enregistrer, et que
      la détection automatique exige Core Motion et un déplacement réel.
- [ ] **Justifier `UIBackgroundModes: location`** dans ces mêmes notes — guideline 2.5.4, un
      service d'arrière-plan doit servir l'objet déclaré. Le cas est légitime, encore faut-il
      l'écrire.
- [ ] **Remplir le questionnaire App Privacy** : position précise, photos, et l'identifiant
      d'appareil pour l'éditeur (`identifierForVendor`) dont le relais se sert comme compteur.
      Tout est déjà décrit dans `LegalDocument+PrivacyPolicy.swift`, y compris le transfert à
      OpenAI et le traitement aux États-Unis : il n'y a qu'à le reporter.
- [ ] **Renseigner l'URL d'assistance (Support URL).** Champ obligatoire de la fiche, et
      guideline 1.5 : « votre app *et* son URL d'assistance doivent offrir un moyen simple de
      vous joindre ». La page doit être publique, sans compte à créer, propre à cette app — ni
      une page d'accueil marketing, ni un profil de réseau social — et porter au moins un canal
      qui fonctionne : adresse, formulaire ou téléphone. Le formulaire « Envoyer un commentaire »
      des réglages couvre déjà la moitié « dans l'app » de cette exigence.
- [ ] **Captures d'écran, description, mots-clés, catégorie.**

## Déploiement en attente

- [ ] **Déployer le proxy de détourage.** Le code du dépôt est corrigé, le worker en ligne
      tourne encore l'ancien — avec un quota contournable par un simple en-tête.
      ```sh
      cd Server/studio-cutout && wrangler deploy
      ```
      Si `[[ratelimits]]` est refusé par wrangler, retirer le bloc : le worker le lit sous
      `if (env.BURST)` et tourne à l'identique sans lui.
- [ ] **Poser un plafond de dépense mensuel sur la clé OpenAI**
      (*platform.openai.com → Settings → Limits*). C'est la seule limite qu'un attaquant ne
      peut pas contourner, et le seul garde-fou qui ne dépende pas de notre code. Cesse d'être
      optionnel le jour de la mise en vente : le relais devient alors une cible publique.
- [x] **Confronter le modèle d'images à la documentation d'OpenAI** — fait le 5 septembre 2026.
      `gpt-image-2` n'est ni déprécié ni annoncé pour l'arrêt, et c'est le remplaçant désigné de
      tous les autres. À refaire avant chaque déploiement ; détails dans
      `Server/studio-cutout/README.md`.

## À tester dans l'app — rien de ce qui suit n'a été exercé à l'exécution

Les corrections de la revue sont vérifiées **par compilation**, pas par un lancement. À
exercer une fois :

- [ ] Supprimer un profil de rapport depuis ses réglages — c'était un crash.
- [ ] Un trajet auto-détecté de bout en bout : vérifier que **distance et durée décrivent la
      même fenêtre** (les minutes de la fenêtre d'arrêt étaient comptées dans la distance).
- [ ] **Les nouveaux seuils de la détection.** Un trajet est réel s'il fait plus de 300 m — la
      durée ne compte plus — et la fenêtre d'arrêt vaut 90 s si Core Motion dit qu'on marche,
      3 min s'il dit seulement qu'on ne bouge plus. À exercer : se garer et s'éloigner à pied
      (la notification doit arriver dans la minute et demie, pas cinq minutes plus tard) ;
      déplacer la voiture sur cent mètres (rien ne doit apparaître) ; s'arrêter cinq minutes en
      chemin (deux trajets, à fusionner si on veut — c'est délibéré, un trajet d'un seul tenant
      étant insécable).
- [ ] **Un vrai trajet, téléphone verrouillé dans la poche.** Le GPS enregistre désormais en
      continu (une mesure par seconde) au lieu d'un point tous les dix mètres, et rien de ce
      qui rend ça possible ne s'exerce au simulateur : ni la suspension de l'app, ni Core
      Motion, ni la session d'activité en arrière-plan. Deux chiffres à lire dans la Console,
      catégorie `recording` : la ligne « Trip finalized: N GPS point(s) over Ns » — N doit
      valoir à peu près la durée en secondes, pas une dizaine — et l'absence de « No location
      delivered for Ns ». La pastille bleue doit rester allumée tout le trajet ; si elle
      s'éteint, c'est l'arrière-plan qu'il faut regarder, pas le filtre.
- [ ] **Le popup d'avis, aux deux moments qui l'arment.** Ouvrir le détail d'un trajet, y rester
      plus de cinq secondes, revenir : les étoiles doivent arriver une seconde et demie plus
      tard, sur la liste. Puis, la demande dépensée, vérifier qu'un rapport lu ne la relance
      pas — les 90 jours d'écart. Le popup lui-même est vérifié (il s'affiche, les compteurs se
      persistent), ce sont les deux `onChange` qui l'arment qui ne se pilotent pas en ligne de
      commande, faute d'injection de touches. **En build Xcode uniquement** : l'appel est ignoré
      en TestFlight, et n'y affiche jamais rien.
- [ ] **Le rapport périodique, de la notification au PDF.** Le reste de la chaîne est vérifié au
      simulateur — l'échéance dépassée déclenche bien la génération à l'ouverture, le PDF porte
      les bons trajets et les bons totaux, `nextDueDate` avance, les trois échéances suivantes
      s'arment, et l'onglet Rapports s'ouvre avec la pastille. Restent les deux bouts que la
      ligne de commande ne touche pas : la **livraison** de la notification à l'heure dite, et
      le **vrai appui** dessus — les trois lignes du delegate qui lèvent `shouldOpenReportsTab`.
- [ ] Répondre « Non » dans l'écran de revue, puis appuyer « Oui » sur la notification restée
      affichée : le trajet ne doit **pas** revenir.
- [ ] Supprimer le compte, relancer : langue et unité doivent repartir sur celles du système.
- [ ] Photographier un véhicule (le décodage de l'image a changé de chemin), et refuser
      l'accès caméra pour voir le message et le bouton Réglages.
- [ ] Ouvrir l'app **hors ligne** avec un abonnement actif : aucune notification
      « abonnement expiré » ne doit partir.
- [ ] Créer un rapport sans abonnement : la feuille doit montrer l'écran d'abonnement requis.
- [ ] Trier la liste par durée pendant un enregistrement, puis balayer une ligne : c'est le
      bon trajet qui part à la corbeille.

## Une fois publié

- [ ] **Renseigner `appStoreID`** (`MyTrack/Views/Account/AccountSettingsView.swift`) et livrer
      une 1.0.1. Jusque-là la ligne « Laisser un avis » reste désactivée — volontairement,
      plutôt que d'ouvrir un lien mort. Le popup à étoiles, lui, n'a pas besoin de cet
      identifiant et fonctionne dès la première version.
- [ ] **Ne juger le popup d'avis qu'en production.** Il ne s'affiche jamais en TestFlight ; en
      App Store, Apple le plafonne à trois fois par 365 jours et l'utilisateur peut le couper
      dans *Réglages → App Store*. `ReviewPromptService` en dépense deux au maximum, à 90 jours
      d'écart. Aucune de ces demandes ne rend de résultat : la seule trace est la ligne
      `AppLog.purchases`.
- [ ] **Surveiller les plantages** dans Xcode → Window → Organizer. C'est là que les seuils de
      `DrivingDetector` et le comportement en arrière-plan se feront juger par la réalité,
      et non par le simulateur qui ne sait reproduire ni l'un ni l'autre.
- [ ] **Répondre aux avis** dans App Store Connect, les mauvais d'abord : c'est public, et
      c'est ce qui remonte une note.
- [ ] **`MyTrackSchemaV1` est gelé** à partir de la version publique. Toute modification d'un
      `@Model` demandera désormais une `MyTrackSchemaV2` et une `MigrationStage` dans
      `MyTrackMigrationPlan` — la règle des propriétés optionnelles du CLAUDE.md ne suffira plus
      seule pour un changement lourd. C'est exactement pourquoi figer la V1 avant était
      bloquant.

## Dette technique

- [ ] **Treize avertissements de concurrence**, et non zéro comme l'affirmaient ce fichier et le
      CLAUDE.md jusqu'au 6 septembre : onze dans `CameraPreview.swift` (`session` et `output`
      touchés depuis un contexte non isolé) et deux dans `NotificationService.swift`
      (`UNUserNotificationCenter` n'est pas `Sendable`). Rien qui bloque une soumission. Ils se
      cachent parce que l'`xcodebuild` incrémental n'en émet aucun pour un fichier qu'il ne
      recompile pas : pour les revoir, `touch` ces deux fichiers avant de rebuilder.
- [ ] **Aucune cible de tests.** `ReportPeriodBoundary`, `TripFormatting`, `Trip+Cost` et
      `VehicleDraft.number(from:)` sont du code pur, sans dépendance système, testables tels
      quels — c'est là que le rapport effort/valeur est le meilleur. `DrivingDetector` vient
      juste après : 600 lignes de machine à états, la pièce la plus difficile à raisonner et la
      seule sans filet.
- [ ] **`hasPendingTrips` charge toute la table** (`RootTabView`). Un `fetchCount` avec
      prédicat compile, mais rien ne prouve que SwiftData sache traduire un prédicat sur une
      propriété d'énumération — et un `0` rendu à tort empêcherait l'écran de revue de s'ouvrir
      sans une ligne dans les journaux. À reprendre seulement avec une vérification à
      l'exécution en main.
- [x] **`ReportProfileEditView` sauvegardait à chaque frappe** dans le champ du nom. Le profil
      change toujours à chaque touche — c'est ce qui garde le live-edit — mais l'écriture sur le
      disque et la replanification de la notification attendent que le champ perde le focus ou
      que l'écran s'en aille.
- [ ] **Faire tourner les deux secrets partagés** (`StudioCutoutConfiguration`,
      `FeedbackConfiguration`) si le dépôt devient public. Ils sont en clair dans
      l'historique git — assumé et documenté, mais l'hypothèse change avec la visibilité.
- [x] **`notifySubscriptionLapsed` ne parlait que des trajets.** Les deux textes nomment
      désormais l'enregistrement *et* la création de rapports, sans s'allonger : la dernière
      phrase reste ce qu'on veut savoir d'abord — ce qui est déjà enregistré ne disparaît pas.
- [ ] **Clé de traduction orpheline** : « Distance totale », ajoutée à la main et plus
      utilisée. Gardée parce que quelqu'un l'a voulue là ; à retirer si elle ne sert plus.
- [x] **`TripListView` recalculait `trips` plusieurs fois par rendu** (filtre + tri). Les listes
      sont désormais relevées une fois en tête du corps et passées de main en main, sur le
      modèle de `MonthlySummary`.

## Décisions prises, notées pour mémoire

- **iPhone seul.** `TARGETED_DEVICE_FAMILY = 1` : la mise en page est calée sur l'iPhone
  (gélule de barre d'onglets mesurée sur la fenêtre, débord de la voiture) et la plupart des
  iPad n'ont pas de coprocesseur de mouvement — donc pas de détection automatique, la moitié de
  ce que l'abonnement paie.
- **L'abonnement paie ce qui est *nouveau*** : enregistrer un trajet, le détecter, générer un
  rapport — ponctuel comme périodique. Tout ce qui existe déjà reste accessible, PDF compris.
  On ne prend pas en otage des données déjà créées.
- **La porte de sortie de la paywall est gardée**, mais resserrée aux refus définitifs : achats
  restreints, produit absent de la boutique du pays, ou boutique qui n'a rien à vendre. Un
  achat simplement échoué ne l'ouvre plus. Elle est nécessaire — une app qui ne s'ouvre pas se
  fait refuser à la revue — et elle ne donne rien de payant : `canRecordTrips` reste faux
  derrière.
- **Le magasin illisible est mis de côté, pas effacé.** Voir `MyTrackApp.makeContainer`.
- **`SWIFT_STRICT_CONCURRENCY = complete`** est activé, et c'est ce qui empêche la dette de
  concurrence de revenir. Le projet n'est pas pour autant à zéro avertissement : voir la dette
  technique ci-dessus.
- **Le moment de la demande d'avis** est le *retour* d'un écran de satisfaction, jamais l'écran
  lui-même : les étoiles ne doivent pas se poser sur la carte qu'on regarde. Voir
  `ReviewPromptService`.
