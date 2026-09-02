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

export interface Env {
  OPENAI_API_KEY: string;
  MYTRACK_SHARED_SECRET: string;
  QUOTA: KVNamespace;
}

/** Photos par appareil et par jour. Un utilisateur en fait une ou deux. */
const DAILY_LIMIT = 5;

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
    // extractible. Il écarte les appels au hasard ; ce sont le plafond
    // ci-dessous et celui de la clé OpenAI qui limitent vraiment les dégâts.
    if (request.headers.get("X-MyTrack-Secret") !== env.MYTRACK_SHARED_SECRET) {
      return new Response("Forbidden", { status: 403 });
    }

    const device = request.headers.get("X-MyTrack-Device") ?? "unknown";
    const quotaKey = `${device}:${new Date().toISOString().slice(0, 10)}`;
    const used = Number((await env.QUOTA.get(quotaKey)) ?? "0");
    if (used >= DAILY_LIMIT) {
      return new Response("Daily limit reached", { status: 429 });
    }

    const incoming = await request.formData();
    const photo = incoming.get("photo");
    if (!(photo instanceof File)) {
      return new Response("Missing photo", { status: 400 });
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
      return new Response(await upstream.text(), { status: 502 });
    }

    // Le compteur ne monte qu'une fois l'image obtenue : un appel raté ne doit
    // pas coûter son quota à quelqu'un. Le statut suffit à en juger — OpenAI ne
    // rend 200 que lorsqu'il a produit une image.
    await env.QUOTA.put(quotaKey, String(used + 1), { expirationTtl: 60 * 60 * 26 });

    // Le corps est passé sans être lu : c'est ce qui garde le proxy dans son
    // budget de processeur, et l'app sait déjà décoder ce JSON — c'est celui
    // qu'elle reçoit en mode debug, quand elle appelle OpenAI elle-même.
    return new Response(upstream.body, {
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  },
};
