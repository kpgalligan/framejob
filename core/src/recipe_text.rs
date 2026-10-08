//! What a text layer SHOWS at one instant: [`Reveal`] — the amount, the
//! phase and the kind that `text.animation` resolves to (spec §5.2, §7.3)
//! — the [`text_hash`] that folds all three, and a word-timed page's five
//! word keys, into the layer's cache key, the [`text_source`] that
//! assembles the `source` object a text layer carries, and the one text
//! layer the core writes itself, the timecode
//! [`burn_in_layer`].
//!
//! Split out of `recipe.rs` under the size rule (core/CLAUDE.md: a module
//! at ~600 lines gives something up BEFORE it takes anything on) when road
//! map 2's phase 7 came to it owing a burn-in timecode layer and found it
//! standing at exactly 600. `model.rs` → `model_query.rs`,
//! `model_props.rs` → `model_regions.rs` and `model_props.rs` →
//! `model_text.rs` are the precedent, and so is their rule: cut along a
//! seam somebody can NAME, and re-export the piece taken out so no path
//! anywhere else changes.
//!
//! # The seam: placement, and the one layer that is not finished by it
//!
//! `recipe.rs` asks one question of every layer — where on the canvas, how
//! big, how turned, how combined with what is under it — and asks it
//! identically of a movie, an image, a shape and a text clip. Every answer
//! is a quantity the model already holds and `actions.rs` has already
//! resolved, so the file is a fold over instances and nothing in it needs
//! to know what any layer DEPICTS.
//!
//! Text is the one kind that is not finished when its placement is. The
//! model can only state an intent — these words, that font — because only
//! the platform can lay a string out; `model_text.rs` argues that seam in
//! the schema, and this is the same seam one stage downstream. An ANIMATED
//! layer is not even a fixed intent: what is showing depends on the clip
//! time, so the recipe has to compute a number no property of the clip
//! holds, decide which of two orders the renderer draws in, and then
//! guarantee both reach the texture cache as part of its KEY or a
//! per-frame picture is served a stale texture. A ramp, a plateau, a phase
//! and a hash over all three is the only arithmetic in the recipe that is
//! about a layer's CONTENT rather than its placement, and it is a hundred
//! and eighty lines of it. Taking it out leaves `recipe.rs` the fold it
//! reads as.
//!
//! # What is NOT here
//!
//! [`crate::recipe::content_hash`] and the FNV under it stay in
//! `recipe.rs` and are `pub(crate)` for this file to call: a SHAPE layer
//! hashes its description through the same function, so the hash is the
//! recipe's texture-cache primitive and not a text concern. The layer
//! object around `source` stays there too, and so does the arm that
//! decides a clip HAS a text description at all — this file is handed one,
//! which is what lets it serve a layer the core synthesizes as readily as
//! one it read off a clip.
//!
//! # Paths
//!
//! `recipe.rs` re-exports [`text_source`] with
//! `pub(crate) use crate::recipe_text::text_source`, so
//! `crate::recipe::text_source` resolves as though the cut had not
//! happened. [`burn_in_layer`] is `pub(crate)` and `recipe.rs` calls it by
//! its own path. [`ramp`] is `pub(crate)` for `recipe_words.rs`, whose
//! every division it is. Nothing else here is reachable from outside the
//! file: [`Reveal`], [`text_hash`] and [`reveal_kind`] were private to
//! `recipe.rs` before the move and are private to this file after it.

use serde_json::{Map, Value};

use crate::evaluate::{json, number};
use crate::model::{
    Backdrop, BlendMode, Canvas, TextAnimation, TextAnimationKind, TextCase, TextProps, VideoProps,
};
use crate::nest::Frame;
use crate::recipe::{content_hash, RecipeLayer};
use crate::recipe_words::Words;
use crate::time::{format_timecode, Ticks};

/// How much of a text layer is showing at one instant, and which half of
/// its animation is showing it (spec §5.2's `text.animation`, §7.3).
///
/// The core decides this and the platform only draws it, which is the whole
/// reason it is computed here: preview, `render_frame` and both export
/// writers read ONE recipe, so they cannot disagree about how far a reveal
/// has got. It is derived from an animation, a clip time and a duration and
/// from nothing else — no clip, no instance — so a layer the core
/// synthesizes rather than reads off a clip can simply not have one.
#[derive(Debug, Clone, Copy)]
struct Reveal {
    /// 0 (nothing showing) through 1 (all of it), the un-reveal folded in.
    amount: f64,
    /// `"in"` while the arrival is what is holding the amount back, `"out"`
    /// once the departure is, and `None` for a layer with no animation at
    /// all — whose amount is always 1. A TENT is the exception and
    /// [`Reveal::of`] argues it: a clip too short to complete its arrival
    /// keeps one word for its whole life.
    ///
    /// The word is not decoration: one number cannot say whether a
    /// typewriter is typing or un-typing, and a line rise falls rather than
    /// rises on the way out. `transition`'s `role` is the same idea one
    /// function away, and adding this later would be a change to a shipped
    /// recipe key rather than a new one.
    phase: Option<&'static str>,
    /// Which of the three reveals this is, or `None` for a layer with no
    /// animation.
    ///
    /// It is carried because the description no longer is: the recipe
    /// strips `animation` out of the text it hands over (see
    /// [`text_source`]), so this is the renderer's ONLY word for which
    /// drawing routine to run — each kind is a different routine, not a
    /// parameter of a shared one. Carried by NAME, as the schema spells
    /// it, so the recipe never depends on the enum's declaration order.
    kind: Option<TextAnimationKind>,
}

impl Reveal {
    /// A layer with no animation: all of it, all of the time.
    const WHOLE: Reveal = Reveal {
        amount: 1.0,
        phase: None,
        kind: None,
    };

    /// The reveal `clip_t` ticks into a clip that is `duration` long.
    ///
    /// Both halves are measured against the CLIP's own duration, never the
    /// instance's visible span — the rule `recipe.rs`'s `Project::layer`
    /// already states for clip time. A nest clip's edge therefore cuts a
    /// nested caption off mid-reveal instead of making it un-reveal early,
    /// and the two halves of one animation are measured on one clock
    /// rather than two.
    ///
    /// The two ramps are combined with `min`, so `in + out > duration`
    /// degrades rather than refusing: the reveal becomes a tent that never
    /// reaches 1, stays inside 0..1 and simply shows a short clip a partial
    /// reveal. Nothing here refuses, and nothing clamps the animation to
    /// fit — a range check is a fact about the vocabulary
    /// (`props_check.rs`), while "these two numbers are too big for THIS
    /// clip" is a fact about a clip, which a later trim could invalidate
    /// anyway.
    ///
    /// A tent keeps ONE phase for its whole life, and that is the second
    /// half of the same argument: the phase is what the renderer staggers
    /// by, so the instant the word turns is an instant the picture mirrors,
    /// and a tent has no instant where mirroring is invisible. The `plateau`
    /// comment below has it in full.
    fn of(animation: Option<&TextAnimation>, clip_t: Ticks, duration: Ticks) -> Reveal {
        let animation = match animation {
            Some(animation) => animation,
            None => return Reveal::WHOLE,
        };
        let arriving = ramp(clip_t, animation.r#in);
        // The departure is measured back from the clip's EXCLUSIVE end, so
        // it reaches 0 one frame past the last frame anybody draws: the
        // last frame of an un-revealing clip still shows a sliver, which is
        // right — the clip is gone on the next one.
        let leaving = ramp(duration.saturating_sub(clip_t), animation.out);

        // The phase is not a label on the amount: it is the ORDER the
        // renderer staggers by. `LayerRenderers.staggerIndex` counts a
        // word_fade's words and a line_rise's lines from the other end while
        // a layer is leaving, so that the first word in is the first word
        // out. The word turning therefore MIRRORS the picture end for end,
        // and the only amount at which that is invisible is 1, where every
        // item is whole whichever end the stagger counted from.
        //
        // The two ramps meet at 1 only when the animation fits — when there
        // is a plateau between them, `in + out <= duration`. A TENT has
        // none: its ramps cross below 1, and turning the word at that peak
        // would swap a four-word cue's alphas from [1, 1, .83, .33] to
        // [.33, .83, 1, 1] between two consecutive frames whose amount did
        // not change at all. So a tent — which D-C7 lets degrade rather than
        // refuse — un-arrives the way it arrived, keeping the phase it began
        // in. That is the arrival's, unless the arrival is instant, which
        // makes the clip nothing but a departure and gives it no order to
        // contradict.
        let plateau = animation.r#in.saturating_add(animation.out) <= duration;
        let departing = if plateau {
            // A tie is the arrival's: it covers the whole middle of a clip
            // that is fully revealed and not yet leaving, and the first
            // instant of an out phase, which is on the plateau and draws the
            // same picture either way.
            leaving < arriving
        } else {
            animation.r#in <= 0
        };

        Reveal {
            amount: arriving.min(leaving),
            phase: Some(if departing { "out" } else { "in" }),
            kind: Some(animation.kind),
        }
    }
}

/// One phase's progress: how far `elapsed` has got through `over`, bounded
/// to 0..1.
///
/// A phase of zero length is complete from the start rather than a division
/// by zero, and so is a NEGATIVE one — which only an action end patch or a
/// hand-written file can produce, since `set_action_end` is deliberately
/// lenient and `clamp_video` does not touch text. This is where an absurd
/// value is caught, because this is where it is consumed.
pub(crate) fn ramp(elapsed: Ticks, over: Ticks) -> f64 {
    if over <= 0 {
        return 1.0;
    }
    let progress = elapsed.max(0) as f64 / over as f64;
    // Both sides are integers, so today this cannot be anything but finite.
    // The guard is one comparison and it fails toward SHOWING the text,
    // where `number()` would turn a non-finite amount into 0.0 and show
    // none of it.
    if progress.is_finite() {
        progress.clamp(0.0, 1.0)
    } else {
        1.0
    }
}

/// The cache key for a text layer: its description, and the reveal when
/// there is one.
///
/// The reveal changes the PIXELS, and this hash is the only thing standing
/// between a per-frame value and a stale texture — Swift caches a rendered
/// paragraph under `"text:" + hash` and consults nothing else — so a frame
/// at one reveal must not be able to collide with the same text at another.
/// A reveal that changed the picture without changing the key would render
/// correctly in a single `render_frame` and freeze during playback, with no
/// error anywhere.
///
/// All THREE computed keys go in, not just the amount: a word fade and a
/// typewriter half done are two different pictures of the same text, and so
/// are a half-arrived and a half-departed line rise.
///
/// A layer with NO animation hashes the bare description, byte for byte as
/// it did before format version 5, so no shipped project's texture cache
/// behaves differently after this phase. An ANIMATED layer keeps its own
/// key even at amount 1: whether a full reveal draws exactly what no
/// animation draws is the renderer's promise, and a cache key must not lean
/// on one.
///
/// `words` is `Some` only when the text has a `word_style` (spec §11, W-4),
/// and then all five word keys go in too: a page is a different picture at
/// every word, and through a glide, a fill and a dim (W-13). Otherwise the
/// hash is exactly what it was before format version 9, `words` or not.
fn text_hash(description: &Value, reveal: &Reveal, words: Option<&Words>) -> String {
    if reveal.phase.is_none() && words.is_none() {
        return content_hash(description);
    }
    let mut keyed = Map::new();
    keyed.insert("text".to_string(), description.clone());
    if let Some(phase) = reveal.phase {
        keyed.insert("reveal".to_string(), number(reveal.amount));
        keyed.insert("reveal_phase".to_string(), Value::from(phase));
        keyed.insert("reveal_kind".to_string(), reveal_kind(reveal));
    }
    if let Some(words) = words {
        words.insert_into(&mut keyed);
    }
    content_hash(&Value::Object(keyed))
}

/// The reveal's kind as the recipe carries it: the schema's own spelling of
/// the variant, or `null` for a layer with no animation.
fn reveal_kind(reveal: &Reveal) -> Value {
    match reveal.kind {
        Some(kind) => json(&kind),
        None => Value::Null,
    }
}

/// A text layer's `source` object (spec §7.3): the description Swift lays
/// out, the hash it caches the laid-out result under, and the eight
/// computed keys that say how much of the description is showing — three
/// for the reveal, five for a word-timed page's words.
///
/// It takes a description, a clip time and a duration and nothing else —
/// no clip, no instance, no `Evaluated` — for [`Reveal`]'s reason read one
/// step further on: a text layer the core SYNTHESIZES has none of those to
/// offer, and this is the one function that would otherwise stop it being
/// a text layer like any other. `recipe.rs`'s `Source::Text` arm is what
/// digs the description out of an evaluated clip; everything after that is
/// here.
pub(crate) fn text_source(text: &TextProps, clip_t: Ticks, duration: Ticks) -> Value {
    // A styled page is a WHOLE reveal: `word_style` and `animation` do not
    // compose, and `word_style` wins (spec §11, W-5).
    let reveal = match text.word_style {
        Some(_) => Reveal::WHOLE,
        None => Reveal::of(text.animation.as_ref(), clip_t, duration),
    };
    let words = Words::of(text, clip_t, duration);
    let mut description = json(text);
    // The animation is STRIPPED from the description carried here: the
    // computed reveal below is the only account of it a renderer gets.
    // Left in, it would be a second one — and the wrong one, since
    // nothing downstream has the clip time to evaluate it against.
    // Removing it also keeps an unanimated clip's hash byte-identical to
    // what it was before format version 5. The inspector reads the
    // animation FIELD through `clip_state`; this description is what
    // draws.
    //
    // Version 9's keys ride in the description only when they change the
    // picture, so an unstyled, as-written title hashes byte for byte as it
    // did before them: `words` never (the computed `word` below is the
    // renderer's only account of them, W-4), `word_style` only when set,
    // `case` only when it is not `as_written`.
    if let Some(map) = description.as_object_mut() {
        map.remove("animation");
        map.remove("words");
        if text.word_style.is_none() {
            map.remove("word_style");
        }
        if text.case == TextCase::AsWritten {
            map.remove("case");
        }
    }
    let styled = text.word_style.is_some().then_some(&words);
    let mut source = Map::new();
    source.insert("kind".to_string(), Value::from("text"));
    source.insert(
        "hash".to_string(),
        Value::from(text_hash(&description, &reveal, styled)),
    );
    source.insert("text".to_string(), description);
    // The three computed reveal keys ride INSIDE the source object, where the
    // kind-specific description already lives, and all three are emitted
    // on every text layer whether it animates or not: an absent key would
    // mean two things — no animation here, or an older core that never
    // computed one — which is the argument `obscure` settled one layer
    // up. A layer-level key instead would put a null on every layer that
    // can never carry one.
    //
    // Together they are the WHOLE of what a renderer is told about the
    // animation: which routine (`reveal_kind`), how far (`reveal`), and
    // which way (`reveal_phase`). The two nulls always travel together —
    // no kind means no phase means an amount of 1.
    source.insert("reveal".to_string(), number(reveal.amount));
    source.insert(
        "reveal_phase".to_string(),
        match reveal.phase {
            Some(phase) => Value::from(phase),
            None => Value::Null,
        },
    );
    source.insert("reveal_kind".to_string(), reveal_kind(&reveal));
    // The five computed word keys (`recipe_words.rs`), emitted on every
    // text layer for the reveal keys' reason: `word` is how many words have
    // started, the other four how far its pop, glide, fill and the page's
    // dim have got, and all are null on a page that is not word-timed.
    words.insert_into(&mut source);
    Value::Object(source)
}

// ---- the burn-in timecode layer -----------------------------------------

/// The face a timecode burn-in is drawn in. A concrete face, not a family,
/// for `edit_clip.rs`'s `TITLE_FONT` reason: the renderer asks for exactly
/// this name. IBM Plex Mono is the app's own face for machine-produced
/// numbers (`Theme.mono`), and monospacing is not decoration here — a
/// proportional timecode's digits change width as they count, so the field
/// twitches thirty times a second in the corner of a frame somebody is
/// trying to watch.
pub(crate) const BURN_IN_FONT: &str = "IBMPlexMono-Regular";

/// The burn-in's type size as a fraction of the canvas HEIGHT, so a 4K
/// review copy and a 1080p one read the same at the same zoom. Smaller than
/// the Caption preset's 0.035 (`CaptionLayout.captionPreset`), because a
/// burn-in is a reference reading a reviewer glances at when they want to
/// name a moment, not the thing being read.
const BURN_IN_SIZE_FRACTION: f64 = 0.03;

/// How far BELOW the canvas centre the burn-in's box centre sits, as a
/// fraction of canvas height — 94 % of the way down the frame.
///
/// # It does NOT clear a caption, and no value of this constant would
///
/// The burn-in is appended LAST and is therefore topmost, and its plate
/// overlaps the Caption preset's at every legal canvas size. Read it here
/// rather than measure it off a frame: with a two-line cue on screen, the
/// burn-in's translucent plate and its digits cover the bottom of the
/// caption's second line — about 34 px of it at 1080.
///
/// The arithmetic, in canvas pixels, because it IS the argument. A layer's
/// `y` is the offset of the box's CENTRE (spec §7.3), so the two box centres
/// are `(0.44 − 0.38)·H = 0.06·H` apart. Both boxes are the laid-out text
/// plus TWICE a backdrop padding of 12 — a fixed PIXEL amount on both sides,
/// [`Backdrop`]'s default and the Caption preset's own — so a caption's
/// half-height is `lines · 0.712 · round(0.035·H) + 12` (SourceSans3's hhea
/// line box is 1.424 em) and the burn-in's is `0.65 · round(0.03·H) + 12`
/// (IBM Plex Mono's is 1.300 em). Two lines therefore want `0.0693·H + 24`
/// of clearance against `0.06·H` of gap, which is short at EVERY H — 4K
/// included, because the shortfall GROWS with the canvas — and one line is
/// short below H ≈ 1540, which is to say at 1080 and at 720.
///
/// **Moving this constant down cannot cure it, and buys a worse picture.**
/// Clearing a two-line caption needs `0.4493 + 24/H`; keeping the plate on
/// the canvas allows at most `0.4805 − 12/H`; the two cross only above
/// H ≈ 1155, so at 1080 no fraction does both and at 720 none comes close.
/// The largest on-canvas value at 1080 is ≈ 0.469, and 0.469 hangs the
/// plate off the bottom of a 720 frame — a burn-in with its digits cut in
/// half is a worse picture than a burn-in over a caption. The one nudge
/// that buys anything at all, ≈ 0.447, clears a ONE-line caption at 1080 by
/// zero pixels and raises the bottom-cut threshold below from H ≈ 296 to
/// H ≈ 355: a margin resting on font metrics this crate cannot see, paid
/// for with a smaller usable canvas. Shrinking [`BURN_IN_SIZE_FRACTION`]
/// does not rescue it either, because the 24 px of padding does not scale
/// with the canvas: the requirement becomes `f ≤ 0.054 − 27.7/H`, and no
/// positive `f` satisfies it at 360.
///
/// The cure is outside this constant and outside this crate: raise the
/// Caption preset (`CaptionLayout.captionPreset`'s `yFraction` — a SHIPPED
/// placement that every caption already on a timeline sits at, and an
/// identity a burn-in does not get to change), or make a backdrop's padding
/// a fraction of the canvas rather than a fixed 12. Each is its own
/// decision with its own consequences for files that exist. And note what
/// the core could not do even if it wanted to: non-overlap is a fact about
/// LAID-OUT text, the model stores no measurement and by the standing rule
/// of spec §5.3 and §11 never will, so every number above is a reader's
/// arithmetic over the bundled faces and not something [`burn_in_layer`]
/// is in any position to compute.
///
/// # The bottom edge
///
/// Clearance under the plate is `0.5·H − (0.44·H + 0.65·round(0.03·H) + 12)`
/// ≈ `0.0405·H − 12` px: about 32 px at 1080, and NEGATIVE below H ≈ 296.
/// `CANVAS_MIN` is 16 (`edit_canvas.rs`), so a legal 640×288 canvas has its
/// plate cut by the bottom of the frame. Same fixed-padding term as above,
/// same cure.
const BURN_IN_Y_FRACTION: f64 = 0.44;

/// The `clip` a burn-in layer reports (spec §7.3's layer `clip` key).
///
/// A burn-in came from no clip, and 0 is the only honest answer available:
/// the key is a `u32`, `Project::new` starts allocating at 2, and
/// `RecipeLayer.init(from:)` already defaults an unreadable `clip` to 0. It
/// is not GUARANTEED unused — `validate` checks id uniqueness, not that an
/// id is non-zero, so a hand-written project may legally name a clip 0 —
/// and the collision is harmless because of who reads the key: the canvas
/// overlay's hit-test, which asks for a recipe with the DEFAULT options and
/// therefore never sees a burn-in at all. Say it rather than assume it,
/// because "the burn-in is never in the overlay's recipe" is the whole
/// reason this is safe.
pub(crate) const BURN_IN_CLIP: u32 = 0;

/// A text layer showing the project timecode at `t`, drawn over everything
/// else (road map 2's phase 7; [`crate::recipe::RecipeOptions`]).
///
/// **Why the core writes it.** A burn-in is a picture, and everything that
/// draws a frame reads one recipe — so a burnt export and a burnt
/// `render_frame` agree by construction, exactly as [`Reveal`] and a
/// layer's `blend` do. A renderer-side burn-in would be a second
/// description of the frame, and the two would disagree the first time
/// either was changed.
///
/// **It has no reveal, and it does not need one.** [`Reveal`]'s own doc
/// sentence was written for this case: the reveal is derived from an
/// animation, a clip time and a duration and from nothing else — no clip,
/// no instance — "so a layer the core synthesizes rather than reads off a
/// clip can simply not have one". `animation` is `None`, so [`Reveal::of`]
/// returns [`Reveal::WHOLE`] and the two arguments below it are not read;
/// the layer carries `reveal` 1.0 with a null phase and a null kind, and
/// [`text_hash`] falls through to the bare [`content_hash`] of the
/// description — one texture per distinct reading, which is what a cache
/// wants for a string that changes every frame anyway.
///
/// # Placement is a FRACTION of the canvas, not "bottom-centre"
///
/// Read it here or read the gap as a bug. A layer's `y` is the offset of the
/// text box's CENTRE from the canvas centre (spec §7.3), and the core has no
/// measured text size to subtract from a bottom edge — only the platform can
/// lay a string out, and by the standing rule of spec §5.3 and §11 the model
/// never stores what comes back. So the burn-in cannot be anchored to the
/// bottom of the frame; it is placed at [`BURN_IN_Y_FRACTION`] of the canvas
/// height below the centre with `valign` `middle`, which keeps the box
/// symmetric about the point the core CAN name. `CaptionLayout`'s Caption
/// preset places every caption the same way and for the same reason, and
/// its `yFraction` 0.38 is the number this one is placed against — though
/// NOT, as [`BURN_IN_Y_FRACTION`] argues at length, far enough from it to
/// clear a caption's plate. A burn-in is topmost and covers the bottom of a
/// two-line cue at every canvas size; that is a documented limit with the
/// arithmetic behind it, not an oversight.
///
/// # Two readings that are not bugs
///
/// **It is NON-DROP, and there is no drop-frame anywhere in this crate.**
/// A 29.97 fps burn-in therefore reads about 3.6 seconds behind wall clock
/// at the one-hour mark — that drift IS the definition of non-drop
/// (`time::Fps::nominal`), it is what the toolbar's timecode field has
/// displayed since M1, and it is what `parse_timecode` reads back. Do not
/// "fix" it here: a burn-in that disagreed with the toolbar over the same
/// instant is a worse outcome than a burn-in that drifts the way the whole
/// application drifts.
///
/// **It shows PROJECT time, not file time.** An export of an in/out range
/// rebases its samples by subtracting `range.start` while the composition
/// time handed to the compositor stays project time, so a range export
/// starting at 00:00:10:00 writes a file that begins at 00:00 and carries a
/// burn-in reading 00:00:10:00 on its first frame. That is the right answer
/// for a review copy — the whole point of the number is to name a moment
/// back on the timeline the notes will be applied to — but it is surprising
/// enough that somebody will file it, so it is written down.
///
/// It honours `canvas.timecode_frames`: `HH:MM:SS:FF` or `HH:MM:SS.mmm`, the
/// document's own choice, through the one formatter. There is deliberately
/// no sub-key for it. A burn-in and the toolbar spelling one instant two
/// ways is precisely what `time::format_timecode` exists to prevent (phase
/// 3's Remove Silences sheet made the same call for the same reason).
pub(crate) fn burn_in_layer(canvas: &Canvas, t: Ticks) -> Value {
    let text = TextProps {
        content: format_timecode(t, canvas.fps, canvas.timecode_frames),
        font: BURN_IN_FONT.to_string(),
        // `check_text` refuses a size of 0, so the floor keeps a synthesized
        // layer inside the vocabulary every authored one is held to. The
        // fraction rounds to 0 only below seventeen pixels of canvas height,
        // which `set_canvas` refuses and only a hand-written file reaches.
        size: (f64::from(canvas.height) * BURN_IN_SIZE_FRACTION)
            .round()
            .max(1.0),
        // The readability plate: a timecode lands on whatever the frame
        // happens to hold at that instant, which for a screencast is often
        // white. The default backdrop is the same translucent black the
        // Caption preset uses.
        backdrop: Some(Backdrop::default()),
        // A timecode is one line and must never wrap. `None` is the default
        // and is stated anyway, because a wrapped burn-in would be a wrong
        // picture nobody would think to look for.
        width: None,
        animation: None,
        ..TextProps::default()
    };
    let video = VideoProps {
        y: f64::from(canvas.height) * BURN_IN_Y_FRACTION,
        ..VideoProps::default()
    };
    RecipeLayer {
        clip: BURN_IN_CLIP,
        // Assembled by the same function every authored text layer goes
        // through, which is what makes the burn-in a text layer like any
        // other rather than a second spelling of one.
        source: text_source(&text, 0, 0),
        // Null for text, whose size only the renderer knows.
        source_size: Value::Null,
        video: &video,
        // `Frame::TOP` is the identity, so this is the placement a timeline
        // clip gets: the burn-in belongs to the canvas, not to any nest.
        placed: Frame::TOP.place(&video),
        blend: BlendMode::Normal,
        transition: Value::Null,
        matte: Value::Null,
    }
    .object()
}
