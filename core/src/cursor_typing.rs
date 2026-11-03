//! `plan_typing`, Speed Up Typing's planner (road map creator-jobs CU9b,
//! spec §11 CU-91, CU-92): the selected clips' typing stretches in container
//! time, less every span of speech under them and every shortcut's overlay,
//! united across the clips, kept when they last `shortest`, trimmed by a
//! 0.3 s margin at ×1 at each end, and answered as `retime_range` ops (CU-90)
//! right to left, so no op moves the range of one still to come. The ops are
//! tried on a clone first: the plan is applied whole or refused whole.
//! Nothing here edits the project it is given.

use std::collections::BTreeSet;

use serde::Deserialize;
use serde_json::{json, Value};

use crate::audio_duck_speech::speech_in_clip;
use crate::cursor_bursts::typing_stretches;
use crate::cursor_overlays::{DEFAULT_DURATION, MOST_LATE, TRACK_NAME};
use crate::cursor_track::{us_to_ticks, CursorTrack};
use crate::cursor_zoom_run::{clip_time, end, media_in};
use crate::model::{Clip, Project, Source};
use crate::outcome::Outcome;
use crate::time::{seconds_to_ticks, Ticks};

/// Seconds kept at ×1 at each end of a sped stretch (CU-92).
pub(crate) const MARGIN: f64 = 0.3;
/// `rate`'s range (CU-92).
pub(crate) const RATE_RANGE: (f64, f64) = (2.0, 8.0);
/// `shortest`'s range, seconds (CU-92).
pub(crate) const SHORTEST_RANGE: (f64, f64) = (1.0, 30.0);

fn default_rate() -> f64 {
    4.0
}

fn default_shortest() -> f64 {
    3.0
}

fn default_keep_pitch() -> bool {
    true
}

/// `plan_typing`'s request (CU-92); `shortest` in seconds, `from` and `to`
/// container ticks.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct PlanTypingArgs {
    #[serde(default)]
    pub clips: Vec<u32>,
    #[serde(default = "default_rate")]
    pub rate: f64,
    #[serde(default = "default_shortest")]
    pub shortest: f64,
    #[serde(default = "default_keep_pitch")]
    pub keep_pitch: bool,
    #[serde(default)]
    pub from: Option<Ticks>,
    #[serde(default)]
    pub to: Option<Ticks>,
}

/// Checks every clip in CU-92's order.
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
                "clip {id} plays reversed; Speed Up Typing speeds only clips that play forward"
            ));
        }
    }
    Ok(())
}

/// A source tick `s` of `clip` in container time, when inside its played
/// window `[in, in + content_length_in_source)` (CU8's mapping, through S).
fn played_at(project: &Project, clip: &Clip, s: Ticks) -> Option<Ticks> {
    let (_, source_in) = media_in(clip)?;
    let length = project.content_length_in_source(clip);
    (source_in <= s && s < source_in.saturating_add(length))
        .then(|| clip.start.saturating_add(clip_time(clip, s - source_in)))
}

/// CU-91 (1): `clip`'s typing stretches, clamped to its played window, in
/// container time, inside `window`.
fn stretches_of(
    project: &Project,
    clip: &Clip,
    track: &CursorTrack,
    window: (Ticks, Ticks),
) -> Vec<(Ticks, Ticks)> {
    let Some((_, source_in)) = media_in(clip) else {
        return Vec::new();
    };
    let source_end = source_in.saturating_add(project.content_length_in_source(clip));
    let mut out = Vec::new();
    for (first, last, _) in typing_stretches(&track.file().keys.typed.t) {
        let (s0, s1) = (us_to_ticks(first).max(source_in), us_to_ticks(last));
        let s1 = s1.min(source_end);
        if s1 <= s0 {
            continue;
        }
        let at = |s: Ticks| clip.start.saturating_add(clip_time(clip, s - source_in));
        let (a, b) = (at(s0).max(window.0), at(s1).min(window.1));
        if b > a {
            out.push((a, b));
        }
    }
    out
}

/// CU-91 (2b): every recorded shortcut's overlay span for `clip`, with no
/// `[from, to)` filter on the presses.
fn overlay_spans(project: &Project, clip: &Clip, track: &CursorTrack) -> Vec<(Ticks, Ticks)> {
    let shortcuts: BTreeSet<u32> = project
        .tracks
        .iter()
        .filter(|t| t.name == TRACK_NAME)
        .map(|t| t.id)
        .collect();
    let late = seconds_to_ticks(MOST_LATE);
    let fallback = seconds_to_ticks(DEFAULT_DURATION);
    let mut out = Vec::new();
    for &t in &track.file().keys.shortcut.t {
        let Some(p) = played_at(project, clip, us_to_ticks(t)) else {
            continue;
        };
        let before = out.len();
        for c in project
            .clips
            .iter()
            .filter(|c| shortcuts.contains(&c.track))
        {
            let holds = c.start <= p && p < end(c);
            let soon = p < c.start && c.start <= p.saturating_add(late);
            if holds || soon {
                out.push((p.min(c.start), end(c)));
            }
        }
        if out.len() == before {
            out.push((p, p.saturating_add(fallback)));
        }
    }
    out
}

/// `piece` less every span of `cuts`.
fn subtract(piece: (Ticks, Ticks), cuts: &[(Ticks, Ticks)]) -> Vec<(Ticks, Ticks)> {
    let mut left = vec![piece];
    for &(c0, c1) in cuts {
        left = left
            .into_iter()
            .flat_map(|(a, b)| {
                if c1 <= a || b <= c0 {
                    return vec![(a, b)];
                }
                [(a, c0.min(b)), (c1.max(a), b)]
                    .into_iter()
                    .filter(|(x, y)| y > x)
                    .collect()
            })
            .collect();
    }
    left
}

/// Pieces sorted and merged where they overlap or touch (CU-91 (3)).
fn united(mut pieces: Vec<(Ticks, Ticks)>) -> Vec<(Ticks, Ticks)> {
    pieces.sort_unstable();
    let mut out: Vec<(Ticks, Ticks)> = Vec::with_capacity(pieces.len());
    for (a, b) in pieces {
        match out.last_mut() {
            Some(last) if a <= last.1 => last.1 = last.1.max(b),
            _ => out.push((a, b)),
        }
    }
    out
}

/// Answers `plan_typing` (CU-91, CU-92) against `tracks`, one per clip.
pub(crate) fn plan_typing(
    tracks: &[&CursorTrack],
    project: &Project,
    args: PlanTypingArgs,
) -> Result<Value, String> {
    let (lo, hi) = RATE_RANGE;
    if !(args.rate.is_finite() && (lo..=hi).contains(&args.rate)) {
        return Err(format!("rate is ×{}; it runs ×{lo}–×{hi}", args.rate));
    }
    let (lo, hi) = SHORTEST_RANGE;
    if !(args.shortest.is_finite() && (lo..=hi).contains(&args.shortest)) {
        return Err(format!(
            "shortest is {} s; it runs {lo}–{hi}",
            args.shortest
        ));
    }
    if let (Some(from), Some(to)) = (args.from, args.to) {
        if to <= from {
            return Err(format!("to ({to}) must be after from ({from})"));
        }
    }
    if args.clips.is_empty() {
        return Err("plan_typing needs at least one clip".into());
    }
    if tracks.len() != args.clips.len() {
        return Err(format!(
            "plan_typing reads one cursor track per clip; {} clips and {} tracks were given",
            args.clips.len(),
            tracks.len()
        ));
    }
    check(project, &args.clips)?;
    let window = (
        args.from.unwrap_or(Ticks::MIN),
        args.to.unwrap_or(Ticks::MAX),
    );
    let mut stretches: Vec<(Ticks, Ticks)> = Vec::new();
    let mut overlays: Vec<(Ticks, Ticks)> = Vec::new();
    for (i, &id) in args.clips.iter().enumerate() {
        let clip = project.require_clip(id)?;
        stretches.extend(stretches_of(project, clip, tracks[i], window));
        overlays.extend(overlay_spans(project, clip, tracks[i]));
    }
    // CU-91 (2a): the speech of every media clip with sound under a stretch.
    let mut speech: Vec<(Ticks, Ticks)> = Vec::new();
    let mut needs: BTreeSet<u32> = BTreeSet::new();
    for c in &project.clips {
        let Source::Media { media: id, .. } = c.source else {
            continue;
        };
        let Some(media) = project.media(id).filter(|m| m.has_audio) else {
            continue;
        };
        if !stretches.iter().any(|&(a, b)| c.start < b && a < end(c)) {
            continue;
        }
        match &media.speech {
            None => {
                needs.insert(id);
            }
            Some(spans) => speech.extend(
                speech_in_clip(c, media, spans)
                    .into_iter()
                    .map(|(a, b)| (c.start.saturating_add(a), c.start.saturating_add(b))),
            ),
        }
    }
    if !needs.is_empty() {
        return Ok(json!({
            "ops": [], "needs_speech": needs.into_iter().collect::<Vec<u32>>(),
            "stretches": 0, "short": 0, "ranges": [], "saved": 0,
        }));
    }
    let cuts: Vec<(Ticks, Ticks)> = speech.into_iter().chain(overlays).collect();
    let pieces: Vec<(Ticks, Ticks)> = stretches
        .into_iter()
        .flat_map(|s| subtract(s, &cuts))
        .collect();
    let (shortest, margin) = (seconds_to_ticks(args.shortest), seconds_to_ticks(MARGIN));
    let mut short = 0;
    let mut ranges: Vec<(Ticks, Ticks)> = Vec::new();
    for (a, b) in united(pieces) {
        let (from, to) = (project.snapped(a + margin), project.snapped(b - margin));
        if b - a < shortest || to <= from {
            short += 1;
            continue;
        }
        ranges.push((from, to));
    }
    let sped_to = |(from, to): (Ticks, Ticks)| {
        let scaled = ((to - from) as f64 / args.rate).round() as Ticks;
        project.snapped(from.saturating_add(scaled))
    };
    // All or nothing (CU-91 (5)): every op tried in order on a clone.
    let mut trial = project.clone();
    let mut ops: Vec<Value> = Vec::new();
    for &(from, to) in ranges.iter().rev() {
        let refused =
            |why: String| format!("the typing from {from} to {to} ticks cannot be sped up: {why}");
        match trial.retime_range(from, to, args.rate, Some(args.keep_pitch)) {
            Ok(Outcome::Applied(next)) => trial = next,
            Ok(Outcome::Identity) => {}
            Ok(Outcome::Refused(why)) | Err(why) => return Err(refused(why)),
        }
        ops.push(json!({
            "op": "retime_range", "from": from, "to": to, "rate": args.rate,
            "keep_pitch": args.keep_pitch,
        }));
    }
    let saved: Ticks = ranges.iter().map(|&r| r.1 - sped_to(r)).sum();
    let answered: Vec<Value> = ranges
        .iter()
        .map(|&r| json!({"from": r.0, "to": r.1, "sped_to": sped_to(r)}))
        .collect();
    Ok(json!({
        "ops": ops, "needs_speech": [], "stretches": ranges.len(), "short": short,
        "ranges": answered, "saved": saved,
    }))
}
