# Ce qu'il reste à faire

État au 4 septembre 2026, après la passe de revue complète du code. Rangé par ce qui
bloque quoi, et non par difficulté.

---

## Bloquant pour une soumission App Store

- [ ] **Renseigner `LegalContact.email`** (`MyTrack/Views/Legal/LegalContact.swift`).
      Tant qu'il vaut `nil`, les conditions d'utilisation et la politique de confidentialité
      s'affichent **sans leur section de contact**. Le RGPD et la nLPD attendent un moyen de
      joindre le responsable : ce n'est pas une préférence, c'est une lacune.
- [ ] **Publier la politique de confidentialité à une URL.** App Store Connect la réclame dans
      les métadonnées de la fiche, et le texte embarqué dans l'app ne l'en dispense pas. C'est
      le même texte : voir `LegalDocument+PrivacyPolicy.swift`.
- [ ] **Renseigner `appStoreID`** (`MyTrack/Views/Account/AccountSettingsView.swift`) une fois
      l'app publiée. La ligne « Laisser un avis » reste désactivée jusque-là — volontairement,
      plutôt que d'ouvrir un lien mort.
- [ ] **Écrire un `SchemaMigrationPlan`** (`MyTrack/MyTrackApp.swift`). Sans lui, tout
      changement de schéma non-léger fait échouer l'ouverture du magasin. Le repli le met
      désormais **de côté** (`.sqlite.<horodatage>.bak`) au lieu de l'effacer, donc plus
      personne ne perd ses trajets en silence — mais l'app repart quand même à vide. Une
      `VersionedSchema` V1 doit être figée **avant** la première version publique : après, il
      sera trop tard pour la déclarer rétroactivement.
- [ ] **Vérifier la déclaration de chiffrement.** `ITSAppUsesNonExemptEncryption = false` a été
      ajouté à l'`Info.plist` : l'app n'emploie que HTTPS, qui relève de l'exemption. À
      confirmer si un jour elle chiffre autre chose elle-même.

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
      peut pas contourner, et le seul garde-fou qui ne dépende pas de notre code.
- [ ] **Confronter le modèle d'images à la documentation d'OpenAI** avant chaque déploiement.
      `gpt-image-1` s'arrête le 23 octobre 2026 ; le proxy est déjà sur `gpt-image-2`. Détails
      dans `Server/studio-cutout/README.md`.

## À tester dans l'app — rien de ce qui suit n'a été exercé à l'exécution

Les corrections de la revue sont vérifiées **par compilation** (Debug, Release et concurrence
stricte, sans un avertissement), pas par un lancement. À exercer une fois :

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

## Dette technique

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
- [ ] **`TripListView` recalcule `trips` plusieurs fois par rendu** (filtre + tri). Le balayage
      vers la corbeille est corrigé, mais la mémoïsation complète reste à faire — celle de
      `RecordTripView` (`MonthlySummary`) sert de modèle.
- [ ] **`ReportProfileEditView` sauvegarde à chaque frappe** dans le champ du nom. Choix
      « live-edit » assumé, mais un `context.save()` par caractère.
- [ ] **Faire tourner les deux secrets partagés** (`StudioCutoutConfiguration`,
      `FeedbackConfiguration`) si le dépôt devient public. Ils sont en clair dans
      l'historique git — assumé et documenté, mais l'hypothèse change avec la visibilité.
- [ ] **`notifySubscriptionLapsed` ne parle que des trajets.** Depuis que la création de
      rapports est aussi derrière l'abonnement, la notification est incomplète — gardée courte
      exprès, mais à revoir si le texte peut s'allonger.
- [ ] **Clé de traduction orpheline** : « Distance totale », ajoutée à la main et plus
      utilisée. Gardée parce que quelqu'un l'a voulue là ; à retirer si elle ne sert plus.

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
- **`SWIFT_STRICT_CONCURRENCY = complete`** est activé : le projet compile sans un seul
  avertissement de concurrence, et c'est ce qui empêche la dette de revenir.
