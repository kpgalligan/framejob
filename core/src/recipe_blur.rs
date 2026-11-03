//! A recipe layer's `blur` key (format 42, spec §7.3, §11 CU-111, CU-114):
//! the placements a blurred layer is drawn at across its shutter, or `null`.
//!
//! `recipe.rs`'s `layer` asks [`Project::layer_shutter`] for the layer's
//! shutter — `None` when the evaluated `video.motion_blur` is 0 or the layer
//! is drawn sharp (CU-111's list, which `layer` computes) — and hands it to
//! [`Project::layer_blur`] for the key and to `recipe_cursor.rs` for the
//! cursor's `shutter`. Each sample is the layer's own placement
//! (`Project::placement`, so a nested layer follows its nest's fold and
//! `clip_rect`) at a sub-frame time `motion_blur.rs`'s offsets give, clamped
//! into the instance's span so no sample reads outside the clip. A layer
//! whose every sample equals the first does not move across the shutter, and
//! its key is `null`, so a still layer draws exactly as it did.
//!
//! [`sharpen_matted`] runs over the finished list after Text Behind
//! Subject's copies and cut layers are added (`recipe_subject.rs`): a layer
//! with a non-null `matte` is drawn into or cut by a group whose picture is
//! drawn once, so it is drawn sharp, its `blur` null and its cursor's
//! `shutter` removed.

use serde_json::{Map, Value};

use crate::evaluate::{json, number};
use crate::model::{Project, VideoProps};
use crate::motion_blur::shutter_offsets;
use crate::nest::{Frame, Instance};
use crate::time::Ticks;

/// A layer's shutter at one instant, in PROJECT time: its fraction of a
/// canvas frame, its [`crate::motion_blur::MOTION_BLUR_SAMPLES`] sample
/// times ascending, and its two ends, each clamped into the instance's span.
pub(crate) struct Shutter {
    pub fraction: f64,
    pub times: Vec<Ticks>,
    pub ends: (Ticks, Ticks),
}

impl Project {
    /// The layer's shutter at `t`, or `None` when `video.motion_blur` (the
    /// evaluated, clamped value) is not above 0 or the layer is `sharp`
    /// (CU-111). Times and ends are clamped into `[instance.start,
    /// instance.end − 1]`.
    pub(crate) fn layer_shutter(
        &self,
        instance: &Instance,
        t: Ticks,
        video: &VideoProps,
        sharp: bool,
    ) -> Option<Shutter> {
        let fraction = video.motion_blur;
        if sharp || fraction.is_nan() || fraction <= 0.0 {
            return None;
        }
        let (offsets, (from, to)) = shutter_offsets(self.canvas.fps, fraction);
        let last = instance.end.saturating_sub(1).max(instance.start);
        let within = |offset: Ticks| t.saturating_add(offset).clamp(instance.start, last);
        Some(Shutter {
            fraction,
            times: offsets.into_iter().map(within).collect(),
            ends: (within(from), within(to)),
        })
    }

    /// The `blur` key (CU-114): `null`, or `{"shutter": s, "samples": [{x,
    /// y, scale, rotation, clip_rect}; N]}` from the layer's placement at
    /// each sample time; `null` when every sample equals the first (f64 ==,
    /// `clip_rect` included).
    pub(crate) fn layer_blur(&self, instance: &Instance, shutter: Option<&Shutter>) -> Value {
        let Some(shutter) = shutter else {
            return Value::Null;
        };
        let placed: Vec<Frame> = shutter
            .times
            .iter()
            .map(|&time| self.placement(instance, time))
            .collect();
        let Some(first) = placed.first() else {
            return Value::Null;
        };
        if placed.iter().all(|frame| same_place(frame, first)) {
            return Value::Null;
        }
        let samples: Vec<Value> = placed.iter().map(sample).collect();
        let mut out = Map::new();
        out.insert("shutter".to_string(), number(shutter.fraction));
        out.insert("samples".to_string(), Value::Array(samples));
        Value::Object(out)
    }
}

/// Whether two placements put the layer in the same place: position, scale,
/// rotation and clip rect, exactly. Opacity is not sampled (CU-114).
fn same_place(a: &Frame, b: &Frame) -> bool {
    a.x == b.x
        && a.y == b.y
        && a.scale == b.scale
        && a.rotation == b.rotation
        && a.clip_rect == b.clip_rect
}

/// One sample as the key publishes it.
fn sample(frame: &Frame) -> Value {
    let mut out = Map::new();
    out.insert("x".to_string(), number(frame.x));
    out.insert("y".to_string(), number(frame.y));
    out.insert("scale".to_string(), number(frame.scale));
    out.insert("rotation".to_string(), number(frame.rotation));
    out.insert(
        "clip_rect".to_string(),
        match frame.clip_rect {
            Some(rect) => json(&rect),
            None => Value::Null,
        },
    );
    Value::Object(out)
}

/// Each layer with a non-null `matte` drawn sharp (CU-111): `blur` null and
/// the cursor's `shutter` removed. Run after Text Behind Subject's copies and
/// cut layers are in the list.
pub(crate) fn sharpen_matted(layers: &mut [Value]) {
    for layer in layers.iter_mut() {
        let Value::Object(fields) = layer else {
            continue;
        };
        if fields.get("matte").is_none_or(Value::is_null) {
            continue;
        }
        fields.insert("blur".to_string(), Value::Null);
        if let Some(Value::Object(cursor)) = fields.get_mut("cursor") {
            cursor.shift_remove("shutter");
        }
    }
}
