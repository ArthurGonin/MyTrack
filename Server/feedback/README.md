# Le courrier que les réglages envoient

Un relais d'une soixantaine de lignes entre l'app et votre boîte aux lettres. L'app y poste un
titre et un texte ; il en fait un courriel.

**Il n'y a aucune clé d'API nulle part**, et c'est ce qui distingue ce relais de celui du
détourage. Cloudflare envoie le courrier lui-même, par le lien `send_email` d'Email Routing —
pas de service de messagerie tiers, pas de compte de plus, et les envois vers une adresse de
destination vérifiée de votre compte sont **gratuits et hors quota**. Ce qui est exactement le
cas ici : la seule destination d'un formulaire de commentaires, c'est vous.

**L'app n'envoie jamais de destinataire.** Elle poste `{"subject", "message"}` et rien d'autre.
L'expéditeur et la boîte qui reçoit vivent dans les secrets du relais. C'est ce qui l'empêche
de servir à écrire ailleurs : même le secret partagé en main, on ne peut rien faire de plus que
vous écrire.

Tant que `FeedbackConfiguration` est vide, l'app répond « L'envoi de commentaires n'est pas
disponible dans cette version » plutôt que d'avaler le message en silence.

## D'abord, le domaine

Il faut un domaine dont les DNS sont chez Cloudflare — un sous-domaine `workers.dev` ne suffit
pas. Dans le tableau de bord, dans cet ordre :

1. **Activer Email Routing sur le domaine** : *Compute → Email Service → Email Routing →
   Onboard Domain*. Cloudflare pose lui-même les MX et le SPF. Comptez cinq à quinze minutes
   de propagation.
2. **Vérifier l'adresse de destination** : *Email Routing → Destination Addresses*, saisir
   votre boîte, ouvrir le courriel reçu, **Verify email address**. C'est cette confirmation
   qui rend l'envoi gratuit et hors quota ; sans elle, le lien n'a le droit d'écrire à
   personne (`E_RECIPIENT_NOT_ALLOWED`).
3. **Choisir l'adresse d'émission**, sur ce domaine — par exemple `feedback@votre-domaine`.
   Elle n'a pas besoin d'exister comme boîte : c'est une adresse d'émission.

**Et une quatrième étape, qui n'a rien à voir avec les DNS.** Le Worker doit être déployé
**sur le compte Cloudflare qui possède le domaine** : un Worker n'a le droit d'émettre que
depuis un domaine de son propre compte. Déployé ailleurs, il rend un `502 Envoi refusé :
E_SENDER_DOMAIN_NOT_AVAILABLE`, un message qui envoie chercher du côté des enregistrements DNS
alors qu'ils sont parfaits. `wrangler email routing list` tranche en une seconde : si le
domaine n'y figure pas, c'est le mauvais compte.

**La page *Email Sending* du tableau de bord ne concerne pas ce relais.** Elle réclame le plan
Workers Paid, mais elle sert à écrire à des destinataires quelconques. Écrire à une adresse de
destination vérifiée de son propre compte reste gratuit sur tous les plans, Email Routing seul
suffit — la page tarifaire de Cloudflare le dit mot pour mot. Il n'y a rien à acheter.

## Déployer

```sh
cd Server/feedback
wrangler kv namespace create FEEDBACK_QUOTA
#   → recopier l'identifiant affiché dans wrangler.toml

# Tout ce qui suit vise le compte qui possède le domaine — voir le piège ci-dessus.
# Avec plusieurs comptes Cloudflare : « wrangler auth create <profil> » une fois,
# puis « --profile <profil> » sur chaque commande, et CLOUDFLARE_ACCOUNT_ID réglé
# sur l'identifiant du bon compte.

# Piper la valeur plutôt que la coller : l'invite masquée de wrangler avale un
# collage et enregistre une chaîne vide sans se plaindre, et l'erreur ne se voit
# qu'à l'appel suivant.
printf '%s' '<une phrase au hasard>'  | wrangler secret put MYTRACK_SHARED_SECRET --name mytrack-feedback
printf '%s' 'feedback@votre-domaine'  | wrangler secret put FEEDBACK_SENDER      --name mytrack-feedback
printf '%s' 'vous@votre-boite'        | wrangler secret put FEEDBACK_RECIPIENT   --name mytrack-feedback

wrangler deploy
```

Le déploiement affiche l'adresse, de la forme
`https://mytrack-feedback.<votre-compte>.workers.dev`.

Le secret partagé doit être **différent** de celui du détourage : deux relais, deux mots, pour
qu'un seul divulgué n'ouvre pas l'autre.

## Brancher l'app

Dans `MyTrack/Services/FeedbackConfiguration.swift` :

```swift
static let endpoint = "https://mytrack-feedback.<votre-compte>.workers.dev"
static let sharedSecret = "<le même mot que ci-dessus>"
```

## Vérifier avant de toucher à l'app

```sh
curl -si -X POST https://mytrack-feedback.<votre-compte>.workers.dev \
  -H "X-MyTrack-Secret: <le secret>" \
  -H "Content-Type: application/json" \
  -d '{"subject":"MyTrack — essai","message":"ceci est un essai"}'
```

Attendu : `200` et `Message transmis`, puis le courriel dans votre boîte en quelques secondes.
L'objet ne doit porter **qu'un seul** « MyTrack — », les sauts de ligne de la signature doivent
être intacts, et la dernière ligne dire que le message est anonyme.

Les refus comptent autant que le succès. Aucun n'envoie de courrier ni ne consomme de quota :

| Ce qu'on envoie | Réponse |
|---|---|
| Un `GET` | `405 Method not allowed` |
| Un mauvais secret | `403 Forbidden` |
| Un corps de plus de 64 Ko | `413 Corps trop long` |
| Du JSON illisible | `400 JSON illisible` |
| Un corps sans `subject` ou sans `message` | `400 Titre ou message absent` |
| L'un des deux vide après élagage | `400 Titre ou message vide` |
| Un titre de plus de 200 caractères, un message de plus de 10 000 | `413 Message trop long` |
| Quatre messages dans la même minute | `429 Trop de messages en peu de temps` |
| Le onzième message du jour | `429 Daily limit reached` |
| Un expéditeur ou un destinataire non vérifié | `502 Envoi refusé : <code>` |

Ce `502` est le seul qui demande d'être lu. `E_SENDER_DOMAIN_NOT_AVAILABLE` : le domaine
d'émission n'est pas sur le compte du Worker — c'est le plus fréquent, voir la quatrième étape
plus haut. `E_SENDER_NOT_VERIFIED` : le domaine est bien là, mais son émission n'est pas
vérifiée. `E_RECIPIENT_NOT_ALLOWED` : la boîte n'a jamais confirmé son adresse. Le détail
complet est côté serveur, sous `wrangler tail`.

Le plafond quotidien se vérifie en rejouant la commande onze fois, en espaçant d'une vingtaine
de secondes pour ne pas buter d'abord sur le coupe-rafale. Et `wrangler kv key list --binding
QUOTA` ne doit montrer que des clés hexadécimales : aucune adresse IP en clair.

## Garde-fous

- **Secret partagé** : il est dans l'app, donc extractible. Il écarte les appels au hasard,
  rien de plus. Ce qui limite vraiment les dégâts, c'est que le destinataire ne puisse pas être
  choisi par l'appelant, et le plafond ci-dessous.
- **Dix messages par jour et trois par minute**, comptés sur `CF-Connecting-IP`, que
  Cloudflare pose lui-même sur la requête : un appelant ne peut pas le falsifier. C'est
  délibérément autre chose que le relais du détourage, qui compte sur un en-tête fourni par le
  client — donc sur une valeur que celui qui voudrait le contourner choisit lui-même.
- **L'adresse IP n'est jamais stockée.** La clé de quota est une empreinte SHA-256 salée par le
  secret partagé, tronquée à seize caractères. Salée, parce qu'un SHA-256 nu d'une IPv4 se
  casse par force brute en quelques secondes.
- **Le coupe-rafale passe avant KV**, et c'est l'ordre qui compte : KV est à cohérence
  éventuelle, donc cent requêtes lancées ensemble y liraient toutes le même compteur à zéro.
  Ce que ces plafonds arrêtent, c'est un script qui a extrait le secret et veut remplir la
  boîte ; ils n'arrêtent pas un attaquant réparti sur mille adresses. Contre celui-là, la
  différence avec le relais du détourage est décisive : **ici une inondation ne coûte pas
  d'argent**, seulement du bruit, et le levier d'urgence est `wrangler delete`.
- **Le compteur ne monte qu'une fois le courrier parti** : un envoi raté ne coûte pas son quota
  à quelqu'un qui n'y est pour rien.
- **Aucune adresse de réponse.** L'app ne demande pas la sienne à l'utilisateur, et n'en joint
  donc aucune : les messages arrivent sans moyen de répondre. C'est un choix, pas un oubli — il
  se change en ajoutant un champ facultatif à la feuille et un `reply_to` ici.
- **Le message quitte l'appareil.** C'est déjà déclaré dans la politique de confidentialité et
  dans `PrivacyInfo.xcprivacy` (`NSPrivacyCollectedDataTypeCustomerSupport`).
