#ifndef FRAMEJOB_VPX_H
#define FRAMEJOB_VPX_H

// The two libvpx calls Swift cannot make (spec §11 CX-16 (9)), wrapped for
// `ExportVP9Encoder.swift`: `vpx_codec_enc_init` is a macro over
// `vpx_codec_enc_init_ver` with the ABI version, and `vpx_codec_control_` is
// variadic. Nothing else of libvpx is wrapped; Swift calls the rest directly.

#include <vpx/vpx_encoder.h>
#include <vpx/vp8cx.h>

/// `vpx_codec_enc_init` with libvpx's VP9 encoder interface.
static inline vpx_codec_err_t framejob_vpx_vp9_enc_init(vpx_codec_ctx_t *ctx,
                                                        const vpx_codec_enc_cfg_t *cfg,
                                                        vpx_codec_flags_t flags) {
    return vpx_codec_enc_init(ctx, vpx_codec_vp9_cx(), cfg, flags);
}

/// One integer control, `vpx_codec_control_(ctx, ctrl_id, value)`; every
/// control the export sets takes an `int` or an `unsigned int`, which pass
/// alike through the variadic call.
static inline vpx_codec_err_t framejob_vpx_control_int(vpx_codec_ctx_t *ctx, int ctrl_id,
                                                       int value) {
    return vpx_codec_control_(ctx, ctrl_id, value);
}

#endif
