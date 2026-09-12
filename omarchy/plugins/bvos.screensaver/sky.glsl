#version 440
// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.
//
// Blue View OS "above the clouds" sky, after the blueview.ai hero.
// The sun (the logo's yellow oval) and moon (its blue oval) sit where they
// really are in the sky; the clouds follow the weather and the wind outside.
//
// One source, two passes. Real stars, constellations and satellites are drawn
// sharp at full resolution between them:
//   SKY_PASS    the sky itself: gradient, twilight, overcast, sun and moon glow
//   CLOUD_PASS  everything in front of the stars, with alpha: sun and moon
//               ovals, high clouds, the sea of clouds, rain, snow, fog
//
// Compile with:
//   qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -DSKY_PASS   -o sky.frag.qsb    sky.glsl
//   qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -DCLOUD_PASS -o clouds.frag.qsb sky.glsl

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    vec2 sunPos;      // x offset from screen center, y from the bottom (screen-height units)
    float sunAlt;     // sine of the sun's altitude
    vec2 moonPos;
    float moonAlt;    // sine of the moon's altitude
    float moonLight;  // 0..1 illuminated fraction
    float cover;      // 0..1 cloud cover
    float gloom;      // 0..1 how dark and grey the weather is
    float rain;       // 0..1
    float snow;       // 0..1
    float fog;        // 0..1
    float storm;      // 0..1
    float moonWaxing; // 1 waxing (lit on the right), -1 waning
    vec3 layerShiftX; // wind-driven travel of each cloud-sea layer (far, mid, near)
    vec3 layerShiftY;
    vec2 highShift;   // travel of the high clouds overhead
};

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 r = mat2(0.8, -0.6, 0.6, 0.8);
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = r * p * 2.03;
        a *= 0.5;
    }
    return v;
}

// Distance in units of an oval shaped like the ones in the Blue View logo.
float oval(vec2 p, vec2 center, float size) {
    return length((p - center) / vec2(size * 1.58, size));
}

// Premultiplied "over": paint color c with coverage a on top of acc.
void over(inout vec4 acc, vec3 c, float a) {
    acc = vec4(c * a, a) + acc * (1.0 - a);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float y = 1.0 - uv.y;
    vec2 p = vec2(uv.x * aspect, y);

    // Civil twilight ends at -6°, so the day fades out between sin(-7°) and sin(+13°).
    float day = smoothstep(-0.12, 0.22, sunAlt);
    float twilight = clamp(1.0 - abs(sunAlt) / 0.28, 0.0, 1.0);
    float grey = gloom * 0.85;

    // ---- Sky: night navy, dawn and dusk warmth, brand-blue day.
    vec3 dayZenith = vec3(0.012, 0.155, 0.330);
    vec3 dayMid = vec3(0.180, 0.520, 0.860);
    vec3 dayHorizon = vec3(0.820, 0.900, 0.965);
    vec3 nightZenith = vec3(0.006, 0.014, 0.045);
    vec3 nightMid = vec3(0.022, 0.050, 0.120);
    vec3 nightHorizon = vec3(0.070, 0.115, 0.210);
    vec3 duskHorizon = vec3(1.000, 0.620, 0.420);
    vec3 duskMid = vec3(0.560, 0.420, 0.620);

    vec3 zenith = mix(nightZenith, dayZenith, day);
    vec3 mid = mix(mix(nightMid, dayMid, day), duskMid, twilight * 0.55);
    vec3 horizon = mix(mix(nightHorizon, dayHorizon, day), duskHorizon, twilight * 0.75);

    vec3 sky = mix(horizon, mid, smoothstep(0.30, 0.66, y));
    sky = mix(sky, zenith, smoothstep(0.64, 1.10, y));

    // Overcast skies go flat and grey.
    vec3 overcast = mix(vec3(0.060, 0.075, 0.100), vec3(0.560, 0.620, 0.680), day) * mix(1.0, 0.7, storm) * (1.0 - rain * 0.35);
    sky = mix(sky, overcast * mix(0.85, 1.1, y), grey * 0.8);

    // ---- Sun glow.
    vec2 sunP = vec2(aspect * 0.5 + sunPos.x, sunPos.y);
    float sunD = length(p - sunP);
    float sunVisible = smoothstep(-0.10, 0.02, sunAlt) * (1.0 - grey * 0.9);
    sky += vec3(1.00, 0.90, 0.75) * (0.34 * exp(-sunD * 3.0) + 0.30 * exp(-sunD * 14.0)) * sunVisible;

    // ---- Moon glow, scaled by how much of it is lit.
    vec2 moonP = vec2(aspect * 0.5 + moonPos.x, moonPos.y);
    float moonD = length(p - moonP);
    float moonVisible = smoothstep(-0.08, 0.04, moonAlt) * (1.0 - day * 0.45) * (1.0 - grey * 0.85);
    float moonGlow = 0.15 + 0.85 * moonLight;
    sky += vec3(0.45, 0.68, 1.0) * (0.22 * exp(-moonD * 4.5) + 0.20 * exp(-moonD * 18.0)) * moonVisible * moonGlow;

    // ---- Brand wash, like the blueview.ai hero overlay (#004c80 -> #38b6ff), strongest by day.
    vec3 wash = mix(vec3(0.220, 0.714, 1.000), vec3(0.000, 0.298, 0.502), y) * mix(0.35, 1.0, day);
    float washAmount = 0.30 * (1.0 - grey * 0.5) * mix(0.5, 1.0, day);

    vec2 v = uv - 0.5;
    float vignette = 1.0 - 0.28 * dot(v, v) * 1.6;

#ifdef SKY_PASS
    vec3 col = mix(sky, wash, washAmount) * vignette;
    fragColor = vec4(col, 1.0) * qt_Opacity;
#endif

#ifdef CLOUD_PASS
    vec4 acc = vec4(0.0);

    // ---- Sun and moon ovals in true logo colors.
    vec3 sunColor = mix(vec3(1.0, 0.62, 0.30), vec3(1.0, 0.871, 0.349), smoothstep(0.0, 0.35, sunAlt));
    float sunDisc = smoothstep(1.0, 0.88, oval(p, sunP, 0.027));
    over(acc, sunColor, sunDisc * sunVisible * (1.0 - fog * 0.8));

    // Real phase: the terminator crosses the oval; the dark side keeps a faint earthshine.
    float moonDisc = smoothstep(1.0, 0.88, oval(p, moonP, 0.024));
    vec2 mq = (p - moonP) / vec2(0.024 * 1.58, 0.024);
    float limb = sqrt(max(0.0, 1.0 - mq.y * mq.y));
    float lit = smoothstep(-0.06, 0.06, moonWaxing * mq.x - (1.0 - 2.0 * moonLight) * limb);
    over(acc, vec3(0.220, 0.714, 1.000), moonDisc * moonVisible * mix(0.22, 1.0, lit) * (1.0 - fog * 0.8));

    // ---- High clouds drifting overhead with the wind aloft.
    vec2 wq = vec2((p.x - highShift.x) * 1.6, (p.y - highShift.y) * 3.2);
    float wn = fbm(wq + fbm(wq * 0.6 + vec2(time * 0.0015, 0.0)) * 0.8);
    float wMask = smoothstep(1.02 - cover * 0.72, 1.18 - cover * 0.55, wn + 0.25) * smoothstep(0.28, 0.55, y);
    vec3 wLit = mix(vec3(0.20, 0.24, 0.32), vec3(0.97, 0.97, 0.98), day);
    wLit = mix(wLit, duskHorizon * 0.9 + 0.1, twilight * (1.0 - grey) * 0.45);
    vec3 wShade = mix(vec3(0.05, 0.06, 0.09), vec3(0.55, 0.60, 0.68), day) * mix(1.0, 0.55, storm);
    vec3 wCloud = mix(wLit, wShade, clamp(grey + (wn - 0.55) * 1.5, 0.0, 1.0));
    over(acc, mix(wCloud, wash, washAmount), wMask * (0.55 + 0.45 * cover));

    // ---- Sea of clouds: three parallax layers, far to near. Thicker when overcast.
    float lift = cover * 0.06 + gloom * 0.04;
    for (int l = 0; l < 3; l++) {
        float fl = float(l);
        float scale = 5.2 - fl * 1.6;   // perspective: nearer clouds look bigger
        float base = 0.40 - fl * 0.11 + lift;

        vec2 q = vec2((p.x - layerShiftX[l]) * scale, (p.y - layerShiftY[l]) * scale * 1.3);
        float warp = fbm(q * 0.45 + vec2(time * 0.0015, 0.0));   // clouds reshape over ~10 minutes
        float n = fbm(q + warp * 0.9);
        float billow = fbm(q * 2.7 + vec2(0.0, time * 0.0015));

        float edge = base + (n - 0.5) * (0.22 + fl * 0.07) + (billow - 0.5) * 0.035;
        float mask = smoothstep(edge + 0.012, edge - 0.022, y);
        float depth = clamp((edge - y) * 7.0, 0.0, 1.0);

        vec3 sunlit = mix(vec3(0.16, 0.22, 0.34), vec3(1.00, 0.990, 0.965), day);
        sunlit = mix(sunlit, vec3(1.0, 0.72, 0.55), twilight * 0.45 * (1.0 - grey));
        sunlit += vec3(0.30, 0.45, 0.70) * moonVisible * moonGlow * (1.0 - day) * 0.35;
        vec3 shadow = mix(vec3(0.05, 0.08, 0.15), vec3(0.520, 0.650, 0.800), day);
        vec3 greyTop = mix(vec3(0.10, 0.11, 0.14), vec3(0.70, 0.73, 0.77), day);
        sunlit = mix(sunlit, greyTop, grey);
        shadow = mix(shadow, shadow * 0.6, grey);

        float fold = smoothstep(0.35, 0.75, billow);
        vec3 cloud = mix(sunlit, shadow, depth * (0.45 + 0.35 * (1.0 - fold)));
        cloud += vec3(1.0, 0.92, 0.80) * 0.18 * exp(-sunD * 2.5) * (1.0 - depth) * sunVisible;
        cloud = mix(cloud, sky, 0.38 - fl * 0.14);   // aerial perspective

        over(acc, mix(cloud, wash, washAmount), mask);
    }

    // ---- Lightning: rare flashes lighting the clouds from within.
    float beat = floor(time * 1.5);
    float strike = step(1.0 - 0.035 * storm, hash(vec2(beat, 3.7)));
    float flicker = strike * (0.6 + 0.4 * sin(time * 60.0)) * (1.0 - fract(time * 1.5));
    vec2 boltAt = vec2(hash(vec2(beat, 1.3)) * aspect, 0.25);
    float flash = flicker * 0.9 * exp(-length((p - boltAt) * vec2(0.8, 1.6)) * 2.2) * storm;
    acc.rgb += vec3(0.75, 0.82, 1.0) * flash * max(acc.a, 0.35);
    acc.a = max(acc.a, flash * 0.35);

    // ---- Rain: slanted streaks.
    if (rain > 0.001) {
        vec2 rp = vec2(p.x * 70.0 + p.y * 12.0, p.y * 7.0 + time * 9.0);
        vec2 cell = floor(rp);
        float drop = step(1.0 - rain * 0.28, hash(cell));
        float streak = smoothstep(0.16, 0.0, abs(fract(rp.x) - 0.5)) * smoothstep(0.0, 0.5, fract(rp.y)) * smoothstep(1.0, 0.5, fract(rp.y));
        over(acc, mix(vec3(0.55, 0.62, 0.72), vec3(0.88, 0.92, 0.98), day), drop * streak * 0.45 * rain);
    }

    // ---- Snow: slow drifting flakes in two depths.
    if (snow > 0.001) {
        for (int s = 0; s < 2; s++) {
            float fs = float(s);
            float density = 26.0 + fs * 22.0;
            vec2 sp = vec2(p.x * density + sin(time * 0.6 + p.y * 6.0 + fs) * 0.8, p.y * density + time * (1.2 + fs * 0.9));
            vec2 cell = floor(sp);
            float has = step(1.0 - snow * 0.35, hash(cell + fs * 13.0));
            vec2 offset = vec2(hash(cell + 1.7), hash(cell + 9.1)) * 0.6 + 0.2;
            float flake = smoothstep(0.16 - fs * 0.05, 0.0, length(fract(sp) - offset));
            over(acc, vec3(0.96, 0.98, 1.0), has * flake * (0.75 - fs * 0.25));
        }
    }

    // ---- Fog and mist: a soft veil.
    float veil = fog * (0.55 + 0.25 * fbm((p - vec2(layerShiftX.z, 0.0)) * 3.0));
    over(acc, mix(vec3(0.10, 0.12, 0.16), vec3(0.82, 0.86, 0.90), day), veil * 0.75);

    acc.rgb *= vignette;
    fragColor = acc * qt_Opacity;
#endif
}
