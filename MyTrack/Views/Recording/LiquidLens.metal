//
//  LiquidLens.metal
//  MyTrack
//
//  Le shader qui fait de la pastille une vraie lentille : le texte qu'elle
//  recouvre est échantillonné avec un décalage vers l'extérieur, d'autant plus
//  fort qu'on approche du bord. C'est ce que fait le verre d'iOS, et c'est ce
//  qu'aucun empilement de `blur` et de dégradés ne sait imiter — d'où le
//  passage par Metal plutôt que par SwiftUI seul.
//
//  D'après LiquidGlassSlider de Balaji Venkatesh (Kavsoft), repris tel quel.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// Distance to Capsule
float d2Capsule(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

[[stitchable]] half4 liquidLens(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float positionX,
    float refractionAmount,
    float refractionDepth
) {
    float2 pillCenter = size * 0.5 + float2(positionX, 0.0);
    float2 local = position - pillCenter;
    float2 halfSize = size * 0.5;
    float radius = size.y * 0.5;
    
    float dist = d2Capsule(local, halfSize, radius);
    
    if (dist > 0.0) {
        return layer.sample(position);
    }
    
    float2 outward = normalize(float2(
       d2Capsule(local + float2(1, 0), halfSize, radius) - d2Capsule(local - float2(1, 0), halfSize, radius),
       d2Capsule(local + float2(0, 1), halfSize, radius) - d2Capsule(local - float2(0, 1), halfSize, radius)
    ));
    
    float depthInside = -dist;
    float edgePxmy = 1.0 - smoothstep(0.0, refractionDepth, depthInside);
    
    float bend = edgePxmy * edgePxmy * refractionAmount;
    
    return layer.sample(position - outward * bend);
}
