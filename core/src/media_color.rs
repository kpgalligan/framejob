//! Camera log on a media (spec §11 GR-16): `set_media_color`, the rules a
//! `media.color` obeys, and what the recipe and the plan publish of it —
//! written once for every door that meets it.
//!
//! - **The op.** `set_media_color {media, color}` sets a video media's
//!   setting, or clears it with `color: null` (an identity when there is
//!   none). `color` is read strictly ([`read_color`]): an object or `null`,
//!   only the keys `log`, `gamut`, `lut`, `peak`, `detected` and `pq`, each
//!   through serde's own vocabulary. `detected` and `pq` are import's to
//!   write, so the op refuses them; what the op stores always has `detected:
//!   false`, and an absent `gamut` is stored as the curve's first
//!   ([`LogCurve::gamuts`]). `peak` is a PQ file's override (spec §11 HD-12):
//!   `color` replaces the Camera Log and the override together, import's
//!   reading (`pq.file`, `pq.from`) survives every op, and `null` clears
//!   both, keeping the reading.
//! - **The rules** ([`Project::check_media_color`]), each its own sentence:
//!   the media is a video file, or an image whose colour is a PQ still's
//!   `pq` alone (spec §11 HD-20 (b)); the setting has `log` or `lut`, not both, or
//!   is a PQ file's `pq` alone; `gamut` goes with `log` and is one its curve
//!   takes; `lut` names a `lut` media of the project; `pq`'s peaks are within
//!   [`PEAK_MIN`]–[`PEAK_MAX`] and `from` goes with `file`. The op answers
//!   them as refusals; `add_media` (whose descriptor may carry a detected
//!   `color`) and `validate` (a file) as errors, as they answer every other
//!   field. The op's own: a `peak` only on a PQ file and in range, an image
//!   taking only a `peak` alone, and an asked `color` with none of `log`,
//!   `lut` and `peak` refused.
//! - **What draws** ([`Project::media_input`]): the recipe layer of a media
//!   or still source and the plan's video segment publish the setting as
//!   `input` — `{log, gamut}` or `{lut}`, and `peak` (the effective PQ peak)
//!   beside either or alone — and the app converts at step 0. The recipe
//!   layer of an image source publishes a PQ still's `{peak}` alone (spec
//!   §11 HD-20 (b)), and `null` for `{pq: {}}`. A `lut` that names no `lut`
//!   media publishes nothing of it.
//! - **Removing a LUT** that converts a media (`lut.rs`'s `remove_lut`) is
//!   refused naming those media ([`Project::media_converted_by`]), or with
//!   `with_clips` clears the conversions with the looks.

use serde_json::{Map, Value};

use crate::export::describe;
use crate::model::{Media, MediaColor, MediaKind, Project};
use crate::model_media_color::{PqColor, PEAK_MAX, PEAK_MIN};
use crate::outcome::Outcome;

/// The keys a `color` may carry: the setting's, `peak` (the op's alone), and
/// the two import writes, which the op refuses by name.
const COLOR_KEYS: [&str; 6] = ["log", "gamut", "lut", "peak", "detected", "pq"];

/// An asked `color`: the Camera Log as the model spells it, and `peak`.
struct Asked {
    color: MediaColor,
    peak: Option<i64>,
}

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

/// The sentence for a setting with nothing to convert by.
const NEEDS_LOG_OR_LUT: &str = "color needs log or lut; null clears it";

/// A colour is a setting on a video file; on an image only when `image_ok`
/// (a PQ still's peak alone, spec §11 HD-20 (b)), and every other kind never.
fn check_kind(media: &Media, image_ok: bool) -> Result<(), String> {
    if media.kind == MediaKind::Video || (media.kind == MediaKind::Image && image_ok) {
        return Ok(());
    }
    Err(format!(
        "media {} is {}; Camera Log is a setting on a video file",
        media.id,
        kind_phrase(media.kind)
    ))
}

/// A stored `pq` (spec §11 HD-12): `file` and `peak` within
/// [`PEAK_MIN`]–[`PEAK_MAX`], and `from` present exactly when `file` is.
fn check_pq(pq: PqColor) -> Result<(), String> {
    for (key, value) in [("file", pq.file), ("peak", pq.peak)] {
        if let Some(n) = value.filter(|n| !(PEAK_MIN..=PEAK_MAX).contains(n)) {
            return Err(format!(
                "color.pq.{key} must be {PEAK_MIN}–{PEAK_MAX} cd/m², not {n}"
            ));
        }
    }
    if pq.file.is_some() != pq.from.is_some() {
        return Err("color.pq.from goes with color.pq.file".to_string());
    }
    Ok(())
}

/// `color` read strictly: `None` for `null`, else the setting and `peak`, or
/// the `Err` naming what is wrong — not an object, an unknown key, a `peak`
/// that is not a whole number, or a value serde refuses (its own sentence,
/// naming the variants).
fn read_color(color: &Value) -> Result<Option<Asked>, String> {
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
    let peak = match fields.get("peak") {
        None => None,
        Some(value) => Some(value.as_i64().ok_or_else(|| {
            format!(
                "color.peak must be a whole number of cd/m², not {}",
                describe(value)
            )
        })?),
    };
    let mut setting = fields.clone();
    setting.remove("peak");
    serde_json::from_value(Value::Object(setting))
        .map(|color| Some(Asked { color, peak }))
        .map_err(|e| format!("color does not match the schema: {e}"))
}

impl Project {
    /// Sets or clears a video media's camera-log setting (spec §11 GR-16)
    /// and a PQ file's peak override (HD-12). `Err` for an unknown media or
    /// an unreadable `color`; a refusal, in the rule's own sentence, for
    /// `detected`, `pq`, a `peak` out of range or on a file that is not PQ,
    /// an asked `color` with none of `log`, `lut` and `peak`, or a setting
    /// [`Project::check_media_color`] refuses.
    pub(crate) fn set_media_color(&self, media: u32, color: &Value) -> Result<Outcome, String> {
        let current = self.require_media(media)?.color;
        // Import's reading, kept by every op: `pq` without the override.
        let reading = current
            .and_then(|c| c.pq)
            .map(|pq| PqColor { peak: None, ..pq });
        let stored = match read_color(color)? {
            None => reading.map(|pq| MediaColor {
                pq: Some(pq),
                ..MediaColor::default()
            }),
            Some(asked) => match self.asked_color(media, asked, reading) {
                Ok(setting) => Some(setting),
                Err(why) => return Ok(Outcome::Refused(why)),
            },
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

    /// The setting an asked `color` stores on `media` beside its `reading`,
    /// or (`Err`) the refusal in the rule's own sentence, in this order: `detected`,
    /// `pq`, a `peak` outside [`PEAK_MIN`]–[`PEAK_MAX`] or on media that is
    /// not a PQ file, the media's kind (an image passes only with a `peak`
    /// alone, spec §11 HD-20 (b)), and none of `log`, `lut` and `peak`.
    fn asked_color(
        &self,
        media: u32,
        asked: Asked,
        reading: Option<PqColor>,
    ) -> Result<MediaColor, String> {
        let given = asked.color;
        if given.detected {
            return Err("color.detected is written by import, not set".to_string());
        }
        if given.pq.is_some() {
            return Err("color.pq is read from the file at import, not set".to_string());
        }
        let peak = match asked.peak {
            None => None,
            Some(n) => match u32::try_from(n) {
                Ok(n) if (PEAK_MIN..=PEAK_MAX).contains(&n) => Some(n),
                _ => {
                    return Err(format!(
                        "color.peak must be {PEAK_MIN}–{PEAK_MAX} cd/m², not {n}"
                    ))
                }
            },
        };
        if peak.is_some() && reading.is_none() {
            return Err(format!(
                "media {media} is not a PQ file; only a PQ file takes a peak"
            ));
        }
        if let Some(row) = self.media(media) {
            let image_ok = peak.is_some()
                && given.log.is_none()
                && given.lut.is_none()
                && given.gamut.is_none();
            check_kind(row, image_ok)?;
        }
        if given.log.is_none() && given.lut.is_none() && peak.is_none() {
            return Err(NEEDS_LOG_OR_LUT.to_string());
        }
        let mut setting = given;
        if let (Some(log), None) = (setting.log, setting.gamut) {
            setting.gamut = log.gamuts().first().copied();
        }
        setting.pq = reading.map(|pq| PqColor { peak, ..pq });
        Ok(setting)
    }

    /// A media's `color` against this project; `Ok` for a media without one.
    /// Each sentence is the rule's own, in this order: the media's kind (an
    /// image passes only with an import's `pq` alone, spec §11 HD-20 (b)), a
    /// setting with neither or both of `log` and `lut` (neither is a PQ
    /// file's `pq` alone, which passes), a `gamut` without a `log`, a pairing
    /// the curve does not take, a `lut` that is not a `lut` media of the
    /// project, and `pq`'s own ([`check_pq`]).
    pub(crate) fn check_media_color(&self, media: &Media) -> Result<(), String> {
        let Some(color) = media.color else {
            return Ok(());
        };
        let image_ok = color.pq.is_some()
            && !color.detected
            && color.log.is_none()
            && color.lut.is_none()
            && color.gamut.is_none();
        check_kind(media, image_ok)?;
        match (color.log, color.lut) {
            (None, None) if color.pq.is_none() || color.detected => {
                return Err(NEEDS_LOG_OR_LUT.to_string())
            }
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
        color.pq.map_or(Ok(()), check_pq)
    }

    /// What step 0 converts `media` with, as the recipe layer's and the plan
    /// segment's `input`: `{log, gamut}` for a built-in curve (the gamut its
    /// first when the stored one is absent), `{lut}` naming a `lut` media of
    /// the project, and `peak` — a PQ file's effective peak (spec §11 HD-12)
    /// — beside either or alone; or `null` — no setting, no such media, or a
    /// `lut` that names none and no peak. A PQ file whose import read nothing
    /// publishes nothing new, so its plan and recipe are the text they were.
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
        } else if let Some(id) = color.lut {
            if self.media(id).is_some_and(|m| m.kind == MediaKind::Lut) {
                out.insert("lut".to_string(), Value::from(id));
            }
        }
        if let Some(peak) = color.pq.and_then(|pq| pq.effective()) {
            out.insert("peak".to_string(), Value::from(peak));
        }
        if out.is_empty() {
            Value::Null
        } else {
            Value::Object(out)
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
