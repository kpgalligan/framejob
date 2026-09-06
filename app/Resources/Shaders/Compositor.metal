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
//  uniforms. Add fields at the END, in groups of four (the struct is
//  deliberately a multiple of 16 bytes — 68 floats, 272 bytes, as of the M3
//  effect block), and mirror them in Swift in the same order.
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

// Filter kind codes. Mirrors `FilterKind.shaderCode` in
// `ProjectSnapshot.swift`, which is the model's declaration order plus one —
// so 0 can mean "this slot holds no filter". Re-ordering `FilterKind` there
// re-orders these, which is why that enum's doc comment says not to.
constant int kFilterNone     = 0;
constant int kFilterBlur     = 1;
constant int kFilterSharpen  = 2;
constant int kFilterPixelate = 3;
constant int kFilterSepia    = 4;
constant int kFilterNoir     = 5;
constant int kFilterVignette = 6;
constant int kFilterInvert   = 7;

// What `amount = 1` means for each of the three filters whose strength is a
// LENGTH. All three are SOURCE pixels, the frame every other length on a
// layer is measured in (the crop, the corner radius, the shadow's blur and
// distance, the spotlight's box) — so a filter, like all of those, grows
// with the layer when the layer is scaled up.
constant float kBlurMaxRadius    = 24.0;   // the outer tap ring at amount 1
constant float kPixelateMaxBlock = 64.0;   // block side at amount 1
constant float kSharpenRadius    = 1.5;    // unsharp low-pass reach
// Unsharp gain at amount 1. Past about 2 the halo is louder than the detail.
constant float kSharpenMaxGain   = 2.0;

/// Whether THIS SPECIALIZATION of the fragment stage carries the two filters
/// that gather neighbouring pixels — blur and sharpen. A function constant and
/// not a uniform, because the difference has to be made by the compiler and
/// not by a branch: `MetalRenderer` builds two pipeline states from this one
/// function and picks per layer (`FilterProps.needsGather`).
///
/// It is a function constant because it was MEASURED. A runtime `if` around
/// the gather is not free even when it is never taken: the tap loop's
/// accumulators and the unsharp's five live samples raise the register count
/// of the WHOLE shader, and an Apple GPU allocates registers per pipeline, so
/// the lower occupancy is paid by every fragment of every layer, filters or
/// not. One full-bleed 1080p layer with NO filters at all, 200 frames per
/// sample, three interleaved runs (the spread is the machine's clocks, which is
/// why the runs are interleaved and the ranges are quoted rather than a point):
///
///     the pre-M3 shader                        0.30 – 0.32 ms
///     this shader, kGatherFilters FALSE        0.30 – 0.33 ms
///     this shader, kGatherFilters TRUE         0.35 – 0.37 ms
///
/// The specialization without the gather is indistinguishable from the shader
/// that never had any of this in it. The one WITH it is consistently a sixth of
/// a frame slower — for code that did not run. The gather itself, when it does
/// run, is 0.46 ms on top of that.
constant bool kGatherFilters [[function_constant(0)]];

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
    // 1 = this pass is a shadow MASK pass and the fragment stage must return
    // the layer's COVERAGE instead of its colour, so the blur that follows
    // sees a clean silhouette (§7.5). Everything that shapes the alpha — the
    // crop, the corner radius, the chroma hole, the transition weight, the
    // layer's own opacity — still runs: that is the whole reason the mask is
    // drawn by this pipeline and not by a second, simpler one, which would
    // start agreeing with this one and quietly stop.
    float shadowMask;
    // ── The M3 effect block (§4.2). `CompositorEffects.swift` fills every
    // field below and argues each one's meaning; what they DO is the fragment
    // stage's order of operations, written out above `reelcut_layer_fragment`.
    // The four reserved floats that used to sit here are the first four of
    // them: 40 + 28 = 68 floats = 272 bytes, and 272 is 17 × 16, so the tail
    // is now empty. The next field to land must come with three companions,
    // or bring the padding back.
    //
    // Four filter slots, applied in slot order. `MAX_FILTERS` in `model.rs`
    // is four BECAUSE this block carries four (kind, amount) pairs — the cap
    // is this struct, not taste.
    float filterKind0;          // a kFilter* code; 0 = empty slot
    float filterKind1;
    float filterKind2;
    float filterKind3;
    float filterAmount0;        // 0…1
    float filterAmount1;
    float filterAmount2;
    float filterAmount3;
    // The mirrored copy below the layer. `reflectionPass` is 1 ONLY on the
    // extra draw `MetalRenderer.encodeReflection` puts in front of the
    // layer's own; on every other draw it is 0 and the four fields under it
    // are dead. Both stages branch on it — the vertex stage mirrors the quad,
    // the fragment stage fades it.
    float reflectionPass;
    float reflectionOpacity;    // 0…1, where the reflection meets the layer
    float reflectionHeight;     // fraction of the CROPPED height, 0…1
    float reflectionGap;        // source px between layer and reflection
    float reflectionFalloff;    // 0 = no fade, 1 = transparent at `height`
    // The spotlight. Centre and box are SOURCE pixels measured from the
    // centre of the CROPPED rectangle — the same frame `cornerRadius` and
    // the crop insets use, so a spotlight survives a scale change.
    float spotEnabled;
    float spotShape;            // 0 = rect, 1 = ellipse
    float spotX;
    float spotY;
    float spotW;
    float spotH;
    float spotFeather;          // source px of ramp across the region's edge
    float spotDim;              // 0…1, how much darker OUTSIDE
    float spotZoom;             // 1…2, magnification INSIDE
    // The rectangle a layer flattened out of a nest is clipped to (§7.3's
    // `clip_rect`). ABSOLUTE canvas pixels, y down, origin at the canvas's
    // top-left corner — the space `[[position]]` already arrives in, so the
    // test costs no conversion. Nothing sets it yet: the core emits `null`
    // for every layer until nests land.
    float clipEnabled;
    float clipX;                // the rectangle's CENTRE
    float clipY;
    float clipW;
    float clipH;
    float clipRotation;         // radians, clockwise, about that centre
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
    // pattern, the vignette, the spotlight and the wipe threshold all work in
    // this space. The invariant every one of them relies on:
    // `uv * sourceSize == cropTopLeft + local * cropped`, on the reflection
    // pass as much as on the layer's own.
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
    float2 pos;
    // The point this vertex samples, in SOURCE pixels inside the crop window.
    float2 samplePx;
    float2 local;
    if (u.reflectionPass > 0.5) {
        // The mirrored copy: a quad as wide as the cropped rectangle and
        // `reflectionHeight` of it tall, hung under the layer's bottom edge
        // across `reflectionGap`, sampling the layer bottom-up.
        //
        // The mirror is done HERE and not by flipping the uv in the fragment
        // stage, because `local` has to be mirrored with it: the corner
        // radius, the vignette and the spotlight all read `local`, and a
        // reflection whose geometry ran the right way up while its pixels ran
        // upside down would round the wrong corners and light the wrong half.
        // One flip in one place keeps every later stage free of a special
        // case — the fragment stage's only mention of the reflection is its
        // fade.
        float reflH = max(cropped.y * clamp(u.reflectionHeight, 0.0, 1.0), 1e-4);
        pos = topLeft
            + float2(corner.x * cropped.x,
                     cropped.y + max(u.reflectionGap, 0.0) + corner.y * reflH)
                * u.scale;
        samplePx = cropTL + float2(corner.x * cropped.x, cropped.y - corner.y * reflH);
        local = float2(corner.x, 1.0 - corner.y * reflH / cropped.y);
    } else {
        pos = topLeft + corner * cropped * u.scale;
        samplePx = cropTL + corner * cropped;
        local = corner;
    }
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
    out.uv = samplePx / srcSize;
    out.local = local;
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

// MARK: - The M3 effect helpers

/// One texture read expressed in the layer's own terms: straight (not
/// premultiplied) colour with the chroma key and the colour adjust already
/// applied, plus the alpha the key left behind.
///
/// It exists so that a filter which gathers neighbours gathers the SAME KIND
/// of pixel as the centre one. Every stage inside it is either affine in rgb
/// (brightness, contrast, saturation, hue) or a smooth function of the
/// sampled colour (the spill), which is what makes the blur below exact
/// rather than approximate — see the order-of-operations note.
struct LayerSample {
    float3 rgb;
    float alpha;
};

/// The chroma key and the colour adjust, on straight colour. Split from the
/// sample below so the missing-media slate goes through exactly the same
/// grade it always has — it is generated colour, not sampled, but a brightness
/// edit that stopped showing on a relink-pending clip would be a change nobody
/// asked for.
static inline LayerSample gradeSample(float3 rgb, float alpha,
                                      constant LayerUniforms &u) {
    // Chroma key (M3): distance from the key colour opens a soft hole, then
    // the spill control pulls the remaining fringe toward its own luma.
    if (u.chromaEnabled > 0.5) {
        float3 key = float3(u.chromaKeyR, u.chromaKeyG, u.chromaKeyB);
        float d = distance(rgb, key);
        float keyed = smoothstep(u.chromaTolerance,
                                 u.chromaTolerance + max(u.chromaSoftness, 1e-4), d);
        alpha *= keyed;
        float keyLuma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        rgb = mix(rgb, float3(keyLuma), u.chromaSpill * (1.0 - keyed));
    }

    rgb += u.brightness;
    rgb = (rgb - 0.5) * (1.0 + u.contrast) + 0.5;
    float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb = mix(float3(luma), rgb, 1.0 + u.saturation);
    if (abs(u.hue) > 1e-4) {
        rgb = hueRotate(rgb, u.hue);
    }

    LayerSample out;
    out.rgb = rgb;
    out.alpha = alpha;
    return out;
}

static inline LayerSample layerSample(texture2d<float> source, sampler samp,
                                      float2 uv, constant LayerUniforms &u) {
    float4 texel = source.sample(
        samp, orientedUV(uv, u.sourceQuarterTurns, u.sourceMirrored));
    // Text, shape and image textures arrive PREMULTIPLIED (that is what
    // LayerRenderers hands over, and what this stage outputs); video frames
    // arrive straight. Every effect wants straight colour, so undo the
    // premultiply here and redo it once at the end of the fragment.
    float3 rgb = u.premultiplied > 0.5 ? texel.rgb / max(texel.a, 1e-4) : texel.rgb;
    return gradeSample(rgb, texel.a, u);
}

/// The three neighbourhood filters, folded out of the slot loop into one
/// description of how the layer is to be sampled. See the order-of-operations
/// note for why they cannot run in slot order.
struct FilterPlan {
    float blurRadius;   // source px; 0 = no gather at all
    float sharpen;      // unsharp gain; 0 = no cross taps
    float block;        // pixelation block side in source px; ≤ 1 = none
    // Whether any slot holds one of the four PER-PIXEL filters. Every field
    // of this struct comes from the constant buffer and is therefore uniform
    // across the draw, so this flag is what turns "four empty slots" into a
    // branch not taken rather than four comparisons per fragment.
    float hasPoint;
};

/// Slot `i` as (kind code, amount). Metal cannot index a struct's fields, and
/// the four slots are scalars by the layout contract, so the switch is what
/// there is — it unrolls to nothing at all when the slots are empty.
static inline float2 filterSlot(constant LayerUniforms &u, int i) {
    if (i == 0) { return float2(u.filterKind0, u.filterAmount0); }
    if (i == 1) { return float2(u.filterKind1, u.filterAmount1); }
    if (i == 2) { return float2(u.filterKind2, u.filterAmount2); }
    return float2(u.filterKind3, u.filterAmount3);
}

static inline FilterPlan filterPlan(constant LayerUniforms &u) {
    FilterPlan plan;
    plan.blurRadius = 0.0;
    plan.sharpen = 0.0;
    plan.block = 0.0;
    plan.hasPoint = 0.0;
    // One test for "no filters at all", ahead of the slot walk. Kind codes are
    // never negative and 0 means an empty slot, so the sum is below a half
    // exactly when all four are empty. This is the fast path a layer with no
    // filters takes, and it is here because it was measured: the walk below is
    // four comparisons and a `sqrt` branch per slot, and leaving it
    // unconditional cost a full-bleed 1080p layer with no filters about a
    // tenth of a millisecond it had never paid before.
    if (u.filterKind0 + u.filterKind1 + u.filterKind2 + u.filterKind3 < 0.5) {
        return plan;
    }
    for (int i = 0; i < 4; ++i) {
        float2 slot = filterSlot(u, i);
        int kind = int(slot.x + 0.5);
        float amount = clamp(slot.y, 0.0, 1.0);
        if (kind == kFilterBlur) {
            // Two blurs in a row are one wider blur: Gaussians compose by
            // adding their variances, so the radii add in quadrature.
            float r = amount * kBlurMaxRadius;
            plan.blurRadius = sqrt(plan.blurRadius * plan.blurRadius + r * r);
        } else if (kind == kFilterSharpen) {
            plan.sharpen += amount * kSharpenMaxGain;
        } else if (kind == kFilterPixelate) {
            // Two pixelations are the coarser of the two: quantizing an
            // already-quantized grid to a finer one changes nothing.
            plan.block = max(plan.block, mix(1.0, kPixelateMaxBlock, amount));
        } else if (kind != kFilterNone) {
            plan.hasPoint = 1.0;
        }
    }
    return plan;
}

/// The blur's tap ring, in units of the blur radius: a hexagon at half the
/// radius and a second at the full radius, turned 30° off it.
///
/// TWELVE taps plus the centre is the budget, and it is a budget: measured at
/// 0.45 ms on a full-bleed 1080p layer, against the 8 ms the spec gives the
/// whole compositor — room for the rest of a layer stack, and not much room
/// for a wider kernel. A 5 × 5 grid (25 taps) would roughly double that for a
/// blur nobody would tell apart; a 3 × 3 grid (9) is cheaper but breaks into
/// nine visible copies of the picture as soon as the radius passes a few
/// pixels, which at `kBlurMaxRadius` = 24 it certainly does. Two staggered
/// rings is the arrangement that spends the taps on ANGLES instead of on a
/// grid, so what a large radius degrades into is a slight radial ripple
/// rather than ghosting. The tap count is fixed: four blur filters at once
/// cost the same thirteen taps as one, because `filterPlan` has already
/// added their radii together.
constant float2 kBlurRing[12] = {
    float2( 0.500,  0.000), float2( 0.250,  0.433), float2(-0.250,  0.433),
    float2(-0.500,  0.000), float2(-0.250, -0.433), float2( 0.250, -0.433),
    float2( 0.866,  0.500), float2( 0.000,  1.000), float2(-0.866,  0.500),
    float2(-0.866, -0.500), float2( 0.000, -1.000), float2( 0.866, -0.500)
};

static inline LayerSample gatherBlur(texture2d<float> source, sampler samp,
                                     float2 uv, float2 srcSize, float radius,
                                     constant LayerUniforms &u) {
    // Weights: 4 at the centre, 2 on the inner ring, 1 on the outer — a
    // coarse radial Gaussian summing to 22.
    float2 reach = radius / srcSize;
    LayerSample centre = layerSample(source, samp, uv, u);
    // Accumulated PREMULTIPLIED and divided back out at the end. That is the
    // only way to average across an alpha edge: the straight colour of a
    // fully transparent texel is meaningless (it was divided by nothing), and
    // averaging it in would bleed black into every soft edge of a text layer.
    float3 rgb = centre.rgb * centre.alpha * 4.0;
    float alpha = centre.alpha * 4.0;
    for (int i = 0; i < 12; ++i) {
        float weight = i < 6 ? 2.0 : 1.0;
        LayerSample tap = layerSample(source, samp, uv + kBlurRing[i] * reach, u);
        rgb += tap.rgb * tap.alpha * weight;
        alpha += tap.alpha * weight;
    }
    LayerSample out;
    out.alpha = alpha / 22.0;
    out.rgb = rgb / max(alpha, 1e-4);
    return out;
}

/// One of the four PER-PIXEL filters. The three neighbourhood ones are not
/// here — `filterPlan` took them — and reach this function as `kFilterNone`
/// would: unmatched, returning the colour untouched.
static inline float3 pointFilter(int kind, float amount, float3 rgb, float2 local) {
    if (kind == kFilterSepia) {
        // The photographic sepia matrix, mixed in by `amount` so the slider
        // runs from the original picture to the full tone.
        float3 toned = float3(dot(rgb, float3(0.393, 0.769, 0.189)),
                              dot(rgb, float3(0.349, 0.686, 0.168)),
                              dot(rgb, float3(0.272, 0.534, 0.131)));
        return mix(rgb, toned, amount);
    }
    if (kind == kFilterNoir) {
        // Not a plain desaturate — that is what `saturation: -1` already is,
        // and a filter that duplicated a colour control would not earn its
        // slot. Noir is monochrome plus contrast, so the luma goes through an
        // S-curve about mid grey before it is mixed back in.
        float luma = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        float pushed = clamp((luma - 0.5) * 1.35 + 0.5, 0.0, 1.0);
        return mix(rgb, float3(pushed), amount);
    }
    if (kind == kFilterVignette) {
        // Radial darkening in the CROPPED rectangle's own 0…1 space, so the
        // fall-off is an ellipse that matches the layer's aspect ratio rather
        // than a circle that would leave a wide layer's corners untouched.
        // √2 puts the corner at exactly 1.
        float2 d = (local - 0.5) * 2.0;
        float r = length(d) * 0.70710678;
        return rgb * (1.0 - smoothstep(0.45, 1.0, r) * amount);
    }
    if (kind == kFilterInvert) {
        return mix(rgb, 1.0 - rgb, amount);
    }
    return rgb;
}

/// The spotlight region as a 0…1 mask in the layer's own source pixels: 1
/// well inside the region, 0 well outside, `feather` pixels of ramp across the
/// edge. `rel` is the fragment's offset from the region's centre.
///
/// The feather is a PARAMETER and not read from the block, because the dim and
/// the lens want different ones — see the zoom, which argues why.
static inline float spotlightMask(float2 rel, constant LayerUniforms &u, float feather) {
    float2 halfSize = max(float2(u.spotW, u.spotH) * 0.5, float2(1e-3));
    float d;
    if (u.spotShape > 0.5) {
        // Ellipse. |p / halfSize| − 1 is zero on the boundary but is not a
        // distance — along the long axis it is off by the aspect ratio, which
        // would make the feather band that much wider there. Dividing by its
        // own gradient turns it into one: exact for a circle, and accurate to
        // a fraction of a pixel near the edge of an ellipse, which is where
        // the dim's feather reads it. Far from the boundary — which only the
        // zoom's wider ramp reaches — the level sets go slightly boxy, and all
        // that decides there is how the magnification tapers.
        float2 q = rel / halfSize;
        float r = length(q);
        float2 grad = q / halfSize;
        d = r > 1e-4 ? (r - 1.0) * r / max(length(grad), 1e-6)
                     : -min(halfSize.x, halfSize.y);
    } else {
        float2 e = abs(rel) - halfSize;
        d = length(max(e, 0.0)) + min(max(e.x, e.y), 0.0);
    }
    return clamp(0.5 - d / max(feather, 1e-3), 0.0, 1.0);
}

// MARK: - The layer fragment stage

// ORDER OF OPERATIONS. Fixed by the M3 contract, and each stage is where it
// is for a reason worth keeping:
//
//   1. spotlight zoom remap    moves the sampling coordinate, so it can only
//                              run BEFORE the sample
//   2. pixelate                quantizes that same coordinate
//   3. sample, or the slate    `layerSample` — un-premultiply, chroma key
//                              and spill, brightness/contrast/saturation/hue
//   4. blur, then sharpen      gather neighbours, each one through (3)
//   5. the point filters       sepia, noir, vignette, invert, IN SLOT ORDER
//   6. spotlight dim           after every colour stage: the dim is a light
//                              on the layer, not something the filters act on
//   7. coverage                corner radius × nest clip rectangle
//   8. transition weight
//   9. opacity, then the reflection's fade
//  10. premultiply out
//
// **Why the neighbourhood filters do not run in slot order.** Blur, sharpen
// and pixelate reach for neighbouring pixels, and in a single pass a second
// gather would have to gather the first gather's output — which does not
// exist, because there is no intermediate. So they are folded into the sample
// instead (steps 1, 2 and 4) and the four point filters run in order after.
//
// That reordering is EXACT, not a concession, for three of the four. Sepia
// and invert are affine in rgb and noir is affine up to its own clamp, and a
// blur is a convex average, so mean(f(x)) = f(mean(x)) — running them before
// or after the gather gives the same pixel. Pixelate is a point selection,
// which commutes with anything per-pixel by construction. The one filter with
// a spatial term is vignette, and even there the tap ring is symmetric, so the
// first-order error cancels and what is left is the SECOND derivative of a
// smoothstep across a blur radius: a fraction of a percent of brightness at
// `kBlurMaxRadius`, well inside the rounding of an 8-bit frame.
//
// **What a layer with no effects costs.** Measured, not asserted. A full-bleed
// 1080p layer with no filters, no spotlight, no reflection and no clip rect
// renders in 0.30–0.33 ms, which is what the same layer measured through the
// pre-M3 shader — the difference is inside the run-to-run spread of the
// machine's own GPU clocks. All that layer pays is the single comparison below
// and the seven uniform reads that answer it; everything else is behind that
// comparison, or compiled out of its pipeline entirely (`kGatherFilters`).
//
// What each effect DOES cost on that same layer, over the no-effect baseline:
// a clip rectangle 0.02 ms, a reflection 0.02, a spotlight with its lens 0.04,
// a pixelate 0.03, four point filters together 0.08, a sharpen 0.18, a blur
// 0.46. Every one of them at once measured 1.05 ms — an eighth of the 8 ms the
// spec gives the whole compositor.
fragment float4 reelcut_layer_fragment(Varyings in [[stage_in]],
                                       constant LayerUniforms &u [[buffer(0)]],
                                       texture2d<float> source [[texture(0)]],
                                       sampler samp [[sampler(0)]]) {
    float2 srcSize = max(float2(u.sourceWidth, u.sourceHeight), float2(1.0));
    float2 cropped = max(srcSize - float2(u.cropL + u.cropR, u.cropT + u.cropB), float2(1.0));

    // The fragment's position inside the cropped rectangle, in source pixels.
    // The slate, the corner radius and the spotlight all measure from it, and
    // the vertex stage guarantees `uv * srcSize == cropTopLeft + localPx` —
    // which is what lets the spotlight compute its remap here and hand the
    // result back as a uv displacement.
    float2 localPx = in.local * cropped;

    // ONE test for "does this layer carry any M3 effect at all", read by both
    // of the two blocks below. Kind codes and flags are all non-negative and
    // all zero when nothing is set, so a single sum-and-compare answers it.
    //
    // It is here because it was MEASURED. The natural shape — one `if` per
    // effect, spread down the stage in the order of operations — is nine tests
    // an Apple GPU evaluates per fragment, and they showed up on a layer that
    // has none of the effects. Collapsing the nine into one leaves the
    // effect-free layer paying a single comparison, which is what leaves it
    // measuring the same as the pre-M3 shader.
    bool effects = (u.filterKind0 + u.filterKind1 + u.filterKind2 + u.filterKind3
                    + u.spotEnabled + u.clipEnabled + u.reflectionPass) > 0.5;

    float2 uv = in.uv;
    float spot = 1.0;
    FilterPlan plan;
    plan.blurRadius = 0.0;
    plan.sharpen = 0.0;
    plan.block = 0.0;
    plan.hasPoint = 0.0;
    if (effects) {
        // (1) The spotlight region. Evaluated once and read twice: to bend the
        // sampling coordinate now, and to darken the outside at step (6).
        if (u.spotEnabled > 0.5) {
            float2 centre = cropped * 0.5 + float2(u.spotX, u.spotY);
            float2 halfSize = max(float2(u.spotW, u.spotH) * 0.5, float2(1e-3));
            spot = spotlightMask(localPx - centre, u, u.spotFeather);
            // The model's own ceiling is 2 (`SPOT_ZOOM_MAX`) and Swift already
            // clamps to it; 8 here is only a guard against a uniform from some
            // future version, not a second opinion on the range.
            float zoom = clamp(u.spotZoom, 1.0, 8.0);
            if (zoom > 1.0001) {
                // Pull the sampling point toward the region's centre by 1/zoom,
                // faded in across the edge rather than switched. A hard switch
                // would TEAR the picture along the boundary — the pixel just
                // inside and the pixel just outside would come from places `zoom`
                // apart — whereas blending the factor keeps the map continuous,
                // and monotone in |r| (the factor only ever grows as the mask
                // falls), so the region magnifies without the coordinate folding
                // back on itself.
                //
                // The lens gets its OWN ramp, at least as wide as the distance the
                // magnification has to travel. Blending across a NARROW band
                // instead means the sampling point sweeps most of the way from
                // 1/zoom to 1 within a few pixels, and the picture bunches into a
                // hard bright ring at the region's edge — visible on any content
                // with a line in it, and the first thing anyone would report. The
                // width below bounds that stretch at about 1.5×, which reads as a
                // loupe. It makes the lens edge softer than the LIGHT edge, and
                // that is the intended difference: `feather` says how sharply the
                // light falls off, and the two are not the same question.
                float ramp = max(u.spotFeather,
                                 max(halfSize.x, halfSize.y) * (1.0 - 1.0 / zoom));
                float lens = spotlightMask(localPx - centre, u, ramp);
                float k = mix(1.0, 1.0 / zoom, lens);
                uv += ((centre + (localPx - centre) * k) - localPx) / srcSize;
            }
        }

        // (2) and (4): the three neighbourhood filters, folded into the sample.
        plan = filterPlan(u);
        if (plan.block > 1.0) {
            // Pixelate: snap the sampling point to the centre of its block. The
            // GEOMETRY is untouched — `localPx` still runs smoothly — so a
            // pixelated layer keeps its clean rounded corners and its clean edge.
            float2 px = uv * srcSize;
            uv = ((floor(px / plan.block) + 0.5) * plan.block) / srcSize;
        }
    }

    // (3) The sample.
    LayerSample base;
    if (u.slate > 0.5) {
        base = gradeSample(slateColor(localPx), 1.0, u);
    } else if (kGatherFilters && plan.blurRadius > 0.0) {
        base = gatherBlur(source, samp, uv, srcSize, plan.blurRadius, u);
    } else {
        base = layerSample(source, samp, uv, u);
    }
    float3 rgb = base.rgb;
    float alpha = base.alpha;
    // The reflection's own fade, computed in the block below and applied with
    // the layer's opacity at the very end. It is a plain multiply, so where it
    // is worked out cannot show, and computing it here keeps the tail of this
    // stage free of a branch every ordinary layer would have to test.
    float reflectFade = 1.0;

    if (effects) {
        if (kGatherFilters && plan.sharpen > 0.0 && u.slate < 0.5) {
            // Unsharp mask, as a DETAIL TERM added on top rather than as a
            // multiply of what is already there: four cross taps a pixel and a
            // half out give the low frequency, and the centre minus that low
            // frequency is the detail. With no blur in front, `sharpCentre` is
            // the pixel itself and this is the textbook `x + k·(x − lowpass(x))`.
            //
            // With a blur in front it takes ONE more tap and stays meaningful:
            // the detail comes from the unblurred texture, so what is added back
            // is exactly the high frequency the blur removed. Taking the detail
            // from the BLURRED value instead would invert the sign — blur(x)
            // minus a narrower low-pass of x is negative detail — and a
            // blur-then-sharpen pair would come out blurrier than the blur alone.
            //
            // Alpha is left alone deliberately: sharpening coverage rings a
            // bright halo round every glyph of a text layer.
            float2 reach = kSharpenRadius / srcSize;
            float3 sharpCentre =
                plan.blurRadius > 0.0 ? layerSample(source, samp, uv, u).rgb : rgb;
            float3 lo = (layerSample(source, samp, uv + float2(reach.x, 0.0), u).rgb
                         + layerSample(source, samp, uv - float2(reach.x, 0.0), u).rgb
                         + layerSample(source, samp, uv + float2(0.0, reach.y), u).rgb
                         + layerSample(source, samp, uv - float2(0.0, reach.y), u).rgb)
                        * 0.25;
            rgb += plan.sharpen * (sharpCentre - lo);
        }

        // (5) The four point filters, in the order the model lists them. A slot
        // holding a neighbourhood filter — or nothing — falls through untouched.
        if (plan.hasPoint > 0.0) {
            for (int i = 0; i < 4; ++i) {
                float2 slot = filterSlot(u, i);
                rgb = pointFilter(int(slot.x + 0.5), clamp(slot.y, 0.0, 1.0), rgb, in.local);
            }
        }

        // (6) The spotlight's dim: everything outside the region goes darker, by
        // `spotDim` at full strength. Colour only — the layer is still there, it
        // is just unlit, and taking its alpha would show the canvas through it.
        if (u.spotEnabled > 0.5) {
            rgb *= mix(1.0 - clamp(u.spotDim, 0.0, 1.0), 1.0, spot);
        }

        // (7a) The nest clip rectangle: a rotated box in ABSOLUTE canvas pixels,
        // which is the space `position` already arrives in — hence no anchor, no
        // scale and no crop in this test. It is deliberately NOT in the layer's
        // own space: a nest clips the flattened layers to ITS canvas, and those
        // layers carry the nest's transform folded into their own, so the only
        // frame all of them share is the canvas.
        if (u.clipEnabled > 0.5) {
            float2 p = rotate2(in.position.xy - float2(u.clipX, u.clipY), -u.clipRotation);
            float2 e = abs(p) - max(float2(u.clipW, u.clipH), float2(0.0)) * 0.5;
            float d = length(max(e, 0.0)) + min(max(e.x, e.y), 0.0);
            // One canvas pixel of feather, and a canvas pixel is a screen pixel
            // here — no 1/scale, unlike the corner radius below.
            alpha *= clamp(0.5 - d, 0.0, 1.0);
        }

        // (9a) The mirrored copy fades LINEARLY down its own height, because that
        // is what the model's `falloff` is documented to mean: 0 does not fade at
        // all, 1 reaches transparent exactly at `height`. Anything curved here
        // would make the two endpoints the only honest readings of the number.
        //
        // `depth` — 0 where the mirrored copy touches the layer, 1 at the far end
        // of `reflectionHeight` — is recovered from `local` rather than carried as
        // a varying of its own: the vertex stage set `local.y = 1 − cornerY ·
        // height`, so this inverts that in two instructions inside a branch a
        // normal layer never enters. A fifth interpolant would have cost every
        // layer of every frame something, and Apple GPUs interpolate in the
        // fragment stage.
        if (u.reflectionPass > 0.5) {
            float depth = (1.0 - in.local.y) / max(clamp(u.reflectionHeight, 0.0, 1.0), 1e-4);
            reflectFade = clamp(u.reflectionOpacity, 0.0, 1.0)
                * max(1.0 - clamp(u.reflectionFalloff, 0.0, 1.0) * clamp(depth, 0.0, 1.0), 0.0);
        }
    }

    // (7b) Coverage. The corner radius and the clip rectangle above are both
    // pure alpha, so nothing else can tell where among the colour stages they
    // ran.
    //
    // Corner radius: a rounded-rect SDF in SOURCE pixels over the cropped
    // rectangle, feathered by one screen pixel (which is 1/scale source
    // pixels) so the curve does not stair-step on a scaled-up layer.
    float radius = clamp(u.cornerRadius, 0.0, min(cropped.x, cropped.y) * 0.5);
    if (radius > 0.0) {
        float d = roundedBoxDistance(localPx - cropped * 0.5, cropped * 0.5, radius);
        float feather = max(1.0 / max(u.scale, 1e-4), 1e-4);
        alpha *= clamp(0.5 - d / feather, 0.0, 1.0);
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

    alpha = clamp(alpha * u.opacity * reflectFade, 0.0, 1.0);
    if (u.shadowMask > 0.5) {
        // Coverage, not colour. The blur downstream only reads the alpha
        // channel; writing it to all four keeps the mask legible in a GPU
        // capture and is still a valid premultiplied pixel (white × alpha).
        // The colour work above is dead in this pass and is left in the
        // common path anyway: the branch is uniform across the draw, and the
        // pass is only ever encoded for a layer that HAS a shadow.
        return float4(alpha);
    }
    rgb = clamp(rgb, 0.0, 1.0);
    // PREMULTIPLIED out: the pipeline blends source-over with
    // (one, one_minus_source_alpha), which is only correct premultiplied.
    return float4(rgb * alpha, alpha);
}

// MARK: - The shadow pass (spec §7.5)

// A drop shadow is three steps, encoded by `MetalRenderer.encodeShadow`
// BEFORE the layer's own pass: (1) the layer is drawn into a canvas-sized
// offscreen texture with `shadowMask = 1`, (2) `MPSImageGaussianBlur` blurs
// that silhouette, (3) the pair below draws a full-canvas quad sampling the
// blurred texture, displaced by the shadow's (distance, angle) and tinted
// with its colour. `Compositor.swift` argues the canvas-sized textures.
//
// The quad is the WHOLE canvas rather than the layer's own rectangle because
// the blur spreads coverage well past the layer's edges and the offset moves
// it further still; a quad clipped to the layer would cut the shadow off
// exactly where it is meant to be softest.

// The shadow pass's own uniform block, deliberately NOT part of
// `LayerUniforms`: this stage shares none of the layer block's placement
// fields, and a separate struct costs `LayerUniforms` one float instead of
// six. The same layout contract applies — scalars only, mirrored
// field-for-field by `ShadowUniforms` in Compositor.swift, 8 floats = 32
// bytes.
struct ShadowUniforms {
    float canvasWidth;
    float canvasHeight;
    // The displacement in CANVAS pixels, y DOWN. Swift resolves the model's
    // (distance, angle) into it — `encodeShadow` is where the sign of the
    // angle is argued.
    float offsetX;
    float offsetY;
    float colorR;
    float colorG;
    float colorB;
    float opacity;      // already folded in: the shadow colour's own alpha
};

struct ShadowVaryings {
    float4 position [[position]];
};

// No uniforms: the quad is the whole canvas, which in clip space is the unit
// square doubled and flipped, the same for every shadow ever drawn.
vertex ShadowVaryings reelcut_shadow_vertex(uint vid [[vertex_id]]) {
    float2 corner = kQuad[vid];
    ShadowVaryings out;
    out.position = float4(corner.x * 2.0 - 1.0, 1.0 - corner.y * 2.0, 0.0, 1.0);
    return out;
}

fragment float4 reelcut_shadow_fragment(ShadowVaryings in [[stage_in]],
                                        constant ShadowUniforms &u [[buffer(0)]],
                                        texture2d<float> mask [[texture(0)]],
                                        sampler samp [[sampler(0)]]) {
    float2 canvas = max(float2(u.canvasWidth, u.canvasHeight), float2(1.0));
    // `position` is in canvas pixels, y down — the space the mask was
    // rendered in. Displacing the SAMPLE by -offset moves the shadow by
    // +offset, which is the direction the model means.
    float2 uv = (in.position.xy - float2(u.offsetX, u.offsetY)) / canvas;
    // The sampler clamps to the edge, so a fragment that lands outside the
    // mask would otherwise smear its border row right across the canvas.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return float4(0.0);
    }
    float alpha = clamp(mask.sample(samp, uv).a * u.opacity, 0.0, 1.0);
    // Premultiplied, like every other pass: the blend factor is one.
    return float4(float3(u.colorR, u.colorG, u.colorB) * alpha, alpha);
}
