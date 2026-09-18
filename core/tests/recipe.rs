//! The frame recipe's OPTIONS, and the one layer the core writes itself
//! (spec §7.3, road map 2's phase 7): `rc_project_frame_recipe_opts` and the
//! timecode burn-in.
//!
//! Two halves, and the first one is a regression proof rather than a feature
//! proof. `frame_recipe(t)` is now `frame_recipe_opts(t, defaults)` and the
//! layer object is built by one shared skeleton, so the thing most likely to
//! break in this phase is a recipe nobody asked to change — the preview, the
//! overlay's hit-test and every earlier phase's proof PNG all read it. So
//! the un-optioned answer is compared BYTE for byte, not field by field, and
//! the burnt answer is compared to it with its last layer dropped.
//!
//! The second half is the burn-in itself, and everything asserted about it
//! is asserted against something written independently of the code under
//! test: literal timecode strings computed by hand from the non-drop
//! definition; the key SET a real drawn layer publishes; and the content
//! hash of an authored text clip patched to the same description, which is
//! what pins the burn-in to `text_source` rather than to a second spelling
//! of one.

mod common;

use serde_json::{json, Value};

use common::{array, at, num, take_string, text, Handle, Outcome};
use reelcut_core::ffi::rc_timecode_format;

/// The twenty keys of a recipe layer (spec §7.3). Written out rather than
/// read off a drawn layer, because a burn-in matching a drawn layer that has
/// itself lost a key would pass a comparison and fail a renderer:
/// `RecipeLayer.init(from:)` DEFAULTS a missing key with no diagnostic
/// anywhere, so nothing downstream would ever complain.
const LAYER_KEYS: [&str; 20] = [
    "blend",
    "chroma",
    "clip",
    "clip_rect",
    "color",
    "corner_radius",
    "crop",
    "filters",
    "obscure",
    "opacity",
    "reflection",
    "rotation",
    "scale",
    "shadow",
    "source",
    "source_size",
    "spotlight",
    "transition",
    "x",
    "y",
];

/// The six keys a TEXT layer's `source` object carries (spec §7.3): the
/// tagged kind, the cache hash, the description, and the three computed
/// reveal keys that are emitted whether the layer animates or not.
const TEXT_SOURCE_KEYS: [&str; 6] = [
    "hash",
    "kind",
    "reveal",
    "reveal_kind",
    "reveal_phase",
    "text",
];

/// The ticks a test sweeps unless it wants a particular reading: inside
/// every clip, on a cut, in the overlap, past the end, and before the
/// start. A recipe is TOTAL, so the last two are as much a case as the rest.
const SPREAD: [i64; 9] = [
    -20_000, 0, 1, 600_000, 2_000_000, 3_500_000, 5_500_000, 8_000_000, 90_000_000,
];

/// A project with one of everything a layer can be: two media clips
/// overlapping (so both halves carry a transition and the recipe's `blend`
/// override fires), an animated text clip, a gradient shape, every video
/// property group on one clip with an action moving two of them, and a nest
/// (so a layer carries a `clip_rect`).
///
/// The byte comparison is only worth what the fixture exercises, which is
/// why it is this and not one clip.
fn rich(fps_num: u32, fps_den: u32) -> Handle {
    Handle::new(1920, 1080, fps_num, fps_den).apply_all(&[
        json!({"op": "add_media", "descriptor": {
            "path": "/m/a.mov", "kind": "video", "duration": 6_000_000,
            "width": 640, "height": 480, "fps": [30, 1],
            "has_video": true, "has_audio": true}}),
        json!({"op": "add_clip", "track": 1, "media": 2, "at": 0}),
        json!({"op": "add_clip", "track": 1, "media": 2, "at": 5_000_000}),
        json!({"op": "add_track"}),
        json!({"op": "add_text_clip", "track": 5, "at": 0, "duration": 4_000_000,
               "text": {"content": "Hello there",
                        "animation": {"kind": "word_fade", "in": 600_000, "out": 300_000}}}),
        json!({"op": "add_shape_clip", "track": 5, "at": 5_000_000,
               "shape": {"kind": "ellipse", "gradient": {"kind": "radial", "angle": 30,
                         "stops": [{"at": 0, "color": [1, 0, 0, 1]},
                                   {"at": 1, "color": [0, 0, 1, 1]}]}}}),
        json!({"op": "set_video", "clips": [3], "patch": {
            "x": 40, "y": -20, "scale": 0.75, "rotation": 12, "opacity": 0.8,
            "crop": {"l": 10, "t": 5, "r": 3, "b": 2}, "corner_radius": 8,
            "shadow": {"blur": 10, "distance": 5, "angle": 45, "color": [0, 0, 0, 0.5]},
            "color": {"brightness": 0.1, "contrast": 0.2, "saturation": -0.1, "hue": 15},
            "chroma": {"key": [0, 1, 0], "tolerance": 0.3, "softness": 0.1, "spill": 0.2},
            "filters": [{"kind": "blur", "amount": 0.4}, {"kind": "sepia", "amount": 0.6}],
            "reflection": {"opacity": 0.4, "height": 0.5, "gap": 6, "falloff": 0.5},
            "spotlight": {"shape": "ellipse", "x": 10, "y": 20, "width": 300, "height": 200,
                          "feather": 30, "dim": 0.6, "zoom": 1.2},
            "obscure": [{"shape": "rect", "x": 0, "y": 0, "width": 200, "height": 100,
                         "feather": 12, "kind": "blur", "amount": 0.9}],
            "blend": "multiply"}}),
        json!({"op": "add_action", "clip": 3, "at": 0, "duration": 1_200_000}),
        json!({"op": "set_action_end", "clip": 3, "action": 8,
               "patch": {"video": {"scale": 1.5, "opacity": 0.3}}}),
        json!({"op": "add_track"}),
        json!({"op": "add_text_clip", "track": 9, "at": 1_000_000, "duration": 3_000_000,
               "text": {"content": "Nested"}}),
        json!({"op": "add_shape_clip", "track": 9, "at": 4_000_000, "duration": 3_000_000}),
        json!({"op": "nest", "clips": [10, 11]}),
    ])
}

/// The options that turn the burn-in on, and the two spellings of off.
fn on() -> Value {
    json!({"burn_in_timecode": true})
}
fn off() -> Value {
    json!({"burn_in_timecode": false})
}

/// An op that may be an identity on this project: `set_canvas` refuses to
/// change nothing (every edit here answers `Outcome::Identity` rather than
/// a phantom undo step), and a test that sets the size or the timecode
/// style a fixture already has is asking for exactly that.
fn settle(handle: &Handle, op: &Value) -> Handle {
    match handle.try_apply(op) {
        Ok(Outcome::Applied(next)) => next,
        Ok(Outcome::Identity) => handle.duplicate(),
        Ok(Outcome::Refused(why)) => panic!("a rule refused this op: {why}\n{op}"),
        Err(msg) => panic!("{msg}\n{op}"),
    }
}

/// The last layer of a burnt recipe — the burn-in, since it is appended.
fn burn_in(recipe: &Value) -> Value {
    let layers = array(recipe, "/layers");
    layers
        .last()
        .cloned()
        .expect("a burnt recipe always has at least the burn-in layer")
}

/// The keys of an object at `pointer`, sorted, so a test can compare SETS.
fn keys(value: &Value, pointer: &str) -> Vec<String> {
    let mut names: Vec<String> = at(value, pointer)
        .as_object()
        .unwrap_or_else(|| panic!("the value at {pointer} is not an object"))
        .keys()
        .cloned()
        .collect();
    names.sort();
    names
}

// ---- the un-optioned recipe did not move --------------------------------

#[test]
fn the_option_off_is_byte_identical_to_the_plain_recipe() {
    let project = rich(30, 1);
    for t in SPREAD {
        let plain = project.recipe_text(t);
        assert_eq!(
            Some(&plain),
            project.recipe_opts_text(t, &json!({})).as_ref(),
            "an empty options object must produce the plain recipe at {t}"
        );
        assert_eq!(
            Some(&plain),
            project.recipe_opts_text(t, &off()).as_ref(),
            "burn_in_timecode: false must produce the plain recipe at {t}"
        );
    }
}

#[test]
fn the_burnt_recipe_is_the_plain_one_plus_a_last_layer() {
    let project = rich(30, 1);
    for t in SPREAD {
        let plain = project.recipe(t);
        let mut burnt = project.recipe_opts(t, &on());
        let layers = array(&burnt, "/layers").len();
        assert_eq!(
            layers,
            array(&plain, "/layers").len() + 1,
            "the burn-in must add exactly one layer at {t}"
        );
        assert_eq!(
            text(&burnt, &format!("/layers/{}/source/kind", layers - 1)),
            "text",
            "the added layer must be the LAST one and must be text, at {t}"
        );
        // Drop the last layer and everything else must be untouched — the
        // other layers, `t`, and the canvas block.
        burnt["layers"]
            .as_array_mut()
            .expect("layers is an array")
            .pop();
        assert_eq!(
            burnt, plain,
            "the burn-in must not disturb anything else in the recipe at {t}"
        );
    }
}

#[test]
fn a_recipe_with_nothing_in_it_still_burns_in() {
    // No clips at all, and a `t` past the end of one that has them: a
    // burn-in is about the CANVAS, so "there is nothing to draw" is not a
    // reason to draw nothing.
    let empty = Handle::new(1920, 1080, 30, 1);
    for t in SPREAD {
        assert!(array(&empty.recipe(t), "/layers").is_empty());
        assert_eq!(array(&empty.recipe_opts(t, &on()), "/layers").len(), 1);
    }
    let project = rich(30, 1);
    assert_eq!(
        array(&project.recipe_opts(90_000_000, &on()), "/layers").len(),
        1,
        "past the last clip the burn-in must be the only layer"
    );
}

// ---- what the burn-in reads ---------------------------------------------

#[test]
fn the_burn_in_content_is_the_documents_timecode() {
    // Literals, computed by hand from the non-drop definition, so nothing
    // here is checked against the code that produced it. At 30 fps a frame
    // is 20 000 ticks; at 25 fps it is 24 000.
    let thirty = rich(30, 1);
    for (t, expected) in [
        (0, "00:00:00:00"),
        (20_000, "00:00:00:01"),
        (600_000, "00:00:01:00"),
        (54_000_000, "00:01:30:00"),
        (54_020_000, "00:01:30:01"),
    ] {
        assert_eq!(
            text(
                &burn_in(&thirty.recipe_opts(t, &on())),
                "/source/text/content"
            ),
            expected,
            "the burn-in at {t} ticks, 30 fps"
        );
    }

    let twentyfive = rich(25, 1);
    for (t, expected) in [
        (0, "00:00:00:00"),
        (168_000, "00:00:00:07"),
        (600_000, "00:00:01:00"),
        (36_024_000, "00:01:00:01"),
    ] {
        assert_eq!(
            text(
                &burn_in(&twentyfive.recipe_opts(t, &on())),
                "/source/text/content"
            ),
            expected,
            "the burn-in at {t} ticks, 25 fps"
        );
    }
}

#[test]
fn the_burn_in_is_non_drop_like_every_other_timecode_this_library_writes() {
    // 29.97 counts 30 frames to the timecode second while only 29.97 of them
    // happen, so a non-drop reading falls behind wall clock by 0.1 % — about
    // 3.6 s at the hour, which is what this asserts. That drift IS the
    // definition (`Fps::nominal`), it is what the toolbar has displayed
    // since M1, and a burn-in that disagreed with the toolbar over one
    // instant would be the worse bug. Nobody is to "fix" it here.
    let project = rich(30_000, 1001);
    let one_hour = 3600 * 600_000;
    assert_eq!(
        text(
            &burn_in(&project.recipe_opts(one_hour, &on())),
            "/source/text/content"
        ),
        "00:59:56:12",
        "one hour of wall clock reads 3.6 s short in non-drop timecode"
    );
}

#[test]
fn the_burn_in_honours_the_documents_timecode_frames() {
    // 740 400 ticks is 1.234 s exactly, and 37.02 frames at 30 fps.
    let t = 740_400;
    let frames = rich(30, 1);
    assert_eq!(
        text(
            &burn_in(&frames.recipe_opts(t, &on())),
            "/source/text/content"
        ),
        "00:00:01:07"
    );

    let millis = settle(
        &frames,
        &json!({"op": "set_canvas", "timecode_frames": false}),
    );
    assert_eq!(
        text(
            &burn_in(&millis.recipe_opts(t, &on())),
            "/source/text/content"
        ),
        "00:00:01.234",
        "a document that spells time in milliseconds burns it in the same way"
    );
}

#[test]
fn the_burn_in_and_the_toolbar_cannot_spell_one_instant_two_ways() {
    // The claim the "no sub-key for it" decision rests on, as a test: the
    // burn-in goes through `time::format_timecode`, which is the same
    // function `rc_timecode_format` publishes for the toolbar's field. A
    // build that formatted the number itself would pass the literals above
    // for the readings they cover and fail here at the first rate or
    // negative tick nobody thought to write down.
    for (num, den) in [(30, 1), (25, 1), (24_000, 1001), (60, 1)] {
        for frames in [true, false] {
            let project = settle(
                &rich(num, den),
                &json!({"op": "set_canvas", "timecode_frames": frames}),
            );
            for t in SPREAD {
                let expected = take_string(unsafe { rc_timecode_format(t, num, den, frames) })
                    .expect("rc_timecode_format never returns NULL for a valid rate");
                assert_eq!(
                    text(
                        &burn_in(&project.recipe_opts(t, &on())),
                        "/source/text/content"
                    ),
                    expected,
                    "burn-in vs toolbar at {t} ticks, {num}/{den}, frames={frames}"
                );
            }
        }
    }
}

// ---- what the burn-in IS ------------------------------------------------

#[test]
fn the_burn_in_carries_every_key_a_drawn_layer_carries() {
    let project = rich(30, 1);
    let burnt = project.recipe_opts(1_000_000, &on());
    let layer = burn_in(&burnt);

    assert_eq!(
        keys(&layer, ""),
        LAYER_KEYS,
        "a layer key the burn-in omits is DEFAULTED silently by \
         RecipeLayer.init(from:), with no diagnostic anywhere"
    );
    assert_eq!(
        keys(&layer, ""),
        keys(&burnt, "/layers/0"),
        "the burn-in and a drawn layer must publish the same key set"
    );

    assert_eq!(
        keys(&layer, "/source"),
        TEXT_SOURCE_KEYS,
        "a source key the burn-in omits is DEFAULTED silently by \
         RecipeSourceRef.init(from:)"
    );
    // Layer 1 of the fixture at this tick is the authored, ANIMATED text
    // clip: the same six keys, which is the point of emitting all three
    // reveal keys on every text layer whether it animates or not.
    assert_eq!(text(&burnt, "/layers/1/source/kind"), "text");
    assert_eq!(keys(&layer, "/source"), keys(&burnt, "/layers/1/source"));
}

#[test]
fn the_burn_in_is_a_whole_reveal_and_hashes_as_one() {
    let project = rich(30, 1);
    let t = 1_000_000;
    let layer = burn_in(&project.recipe_opts(t, &on()));

    assert_eq!(num(&layer, "/source/reveal"), 1.0);
    assert!(
        at(&layer, "/source/reveal_phase").is_null(),
        "a layer the core synthesizes has no animation, so no phase"
    );
    assert!(at(&layer, "/source/reveal_kind").is_null());
    assert!(
        at(&layer, "/source/text").get("animation").is_none(),
        "the recipe strips `animation` out of every text description"
    );

    // The oracle: an AUTHORED text clip patched to the burn-in's own
    // description must hash to the burn-in's hash. `text_hash` folds a
    // reveal into the key whenever there IS one, so a burn-in that carried
    // an animation — or that built its source object by hand instead of
    // going through `text_source` — cannot match this.
    let content = text(&layer, "/source/text/content").to_string();
    let twin = project.apply(&json!({
        "op": "add_text_clip", "track": 1, "at": 20_000_000, "duration": 600_000,
        "text": {"content": content, "font": "IBMPlexMono-Regular", "size": 32,
                 "backdrop": {"color": [0, 0, 0, 0.6], "padding": 12, "radius": 8}}}));
    let authored = twin.recipe(20_000_000);
    let authored = array(&authored, "/layers")
        .iter()
        .find(|l| at(l, "/source/kind") == "text")
        .cloned()
        .expect("the twin clip draws a text layer");
    assert_eq!(
        at(&authored, "/source/text"),
        at(&layer, "/source/text"),
        "the twin must be described identically before its hash can mean anything"
    );
    assert_eq!(
        text(&authored, "/source/hash"),
        text(&layer, "/source/hash"),
        "the burn-in must hash through the same text_source every text layer does"
    );
}

#[test]
fn the_burn_in_is_a_plain_topmost_layer() {
    let project = rich(30, 1);
    // 1 000 000 ticks is inside the fixture's transition-free stretch and
    // also inside the nest, so the layers under this one carry a clip_rect
    // and a multiply — neither of which may reach the burn-in.
    let layer = burn_in(&project.recipe_opts(1_000_000, &on()));

    assert_eq!(at(&layer, "/clip"), 0, "a burn-in came from no clip");
    assert_eq!(text(&layer, "/blend"), "normal");
    assert!(at(&layer, "/transition").is_null());
    assert!(at(&layer, "/clip_rect").is_null());
    assert!(
        at(&layer, "/source_size").is_null(),
        "text has no size the core knows"
    );
    assert_eq!(num(&layer, "/scale"), 1.0);
    assert_eq!(num(&layer, "/rotation"), 0.0);
    assert_eq!(num(&layer, "/opacity"), 1.0);
    assert_eq!(num(&layer, "/corner_radius"), 0.0);
    for edge in ["l", "t", "r", "b"] {
        assert_eq!(num(&layer, &format!("/crop/{edge}")), 0.0);
    }
    assert!(array(&layer, "/filters").is_empty());
    assert!(array(&layer, "/obscure").is_empty());
    for key in ["shadow", "chroma", "reflection", "spotlight"] {
        assert!(at(&layer, &format!("/{key}")).is_null(), "{key}");
    }

    assert_eq!(
        text(&layer, "/source/text/font"),
        "IBMPlexMono-Regular",
        "the bundled monospaced face, so the digits do not change width as \
         they count"
    );
    assert!(
        at(&layer, "/source/text/width").is_null(),
        "a timecode is one line and must never wrap"
    );
    assert!(
        !at(&layer, "/source/text/backdrop").is_null(),
        "the readability plate"
    );
    assert_eq!(
        text(&layer, "/source/text/valign"),
        "middle",
        "the box is symmetric about the point the core can name"
    );
}

#[test]
fn the_burn_in_is_placed_as_a_fraction_of_the_canvas_height() {
    let ops = |handle: &Handle, w: u32, h: u32| -> Value {
        let sized = settle(
            handle,
            &json!({"op": "set_canvas", "width": w, "height": h}),
        );
        burn_in(&sized.recipe_opts(1_000_000, &on()))
    };
    let project = rich(30, 1);
    let at_1080 = ops(&project, 1920, 1080);
    let at_2160 = ops(&project, 3840, 2160);

    assert_eq!(
        num(&at_1080, "/x"),
        0.0,
        "centred horizontally: the core has no measured width either"
    );
    let y = num(&at_1080, "/y");
    assert!(
        y > 0.0 && y < 540.0,
        "below the canvas centre and inside the canvas, got {y}"
    );
    // A layer's y is the offset of the text box's CENTRE (spec §7.3), and
    // the core stores no measured text size, so the placement can only be a
    // fraction. The two canvases must therefore agree on the fraction, not
    // on the pixels.
    assert_eq!(
        num(&at_2160, "/y") / 2160.0,
        y / 1080.0,
        "the same fraction of the canvas height at both sizes"
    );
    // The type size is a fraction of the height too, ROUNDED to a whole
    // point the way `CaptionLayout` rounds a preset's — so it scales with
    // the canvas without landing on a fractional face size. 0.03 of 1080 is
    // 32.4; of 2160 it is 64.8, which is 65 and not 64, so the two sizes are
    // within a point of double rather than exactly double.
    let small = num(&at_1080, "/source/text/size");
    let large = num(&at_2160, "/source/text/size");
    assert_eq!(small, 32.0, "0.03 of 1080, rounded");
    assert_eq!(small.fract(), 0.0, "a whole point size");
    assert!(
        large > small && (large - 2.0 * small).abs() <= 1.0,
        "the size must scale with the canvas, got {small} then {large}"
    );

    // The plate has to stay ON the canvas. One em box below the centre
    // offset is a conservative stand-in for the line height the core cannot
    // measure, and even that clears the bottom edge.
    assert!(small > 0.0, "text.size must be above zero (props_check.rs)");
    assert!(
        y + small < 540.0,
        "the burn-in and its plate must stay on the canvas: y {y} + size {small}"
    );
}

// ---- how the options are read -------------------------------------------

#[test]
fn text_that_is_not_json_answers_null() {
    // NULL is the only answer available: the queries carry no err_out. What
    // this really stands over is the pointer being read INSIDE the closure
    // `project_json` wraps in catch_unwind — an unwrap outside it would take
    // the whole test binary down rather than fail one assertion.
    let project = rich(30, 1);
    for bad in ["{", "", "not json", "{\"burn_in_timecode\":", "}{"] {
        assert!(
            project.recipe_opts_text(0, bad).is_none(),
            "unreadable options must answer NULL, not a recipe: {bad:?}"
        );
    }
}

#[test]
fn an_option_the_caller_spelled_wrong_means_off() {
    // Absent, wrongly typed, or in a document that is not an object at all:
    // all of them are OFF, which is the frame the caller would have got
    // before the option existed. A refusal has nowhere to go on this path,
    // and a NULL at frame rate is a black preview.
    let project = rich(30, 1);
    let plain = project.recipe_text(1_000_000);
    for spelling in [
        "{}",
        "[]",
        "null",
        "7",
        "\"burn_in_timecode\"",
        "{\"burn_in_timecode\": \"yes\"}",
        "{\"burn_in_timecode\": 1}",
        "{\"burn_in_timecode\": null}",
        "{\"burn_in\": true}",
        "{\"BURN_IN_TIMECODE\": true}",
    ] {
        assert_eq!(
            project.recipe_opts_text(1_000_000, spelling).as_ref(),
            Some(&plain),
            "this must read as OFF: {spelling}"
        );
    }
}

#[test]
fn an_unknown_option_beside_a_known_one_is_ignored() {
    // The other half of the rule: reading the keys it knows means a caller
    // from a newer build still gets its burn-in.
    let project = rich(30, 1);
    let burnt = project.recipe_opts(
        1_000_000,
        "{\"burn_in_timecode\": true, \"no_such_option\": 3}",
    );
    assert_eq!(
        burnt.to_string(),
        project.recipe_opts_text(1_000_000, &on()).unwrap(),
        "an unknown option must change nothing about the answer"
    );
    assert_eq!(text(&burn_in(&burnt), "/source/kind"), "text");
}

#[test]
fn the_option_changes_no_other_answer_the_project_gives() {
    // A recipe option is a question asked of a project, not a property of
    // one: nothing is stored, so the plan, the duration and the file are
    // what they were. The plan matters most — Swift rebuilds its
    // composition on a plan STRING difference (spec §7.6), so an option that
    // touched it would rebuild the world every burnt frame.
    let project = rich(30, 1);
    let plan = project.plan_text();
    let file = project.to_json();
    let duration = project.duration();
    let _ = project.recipe_opts(1_000_000, &on());
    assert_eq!(project.plan_text(), plan);
    assert_eq!(project.to_json(), file);
    assert_eq!(project.duration(), duration);
    // And the burn-in is not a clip: the project still holds the five it
    // had (two media, a text, a shape, and the nest clip the last two
    // became).
    assert_eq!(array(&project.value(), "/clips").len(), 5);
}
