//
//  Compositor.metal — the ONE pipeline every layer of a frame goes through
//  (spec §7.5). Owned by `app/Sources/Compositor.swift`, which encodes one
//  pass per layer, back to front, source-over into the destination.
//
//  LAYOUT CONTRACT — read before touching `LayerUniforms`.
//  The Swift half of this struct is `LayerUniforms` in Compositor.swift and
//  it must stay field-for-field identical. Every field is a scalar `float`
//  on purpose: a struct of scalars has 4-byte alignment and sequential
//  layout in BOTH compilers, so no padding rule can drift between them. The
//  moment someone adds a `float2` or a `float4x4` here, the two layouts stop
//  being obviously equal and the frame silently renders with garbage
//  uniforms. Add fields at the END, in pairs (the struct is deliberately a
//  multiple of 16 bytes), and mirror them in Swift in the same order.
//

#include <metal_stdlib>
using namespace metal;

// Transition kind codes. Mirrors `TransitionCode` in Compositor.swift, which
// maps `TransitionKind` (§5.2) onto these.
constant int kTransitionNone      = 0;
constant int kTransitionDissolve  = 1;
constant int kTransitionFadeBlack = 2;
constant int kTransitionFadeWhite = 3;
constant int kTransitionPush      = 4;
constant int kTransitionSlide     = 5;
constant int kTransitionWipe      = 6;
constant int kTransitionZoom      = 7;

struct LayerUniforms {
    float canvasWidth;
    float canvasHeight;
    // Placement anchor in canvas pixels, y DOWN (§5.3): the canvas centre
    // plus the clip's (x, y), and the point rotation happens about — the
    // centre of the UNCROPPED rectangle, never of the cropped one.
    float anchorX;
    float anchorY;
    float sourceWidth;
    float sourceHeight;
    float scale;
    float rotation;      // radians, clockwise on screen
    float cropL;         // crop insets in SOURCE pixels
    float cropT;
    float cropR;
    float cropB;
    float cornerRadius;  // source pixels, applied to the CROPPED rectangle
    float opacity;
    float brightness;
    float contrast;
    float saturation;
    float hue;           // radians
    float chromaEnabled;
    float chromaKeyR;
    float chromaKeyG;
    float chromaKeyB;
    float chromaTolerance;
    float chromaSoftness;
    float chromaSpill;
    float transitionKind;
    float transitionProgress;   // 0…1 across the overlap
    float transitionIncoming;   // 1 = role "in", 0 = role "out"
    float transitionDirX;       // push/slide/wipe direction, unit vector
    float transitionDirY;
    float premultiplied;        // 1 for text/shape/image textures
    float slate;                // 1 = missing media, ignore the texture
    // A video track's frames arrive in the source's CODED orientation, while
    // the model measures the DISPLAY size (§7.7). These turn the sampling
    // coordinates instead of the quad, so a portrait phone clip samples right
    // way up with no change to the placement math.
    float sourceQuarterTurns;   // 0…3, clockwise, texture → display
    float sourceMirrored;       // 1 = also flipped horizontally
    // The transition PARTNER's canvas-space box and its own alpha, filled in
    // for the OUTGOING half of a dissolve only (see the fragment stage for
    // why). An empty box means "the partner covers nothing here".
    float partnerMinX;
    float partnerMinY;
    float partnerMaxX;
    float partnerMaxY;
    float partnerAlpha;
    float reserved0;            // padding: keeps the struct a multiple of 16
    float reserved1;
    float reserved2;
};

// Display-space UV back to the texture's own coded space. The inverse of the
// source's preferred transform, restricted to the quarter turns and the
// horizontal mirror that real files carry.
static inline float2 orientedUV(float2 uv, float quarterTurns, float mirrored) {
    float2 t = uv;
    int q = int(quarterTurns + 0.5);
    if (q == 1) {
        t = float2(uv.y, 1.0 - uv.x);
    } else if (q == 2) {
        t = float2(1.0 - uv.x, 1.0 - uv.y);
    } else if (q == 3) {
        t = float2(1.0 - uv.y, uv.x);
    }
    if (mirrored > 0.5) {
        t.x = 1.0 - t.x;
    }
    return t;
}

struct Varyings {
    float4 position [[position]];
    // Texture coordinates inside the crop window.
    float2 uv;
    // 0…1 across the CROPPED quad — the corner-radius mask, the slate
    // pattern and the wipe threshold all work in this space.
    float2 local;
};

// A triangle strip over the unit square: (0,0) (1,0) (0,1) (1,1).
constant float2 kQuad[4] = {
    float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0), float2(1.0, 1.0)
};

static inline float2 rotate2(float2 v, float radians) {
    // y-down space, so the standard rotation matrix turns CLOCKWISE on
    // screen — which is what the model's positive `rotation` means.
    float c = cos(radians);
    float s = sin(radians);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

vertex Varyings reelcut_layer_vertex(uint vid [[vertex_id]],
                                     constant LayerUniforms &u [[buffer(0)]]) {
    float2 canvas = max(float2(u.canvasWidth, u.canvasHeight), float2(1.0));
    float2 srcSize = max(float2(u.sourceWidth, u.sourceHeight), float2(1.0));
    float2 cropTL = float2(u.cropL, u.cropT);
    float2 cropBR = float2(u.cropR, u.cropB);
    float2 cropped = max(srcSize - cropTL - cropBR, float2(1.0));
    float2 anchor = float2(u.anchorX, u.anchorY);
    float2 corner = kQuad[vid];

    // Place the UNCROPPED rectangle centred on the anchor, then step in by
    // the crop: cropping removes edges in place and never moves content.
    float2 topLeft = anchor - srcSize * u.scale * 0.5 + cropTL * u.scale;
    float2 pos = topLeft + corner * cropped * u.scale;
    pos = anchor + rotate2(pos - anchor, u.rotation);

    int kind = int(u.transitionKind + 0.5);
    float p = clamp(u.transitionProgress, 0.0, 1.0);
    bool incoming = u.transitionIncoming > 0.5;
    float2 dir = float2(u.transitionDirX, u.transitionDirY);
    if (kind == kTransitionZoom) {
        // Outgoing pushes toward the viewer, incoming arrives from behind.
        float z = incoming ? mix(0.75, 1.0, p) : mix(1.0, 1.25, p);
        pos = anchor + (pos - anchor) * z;
    } else if (kind == kTransitionPush) {
        // Both move: the outgoing leaves along `dir`, the incoming arrives
        // from the opposite edge and lands exactly at p = 1.
        pos += dir * canvas * (incoming ? (p - 1.0) : p);
    } else if (kind == kTransitionSlide) {
        // Only the incoming moves; the outgoing stays put underneath.
        if (incoming) {
            pos += dir * canvas * (p - 1.0);
        }
    }

    Varyings out;
    out.position = float4(pos.x / canvas.x * 2.0 - 1.0,
                          1.0 - pos.y / canvas.y * 2.0, 0.0, 1.0);
    out.uv = (cropTL + corner * cropped) / srcSize;
    out.local = corner;
    return out;
}

// The missing-media slate: a dark plate with diagonal stripes, generated
// here so no asset ships with the app and a relink-pending clip still has
// something recognisable on the canvas.
static inline float3 slateColor(float2 px) {
    float stripe = fract((px.x + px.y) / 48.0);
    float3 plate = float3(0.10, 0.11, 0.13);
    float3 bar = float3(0.19, 0.20, 0.24);
    return stripe < 0.5 ? plate : bar;
}

// Signed distance to a rounded rectangle centred at the origin.
static inline float roundedBoxDistance(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

static inline float3 hueRotate(float3 c, float radians) {
    float cs = cos(radians);
    float sn = sin(radians);
    float3 r = float3(0.299 + 0.701 * cs + 0.168 * sn,
                      0.587 - 0.587 * cs + 0.330 * sn,
                      0.114 - 0.114 * cs - 0.497 * sn);
    float3 g = float3(0.299 - 0.299 * cs - 0.328 * sn,
                      0.587 + 0.413 * cs + 0.035 * sn,
                      0.114 - 0.114 * cs + 0.292 * sn);
    float3 b = float3(0.299 - 0.300 * cs + 1.250 * sn,
                      0.587 - 0.588 * cs - 1.050 * sn,
                      0.114 + 0.886 * cs - 0.203 * sn);
    return float3(dot(c, r), dot(c, g), dot(c, b));
}

fragment float4 reelcut_layer_fragment(Varyings in [[stage_in]],
                                       constant LayerUniforms &u [[buffer(0)]],
                                       texture2d<float> source [[texture(0)]],
                                       sampler samp [[sampler(0)]]) {
    float2 srcSize = max(float2(u.sourceWidth, u.sourceHeight), float2(1.0));
    float2 cropped = max(srcSize - float2(u.cropL + u.cropR, u.cropT + u.cropB), float2(1.0));

    float3 rgb;
    float alpha;
    if (u.slate > 0.5) {
        rgb = slateColor(in.local * cropped);
        alpha = 1.0;
    } else {
        float4 texel = source.sample(
            samp, orientedUV(in.uv, u.sourceQuarterTurns, u.sourceMirrored));
        alpha = texel.a;
        // Text, shape and image textures arrive PREMULTIPLIED (that is what
        // LayerRenderers hands over, and what this stage outputs); video
        // frames arrive straight. Every effect below wants straight colour,
        // so undo the premultiply here and redo it once at the end.
        rgb = u.premultiplied > 0.5 ? texel.rgb / max(texel.a, 1e-4) : texel.rgb;
    }

    // Corner radius: a rounded-rect SDF in SOURCE pixels over the cropped
    // rectangle, feathered by one screen pixel (which is 1/scale source
    // pixels) so the curve does not stair-step on a scaled-up layer.
    float radius = clamp(u.cornerRadius, 0.0, min(cropped.x, cropped.y) * 0.5);
    if (radius > 0.0) {
        float2 px = in.local * cropped;
        float d = roundedBoxDistance(px - cropped * 0.5, cropped * 0.5, radius);
        float feather = max(1.0 / max(u.scale, 1e-4), 1e-4);
        alpha *= clamp(0.5 - d / feather, 0.0, 1.0);
    }

    // Chroma key (M3): distance from the key colour opens a soft hole, then
    // the spill control pulls the remaining fringe toward its own luma.
    if (u.chromaEnabled > 0.5) {
        float3 key = float3(u.chromaKeyR, u.chromaKeyG, u.chromaKeyB);
        float d = distance(rgb, key);
        float keyed = smoothstep(u.chromaTolerance, u.chromaTolerance + max(u.chromaSoftness, 1e-4), d);
        alpha *= keyed;
        float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        rgb = mix(rgb, float3(luma), u.chromaSpill * (1.0 - keyed));
    }

    rgb += u.brightness;
    rgb = (rgb - 0.5) * (1.0 + u.contrast) + 0.5;
    float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb = mix(float3(luma), rgb, 1.0 + u.saturation);
    if (abs(u.hue) > 1e-4) {
        rgb = hueRotate(rgb, u.hue);
    }

    // Transitions. The recipe hands the pair as two adjacent layers with the
    // same kind and progress, so each pass only needs its own half: every
    // kind decomposes into a per-layer weight (here) plus a per-layer offset
    // (in the vertex stage), which is why no offscreen intermediate exists.
    int kind = int(u.transitionKind + 0.5);
    float p = clamp(u.transitionProgress, 0.0, 1.0);
    bool incoming = u.transitionIncoming > 0.5;
    if (kind == kTransitionDissolve || kind == kTransitionZoom) {
        if (incoming) {
            alpha *= p;
        } else {
            // A dissolve must hold its total weight at 1: (1-p) of the
            // outgoing plus p of the incoming. But the pair is TWO
            // source-over passes, and the incoming pass multiplies whatever
            // this pass leaves behind by (1 - p·alphaIncoming). Weighting
            // this layer by (1-p) as well therefore lands it at (1-p)² and
            // the whole frame dips ~25 % dark at the midpoint. Dividing by
            // the incoming pass's own attenuation is the exact inverse of
            // that second multiply — algebraically identical to the one-pass
            // mix(out, in, p) spec §7.5 describes.
            //
            // Where the incoming does NOT cover this pixel there is no
            // second multiply, the divisor is 1, and the layer correctly
            // fades to whatever is behind it.
            float2 canvasPoint = in.position.xy;
            bool insidePartner =
                canvasPoint.x >= u.partnerMinX && canvasPoint.x <= u.partnerMaxX &&
                canvasPoint.y >= u.partnerMinY && canvasPoint.y <= u.partnerMaxY;
            float cover = insidePartner ? clamp(u.partnerAlpha, 0.0, 1.0) : 0.0;
            alpha *= (1.0 - p) / max(1.0 - p * cover, 1e-4);
        }
    } else if (kind == kTransitionFadeBlack || kind == kTransitionFadeWhite) {
        // First half: the outgoing clip fades to the colour. Second half:
        // the incoming clip fades up from it.
        float3 fade = kind == kTransitionFadeWhite ? float3(1.0) : float3(0.0);
        if (incoming) {
            rgb = mix(fade, rgb, clamp((p - 0.5) * 2.0, 0.0, 1.0));
            alpha *= p >= 0.5 ? 1.0 : 0.0;
        } else {
            rgb = mix(rgb, fade, clamp(p * 2.0, 0.0, 1.0));
            alpha *= p < 0.5 ? 1.0 : 0.0;
        }
    } else if (kind == kTransitionWipe) {
        // A moving edge along the wipe direction, in the layer's own 0…1
        // space, with a 0.5 % soft edge so it does not crawl.
        float axis = abs(u.transitionDirY) > abs(u.transitionDirX) ? in.local.y : in.local.x;
        if (u.transitionDirX < 0.0 || u.transitionDirY < 0.0) {
            axis = 1.0 - axis;
        }
        float edge = smoothstep(p - 0.005, p + 0.005, axis);
        alpha *= incoming ? (1.0 - edge) : edge;
    }

    alpha = clamp(alpha * u.opacity, 0.0, 1.0);
    rgb = clamp(rgb, 0.0, 1.0);
    // PREMULTIPLIED out: the pipeline blends source-over with
    // (one, one_minus_source_alpha), which is only correct premultiplied.
    return float4(rgb * alpha, alpha);
}
