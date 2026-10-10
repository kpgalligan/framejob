//
//  Waveform.metal — the luma waveform's one pass (spec §11 GR-5). Owned by
//  `app/Sources/WaveformAnalyzer.swift`, which dispatches one thread per
//  pixel of a composited frame and reads the 256 × 256 counts back.
//
//  Nothing here touches `Compositor.metal` or `LayerUniforms`: the pass reads
//  a FINISHED frame (the compositor's destination, or a rendered image) and
//  writes only its own counts buffer.
//

#include <metal_stdlib>
using namespace metal;

// Rec. 709 luma weights, on the ENCODED (sRGB) values: Y′, what the person
// sees, not linear luminance.
constant float3 kLumaWeights = float3(0.2126, 0.7152, 0.0722);

// One pixel into its (column bin, level) cell. The column bin is the pixel's
// x scaled to 256; the level is Y′ of the saturated colour rounded to 0…255,
// so level 255 is exactly "an 8-bit file writes 255" (Y′ ≥ 254.5/255) and
// level 0 is Y′ < 0.5/255. `counts` is `column * 256 + level`.
kernel void reelcut_waveform_bin(texture2d<half, access::read> frame [[texture(0)]],
                                 device atomic_uint *counts [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    uint width = frame.get_width();
    if (gid.x >= width || gid.y >= frame.get_height()) {
        return;
    }
    float3 rgb = saturate(float3(frame.read(gid).rgb));
    uint level = min(255u, uint(dot(rgb, kLumaWeights) * 255.0 + 0.5));
    uint column = gid.x * 256u / width;
    atomic_fetch_add_explicit(&counts[column * 256u + level], 1u, memory_order_relaxed);
}
