//! `plan_overlays`, Add Shortcut Overlays' planner (road map creator-jobs
//! CU8, spec §11 CU-80…CU-84): the selected clips' recorded shortcuts read
//! into presses in container time, laid out as non-overlapping overlays by
//! CU-80's timing, and answered as ops — an optional `add_track`, then one
//! `add_graphic_clip` per overlay in time order — that the app applies as
//! ONE undo step. Nothing here edits, and nothing here names the graphic
//! engine: the module and its schema are the app's (CU-81), passed through.
//!
//! **Timing (CU-80)** is counted in frames of the container's canvas rate,
//! so every start and end is a grid frame: an overlay of a chord with n
//! keycaps lasts at least `min_frames(n)`, the frames `keyboard-keys.js`
//! needs to press its last keycap and exit.

use serde::Deserialize;
use serde_json::{json, Value};

use crate::cursor_track::{us_to_ticks, CursorTrack};
use crate::cursor_zoom_run::{clip_time, media_in};
use crate::model::{Project, Source};
use crate::time::{self, seconds_to_ticks, Ticks};

/// The track the overlays go on (CU-83).
pub(crate) const TRACK_NAME: &str = "Shortcuts";
/// A different chord may start at most this late after its press (CU-80).
const MOST_LATE: f64 = 0.5;
/// `duration`'s range, seconds.
const DURATION_RANGE: (f64, f64) = (0.5, 10.0);

fn default_duration() -> f64 {
    1.5
}

/// Where the keycaps sit, the template's `position` (the owner's answer:
/// the bottom).
#[derive(Deserialize, Default, Clone, Copy)]
#[serde(rename_all = "snake_case")]
pub(crate) enum OverlayPosition {
    #[default]
    Bottom,
    Center,
    Top,
}

impl OverlayPosition {
    fn name(self) -> &'static str {
        match self {
            OverlayPosition::Bottom => "bottom",
            OverlayPosition::Center => "center",
            OverlayPosition::Top => "top",
        }
    }
}

/// The keycaps' look, the template's `theme` (the owner's answer: dark).
#[derive(Deserialize, Default, Clone, Copy)]
#[serde(rename_all = "snake_case")]
pub(crate) enum OverlayTheme {
    #[default]
    Dark,
    Light,
}

impl OverlayTheme {
    fn name(self) -> &'static str {
        match self {
            OverlayTheme::Dark => "dark",
            OverlayTheme::Light => "light",
        }
    }
}

/// `plan_overlays`' request (CU-84); `duration` in seconds, `from` and `to`
/// container ticks, `module` the graphic module's name and `schema` its
/// compiled schema, passed through to `add_graphic_clip`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct PlanOverlaysArgs {
    #[serde(default)]
    pub clips: Vec<u32>,
    #[serde(default = "default_duration")]
    pub duration: f64,
    #[serde(default)]
    pub position: OverlayPosition,
    #[serde(default)]
    pub theme: OverlayTheme,
    pub module: String,
    #[serde(default)]
    pub schema: Option<Value>,
    #[serde(default)]
    pub from: Option<Ticks>,
    #[serde(default)]
    pub to: Option<Ticks>,
}

/// D_min(n) = 10n + 25 frames (CU-80): `keyboard-keys.js` presses its last
/// keycap at frame `pressAt + 5(n − 1)` = 10n + 9 (`pressAt` = 5n + 14) and
/// exits over the clip's last 15 frames, so the last press needs 16 frames
/// before the end.
pub(crate) fn min_frames(keycaps: usize) -> i64 {
    10 * keycaps as i64 + 25
}

/// A chord's keycap count: its non-empty trimmed `+` tokens, the template's
/// own split.
fn keycaps(keys: &str) -> usize {
    keys.split('+').filter(|t| !t.trim().is_empty()).count()
}

/// One press in container frames.
struct Press {
    frame: i64,
    keys: String,
}

/// One overlay in container frames, `[start, end)`.
struct Overlay {
    start: i64,
    end: i64,
    keys: String,
    n: usize,
    count: u32,
}

/// The overlays CU-80 makes of `presses` (in time order): the overlays,
/// the presses dropped and the presses merged.
fn lay_out(presses: &[Press], duration: i64, most_late: i64) -> (Vec<Overlay>, u32, u32) {
    let (mut out, mut dropped, mut merged): (Vec<Overlay>, u32, u32) = (Vec::new(), 0, 0);
    for p in presses {
        let n = keycaps(&p.keys);
        let length = duration.max(min_frames(n));
        let mut start = p.frame;
        if let Some(cur) = out.last_mut() {
            if p.frame < cur.end {
                if p.keys == cur.keys {
                    cur.end = cur.end.max(p.frame + duration);
                    cur.count += 1;
                    merged += 1;
                    continue;
                }
                start = p.frame.max(cur.start + min_frames(cur.n));
                if start - p.frame > most_late {
                    dropped += 1;
                    continue;
                }
                cur.end = start;
            }
        }
        out.push(Overlay {
            start,
            end: start + length,
            keys: p.keys.clone(),
            n,
            count: 1,
        });
    }
    (out, dropped, merged)
}

/// Checks every clip in CU-84's order.
fn check(project: &Project, clips: &[u32]) -> Result<(), String> {
    for (i, &id) in clips.iter().enumerate() {
        if clips[..i].contains(&id) {
            return Err(format!("clip {id} is named twice"));
        }
        let clip = project.require_clip(id)?;
        let Source::Media {
            media, reversed, ..
        } = &clip.source
        else {
            return Err(format!("clip {id} is not a media clip"));
        };
        if project
            .media(*media)
            .and_then(|m| m.cursor.as_ref())
            .is_none()
        {
            return Err(format!("clip {id}'s media {media} has no cursor file"));
        }
        if *reversed {
            return Err(format!(
                "clip {id} plays reversed; Add Shortcut Overlays places only clips that play \
                 forward"
            ));
        }
    }
    Ok(())
}

/// The track CU-83 picks for the span `[from, to)`: the id and whether it
/// is new.
fn track_for(project: &Project, clips: &[u32], span: (Ticks, Ticks)) -> (u32, bool) {
    let index_of = |track: u32| project.tracks.iter().position(|t| t.id == track);
    let front_of_clips = clips
        .iter()
        .filter_map(|&id| project.clip(id))
        .filter_map(|c| index_of(c.track))
        .max()
        .unwrap_or(0);
    let found = project
        .tracks
        .iter()
        .enumerate()
        .rev()
        .find(|(_, t)| t.name == TRACK_NAME);
    if let Some((index, track)) = found {
        let free = !project.clips.iter().any(|c| {
            c.track == track.id && c.start < span.1 && span.0 < c.start.saturating_add(c.duration)
        });
        if index > front_of_clips && !track.locked && !track.hidden && track.matte.is_none() && free
        {
            return (track.id, false);
        }
    }
    (project.next_id, true)
}

/// Answers `plan_overlays` (CU-80…CU-84) against `tracks`, one per clip.
pub(crate) fn plan_overlays(
    tracks: &[&CursorTrack],
    project: &Project,
    args: PlanOverlaysArgs,
) -> Result<Value, String> {
    let (lo, hi) = DURATION_RANGE;
    if !(args.duration.is_finite() && (lo..=hi).contains(&args.duration)) {
        return Err(format!(
            "duration is {} s; it runs {lo}–{hi}",
            args.duration
        ));
    }
    if let (Some(from), Some(to)) = (args.from, args.to) {
        if to <= from {
            return Err(format!("to ({to}) must be after from ({from})"));
        }
    }
    if args.clips.is_empty() {
        return Err("plan_overlays needs at least one clip".into());
    }
    if tracks.len() != args.clips.len() {
        return Err(format!(
            "plan_overlays reads one cursor track per clip; {} clips and {} tracks were given",
            args.clips.len(),
            tracks.len()
        ));
    }
    check(project, &args.clips)?;
    let fps = project.canvas.fps;
    let frame = project.frame();
    let index = |t: Ticks| time::frame_index(t, fps).unwrap_or(t / frame);
    let tick = |i: i64| time::tick_at_frame(i, fps).unwrap_or(i * frame);
    let window = (
        args.from.unwrap_or(Ticks::MIN),
        args.to.unwrap_or(Ticks::MAX),
    );
    let mut presses: Vec<Press> = Vec::new();
    for (i, &id) in args.clips.iter().enumerate() {
        let clip = project.require_clip(id)?;
        let Some((_, source_in)) = media_in(clip) else {
            continue;
        };
        let length = project.content_length_in_source(clip);
        let k = &tracks[i].file().keys.shortcut;
        for j in 0..k.t.len() {
            let s = us_to_ticks(k.t[j]);
            if s < source_in || s >= source_in.saturating_add(length) {
                continue;
            }
            let at = clip.start.saturating_add(clip_time(clip, s - source_in));
            if at < window.0 || at >= window.1 {
                continue;
            }
            presses.push(Press {
                frame: index(project.snapped(at)),
                keys: k.keys[j].clone(),
            });
        }
    }
    // Stable: equal frames keep the given clip order.
    presses.sort_by_key(|p| p.frame);
    let duration = index(seconds_to_ticks(args.duration));
    let most_late = index(seconds_to_ticks(MOST_LATE));
    let (overlays, dropped, merged) = lay_out(&presses, duration, most_late);
    let (Some(first), Some(last)) = (overlays.first(), overlays.last()) else {
        return Ok(json!({
            "ops": [], "added": 0, "dropped": dropped, "merged": merged,
            "track": null, "new_track": false, "overlays": [],
        }));
    };
    let span = (tick(first.start), tick(last.end));
    let (track, new_track) = track_for(project, &args.clips, span);
    let mut ops: Vec<Value> = Vec::new();
    if new_track {
        ops.push(json!({"op": "add_track", "index": project.tracks.len(), "name": TRACK_NAME}));
    }
    let mut answered: Vec<Value> = Vec::new();
    for o in &overlays {
        let at = tick(o.start);
        let length = tick(o.end) - at;
        let label = if o.count > 1 {
            format!("×{}", o.count)
        } else {
            String::new()
        };
        let mut op = json!({
            "op": "add_graphic_clip", "track": track, "at": at, "duration": length,
            "name": args.module,
            "props": {"keys": o.keys, "label": label, "position": args.position.name(),
                      "theme": args.theme.name()},
        });
        if let Some(schema) = &args.schema {
            op["schema"] = schema.clone();
        }
        ops.push(op);
        answered.push(json!({"at": at, "duration": length, "keys": o.keys, "label": label}));
    }
    Ok(json!({
        "ops": ops, "added": overlays.len(), "dropped": dropped, "merged": merged,
        "track": track, "new_track": new_track, "overlays": answered,
    }))
}
