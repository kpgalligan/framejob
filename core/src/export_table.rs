//! The export table: the closed set of files Frame Job can write, and
//! nothing whatever about writing one of them (spec §7.8).
//!
//! Split out of `export.rs` under the size rule (core/CLAUDE.md: a module
//! at ~600 lines gives something up BEFORE it takes anything on), which
//! that file paid once already — `describe` and the override readers went
//! to `export_overrides.rs` in road map 2's phase 5, and this is the
//! second cut, taken in phase 7 for the same reason and along a different
//! seam. The rule both follow: cut where somebody can NAME the line, and
//! re-export the piece taken out whole, so not one path anywhere else
//! changes.
//!
//! # The seam: a fact about the world, not about a document
//!
//! Everything in this file is a constant, and none of it can be
//! influenced by a project. [`Container`] is the set of files this
//! application knows how to produce and the four questions each one
//! answers about ITSELF — its extension, its UTI, whether a leading index
//! is worth rewriting, whether it can hold sound at all. [`Preset`] is one
//! encoding placed in one of those containers, and [`PRESETS`] is every
//! such row in menu order. An APNG's type identifier is PNG's whatever
//! the timeline holds; GIF caps its size because of what a palettised
//! frame-by-frame format costs, not because of anybody's canvas.
//!
//! `export.rs` keeps the other half, and the other half is the one with a
//! `&self`: `Project::export_settings` is the only code that reads a
//! canvas, a duration, a rate or an override, and it is where those meet
//! a row from here. So the line runs between them in one direction only —
//! the resolver knows the table, the table knows nothing about a project
//! — which is also why the module doc that explains the whole export
//! design stays over there rather than following the rows here. This file
//! says what CAN be written. That one says what this particular document,
//! written that way, comes out as.
//!
//! # Paths
//!
//! `export.rs` re-exports [`presets`] and [`preset`] at their old names,
//! so `crate::export::presets()` (`ffi_query.rs`) and
//! `crate::export::preset(id)` (`export_size.rs`) resolve exactly as they
//! did — the same trick, and for the same reason, as the `describe`
//! re-export sitting a few lines above them. What the cut did cost is
//! visibility, mechanically: the [`Preset`] fields the resolver reads and
//! the four [`Container`] questions it asks are `pub(crate)` now, where
//! one file had been able to keep them private. [`fps_json`] came across
//! with the table rather than staying with the resolver and is
//! `pub(crate)` for it: both sides spell a rate, and its being one
//! function is the whole of why they cannot disagree about the shape.

use serde_json::Value;

pub(crate) use crate::export_container::Container;
pub(crate) use crate::export_encoder::{EncoderSpeed, Writer};
pub(crate) use crate::export_preset::{fps_json, Preset};
use crate::time::Fps;

/// The §7.8 set: one row per ENCODING, in menu order. A row is a container
/// and a codec and nothing else — no size, no rate — so an export is at the
/// document's own size and rate unless a person asks for another, through
/// the Size popup the sheet fills from `Project::export_sizes` or the
/// overrides a script sends. The size used to be part of the row ("H.264
/// 1080p", "HEVC 4K"), and that shape made the format menu two questions
/// asked as one: picking HEVC meant picking 1080p or 4K with it, and a
/// 1440p or a vertical document had no row that fit it at all. Two
/// questions get two controls, and the format is only ever the encoding.
///
/// The two image rows are the exception and keep a size and a rate,
/// because for them the numbers ARE what makes the row worth having: a GIF
/// or an APNG costs frames × pixels with no inter-frame prediction to
/// spend against, so "at the document's size and rate" is a file no one
/// can send, and the cap is the point of the format rather than a default
/// it happens to carry (§7.8; the row comments argue each number). Both
/// caps are still defaults a size or fps override replaces, and
/// `export_sizes` lists each as the first row of its list.
///
/// The FIRST row is the default: `rc_export_presets` is "in menu order"
/// and the export sheet opens on its first entry, so whatever sits here is
/// what ⌘E writes unless a person picks otherwise. H.264 in MP4 is the
/// file every player and every upload form takes, which is why it leads
/// and HEVC — half the size, not yet everywhere — follows.
///
/// Each movie row carries an `AVAssetExportSession` preset name for the
/// record: the three "highest quality" names are the ones a session would
/// take the composition's own size under rather than fit it to a fixed
/// frame, which is exactly a row with no size of its own. Nothing runs a
/// session any more (§7.8), so on the Swift side the name is only the
/// signal that AVFoundation can write the row at all; the two image rows
/// carry none, which is the signal to write them frame by frame through
/// ImageIO instead. The two LPCM rows repeat `audio_m4a`'s name for the
/// same reason and with the field doc's caveat: AVFoundation has no
/// session preset for LPCM, and a null would route a WAV to ImageIO.
///
/// **No row carries a default bitrate, deliberately.** On the session path
/// the preset name IS the ladder — `AVAssetExportSession` exposes no way to
/// set a rate — so a number here would be one the export cannot honour,
/// which is worse than none at all. On the writer path VideoToolbox derives
/// a rate from the frame size, which beats any constant this table could
/// hold: one that suits 4K wastes half the file at 720p. ProRes is fixed by
/// its profile and ignores a request outright, and GIF and APNG have no
/// bitrate to set. A bitrate is therefore something the user asks for — the
/// `video_bitrate` / `audio_bitrate` overrides — never something a preset
/// assumes on their behalf.
const PRESETS: [Preset; 15] = [
    // The default (see above). The ids are the `export` tool's vocabulary
    // and every script that calls it spells them, so a row is named for
    // the encoding alone — `h264`, not `h264_document` — because the size
    // is no longer anything the id could say.
    Preset {
        id: "h264",
        name: "H.264 (MP4)",
        container: Container::Mp4,
        codec: "h264",
        video: true,
        alpha: false,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetHighestQuality"),
        writer: None,
    },
    Preset {
        id: "hevc",
        name: "HEVC (MP4)",
        container: Container::Mp4,
        codec: "hevc",
        video: true,
        alpha: false,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetHEVCHighestQuality"),
        writer: None,
    },
    // HEVC with an alpha channel (spec §11 G-33), directly after the row it
    // is a variant of. It is the DELIVERY row that keeps transparency — a
    // title or a lower third a web page or another editor plays over its
    // own background, at HEVC's size where `prores_4444` is a master — and
    // it is a MOV because that is the container AVFoundation writes the
    // codec into (it refuses it an `.mp4`). The codec is spelled as the id
    // is, `hevc_alpha`: `ExporterWriter.codecType(for:)` maps it to
    // `AVVideoCodecType.hevcWithAlpha`, and the sheet's Quality tiers and
    // bit-rate controls read the `hevc` prefix, so it takes HEVC's.
    Preset {
        id: "hevc_alpha",
        name: "HEVC with Alpha (MOV)",
        container: Container::Mov,
        codec: "hevc_alpha",
        video: true,
        alpha: true,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetHEVCHighestQualityWithAlpha"),
        writer: None,
    },
    // HEVC Main 10 (spec §11 PR-3): `hevc`'s MP4 from the compositor's
    // 16-bit frames, so a 10-bit source survives to a 10-bit delivery file.
    // After `hevc_alpha`, which G-33 keeps directly after `hevc`. The codec
    // spelling is the id's: `ExporterWriter.codecType(for:)` maps it to
    // `.hevc` with the Main 10 profile, and the `hevc` prefix gives it
    // HEVC's Quality tiers.
    Preset {
        id: "hevc_10bit",
        name: "HEVC 10-bit (MP4)",
        container: Container::Mp4,
        codec: "hevc_10bit",
        video: true,
        alpha: false,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetHEVCHighestQuality"),
        writer: None,
    },
    // AV1 in MP4 (spec §11 CX-1, CX-12, CX-14), 10-bit, an HDR row through
    // `HDR_ROWS`. SVT-AV1 encodes (`writer`); AVFoundation still writes the
    // container, which is what the passthrough name records, so the row is
    // even-sized and routed as every AVFoundation row is.
    Preset {
        id: "av1",
        name: "AV1 (MP4)",
        container: Container::Mp4,
        codec: "av1",
        video: true,
        alpha: false,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetPassthrough"),
        writer: Some(Writer::SvtAv1),
    },
    // AV1 in WebM (spec §11 CX-15): `av1`'s encoding — the same encoder,
    // speeds, cap and HDR — in a WebM the core writes (`webm_writer.rs`),
    // with Opus sound. The passthrough name records that the composition is
    // read back through AVFoundation, so the row is even-sized and routed as
    // every AVFoundation row is until `Exporter.pipeline` reads the container.
    Preset {
        id: "av1_webm",
        name: "AV1 (WebM)",
        container: Container::Webm,
        codec: "av1",
        video: true,
        alpha: false,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetPassthrough"),
        writer: Some(Writer::SvtAv1),
    },
    // VP9 in WebM (spec §11 CX-16): libvpx at its one speed (CX-3) into the
    // same core-written WebM with Opus; Profile 0 8-bit for an SDR picture,
    // Profile 2 10-bit for HLG and PQ, so an HDR row.
    Preset {
        id: "vp9_webm",
        name: "VP9 (WebM)",
        container: Container::Webm,
        codec: "vp9",
        video: true,
        alpha: false,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetPassthrough"),
        writer: Some(Writer::Libvpx),
    },
    // VP9 with alpha in WebM (spec §11 CX-17): `vp9_webm`'s 8-bit Profile 0
    // picture and a second libvpx stream of its alpha, written as each video
    // block's BlockAdditional 1 — the format Chrome and Firefox play with
    // transparency. One of the four rows with a fourth channel, so the shape
    // rule binds it; 8-bit SDR only, so not an HDR row: an HLG project writes
    // the SDR version.
    Preset {
        id: "vp9_alpha_webm",
        name: "VP9 with Alpha (WebM)",
        container: Container::Webm,
        codec: "vp9",
        video: true,
        alpha: true,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetPassthrough"),
        writer: Some(Writer::Libvpx),
    },
    Preset {
        id: "prores_422",
        name: "ProRes 422 (MOV)",
        container: Container::Mov,
        codec: "prores422",
        video: true,
        alpha: false,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetAppleProRes422LPCM"),
        writer: None,
    },
    // The MASTERING row that keeps transparency (road map 2, phase 7) —
    // one of the four rows with a fourth channel and not the only one:
    // `hevc_alpha` and `vp9_alpha_webm` above and `apng` below carry one too
    // and say so at their own rows. The four are not redundant, which is why
    // no row's comment may be written as if it were alone: this is a MASTER,
    // in a container AVFoundation writes, whose next reader is another
    // application; `hevc_alpha` is the delivery movie and `vp9_alpha_webm`
    // the browser's; and `apng` is a frame sequence with a null `avf_preset`
    // and no audio track at all. `alpha`'s field doc holds the rule all four
    // answer to, and `core/tests/export.rs` pins the four by name.
    //
    // ProRes 4444 is a master or an intermediate: a file whose next
    // reader is another application rather than a viewer — a lower third
    // or a title card cut over somebody else's footage, a screencast going
    // back into a compositor, a graphic handed to a motion designer. The
    // fourth channel is the whole of why it earns a row beside
    // `prores_422`, which shares its container, its colour and its
    // editing-master posture and differs in exactly this: 422 cannot carry
    // alpha at any bitrate. Nor can the `h264` or `hevc` row stand in —
    // neither has an alpha channel in the profile `ExporterWriter` writes
    // for it, so an export of a transparent canvas through one of them is
    // a picture flattened onto black with no way back. `hevc_alpha` does
    // keep the channel, as a lossy 8-bit 4:2:0 delivery file, which is not
    // what a master is.
    //
    // It sits AFTER 422 rather than before it because a row's position is
    // an invitation: most exports of a finished timeline have nothing
    // under them and want the smaller of the two files, so 422 stays the
    // ProRes people reach for first and 4444 is the one you go looking for
    // when you need the channel.
    Preset {
        id: "prores_4444",
        name: "ProRes 4444 (MOV)",
        container: Container::Mov,
        // The spelling `ExporterWriter.codecType(for:)` already maps to
        // `AVVideoCodecType.proRes4444`; it accepts `prores_4444` too, and
        // this one is chosen for the same reason `prores422` is — the
        // codec field is the codec's own name, where the underscore-and-id
        // spelling is the PRESET's.
        codec: "prores4444",
        video: true,
        alpha: true,
        size: None,
        fps: None,
        // Non-null, and not optional: a null `avf_preset` is the ONE
        // routing signal to the ImageIO writer (`avf_preset`'s field doc),
        // which would meet a `"mov"` container it has never heard of and
        // refuse a format this table advertises. The name is
        // AVFoundation's real ProRes 4444 preset and is a record of what
        // writes the row, nothing more — nothing has run a session since
        // M2.
        avf_preset: Some("AVAssetExportPresetAppleProRes4444LPCM"),
        writer: None,
    },
    Preset {
        id: "audio_m4a",
        name: "Audio only (M4A)",
        container: Container::M4a,
        codec: "aac",
        video: false,
        alpha: false,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetAppleM4A"),
        writer: None,
    },
    // The two uncompressed audio rows (road map 2, phase 5). M4A is what
    // you send; these are what you hand to someone else's tool — a mix
    // going out to a mastering engineer, a bed going into a podcast
    // editor, a stem a DAW will re-encode anyway — where a second lossy
    // generation is the one thing you cannot take back.
    //
    // The codec is `lpcm`, not a container spelling, because the container
    // and the codec are separate questions here and `ExportWriter` has to
    // answer the codec one to pick its `AVAssetWriterInput` settings: the
    // decoded mix is already 16-bit little-endian interleaved 48 kHz LPCM
    // (it is what the ProRes row writes), so a WAV is that dictionary
    // written straight out and an AIFF is the same samples big-endian,
    // which the CONTAINER decides.
    //
    // 16-bit, and 24 deliberately deferred: 24 would mean widening the
    // decode settings the mix is read through, which is the same
    // dictionary every other preset's encoder consumes, and a silent
    // format mismatch there is a file of noise rather than an error. A
    // depth is a request rather than a row when it comes (an `audio_bits`
    // override beside the bitrates), and it needs measuring first.
    Preset {
        id: "audio_wav",
        name: "Audio only (WAV)",
        container: Container::Wav,
        codec: "lpcm",
        video: false,
        alpha: false,
        size: None,
        fps: None,
        // Not a lie the resolver tells: see `avf_preset`'s field doc. The
        // name says "AVFoundation writes this row", and nothing more.
        avf_preset: Some("AVAssetExportPresetAppleM4A"),
        writer: None,
    },
    Preset {
        id: "audio_aiff",
        name: "Audio only (AIFF)",
        container: Container::Aiff,
        codec: "lpcm",
        video: false,
        alpha: false,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetAppleM4A"),
        writer: None,
    },
    Preset {
        id: "gif",
        name: "Animated GIF",
        container: Container::Gif,
        codec: "gif",
        video: true,
        alpha: false,
        // 480 × 270 at 12.5 fps, and both numbers are the point of the
        // preset rather than an afterthought. GIF stores every frame as a
        // whole picture over a 256-colour palette with no inter-frame
        // prediction, so its size is frames × pixels and nothing else:
        // the same ten seconds carries sixteen times the pixels at 1080p
        // and a hundred and thirty at 4K, which is why a full-rate 4K GIF
        // is a file no one can send. At 480 × 270 a ten-second clip lands
        // in single-digit megabytes, and 270 keeps the 16:9 shape the
        // other fixed-size rows use.
        //
        // 12.5 fps is not a rounding of 12. A GIF frame delay is stored in
        // hundredths of a second, so only rates that divide 100 exactly
        // survive the write, and 12.5 (8 cs) is the lowest of those that
        // still reads as motion when a cursor crosses a screen recording.
        // 10 fps (10 cs) visibly steps; 15 fps would want 6.67 cs, which
        // viewers round to 7 and then play at 14.3.
        size: Some((480, 270)),
        fps: Some(Fps { num: 25, den: 2 }),
        avf_preset: None,
        writer: None,
    },
    Preset {
        id: "apng",
        name: "Animated PNG",
        container: Container::Apng,
        codec: "apng",
        video: true,
        // One of the four rows that keep a transparent canvas
        // transparent, and the only one that is not a movie — a lossless
        // frame sequence any browser shows, with no sound.
        alpha: true,
        // 960 × 540 at 25 fps. APNG is true colour and lossless, so it
        // costs more per pixel than GIF but has no palette to quantise to:
        // twice the linear size buys back the detail GIF spends on its 256
        // colours, and the format is worth choosing only for that.
        // The rate is free of GIF's constraint — an `fcTL` delay is an
        // exact rational, not a centisecond count — so it is a familiar 25
        // rather than an arithmetic one; that is half the 50 or 60 a screen
        // recording arrives at and smooth enough that the cap is invisible.
        size: Some((960, 540)),
        fps: Some(Fps { num: 25, den: 1 }),
        avf_preset: None,
        writer: None,
    },
];

/// Every preset, in menu order, as the JSON array `rc_export_presets`
/// returns.
pub fn presets() -> Value {
    Value::Array(PRESETS.iter().map(Preset::to_json).collect())
}

/// The row for `id`, or the error naming it. The ONE lookup: both
/// [`Project::export_settings`] and `Project::export_sizes` go through it,
/// so an unknown preset reads the same whichever of the two the sheet or
/// the `export` tool asked first, and a row cannot have sizes and no
/// settings or the other way round.
pub(crate) fn preset(id: &str) -> Result<&'static Preset, String> {
    PRESETS
        .iter()
        .find(|p| p.id == id)
        .ok_or_else(|| format!("unknown export preset \"{id}\""))
}
