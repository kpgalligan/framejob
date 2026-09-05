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
//! The preset table is the single source of truth: [`presets`] serializes
//! it for the picker and [`Project::export_settings`] resolves against the
//! same rows, so a preset cannot exist in the menu and not in the resolver.

use serde_json::{Map, Value};

use crate::model::Project;
use crate::time::{self, Fps, Ticks};

// ---- the preset table ----------------------------------------------------

/// The three containers Reelcut writes. Kept as an enum rather than a
/// string so the container, its UTI and its network-optimization default
/// are decided in exactly one exhaustive place.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Container {
    Mov,
    Mp4,
    M4a,
}

impl Container {
    fn as_str(self) -> &'static str {
        match self {
            Container::Mov => "mov",
            Container::Mp4 => "mp4",
            Container::M4a => "m4a",
        }
    }

    /// The exact `AVFileType` raw value, which is a UTI string. Swift
    /// passes this straight to `outputFileType`.
    fn file_type(self) -> &'static str {
        match self {
            Container::Mov => "com.apple.quicktime-movie",
            Container::Mp4 => "public.mpeg-4",
            Container::M4a => "com.apple.m4a-audio",
        }
    }

    /// Whether `shouldOptimizeForNetworkUse` defaults on. MP4 and M4A are
    /// the delivery containers people upload, and a leading `moov` atom
    /// lets a player start before the file is fully fetched. A ProRes MOV
    /// is an editing master handed to another application, where the
    /// rewrite pass buys nothing.
    fn optimizes_for_network(self) -> bool {
        matches!(self, Container::Mp4 | Container::M4a)
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
    /// The `AVAssetExportSession` preset name, verbatim.
    avf_preset: &'static str,
}

/// The §7.8 set. M1 maps these onto `AVAssetExportSession`'s named presets,
/// which is why each row carries one: the session's preset decides the
/// codec and the bitrate ladder, and the size below is what the video
/// composition renders at.
const PRESETS: [Preset; 7] = [
    Preset {
        id: "h264_1080p",
        name: "H.264 1080p",
        container: Container::Mp4,
        codec: "h264",
        video: true,
        size: Some((1920, 1080)),
        avf_preset: "AVAssetExportPreset1920x1080",
    },
    Preset {
        id: "h264_720p",
        name: "H.264 720p",
        container: Container::Mp4,
        codec: "h264",
        video: true,
        size: Some((1280, 720)),
        avf_preset: "AVAssetExportPreset1280x720",
    },
    Preset {
        id: "h264_source",
        name: "H.264 source size",
        container: Container::Mp4,
        codec: "h264",
        video: true,
        size: None,
        avf_preset: "AVAssetExportPresetHighestQuality",
    },
    Preset {
        id: "hevc_1080p",
        name: "HEVC 1080p",
        container: Container::Mp4,
        codec: "hevc",
        video: true,
        size: Some((1920, 1080)),
        avf_preset: "AVAssetExportPresetHEVC1920x1080",
    },
    Preset {
        id: "hevc_4k",
        name: "HEVC 4K",
        container: Container::Mp4,
        codec: "hevc",
        video: true,
        size: Some((3840, 2160)),
        avf_preset: "AVAssetExportPresetHEVC3840x2160",
    },
    Preset {
        id: "prores_422",
        name: "ProRes 422 (MOV)",
        container: Container::Mov,
        codec: "prores422",
        video: true,
        size: None,
        avf_preset: "AVAssetExportPresetAppleProRes422LPCM",
    },
    Preset {
        id: "audio_m4a",
        name: "Audio only (M4A)",
        container: Container::M4a,
        codec: "aac",
        video: false,
        size: None,
        avf_preset: "AVAssetExportPresetAppleM4A",
    },
];

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
        out.insert("avf_preset".to_string(), Value::from(self.avf_preset));
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
    /// (`{"start", "duration"}` in ticks) and `optimize_for_network`;
    /// anything else in the object is ignored, so a newer UI can send
    /// fields this build does not know.
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

        let fps = match field(overrides, "fps") {
            None => self.canvas.fps,
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
        out.insert("avf_preset".to_string(), Value::from(preset.avf_preset));
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
        out.insert(
            "fps".to_string(),
            Value::Array(vec![Value::from(fps.num), Value::from(fps.den)]),
        );
        out.insert("range".to_string(), Value::Object(range));
        // Audio is always offered: a project with no audio simply produces
        // no audio track, which is cheaper than deciding here.
        out.insert("audio".to_string(), Value::from(true));
        out.insert("video".to_string(), Value::from(preset.video));
        out.insert("optimize_for_network".to_string(), Value::from(optimize));
        Ok(Value::Object(out))
    }
}
