//
//  ExportI010.metal — the `av1` row's frames for SVT-AV1 (spec §11 CX-12 (5),
//  CX-14 (3)): a compositor frame (64RGBAHalf, premultiplied, in the encoding
//  of the picture the export writes) converted to video-range 10-bit I010 in
//  three planes of one buffer, each sample 16 bits, little-endian, the 10 bits
//  in its low bits (yuv420p10le). Owned by `app/Sources/ExportI010.swift`,
//  which scales the frame to the export size first when it is not the canvas.
//
//  One thread per 2 × 2 block: it writes the block's four luma samples and
//  one Cb and one Cr, the mean of the four pixels' (a 2 × 2 box, the chroma
//  siting SVT's sequence header leaves unspecified). RGB is clamped to 0…1 and
//  read as it is, premultiplied, so a transparent canvas lands on black as it
//  does through VideoToolbox on `h264`.
//
//  The matrix is the picture's (`kr`, `kb`: BT.709's or BT.2020's):
//  Y′ = kr R + (1 − kr − kb) G + kb B; Cb′ = (B − Y′) / (2 (1 − kb));
//  Cr′ = (R − Y′) / (2 (1 − kr)); Y = round(64 + 876 Y′);
//  C = clamp(round(512 + 896 C′), 0, 1023), C′ the block's mean.
//

#include <metal_stdlib>
using namespace metal;

/// Mirrored by `ExportI010Uniforms` in `ExportI010.swift`; every field 32 bits.
/// Strides and offsets are in samples.
struct ExportI010Uniforms {
    uint width;
    uint height;
    uint lumaStride;
    uint chromaStride;
    uint cbOffset;
    uint crOffset;
    float kr;
    float kb;
};

kernel void framejob_export_i010(texture2d<half, access::read> src [[texture(0)]],
                                 device ushort *planes [[buffer(0)]],
                                 constant ExportI010Uniforms &u [[buffer(1)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    if (gid.x * 2 >= u.width || gid.y * 2 >= u.height) {
        return;
    }
    const float3 weights = float3(u.kr, 1.0 - u.kr - u.kb, u.kb);
    const float cbScale = 2.0 * (1.0 - u.kb);
    const float crScale = 2.0 * (1.0 - u.kr);
    float cb = 0.0;
    float cr = 0.0;
    float count = 0.0;
    for (uint dy = 0; dy < 2; dy++) {
        for (uint dx = 0; dx < 2; dx++) {
            uint2 at = uint2(gid.x * 2 + dx, gid.y * 2 + dy);
            if (at.x >= u.width || at.y >= u.height) {
                continue;
            }
            float3 rgb = clamp(float3(src.read(at).rgb), 0.0, 1.0);
            float luma = dot(rgb, weights);
            planes[at.y * u.lumaStride + at.x] = ushort(round(64.0 + 876.0 * luma));
            cb += (rgb.b - luma) / cbScale;
            cr += (rgb.r - luma) / crScale;
            count += 1.0;
        }
    }
    uint chroma = gid.y * u.chromaStride + gid.x;
    planes[u.cbOffset + chroma] = ushort(clamp(round(512.0 + 896.0 * cb / count), 0.0, 1023.0));
    planes[u.crOffset + chroma] = ushort(clamp(round(512.0 + 896.0 * cr / count), 0.0, 1023.0));
}
