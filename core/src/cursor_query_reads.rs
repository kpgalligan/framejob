//! `rc_cursor_query`'s two range reads, `events` and `path` (spec §11
//! CU-25), moved out of `cursor_query.rs` whole for its size (road map
//! creator-jobs CU11a's toll); `cursor_query.rs`'s module doc describes them.

use serde::Deserialize;
use serde_json::{json, Value};

use crate::cursor_bursts::typing_stretches;
use crate::cursor_query::{ordered, smoothing_in_range};
use crate::cursor_smooth::SmoothPath;
use crate::cursor_track::{ticks_to_us, us_to_ticks, CursorTrack, MAX_PATH_SAMPLES, PATH_MIN_STEP};
use crate::time::Ticks;

#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum EventKind {
    Clicks,
    Scrolls,
    Shortcuts,
    Typing,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct EventsArgs {
    from: Ticks,
    to: Ticks,
    kinds: Vec<EventKind>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct PathArgs {
    from: Ticks,
    to: Ticks,
    step: Ticks,
    smoothing: f64,
}

pub(crate) fn events(track: &CursorTrack, a: EventsArgs) -> Result<Value, String> {
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

pub(crate) fn path(track: &CursorTrack, a: PathArgs) -> Result<Value, String> {
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
