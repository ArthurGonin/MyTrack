//
//  StudioCutoutConfiguration.swift
//  MyTrack
//
//  Où joindre le service qui détoure et nettoie les photos de véhicule.
//
//  Deux façons de le joindre, et une seule est publiable.
//
//  **Le proxy**, pour de vrai. Il détient la clé OpenAI — elle ne peut pas vivre
//  dans l'app, où elle se lirait dans le bundle en deux minutes. C'est lui aussi
//  qui porte le prompt : l'améliorer ne demandera pas de republier sur l'App
//  Store. Son code est dans `Server/studio-cutout/`.
//
//  **La clé directe**, pour essayer. Elle appelle OpenAI depuis le téléphone,
//  sans rien déployer — de quoi voir le résultat en dix minutes. Elle n'existe
//  qu'en configuration Debug (`#if DEBUG`) : une compilation Release n'en
//  contient pas une ligne, donc elle ne peut pas partir sur l'App Store même en
//  l'oubliant remplie.
//
//  Le secret partagé, lui, est embarqué et c'est assumé : il n'authentifie
//  personne, il écarte les appels au hasard. Ce sont les plafonds du proxy et
//  celui de la clé OpenAI qui limitent vraiment les dégâts.
//

import Foundation

enum StudioCutoutConfiguration {
    /// L'adresse du proxy, par exemple
    /// « https://mytrack-studio.votre-compte.workers.dev ».
    static let endpoint = "https://mytrack-studio.studio-cutout.workers.dev"

    /// Le même mot que celui posé côté proxy sous `MYTRACK_SHARED_SECRET`.
    static let sharedSecret = "f5341d8941d762780049fc3ee1bcf1d299ea9f6e4c77b7e4"

    /// Vrai quand les deux sont renseignés. Un seul des deux ne sert à rien :
    /// le proxy refuserait l'appel, et l'app aurait attendu pour rien.
    static var isConfigured: Bool {
        !endpoint.isEmpty && !sharedSecret.isEmpty
    }

    static var endpointURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: endpoint)
    }

    #if DEBUG
    /// Une clé OpenAI, le temps d'un essai depuis Xcode. À vider avant de
    /// pousser quoi que ce soit sur un dépôt partagé — et de toute façon
    /// absente des compilations Release.
    static let debugOpenAIKey = ""

    static var hasDebugKey: Bool { !debugOpenAIKey.isEmpty }
    #endif

    /// Le prompt, dans sa copie d'essai.
    ///
    /// Celui qui compte est dans `Server/studio-cutout/worker.ts` : c'est lui
    /// qui tournera en production, et lui qu'on ajustera sans republier l'app.
    /// Celui-ci ne sert qu'au mode Debug ci-dessus, pour que l'essai porte sur
    /// le même texte.
    static let prompt = """
        Turn the attached photo into a product-style cut-out of THIS EXACT CAR, \
        on a fully transparent background, for use as an app illustration.

        SUBJECT — retouch, do not reinvent
        · Keep the identical vehicle: same model, body shape, colour, trim, wheel \
        design, badges, headlight signature. Do not substitute a different or \
        idealised car, do not restyle it.
        · Keep its true proportions. Do not stretch, squash or widen the car to \
        fill the frame.
        · Straight-on front elevation. Camera at headlight height, centred on the \
        car's axis, both sides symmetric. If the photo is off-axis, correct the \
        perspective to dead-on frontal.
        · Rectilinear lens look: no wide-angle bulge, no tilt, no vanishing point.

        FINISH
        · Even studio lighting: broad soft key from above-front, gentle fill on \
        both sides, no hotspots, no lens flare, no colour cast.
        · Windscreen and side windows: uniform dark neutral tint. Remove ALL \
        reflections — sky, buildings, photographer, interior.
        · Clean bodywork: no dust, water spots, scratches or background elements \
        reflected in the paint. Keep the paint's own colour and finish.
        · No environment: no road, no wall, no floor plane, no gradient, no vignette.

        GROUND SHADOW
        · One soft elliptical contact shadow directly beneath the car, fading to \
        fully transparent at its edges. Neutral grey, 25–35 % opacity at its darkest.

        OUTPUT
        · PNG, RGBA, real alpha channel, 1536 × 1024 px, landscape.
        · Fully transparent everywhere except the car and its shadow.
        · No white or grey halo, no matte fringe, no border, no watermark, no text.

        FRAMING
        · Centre the car horizontally, equal margins left and right.
        · Scale it to fit inside 86 % of the width and 80 % of the height, touching \
        whichever limit it reaches first.
        · The bottom of the tyres sits at 94 % of the image height.
        · Nothing touches or crosses the image edges.

        The result must read correctly on a light grey background AND on a black one.
        """
}
