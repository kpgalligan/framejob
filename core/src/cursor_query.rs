//! `rc_cursor_query`'s vocabulary (spec §11 CU-25): one JSON request with
//! one key, read strictly (an unknown key refused through
//! `serde_path_to_error`, naming its path), answered as JSON. Ticks are
//! source ticks, positions movie px (f64), ranges half-open `[from, to)`.
//!
//! - `{"prepare":{"smoothing":s}}` → `{"prepared":{"smoothing":s,"kept":n}}`:
//!   builds and stores the smoothed path (CU-21); at 0 `kept` is the move
//!   count and nothing is stored.
//! - `{"unprepare":{"smoothing":s}}` → `{"unprepared":b}`: drops a stored
//!   path; false when none was stored, always at 0. The core never drops one
//!   on its own; `CursorTracks` owns the cap (CU-26).
//! - `{"state":{"at":T,"props":{…},"ends"?:[T0,T1]}}` → `{visible, x, y,
//!   opacity, px_per_point, image, ripples}`, and `ends` `[[x0, y0], [x1,
//!   y1]]` (the positions at T0 and T1, as `x`, `y`; CU-115) when asked.
//!   `props` takes `smoothing` (0), `hide_idle` (null or seconds), `scale`
//!   (1) and `clicks` (`"none"` or `"ripple"`) and ignores any other key,
//!   so the recipe's object may be passed whole. An unprepared smoothing
//!   answers the raw path and never builds one. `image`
//!   is `{id, w, h, hot_x, hot_y}` in px (points × `px_per_point` × `scale`),
//!   null under `cursor_image: none` or before the first image change;
//!   `ripples` (CU-23) only under `clicks: "ripple"`.
//! - `{"image":{"id":i}}` → `{id, png (base64), w, h, hot_x, hot_y (points),
//!   kind}`.
//! - `{"events":{"from":T0,"to":T1,"kinds":[…]}}` → only the asked keys of
//!   `clicks [{t, button, down, x, y, count}]`, `scrolls [{t, x, y, dx, dy}]`
//!   (dx, dy in points), `shortcuts [{t, keys, code}]` and `typing [{from,
//!   to, marks}]` (each stretch overlapping the range, `cursor_bursts.rs`).
//! - `{"path":{"from":T0,"to":T1,"step":S,"smoothing":s}}` → `{t, x, y}`,
//!   sampled at from, from + S, … < to: VR5's read. An unprepared smoothing
//!   is built for the request and not stored.
//!
//! - `{"plan_zooms":{"clips":[…], "zoom", "lead", "stay", "follow",
//!   "typing", "replace", "from"?, "to"?}}` → `{ops, visits, added,
//!   replaced, dropped, closed_at_cut, bases_set, actions}`: Auto Zoom's
//!   plan (spec §11 CU-70…CU-75, `cursor_zoom.rs`). It reads one track per
//!   clip — `tracks[i]` is the cursor track of `clips[i]` — and `project`,
//!   the scoped one inside a nest; `from` and `to` are its container ticks,
//!   `lead` and `stay` seconds.
//! - `{"plan_overlays":{"clips":[…], "duration"?, "position"?, "theme"?,
//!   "module", "schema"?, "from"?, "to"?}}` → `{ops, added, dropped, merged,
//!   track, new_track, overlays}`: Add Shortcut Overlays' plan (road map
//!   creator-jobs CU8, spec §11 CU-80…CU-84, `cursor_overlays.rs`), one track
//!   per clip and `project`, as `plan_zooms`; `duration` seconds, `from` and
//!   `to` container ticks.
//! - `{"plan_typing":{"clips":[…], "rate"?, "shortest"?, "keep_pitch"?,
//!   "from"?, "to"?}}` → `{ops, needs_speech, stretches, short, ranges, saved}`:
//!   Speed Up Typing's plan (CU9b, spec §11 CU-91, CU-92, `cursor_typing.rs`),
//!   `retime_range` ops right to left, one track per clip and `project`.
//!
//! The other six each read one track and ignore `project`, which the three
//! planners read. Each refusal is its own lowercase sentence.

use serde::Deserialize;
use serde_json::{json, Value};

use crate::cursor_file_check::encode_base64;
use crate::cursor_overlays::{plan_overlays, PlanOverlaysArgs};
use crate::cursor_query_reads::{events, path, EventsArgs, PathArgs};
use crate::cursor_track::{ticks_to_us, CursorTrack};
use crate::cursor_typing::{plan_typing, PlanTypingArgs};
use crate::cursor_zoom::{plan_zooms, PlanZoomsArgs};
use crate::model::Project;
use crate::time::Ticks;

#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
enum Request {
    Prepare(SmoothingArg),
    Unprepare(SmoothingArg),
    State(StateArgs),
    Image(ImageArgs),
    Events(EventsArgs),
    Path(PathArgs),
    PlanZooms(PlanZoomsArgs),
    PlanOverlays(PlanOverlaysArgs),
    PlanTyping(PlanTypingArgs),
}

/// The one track a read takes, or the refusal naming the request.
fn one<'t>(tracks: &[&'t CursorTrack], name: &str) -> Result<&'t CursorTrack, String> {
    match tracks {
        [track] => Ok(track),
        _ => Err(format!(
            "{name} reads one cursor track; {} were given",
            tracks.len()
        )),
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SmoothingArg {
    smoothing: f64,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct StateArgs {
    at: Ticks,
    #[serde(default)]
    props: Props,
    /// The shutter's two source ticks (spec §11 CU-115), answered as `ends`.
    #[serde(default)]
    ends: Option<[Ticks; 2]>,
}

/// A `state`'s props: unknown keys ignored, on purpose (the recipe's object).
#[derive(Deserialize)]
struct Props {
    #[serde(default)]
    smoothing: f64,
    #[serde(default)]
    hide_idle: Option<f64>,
    #[serde(default = "unit_scale")]
    scale: f64,
    #[serde(default)]
    clicks: ClickLook,
}

impl Default for Props {
    fn default() -> Props {
        Props {
            smoothing: 0.0,
            hide_idle: None,
            scale: 1.0,
            clicks: ClickLook::None,
        }
    }
}

fn unit_scale() -> f64 {
    1.0
}

#[derive(Deserialize, Default, PartialEq)]
#[serde(rename_all = "snake_case")]
enum ClickLook {
    #[default]
    None,
    Ripple,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ImageArgs {
    id: i64,
}

/// Reads `request` and answers it against `tracks`, or the refusal's
/// sentence.
pub fn query(
    tracks: &[&CursorTrack],
    project: Option<&Project>,
    request: &str,
) -> Result<String, String> {
    let de = &mut serde_json::Deserializer::from_str(request);
    let request: Request = serde_path_to_error::deserialize(de)
        .map_err(|e| format!("the cursor request at \"{}\": {}", e.path(), e.inner()))?;
    let answer = match request {
        Request::Prepare(a) => prepare(one(tracks, "prepare")?, a.smoothing)?,
        Request::Unprepare(a) => {
            let track = one(tracks, "unprepare")?;
            smoothing_in_range(a.smoothing)?;
            json!({ "unprepared": a.smoothing > 0.0 && track.unprepare(a.smoothing) })
        }
        Request::State(a) => state(one(tracks, "state")?, a)?,
        Request::Image(a) => image(one(tracks, "image")?, a.id)?,
        Request::Events(a) => events(one(tracks, "events")?, a)?,
        Request::Path(a) => path(one(tracks, "path")?, a)?,
        Request::PlanZooms(a) => {
            let project = project.ok_or("plan_zooms needs the project")?;
            plan_zooms(tracks, project, a)?
        }
        Request::PlanOverlays(a) => {
            let project = project.ok_or("plan_overlays needs the project")?;
            plan_overlays(tracks, project, a)?
        }
        Request::PlanTyping(a) => {
            let project = project.ok_or("plan_typing needs the project")?;
            plan_typing(tracks, project, a)?
        }
    };
    Ok(answer.to_string())
}

pub(crate) fn smoothing_in_range(s: f64) -> Result<(), String> {
    if s.is_finite() && (0.0..=1.0).contains(&s) {
        return Ok(());
    }
    Err(format!("smoothing is {s}; it runs 0…1"))
}

fn positive(name: &str, v: f64) -> Result<(), String> {
    if v.is_finite() && v > 0.0 {
        return Ok(());
    }
    Err(format!("{name} is {v}; it must be a finite number above 0"))
}

pub(crate) fn ordered(from: Ticks, to: Ticks) -> Result<(), String> {
    if to < from {
        return Err(format!("to ({to}) is before from ({from})"));
    }
    Ok(())
}

fn prepare(track: &CursorTrack, smoothing: f64) -> Result<Value, String> {
    smoothing_in_range(smoothing)?;
    let kept = if smoothing > 0.0 {
        track.prepare(smoothing)
    } else {
        track.file().moves.t.len()
    };
    Ok(json!({ "prepared": { "smoothing": smoothing, "kept": kept } }))
}

fn state(track: &CursorTrack, a: StateArgs) -> Result<Value, String> {
    let p = a.props;
    smoothing_in_range(p.smoothing)?;
    positive("scale", p.scale)?;
    if let Some(h) = p.hide_idle {
        positive("hide_idle", h)?;
    }
    let position = |t: Ticks| {
        let at = ticks_to_us(t);
        match track.position(at, p.smoothing) {
            Some((x, y)) => track.to_movie(at, x, y),
            None => (0.0, 0.0),
        }
    };
    let at = ticks_to_us(a.at);
    let f = track.px_per_point(at);
    let (x, y) = position(a.at);
    let opacity = track.opacity(at, p.hide_idle.map(|h| h * 1e6));
    let size = |v: i64| v as f64 / 100.0 * f * p.scale;
    let image = track.image_at(at).and_then(|id| {
        let img = track.file().images.get(id)?;
        Some(json!({
            "id": id, "w": size(img.w), "h": size(img.h),
            "hot_x": size(img.hot_x), "hot_y": size(img.hot_y),
        }))
    });
    let ripples: Vec<Value> = if p.clicks == ClickLook::Ripple {
        track
            .ripples(at)
            .iter()
            .map(|r| json!({ "x": r.x, "y": r.y, "phase": r.phase }))
            .collect()
    } else {
        Vec::new()
    };
    let mut answer = json!({
        "visible": opacity > 0.0, "x": x, "y": y, "opacity": opacity,
        "px_per_point": f, "image": image, "ripples": ripples,
    });
    if let (Some(ends), Value::Object(fields)) = (a.ends, &mut answer) {
        let [(x0, y0), (x1, y1)] = ends.map(position);
        fields.insert("ends".to_string(), json!([[x0, y0], [x1, y1]]));
    }
    Ok(answer)
}

fn image(track: &CursorTrack, id: i64) -> Result<Value, String> {
    let images = &track.file().images;
    let img = usize::try_from(id)
        .ok()
        .and_then(|i| images.get(i))
        .ok_or_else(|| {
            format!(
                "image {id} is not in this cursor file (it has {})",
                images.len()
            )
        })?;
    let pt = |v: i64| v as f64 / 100.0;
    Ok(json!({
        "id": id, "png": encode_base64(&img.png), "w": pt(img.w), "h": pt(img.h),
        "hot_x": pt(img.hot_x), "hot_y": pt(img.hot_y), "kind": img.kind,
    }))
}
