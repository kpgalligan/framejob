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
//  deliberately a multiple of 16 bytes — 104 floats, 416 bytes, as of the
//  obscure block), and mirror them in Swift in the same order.
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

// Obscure kind codes, on the same terms: `ObscureKind.shaderCode` in
// `ProjectSnapshot.swift` is the model's declaration order plus one, so 0 can
// mean "this slot holds no region". `ObscureKind` in `model_regions.rs` says a
// kind may be added at the END and the two here must never be swapped.
constant int kObscureNone     = 0;
constant int kObscureBlur     = 1;
constant int kObscurePixelate = 2;

// Blend mode codes (format version 6). Mirrors `BlendMode.shaderCode` in
// `ProjectSnapshot.swift`, which is `BlendMode`'s declaration order in
// `model_props.rs` — with NO `+1`, unlike the two lists above. There is
// nothing to reserve, because a layer has exactly one blend mode rather than
// four slots that may be empty, and 0 meaning `normal` is the property that
// makes the field safe to have added to a shipped schema: a zeroed uniform
// block, a recipe emitted by a core that predates the key, and a project file
// with no `blend` in it all render source-over, which is what every frame
// drew before phase 6.
//
// **APPEND ONLY.** This order is a contract with two other files, and it is
// checked nowhere but by reading the three side by side. A mode may be added
// at the END; the eight here may never be reordered or removed.
constant int kBlendNormal     = 0;
constant int kBlendMultiply   = 1;
constant int kBlendScreen     = 2;
constant int kBlendAdd        = 3;
constant int kBlendOverlay    = 4;
constant int kBlendDarken     = 5;
constant int kBlendLighten    = 6;
constant int kBlendDifference = 7;

// `TrackMatte` (format version 14, spec §11 MT-3) as the matte resolve
// pass's code: the case index of `core/src/model_matte.rs`'s enum and of
// `TrackMatte.swift`'s, `none` 0 to `luma_inverted` 4. **APPEND ONLY**, the
// same contract as the blend modes above, checked by reading the three.
constant int kMatteNone          = 0;
constant int kMatteAlpha         = 1;
constant int kMatteAlphaInverted = 2;
constant int kMatteLuma          = 3;
constant int kMatteLumaInverted  = 4;

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

// What `amount = 1` means for an OBSCURED region — the same two lengths, by
// alias rather than by repetition, so "a region at amount 1" is exactly "that
// filter at amount 1" and nobody has to hold two numbers. They are named
// separately because the two are answering different questions: a filter's
// maximum is how strong an effect anyone would want to look at, a region's is
// how much it can hide, and the day those diverge this is the one line that
// changes. Know the caveat before raising the blur: thirteen taps at 24
// source pixels is a SOFT blur — a large password field can still be read
// through it — and the tap-count budget above refuses a wider kernel, so
// raising the radius alone buys radial ripple, not privacy. `pixelate` is the
// kind that actually hides, and it is a region's default for that reason.
constant float kObscureMaxBlur  = kBlurMaxRadius;
constant float kObscureMaxBlock = kPixelateMaxBlock;

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
    // ── The M3 effect block (§4.2), and the obscure block after it.
    // `CompositorEffects.swift` fills every field below and argues each one's
    // meaning; what they DO is the fragment stage's order of operations,
    // written out above `layerColorPremultiplied`. The four reserved floats
    // that used to sit here are the first four of the M3 block; the obscure
    // block brought a tail of three back, and phase 6's `blendMode` spent the
    // first of those, leaving TWO:
    // 40 + 28 + 36 = 104 floats = 416 bytes, and 416 is 26 × 16.
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
    // top-left corner — which is NOT the space `[[position]]` arrives in
    // whenever the destination is not the canvas, so the test converts
    // through `canvasPixels` below (this comment claimed the opposite until
    // phase 8d, and the claim was true only while `renderSize` was always the
    // canvas).
    float clipEnabled;
    float clipX;                // the rectangle's CENTRE
    float clipY;
    float clipW;
    float clipH;
    float clipRotation;         // radians, clockwise, about that centre
    // ── The obscured regions (phase 3c): up to four boxes on the layer whose
    // contents are blurred or pixelated. Centre, size and feather are SOURCE
    // pixels measured from the centre of the CROPPED rectangle — the
    // spotlight's frame above, field for field, which is why they share
    // `regionMask` and why `SpotShape` is one enum and not two.
    //
    // REGION-MAJOR: all eight of region 0, then region 1, and so on, where
    // the filter slots above are field-major. A filter's record is two
    // fields, so field-major fell into runs of four there; an eight-field
    // record laid out that way would be thirty-two lines nobody could line up
    // against Compositor.swift's, and reading the two lists side by side is
    // the ONLY way this contract is ever checked. `MAX_OBSCURE` in
    // `model_regions.rs` is four BECAUSE there are four slots here.
    float obscureEnabled;       // 1 when the layer carries at least one region
    float obscure0Shape;        // 0 = rect, 1 = ellipse, as `spotShape`
    float obscure0X;            // the region's CENTRE, from the cropped centre
    float obscure0Y;
    float obscure0W;
    float obscure0H;
    float obscure0Feather;      // source px of ramp across the region's edge
    float obscure0Kind;         // a kObscure* code; 0 = empty slot
    float obscure0Amount;       // 0…1
    float obscure1Shape;
    float obscure1X;
    float obscure1Y;
    float obscure1W;
    float obscure1H;
    float obscure1Feather;
    float obscure1Kind;
    float obscure1Amount;
    float obscure2Shape;
    float obscure2X;
    float obscure2Y;
    float obscure2W;
    float obscure2H;
    float obscure2Feather;
    float obscure2Kind;
    float obscure2Amount;
    float obscure3Shape;
    float obscure3X;
    float obscure3Y;
    float obscure3W;
    float obscure3H;
    float obscure3Feather;
    float obscure3Kind;
    float obscure3Amount;
    // How this layer combines with what is already on the canvas: a kBlend*
    // code (format version 6). It took the FIRST of the three reserved floats
    // the obscure block left behind, so phase 6 added zero bytes to this
    // struct — which is what that tail exists for.
    //
    // Read only by `reelcut_layer_blend_fragment`. The plain entry point
    // never looks at it, and a layer whose mode is `normal` is drawn by the
    // plain one, so this field is 0 on nearly every draw of nearly every
    // frame.
    float blendMode;
    // ── The DESTINATION's size, as CANVAS PIXELS PER DESTINATION PIXEL on
    // each axis (phase 8d). These spent the last two floats of the padding
    // tail, so the struct is still 104 floats and the tail is now EMPTY: the
    // next field to land needs three companions.
    //
    // **What they are for.** `[[position]]` is in DESTINATION pixels, and
    // until phase 8a the destination was always the canvas — `renderSize` was
    // written once, by `CompositionBuilder`, to the canvas size — so three
    // stages here read the fragment's position as canvas pixels and said so.
    // Preview Quality renders the player's composition at a FRACTION of the
    // canvas (`Playback.previewComposition`), and at Half a nest's clip
    // rectangle magnified about the canvas origin, a shadow sampled its
    // canvas-sized mask at a quarter of the frame, and a dissolve applied its
    // weight correction where its partner was not. So the conversion is
    // explicit now, at the three sites that need it and nowhere else.
    //
    // **ZERO MEANS ONE.** A zeroed uniform block must render exactly what
    // every frame rendered before this field existed, so 0 is read as "the
    // destination IS the canvas" rather than as a divide-by-zero to guard
    // against — see `canvasPixels`. Swift writes canvas ÷ destination, which
    // is 1 on every export, every `render_frame` and every Full preview, and
    // 1 on the shadow MASK pass whatever the destination is, because that
    // pass draws into a canvas-sized target of its own.
    float canvasPerDestX;
    float canvasPerDestY;
};

/// A fragment's `[[position]]` in CANVAS pixels — the frame the nest clip
/// rectangle, the shadow mask and the dissolve partner box are all measured
/// in (§5.3, §7.3).
///
/// A MULTIPLY and not a divide: Swift resolves canvas ÷ destination once per
/// layer, so this is two selects and two multiplies, and it is called inside
/// the branches that need it rather than at the top of the stage — a layer
/// with no nest rectangle and no dissolve pays nothing for it, which is the
/// property the cost table above `layerColorPremultiplied` states.
static inline float2 canvasPixels(float2 position, float2 canvasPerDest) {
    return position
        * float2(canvasPerDest.x > 0.0 ? canvasPerDest.x : 1.0,
                 canvasPerDest.y > 0.0 ? canvasPerDest.y : 1.0);
}

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

/// A rect-or-ellipse region as a 0…1 mask in the layer's own source pixels: 1
/// well inside the region, 0 well outside, `feather` pixels of ramp across the
/// edge. `rel` is the fragment's offset from the region's centre.
///
/// EVERY region-shaped effect on a layer comes through here — the spotlight's
/// dim, the spotlight's lens and each obscured region — because they are all
/// the same box in the same frame, and one distance field means a region of
/// one kind and a region of the other with the same numbers cover exactly the
/// same pixels. `halfSize`, `shape` and `feather` are all PARAMETERS rather
/// than reads off the block: the caller is the only one that knows which
/// slot's numbers it wants, and the spotlight's dim and lens want different
/// ramps from the same box — see the zoom, which argues why.
static inline float regionMask(float2 rel, float2 halfSize, float shape, float feather) {
    float d;
    if (shape > 0.5) {
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

/// One obscure slot, unpacked. A LOCAL struct, so it may hold `float2`s: the
/// layout contract binds the constant buffer and nothing else.
struct ObscureSlot {
    float shape;
    float kind;
    float feather;
    float amount;
    float2 centre;   // offset from the centre of the cropped rect, source px
    float2 size;
};

/// Slot `i`. The if-chain is `filterSlot`'s, for the same reason: Metal
/// cannot index a struct's fields, and the slots are scalars by the layout
/// contract. It unrolls to nothing when the slots are empty.
static inline ObscureSlot obscureSlot(constant LayerUniforms &u, int i) {
    ObscureSlot s;
    if (i == 0) {
        s.shape = u.obscure0Shape; s.kind = u.obscure0Kind;
        s.feather = u.obscure0Feather; s.amount = u.obscure0Amount;
        s.centre = float2(u.obscure0X, u.obscure0Y);
        s.size = float2(u.obscure0W, u.obscure0H);
    } else if (i == 1) {
        s.shape = u.obscure1Shape; s.kind = u.obscure1Kind;
        s.feather = u.obscure1Feather; s.amount = u.obscure1Amount;
        s.centre = float2(u.obscure1X, u.obscure1Y);
        s.size = float2(u.obscure1W, u.obscure1H);
    } else if (i == 2) {
        s.shape = u.obscure2Shape; s.kind = u.obscure2Kind;
        s.feather = u.obscure2Feather; s.amount = u.obscure2Amount;
        s.centre = float2(u.obscure2X, u.obscure2Y);
        s.size = float2(u.obscure2W, u.obscure2H);
    } else {
        s.shape = u.obscure3Shape; s.kind = u.obscure3Kind;
        s.feather = u.obscure3Feather; s.amount = u.obscure3Amount;
        s.centre = float2(u.obscure3X, u.obscure3Y);
        s.size = float2(u.obscure3W, u.obscure3H);
    }
    return s;
}

/// What the four regions ask of THIS fragment, folded into one blur and one
/// pixelation.
///
/// `blurRadius` and `block` are the strengths; `blurCover` and `pixelCover`
/// are how much of each to mix in, 0 outside every region of that kind and 1
/// well inside one. That split is the whole design: **the feather ramps the
/// MIX, never the strength**. A block size or a tap radius that varied across
/// the feather band would tear the grid into visible steps and swim as the
/// region moved; mixing two settled colours cannot, and it makes `feather`
/// mean for a region exactly what it means for the spotlight's dim.
///
/// Where two regions of ONE kind overlap, the STRONGEST wins per fragment —
/// blur radii added in quadrature, block sizes taken at the max. That is
/// `filterPlan`'s own rule for two blurs and two pixelates and it needs no new
/// vocabulary. Applying each region in slot order with its own sample would be
/// up to 52 taps for a picture nobody could tell from this one.
///
/// The COVER that goes with that strength is each slot's mask weighted by the
/// slot's own strength — the greatest `strength × mask`, divided by the
/// greatest strength — and not the bare max of the masks. A bare max lets a
/// region set to `amount` 0, which the model documents as "there but hides
/// nothing", pull a NEIGHBOUR's full-strength pixelation up to full cover
/// inside its own box: a hard-edged square of 64-pixel blocks conjured by
/// adding a region that hides nothing. Weighting keeps both ends honest — a
/// slot with no strength contributes no cover, a slot with half the winner's
/// strength can carry the cover only half way — and it is continuous in
/// `amount`, where a bare "skip the empty slots" guard would leave a cliff
/// between amount 0 and amount 0.001. What it maximizes — a strength times the
/// mix that strength would be applied at — is the same shape of measure the
/// fragment stage picks the winning KIND with, so the two decisions are one
/// idea in two places.
///
/// Which KIND is applied is the fragment stage's decision, not this one's: it
/// takes the greater of the two hidings and applies that one ALONE. Both are
/// planned here because the comparison needs both, and it costs one extra
/// sample path per fragment however many regions cover it.
struct ObscurePlan {
    float blurRadius;   // source px, the outer tap ring
    float blurCover;    // 0…1 mix factor for the blurred sample
    float block;        // source px, the pixelation's block side
    float pixelCover;   // 0…1 mix factor for the snapped sample
};

static inline ObscurePlan obscurePlan(constant LayerUniforms &u, float2 localPx,
                                      float2 cropped) {
    ObscurePlan plan;
    plan.blurRadius = 0.0;
    plan.blurCover = 0.0;
    plan.block = 0.0;
    plan.pixelCover = 0.0;
    // The two covers, accumulated as `strength × mask` and divided by the
    // strongest slot of their kind at the end. A pixelation's strength is
    // measured from 1 — `mix(1, kObscureMaxBlock, amount)` is the block side
    // and a block of ONE pixel is the identity — so that an amount of 0 is a
    // strength of 0 for both kinds and neither can raise a cover.
    float blurReach = 0.0, blurHidden = 0.0;
    float blockReach = 0.0, blockHidden = 0.0;
    for (int i = 0; i < 4; ++i) {
        ObscureSlot slot = obscureSlot(u, i);
        int kind = int(slot.kind + 0.5);
        if (kind == kObscureNone) { continue; }
        // The region's frame, which is the spotlight's: its centre is an
        // offset in SOURCE pixels from the centre of the CROPPED rect, and
        // `localPx` is the fragment measured in exactly those pixels. The
        // layer's scale and rotation are the vertex stage's business, which
        // is what makes a region ride with its layer for free.
        float2 centre = cropped * 0.5 + slot.centre;
        float m = regionMask(localPx - centre, max(slot.size * 0.5, float2(1e-3)),
                             slot.shape, slot.feather);
        if (m <= 0.0) { continue; }
        float amount = clamp(slot.amount, 0.0, 1.0);
        if (kind == kObscureBlur) {
            float r = amount * kObscureMaxBlur;
            if (r <= 0.0) { continue; }
            plan.blurRadius = sqrt(plan.blurRadius * plan.blurRadius + r * r);
            blurReach = max(blurReach, r);
            blurHidden = max(blurHidden, r * m);
        } else if (kind == kObscurePixelate) {
            float b = mix(1.0, kObscureMaxBlock, amount) - 1.0;
            if (b <= 0.0) { continue; }
            plan.block = max(plan.block, b + 1.0);
            blockReach = max(blockReach, b);
            blockHidden = max(blockHidden, b * m);
        }
        // A code this shader does not know — a region out of some later
        // schema — hides nothing rather than guessing at a kind. It is the
        // reading a slot holding `kObscureNone` already gets.
    }
    plan.blurCover = blurReach > 0.0 ? blurHidden / blurReach : 0.0;
    plan.pixelCover = blockReach > 0.0 ? blockHidden / blockReach : 0.0;
    return plan;
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
//  4b. obscure the regions     colour only, and AFTER the sharpen: see below
//   5. the point filters       sepia, noir, vignette, invert, IN SLOT ORDER
//   6. spotlight dim           after every colour stage: the dim is a light
//                              on the layer, not something the filters act on
//   7. coverage                corner radius × nest clip rectangle × matte
//   8. transition weight
//   9. opacity, then the reflection's fade
//  10. premultiply out
//  11. blend                   ONLY on the blend specialization, which reads
//                              the destination through `[[color(0)]]` and
//                              computes the combination itself — see
//                              `blendPremultiplied` and the note below
//
// **Step 11 is not in this function**, and cannot be: the stage below ends at
// step 10 and hands its premultiplied colour to whichever entry point called
// it. A `normal` layer's entry point returns it and the PIPELINE combines it
// with `(one, one_minus_source_alpha)`; a blended layer's reads the
// destination and combines it here. The two are the same function at
// `normal` — the general formula reduces to the fixed-function factors
// algebraically, which is written out over `blendPremultiplied` — so nothing
// about a `normal` layer's pixels depends on which one drew it.
//
// **A layer mid-TRANSITION always blends normal, and the CORE is what says
// so.** `recipe.rs::layer` emits `"normal"` for any layer whose `transition`
// is non-null, so the uniform arrives at 0 and this shader has no special
// case for it — do not add one here. The reason is step 8: the outgoing half
// of a dissolve divides its weight by the attenuation the incoming pass is
// about to apply, which is the exact algebraic inverse of a FIXED-FUNCTION
// destination factor, and a programmable blend on either half invalidates it.
// The decision lives in the core because everything that draws a frame reads
// that one description, so preview, `render_frame` and both export writers
// cannot disagree — and because a core test can read the layer's `blend` at a
// tick inside the overlap, where a renderer-side rule would need two PNGs.
// The visible consequence, said out loud because from here it reads as a bug:
// the inspector shows the MODEL's value while an overlap draws `normal`.
//
// **This compositor blends in the ENCODED sRGB space, deliberately.** Nothing
// in the pipeline uses an `_srgb` pixel format — the attachment is
// `.bgra8Unorm` — so every stage above works on stored 8-bit values, and step
// 11 works on the same ones. "Multiply of 50 % grey over 50 % grey is 25 %"
// is a statement about ENCODED values and is false in linear light, where the
// answer is about 22 %. A reader who knows colour will want to put a
// linearise/encode pair around the blend; that would change every blended
// pixel, break the proof's measured 64 / 192 / 255, and make the compositor
// disagree with itself, since the grade, the filters and the transitions have
// all worked in encoded space since M1. If linear light is ever wanted it is
// a decision for the WHOLE pipeline, not for this one stage.
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
// **Why the obscured regions run at 4b and not at the end.** They must come
// after the SHARPEN, because the unsharp term is built from the RAW texture
// and added on top: hide first and a layer that also carries a sharpen filter
// has the hidden detail put straight back, on that layer only. And they must
// come before the POINT FILTERS, because a region replaces the colour with a
// second sample of the same texture, and a sample taken after the point
// filters would not have been through them — an obscured region on a sepia
// layer would show as an unsepia'd hole. Between the two is the one place
// that is right, and the region's own colour is then graded, lit and
// filtered exactly like the picture around it.
//
// **What a layer with no effects costs.** Measured, not asserted. A full-bleed
// 1080p layer with no filters, no spotlight, no reflection, no clip rect and
// no obscured region renders in 0.30–0.33 ms, which is what the same layer
// measured through the pre-M3 shader — the difference is inside the
// run-to-run spread of the machine's own GPU clocks. All that layer pays is
// the single comparison below and the eight uniform reads that answer it;
// everything else is behind that comparison, or compiled out of its pipeline
// entirely (`kGatherFilters`).
//
// What each effect DOES cost on that same layer, over the no-effect baseline:
// a clip rectangle 0.02 ms, a reflection 0.02, a spotlight with its lens 0.04,
// a pixelate 0.03, four point filters together 0.08, a sharpen 0.18, a blur
// 0.46. Every one of them at once measured 1.05 ms — an eighth of the 8 ms the
// spec gives the whole compositor.
//
// A BLEND MODE (format version 6), measured the same way — same layer, 200
// frames a sample, three interleaved runs, the baseline reproducing at
// 0.293–0.295 ms: `add` 0.02 ms, `multiply`, `darken` and `difference` 0.07,
// `screen` 0.08, `overlay` 0.09. Most of that is the FORMULA and not the tile
// read: the same blend pipeline asked for `normal` — which reads the
// destination and then takes the early return, dividing nothing — costs 0.02,
// which is exactly what `add` costs, and `add` skips the divisions too. So a
// destination read is 0.02 and the un-premultiply pair plus the mode is the
// other 0.05, which is worth knowing before anyone tries to save one of the
// two reciprocals by assuming an opaque destination.
//
// **Why the whole stage is a helper and not the entry point.** Metal cannot
// call one `fragment` function from another, and phase 6 needs two entry
// points that differ only in what they do with the answer — one that hands
// the premultiplied colour to fixed-function source-over, and one that reads
// the destination and blends it here. So the stage below is an ordinary
// `static inline` function and both entry points forward to it. It is the
// same body, in the same order, with the same expressions: the refactor was
// landed and phases 1–5 re-proved BEFORE any blend code existed, so a
// one-LSB drift in the plain path could be attributed to the move rather
// than to the feature.
static inline float4 layerColorPremultiplied(Varyings in,
                                             constant LayerUniforms &u,
                                             texture2d<float> source,
                                             sampler samp,
                                             texture2d<float> matte) {
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
                    + u.spotEnabled + u.clipEnabled + u.reflectionPass
                    + u.obscureEnabled) > 0.5;

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
            spot = regionMask(localPx - centre, halfSize, u.spotShape, u.spotFeather);
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
                float lens = regionMask(localPx - centre, halfSize, u.spotShape, ramp);
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

        // (4b) The obscured regions. COLOUR ONLY, exactly like the spotlight's
        // dim below and for one more reason besides: this same fragment stage
        // draws the layer's shadow silhouette with `shadowMask` raised, so an
        // effect that touched alpha would change the SHAPE of a shadowed
        // layer's shadow the moment a region was added. Leaving coverage
        // alone is also what makes "every pixel outside the region is byte
        // identical" true, which is the claim the whole feature is proved by.
        //
        // The `slate` guard is not optional: on a missing-media layer the
        // bound texture is a 1×1 white placeholder and `base` came from
        // `slateColor`, so re-sampling would paint a white block over the
        // slate's own stripes. The sharpen above guards the same way.
        if (u.obscureEnabled > 0.5 && u.slate < 0.5) {
            ObscurePlan hide = obscurePlan(u, localPx, cropped);
            // Sample with `uv`, mask with `localPx`. `uv` has already been
            // bent by the spotlight's lens and quantized by a global
            // pixelate, so sampling it keeps the region showing the same
            // picture the rest of the layer shows; `localPx` is pure geometry
            // and is what keeps the region sitting where it was put. It is
            // the same asymmetry the spotlight's dim has.
            //
            // The block grid is anchored at the TEXTURE origin, not at the
            // region's corner — `filterPlan`'s pixelate is too — so blocks
            // inside a region are full-size and stay put when the region
            // moves, at the price of the region's edge cutting the blocks it
            // crosses. One consequence to know: a layer carrying a global
            // BLUR shows its pixelated regions unblurred, because this takes
            // a single raw sample rather than a second thirteen-tap gather.
            // Twelve extra taps to soften a 64-pixel block is not a trade
            // worth making, and the coarser of the two is what hides.
            //
            // WHICH KIND, decided once for this fragment. Each hiding is a
            // length in SOURCE pixels times the mix it would be applied at: a
            // block of side b destroys every detail smaller than b, a blur
            // whose outer tap ring sits at r spreads detail across a disc 2r
            // wide, and the mix is in the product because half of a strong
            // effect can hide less than all of a weak one.
            //
            // The greater wins OUTRIGHT and the other is not applied at all,
            // because both mixes take a fresh sample of the RAW texture:
            // running the two would let the second paint over what the first
            // hid. With the blur running second, a region at 5% blur dropped
            // over a full-strength pixelation used to put the face the blocks
            // had destroyed back on screen, softened by a pixel — adding a
            // region made the frame LESS hidden, which for this feature is the
            // one thing that must never happen. A tie goes to the pixelate,
            // which destroys where a blur only softens (`kObscureMaxBlur`'s
            // note says how soft). What it costs is a seam where the winner
            // changes inside an overlap of two FEATHERED regions of different
            // kinds; one sample path a fragment is worth that, and the only
            // way to have both — blurring the pixelated colour — means
            // snapping all thirteen taps to the block grid as well.
            float hidePixel = hide.block > 1.0 ? hide.block * hide.pixelCover : 0.0;
            float hideBlur = kGatherFilters && hide.blurRadius > 0.0
                ? 2.0 * hide.blurRadius * hide.blurCover : 0.0;
            if (hideBlur > hidePixel) {
                // In quadrature with whatever blur the layer already carries,
                // so a region is always at LEAST as blurred as the picture
                // around it — a region that came out sharper than its
                // surroundings would advertise exactly what it was hiding.
                float r = sqrt(plan.blurRadius * plan.blurRadius
                               + hide.blurRadius * hide.blurRadius);
                rgb = mix(rgb, gatherBlur(source, samp, uv, srcSize, r, u).rgb,
                          hide.blurCover);
            } else if (hidePixel > 0.0) {
                float2 px = uv * srcSize;
                float2 snapped = ((floor(px / hide.block) + 0.5) * hide.block) / srcSize;
                rgb = mix(rgb, layerSample(source, samp, snapped, u).rgb, hide.pixelCover);
            }
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

        // (7a) The nest clip rectangle: a rotated box in ABSOLUTE canvas pixels
        // — hence no anchor, no scale and no crop in this test. It is
        // deliberately NOT in the layer's own space: a nest clips the flattened
        // layers to ITS canvas, and those layers carry the nest's transform
        // folded into their own, so the only frame all of them share is the
        // canvas. The fragment is converted INTO that frame rather than tested
        // in the destination's, which is the whole of phase 8d's defect here: a
        // rectangle in canvas pixels compared against a half-size destination's
        // position is a rectangle magnified about the canvas origin, and at
        // Quarter it left the frame entirely.
        if (u.clipEnabled > 0.5) {
            float2 canvasPoint = canvasPixels(
                in.position.xy, float2(u.canvasPerDestX, u.canvasPerDestY));
            float2 p = rotate2(canvasPoint - float2(u.clipX, u.clipY), -u.clipRotation);
            float2 e = abs(p) - max(float2(u.clipW, u.clipH), float2(0.0)) * 0.5;
            float d = length(max(e, 0.0)) + min(max(e.x, e.y), 0.0);
            // One CANVAS pixel of feather — no 1/scale, unlike the corner
            // radius below. At a reduced preview size that is less than a
            // destination pixel, so the edge is as hard as the resample makes
            // it, which is the same edge the upsample would have given it.
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

    // (7c) The matte coverage (spec §11 MT-3, MT-6): the product of every
    // matte cutting this layer, resolved into one r8 texture the size of the
    // destination, sampled at the fragment's canvas-normalised position — so
    // Preview Quality, the shadow's canvas-sized silhouette pass and the
    // reflection, which lands where it lands, all read one coverage. An
    // unmatted layer binds the 1×1 white placeholder, which reads 1
    // everywhere (MT0's spike chose that route over a specialization: its
    // cost per layer was within the measured bound). Kept as a value: the
    // outgoing half of a dissolve weighs its partner's cover by it below.
    float matteCover = matte.sample(samp, canvasPixels(
        in.position.xy, float2(u.canvasPerDestX, u.canvasPerDestY))
        / max(float2(u.canvasWidth, u.canvasHeight), float2(1.0))).r;
    alpha *= matteCover;

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
            //
            // `partnerBox` builds that box in CANVAS pixels, so the fragment
            // is converted into them — the local was named `canvasPoint` and
            // assigned the destination's position, which was the same thing
            // only while `renderSize` was always the canvas. A PiP dissolve
            // at Half corrected nothing and dipped ~25 % dark across the
            // whole overlap; two full-frame clips hid it, because a partner
            // covering the whole canvas is the case where the box's own
            // edges never fall inside the frame.
            float2 canvasPoint = canvasPixels(
                in.position.xy, float2(u.canvasPerDestX, u.canvasPerDestY));
            bool insidePartner =
                canvasPoint.x >= u.partnerMinX && canvasPoint.x <= u.partnerMaxX &&
                canvasPoint.y >= u.partnerMinY && canvasPoint.y <= u.partnerMaxY;
            //
            // Under a matte the incoming pass's attenuation is
            // (1 - p·alphaIncoming·m), m the coverage at this pixel: both
            // halves on one matted track are cut by the same mattes (spec
            // §11 MT-3), so this layer's own `matteCover` is the partner's
            // m, and the composite stays m·mix(out, in, p) + (1 - m)·bg
            // under a soft matte as well as a hard one.
            float cover = insidePartner ? clamp(u.partnerAlpha, 0.0, 1.0) * matteCover : 0.0;
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
    // PREMULTIPLIED out: the plain pipeline blends source-over with
    // (one, one_minus_source_alpha), which is only correct premultiplied —
    // and `blendPremultiplied` takes premultiplied operands for the same
    // reason, so both entry points below want exactly this value.
    return float4(rgb * alpha, alpha);
}

// The layer stage as every layer before phase 6 drew it: the premultiplied
// colour handed straight to the pipeline's fixed-function source-over. Every
// layer whose blend mode is `normal` still comes through here, and so does
// every shadow MASK pass, whatever the layer's mode (`encodeShadow`).
fragment float4 reelcut_layer_fragment(Varyings in [[stage_in]],
                                       constant LayerUniforms &u [[buffer(0)]],
                                       texture2d<float> source [[texture(0)]],
                                       sampler samp [[sampler(0)]],
                                       texture2d<float> matte [[texture(1)]]) {
    return layerColorPremultiplied(in, u, source, samp, matte);
}

/// Step 11: one layer's colour combined with the destination under a
/// `kBlend*` mode. Both operands are PREMULTIPLIED — `src` is what the stage
/// above returns and `dst` is what the attachment holds — and so is the
/// result, because the pipeline that runs this has fixed-function blending
/// DISABLED and whatever comes back here is written to the tile verbatim.
///
/// With `as = src.a`, `ab = dst.a` and the straight colours
/// `Cs = src.rgb/as`, `Cb = dst.rgb/ab`, the six separable modes are the
/// W3C compositing formula:
///
///     rgb = (1-as)·dst.rgb + (1-ab)·src.rgb + as·ab·B(Cs, Cb)
///     a   = as + ab·(1-as)
///
/// with `B` the mode's own two-colour function. Three properties of that
/// shape are worth knowing, because each one is a thing that could have gone
/// wrong and did not:
///
/// · **`normal` reduces to the fixed-function factors.** Put `B = Cs` in and
///   the middle two terms collapse: `(1-ab)·as·Cs + as·ab·Cs = as·Cs =
///   src.rgb`, leaving `rgb = src.rgb + (1-as)·dst.rgb`, which is exactly
///   `(one, one_minus_source_alpha)`. The plain path and this one are
///   provably the same function at `normal`, which is what lets the fast
///   path stay fixed-function without the two drifting apart.
/// · **A fully transparent fragment leaves the destination alone.** At
///   `as = 0` a premultiplied `src.rgb` is 0 — which is what a `clip_rect`,
///   a corner radius or a crop leaves behind — so `Cs` is 0, the last two
///   terms vanish and `rgb = dst.rgb`, `a = ab`, to the bit. Coverage still
///   works, and a blended layer flattened out of a NEST cannot paint outside
///   its nest.
/// · **The destination-alpha term is kept** rather than assumed to be 1. It
///   costs one multiply on a path nothing else is close to saturating, and
///   the frame is not always opaque: phase 7 wants a transparent canvas for
///   ProRes 4444, and a formula written for `ab = 1` would be wrong there in
///   a way nobody would think to look for.
///
/// `add` is NOT a separable blend and does not go through that formula at
/// all: it is plus-lighter, `min(src + dst, 1)` on both the colour and the
/// alpha, which is what makes a glow add light to the frame rather than
/// average with it.
///
/// The general path needs no final clamp. Every `B` above lands in 0…1 for
/// operands in 0…1, `Cs` and `Cb` are bounded because both inputs are
/// well-formed premultiplied pixels (`rgb <= a`, which source-over
/// preserves), and the three weights `(1-as)`, `(1-ab)·as` and `as·ab` sum to
/// EXACTLY 1 — the result is a convex combination of three values that are
/// each already in range. The `max(a, 1e-4)` guards divide a zero by a zero,
/// not a colour by a small number.
static inline float4 blendPremultiplied(int mode, float4 src, float4 dst) {
    // `normal` first and on its own: it is the mode nearly every blended
    // frame's OTHER layers are in, and this is the fixed-function formula
    // spelled out, so a blend pipeline that happened to draw one is still
    // exactly source-over.
    if (mode == kBlendNormal) {
        return float4(src.rgb + dst.rgb * (1.0 - src.a),
                      src.a + dst.a * (1.0 - src.a));
    }
    // Plus-lighter, before the separable machinery, because it shares none
    // of it — no un-premultiply, no destination-alpha weighting.
    if (mode == kBlendAdd) {
        return float4(min(src.rgb + dst.rgb, 1.0), min(src.a + dst.a, 1.0));
    }

    float as = src.a;
    float ab = dst.a;
    float3 Cs = src.rgb / max(as, 1e-4);
    float3 Cb = dst.rgb / max(ab, 1e-4);
    float3 B = Cs;
    if (mode == kBlendMultiply) {
        B = Cs * Cb;
    } else if (mode == kBlendScreen) {
        B = Cs + Cb - Cs * Cb;
    } else if (mode == kBlendOverlay) {
        // HardLight with the operands swapped, which is what `overlay` is.
        // The comparison is on the BACKDROP and it is `<=`, so a backdrop at
        // 128/255 — which is 0.50196 and not 0.5 — takes the screen half.
        // That is not a detail: it is why the proof measures overlay with a
        // BASE of 64 rather than of 128 — a 192 source over a 64 base gives
        // 2 × 0.753 × 0.251 = 96.4, which reads back as 96 and cannot round
        // either way, where 128 over 128 lands on 128.5 and can.
        B = select(1.0 - 2.0 * (1.0 - Cs) * (1.0 - Cb), 2.0 * Cs * Cb, Cb <= 0.5);
    } else if (mode == kBlendDarken) {
        B = min(Cs, Cb);
    } else if (mode == kBlendLighten) {
        B = max(Cs, Cb);
    } else if (mode == kBlendDifference) {
        B = abs(Cs - Cb);
    }
    return float4((1.0 - as) * dst.rgb + (1.0 - ab) * src.rgb + as * ab * B,
                  as + ab * (1.0 - as));
}

/// The same layer stage, for a layer whose blend mode is not `normal`: it
/// READS the destination through `[[color(0)]]` and returns the combination
/// itself. `MetalRenderer` builds this one with `isBlendingEnabled = false`,
/// so what comes back is written to the tile as it stands.
///
/// **There is no `shadowMask` guard here because none is needed**, and the
/// reason is the same term that makes coverage work. A shadow's mask pass
/// draws into a texture cleared to transparent black, so `ab` is 0, and
/// `blendPremultiplied` at `ab` = 0 reduces to `(1 - as)·0 + 1·src.rgb + 0`
/// — the source, exactly, for all eight modes with `add` included. The
/// silhouette comes out right whichever pipeline draws it.
///
/// **This comment used to say the opposite and state it as fact**: that a
/// `multiply` against a cleared destination is 0, so a blended layer's
/// shadow would vanish, so `MetalRenderer.render`'s separate `maskState`
/// was holding a bug back. That is true of a naive `src · dst` and false of
/// the premultiplied composite above. Phase 6's mutation run settled it —
/// a build passing `state` to `encodeShadow` renders every shadow correctly
/// and the proof scores full marks against it — and four other documents
/// were corrected then; this one, where the formula actually lives, was
/// missed until an audit found it. `maskState` stays because it costs
/// nothing and names what a mask pass means, not because it is load-bearing.
fragment float4 reelcut_layer_blend_fragment(Varyings in [[stage_in]],
                                             constant LayerUniforms &u [[buffer(0)]],
                                             texture2d<float> source [[texture(0)]],
                                             sampler samp [[sampler(0)]],
                                             float4 dst [[color(0)]],
                                             texture2d<float> matte [[texture(1)]]) {
    float4 src = layerColorPremultiplied(in, u, source, samp, matte);
    return blendPremultiplied(int(u.blendMode + 0.5), src, dst);
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
// field-for-field by `ShadowUniforms` in Compositor.swift, 12 floats = 48
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
    // Canvas pixels per DESTINATION pixel, `LayerUniforms`' two fields under
    // the same rule — 0 means the destination is the canvas. This pass needs
    // them more than any other stage does: the mask it samples is CANVAS
    // sized whatever the destination is (`shadowSilhouette` allocates it at
    // the recipe canvas's size, and phase 8a's own doc leaned on that fact —
    // to argue about COST, without noticing it was also a wrong picture), so
    // both the sampling coordinate and the offset subtracted from it are in
    // canvas pixels and the fragment must be converted into them.
    float canvasPerDestX;
    float canvasPerDestY;
    // The padding tail this pair brought with it: 12 floats, 48 bytes, three
    // times 16. Eight and twelve are multiples of 16 bytes and ten is not,
    // which is why two fields cost four.
    float reserved0;
    float reserved1;
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
    // The mask was rendered in CANVAS pixels, y down, so the fragment is
    // converted into them before anything is subtracted from it: `position`
    // is the DESTINATION's, and at Half this whole expression used to reach
    // only uv 0.5 — a 2× magnified slab of the mask, sitting nowhere near
    // the layer that cast it. Displacing the SAMPLE by -offset moves the
    // shadow by +offset, which is the direction the model means.
    float2 uv = (canvasPixels(in.position.xy, float2(u.canvasPerDestX, u.canvasPerDestY))
        - float2(u.offsetX, u.offsetY)) / canvas;
    // The sampler clamps to the edge, so a fragment that lands outside the
    // mask would otherwise smear its border row right across the canvas.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return float4(0.0);
    }
    float alpha = clamp(mask.sample(samp, uv).a * u.opacity, 0.0, 1.0);
    // Premultiplied, like every other pass: the blend factor is one.
    return float4(float3(u.colorR, u.colorG, u.colorB) * alpha, alpha);
}

// MARK: - The matte resolve pass (spec §11 MT-3, MT-6)

// The matte resolve pass's uniform block: the mode's code and a padding
// tail to 16 bytes, mirrored by `MatteUniforms` in `Compositor+Matte.swift`
// under `LayerUniforms`' layout contract.
struct MatteUniforms {
    float mode;
    float reserved0;
    float reserved1;
    float reserved2;
};

// One matte's value at this pixel, from its composite — PREMULTIPLIED, in
// encoded sRGB like every stage above — multiplied into the r8 coverage by
// the pipeline (source factor zero, destination factor sourceColor), so a
// layer cut by two mattes reads their product. The composite and the
// coverage are both the destination's size, so the pixel is read, not
// sampled. Luma is Rec. 709 over the premultiplied colour, the saturation
// stage's weights, so a transparent pixel counts as black.
fragment float4 reelcut_matte_resolve_fragment(ShadowVaryings in [[stage_in]],
                                               constant MatteUniforms &u [[buffer(0)]],
                                               texture2d<float> mask [[texture(0)]]) {
    float4 m = mask.read(uint2(in.position.xy));
    int mode = int(u.mode + 0.5);
    float luma = dot(m.rgb, float3(0.2126, 0.7152, 0.0722));
    float v = 1.0;
    if (mode == kMatteAlpha) {
        v = m.a;
    } else if (mode == kMatteAlphaInverted) {
        v = 1.0 - m.a;
    } else if (mode == kMatteLuma) {
        v = luma;
    } else if (mode == kMatteLumaInverted) {
        v = 1.0 - luma;
    }
    return float4(clamp(v, 0.0, 1.0));
}
