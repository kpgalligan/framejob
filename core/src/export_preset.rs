//! One row of the export table (spec §7.8): [`Preset`], what each row
//! answers about itself, and [`fps_json`], the rate's one spelling.
//!
//! Moved whole out of `export_table.rs` under the size rule (core/CLAUDE.md:
//! a module at ~600 lines gives something up BEFORE it takes anything on),
//! as codec-export C5's toll T1, a pure move. `export_table.rs` re-exports
//! both, so every `crate::export_table::Preset` and
//! `crate::export_table::fps_json` path holds; `name` and `to_json` became
//! `pub(crate)` because the table's rows and `presets` stay behind.

use serde_json::{Map, Value};

use crate::export_container::Container;
use crate::export_encoder::{EncoderSpeed, Writer};
use crate::time::Fps;

/// One row of the table. Crate-visible so `export_size.rs` can read the
/// cap and the codec of the row it lists sizes for, and so `export.rs`'s
/// resolver can read the rest, both through [`preset`]; every field is
/// `pub(crate)` because the table's rows are built in `export_table.rs`.
pub(crate) struct Preset {
    pub(crate) id: &'static str,
    pub(crate) name: &'static str,
    pub(crate) container: Container,
    pub(crate) codec: &'static str,
    /// False for the three audio-only presets; every other row carries
    /// video.
    pub(crate) video: bool,
    /// Whether this ENCODING carries an alpha channel — `hevc_alpha`,
    /// `vp9_alpha_webm`, `prores_4444` and `apng`, and nothing else. It says what the FILE can
    /// hold, and never that a particular canvas is translucent:
    /// `export_settings`
    /// emits one flat object for every row, so a flag derived from the
    /// project's background would report `alpha: true` on an H.264, a GIF
    /// and a WAV, which reads as a defect from either side of the FFI. A
    /// transparent canvas exported through a row with no fourth channel
    /// simply composites onto black, and the flag is what lets the sheet
    /// and the `export` tool say so before the file exists.
    ///
    /// **It is a `Preset` field and not a [`Container`] question**, which
    /// is the one thing worth arguing here, because the neighbouring
    /// capability [`Container::carries_audio`] IS a container question and
    /// the two look alike. Whether a file can hold a sound track is decided
    /// by the container's format — a GIF has no audio track to put samples
    /// in whatever you encode — so it is answered once for the container.
    /// A fourth channel is decided by the CODEC: `Container::Mov` hosts
    /// `prores_422` and `prores_4444` alike, and 422 cannot carry alpha at
    /// any bitrate, so a container-level answer would have to be wrong for
    /// one of the two rows. Same shape of fact, different owner.
    ///
    /// **`gif` is false and `apng` is true, and the difference is the word
    /// CHANNEL.** Both can show a transparent pixel, so both look alike
    /// from the outside and a reader who has exported one will call this
    /// row a mistake. APNG is true colour with a real fourth channel and a
    /// pixel may be any fraction of opaque. A GIF has ONE palette index
    /// nominated as transparent: a pixel is either that index or fully
    /// opaque, there is no partial value to store, and a soft edge against
    /// nothing comes out as a hard jagged one. A flag that answered "yes"
    /// for both would license the sheet to promise a translucent GIF.
    /// Measured on the way in, not assumed: an `apng` export of a
    /// transparent canvas decodes `pix_fmt=rgba` with its corner at
    /// alpha 0, and a `gif` of the same timeline decodes with the corner
    /// transparent through its palette and no partial value anywhere.
    pub(crate) alpha: bool,
    /// `None` means "the project's canvas size", which is what every movie
    /// row wants: a preset is an encoding, and the size is the document's
    /// unless a `width`/`height` override says otherwise. The resolver
    /// fills the canvas in for the audio-only rows too, so every settings
    /// object carries a width. Only the two image rows pin one — the cap
    /// `Project::export_sizes` lists as their default.
    pub(crate) size: Option<(u32, u32)>,
    /// `None` means "the project's canvas rate", which is what every movie
    /// preset wants. Only the image-sequence rows pin one, because their
    /// cost is frames × pixels and nothing else.
    pub(crate) fps: Option<Fps>,
    /// The `AVAssetExportSession` preset name, verbatim; `None` for a
    /// container AVFoundation cannot write.
    ///
    /// Since phase 5 the field means only **"AVFoundation can write this
    /// row"**, and the name itself is a record rather than an instruction.
    /// Nothing has run a session since M2, but `null` here is still the
    /// one thing routing an export to the ImageIO writer
    /// (`ExportSettings.isImageSequence` is literally `avPreset == nil`),
    /// so a row that AVFoundation writes must carry SOME name even when
    /// AVFoundation has no name for it. There is no `AVAssetExportPreset`
    /// for LPCM in a WAV or an AIFF, so those two rows carry the audio-only
    /// name `audio_m4a` carries: it is the closest true statement
    /// available — "an audio-only file AVFoundation writes" — and a null
    /// there would hand a WAV to `ImageSequenceWriter`, which would refuse
    /// it as an unknown image container and report a format this table
    /// advertises as unsupported. A name also means "the composition is
    /// read back through AVFoundation" (spec §11 CX-15), which is all it says
    /// on `av1_webm` and `vp9_webm`, whose files the core writes.
    pub(crate) avf_preset: Option<&'static str>,
    /// The bundled encoder that writes the row's video, or `None` for
    /// AVFoundation's own encoders (ImageIO where `avf_preset` is null).
    /// A row with a writer takes `encoder_speed` when its encoder has
    /// speeds (`Writer::takes_speed`).
    pub(crate) writer: Option<Writer>,
}

/// A rate as the two-element `[num, den]` array the spec spells every rate
/// with, or null for "the project's own". One function so the preset row
/// and the resolved settings cannot disagree about the shape.
pub(crate) fn fps_json(fps: Option<Fps>) -> Value {
    match fps {
        Some(fps) => Value::Array(vec![Value::from(fps.num), Value::from(fps.den)]),
        None => Value::Null,
    }
}

impl Preset {
    /// True for the rows written frame by frame through ImageIO — the ones
    /// with no session preset — whose picture is FITTED inside the size
    /// rather than letterboxed to it, so a size on them is a box and the
    /// resolved numbers are the fit (`export_size::fit_within`).
    pub(crate) fn fits_inside_size(&self) -> bool {
        self.video && self.avf_preset.is_none()
    }

    /// True for the rows whose frame has to have EVEN pixel dimensions:
    /// every row AVFoundation writes but ProRes 4444 (spec §11 G-33). On
    /// these an odd edge is resolved one pixel smaller, in the size list's
    /// Document row and in the resolved settings alike
    /// (`export_size::even_size`), so the size reported is the size the
    /// writer writes.
    ///
    /// It is asked of `avf_preset` and the codec rather than listed row by
    /// row, so a new AVFoundation row is even-sized until someone exempts
    /// it — the safe side, since 4:2:0 chroma needs it and a row that can
    /// keep an odd edge has to be measured doing so, as ProRes 4444 was
    /// (`ExporterWriter+Settings.swift`'s `encodedSize`). The audio-only
    /// rows answer true: they have no picture and go on reporting what
    /// `h264` reports. The two image rows answer false; their numbers are
    /// the fit (`fits_inside_size`), odd or not.
    pub(crate) fn even_sized(&self) -> bool {
        self.avf_preset.is_some() && self.codec != "prores4444"
    }

    /// True for a row whose bundled encoder has speeds, the rows
    /// `encoder_speed` applies to (spec §11 CX-12 (2), CX-16 (2)).
    pub(crate) fn takes_encoder_speed(&self) -> bool {
        self.writer.is_some_and(Writer::takes_speed)
    }

    pub(crate) fn to_json(&self) -> Value {
        let mut out = Map::new();
        out.insert("id".to_string(), Value::from(self.id));
        out.insert("name".to_string(), Value::from(self.name));
        out.insert(
            "container".to_string(),
            Value::from(self.container.as_str()),
        );
        out.insert("codec".to_string(), Value::from(self.codec));
        out.insert("video".to_string(), Value::from(self.video));
        out.insert(
            "size".to_string(),
            match self.size {
                Some((w, h)) => Value::Array(vec![Value::from(w), Value::from(h)]),
                None => Value::Null,
            },
        );
        // `size` and `fps` are spelled the same way for the same reason:
        // null is "whatever the project is" — the document size, the
        // document rate — which the resolver fills in from the canvas.
        out.insert("fps".to_string(), fps_json(self.fps));
        out.insert(
            "avf_preset".to_string(),
            match self.avf_preset {
                Some(name) => Value::from(name),
                None => Value::Null,
            },
        );
        if crate::dynamic_range::HDR_ROWS.contains(&self.id) {
            out.insert("hdr".to_string(), Value::from(true));
        }
        if let Some(writer) = self.writer {
            out.insert("writer".to_string(), Value::from(writer.as_str()));
            if writer.takes_speed() {
                let speeds = EncoderSpeed::ALL.iter().map(|s| Value::from(s.as_str()));
                out.insert("encoder_speeds".to_string(), speeds.collect());
            }
        }
        Value::Object(out)
    }
}
