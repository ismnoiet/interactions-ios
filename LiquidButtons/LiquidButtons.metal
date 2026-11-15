//
//  LiquidMetal.metal
//  Add this file to your app target (it is picked up by ShaderLibrary.default).
//
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Helpers

static float sdRoundBox(float2 p, float2 halfSize, float r) {
    float2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Soft/hard hybrid stripe: chrome-like bands with crisp edges and grey roll-off.
static float chromeBand(float x, float bias) {
    float s = sin(6.2831853 * x);
    float hard = smoothstep(-0.10, 0.10, s + bias);
    float soft = 0.5 + 0.5 * s;
    return mix(soft, hard, 0.78);
}


static float sq(float x) { return x * x; }
static float angDist(float a, float b) { return fract(a - b + 0.5) - 0.5; }

// white -> yellow -> orange -> navy-black -> blue -> white (periodic), like the reference ribbons.
static float3 filmPalette(float s) {
    const float3 stops[8] = {
        float3(1.00, 1.00, 1.00),
        float3(0.97, 0.97, 1.00),
        float3(1.00, 0.86, 0.28),
        float3(0.95, 0.36, 0.10),
        float3(0.03, 0.04, 0.16),
        float3(0.10, 0.22, 0.95),
        float3(0.92, 0.94, 1.00),
        float3(1.00, 1.00, 1.00)
    };
    float x = fract(s) * 7.0;
    int i = int(floor(x));
    float f = smoothstep(0.0, 1.0, fract(x));
    return mix(stops[i], stops[min(i + 1, 7)], f);
}

// MARK: - Liquid metal ring
//
// Used with `.colorEffect` on a stroked rounded rectangle. The incoming alpha is
// the ring coverage; we replace the colour with animated liquid chrome.
//
//  size   : view size in points
//  time   : seconds
//  light  : 0 = dark theme, 1 = light theme (animatable crossfade)
//  radius : outer corner radius of the ring
//  width  : ring thickness

[[ stitchable ]] half4 liquidMetalRing(float2 position,
                                       half4 color,
                                       float2 size,
                                       float time,
                                       float light,
                                       float radius,
                                       float width)
{
    if (color.a < 0.001h) { return half4(0.0h); }

    float2 center = size * 0.5;
    float2 p = position - center;

    // Distance inside the ring: 0 on the outer edge, 1 on the inner edge.
    float d = sdRoundBox(p, center, radius);
    float t = clamp(-d / width, 0.0, 1.0);

    float2 n = p / size.y;
    float a = atan2(n.y, n.x) / 6.2831853;          // -0.5 ... 0.5

    // Liquid domain warp (fast drifting value noise).
    float w1 = vnoise(n * 3.0 + float2(time * 0.65, -time * 0.50));
    float w2 = vnoise(n * 7.5 - float2(time * 0.90, time * 0.70));
    float warp = (w1 - 0.5) * 1.15 + (w2 - 0.5) * 0.35;

    // --- Base: soft silver with moving navy shadow lobes ---------------------------
    float3 lo = float3(0.045, 0.050, 0.095);
    float3 hi = float3(0.91, 0.92, 0.97);
    float sheen = 0.5 + 0.5 * sin(6.2831853 * (a - time * 0.14 + 0.12 * warp));
    float base = mix(0.62, 1.0, sheen);
    float lobeA = exp(-sq(angDist(a, fract(0.62 - time * 0.10)) / 0.17));
    float lobeB = exp(-sq(angDist(a, fract(0.12 + time * 0.07)) / 0.12));
    base *= 1.0 - mix(0.55, 0.85, light) * lobeA - mix(0.0, 0.7, light) * lobeB;
    float3 rgb = mix(lo, hi, clamp(base, 0.0, 1.0));

    // --- Travelling iridescent ribbon patches ------------------------------------
    // Each patch laps the ring at its own speed; inside it, thin ribbons run along the
    // ring (u depends mostly on the radial coordinate t) with a dark navy line between colours.
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float dir = (k == 1) ? -1.0 : 1.0;
        float c = fract(0.10 + fk * 0.37 + dir * time * (0.075 + 0.05 * fk));
        float dth = angDist(a, c);
        float sigma = 0.115 + 0.030 * sin(time * 0.9 + fk * 2.1);
        float env = exp(-sq(dth / sigma));

        // Ribbon coordinate: mostly across the band (t) but bent into large S-curves by
        // travelling sine waves, so the iso-lines sweep diagonally across the band like
        // the reference. `dth` runs along the ring.
        float along = dth * 6.0;
        float u = (t - 0.5) * 1.5
                + 0.85 * sin(6.2831853 * (along * 0.55 + 0.35 * w1) + time * 1.3 + fk * 1.9)
                + 0.40 * sin(6.2831853 * (along * 1.10 - (t - 0.5) * 0.55) - time * 1.9 + fk)
                + (w2 - 0.5) * 0.9;
        float3 col = filmPalette(u * 0.42 + fk * 0.21 + time * 0.05);
        float g = sin(6.2831853 * (u * 0.6 + 0.1));
        float line = exp(-g * g / 0.025);
        col = mix(col, float3(0.02, 0.03, 0.10), line * 0.85);

        rgb = mix(rgb, col, clamp(env * 1.15, 0.0, 1.0));
    }

    // Bevel: gentle bright lip outside, falls to dark navy toward the face.
    float lip   = 1.0 - smoothstep(0.0, 0.14, t);
    float inner = smoothstep(0.45, 1.0, t);
    rgb = mix(rgb, rgb * 0.38 + lo * 0.5, inner * 0.8);
    rgb += 0.06 * lip;

    rgb = clamp(rgb, 0.0, 1.0);
    return half4(half3(rgb) * color.a, color.a);
}

