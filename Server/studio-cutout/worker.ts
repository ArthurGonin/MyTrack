/**
 * MyTrack — finition studio des photos de véhicule.
 *
 * Ce proxy existe pour une seule raison : la clé OpenAI ne peut pas voyager
 * dans l'app. Une clé embarquée dans un binaire iOS se lit en deux minutes, et
 * c'est le crédit de quelqu'un d'autre qui se vide. Elle reste donc ici, et
 * l'app n'envoie qu'une photo.
 *
 * Le prompt aussi vit ici, et c'est délibéré : l'améliorer ne demandera pas de
 * republier sur l'App Store, juste un « wrangler deploy ».
 *
 * Il ne lit jamais l'image qu'il transporte. La réponse d'OpenAI repart telle
 * quelle, en flux, et c'est l'app qui la décode. Ce n'est pas de la paresse :
 * le plan gratuit de Cloudflare accorde dix millisecondes de processeur par
 * requête — l'attente du réseau n'y compte pas, mais décoder plusieurs
 * mégaoctets de base64, si. Un relais qui ne fait que relayer en consomme deux.
 */

/** Le coupe-rafale, quand il est branché — voir `wrangler.toml`. */
interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  OPENAI_API_KEY: string;
  MYTRACK_SHARED_SECRET: string;
  QUOTA: KVNamespace;
  /** Facultatif : le worker tourne à l'identique sans lui. */
  BURST?: RateLimiter;
}

/** Photos par appareil et par jour. Un utilisateur en fait une ou deux.
 *
 *  Ce plafond-là est un confort, pas une défense : l'appareil s'annonce dans un
 *  en-tête que l'appelant choisit, et un UUID neuf à chaque requête le remet à
 *  zéro. Il est gardé parce qu'il empêche une app qui déraille de brûler le
 *  quota d'un foyer entier ; ce qui protège vraiment, c'est celui du dessous. */
const DAILY_LIMIT = 5;

/** Photos par adresse IP et par jour.
 *
 *  Celui-ci est le vrai plafond, parce que `CF-Connecting-IP` est posé par
 *  Cloudflare et écrase ce que le client aurait mis. Plus haut que le précédent
 *  parce qu'une adresse n'est pas une personne : un foyer, ou un opérateur
 *  mobile derrière son NAT, en partage une. Assez large pour une famille, assez
 *  serré pour que le secret extrait du binaire ne donne pas accès au crédit
 *  OpenAI — chaque image se facture. */
const DAILY_IP_LIMIT = 15;

/** De quoi écarter ce qui n'est manifestement pas une photo de voiture, avant
 *  même de lire le corps. `upright()` côté app réduit à 2048 pixels de côté et
 *  réencode en JPEG à 0,85 : cinq mégaoctets laissent de la marge. */
const MAX_BODY = 5 * 1024 * 1024;

const PROMPT = `Turn the attached photo into a product-style cut-out of THIS EXACT CAR,
on a fully transparent background, for use as an app illustration.

SUBJECT — retouch, do not reinvent
· Keep the identical vehicle: same model, body shape, colour, trim, wheel
  design, badges, headlight signature. Do not substitute a different or
  idealised car, do not restyle it.
· Keep its true proportions. Do not stretch, squash or widen the car to fill
  the frame.
· Straight-on front elevation. Camera at headlight height, centred on the car's
  axis, both sides symmetric. If the photo is off-axis, correct the perspective
  to dead-on frontal.
· Rectilinear lens look: no wide-angle bulge, no tilt, no vanishing point.

FINISH
· Even studio lighting: broad soft key from above-front, gentle fill on both
  sides, no hotspots, no lens flare, no colour cast.
· Windscreen and side windows: uniform dark neutral tint. Remove ALL
  reflections — sky, buildings, photographer, interior.
· Clean bodywork: no dust, water spots, scratches or background elements
  reflected in the paint. Keep the paint's own colour and finish.
· No environment: no road, no wall, no floor plane, no gradient, no vignette.

GROUND SHADOW
· One soft elliptical contact shadow directly beneath the car, fading to fully
  transparent at its edges. Neutral grey, 25–35 % opacity at its darkest.

OUTPUT
· PNG, RGBA, real alpha channel, 1536 × 1024 px, landscape.
· Fully transparent everywhere except the car and its shadow.
· No white or grey halo, no matte fringe, no border, no watermark, no text.

FRAMING
· Centre the car horizontally, equal margins left and right.
· Scale it to fit inside 86 % of the width and 80 % of the height, touching
  whichever limit it reaches first.
· The bottom of the tyres sits at 94 % of the image height.
· Nothing touches or crosses the image edges.

The result must read correctly on a light grey background AND on a black one.`;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }
    // Le secret partagé n'authentifie personne — il est dans l'app, donc
    // extractible. Il écarte les appels au hasard ; ce qui limite vraiment les
    // dégâts, ce sont le plafond par adresse et le coupe-rafale ci-dessous, et
    // le plafond de dépense posé sur la clé OpenAI.
    if (request.headers.get("X-MyTrack-Secret") !== env.MYTRACK_SHARED_SECRET) {
      return new Response("Forbidden", { status: 403 });
    }

    const announced = Number(request.headers.get("Content-Length") ?? "0");
    if (announced > MAX_BODY) {
      return new Response("Photo too large", { status: 413 });
    }

    // Deux compteurs, et un seul des deux est une défense — voir DAILY_LIMIT et
    // DAILY_IP_LIMIT. L'adresse elle-même n'est pas stockée : une app qui
    // promet que rien ne sort de l'appareil n'a pas à écrire l'IP de ses
    // utilisateurs dans une base, même vingt-six heures. Et un SHA-256 *non
    // salé* d'une IPv4 se casse par force brute en quelques secondes — quatre
    // milliards d'entrées. Le sel est le secret partagé, déjà là.
    const day = new Date().toISOString().slice(0, 10);
    const device = request.headers.get("X-MyTrack-Device") ?? "unknown";
    const fingerprint = await salted(
      request.headers.get("CF-Connecting-IP") ?? "inconnu",
      env.MYTRACK_SHARED_SECRET
    );

    // Avant les lectures KV, et c'est l'ordre qui compte : KV est à cohérence
    // éventuelle, donc cent requêtes lancées en deux secondes y liraient toutes
    // le même compteur et passeraient toutes. Ce plafond-ci est immédiat.
    if (env.BURST) {
      const { success } = await env.BURST.limit({ key: fingerprint });
      if (!success) return new Response("Too many requests", { status: 429 });
    }

    const deviceKey = `${device}:${day}`;
    const ipKey = `ip:${fingerprint}:${day}`;
    const [deviceUsed, ipUsed] = await Promise.all([
      env.QUOTA.get(deviceKey).then((value) => Number(value ?? "0")),
      env.QUOTA.get(ipKey).then((value) => Number(value ?? "0")),
    ]);
    if (deviceUsed >= DAILY_LIMIT || ipUsed >= DAILY_IP_LIMIT) {
      return new Response("Daily limit reached", { status: 429 });
    }

    const incoming = await request.formData();
    const photo = incoming.get("photo");
    if (!(photo instanceof File)) {
      return new Response("Missing photo", { status: 400 });
    }
    // Relu sur le fichier reçu : un client hostile ment sur `Content-Length`.
    if (photo.size > MAX_BODY) {
      return new Response("Photo too large", { status: 413 });
    }

    const form = new FormData();
    form.append("model", "gpt-image-2");
    form.append("image", photo, "photo.jpg");
    form.append("prompt", PROMPT);
    form.append("size", "1536x1024");
    form.append("background", "transparent");
    form.append("output_format", "png");
    // « low » plutôt que « medium » : huit fois moins cher ($0,005 contre $0,041
    // l'image en 1536 × 1024, tarif du 2 septembre 2026) pour un dessin qui ne
    // dépasse jamais 1290 pixels de large sur l'iPhone le plus grand. Le seul
    // risque est ailleurs que dans le détail : des bords d'alpha qui bavent
    // fausseraient la mesure du normalisateur autant qu'ils se verraient sur
    // fond noir. C'est ce qu'il faut regarder si on revient à « medium ».
    form.append("quality", "low");
    form.append("n", "1");

    const upstream = await fetch("https://api.openai.com/v1/images/edits", {
      method: "POST",
      headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}` },
      body: form,
    });
    if (!upstream.ok) {
      // Le détail va dans le journal, lisible par « wrangler tail » et par
      // personne d'autre : la réponse d'OpenAI porte des identifiants
      // d'organisation et des messages qui n'ont rien à faire chez un appelant
      // dont on ne sait rien. L'app, elle, ne lit aucun code — elle traduit tout
      // ce qui n'est pas 200 ni 429 par « le service n'a pas répondu ».
      console.error("Studio refusé", upstream.status, await upstream.text());
      return new Response("Upstream error", { status: 502 });
    }

    // Les compteurs ne montent qu'une fois l'image obtenue : un appel raté ne
    // doit pas coûter son quota à quelqu'un. Le statut suffit à en juger —
    // OpenAI ne rend 200 que lorsqu'il a produit une image.
    await Promise.all([
      env.QUOTA.put(deviceKey, String(deviceUsed + 1), { expirationTtl: 60 * 60 * 26 }),
      env.QUOTA.put(ipKey, String(ipUsed + 1), { expirationTtl: 60 * 60 * 26 }),
    ]);

    // Le corps est passé sans être lu : c'est ce qui garde le proxy dans son
    // budget de processeur, et l'app sait déjà décoder ce JSON — c'est celui
    // qu'elle reçoit en mode debug, quand elle appelle OpenAI elle-même.
    return new Response(upstream.body, {
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  },
};

/** Une empreinte courte et salée, qui identifie sans conserver. La même que
 *  celle du relais de commentaires — voir `Server/feedback/worker.ts`. */
async function salted(value: string, salt: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(salt + value)
  );
  return [...new Uint8Array(digest)]
    .slice(0, 8)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
