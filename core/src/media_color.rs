//! Camera log on a media (spec §11 GR-16): `set_media_color`, the rules a
//! `media.color` obeys, and what the recipe and the plan publish of it —
//! written once for every door that meets it.
//!
//! - **The op.** `set_media_color {media, color}` sets a video media's
//!   setting, or clears it with `color: null` (an identity when there is
//!   none). `color` is read strictly ([`read_color`]): an object or `null`,
//!   only the keys `log`, `gamut`, `lut` and `detected`, each through
//!   serde's own vocabulary. `detected` is import's to write, so the op
//!   refuses it; what the op stores always has `detected: false`, and an
//!   absent `gamut` is stored as the curve's first ([`LogCurve::gamuts`]).
//! - **The rules** ([`Project::check_media_color`]), each its own sentence:
//!   the media is a video file; the setting has `log` or `lut`, not both;
//!   `gamut` goes with `log` and is one its curve takes; `lut` names a
//!   `lut` media of the project. The op answers them as refusals; `add_media`
//!   (whose descriptor may carry a detected `color`) and `validate` (a file)
//!   as errors, as they answer every other field.
//! - **What draws** ([`Project::media_input`]): the recipe layer of a media
//!   or still source and the plan's video segment publish the setting as
//!   `input` — `{log, gamut}` or `{lut}` — and the app converts at step 0.
//!   A `lut` that names no `lut` media publishes nothing.
//! - **Removing a LUT** that converts a media (`lut.rs`'s `remove_lut`) is
//!   refused naming those media ([`Project::media_converted_by`]), or with
//!   `with_clips` clears the conversions with the looks.

use serde_json::{Map, Value};

use crate::export::describe;
use crate::model::{Media, MediaColor, MediaKind, Project};
use crate::outcome::Outcome;

/// The keys a `color` may carry.
const COLOR_KEYS: [&str; 4] = ["log", "gamut", "lut", "detected"];

/// A media kind as a sentence names it: "an audio file", "an image", "a LUT".
fn kind_phrase(kind: MediaKind) -> &'static str {
    match kind {
        MediaKind::Video => "a video file",
        MediaKind::Audio => "an audio file",
        MediaKind::Image => "an image",
        MediaKind::Lut => "a LUT",
    }
}

/// A vocabulary value's JSON spelling, serde's own.
fn spelled<T: serde::Serialize>(value: T) -> String {
    serde_json::to_value(value)
        .ok()
        .and_then(|value| value.as_str().map(str::to_string))
        .unwrap_or_default()
}

/// `color` read strictly: `None` for `null`, else the setting, or the `Err`
/// naming what is wrong — not an object, an unknown key, or a value serde
/// refuses (its own sentence, naming the variants).
fn read_color(color: &Value) -> Result<Option<MediaColor>, String> {
    let fields = match color {
        Value::Null => return Ok(None),
        Value::Object(fields) => fields,
        other => {
            return Err(format!(
                "color must be a json object or null, not {}",
                describe(other)
            ))
        }
    };
    if let Some(key) = fields
        .keys()
        .find(|key| !COLOR_KEYS.contains(&key.as_str()))
    {
        return Err(format!("unknown key \"{key}\" in color"));
    }
    serde_json::from_value(color.clone())
        .map(Some)
        .map_err(|e| format!("color does not match the schema: {e}"))
}

impl Project {
    /// Sets or clears a video media's camera-log setting (spec §11 GR-16).
    /// `Err` for an unknown media or an unreadable `color`; a refusal, in the
    /// rule's own sentence, for `detected` or a setting
    /// [`Project::check_media_color`] refuses.
    pub(crate) fn set_media_color(&self, media: u32, color: &Value) -> Result<Outcome, String> {
        self.require_media(media)?;
        let asked = read_color(color)?;
        let stored = match asked {
            None => None,
            Some(given) => {
                if given.detected {
                    return Ok(Outcome::Refused(
                        "color.detected is written by import, not set".to_string(),
                    ));
                }
                let mut setting = given;
                if let (Some(log), None) = (setting.log, setting.gamut) {
                    setting.gamut = log.gamuts().first().copied();
                }
                Some(setting)
            }
        };
        let mut next = self.clone();
        let Some(row) = next.media.iter_mut().find(|m| m.id == media) else {
            return Err(format!("no media with id {media}"));
        };
        row.color = stored;
        if stored.is_some() {
            if let Err(why) = self.check_media_color(row) {
                return Ok(Outcome::Refused(why));
            }
        }
        self.finish(next)
    }

    /// A media's `color` against this project; `Ok` for a media without one.
    /// Each sentence is the rule's own, in this order: the media's kind, a
    /// setting with neither or both of `log` and `lut`, a `gamut` without a
    /// `log`, a pairing the curve does not take, and a `lut` that is not a
    /// `lut` media of the project.
    pub(crate) fn check_media_color(&self, media: &Media) -> Result<(), String> {
        let Some(color) = media.color else {
            return Ok(());
        };
        if media.kind != MediaKind::Video {
            return Err(format!(
                "media {} is {}; Camera Log is a setting on a video file",
                media.id,
                kind_phrase(media.kind)
            ));
        }
        match (color.log, color.lut) {
            (None, None) => return Err("color needs log or lut; null clears it".to_string()),
            (Some(_), Some(_)) => return Err("color takes log or lut, not both".to_string()),
            _ => {}
        }
        if let (None, Some(_)) = (color.log, color.gamut) {
            return Err("color.gamut goes with log".to_string());
        }
        if let (Some(log), Some(gamut)) = (color.log, color.gamut) {
            if !log.gamuts().contains(&gamut) {
                let takes: Vec<String> = log.gamuts().iter().map(|g| spelled(*g)).collect();
                return Err(format!(
                    "{} takes gamut {}, not {}",
                    spelled(log),
                    takes.join(" or "),
                    spelled(gamut)
                ));
            }
        }
        if let Some(id) = color.lut {
            match self.media(id) {
                None => return Err(format!("color.lut {id} is not a media of this project")),
                Some(found) if found.kind != MediaKind::Lut => {
                    let kind = spelled(found.kind);
                    let article = if kind.starts_with(['a', 'e', 'i', 'o', 'u']) {
                        "an"
                    } else {
                        "a"
                    };
                    return Err(format!(
                        "color.lut {id} is {article} {kind} media, not a lut"
                    ));
                }
                Some(_) => {}
            }
        }
        Ok(())
    }

    /// What step 0 converts `media` with, as the recipe layer's and the plan
    /// segment's `input`: `{log, gamut}` for a built-in curve (the gamut its
    /// first when the stored one is absent), `{lut}` naming a `lut` media of
    /// the project, or `null` — no setting, no such media, or a `lut` that
    /// names none.
    pub(crate) fn media_input(&self, media: u32) -> Value {
        let Some(color) = self.media(media).and_then(|m| m.color) else {
            return Value::Null;
        };
        let mut out = Map::new();
        if let Some(log) = color.log {
            let Some(gamut) = color.gamut.or_else(|| log.gamuts().first().copied()) else {
                return Value::Null;
            };
            out.insert("log".to_string(), Value::from(spelled(log)));
            out.insert("gamut".to_string(), Value::from(spelled(gamut)));
            return Value::Object(out);
        }
        match color.lut {
            Some(id) if self.media(id).is_some_and(|m| m.kind == MediaKind::Lut) => {
                out.insert("lut".to_string(), Value::from(id));
                Value::Object(out)
            }
            _ => Value::Null,
        }
    }

    /// The media whose `color.lut` is `lut`, in list order.
    pub(crate) fn media_converted_by(&self, lut: u32) -> Vec<u32> {
        self.media
            .iter()
            .filter(|m| m.color.and_then(|color| color.lut) == Some(lut))
            .map(|m| m.id)
            .collect()
    }
}
