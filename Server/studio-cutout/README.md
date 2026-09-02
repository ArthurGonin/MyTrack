# Finition studio des photos de véhicule

Un proxy de quarante lignes entre l'app et l'API images d'OpenAI. Il existe parce que la clé
OpenAI ne peut pas vivre dans l'app : embarquée dans un binaire iOS, elle se lit en deux
minutes. Le prompt vit ici aussi — l'améliorer ne demande pas de republier sur l'App Store.

**Sans lui, la fonctionnalité n'existe pas.** C'est le modèle d'OpenAI qui détoure, allume la
lumière de studio, efface les reflets des vitres et redresse la perspective ; l'app ne sait
faire aucune de ces quatre choses toute seule. Tant que `StudioCutoutConfiguration` est vide,
prendre une photo affiche « La retouche photo n'est pas disponible ».

## D'abord, le compte OpenAI

Trois choses, dans cet ordre, sur `platform.openai.com` — rien à voir avec un abonnement
ChatGPT, qui ne donne aucun accès à l'API et se facture à part :

1. **Créditer le compte.** L'API est prépayée. Sans crédit, chaque appel revient en 429, que
   l'app traduit par « Vous avez atteint la limite de photos du jour » — un message faux, mais
   c'est bien de crédit qu'il s'agit.
2. **Vérifier l'organisation** (*Settings → Organization → General → Verify Organization*).
   Les modèles GPT Image l'exigent ; sans elle, l'appel est refusé quel que soit le crédit.
3. **Poser un plafond de dépense mensuel** (*Settings → Limits*). C'est la seule limite qu'un
   attaquant ne peut pas contourner.

La clé se crée ensuite dans *API keys*, et ne se réaffiche jamais : copiez-la tout de suite.

## Essayer avant de déployer

Pour voir le résultat ce soir, sans compte Cloudflare : posez une clé OpenAI dans
`StudioCutoutConfiguration.debugOpenAIKey` et lancez l'app depuis Xcode. L'app appelle alors
OpenAI directement, avec la copie du prompt qui est dans ce même fichier.

Ce raccourci est enfermé dans `#if DEBUG` : une compilation Release n'en contient pas une
ligne, donc la clé ne peut pas partir sur l'App Store même en l'oubliant remplie. Ne la
laissez pas non plus dans un commit — c'est la même clé que celle qui facture.

## Déployer

```sh
cd Server/studio-cutout
npm install -g wrangler          # une fois
wrangler login                   # une fois

wrangler kv namespace create QUOTA
#   → recopier l'identifiant affiché dans wrangler.toml

wrangler secret put OPENAI_API_KEY
wrangler secret put MYTRACK_SHARED_SECRET   # une phrase au hasard, la même que dans l'app

wrangler deploy
```

Le déploiement affiche l'adresse, de la forme
`https://mytrack-studio.<votre-compte>.workers.dev`.

## Brancher l'app

Dans `MyTrack/Services/StudioCutoutConfiguration.swift` :

```swift
static let endpoint = "https://mytrack-studio.<votre-compte>.workers.dev"
static let sharedSecret = "<le même mot que ci-dessus>"
```

Ces deux lignes remplies, l'app passe par le proxy et ignore la clé de debug. Videz cette
dernière au passage : elle ne servira plus.

## Vérifier avant de toucher à l'app

```sh
curl -sX POST https://mytrack-studio.<votre-compte>.workers.dev \
  -H "X-MyTrack-Secret: <le secret>" \
  -H "X-MyTrack-Device: test" \
  -F photo=@voiture.jpg \
  | python3 -c "import sys,json,base64;open('resultat.png','wb').write(base64.b64decode(json.load(sys.stdin)['data'][0]['b64_json']))"
```

Le proxy rend le JSON d'OpenAI, l'image en base64 dedans ; la ligne Python en sort le fichier.
Un PNG de 1536 × 1024 avec un vrai canal alpha doit en tomber. Posez-le sur un fond **noir**
autant que sur un fond blanc : un halo blanc ne se voit que sur le noir.

## Garde-fous

- **Secret partagé** : il est dans l'app, donc extractible. Il écarte les appels au hasard,
  rien de plus. App Attest ferait mieux le jour où le volume le justifiera.
- **Cinq photos par appareil et par jour**, comptées dans KV (`DAILY_LIMIT` dans
  `worker.ts`). Le compteur ne monte qu'une fois l'image obtenue : un appel raté ne coûte pas
  son quota. Au-delà, le proxy répond 429 et l'app dit « Réessayez demain ».
- **Le plan gratuit de Cloudflare suffit**, et doit continuer de suffire. Dix millisecondes de
  processeur par requête, l'attente du réseau non comptée : ce proxy en consomme deux, parce
  qu'il ne lit jamais l'image qu'il transporte. Lui faire décoder le base64 est précisément ce
  qui ferait sauter ce budget — c'est pour ça que l'app s'en charge.
- **Posez un plafond de dépense mensuel sur la clé OpenAI**, dans votre tableau de bord. C'est
  la seule limite qu'un attaquant ne peut pas contourner.
- **La photo quitte l'appareil.** À déclarer dans la politique de confidentialité et dans la
  fiche App Store.

## Le modèle, et sa date de péremption

Confronté à la documentation d'OpenAI le **2 septembre 2026** :

- `gpt-image-1`, sur quoi ce proxy était écrit, **s'arrête le 23 octobre 2026**. D'où
  `gpt-image-2`, son remplaçant désigné, ici comme dans le mode debug de l'app.
- Les paramètres tiennent tels quels : `size=1536x1024`, `quality=high`, `background=transparent`,
  `output_format=png`. Le fond transparent demande toujours du PNG (ou du WebP), jamais du JPEG.
- `input_fidelity` n'a pas à être envoyé : `gpt-image-2` ne le laisse pas régler.

Refaites cette confrontation avant chaque déploiement — un modèle d'images a la durée de vie
d'un yaourt. Le mode debug de l'app journalise la réponse d'OpenAI en cas de refus (catégorie
`recording` dans Console) : c'est là que se lit un paramètre devenu faux.
