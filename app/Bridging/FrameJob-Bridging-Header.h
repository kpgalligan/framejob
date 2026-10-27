#ifndef FRAMEJOB_BRIDGING_HEADER_H
#define FRAMEJOB_BRIDGING_HEADER_H

#include "../../core/include/framejob_core.h"

// The bundled encoders (spec §11 CX-4): platform-side C APIs Swift calls
// directly, never through an rc_* export. Their headers are build/codecs/include,
// from tools/codecs/build_codecs.py (`make codecs`).
#include <svt-av1/EbSvtAv1Enc.h>
#include <vpx/vpx_encoder.h>
#include <vpx/vp8cx.h>

#endif
