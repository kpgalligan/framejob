//! A graphic clip's own timeline (road map 10's G-9) and the layer source
//! the recipe publishes for one (spec §7.3).
//!
//! A graphic has a timeline of its own, counted in the graphic's frames:
//! the clip's first frame shows graphic time `in`, and the graphic runs for
//! `length` ticks, or — `length` null — until the clip ends, which is
//! graphic time `in + duration` (decision G-9·c). The module is asked for
//! one frame of that timeline, with a `ctx` saying where the frame falls in
//! the whole, and returns SVG; the app rasterizes it and caches the texture
//! by the `hash` published here.
//!
//! The arithmetic lives here, in ONE place, because it has writers and a
//! reader that must agree on it: `trim_start`, `roll`, `split`'s second
//! half and `add_transition`'s head move `in` through [`graphic_advanced`],
//! `split` pins both halves' `length` to [`effective_length`], every
//! re-snap through `frame_grid.rs` puts `in` and `length` on the new grid
//! through [`graphic_resnapped`] (G-18), and the recipe reads the same
//! [`effective_length`] for `durationInFrames`. An edit module importing a
//! read-side one has precedent (`edit_split.rs` reads `actions` and
//! `source_window`); the two natural homes, `model_graphic.rs` and
//! `source_window.rs`, stand at their caps.
//!
//! The `ctx` keys are exactly the engine's (road map 10 §5c) and the app
//! passes the object through verbatim, so a key renamed here is a key the
//! module never sees. The core never names the engine's crate (G-2), so the
//! shape is restated, and `core/tests/graphic.rs` holds it to a fixture.

use serde_json::{Map, Value};

use crate::actions::Evaluated;
use crate::evaluate::number;
use crate::model::{Canvas, Clip, GraphicProps, Project};
use crate::recipe::{content_hash, missing_source};
use crate::source_window::in_advanced;
use crate::time::{frame_index, snap_down_to_frame, snap_up_to_frame, Ticks};

/// How long a graphic clip's own timeline is, in ticks, or `None` for a
/// clip that describes no graphic.
///
/// `length` when it is set; null means "it ends with the clip" (G-9), and
/// the clip ends at graphic time `in + duration` — not at `duration`, which
/// would make a front trim shorten the graphic's timeline and finish its
/// outro early while the clip still showed it (decision G-9·c). Under this
/// rule a front trim and a roll leave `durationInFrames` where it was.
pub(crate) fn effective_length(clip: &Clip) -> Option<Ticks> {
    clip.graphic.as_ref().map(|graphic| {
        graphic
            .length
            .unwrap_or(graphic.r#in.saturating_add(clip.duration))
    })
}

/// `graphic` with its `in` advanced by `timeline` ticks, or `None` when
/// there is no graphic to move.
///
/// Through `source_window.rs`'s one mover at speed 1 (a graphic has no
/// speed), so `in` never goes below 0: a start dragged earlier than the
/// graphic's own first frame saturates there (decision G-9·a). Its four
/// callers are the front-trim writers: `trim_start`, `roll`, `split`'s
/// second half, and `add_transition`'s handle form, which moves `in` BACK
/// by the head it adds (G-18·a).
pub(crate) fn graphic_advanced(
    graphic: Option<&GraphicProps>,
    timeline: Ticks,
) -> Option<GraphicProps> {
    graphic.map(|graphic| {
        let mut moved = graphic.clone();
        moved.r#in = in_advanced(graphic.r#in, timeline, 1.0);
        moved
    })
}

/// `graphic` on `project`'s frame grid, or `None` when there is no graphic
/// — what every re-snap through `frame_grid.rs` writes (G-18·b). `in` is
/// the canvas's frames, not a source position, so it snaps to the nearest
/// frame, never below 0; a set `length` snaps with `set_graphic`'s
/// one-frame floor, and a null one stays null.
pub(crate) fn graphic_resnapped(
    graphic: Option<&GraphicProps>,
    project: &Project,
) -> Option<GraphicProps> {
    graphic.map(|graphic| {
        let mut snapped = graphic.clone();
        snapped.r#in = project.snapped(graphic.r#in).max(0);
        snapped.length = graphic
            .length
            .map(|length| project.snapped(length).max(project.frame()));
        snapped
    })
}

/// A graphic layer's `source` and `source_size` at `clip_t` ticks into the
/// clip, on `canvas` — the PROJECT's canvas, inside a nest too (§5c).
///
/// The frame is FLOORED onto the grid (a tick inside a frame shows that
/// frame) and `durationInFrames` is CEILED (a partial last frame still
/// draws); `progress` runs 0 to 1 over the graphic's frames and clamps, so
/// a clip held past its graphic's `length` shows the last state. Every
/// float passes through `number`, so a degenerate rate publishes 0 and
/// never a non-finite value.
///
/// The `hash` covers everything the module is called with — the name, the
/// frame, the whole `ctx` and the props (decision G-9·b): a `trim_end`
/// changes `durationInFrames` and so the outro at the same frame, and a
/// rate change changes `time`, so a key over less would serve a stale
/// texture. The props are the map EVALUATED at `clip_t`
/// ([`Evaluated::graphic`], spec §11 G-34): the stored map with each
/// finished action's `graphic.props` laid over it and the spanning one's
/// interpolated, which is the stored map itself when no action names a
/// prop, so such a layer's hash is what it always was. `content_hash` sorts
/// keys, so their order does not move the hash.
pub(crate) fn graphic_source(
    clip: &Clip,
    evaluated: &Evaluated,
    clip_t: Ticks,
    canvas: &Canvas,
) -> (Value, Value) {
    let (Some(graphic), Some(effective)) = (clip.graphic.as_ref(), effective_length(clip)) else {
        return (missing_source(), Value::Null);
    };
    let fps = canvas.fps;
    let rate = fps.as_f64();
    let at = graphic.r#in.saturating_add(clip_t);
    let frame = frame_index(snap_down_to_frame(at, fps), fps).unwrap_or(0);
    let frames = frame_index(snap_up_to_frame(effective, fps), fps).unwrap_or(0);
    let progress = (frame as f64 / frames.saturating_sub(1).max(1) as f64).clamp(0.0, 1.0);

    let mut size = Map::new();
    size.insert("width".to_string(), Value::from(canvas.width));
    size.insert("height".to_string(), Value::from(canvas.height));
    let mut ctx = Map::new();
    ctx.insert("fps".to_string(), number(rate));
    ctx.insert("time".to_string(), number(frame as f64 / rate));
    ctx.insert("durationInFrames".to_string(), Value::from(frames));
    ctx.insert("progress".to_string(), number(progress));
    ctx.insert("width".to_string(), Value::from(graphic.width));
    ctx.insert("height".to_string(), Value::from(graphic.height));
    ctx.insert("canvas".to_string(), Value::Object(size));
    let ctx = Value::Object(ctx);
    let props = Value::Object(evaluated.graphic.as_ref().map_or_else(
        || graphic.props.clone(),
        |evaluated| evaluated.props.clone(),
    ));
    let ctx_json = serde_json::to_string(&ctx).unwrap_or_default();
    let props_json = serde_json::to_string(&props).unwrap_or_default();

    let mut called = Map::new();
    called.insert("name".to_string(), Value::from(graphic.name.as_str()));
    called.insert("frame".to_string(), Value::from(frame));
    called.insert("ctx".to_string(), ctx.clone());
    called.insert("props".to_string(), props.clone());
    let hash = content_hash(&Value::Object(called));

    let mut source = Map::new();
    source.insert("kind".to_string(), Value::from("graphic"));
    source.insert("name".to_string(), Value::from(graphic.name.as_str()));
    source.insert("hash".to_string(), Value::from(hash));
    source.insert("frame".to_string(), Value::from(frame));
    source.insert("ctx".to_string(), ctx);
    source.insert("props".to_string(), props);
    source.insert("props_json".to_string(), Value::String(props_json));
    source.insert("ctx_json".to_string(), Value::String(ctx_json));
    let source_size = Value::Array(vec![
        Value::from(graphic.width),
        Value::from(graphic.height),
    ]);
    (Value::Object(source), source_size)
}
