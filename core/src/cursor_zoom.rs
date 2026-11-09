//! `plan_zooms`, Auto Zoom's planner (spec §11 CU-70…CU-75): the selected
//! clips' cursor files read into anchors, planned as visits by
//! `cursor_zoom_visits.rs`, moved onto clips and answered as ops — every
//! `remove_action` (Replace), then every `set_video`, then every
//! `add_zoom_action` in time order — that the app applies as ONE undo step.
//! Nothing here edits; the plan is checked against the project as it will
//! be at apply, so no op refuses there.
//!
//! **Runs (CU-74).** Clips on one track, each touching the one before, of
//! one media, forward, each continuing the other's source — the halves of a
//! split — are one run, formed over the whole track. The rest placement is
//! the run's first clip's base `scale`, `x`, `y`, and every zoom back ends
//! there. Planned actions land only on given clips and never straddle a
//! cut; a hold across a cut into a given clip sets its base to the
//! placement in force, or, when that clip was not given or has a kept
//! action meeting the hold, the cut is a barrier the visit closes at.

use serde::Deserialize;
use serde_json::{json, Value};

use crate::action_class::{is_zoom, moves};
use crate::cursor_track::CursorTrack;
use crate::cursor_zoom_run::{base, end, media_in, run_of, Run};
use crate::cursor_zoom_visits::{self as visits, Planned, Timing};
use crate::edit_action::overlapping_action;
use crate::edit_zoom::{region_size, ZoomFit, ZoomRegion};
use crate::model::{Clip, Project, Source};
use crate::time::{seconds_to_ticks, Ticks};

/// A rest placement equal to a base, each number to this.
const SAME: f64 = 1e-9;
/// A run's rest scale may sit this far under the fit before it is placed.
const PLACED_TOLERANCE: f64 = 0.001;

/// A base's `scale`, `x`, `y`.
type Placement = (f64, f64, f64);

fn default_zoom() -> f64 {
    2.0
}
fn default_lead() -> f64 {
    0.6
}
fn default_stay() -> f64 {
    2.5
}
fn yes() -> bool {
    true
}

/// `plan_zooms`' request (CU-70's defaults); `lead` and `stay` in seconds,
/// `from` and `to` container ticks.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct PlanZoomsArgs {
    #[serde(default)]
    pub clips: Vec<u32>,
    #[serde(default = "default_zoom")]
    pub zoom: f64,
    #[serde(default = "default_lead")]
    pub lead: f64,
    #[serde(default = "default_stay")]
    pub stay: f64,
    #[serde(default = "yes")]
    pub follow: bool,
    #[serde(default = "yes")]
    pub typing: bool,
    #[serde(default)]
    pub replace: bool,
    #[serde(default)]
    pub from: Option<Ticks>,
    #[serde(default)]
    pub to: Option<Ticks>,
}

fn in_range(name: &str, unit: &str, v: f64, lo: f64, hi: f64) -> Result<(), String> {
    if v.is_finite() && (lo..=hi).contains(&v) {
        return Ok(());
    }
    Err(format!("{name} is {v}{unit}; it runs {lo}–{hi}"))
}

fn placement(clip: &Clip) -> Placement {
    let v = base(clip);
    (v.scale, v.x, v.y)
}

fn same(a: Placement, b: Placement) -> bool {
    (a.0 - b.0).abs() <= SAME && (a.1 - b.1).abs() <= SAME && (a.2 - b.2).abs() <= SAME
}

/// Checks every clip in CU-75's order; answers each clip's run.
fn check<'p>(project: &'p Project, clips: &[u32]) -> Result<Vec<Vec<&'p Clip>>, String> {
    let mut runs = Vec::new();
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
        let found = project.media(*media);
        if found.and_then(|m| m.cursor.as_ref()).is_none() {
            return Err(format!("clip {id}'s media {media} has no cursor file"));
        }
        if *reversed {
            return Err(format!(
                "clip {id} plays reversed; Auto Zoom plans only clips that play forward"
            ));
        }
        let picture = clip.video.is_some() && found.is_some_and(|m| m.has_video);
        let Some((sw, sh)) = project.source_size(clip).filter(|_| picture) else {
            return Err(format!("clip {id} has no picture"));
        };
        let run = run_of(project, clip);
        let rest = run.first().map_or(1.0, |c| base(c).scale);
        if rest < project.fit_scale(sw, sh) * (1.0 - PLACED_TOLERANCE) {
            return Err(format!(
                "clip {id} is placed smaller than the canvas; a zoom would fill the canvas. \
                 Nest it (Clip ▸ Nest) and run Auto Zoom inside the nest."
            ));
        }
        runs.push(run);
    }
    Ok(runs)
}

/// Answers `plan_zooms` (CU-70…CU-75) against `tracks`, one per clip.
pub(crate) fn plan_zooms(
    tracks: &[&CursorTrack],
    project: &Project,
    args: PlanZoomsArgs,
) -> Result<Value, String> {
    in_range("zoom", "", args.zoom, 1.25, 4.0)?;
    in_range("lead", " s", args.lead, 0.2, 2.0)?;
    in_range("stay", " s", args.stay, 0.5, 10.0)?;
    if let (Some(from), Some(to)) = (args.from, args.to) {
        if to <= from {
            return Err(format!("to ({to}) must be after from ({from})"));
        }
    }
    if args.clips.is_empty() {
        return Err("plan_zooms needs at least one clip".into());
    }
    if tracks.len() != args.clips.len() {
        return Err(format!(
            "plan_zooms reads one cursor track per clip; {} clips and {} tracks were given",
            args.clips.len(),
            tracks.len()
        ));
    }
    let runs = check(project, &args.clips)?;
    let window = (
        args.from.unwrap_or(Ticks::MIN),
        args.to.unwrap_or(Ticks::MAX),
    );
    // CU-71: what Replace removes; `next` is the project as it will be at
    // apply — the removals, then the bases this plan sets.
    let mut next = project.clone();
    let mut removed: Vec<(u32, u32)> = Vec::new();
    if args.replace {
        for &id in &args.clips {
            let clip = project.require_clip(id)?;
            for a in clip.actions.iter().filter(|a| is_zoom(a)) {
                let s = clip.start.saturating_add(a.start);
                if s < window.1 && window.0 < s.saturating_add(a.duration) {
                    removed.push((id, a.id));
                }
            }
            if let Some(c) = next.clip_mut(id) {
                c.actions.retain(|a| !removed.contains(&(id, a.id)));
            }
        }
    }
    let timing = Timing {
        lead: seconds_to_ticks(args.lead),
        stay: seconds_to_ticks(args.stay),
        follow: args.follow,
        frame: project.frame(),
    };
    let mut bases: Vec<(u32, Placement)> = Vec::new();
    // Each landed span with its run's rest and zoomed scale.
    let mut landed: Vec<(u32, Planned, Placement, f64)> = Vec::new();
    let (mut visit_count, mut closed) = (0, 0);
    let mut heads: Vec<u32> = Vec::new();
    for run_clips in runs {
        let Some(&head) = run_clips.first() else {
            continue;
        };
        if heads.contains(&head.id) {
            continue;
        }
        heads.push(head.id);
        let rest = placement(head);
        let scale = rest.0 * args.zoom;
        let media = media_in(head).and_then(|(m, _)| project.media(m));
        let half = media.map_or((0.0, 0.0), |m| {
            (f64::from(m.width) / 2.0, f64::from(m.height) / 2.0)
        });
        let run = Run {
            clips: run_clips,
            given: &args.clips,
            tracks,
            next: &next,
            window,
            typing: args.typing,
            half,
        };
        let frame = run.frame(scale);
        let (anchors, bursts) = run.anchors();
        let mut barriers = run.barriers();
        let plan = loop {
            let cursor = |t: Ticks| run.cursor(t);
            let plan = visits::plan(anchors.clone(), &bursts, &barriers, timing, frame, &cursor);
            let more = run.closing_cuts(&plan.holds, &barriers);
            if more.is_empty() {
                break plan;
            }
            barriers.extend(more);
            barriers.sort_by_key(|b| b.at);
        };
        visit_count += plan.visits;
        closed += plan.closed;
        let moved: Vec<(u32, Planned)> = plan.actions.iter().filter_map(|p| run.land(*p)).collect();
        let mut run_bases: Vec<(u32, Placement)> = Vec::new();
        // CU-74: a hold across a cut into a given clip sets its base.
        for w in run.clips.windows(2) {
            if !run.is_given(w[1]) {
                continue;
            }
            let cut = end(w[0]);
            // Only the hold spanning the cut is in force there: a hold
            // closed at or before it (its Back maybe too short to plan)
            // leaves no aim behind (#447).
            let spanning = plan
                .holds
                .iter()
                .rposition(|&(lo, hi)| lo < cut && cut < hi);
            let in_force = spanning.and_then(|h| {
                moved
                    .iter()
                    .filter(|(_, p)| p.hold == h && p.to <= cut)
                    .max_by_key(|(_, p)| p.to)
                    .and_then(|(_, p)| p.aim)
            });
            if let Some(aim) = in_force {
                let target = next.require_clip(w[1].id)?;
                let region = zoom_region(&next, target, 0, aim, scale);
                let set = next.zoom_placement(target, 0, &region, ZoomFit::Fit);
                run_bases.push((w[1].id, set));
            }
        }
        // CU-71: Replace resets a later clip moved by no kept action.
        if args.replace {
            for c in run.clips.iter().skip(1).filter(|c| run.is_given(c)) {
                let kept = next.require_clip(c.id)?;
                let off = !same(placement(kept), rest);
                let set = run_bases.iter().any(|(id, _)| *id == c.id);
                if off && !set && !kept.actions.iter().any(moves) {
                    run_bases.push((c.id, rest));
                }
            }
        }
        landed.extend(moved.into_iter().map(|(id, p)| (id, p, rest, scale)));
        bases.extend(run_bases);
    }
    for &(id, set) in &bases {
        if let Some(v) = next.clip_mut(id).and_then(|c| c.video.as_mut()) {
            (v.scale, v.x, v.y) = set;
        }
    }
    landed.sort_by_key(|(_, p, _, _)| p.from);
    let mut ops: Vec<Value> = removed
        .iter()
        .map(|(c, a)| json!({"op": "remove_action", "clip": c, "action": a}))
        .collect();
    for (id, (scale, x, y)) in &bases {
        ops.push(json!({"op": "set_video", "clips": [id],
                        "patch": {"scale": scale, "x": x, "y": y}}));
    }
    let (mut added, mut dropped) = (0, 0);
    let mut actions: Vec<Value> = Vec::new();
    let mut busy: Vec<(u32, Ticks)> = Vec::new();
    for (id, p, rest, scale) in landed {
        let clip = next.require_clip(id)?;
        let mut at = next.snapped(p.from - clip.start).max(0);
        let mut duration = next.snapped(p.to - p.from);
        if let Some((_, until)) = busy.iter().find(|(c, _)| *c == id) {
            if at < *until {
                duration -= until - at;
                at = *until;
            }
        }
        duration = duration.min(clip.duration - at);
        if duration < next.frame() {
            continue;
        }
        if overlapping_action(&clip.actions, None, at, duration).is_some() {
            dropped += 1;
            continue;
        }
        busy.retain(|(c, _)| *c != id);
        busy.push((id, at + duration));
        let region = match p.aim {
            Some(aim) => json!(zoom_region(&next, clip, at, aim, scale)),
            None if same(placement(clip), rest) => Value::Null,
            None => json!(next.region_for_placement(clip, at, rest)),
        };
        ops.push(
            json!({"op": "add_zoom_action", "clip": id, "at": at, "duration": duration,
                        "region": region, "fit": "fit", "curve": "ease_in_out"}),
        );
        actions.push(json!({"clip": id, "at": at, "duration": duration, "kind": p.kind.name()}));
        added += 1;
    }
    Ok(json!({
        "ops": ops, "visits": visit_count, "added": added, "replaced": removed.len(),
        "dropped": dropped, "closed_at_cut": closed, "bases_set": bases.len(),
        "actions": actions,
    }))
}

/// The region in Q for `aim` (in P) on `clip` at clip time `at` of the
/// project as it will be at apply: `region_size` at the zoomed scale and the
/// evaluated rotation, centred on the aim less the evaluated crop's centre.
fn zoom_region(next: &Project, clip: &Clip, at: Ticks, aim: (f64, f64), scale: f64) -> ZoomRegion {
    let v = next.evaluate_clip(clip, at).video;
    let canvas = (f64::from(next.canvas.width), f64::from(next.canvas.height));
    let (width, height) = region_size(canvas, scale, v.rotation);
    ZoomRegion {
        x: aim.0 - (v.crop.l - v.crop.r) / 2.0,
        y: aim.1 - (v.crop.t - v.crop.b) / 2.0,
        width,
        height,
    }
}
