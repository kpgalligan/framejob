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
//! - `{"state":{"at":T,"props":{…}}}` → `{visible, x, y, opacity,
//!   px_per_point, image, ripples}`. `props` takes `smoothing` (0), `hide_idle`
//!   (null or seconds), `scale` (1) and `clicks` (`"none"` or `"ripple"`) and
//!   ignores any other key, so the recipe's object may be passed whole. An
//!   unprepared smoothing answers the raw path and never builds one. `image`
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
//! Every request reads one track; `project` is for the planners to come and
//! is unused by these six. Each refusal is its own lowercase sentence.

use serde::Deserialize;
use serde_json::{json, Value};

use crate::cursor_bursts::typing_stretches;
use crate::cursor_file_check::encode_base64;
use crate::cursor_smooth::SmoothPath;
use crate::cursor_track::{ticks_to_us, us_to_ticks, CursorTrack, MAX_PATH_SAMPLES, PATH_MIN_STEP};
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
}

impl Request {
    fn name(&self) -> &'static str {
        match self {
            Request::Prepare(_) => "prepare",
            Request::Unprepare(_) => "unprepare",
            Request::State(_) => "state",
            Request::Image(_) => "image",
            Request::Events(_) => "events",
            Request::Path(_) => "path",
        }
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

#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
enum EventKind {
    Clicks,
    Scrolls,
    Shortcuts,
    Typing,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct EventsArgs {
    from: Ticks,
    to: Ticks,
    kinds: Vec<EventKind>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PathArgs {
    from: Ticks,
    to: Ticks,
    step: Ticks,
    smoothing: f64,
}

/// Reads `request` and answers it against `tracks`, or the refusal's
/// sentence.
pub fn query(
    tracks: &[&CursorTrack],
    _project: Option<&Project>,
    request: &str,
) -> Result<String, String> {
    let de = &mut serde_json::Deserializer::from_str(request);
    let request: Request = serde_path_to_error::deserialize(de)
        .map_err(|e| format!("the cursor request at \"{}\": {}", e.path(), e.inner()))?;
    let [track] = tracks else {
        return Err(format!(
            "{} reads one cursor track; {} were given",
            request.name(),
            tracks.len()
        ));
    };
    let answer = match request {
        Request::Prepare(a) => prepare(track, a.smoothing)?,
        Request::Unprepare(a) => {
            smoothing_in_range(a.smoothing)?;
            json!({ "unprepared": a.smoothing > 0.0 && track.unprepare(a.smoothing) })
        }
        Request::State(a) => state(track, a)?,
        Request::Image(a) => image(track, a.id)?,
        Request::Events(a) => events(track, a)?,
        Request::Path(a) => path(track, a)?,
    };
    Ok(answer.to_string())
}

fn smoothing_in_range(s: f64) -> Result<(), String> {
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

fn ordered(from: Ticks, to: Ticks) -> Result<(), String> {
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
    let at = ticks_to_us(a.at);
    let f = track.px_per_point(at);
    let (x, y) = match track.position(at, p.smoothing) {
        Some((x, y)) => track.to_movie(at, x, y),
        None => (0.0, 0.0),
    };
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
    Ok(json!({
        "visible": opacity > 0.0, "x": x, "y": y, "opacity": opacity,
        "px_per_point": f, "image": image, "ripples": ripples,
    }))
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

fn events(track: &CursorTrack, a: EventsArgs) -> Result<Value, String> {
    ordered(a.from, a.to)?;
    let (from, to) = (ticks_to_us(a.from), ticks_to_us(a.to));
    let inside = |t: i64| from <= t as f64 && (t as f64) < to;
    let file = track.file();
    let mut out = serde_json::Map::new();
    if a.kinds.contains(&EventKind::Clicks) {
        let c = &file.clicks;
        let list: Vec<Value> = (0..c.t.len())
            .filter(|&i| inside(c.t[i]))
            .map(|i| {
                let (x, y) = track.to_movie(c.t[i] as f64, c.x[i] as f64, c.y[i] as f64);
                json!({ "t": us_to_ticks(c.t[i]), "button": c.button[i], "down": c.down[i],
                        "x": x, "y": y, "count": c.count[i] })
            })
            .collect();
        out.insert("clicks".into(), list.into());
    }
    if a.kinds.contains(&EventKind::Scrolls) {
        let s = &file.scrolls;
        let list: Vec<Value> = (0..s.t.len())
            .filter(|&i| inside(s.t[i]))
            .map(|i| {
                let (x, y) = track.to_movie(s.t[i] as f64, s.x[i] as f64, s.y[i] as f64);
                json!({ "t": us_to_ticks(s.t[i]), "x": x, "y": y,
                        "dx": s.dx[i] as f64 / 100.0, "dy": s.dy[i] as f64 / 100.0 })
            })
            .collect();
        out.insert("scrolls".into(), list.into());
    }
    if a.kinds.contains(&EventKind::Shortcuts) {
        let k = &file.keys.shortcut;
        let list: Vec<Value> = (0..k.t.len())
            .filter(|&i| inside(k.t[i]))
            .map(|i| json!({ "t": us_to_ticks(k.t[i]), "keys": k.keys[i], "code": k.code[i] }))
            .collect();
        out.insert("shortcuts".into(), list.into());
    }
    if a.kinds.contains(&EventKind::Typing) {
        let list: Vec<Value> = typing_stretches(&file.keys.typed.t)
            .into_iter()
            .filter(|&(first, last, _)| (first as f64) < to && last as f64 >= from)
            .map(|(first, last, marks)| {
                json!({ "from": us_to_ticks(first), "to": us_to_ticks(last), "marks": marks })
            })
            .collect();
        out.insert("typing".into(), list.into());
    }
    Ok(Value::Object(out))
}

fn path(track: &CursorTrack, a: PathArgs) -> Result<Value, String> {
    smoothing_in_range(a.smoothing)?;
    ordered(a.from, a.to)?;
    if a.step < PATH_MIN_STEP {
        return Err(format!(
            "path's step is {} ticks; a path is sampled at most 10 times a second (step ≥ \
             {PATH_MIN_STEP})",
            a.step
        ));
    }
    let span = i128::from(a.to) - i128::from(a.from);
    let samples = (span + i128::from(a.step) - 1) / i128::from(a.step);
    if samples > MAX_PATH_SAMPLES as i128 {
        return Err(format!(
            "path's range from {} to {} at step {} is {samples} samples; a path holds at most \
             {MAX_PATH_SAMPLES}",
            a.from, a.to, a.step
        ));
    }
    // A stored path when `prepare` made one; else one built for this
    // request alone and never stored (CU-25).
    let built = (a.smoothing > 0.0)
        .then(|| track.prepared(a.smoothing))
        .flatten()
        .or_else(|| {
            (a.smoothing > 0.0)
                .then(|| std::sync::Arc::new(SmoothPath::build(track.file(), a.smoothing)))
        });
    let n = samples as usize;
    let (mut ts, mut xs, mut ys) = (
        Vec::with_capacity(n),
        Vec::with_capacity(n),
        Vec::with_capacity(n),
    );
    for k in 0..n {
        let t = a.from + a.step * k as i64;
        let at = ticks_to_us(t);
        let p = match &built {
            Some(path) => path.at(at),
            None => track.raw_at(at),
        };
        let Some((x, y)) = p else { break };
        let (x, y) = track.to_movie(at, x, y);
        ts.push(t);
        xs.push(x);
        ys.push(y);
    }
    Ok(json!({ "t": ts, "x": xs, "y": ys }))
}
