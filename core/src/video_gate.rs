//! Hide while silent (format 43, spec §11 CO-90…CO-93): a picture clip's
//! `video.hide_silent` gate, read from a media's saved speech spans.
//!
//! The gate is a presentation term, as `video.motion` is (R5-4): every edit,
//! `clip_state`, `get_project` and the inspector read the clip UN-gated, and
//! only two readers see it — `recipe.rs`'s `layer`, which multiplies the
//! layer's placed opacity by [`Project::hide_silent_gate`], and the plan's
//! `gates` ([`Project::gate_entries`]), the line the timeline draws.
//!
//! **Which instances of the media count** (CO-90): the containers of a layer
//! are its own (the innermost enclosing nest, or the timeline) and then each
//! enclosing one outward; an instance of the media is IN a container when
//! its `inside` clip-id path starts with that container's path. The gate
//! reads the NEAREST container in which an instance of the media covers `t`;
//! in it, every instance whose played window meets `[t − hold − fade,
//! t + pre_roll + fade]` gives its played speech, sorted, widened by
//! `pre_roll` and `hold` (`audio_duck_speech.rs`'s `widened`) and merged.
//! The window is exact: a widened span that ends before `t − fade` or starts
//! after `t + fade` reaches 0 before `t`, and merging it with a span that
//! does reach `t` changes nothing there, since the gate of a merged span is
//! the maximum of its parts'.
//!
//! **The gate** is the maximum over the merged spans of 1 inside, a straight
//! ramp to 0 over `fade` either side, floored at 0; a `fade` of 0 is a step.
//! 1 where no container has an instance covering `t`, where the media is not
//! in the project or has no saved `speech`, and on a clip with no gate.
//! Nothing here edits but the two carries: `clear_hide_silent`
//! (`remove_media`) and `remap_hide_silent` (paste and Paste Attributes).

use std::collections::HashMap;

use serde_json::{Map, Value};

use crate::audio::{coalesce, covers, Ramp, Side};
use crate::audio_duck_speech::widened;
use crate::evaluate::json;
use crate::model::{Clip, HideSilent, Project, Source};
use crate::nest::Instance;
use crate::time::Ticks;

/// The media a clip's gate follows, when it has one (paste's absorb list,
/// `keep_range`'s kept media).
pub(crate) fn hide_silent_media(clip: &Clip) -> Option<u32> {
    clip.video.as_ref()?.hide_silent.map(|gate| gate.media)
}

/// Points a pasted clip's gate at this project's media id. An id `map` does
/// not carry never stays (it could name another media here): the gate goes,
/// `remap_look_media`'s rule (spec §11 CO-92).
pub(crate) fn remap_hide_silent(clip: &mut Clip, map: &HashMap<u32, u32>) {
    let Some(video) = clip.video.as_mut() else {
        return;
    };
    let Some(gate) = video.hide_silent.as_mut() else {
        return;
    };
    match map.get(&gate.media) {
        Some(local) => gate.media = *local,
        None => video.hide_silent = None,
    }
}

/// Whether `instance` sits in the container named by `path` (the enclosing
/// nest clip ids, outermost first; empty for the timeline), at any depth.
fn in_container(instance: &Instance<'_>, path: &[u32]) -> bool {
    instance.inside.len() >= path.len()
        && instance
            .inside
            .iter()
            .zip(path)
            .all(|(enclosing, id)| enclosing.clip.id == *id)
}

/// One merged span's gate at `t` (CO-90): 1 inside, a ramp to 0 over `fade`
/// either side, floored at 0; a step at `fade` 0, `[s, e)` on the right and
/// `(s, e]` on the left.
fn span_gate(s: Ticks, e: Ticks, fade: Ticks, t: Ticks, side: Side) -> f64 {
    if fade <= 0 {
        return if covers(s, e, t, side) { 1.0 } else { 0.0 };
    }
    let off = if t < s {
        s.saturating_sub(t)
    } else if t > e {
        t.saturating_sub(e)
    } else {
        0
    };
    (1.0 - off as f64 / fade as f64).max(0.0)
}

/// The gate at `t` over merged spans: the maximum of each span's, 0 with none.
fn gate_over(spans: &[(Ticks, Ticks)], fade: Ticks, t: Ticks, side: Side) -> f64 {
    spans
        .iter()
        .map(|&(s, e)| span_gate(s, e, fade, t, side))
        .fold(0.0, f64::max)
}

impl Project {
    /// Every instance of `media` in the project, at any depth.
    fn media_instances(&self, media: u32) -> Vec<Instance<'_>> {
        self.all_instances()
            .into_iter()
            .filter(|i| matches!(i.clip.source, Source::Media { media: m, .. } if m == media))
            .collect()
    }

    /// The merged, widened speech of `members`, each instance's own spans
    /// projected at its own origin and kept to its played window; only the
    /// ones whose window meets `window` when one is given (CO-90).
    fn gate_spans(
        &self,
        members: &[&Instance<'_>],
        gate: &HideSilent,
        window: Option<(Ticks, Ticks)>,
    ) -> Vec<(Ticks, Ticks)> {
        let mut spans: Vec<(Ticks, Ticks)> = Vec::new();
        for instance in members {
            if let Some((lo, hi)) = window {
                if instance.end < lo || instance.start > hi {
                    continue;
                }
            }
            spans.extend(self.played_speech(
                instance.clip,
                instance.origin,
                (instance.start, instance.end),
            ));
        }
        spans.sort_unstable();
        widened(spans, gate.pre_roll, gate.hold)
    }

    /// The gate's settings when `clip` has one and its media has saved
    /// speech; `None` is a gate of 1 everywhere.
    fn live_gate(&self, clip: &Clip) -> Option<HideSilent> {
        let gate = clip.video.as_ref()?.hide_silent?;
        self.media(gate.media)?.speech.as_ref()?;
        Some(gate)
    }

    /// The gate at `t` for `instance` among `all`, the media's instances
    /// (CO-90): the nearest container, outward from the layer's own, in
    /// which one of them covers `t`.
    fn gate_among(
        &self,
        instance: &Instance<'_>,
        all: &[Instance<'_>],
        gate: &HideSilent,
        t: Ticks,
        side: Side,
    ) -> f64 {
        let path: Vec<u32> = instance.inside.iter().map(|e| e.clip.id).collect();
        let fade = gate.fade.max(0);
        for depth in (0..=path.len()).rev() {
            let container = path.get(..depth).unwrap_or(&[]);
            let members: Vec<&Instance<'_>> =
                all.iter().filter(|i| in_container(i, container)).collect();
            if !members.iter().any(|i| covers(i.start, i.end, t, side)) {
                continue;
            }
            let lo = t.saturating_sub(gate.hold.max(0)).saturating_sub(fade);
            let hi = t.saturating_add(gate.pre_roll.max(0)).saturating_add(fade);
            let spans = self.gate_spans(&members, gate, Some((lo, hi)));
            return gate_over(&spans, fade, t, side);
        }
        1.0
    }

    /// `instance`'s hide-while-silent gate at project time `t` (CO-90): 1
    /// for a clip with none. `side` says which limit a container's edge
    /// reads, as `audio.rs`'s envelopes do.
    pub(crate) fn hide_silent_gate(&self, instance: &Instance<'_>, t: Ticks, side: Side) -> f64 {
        let Some(gate) = self.live_gate(instance.clip) else {
            return 1.0;
        };
        let all = self.media_instances(gate.media);
        self.gate_among(instance, &all, &gate, t, side)
    }

    /// The plan's `gates` (CO-93): one `{clip, ramps}` per timeline-level
    /// instance of a gated clip whose media has speech, the ramps tiling
    /// its `[start, end)`, `coalesce`d. Empty when no clip has a gate, so
    /// the plan writes no key.
    pub(crate) fn gate_entries(&self) -> Vec<Value> {
        let mut out = Vec::new();
        for instance in self.all_instances() {
            if !instance.inside.is_empty() {
                continue;
            }
            let Some(gate) = self.live_gate(instance.clip) else {
                continue;
            };
            let all = self.media_instances(gate.media);
            let ramps = self.gate_ramps(&instance, &all, &gate);
            let mut entry = Map::new();
            entry.insert("clip".to_string(), Value::from(instance.clip.id));
            entry.insert(
                "ramps".to_string(),
                Value::Array(ramps.iter().map(json).collect()),
            );
            out.push(Value::Object(entry));
        }
        out
    }

    /// A timeline-level instance's gate as ramps over `[start, end)`: the
    /// breakpoints are the instance's ends, every instance of the media's
    /// ends, each merged span's `s − fade`, `s`, `e`, `e + fade`, and the
    /// midpoint of two spans closer than `2·fade`, where one's fall meets
    /// the next one's rise. Between two breakpoints the gate is a straight
    /// line, read on the right at the start and on the left at the end.
    fn gate_ramps(
        &self,
        instance: &Instance<'_>,
        all: &[Instance<'_>],
        gate: &HideSilent,
    ) -> Vec<Ramp> {
        let fade = gate.fade.max(0);
        let members: Vec<&Instance<'_>> = all.iter().collect();
        // Windowed as `gate_among` is, and exact by the same argument: an
        // instance ending before `start − hold − fade` or starting after
        // `end + pre_roll + fade` gives spans whose gate is 0 throughout
        // `[start, end]`, so only the instance's neighbourhood is projected.
        let lo = instance
            .start
            .saturating_sub(gate.hold.max(0))
            .saturating_sub(fade);
        let hi = instance
            .end
            .saturating_add(gate.pre_roll.max(0))
            .saturating_add(fade);
        let spans = self.gate_spans(&members, gate, Some((lo, hi)));
        let mut breaks = vec![instance.start, instance.end];
        for i in all {
            breaks.extend([i.start, i.end]);
        }
        for &(s, e) in &spans {
            breaks.extend([s.saturating_sub(fade), s, e, e.saturating_add(fade)]);
        }
        for pair in spans.windows(2) {
            if let (Some(&(_, e1)), Some(&(s2, _))) = (pair.first(), pair.get(1)) {
                if s2.saturating_sub(e1) < fade.saturating_mul(2) {
                    breaks.push(e1.saturating_add(s2.saturating_sub(e1) / 2));
                }
            }
        }
        breaks.retain(|t| *t >= instance.start && *t <= instance.end);
        breaks.sort_unstable();
        breaks.dedup();
        let ramps = breaks
            .windows(2)
            .filter_map(|pair| match (pair.first(), pair.get(1)) {
                (Some(&a), Some(&b)) if b > a => Some(Ramp {
                    start: a,
                    duration: b.saturating_sub(a),
                    from: self.gate_among(instance, all, gate, a, Side::Right),
                    to: self.gate_among(instance, all, gate, b, Side::Left),
                }),
                _ => None,
            })
            .collect();
        coalesce(ramps)
    }

    /// Every gate naming `media` cleared, on the timeline and in every nest
    /// (`remove_media`, spec §11 CO-92).
    pub(crate) fn clear_hide_silent(&mut self, media: u32) {
        let clips = self
            .clips
            .iter_mut()
            .chain(self.nests.iter_mut().flat_map(|n| n.clips.iter_mut()));
        for clip in clips {
            if let Some(video) = clip.video.as_mut() {
                if video.hide_silent.is_some_and(|gate| gate.media == media) {
                    video.hide_silent = None;
                }
            }
        }
    }
}
