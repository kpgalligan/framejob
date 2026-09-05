//! Snapping: the ticks a timeline drag sticks to, and the resolution of a
//! dragged time against them (spec §4.4, §7.1).
//!
//! The split is deliberate. [`Project::snap_candidates`] is asked ONCE when
//! a drag begins — it walks every clip and marker — and [`resolve`] runs on
//! every mouse-moved event against that fixed array. Recomputing candidates
//! per event would be quadratic in a long timeline, and worse, the set
//! would change under the user's hand as the dragged clip moved.
//!
//! The candidate array is flat and sorted so `rc_snap_resolve` can take the
//! `"ticks"` array straight from the JSON with no reshaping, and so
//! [`resolve`] can binary-search it.

use serde_json::{Map, Value};

use crate::model::Project;
use crate::time::Ticks;

impl Project {
    /// Everything a drag should stick to: 0, the end of the timeline, every
    /// marker, and the start and end of every clip except the ones in
    /// `exclude` (the clips being dragged — a clip must not snap to
    /// itself).
    ///
    /// Returns `{"ticks": [sorted unique ticks], "labels": {"<tick>": "…"}}`.
    /// `labels` is what the timeline shows in the snap indicator; when
    /// several things land on one tick the FIRST to claim it wins, and the
    /// insertion order below is that priority: the timeline bounds, then
    /// markers (a user placed them deliberately), then clip edges.
    ///
    /// The playhead and the in/out points are NOT here: they are view
    /// state, live in Swift, and Swift appends them to the array before
    /// calling [`resolve`].
    pub fn snap_candidates(&self, exclude: &[u32]) -> Value {
        let mut ticks: Vec<Ticks> = Vec::new();
        let mut labels: Map<String, Value> = Map::new();

        let mut add = |tick: Ticks, label: String, ticks: &mut Vec<Ticks>| {
            ticks.push(tick);
            labels
                .entry(tick.to_string())
                .or_insert(Value::String(label));
        };

        add(0, "start".to_string(), &mut ticks);
        add(self.duration(), "end".to_string(), &mut ticks);

        for marker in &self.markers {
            let label = if marker.name.is_empty() {
                "marker".to_string()
            } else {
                format!("marker: {}", marker.name)
            };
            add(marker.time, label, &mut ticks);
        }

        for clip in &self.clips {
            if exclude.contains(&clip.id) {
                continue;
            }
            add(clip.start, format!("clip {} start", clip.id), &mut ticks);
            add(
                clip.start.saturating_add(clip.duration),
                format!("clip {} end", clip.id),
                &mut ticks,
            );
        }

        ticks.sort_unstable();
        ticks.dedup();

        let mut out = Map::new();
        out.insert(
            "ticks".to_string(),
            Value::Array(ticks.into_iter().map(Value::from).collect()),
        );
        out.insert("labels".to_string(), Value::Object(labels));
        Value::Object(out)
    }
}

/// The nearest candidate to `t` within `threshold` ticks, and whether one
/// was taken. Ties go to the SMALLER tick, so a drag between two equally
/// close edges lands somewhere predictable rather than flickering.
///
/// `candidates` must be sorted ascending — [`Project::snap_candidates`]
/// produces it that way, and the search is a binary one because a
/// half-hour timeline has thousands of edges and this runs on every
/// mouse-moved event. An unsorted array still returns safely; it just
/// returns an arbitrary one of the candidates or none.
///
/// A negative `threshold` snaps to nothing, which is how the ⌘ modifier
/// (suppress snapping) is expressed without a second code path.
pub fn resolve(candidates: &[Ticks], t: Ticks, threshold: Ticks) -> (Ticks, bool) {
    if candidates.is_empty() || threshold < 0 {
        return (t, false);
    }
    let index = match candidates.binary_search(&t) {
        // Exactly on a candidate: distance 0, always within the threshold.
        Ok(_) => return (t, true),
        Err(index) => index,
    };

    // The insertion point straddles `t`: everything before it is below,
    // everything from it up is above. Distances go through i128 because
    // `t` and a candidate can be far enough apart to overflow i64.
    let below = index
        .checked_sub(1)
        .and_then(|i| candidates.get(i))
        .copied();
    let above = candidates.get(index).copied();
    let nearest = match (below, above) {
        (Some(b), Some(a)) => {
            let distance_below = i128::from(t) - i128::from(b);
            let distance_above = i128::from(a) - i128::from(t);
            if distance_below <= distance_above {
                Some((b, distance_below))
            } else {
                Some((a, distance_above))
            }
        }
        (Some(b), None) => Some((b, i128::from(t) - i128::from(b))),
        (None, Some(a)) => Some((a, i128::from(a) - i128::from(t))),
        (None, None) => None,
    };

    match nearest {
        Some((tick, distance)) if distance <= i128::from(threshold) => (tick, true),
        _ => (t, false),
    }
}
