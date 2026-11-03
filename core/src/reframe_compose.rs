//! A framing composed into a clip that already moves (road map
//! "creator-jobs" VR2b1, spec §11 VR-27): `reframe.rs`'s path F written as
//! the clip's base and actions AROUND the actions it already carries, and
//! `replace`'s strip. Pure; `edit_reframe.rs`'s op decides and finishes.
//!
//! **Composition** (VR-27 (b)). P(t) is the input clip's evaluated
//! placement and F′ the scheduled path; a key `(k, dx, dy)` composes as
//! `scale′ = k·s`, `x′ = k·x + dx`, `y′ = k·y + dy`, raw. The base becomes
//! F′(0)∘P(0); an action end writes `video.{scale,x,y}` = F′(end)∘P(end)
//! when it names any of them (`null` included) or F′ changes across it.
//!
//! **Cuts first** (VR-27 (d)). A cut piece `[c − frame, c]` meeting an
//! action A naming `speed`, or ending past the clip, is CARRIED by A; any
//! other A is split at `c − frame` and `c`, each clamped into A, as
//! `edit_split.rs` narrows a straddled action (`state_patch`, `narrow_to`):
//! the head keeps A's id and curve, the cut piece is `linear`, the tail
//! keeps A's end and curve. So a linear A plays unchanged on every key,
//! volume included; an eased one is re-eased on each side (counted).
//!
//! **Then the moves** (VR-27 (c)), against the pieces: a move in no busy
//! span is its own action; one that overlaps a span is shifted earlier to
//! end at its start, by at most [`SHIFT_MAX`] and never before the
//! previous key or span; otherwise the first span's action CARRIES it — F′
//! holds to A's start and reaches the move's value at A's end along A's
//! curve, later moves inside A chaining into it.
//!
//! **Ids** (VR-27 (e)) are minted in time order for every new action and
//! tail; a clip's actions are written in start order. With no actions this
//! is VR2a2's writing to the byte: key 0 the base, one action per change.

use std::collections::BTreeSet;

use serde_json::{Map, Value};

use crate::edit_split::{narrow_to, state_patch};
use crate::edit_zoom::{zoom_offset, zoom_scale, ZoomFit, ZoomRegion};
use crate::model::{Action, Curve, Project, VideoProps};
use crate::reframe::{FramingKey, FramingPath};
use crate::time::{Ticks, TIMESCALE};

/// The furthest a move is shifted earlier to clear an action: 0.5 s.
pub const SHIFT_MAX: Ticks = TIMESCALE / 2;

/// What composing did that a person may want told (VR-27 (f)).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Composed {
    /// Non-linear actions split at a cut.
    pub re_eased: usize,
    /// Actions across which F′ changes from a carried move or cut.
    pub carried: usize,
}

const PLACEMENT: [&str; 3] = ["scale", "x", "y"];

type Value3 = (f64, f64, f64);

fn names_placement(end: &Value) -> bool {
    end.get("video")
        .and_then(Value::as_object)
        .is_some_and(|v| PLACEMENT.iter().any(|k| v.contains_key(*k)))
}

/// F′ as keys, read exactly at a key and eased between (`FramingPath::at`).
fn at(keys: &[FramingKey], t: Ticks) -> Value3 {
    if let Some(k) = keys.iter().find(|k| k.t == t) {
        return (k.scale, k.x, k.y);
    }
    FramingPath {
        keys: keys.to_vec(),
        shows_fit: false,
        cuts: Vec::new(),
    }
    .at(t)
}

/// One action of the written list: an existing one (or a piece of one), or
/// a new one, and whether its id is still to mint.
struct Piece {
    action: Action,
    fresh: bool,
    /// A speed action or one past the clip's end: never split (VR-27 (d)).
    whole: bool,
}

impl Piece {
    /// A new action of F′'s own, its end written by (b).
    fn new(start: Ticks, duration: Ticks, curve: Curve) -> Piece {
        let end = Value::Object(Map::new());
        let action = Action {
            id: 0,
            start,
            duration,
            curve,
            end,
        };
        Piece {
            action,
            fresh: true,
            whole: false,
        }
    }

    fn end(&self) -> Ticks {
        self.action.start.saturating_add(self.action.duration)
    }

    /// A busy span meeting `[from, to]` (VR-27 (c)).
    fn meets(&self, from: Ticks, to: Ticks) -> bool {
        self.action.duration > 0 && self.action.start < to && self.end() > from
    }
}

/// F′ being written, and which piece it is carrying through.
struct Schedule {
    keys: Vec<FramingKey>,
    carrier: Option<usize>,
    carriers: BTreeSet<usize>,
}

impl Schedule {
    fn push(&mut self, t: Ticks, v: Value3, curve: Curve) {
        let key = FramingKey {
            t,
            scale: v.0,
            x: v.1,
            y: v.2,
            curve,
        };
        match self.keys.last_mut() {
            Some(last) if last.t >= t => *last = key,
            _ => self.keys.push(key),
        }
    }

    fn value(&self) -> Value3 {
        let k = self.keys.last().expect("key 0");
        (k.scale, k.x, k.y)
    }

    /// A segment of F (`from` → `to`, reaching `v`) as its own motion.
    fn own(&mut self, from: Ticks, to: Ticks, v: Value3, curve: Curve) {
        let hold = self.value();
        if from > self.keys.last().expect("key 0").t {
            self.push(from, hold, Curve::Linear);
        }
        self.push(to, v, curve);
        self.carrier = None;
    }

    /// A segment carried by piece `i` (VR-27 (c)): hold to its start, reach
    /// `v` at its end along its curve; a later one inside it chains.
    fn carry(&mut self, i: usize, piece: &Piece, v: Value3) {
        if self.carrier != Some(i) {
            let hold = self.value();
            if piece.action.start > self.keys.last().expect("key 0").t {
                self.push(piece.action.start, hold, Curve::Linear);
            }
        }
        self.push(piece.end(), v, piece.action.curve);
        self.carrier = Some(i);
        self.carriers.insert(i);
    }
}

fn compose(f: Value3, p: Value3) -> Value3 {
    (f.0 * p.0, f.0 * p.1 + f.1, f.0 * p.2 + f.2)
}

/// `end`'s `video.{scale,x,y}` set to `v`, keeping every other key.
fn write_placement(end: &mut Value, v: Value3) {
    if !end.is_object() {
        *end = Value::Object(Map::new());
    }
    let Value::Object(end) = end else { return };
    let video = end
        .entry("video")
        .or_insert_with(|| Value::Object(Map::new()));
    if !video.is_object() {
        *video = Value::Object(Map::new());
    }
    if let Value::Object(video) = video {
        for (key, n) in PLACEMENT.iter().zip([v.0, v.1, v.2]) {
            video.insert((*key).to_string(), Value::from(n));
        }
    }
}

impl Project {
    /// VR-27 (g): `clip` with `x`, `y` and `scale` removed from every end's
    /// `video` (a group left empty dropped, then an end left `{}`), and its
    /// base at the Fit placement of the cropped picture on the canvas.
    pub fn replaced(&self, clip: u32) -> Project {
        let mut next = self.clone();
        let Some(index) = next.clips.iter().position(|c| c.id == clip) else {
            return next;
        };
        let size = next.source_size(&next.clips[index]);
        let canvas = (f64::from(next.canvas.width), f64::from(next.canvas.height));
        let target = &mut next.clips[index];
        target.actions.retain_mut(|a| {
            let Value::Object(end) = &mut a.end else {
                return true;
            };
            if let Some(Value::Object(video)) = end.get_mut("video") {
                for key in PLACEMENT {
                    video.shift_remove(key);
                }
                if video.is_empty() {
                    end.shift_remove("video");
                }
            }
            !end.is_empty()
        });
        if let Some((mw, mh)) = size {
            let mut video = target.video.clone().unwrap_or_default();
            let crop = video.crop;
            let whole = ZoomRegion {
                x: 0.0,
                y: 0.0,
                width: mw - crop.l - crop.r,
                height: mh - crop.t - crop.b,
            };
            let scale = zoom_scale(canvas, &whole, ZoomFit::Fit, 0.0);
            let (x, y) = zoom_offset(&video, &whole, scale);
            (video.scale, video.x, video.y) = (scale, x, y);
            target.video = Some(video);
        }
        next
    }

    /// `clip` with `path` composed into its base and actions (the module
    /// doc), and what composing counted.
    pub fn composed(&self, clip: u32, path: &FramingPath) -> (Project, Composed) {
        let mut next = self.clone();
        let (Some(index), Some(first)) = (
            next.clips.iter().position(|c| c.id == clip),
            path.keys.first(),
        ) else {
            return (next, Composed::default());
        };
        let original = self.clips[index].clone();
        let base = original.video.clone().unwrap_or_default();
        let placement = |t: Ticks| -> Value3 {
            let v = if original.actions.is_empty() {
                base.clone()
            } else {
                self.evaluate_clip(&original, t).video
            };
            (v.scale, v.x, v.y)
        };
        let mut pieces: Vec<Piece> = original
            .actions
            .iter()
            .map(|a| Piece {
                whole: a.end.get("speed").is_some()
                    || a.start.saturating_add(a.duration) > original.duration,
                action: a.clone(),
                fresh: false,
            })
            .collect();
        pieces.sort_by_key(|p| (p.action.start, p.action.id));

        // F's segments: (from, to, value, curve, is a cut).
        let segments: Vec<(Ticks, Ticks, Value3, Curve, bool)> = path
            .keys
            .windows(2)
            .filter(|w| (w[0].scale, w[0].x, w[0].y) != (w[1].scale, w[1].x, w[1].y))
            .map(|w| {
                let (a, b) = (&w[0], &w[1]);
                (
                    a.t,
                    b.t,
                    (b.scale, b.x, b.y),
                    b.curve,
                    path.cuts.contains(&b.t),
                )
            })
            .collect();

        // (d): every cut splits the action it lands in, first.
        let mut re_eased: BTreeSet<u32> = BTreeSet::new();
        for &(from, to, _, _, cut) in &segments {
            if !cut {
                continue;
            }
            let Some(i) = pieces.iter().position(|p| p.meets(from, to)) else {
                continue;
            };
            if pieces[i].whole {
                continue;
            }
            let a = pieces.remove(i);
            if a.action.curve != Curve::Linear {
                re_eased.insert(a.action.id);
            }
            let end_at = |t: Ticks| {
                narrow_to(
                    &state_patch(&self.evaluate_clip(&original, t)),
                    &a.action.end,
                    0,
                )
            };
            let (cf, ct) = (from.max(a.action.start), to.min(a.end()));
            let mut split = vec![
                (a.action.start, cf, a.action.curve, end_at(cf)),
                (cf, ct, Curve::Linear, end_at(ct)),
                (ct, a.end(), a.action.curve, a.action.end.clone()),
            ];
            split.retain(|&(s, e, _, _)| e > s);
            for (n, (start, end, curve, patch)) in split.into_iter().enumerate() {
                // The first written piece keeps A's id (the head, unless
                // A starts at the cut piece).
                let keeps = n == 0 && !a.fresh;
                pieces.push(Piece {
                    action: Action {
                        id: a.action.id,
                        start,
                        duration: end - start,
                        curve,
                        end: patch,
                    },
                    fresh: !keeps,
                    whole: false,
                });
            }
            pieces.sort_by_key(|p| (p.action.start, p.action.id));
        }

        // (c): F′ in time order against the pieces.
        let mut f = Schedule {
            keys: vec![*first],
            carrier: None,
            carriers: BTreeSet::new(),
        };
        let mut own: Vec<Piece> = Vec::new();
        for &(from, to, v, curve, cut) in &segments {
            let Some(i) = pieces.iter().position(|p| p.meets(from, to)) else {
                f.own(from, to, v, curve);
                own.push(Piece::new(from, to - from, curve));
                continue;
            };
            let span = &pieces[i];
            let start = span.action.start;
            // A split cut piece (clamped into its action) is its own segment.
            if cut && !span.whole && start >= from && span.end() <= to {
                f.own(start, span.end(), v, curve);
                continue;
            }
            let shifted = start - (to - from);
            let previous = pieces
                .iter()
                .map(Piece::end)
                .filter(|&e| e <= start)
                .max()
                .unwrap_or(0)
                .max(f.keys.last().expect("key 0").t);
            if !cut && f.carrier != Some(i) && to - start <= SHIFT_MAX && shifted >= previous {
                f.own(shifted, start, v, curve);
                own.push(Piece::new(shifted, to - from, curve));
                continue;
            }
            f.carry(i, &pieces[i], v);
        }

        // (b): the base and every end.
        let keys = f.keys;
        let mut carried = 0;
        for (i, piece) in pieces.iter_mut().enumerate() {
            let (s, e) = (piece.action.start, piece.end());
            let changes = at(&keys, s) != at(&keys, e);
            if changes && f.carriers.contains(&i) {
                carried += 1;
            }
            if changes || names_placement(&piece.action.end) {
                write_placement(&mut piece.action.end, compose(at(&keys, e), placement(e)));
            }
        }
        for piece in &mut own {
            let e = piece.end();
            write_placement(&mut piece.action.end, compose(at(&keys, e), placement(e)));
        }
        pieces.extend(own);
        // (e): fresh ids in time order, then the list in start order.
        pieces.sort_by_key(|p| p.action.start);
        for piece in pieces.iter_mut().filter(|p| p.fresh) {
            piece.action.id = next.allocate_id();
        }
        let (scale, x, y) = compose(at(&keys, 0), (base.scale, base.x, base.y));
        let target = &mut next.clips[index];
        target.video = Some(VideoProps {
            scale,
            x,
            y,
            ..base
        });
        target.actions = pieces.into_iter().map(|p| p.action).collect();
        let re_eased = re_eased.len();
        (next, Composed { re_eased, carried })
    }
}
