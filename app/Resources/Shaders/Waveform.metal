//
//  Waveform.metal — the four scopes' passes (spec §11 GR-5, GR-10): the luma
//  waveform, the RGB parade, the Rec. 709 vectorscope and the R′G′B′Y′
//  histogram. Owned by `app/Sources/WaveformAnalyzer.swift`, which dispatches
//  one thread per pixel of a composited frame for each shown scope and reads
//  each scope's counts back.
//
//  Nothing here touches `Compositor.metal` or `LayerUniforms`: every pass
//  reads a FINISHED frame (the compositor's destination, or a rendered image)
//  and writes only its own counts buffer.
//
//  **The counting rule** (GR-10): never one global atomic per pixel into a
//  counter a picture region shares. The waveform spreads by column, so it
//  adds globally; the parade counts each 8-px-wide threadgroup's two column
//  bins in threadgroup memory (GR-10's fallback, taken in G2-1); the
//  vectorscope counts its central 64 × 64 bins (where grey and near-grey
//  pixels land) in threadgroup memory and the rest globally, a non-central
//  bin shared by a whole SIMD group added once (GR-26's same-bin add: a flat
//  saturated colour); the histogram counts in threadgroup memory. Each
//  threadgroup merges its counts once, and a threadgroup kernel guards its
//  pixel read rather than returning before its barriers.
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
kernel void framejob_waveform_bin(texture2d<half, access::read> frame [[texture(0)]],
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

// A saturated encoded value's level, GR-5's rule: round(255·v), 0…255.
static inline uint scopeLevel(float v) {
    return min(255u, uint(v * 255.0 + 0.5));
}

// The parade's threadgroup: 8 pixels across (`WaveformAnalyzer.paradeAcross`),
// which in a frame 1792 px wide or more (7 × 256) spans at most two of the
// 256 column bins.
constant uint kParadeBands = 2u;
// Two copies of each threadgroup cell, alternate threads adding to
// alternate copies, so neighbours on one flat run contend half as often.
constant uint kParadeCopies = 2u;

// R′, G′ and B′ each binned as the waveform bins Y′: `counts` is
// `(channel * 256 + column) * 256 + level`, channel 0 R′, 1 G′, 2 B′. GR-10's
// per-band threadgroup counts: a group spanning at most `kParadeBands`
// column bins counts its pixels in threadgroup memory and merges once per
// group, non-zero only; a group spanning more (some groups of a frame under
// 1792 px wide) adds globally, as the waveform does. Taken in G2-1 because the global
// parade's 4K time sat within 7 % of GR-10's bound.
kernel void framejob_parade_bin(texture2d<half, access::read> frame [[texture(0)]],
                               device atomic_uint *counts [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]],
                               uint index [[thread_index_in_threadgroup]],
                               uint2 group [[threads_per_threadgroup]]) {
    const uint cells = kParadeBands * 3u * 256u;
    threadgroup atomic_uint local[kParadeBands * 3u * 256u * kParadeCopies];
    uint width = frame.get_width();
    uint threads = group.x * group.y;
    uint originX = gid.x - index % group.x;
    uint first = originX * 256u / width;
    uint last = min(originX + group.x - 1u, width - 1u) * 256u / width;
    bool banded = last - first < kParadeBands;
    if (banded) {
        for (uint i = index; i < cells * kParadeCopies; i += threads) {
            atomic_store_explicit(&local[i], 0u, memory_order_relaxed);
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (gid.x < width && gid.y < frame.get_height()) {
        float3 rgb = saturate(float3(frame.read(gid).rgb));
        uint column = gid.x * 256u / width;
        uint copy = index % kParadeCopies;
        for (uint channel = 0u; channel < 3u; channel++) {
            uint level = scopeLevel(rgb[channel]);
            if (banded) {
                uint cell = (channel * kParadeBands + column - first) * 256u + level;
                atomic_fetch_add_explicit(&local[cell * kParadeCopies + copy], 1u,
                                          memory_order_relaxed);
            } else {
                atomic_fetch_add_explicit(&counts[(channel * 256u + column) * 256u + level], 1u,
                                          memory_order_relaxed);
            }
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (banded) {
        for (uint i = index; i < cells; i += threads) {
            uint n = 0u;
            for (uint c = 0u; c < kParadeCopies; c++) {
                n += atomic_load_explicit(&local[i * kParadeCopies + c], memory_order_relaxed);
            }
            if (n != 0u) {
                uint channel = i / (kParadeBands * 256u);
                uint band = (i / 256u) % kParadeBands;
                atomic_fetch_add_explicit(&counts[(channel * 256u + first + band) * 256u + i % 256u],
                                          n, memory_order_relaxed);
            }
        }
    }
}

// Rec. 709 Cb and Cr of a saturated encoded colour, each as its bin at
// `zoom` (GR-10, GR-31): 256 bins centred on neutral, `bin = 128 +
// round(255·zoom·c)`, so a grey is mid-bin 128 and never on an edge between
// two bins. At ×1 the bins are clamped to 0…255, GR-10's rule, through its
// own expression (never `255·zoom·c` with zoom 1: fast math may reassociate
// a runtime product), so every ×1 trace is the one the T4-0 tree counted. At
// ×2 and ×4 they are not clamped, and a bin outside 0…255 is off the plot.
static inline int2 chromaBins(float3 rgb, uint zoom) {
    float luma = dot(rgb, kLumaWeights);
    float2 c = float2((rgb.b - luma) / 1.8556, (rgb.r - luma) / 1.5748);
    if (zoom == 1u) {
        return clamp(int2(128) + int2(round(255.0 * c)), int2(0), int2(255));
    }
    return int2(128) + int2(round(255.0 * float(zoom) * c));
}

// A lane with no global bin to add: off the frame, off the plot, or counted
// in the centre.
constant uint kNoBin = 0xFFFFFFFFu;

// The vectorscope: `counts` is `crBin * 256 + cbBin`, `zoom` 1, 2 or 4
// (GR-31; a pixel off the plot at ×2 and ×4 is not counted). The central
// 64 × 64 bins (96..<160 on both axes) are counted per threadgroup and
// merged once per group, non-zero only; every other bin globally, once per
// SIMD group when all of its lanes share the bin (GR-26), else per pixel.
kernel void framejob_vectorscope_bin(texture2d<half, access::read> frame [[texture(0)]],
                                    device atomic_uint *counts [[buffer(0)]],
                                    constant uint &zoom [[buffer(1)]],
                                    uint2 gid [[thread_position_in_grid]],
                                    uint index [[thread_index_in_threadgroup]],
                                    uint2 group [[threads_per_threadgroup]]) {
    threadgroup atomic_uint centre[4096];
    uint threads = group.x * group.y;
    for (uint i = index; i < 4096u; i += threads) {
        atomic_store_explicit(&centre[i], 0u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    uint bin = kNoBin;
    if (gid.x < frame.get_width() && gid.y < frame.get_height()) {
        int2 raw = chromaBins(saturate(float3(frame.read(gid).rgb)), zoom);
        if (all(raw >= int2(0)) && all(raw <= int2(255))) {
            uint2 bins = uint2(raw);
            bool central = all(bins >= 96u) && all(bins < 160u);
            if (central) {
                atomic_fetch_add_explicit(&centre[(bins.y - 96u) * 64u + (bins.x - 96u)], 1u,
                                          memory_order_relaxed);
            } else {
                bin = bins.y * 256u + bins.x;
            }
        }
    }
    // GR-26's same-bin add, outside the in-frame branch so every lane of the
    // SIMD group reaches it: a group whose lanes all share one global bin
    // adds their count once; otherwise each lane with a bin adds alone.
    uint lead = simd_broadcast_first(bin);
    uint lanes = simd_sum(bin != kNoBin ? 1u : 0u);
    if (simd_all(bin == lead)) {
        if (simd_is_first() && lead != kNoBin) {
            atomic_fetch_add_explicit(&counts[lead], lanes, memory_order_relaxed);
        }
    } else if (bin != kNoBin) {
        atomic_fetch_add_explicit(&counts[bin], 1u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint i = index; i < 4096u; i += threads) {
        uint n = atomic_load_explicit(&centre[i], memory_order_relaxed);
        if (n != 0u) {
            atomic_fetch_add_explicit(&counts[(i / 64u + 96u) * 256u + (i % 64u + 96u)], n,
                                      memory_order_relaxed);
        }
    }
}

// The histogram: `counts` is `plane * 256 + level`, plane 0 R′, 1 G′, 2 B′,
// 3 Y′, counted per threadgroup and merged once per group, non-zero only.
kernel void framejob_histogram_bin(texture2d<half, access::read> frame [[texture(0)]],
                                  device atomic_uint *counts [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]],
                                  uint index [[thread_index_in_threadgroup]],
                                  uint2 group [[threads_per_threadgroup]]) {
    threadgroup atomic_uint local[1024];
    uint threads = group.x * group.y;
    for (uint i = index; i < 1024u; i += threads) {
        atomic_store_explicit(&local[i], 0u, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (gid.x < frame.get_width() && gid.y < frame.get_height()) {
        float3 rgb = saturate(float3(frame.read(gid).rgb));
        uint4 levels = uint4(scopeLevel(rgb.r), scopeLevel(rgb.g), scopeLevel(rgb.b),
                             scopeLevel(dot(rgb, kLumaWeights)));
        for (uint plane = 0u; plane < 4u; plane++) {
            atomic_fetch_add_explicit(&local[plane * 256u + levels[plane]], 1u,
                                      memory_order_relaxed);
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint i = index; i < 1024u; i += threads) {
        uint n = atomic_load_explicit(&local[i], memory_order_relaxed);
        if (n != 0u) {
            atomic_fetch_add_explicit(&counts[i], n, memory_order_relaxed);
        }
    }
}
