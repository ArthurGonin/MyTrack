/**
 * MyTrack — le courrier que les réglages envoient.
 *
 * Ce relais existe pour deux raisons, et la première n'est pas celle qu'on croit.
 *
 * La seconde, la plus évidente : rien qui ressemble à une clé ne peut voyager
 * dans l'app, où elle se lirait dans le bundle en deux minutes. Ici il n'y en a
 * même pas — Cloudflare envoie le courrier lui-même, par le lien `send_email`,
 * et les envois vers une adresse de destination vérifiée du compte sont gratuits
 * et hors quota. Pas de service tiers, pas de clé, pas de facture.
 *
 * La première : **le destinataire ne vient que de `env`**, jamais du corps de la
 * requête, jamais d'un en-tête, jamais de l'URL. L'app poste un titre et un
 * texte, rien d'autre. C'est cet invariant-là qui empêche ce relais de servir à
 * écrire ailleurs : même le secret partagé en main, on ne peut rien faire de
 * plus que nous écrire. Ne l'affaiblissez pas.
 */

/**
 * Le lien `send_email`, décrit ici plutôt qu'importé.
 *
 * Il n'y a ni `package.json` ni `node_modules` sous `Server/` : wrangler efface
 * les types sans les résoudre. Écrire la forme dont ce fichier a besoin le met à
 * l'abri d'un nom ambiant qui changerait entre deux versions des types
 * Cloudflare. `KVNamespace`, lui, n'a pas bougé depuis des années, et le worker
 * voisin s'en sert déjà tel quel.
 */
interface SendEmail {
  send(message: {
    from: string | { email: string; name?: string };
    to: string | { email: string; name?: string };
    subject: string;
    text?: string;
  }): Promise<{ messageId: string }>;
}

/** Le coupe-rafale, quand il est branché — voir `wrangler.toml`. */
interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  /** Le même mot que celui posé dans l'app, et différent de celui du détourage. */
  MYTRACK_SHARED_SECRET: string;
  /** L'adresse d'émission, sur le domaine intégré à Email Service. Une adresse
   *  nue (« feedback@domaine ») : le nom d'affichage se pose à part, plus bas. */
  FEEDBACK_SENDER: string;
  /** La boîte qui reçoit, vérifiée dans Email Routing. */
  FEEDBACK_RECIPIENT: string;
  EMAIL: SendEmail;
  QUOTA: KVNamespace;
  /** Facultatif : le worker tourne à l'identique sans lui. */
  BURST?: RateLimiter;
}

/** Messages par empreinte et par jour. Quelqu'un qui signale vraiment quelque
 *  chose écrit souvent un message, puis un correctif, parfois un troisième — et
 *  une adresse IP n'est pas une personne : un foyer, ou un opérateur mobile
 *  derrière son NAT, en partage une. Dix laissent la marge sans laisser la porte
 *  ouverte à qui voudrait remplir la boîte. */
const DAILY_LIMIT = 10;

/** De quoi écarter ce qui n'est manifestement pas un message : les deux champs
 *  de la feuille se saisissent au clavier. Refuser plutôt que tronquer — tronquer
 *  avalerait des mots sans le dire à personne, et ces murs-là sont inatteignables
 *  par accident. */
const MAX_SUBJECT = 200;
const MAX_MESSAGE = 10_000;
/** Lu deux fois : sur `Content-Length`, qui évite de lire quoi que ce soit, puis
 *  sur le texte réellement reçu — un client hostile ment sur `Content-Length`. */
const MAX_BODY = 64 * 1024;

/** Ajoutée sous la signature de l'app, pour le lecteur qui cherchera six mois
 *  plus tard une adresse de réponse qui n'existe pas. */
const FOOTER =
  "\n\nMessage anonyme — MyTrack ne demande aucune adresse, il n'y a personne à qui répondre.";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") return text(405, "Method not allowed");

    // Le secret partagé n'authentifie personne — il est dans l'app, donc
    // extractible. Il écarte les appels au hasard ; ce qui limite vraiment les
    // dégâts, ce sont les plafonds ci-dessous et le fait que le destinataire ne
    // puisse pas être choisi par l'appelant.
    if (request.headers.get("X-MyTrack-Secret") !== env.MYTRACK_SHARED_SECRET) {
      return text(403, "Forbidden");
    }

    const announced = Number(request.headers.get("Content-Length") ?? "0");
    if (announced > MAX_BODY) return text(413, "Corps trop long");

    // `CF-Connecting-IP` est posé par Cloudflare et écrase ce que le client
    // aurait mis : c'est le seul identifiant non falsifiable dont ce worker
    // dispose. Le worker voisin compte, lui, sur un en-tête fourni par l'app —
    // donc sur une valeur que celui qui voudrait le contourner choisit.
    //
    // Mais l'adresse elle-même n'est pas stockée. Une app qui promet que rien ne
    // sort de l'appareil n'a pas à écrire l'IP de ses utilisateurs dans une
    // base, même vingt-six heures. Et un SHA-256 *non salé* d'une IPv4 se casse
    // par force brute en quelques secondes — quatre milliards d'entrées. Le sel
    // est le secret partagé, déjà là.
    const fingerprint = await salted(
      request.headers.get("CF-Connecting-IP") ?? "inconnu",
      env.MYTRACK_SHARED_SECRET
    );

    // Avant la lecture KV, et c'est l'ordre qui compte : KV est à cohérence
    // éventuelle, donc cent requêtes en deux secondes y liraient toutes le même
    // compteur à zéro et passeraient. Ce plafond-ci est immédiat. Il protège
    // aussi le budget d'écritures du plan gratuit.
    if (env.BURST) {
      const { success } = await env.BURST.limit({ key: fingerprint });
      if (!success) return text(429, "Trop de messages en peu de temps");
    }

    const quotaKey = `${fingerprint}:${new Date().toISOString().slice(0, 10)}`;
    const used = Number((await env.QUOTA.get(quotaKey)) ?? "0");
    if (used >= DAILY_LIMIT) return text(429, "Daily limit reached");

    const raw = await request.text();
    if (raw.length > MAX_BODY) return text(413, "Corps trop long");

    let payload: { subject?: unknown; message?: unknown };
    try {
      payload = JSON.parse(raw);
    } catch {
      return text(400, "JSON illisible");
    }
    if (typeof payload.subject !== "string" || typeof payload.message !== "string") {
      return text(400, "Titre ou message absent");
    }

    // Le titre finit dans un en-tête de courrier : un retour à la ligne au
    // milieu, et ce qui suit devient un en-tête à part. Cloudflare construit le
    // MIME lui-même et encode probablement comme il faut, mais un invariant
    // d'une ligne sur un champ pareil ne se discute pas.
    const subject = payload.subject.replace(/[\r\n]+/g, " ").trim();
    const message = payload.message.trim();
    if (!subject || !message) return text(400, "Titre ou message vide");
    if (subject.length > MAX_SUBJECT || message.length > MAX_MESSAGE) {
      return text(413, "Message trop long");
    }

    if (!env.FEEDBACK_SENDER || !env.FEEDBACK_RECIPIENT) {
      return text(500, "Relais mal configuré");
    }

    try {
      await env.EMAIL.send({
        // La forme objet, et non « MyTrack <feedback@domaine> » : cette
        // dernière n'est pas acceptée. Le nom d'affichage n'a rien de secret et
        // reste ici ; l'adresse vient du secret.
        from: { email: env.FEEDBACK_SENDER, name: "MyTrack" },
        to: env.FEEDBACK_RECIPIENT,
        // Tel quel : l'app préfixe déjà « MyTrack — », et un second préfixe
        // donnerait « MyTrack — MyTrack — … ».
        subject,
        // Du texte brut, et pas de HTML du tout. Le message vient d'un champ de
        // saisie : en HTML il faudrait l'échapper, ce qui serait une surface
        // d'injection en échange de rien. Le texte brut garde les sauts de ligne
        // de la signature que l'app a composée.
        text: message + FOOTER,
      });
    } catch (error) {
      // Le code de Cloudflare est le seul diagnostic disponible le jour où ça
      // refuse : `E_SENDER_NOT_VERIFIED` dit que le domaine d'émission n'est pas
      // intégré, `E_RECIPIENT_NOT_ALLOWED` que la boîte n'a jamais confirmé son
      // adresse. Le détail complet va dans le journal, lisible par
      // « wrangler tail » et par personne d'autre ; ce qui repart à l'appelant
      // est expurgé du destinataire, pour que l'erreur ne serve pas d'oracle à
      // qui a extrait le secret.
      console.error("Envoi refusé", error);
      const code = (error as { code?: string })?.code ?? String(error);
      return text(502, `Envoi refusé : ${code.split(env.FEEDBACK_RECIPIENT).join("<destinataire>")}`);
    }

    // Le compteur ne monte qu'une fois le courrier parti : un envoi raté ne doit
    // pas coûter son quota à quelqu'un qui n'y est pour rien.
    await env.QUOTA.put(quotaKey, String(used + 1), { expirationTtl: 60 * 60 * 26 });

    return text(200, "Message transmis");
  },
};

/** Les corps d'erreur sont des phrases courtes et lisibles : l'app ne lit aucun
 *  code, elle journalise le corps tel quel — c'est donc cette phrase-là qu'on
 *  relira dans Console depuis un vrai iPhone. */
function text(status: number, body: string): Response {
  return new Response(body, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
  });
}

/** Une empreinte courte et salée, qui identifie sans conserver. */
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
