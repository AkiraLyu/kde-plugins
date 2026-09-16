// SPDX-License-Identifier: GPL-2.0-or-later
#version 140
#include "colormanagement.glsl"
#include "saturation.glsl"

uniform sampler2D sampler;
uniform vec4 modulation;
uniform vec2 uFrameSize;
uniform vec2 uExpandedSize;
uniform vec2 uExpandedOffset;
uniform vec2 uBarSize;
uniform float uOpacity;
uniform float uTolerance;
uniform vec4 uCornerRadii; // top left, top right, bottom left, bottom right
in vec2 texcoord0;
out vec4 fragColor;

vec4 sampleAt(vec2 p) {
    vec2 uv = (p - uExpandedOffset) / uExpandedSize;
    return texture(sampler, vec2(uv.x, 1.0 - uv.y));
}

void main() {
    vec4 tex = texture(sampler, texcoord0);
    vec2 p = vec2(texcoord0.x, 1.0 - texcoord0.y) * uExpandedSize + uExpandedOffset;
    // Include the outermost pixels: leaving an opaque rim around translucent
    // bars makes a pale line that is especially visible while moving.
    bool inside = all(greaterThanEqual(p, vec2(0.0)))
        && all(lessThan(p, uFrameSize));
    bool title = p.y < uBarSize.y;
    bool nav = p.x < uBarSize.x;

    // Keep the profile image untouched, including its pale pixels.
    bool avatar = nav && p.x > 10.0 && p.x < 51.0 && p.y > 42.0 && p.y < 84.0;
    if (inside && (title || nav) && !avatar && tex.a > 0.0001) {
        vec3 bg = sampleAt(vec2(5.0, uFrameSize.y * 0.5)).rgb;
        vec3 color = tex.rgb / tex.a;
        vec2 pixelSize = uExpandedSize / vec2(textureSize(sampler, 0));
        bool frameEdge = any(lessThan(min(p, uFrameSize - p), pixelSize));
        float chroma = max(max(color.r, color.g), color.b) - min(min(color.r, color.g), color.b);
        // WeChat's one-pixel gray outline belongs to the background too.
        // Otherwise the foreground detector keeps that darker gray opaque.
        if (frameEdge && chroma < 0.02 && length(color - bg) < 0.2) {
            bg = color;
        }
        // Infer local foreground coverage so antialiased icon edges do not
        // retain the old gray matte. Solid icon pixels stay fully opaque.
        vec3 foregroundDelta = color - bg;
        float bestDistance = dot(foregroundDelta, foregroundDelta);
        vec2 texel = 1.0 / vec2(textureSize(sampler, 0));
        for (int y = -2; y <= 2; ++y) {
            for (int x = -2; x <= 2; ++x) {
                vec4 neighbor = texture(sampler, texcoord0 + vec2(x, y) * texel);
                vec3 delta = neighbor.rgb - bg;
                float distance = dot(delta, delta);
                if (neighbor.a > 0.99 && distance > bestDistance) {
                    foregroundDelta = delta;
                    bestDistance = distance;
                }
            }
        }
        float coverage = bestDistance > 0.00002
            ? clamp(dot(color - bg, foregroundDelta) / bestDistance, 0.0, 1.0) : 0.0;
        float residual = length(color - bg - foregroundDelta * coverage);
        float compatible = 1.0 - smoothstep(0.005, uTolerance, residual);
        float removedAlpha = (1.0 - uOpacity) * (1.0 - coverage) * compatible * tex.a;
        tex.rgb = max(vec3(0.0), tex.rgb - bg * removedAlpha);
        tex.a -= removedAlpha;
    }

    // Offscreen quads cover the entire rectangle. Clip their client area to
    // the same rounded outline used by the background-blur region.
    if (inside) {
        bool left = p.x < uFrameSize.x * 0.5;
        bool top = p.y < uFrameSize.y * 0.5;
        float radius = left ? (top ? uCornerRadii.x : uCornerRadii.z)
                            : (top ? uCornerRadii.y : uCornerRadii.w);
        vec2 q = abs(p - uFrameSize * 0.5) - (uFrameSize * 0.5 - vec2(radius));
        float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
        float coverage = clamp(0.5 - distance / max(fwidth(distance), 0.0001), 0.0, 1.0);
        tex *= coverage;
    }
    tex = sourceEncodingToNitsInDestinationColorspace(tex);
    tex = adjustSaturation(tex);
    fragColor = nitsToDestinationEncoding(tex * modulation);
}
