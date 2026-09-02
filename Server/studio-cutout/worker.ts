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
    form.append("model", "gpt-image-1");
    form.append("image", photo, "photo.jpg");
    form.append("prompt", PROMPT);
    form.append("size", "1536x1024");
    form.append("background", "transparent");
    form.append("output_format", "png");
    form.append("quality", "high");
    form.append("n", "1");

    const upstream = await fetch("https://api.openai.com/v1/images/edits", {
      method: "POST",
      headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}` },
      body: form,
    });
    if (!upstream.ok) {
      return new Response(await upstream.text(), { status: 502 });
    }

    const payload = (await upstream.json()) as { data?: { b64_json?: string }[] };
    const base64 = payload.data?.[0]?.b64_json;
    if (!base64) {
      return new Response("No image returned", { status: 502 });
    }

    // Le compteur ne monte qu'une fois l'image obtenue : un appel raté ne doit
    // pas coûter son quota à quelqu'un.
    await env.QUOTA.put(quotaKey, String(used + 1), { expirationTtl: 60 * 60 * 26 });

    const bytes = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
    return new Response(bytes, {
      headers: { "Content-Type": "image/png", "Cache-Control": "no-store" },
    });
  },
};
