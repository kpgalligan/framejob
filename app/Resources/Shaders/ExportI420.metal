//
//  ExportI420.metal — the `av1` row's frames for SVT-AV1 (spec §11 CX-12 (5)):
//  a compositor frame (64RGBAHalf, SDR BT.709, premultiplied) converted to
//  BT.709 video-range 8-bit I420 in three planes of one buffer. Owned by
//  `app/Sources/ExportI420.swift`, which scales the frame to the export size
//  first when it is not the canvas.
//
//  One thread per 2 × 2 block: it writes the block's four luma samples and
//  one Cb and one Cr, the mean of the four pixels' (a 2 × 2 box, the chroma
//  siting SVT's sequence header leaves unspecified). RGB is clamped to 0…1 and
//  read as it is, premultiplied, so a transparent canvas lands on black as it
//  does through VideoToolbox on `h264`.
//
//  Y′ = 0.2126 R + 0.7152 G + 0.0722 B; Y = round(16 + 219 Y′);
//  Cb = round(128 + 224 (B − Y′) / 1.8556); Cr = round(128 + 224 (R − Y′) / 1.5748).
//

#include <metal_stdlib>
using namespace metal;

/// Mirrored by `ExportI420Uniforms` in `ExportI420.swift`; every field 32 bits.
struct ExportI420Uniforms {
    uint width;
    uint height;
    uint lumaStride;
    uint chromaStride;
    uint cbOffset;
    uint crOffset;
};

kernel void framejob_export_i420(texture2d<half, access::read> src [[texture(0)]],
                                 device uchar *planes [[buffer(0)]],
                                 constant ExportI420Uniforms &u [[buffer(1)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    if (gid.x * 2 >= u.width || gid.y * 2 >= u.height) {
        return;
    }
    const float3 weights = float3(0.2126, 0.7152, 0.0722);
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
            planes[at.y * u.lumaStride + at.x] = uchar(round(16.0 + 219.0 * luma));
            cb += (rgb.b - luma) / 1.8556;
            cr += (rgb.r - luma) / 1.5748;
            count += 1.0;
        }
    }
    uint chroma = gid.y * u.chromaStride + gid.x;
    planes[u.cbOffset + chroma] = uchar(clamp(round(128.0 + 224.0 * cb / count), 0.0, 255.0));
    planes[u.crOffset + chroma] = uchar(clamp(round(128.0 + 224.0 * cr / count), 0.0, 255.0));
}
