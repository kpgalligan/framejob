//! Export presets and the resolution of one into concrete settings
//! (spec §7.8).
//!
//! Rust decides, AVFoundation does: nothing here encodes anything. The job
//! is to turn "H.264 1080p, the in/out range, 30 fps" into the exact set of
//! values Swift hands to `AVAssetExportSession` — the preset name, the
//! output file type, the time range, the frame size — so that the choice of
//! preset is testable without a GPU and the MCP agent's `export` tool takes
//! the same vocabulary the UI does.
//!
//! Two of the presets name a format AVFoundation cannot write at all: an
//! animated GIF and an animated PNG are assembled frame by frame through
//! ImageIO. That changes nothing here except one field — those rows carry
//! no `avf_preset`, and a null `avf_preset` is Swift's signal to take the
//! image-sequence path instead of building a session. Everything else
//! (the size, the rate, the range, the file's UTI) is resolved identically,
//! because it means the same thing on either path.
//!
//! The preset table is the single source of truth: [`presets`] serializes
//! it for the picker and [`Project::export_settings`] resolves against the
//! same rows, so a preset cannot exist in the menu and not in the resolver.

use serde_json::{Map, Value};

use crate::model::Project;
use crate::time::{self, Fps, Ticks};

// ---- the preset table ----------------------------------------------------

/// The containers Reelcut writes. Kept as an enum rather than a string so
/// the container, its UTI, its network-optimization default and whether it
/// can hold sound at all are decided in exactly one exhaustive place.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Container {
    Mov,
    Mp4,
    M4a,
    Gif,
    Apng,
}

impl Container {
    fn as_str(self) -> &'static str {
        match self {
            Container::Mov => "mov",
            Container::Mp4 => "mp4",
            Container::M4a => "m4a",
            Container::Gif => "gif",
            Container::Apng => "apng",
        }
    }

    /// The output file's UTI. On the AVFoundation path Swift passes this
    /// straight to `outputFileType`, whose raw values ARE UTIs; on the
    /// ImageIO path it is the destination type
    /// `CGImageDestinationCreateWithURL` takes. Either way it is what the
    /// save panel's content type and file extension are derived from, which
    /// is why the two image formats name a real UTI here rather than
    /// nothing — an export that could not tell the panel it writes a `.gif`
    /// would be worse off than one whose type string a session would
    /// reject, and a session is never built for them.
    ///
    /// An APNG is written to an ordinary PNG destination — the animation
    /// lives in `acTL`/`fcTL` chunks inside a file that is still a PNG — so
    /// its type identifier is PNG's, not one of its own.
    fn file_type(self) -> &'static str {
        match self {
            Container::Mov => "com.apple.quicktime-movie",
            Container::Mp4 => "public.mpeg-4",
            Container::M4a => "com.apple.m4a-audio",
            Container::Gif => "com.compuserve.gif",
            Container::Apng => "public.png",
        }
    }

    /// Whether `shouldOptimizeForNetworkUse` defaults on. MP4 and M4A are
    /// the delivery containers people upload, and a leading `moov` atom
    /// lets a player start before the file is fully fetched. A ProRes MOV
    /// is an editing master handed to another application, where the
    /// rewrite pass buys nothing. GIF and APNG have no `moov` atom and
    /// nothing to move: a viewer already starts on the first frame.
    fn optimizes_for_network(self) -> bool {
        matches!(self, Container::Mp4 | Container::M4a)
    }

    /// Whether the container can hold sound. Every movie container can and
    /// M4A is nothing else; GIF and APNG are picture formats with no audio
    /// track in the file format at all, so `audio: false` for those is a
    /// fact about the container rather than a decision about the project.
    fn carries_audio(self) -> bool {
        !matches!(self, Container::Gif | Container::Apng)
    }
}

struct Preset {
    id: &'static str,
    name: &'static str,
    container: Container,
    codec: &'static str,
    /// False for the audio-only preset; every other row carries video.
    video: bool,
    /// `None` means "the project's canvas size" — the source-size presets.
    size: Option<(u32, u32)>,
    /// `None` means "the project's canvas rate", which is what every movie
    /// preset wants. Only the image-sequence rows pin one, because their
    /// cost is frames × pixels and nothing else.
    fps: Option<Fps>,
    /// The `AVAssetExportSession` preset name, verbatim; `None` for a
    /// container AVFoundation cannot write.
    avf_preset: Option<&'static str>,
}

/// The §7.8 set. M1 maps the movie rows onto `AVAssetExportSession`'s named
/// presets, which is why each carries one: the session's preset decides the
/// codec and the bitrate ladder, and the size below is what the video
/// composition renders at. The two image rows carry none — Swift writes
/// those frame by frame through ImageIO.
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
const PRESETS: [Preset; 9] = [
    Preset {
        id: "h264_1080p",
        name: "H.264 1080p",
        container: Container::Mp4,
        codec: "h264",
        video: true,
        size: Some((1920, 1080)),
        fps: None,
        avf_preset: Some("AVAssetExportPreset1920x1080"),
    },
    Preset {
        id: "h264_720p",
        name: "H.264 720p",
        container: Container::Mp4,
        codec: "h264",
        video: true,
        size: Some((1280, 720)),
        fps: None,
        avf_preset: Some("AVAssetExportPreset1280x720"),
    },
    Preset {
        id: "h264_source",
        name: "H.264 source size",
        container: Container::Mp4,
        codec: "h264",
        video: true,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetHighestQuality"),
    },
    Preset {
        id: "hevc_1080p",
        name: "HEVC 1080p",
        container: Container::Mp4,
        codec: "hevc",
        video: true,
        size: Some((1920, 1080)),
        fps: None,
        avf_preset: Some("AVAssetExportPresetHEVC1920x1080"),
    },
    Preset {
        id: "hevc_4k",
        name: "HEVC 4K",
        container: Container::Mp4,
        codec: "hevc",
        video: true,
        size: Some((3840, 2160)),
        fps: None,
        avf_preset: Some("AVAssetExportPresetHEVC3840x2160"),
    },
    Preset {
        id: "prores_422",
        name: "ProRes 422 (MOV)",
        container: Container::Mov,
        codec: "prores422",
        video: true,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetAppleProRes422LPCM"),
    },
    Preset {
        id: "audio_m4a",
        name: "Audio only (M4A)",
        container: Container::M4a,
        codec: "aac",
        video: false,
        size: None,
        fps: None,
        avf_preset: Some("AVAssetExportPresetAppleM4A"),
    },
    Preset {
        id: "gif",
        name: "Animated GIF",
        container: Container::Gif,
        codec: "gif",
        video: true,
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
    },
    Preset {
        id: "apng",
        name: "Animated PNG",
        container: Container::Apng,
        codec: "apng",
        video: true,
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
    },
];

/// A rate as the two-element `[num, den]` array the spec spells every rate
/// with, or null for "the project's own". One function so the preset row
/// and the resolved settings cannot disagree about the shape.
fn fps_json(fps: Option<Fps>) -> Value {
    match fps {
        Some(fps) => Value::Array(vec![Value::from(fps.num), Value::from(fps.den)]),
        None => Value::Null,
    }
}

impl Preset {
    fn to_json(&self) -> Value {
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
        // null is "whatever the project is", which the picker shows as
        // "source" and the resolver fills in from the canvas.
        out.insert("fps".to_string(), fps_json(self.fps));
        out.insert(
            "avf_preset".to_string(),
            match self.avf_preset {
                Some(name) => Value::from(name),
                None => Value::Null,
            },
        );
        Value::Object(out)
    }
}

/// Every preset, in menu order, as the JSON array `rc_export_presets`
/// returns.
pub fn presets() -> Value {
    Value::Array(PRESETS.iter().map(Preset::to_json).collect())
}

// ---- override reading ----------------------------------------------------

/// A JSON value as short text for an error message, truncated on a char
/// boundary so a pasted megabyte of JSON cannot become the error string.
pub(crate) fn describe(value: &Value) -> String {
    let text = value.to_string();
    if text.chars().count() <= 40 {
        text
    } else {
        format!("{} …", text.chars().take(40).collect::<String>())
    }
}

/// An override field, or `None` when absent or explicitly null (null means
/// "use the preset", so a caller can build one overrides object and leave
/// the fields it does not care about).
fn field<'a>(overrides: Option<&'a Value>, key: &str) -> Option<&'a Value> {
    overrides.and_then(|o| o.get(key)).filter(|v| !v.is_null())
}

/// A strictly positive integer override — the pixel dimensions and the two
/// bitrates, which want the identical check. `u64::MAX` is not the ceiling
/// on purpose: a bitrate is bits per second, and `u32`'s 4.3 Gbit/s is an
/// order of magnitude past anything deliverable (ProRes 422 at 4K is about
/// 0.7), so the same bound that keeps a width sane keeps a bitrate honest.
/// Zero and negative both land in the error arm, which names the value.
fn positive_u32(overrides: Option<&Value>, key: &str) -> Result<Option<u32>, String> {
    let Some(value) = field(overrides, key) else {
        return Ok(None);
    };
    match value.as_u64() {
        Some(n) if n > 0 && n <= u64::from(u32::MAX) => Ok(Some(n as u32)),
        _ => Err(format!(
            "export {key} must be a positive integer, not {}",
            describe(value)
        )),
    }
}

fn ticks(value: &Value, what: &str) -> Result<Ticks, String> {
    value.as_i64().ok_or_else(|| {
        format!(
            "export {what} must be an integer number of ticks, not {}",
            describe(value)
        )
    })
}

// ---- resolution ----------------------------------------------------------

impl Project {
    /// Resolves `preset_id` plus optional `overrides` against this project
    /// into the concrete settings Swift configures the export session with
    /// (`rc_export_settings`).
    ///
    /// Overrides may set `width`, `height`, `fps` (`[num, den]`), `range`
    /// (`{"start", "duration"}` in ticks), `optimize_for_network` and the
    /// two bitrates `video_bitrate` / `audio_bitrate` (bits per second,
    /// strictly positive); anything else in the object is ignored, so a
    /// newer UI can send fields this build does not know.
    ///
    /// A bitrate is emitted only when it was asked for. There is no default
    /// to fall back on (see [`PRESETS`]), and an absent key says exactly
    /// that — "let the encoder pick" — where a zero or a null would have to
    /// be re-interpreted as the same thing on the Swift side. The two are
    /// accepted for every preset, including the ones that cannot use them,
    /// on the same principle that reports a width for the audio-only row:
    /// one rule for reading overrides, and the format flags say what the
    /// output can actually carry.
    ///
    /// The range is snapped to the export's frame grid and clamped to the
    /// project, because an `AVAssetExportSession` `timeRange` that begins
    /// between two frames starts the export on a frame the user did not
    /// choose. A range that resolves to zero length is refused: an empty
    /// export is always a mistake, and AVFoundation reports it far later
    /// and far less clearly.
    ///
    /// `Err` for an unknown preset or a malformed override; there is no
    /// "changes nothing" case, so this never returns a bare `None`.
    pub fn export_settings(
        &self,
        preset_id: &str,
        overrides: Option<&Value>,
    ) -> Result<Value, String> {
        let preset = PRESETS
            .iter()
            .find(|p| p.id == preset_id)
            .ok_or_else(|| format!("unknown export preset \"{preset_id}\""))?;

        let overrides = match overrides {
            None => None,
            Some(Value::Null) => None,
            Some(value) if value.is_object() => Some(value),
            Some(value) => {
                return Err(format!(
                    "export overrides must be a json object, not {}",
                    describe(value)
                ))
            }
        };

        // Size: the preset's, else the canvas — the "source size" presets
        // render at whatever the project composites at.
        let (preset_width, preset_height) = preset
            .size
            .unwrap_or((self.canvas.width, self.canvas.height));
        let width = positive_u32(overrides, "width")?.unwrap_or(preset_width);
        let height = positive_u32(overrides, "height")?.unwrap_or(preset_height);

        // The preset's rate, else the canvas — the image-sequence presets
        // cap the rate for the same reason they cap the size, and every
        // movie preset exports at the rate the project was cut at.
        let fps = match field(overrides, "fps") {
            None => preset.fps.unwrap_or(self.canvas.fps),
            Some(value) => {
                let terms = value.as_array().and_then(|a| {
                    match (
                        a.first().and_then(Value::as_u64),
                        a.get(1).and_then(Value::as_u64),
                    ) {
                        (Some(num), Some(den)) if a.len() == 2 => Some((num, den)),
                        _ => None,
                    }
                });
                match terms {
                    Some((num, den))
                        if num > 0
                            && den > 0
                            && num <= u64::from(u32::MAX)
                            && den <= u64::from(u32::MAX) =>
                    {
                        Fps {
                            num: num as u32,
                            den: den as u32,
                        }
                    }
                    _ => {
                        return Err(format!(
                            "export fps must be [num, den] with non-zero terms, not {}",
                            describe(value)
                        ))
                    }
                }
            }
        };

        let project_duration = self.duration();
        let (mut start, mut duration) = (0, project_duration);
        if let Some(range) = field(overrides, "range") {
            if !range.is_object() {
                return Err(format!(
                    "export range must be a json object with start and duration, not {}",
                    describe(range)
                ));
            }
            if let Some(value) = field(Some(range), "start") {
                start = ticks(value, "range start")?;
            }
            if let Some(value) = field(Some(range), "duration") {
                duration = ticks(value, "range duration")?;
            }
        }
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

        let optimize = match field(overrides, "optimize_for_network") {
            None => preset.container.optimizes_for_network(),
            Some(value) => value.as_bool().ok_or_else(|| {
                format!(
                    "export optimize_for_network must be true or false, not {}",
                    describe(value)
                )
            })?,
        };

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
        out.insert("range".to_string(), Value::Object(range));
        // Audio is offered whenever the container can hold it: a project
        // with no sound simply produces no audio track, which is cheaper
        // than deciding here. A GIF or an APNG holds none at all.
        out.insert(
            "audio".to_string(),
            Value::from(preset.container.carries_audio()),
        );
        out.insert("video".to_string(), Value::from(preset.video));
        out.insert("optimize_for_network".to_string(), Value::from(optimize));
        Ok(Value::Object(out))
    }
}
