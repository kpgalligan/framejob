//! Export presets and the resolution of one into concrete settings
//! (spec §7.8).
//!
//! Rust decides, AVFoundation does: nothing here encodes anything. The job
//! is to turn "H.264, 1920 × 1080, the in/out range, 30 fps" into the exact
//! set of values Swift hands to the writer — the preset name, the output
//! file type, the time range, the frame size — so that the choice of format
//! is testable without a GPU and the MCP agent's `export` tool takes the
//! same vocabulary the UI does.
//!
//! A preset is an ENCODING — a container and a codec — and carries no size:
//! an export is at the document's own size unless one is asked for, and
//! the sizes on offer for a document and a format are a separate list,
//! [`Project::export_sizes`] in `export_size.rs`, whose rows reach the
//! resolver here as the same `width`/`height` overrides a script sends.
//!
//! Two of the presets name a format AVFoundation cannot write at all: an
//! animated GIF and an animated PNG are assembled frame by frame through
//! ImageIO. That changes nothing here except one field — those rows carry
//! no `avf_preset`, and a null `avf_preset` is Swift's signal to take the
//! image-sequence path instead of building a session. Everything else
//! (the size, the rate, the range, the file's UTI) is resolved identically,
//! because it means the same thing on either path.
//!
//! Two rows, `av1` (spec §11 CX-12) and `av1_webm` (CX-15), are encoded by
//! a bundled library and not by AVFoundation, which still writes `av1`'s
//! container (the core writes `av1_webm`'s): their `writer` names the route
//! and their `encoder_speed` the library's speed, two keys no other row's
//! settings carry.
//!
//! The preset table is the single source of truth: [`presets`] serializes
//! it for the picker and [`Project::export_settings`] resolves against the
//! same rows, so a preset cannot exist in the menu and not in the resolver.
//!
//! How an override value is READ and REFUSED is `export_overrides.rs`,
//! and the rows themselves — the containers, and the presets written into
//! them — are `export_table.rs`. The vocabulary and the table: this file
//! is the design they serve and the resolution that brings the two of
//! them together against one project.

use serde_json::{Map, Value};

use crate::export_overrides::{
    boolean, dynamic_range, encoder_speed, fps as fps_override, loudness, object, positive_u32,
    range as range_override,
};
use crate::export_table::{fps_json, EncoderSpeed};
use crate::model::Project;
use crate::time;

/// Re-exported at its old path. Five modules outside this one
/// (`edit.rs`, `edit_props.rs`, `edit_action.rs`, `edit_paste.rs`,
/// `edit_track.rs`) name `crate::export::describe` for their own error
/// messages — it was never really an export function — so the phase-5 cut
/// that moved it into `export_overrides.rs` costs them nothing.
pub(crate) use crate::export_overrides::describe;

/// Re-exported at their old paths too, on the same terms and for the same
/// reason: the rows went out to `export_table.rs` under the size rule, and
/// the two callers that ask the table a question should not have to learn
/// which file the answer moved to. `ffi_query.rs` answers
/// `rc_export_presets` with `export::presets()`, and `export_size.rs`
/// looks a row up with `export::preset(id)` — the ONE lookup, which the
/// resolver below shares with it.
pub(crate) use crate::export_table::preset;
pub use crate::export_table::presets;

// ---- resolution ----------------------------------------------------------

impl Project {
    /// Resolves `preset_id` plus optional `overrides` against this project
    /// into the concrete settings Swift configures the export session with
    /// (`rc_export_settings`).
    ///
    /// Overrides may set `width`, `height`, `fps` (`[num, den]`), `range`
    /// (`{"start", "duration"}` in ticks), `optimize_for_network`, the two
    /// bitrates `video_bitrate` / `audio_bitrate` (bits per second,
    /// strictly positive), the two loudness figures `loudness_lufs` /
    /// `peak_dbtp`, `dynamic_range` (`hlg`, `pq` or `sdr`, spec §11
    /// HD-14) and `encoder_speed` (`faster`, `balanced` or `smaller`, on a
    /// row a bundled encoder writes, CX-12); anything else in the object is ignored, so a newer UI
    /// can send fields this build does not know. Each is read and refused
    /// by `export_overrides.rs`, which is where the spelling of every one
    /// of them lives.
    ///
    /// A bitrate is emitted only when it was asked for. There is no default
    /// to fall back on (see `export_table::PRESETS`), and an absent key says
    /// exactly that — "let the encoder pick" — where a zero or a null would
    /// have to be re-interpreted as the same thing on the Swift side. The two
    /// are accepted for every preset, including the ones that cannot use them,
    /// on the same principle that reports a width for the audio-only row:
    /// one rule for reading overrides, and the format flags say what the
    /// output can actually carry.
    ///
    /// The two loudness figures follow the bitrates exactly — emitted only
    /// when asked for, accepted by every preset — with one difference the
    /// reader states and argues: a `peak_dbtp` with no `loudness_lufs` is
    /// an `Err`, because normalisation is gain-only and a ceiling with
    /// nothing to cap would be a key accepted, echoed and silently inert.
    ///
    /// The range is snapped to the export's frame grid and clamped to the
    /// project, because an `AVAssetExportSession` `timeRange` that begins
    /// between two frames starts the export on a frame the user did not
    /// choose. A range that resolves to zero length is refused: an empty
    /// export is always a mistake, and AVFoundation reports it far later
    /// and far less clearly.
    ///
    /// `Err` for an unknown preset or a malformed override. This is a QUERY
    /// and not an edit: there is no "changes nothing" case, so it has no
    /// identity arm and no refusal arm (spec §5.5).
    pub fn export_settings(
        &self,
        preset_id: &str,
        overrides: Option<&Value>,
    ) -> Result<Value, String> {
        let preset = preset(preset_id)?;
        let overrides = object(overrides)?;
        // The picture the row writes (spec §11 HD-14 (c), `dynamic_range.rs`):
        // read before anything else, so a mistyped value is refused by name
        // whatever the row, and resolved against the canvas and the row.
        let picture = self.deliverable(preset, dynamic_range(overrides)?)?;
        // The bundled encoder's speed (spec §11 CX-12 (2)): read on any row
        // so a misspelling is named, then refused on a row it cannot apply
        // to, and Balanced when a writer row was not asked.
        let speed = match (encoder_speed(overrides)?, preset.takes_encoder_speed()) {
            (Some(_), false) => {
                return Err(format!(
                    "{} has no encoder speed; encoder_speed applies to av1 and av1_webm",
                    preset.id
                ))
            }
            (asked, true) => Some(asked.unwrap_or(EncoderSpeed::Balanced)),
            (None, false) => None,
        };

        // Size: the preset's cap if it has one, else the canvas — a movie
        // preset renders at whatever the project composites at, and a size
        // the sheet's popup or a script chose arrives as the override.
        let (preset_width, preset_height) = preset
            .size
            .unwrap_or((self.canvas.width, self.canvas.height));
        let width = positive_u32(overrides, "width")?.unwrap_or(preset_width);
        let height = positive_u32(overrides, "height")?.unwrap_or(preset_height);
        // What is reported is the size the FILE will have, so that the
        // sheet's readout, its Size popup and the `export` tool's result
        // all say the numbers the writer draws (`export_size.rs` has both
        // rules and their reasons). An image format is written with the
        // picture FITTED inside the size, never letterboxed and never
        // upscaled, so its numbers are the fit and not the box. A row that
        // needs even dimensions writes an odd edge one pixel smaller
        // (spec §11 G-33), whether the edge came from the canvas or was
        // asked for. Every other row writes the pair as it stands.
        let (width, height) = if preset.fits_inside_size() {
            crate::export_size::fit_within((self.canvas.width, self.canvas.height), (width, height))
        } else if preset.even_sized() {
            crate::export_size::even_size((width, height))
        } else {
            (width, height)
        };

        // The preset's rate, else the canvas — the image-sequence presets
        // cap the rate for the same reason they cap the size, and every
        // movie preset exports at the rate the project was cut at.
        let fps = fps_override(overrides, preset.fps.unwrap_or(self.canvas.fps))?;

        let project_duration = self.duration();
        let (mut start, mut duration) = range_override(overrides, (0, project_duration))?;
        // Snap first, then clamp: snapping can only move a bound by less
        // than a frame, so clamping afterwards cannot be undone by it.
        start = time::snap_to_frame(start, fps).clamp(0, project_duration);
        duration =
            time::snap_to_frame(duration, fps).clamp(0, project_duration.saturating_sub(start));
        if duration <= 0 {
            return Err(format!(
                "export range is empty: {duration} ticks at {start} in a project {project_duration} ticks long"
            ));
        }

        // Bits per second, or nothing at all. No preset supplies one, so an
        // absent key here reaches Swift as an absent key there and means
        // "the encoder's own ladder".
        let video_bitrate = positive_u32(overrides, "video_bitrate")?;
        let audio_bitrate = positive_u32(overrides, "audio_bitrate")?;

        // The integrated loudness target and the true-peak ceiling that
        // caps the gain it asks for, on the bitrates' terms: emitted only
        // when asked for, so an absent `loudness_lufs` reaches Swift as an
        // absent key and means "do not normalise". The reader is the one
        // place their bounds and their pairing rule live.
        let (loudness_lufs, peak_dbtp) = loudness(overrides)?;

        let optimize = boolean(
            overrides,
            "optimize_for_network",
            preset.container.optimizes_for_network(),
        )?;

        let mut range = Map::new();
        range.insert("start".to_string(), Value::from(start));
        range.insert("duration".to_string(), Value::from(duration));

        let mut out = Map::new();
        out.insert("preset".to_string(), Value::from(preset.id));
        // Null here means "AVFoundation cannot write this" — the GIF and
        // APNG rows — and is Swift's cue to take the ImageIO path. It is
        // NOT "pick a session preset yourself".
        out.insert(
            "avf_preset".to_string(),
            match preset.avf_preset {
                Some(name) => Value::from(name),
                None => Value::Null,
            },
        );
        out.insert(
            "container".to_string(),
            Value::from(preset.container.as_str()),
        );
        out.insert(
            "file_type".to_string(),
            Value::from(preset.container.file_type()),
        );
        out.insert("codec".to_string(), Value::from(preset.codec));
        // Width and height are reported even for the audio-only preset —
        // they cost nothing and let the sheet show one summary line for
        // every preset — but `video: false` is what Swift keys off.
        out.insert("width".to_string(), Value::from(width));
        out.insert("height".to_string(), Value::from(height));
        out.insert("fps".to_string(), fps_json(Some(fps)));
        if let Some(bps) = video_bitrate {
            out.insert("video_bitrate".to_string(), Value::from(bps));
        }
        if let Some(bps) = audio_bitrate {
            out.insert("audio_bitrate".to_string(), Value::from(bps));
        }
        if let Some(lufs) = loudness_lufs {
            out.insert("loudness_lufs".to_string(), Value::from(lufs));
        }
        if let Some(dbtp) = peak_dbtp {
            out.insert("peak_dbtp".to_string(), Value::from(dbtp));
        }
        out.insert("range".to_string(), Value::Object(range));
        // Audio is offered whenever the container can hold it: a project
        // with no sound simply produces no audio track, which is cheaper
        // than deciding here. A GIF or an APNG holds none at all.
        out.insert(
            "audio".to_string(),
            Value::from(preset.container.carries_audio()),
        );
        out.insert("video".to_string(), Value::from(preset.video));
        // Whether the ENCODING carries a fourth channel — true for
        // `prores_4444`, `hevc_alpha` and `apng`, and for nothing else the
        // table offers. `export_table.rs`'s `alpha` field doc is where
        // `apng` against `gif` is argued — a GIF shows a transparent pixel
        // and still answers false, because it has one palette index and no
        // fourth channel — and `core/tests/export.rs` pins the three rows
        // by name.
        //
        // It reads `preset.alpha` and not `self.canvas.background`, which
        // is the whole decision and is worth one sentence here as well as
        // in the field doc: this object is flat and one shape for every
        // row, so a flag that answered "the canvas is translucent" would
        // say `alpha: true` on an H.264, a GIF and a WAV — three files with
        // nowhere to put it. It is `audio`'s kind of fact, one line up, and
        // told the same way: what the file can HOLD, never what this
        // document happens to be. A transparent canvas written through a
        // row that answers FALSE composites onto black, and this is the key
        // that lets the sheet and the `export` tool say so before the file
        // exists.
        out.insert("alpha".to_string(), Value::from(preset.alpha));
        out.insert("optimize_for_network".to_string(), Value::from(optimize));
        // An HLG project's video row names the picture it writes (spec §11
        // HD-14 (c)): `hlg`, `pq` or `sdr`; only then, so every SDR project's
        // settings are the text they were and an audio row is unchanged.
        if let Some(picture) = picture {
            out.insert("color".to_string(), Value::from(picture.as_str()));
        }
        // The encoder route and its speed, on a writer row only, so every
        // other row's settings are the text they were (spec §11 CX-12).
        if let (Some(writer), Some(speed)) = (preset.writer, speed) {
            out.insert("writer".to_string(), Value::from(writer.as_str()));
            out.insert("encoder_speed".to_string(), Value::from(speed.as_str()));
        }
        Ok(Value::Object(out))
    }
}
