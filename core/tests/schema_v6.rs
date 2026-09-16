//! Black-box tests for what format version 6 added — `video.blend`, how a
//! layer combines with the canvas under it, and `shape.gradient`, a ramp
//! that takes precedence over a shape's flat fill (road map 2, phase 6) —
//! driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Eight things are pinned here, and each is a promise the rest of phase 6
//! leans on:
//!
//! - **Every older file still opens.** Both fields default — `normal` and
//!   `null` — so there is no migration step and a version-1 … version-5
//!   file reads back blending source-over with no gradient anywhere,
//!   stamped version 6. The BUMP is still the point, and this version's
//!   loss would be the quietest yet: unknown keys are ignored at every
//!   level by design (`model.rs`'s module doc), so without the gate a
//!   version-5 build would open the file, drop every blend and every
//!   gradient on read, and write that loss back on the next save — and a
//!   dropped blend removes NOTHING from the picture, since the layer is
//!   still drawn, just source-over. There is not even a hole to notice.
//!   The gate itself is `schema_v3.rs`'s claim and is not restated here.
//! - **Each is the LAST key of its object**, read off the written TEXT,
//!   because a parsed `Value` sorts its keys and cannot tell. Declaration
//!   order is key order, so a version-5 file diffed against a version-6 one
//!   differs by two trailing keys rather than by a re-ordering.
//! - **`normal` is the default and it is first**, which is the whole reason
//!   the field is safe to add to a shipped schema: an absent key, a zeroed
//!   uniform block and a recipe from an older core must all mean the
//!   source-over every project drew before the key existed.
//! - **Every mode's spelling round-trips**, all eight of them. The JSON
//!   spelling is persisted and the declaration ORDER is the shader
//!   discriminant, so a rename is silent data loss in a shipped file and a
//!   reorder is every blended layer in every project drawing differently.
//! - **A gradient added with nothing said is black to white, left to
//!   right** — the feature's whole first impression, since `{"gradient":
//!   {}}` is what the inspector's Add and the most natural agent patch both
//!   send.
//! - **Setting a gradient does not clear `fill`.** Both persist, the
//!   renderer prefers the gradient, and `{"gradient": null}` is therefore
//!   an exact inverse rather than a one-way door.
//! - **The stops are policed at both ends and NOT sorted.** Fewer than two
//!   is a solid colour, which `fill` already spells; more than
//!   `MAX_GRADIENT_STOPS` is named rather than trimmed; an out-of-order
//!   list is ACCEPTED on purpose, and that is pinned here so a later reader
//!   does not "fix" it into a refusal (`props_check.rs` argues it).
//! - **Both travel through `paste_attributes`**, which replaces a group
//!   whole out of a payload written by hand and runs `Project::check_group`
//!   rather than the patch path.
//!
//! What a blend or a gradient DOES to the picture is the compositor's claim
//! and cannot be made here — the core touches no pixel (spec §7); the
//! renderer's half is `tools/proof/phase6_proof.py`. What the recipe
//! carries, including the rule that a layer under a transition is forced
//! back to `normal`, is `recipe.rs`'s and is proved in
//! `evaluate_tests.rs`. This file owns the SHAPE, the RANGES and where the
//! two fields travel.

mod common;

use serde_json::{json, Value};

use common::{array, at, num, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails these tests instead of moving with
/// them.
const SEC: i64 = 600_000;

/// Every `BlendMode` spelling, in declaration order. The list is the test's
/// statement of the discriminant: a mode added to the model and not to this
/// line is a mode this file does not round-trip.
const BLEND_MODES: [&str; 8] = [
    "normal",
    "multiply",
    "screen",
    "add",
    "overlay",
    "darken",
    "lighten",
    "difference",
];

// ---- fixtures ------------------------------------------------------------

fn video_media(id: u32) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/{id}.mov"), "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

/// One media, one track (id 2), a 10 s media clip (id 11) and a 5 s shape
/// clip (id 12), at `version` and spelled the way a file of that version
/// was written: no `blend` and no `gradient` key anywhere.
///
/// Two clips because version 6's two keys live in two different groups and
/// neither op will touch the other's: `set_video` needs a clip with video
/// props and `set_shape` needs one with shape props. The media clip carries
/// a `spotlight` and the shape clip a `fill`, so both key-order claims below
/// are about keys that both exist, and the `fill` is what the precedence
/// test needs to still be there afterwards.
fn one_clip(version: u32) -> Value {
    json!({
        "version": version,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [video_media(1)],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            {
                "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
                "source": { "kind": "media", "media": 1, "in": 0 },
                "video": {
                    "opacity": 0.9,
                    "spotlight": { "shape": "rect", "x": 0.0, "y": 0.0, "width": 480.0,
                                   "height": 270.0, "feather": 40.0, "dim": 0.6, "zoom": 1.0 }
                },
                "audio": {}
            },
            {
                "id": 12, "track": 2, "start": 10 * SEC, "duration": 5 * SEC,
                "source": { "kind": "shape" },
                "video": {},
                "shape": { "kind": "rectangle", "width": 400.0, "height": 300.0,
                           "fill": [0.2, 0.4, 0.8, 1.0] }
            }
        ],
        "next_id": 13
    })
}

/// [`one_clip`] at the current version — the handle the op tests patch.
fn plain() -> Handle {
    Handle::from_value(&one_clip(6))
}

/// A gradient with every field away from its default and both nullable
/// neighbours untouched: three stops rather than two, a kind that is not
/// the default, a non-zero angle, and a translucent stop so the alpha
/// channel is exercised too. A field that silently fell back to its default
/// on read would fail the round trip rather than pass it by luck.
fn sunset() -> Value {
    json!({
        "kind": "radial",
        "stops": [
            { "at": 0.0, "color": [1.0, 0.25, 0.0, 1.0] },
            { "at": 0.35, "color": [1.0, 0.75, 0.2, 0.8] },
            { "at": 1.0, "color": [0.1, 0.0, 0.35, 1.0] }
        ],
        "angle": 135.0
    })
}

/// [`one_clip`] as a version-6 file holds it: the media clip blending, the
/// shape clip carrying [`sunset`] over the fill it already had.
fn styled() -> Value {
    let mut project = one_clip(6);
    project["clips"][0]["video"]["blend"] = json!("multiply");
    project["clips"][1]["shape"]["gradient"] = sunset();
    project
}

/// A `set_video` op carrying `patch`, aimed at the media clip.
fn set_video(patch: Value) -> Value {
    json!({ "op": "set_video", "clips": [11], "patch": patch })
}

/// A `set_shape` op carrying `patch`, aimed at the shape clip.
fn set_shape(patch: Value) -> Value {
    json!({ "op": "set_shape", "clips": [12], "patch": patch })
}

// ---- reading older files -------------------------------------------------

fn assert_unstyled(project: &Value) {
    assert_eq!(at(project, "/version"), &json!(8));
    assert_eq!(at(project, "/clips/0/video/blend"), &json!("normal"));
    assert_eq!(at(project, "/clips/1/video/blend"), &json!("normal"));
    assert_eq!(at(project, "/clips/1/shape/gradient"), &Value::Null);
    // The neighbours a version-6 reader adds nothing to, so a file that
    // gained two defaulted keys gained ONLY those.
    assert_eq!(num(project, "/clips/0/video/opacity"), 0.9);
    assert_eq!(num(project, "/clips/0/video/spotlight/dim"), 0.6);
    assert_eq!(at(project, "/clips/0/video/obscure"), &json!([]));
    assert_eq!(
        at(project, "/clips/1/shape/fill"),
        &json!([0.2, 0.4, 0.8, 1.0])
    );
}

#[test]
fn a_version_five_file_reads_with_a_normal_blend_and_no_gradient() {
    // Both fields carry a serde default, so a file written before the
    // feature existed opens untouched and comes back as a version-6 project
    // drawing exactly what it drew before: source-over, with a flat fill.
    assert_unstyled(&Handle::from_value(&one_clip(5)).value());
}

#[test]
fn every_older_version_reads_the_same_way() {
    // The migration chain still runs underneath: a version-1 file reaches
    // version 6 through `migrate_1_to_2` and then through nothing at all,
    // because none of versions 3, 4, 5 and 6 needed a rewrite.
    for version in [4, 3, 2, 1] {
        assert_unstyled(&Handle::from_value(&one_clip(version)).value());
    }
}

// ---- the round trip ------------------------------------------------------

#[test]
fn the_blend_and_the_gradient_round_trip_exactly() {
    let written = Handle::from_value(&styled()).value();
    assert_eq!(at(&written, "/version"), &json!(8));
    assert_eq!(text(&written, "/clips/0/video/blend"), "multiply");

    let gradient = at(&written, "/clips/1/shape/gradient");
    assert_eq!(text(gradient, "/kind"), "radial");
    assert_eq!(num(gradient, "/angle"), 135.0);
    assert_eq!(array(gradient, "/stops").len(), 3);
    assert_eq!(gradient, &sunset(), "the whole object, key for key");

    // And the fill is still under it: a gradient takes PRECEDENCE in the
    // renderer, it does not consume what it covers.
    assert_eq!(
        at(&written, "/clips/1/shape/fill"),
        &json!([0.2, 0.4, 0.8, 1.0])
    );
}

#[test]
fn every_blend_mode_survives_a_write_and_a_read() {
    // Eight spellings, each persisted, and the declaration ORDER is the
    // shader discriminant. So a renamed variant is silent data loss in a
    // shipped file and a reordered one is every blended layer in every
    // project drawing differently — naming all eight here is what makes
    // either fail a test instead of a user's project.
    // Walked as a CHAIN rather than eight writes from one base, because
    // `normal` is where a fresh clip already is and a write that changes
    // nothing correctly answers `None`. Each step is a real change, and the
    // walk ends by coming back to `normal` from the far end of the list,
    // which is the one write of it that is not the identity.
    let mut handle = plain();
    assert_eq!(
        text(&handle.value(), "/clips/0/video/blend"),
        BLEND_MODES[0]
    );
    for mode in &BLEND_MODES[1..] {
        handle = handle.apply(&set_video(json!({ "blend": mode })));
        assert_eq!(text(&handle.value(), "/clips/0/video/blend"), *mode);
    }
    let back = handle
        .apply(&set_video(json!({ "blend": "normal" })))
        .value();
    assert_eq!(text(&back, "/clips/0/video/blend"), "normal");
}

#[test]
fn blend_is_the_last_key_of_the_video_object() {
    // Declaration order IS key order, and `blend` is the last field of
    // `VideoProps`, so a version-5 file diffed against a version-6 one
    // differs by a trailing key rather than by a re-ordering. Read off the
    // written TEXT, because a `Value` sorts its keys and cannot tell.
    let first = Handle::from_value(&styled()).to_json();
    let position = |needle: &str| {
        first
            .find(needle)
            .unwrap_or_else(|| panic!("no {needle:?} in the written text:\n{first}"))
    };
    assert!(position("\"spotlight\"") < position("\"obscure\""));
    assert!(position("\"obscure\"") < position("\"blend\""));
    // ...and `blend` is still followed by `motion` and nothing else. The
    // CLOSING claim moved onto version 8's key when it was appended, which
    // is the point of writing it this way: what is pinned is that a new key
    // lands at the END of the object, not that any one key is forever last.
    assert!(position("\"blend\"") < position("\"motion\""));
    assert!(
        first.contains("\"blend\": \"multiply\""),
        "blend is not written as the styled fixture asks:\n{first}"
    );
    assert!(
        first.contains("\"motion\": null\n      }"),
        "motion does not close the video object:\n{first}"
    );

    // A second trip through the text is byte-identical to the first, which
    // is what lets Swift compare project strings at all.
    let second = Handle::from_json(&first).to_json();
    assert_eq!(first, second, "a second round trip changed the bytes");
}

#[test]
fn gradient_is_the_last_key_of_the_shape_object() {
    // The same claim for the other group. Scoped to the shape object,
    // because `to`, `from` and `width` are keys of half a dozen other
    // things in the file and the first match would be one of those.
    let first = Handle::from_value(&styled()).to_json();
    let group = &first[first
        .find("\"shape\": {\n        \"kind\": \"rectangle\"")
        .unwrap_or_else(|| panic!("no shape group in the written text:\n{first}"))..];
    let position = |needle: &str| {
        group
            .find(needle)
            .unwrap_or_else(|| panic!("no {needle:?} in the shape group:\n{group}"))
    };
    assert!(position("\"from\"") < position("\"to\""));
    assert!(position("\"to\"") < position("\"gradient\""));
    // ...and it CLOSES the object: the gradient's own last key, its closing
    // brace and the shape object's closing brace, with nothing between.
    assert!(
        first.contains("\"angle\": 135.0\n        }\n      }"),
        "gradient does not close the shape object:\n{first}"
    );
}

// ---- the defaults --------------------------------------------------------

#[test]
fn normal_is_the_default_and_it_is_the_absence_of_the_key() {
    // The property the whole field rests on. An absent key, an explicit
    // `"normal"` and a clip whose video group was never touched must all be
    // the same value — the source-over every project drew before version 6
    // — because the shader reads 0 and a zeroed uniform block, a recipe
    // from an older core and a file with no key have to agree.
    assert_eq!(BLEND_MODES[0], "normal", "normal is the first variant");

    let untouched = plain().value();
    assert_eq!(text(&untouched, "/clips/0/video/blend"), "normal");

    // ...so writing it explicitly onto a clip that already has it changes
    // nothing and registers no undo step — the identity answer every op
    // owes, and the reason the inspector's popup can be set to Normal
    // twice without stacking undo.
    plain().refuses(&set_video(json!({ "blend": "normal" })));

    // And an empty video patch is the same non-answer, so nothing about
    // the new key made an unrelated write start reporting a change.
    plain().refuses(&set_video(json!({})));
}

#[test]
fn a_gradient_added_with_nothing_said_is_black_to_white_left_to_right() {
    // What the inspector's Add produces and what an agent writing
    // `{"gradient": {}}` gets: the container-level `#[serde(default)]` over
    // a `null` base means the type's `Default` in full, so this IS the
    // feature's first impression rather than a formality. Black and white
    // are the two colours that cannot be mistaken for footage, for the
    // canvas or for each other in either appearance; angle 0 is to the
    // RIGHT, the crate's one angle convention.
    let applied = plain().apply(&set_shape(json!({ "gradient": {} }))).value();
    assert_eq!(
        at(&applied, "/clips/1/shape/gradient"),
        &json!({
            "kind": "linear",
            "stops": [
                { "at": 0.0, "color": [0.0, 0.0, 0.0, 1.0] },
                { "at": 1.0, "color": [1.0, 1.0, 1.0, 1.0] }
            ],
            "angle": 0.0
        }),
        "Gradient defaults"
    );
}

#[test]
fn a_stop_added_with_nothing_said_is_opaque_black_at_zero() {
    // `GradientStop`'s own default does a different job from the
    // gradient's: it is what the container-level `#[serde(default)]` fills
    // in, so a stop written as only a position or only a colour is a legal
    // stop rather than a schema error. Both halves, in one gradient.
    let applied = plain()
        .apply(&set_shape(json!({
            "gradient": { "stops": [{ "at": 0.75 }, { "color": [1.0, 0.0, 0.0, 1.0] }] }
        })))
        .value();
    let stops = array(&applied, "/clips/1/shape/gradient/stops");
    assert_eq!(
        stops[0],
        json!({ "at": 0.75, "color": [0.0, 0.0, 0.0, 1.0] }),
        "the colour was filled in"
    );
    assert_eq!(
        stops[1],
        json!({ "at": 0.0, "color": [1.0, 0.0, 0.0, 1.0] }),
        "the position was filled in"
    );
}

// ---- the range checks ----------------------------------------------------

#[test]
fn every_stop_value_is_range_checked_and_the_message_names_it() {
    // The element key is spelled without an index —
    // `shape.gradient.stops[].at` — exactly as `video.filters[].amount` and
    // `video.obscure[].x` are, because the check walks the list and the
    // caller is being told which FIELD it got wrong.
    //
    // `angle` has no case here: it is only required to be finite, which
    // JSON cannot spell, and `clamp_video`'s equivalent for an infinity
    // arriving through an action's end patch is not this file's claim.
    let project = plain();
    let cases: [(Value, &str); 4] = [
        (
            json!({ "gradient": { "stops": [{ "at": -0.1 }, { "at": 1.0 }] } }),
            "shape.gradient.stops[].at must be between 0 and 1, not -0.1",
        ),
        (
            json!({ "gradient": { "stops": [{ "at": 0.0 }, { "at": 1.5 }] } }),
            "shape.gradient.stops[].at must be between 0 and 1, not 1.5",
        ),
        (
            json!({ "gradient": { "stops": [
                { "at": 0.0, "color": [0.0, 0.0, 0.0, 1.0] },
                { "at": 1.0, "color": [1.0, 1.0, 255.0, 1.0] }
            ] } }),
            "shape.gradient.stops[].color must be between 0 and 1, not 255",
        ),
        (
            json!({ "gradient": { "stops": [
                { "at": 0.0, "color": [0.0, 0.0, 0.0, -1.0] },
                { "at": 1.0 }
            ] } }),
            "shape.gradient.stops[].color must be between 0 and 1, not -1",
        ),
    ];
    for (patch, expected) in cases {
        assert_eq!(project.errors(&set_shape(patch)), expected);
    }

    // 0 and 1 are the boundaries and both are inclusive: they are the ends
    // of the ramp, which is where a two-stop gradient lives.
    let applied = project
        .apply(&set_shape(json!({
            "gradient": { "stops": [{ "at": 0.0 }, { "at": 1.0 }] }
        })))
        .value();
    assert_eq!(num(&applied, "/clips/1/shape/gradient/stops/1/at"), 1.0);
}

#[test]
fn the_stop_count_is_named_at_both_ends() {
    let project = plain();

    // One stop is a SOLID COLOUR, and `shape.fill` already spells a solid
    // colour. `CGGradient` would draw it happily, which is exactly why the
    // refusal is in the core: a control that quietly turns into a different
    // control is worse than one that says no.
    let msg = project.errors(&set_shape(
        json!({ "gradient": { "stops": [{ "at": 0.5 }] } }),
    ));
    assert_eq!(
        msg,
        "shape.gradient.stops must hold at least 2 stops, not 1"
    );
    let msg = project.errors(&set_shape(json!({ "gradient": { "stops": [] } })));
    assert_eq!(
        msg,
        "shape.gradient.stops must hold at least 2 stops, not 0"
    );

    // And the ceiling is NAMED rather than trimmed, the posture
    // `MAX_FILTERS` and `MAX_OBSCURE` take — though it is 8 where both of
    // those are 4, because those two are shader slots and a gradient is
    // drawn by `CGGradient` on the CPU, which has none.
    let nine: Vec<Value> = (0..9)
        .map(|i| json!({ "at": f64::from(i) / 8.0 }))
        .collect();
    let msg = project.errors(&set_shape(json!({ "gradient": { "stops": nine } })));
    assert_eq!(msg, "shape.gradient.stops must hold at most 8 stops, not 9");

    // Eight is the boundary and it is inclusive.
    let eight: Vec<Value> = (0..8)
        .map(|i| json!({ "at": f64::from(i) / 7.0 }))
        .collect();
    let applied = project
        .apply(&set_shape(json!({ "gradient": { "stops": eight } })))
        .value();
    assert_eq!(array(&applied, "/clips/1/shape/gradient/stops").len(), 8);
}

#[test]
fn an_unsorted_stop_list_is_accepted_on_purpose() {
    // There is deliberately no ordering check, and this test exists so a
    // later reader does not add one. `CGGradient` needs monotonic
    // locations, but a refusal here has a failure mode nobody would
    // accept — dragging one stop past another is how a gradient is edited,
    // and the drag would stop working halfway through — so the renderer
    // sorts and the core stores what it is given, exactly as it does for
    // the ordered `video.filters`.
    let unsorted = json!({
        "kind": "linear",
        "stops": [
            { "at": 0.9, "color": [1.0, 0.0, 0.0, 1.0] },
            { "at": 0.2, "color": [0.0, 1.0, 0.0, 1.0] },
            { "at": 0.5, "color": [0.0, 0.0, 1.0, 1.0] }
        ],
        "angle": 0.0
    });
    let applied = plain()
        .apply(&set_shape(json!({ "gradient": unsorted })))
        .value();
    let stops = array(&applied, "/clips/1/shape/gradient/stops");
    let positions: Vec<f64> = stops.iter().map(|s| num(s, "/at")).collect();
    assert_eq!(
        positions,
        [0.9, 0.2, 0.5],
        "the writer kept the list's own order"
    );
}

#[test]
fn an_unknown_blend_mode_and_an_unknown_gradient_kind_are_refused_by_the_enums() {
    // Both enums are closed, and this is what that bought: there is no
    // neutral value to fall back to — a mode the shader has no constant for
    // and a geometry `CGGradient` has no call for are alike unrepairable —
    // so an unknown one is refused at the serde boundary rather than range
    // checked a long way from the type.
    let project = plain();
    let msg = project.errors(&set_video(json!({ "blend": "muliply" })));
    assert!(
        msg.starts_with("video patch does not match the schema:"),
        "the schema refusal, got {msg:?}"
    );
    assert!(
        msg.contains("unknown variant `muliply`"),
        "the message names the variant, got {msg:?}"
    );

    let msg = project.errors(&set_shape(json!({ "gradient": { "kind": "conic" } })));
    assert!(
        msg.contains("unknown variant `conic`"),
        "the message names the variant, got {msg:?}"
    );
}

#[test]
fn an_unknown_key_inside_the_gradient_is_named_like_any_other() {
    // `check_keys` can only look inside an optional object against a
    // POPULATED reference — the group's template — and a shape whose
    // `gradient` is `null` gives it none of its own. So `Group::template()`
    // has to populate one, beside `stroke` and `fill`, or serde drops
    // `angel` on the floor and `set_shape` answers that the patch applied
    // while the shape kept the gradient it had. `schema_v4.rs` makes the
    // same claim for a region and `schema_v5.rs` for an animation; it is
    // the same trap each time.
    let project = plain();
    // The failure this can have is a SILENT one — the patch applies and the
    // misspelt key is simply gone — so the panic says what to add rather
    // than leaving the next reader to work it out from "expected an error".
    let refusal = |patch: Value| match project.try_apply(&set_shape(patch)) {
        Err(msg) => msg,
        Ok(_) => panic!(
            "a misspelt key inside a gradient was DROPPED in silence. \
             `Group::template()`'s Shape arm (core/src/edit_props.rs) must \
             populate `gradient: Some(Gradient::default())`, the way its \
             Video arm populates `obscure` and its Text arm `animation` — \
             `check_keys` can only look inside an optional object, or inside \
             the elements of an array, against a populated reference, and \
             `Gradient::default()`'s two stops are what give the stop list \
             one."
        ),
    };
    let msg = refusal(json!({ "gradient": { "kind": "linear", "angel": 45.0 } }));
    assert_eq!(msg, "unknown key \"gradient.angel\" in a shape patch");

    // ...and inside a STOP, which is the schema's third array of objects
    // after `video.filters` and `video.obscure`. The template's gradient
    // has to carry a stop for the same reason its `obscure` carries a
    // region: the array arm reads the FIRST element as the reference for
    // every element it is given, and an empty list is no reference at all.
    let msg = refusal(json!({
        "gradient": { "stops": [{ "at": 0.0 }, { "at": 1.0, "colour": [1.0, 0.0, 0.0, 1.0] }] }
    }));
    assert_eq!(
        msg,
        "unknown key \"gradient.stops.colour\" in a shape patch"
    );
}

// ---- precedence, and clearing --------------------------------------------

#[test]
fn a_gradient_does_not_clear_the_fill_and_null_puts_it_back() {
    // The precedence rule lives in the RENDERER, which prefers the gradient
    // while it is non-null, and not in an op that consumes the fill on its
    // way past. That is what makes `{"gradient": null}` an exact inverse:
    // the inspector's Reset restores the colour that was underneath rather
    // than leaving an invisible shape.
    let styled = plain().apply(&set_shape(json!({ "gradient": sunset() })));
    let value = styled.value();
    assert_eq!(text(&value, "/clips/1/shape/gradient/kind"), "radial");
    assert_eq!(
        at(&value, "/clips/1/shape/fill"),
        &json!([0.2, 0.4, 0.8, 1.0]),
        "the fill survived the gradient"
    );

    let cleared = styled
        .apply(&set_shape(json!({ "gradient": null })))
        .value();
    assert_eq!(at(&cleared, "/clips/1/shape/gradient"), &Value::Null);
    assert_eq!(
        at(&cleared, "/clips/1/shape/fill"),
        &json!([0.2, 0.4, 0.8, 1.0]),
        "the fill is back on its own"
    );

    // And clearing a gradient that is already absent changes nothing, so it
    // registers no undo step — the identity answer every op owes.
    Handle::from_value(&cleared).refuses(&set_shape(json!({ "gradient": null })));
}

#[test]
fn a_line_stores_and_checks_a_gradient_it_will_never_draw() {
    // `Line` and `Arrow` have no area, so the renderer ignores a gradient
    // on them and the inspector disables the rows — but the core does NOT
    // refuse one. `shape.radius` is the precedent exactly: every kind
    // carries it, only the rectangle reads it. A property refused per kind
    // would mean the kind popup had to CLEAR that property on its way past,
    // and a value a popup silently deleted is work nobody can get back.
    let applied = plain()
        .apply(&set_shape(json!({ "kind": "line", "gradient": sunset() })))
        .value();
    assert_eq!(text(&applied, "/clips/1/shape/kind"), "line");
    assert_eq!(at(&applied, "/clips/1/shape/gradient"), &sunset());

    // Stored, and range-checked like any other: ignoring a value is not
    // the same as not policing it, or a kind flip would smuggle an illegal
    // gradient into a rectangle.
    let msg = plain().errors(&set_shape(json!({
        "kind": "arrow", "gradient": { "stops": [{ "at": 0.5 }] }
    })));
    assert_eq!(
        msg,
        "shape.gradient.stops must hold at least 2 stops, not 1"
    );
}

// ---- where the two fields travel -----------------------------------------

/// A Copy payload whose one clip carries both new keys — the shape
/// `paste_attributes` reads, written by hand the way a pasteboard from
/// another document would be.
fn payload_with(blend: &str, gradient: Value) -> Value {
    json!({
        "clips": [{
            "id": 90, "track": 0, "start": 0, "duration": 2 * SEC,
            "source": { "kind": "shape" },
            "video": { "opacity": 0.4, "blend": blend },
            "shape": { "kind": "ellipse", "width": 200.0, "height": 200.0,
                       "fill": [1.0, 1.0, 1.0, 1.0], "gradient": gradient }
        }],
        "media": [], "nests": []
    })
}

#[test]
fn paste_attributes_carries_both_and_re_checks_them() {
    // `paste_attributes` replaces a group WHOLE out of a payload that never
    // went through a patch — struct-update syntax, so both new fields
    // travel with Paste Attributes with no code of their own, which is
    // right (a blend and a gradient are a LOOK, which is what the command
    // pastes) but ships silently unless something pins it. Both groups the
    // two sides share are copied, since the op was sent with no `groups`.
    let landed = plain()
        .apply(&json!({
            "op": "paste_attributes", "clips": [12],
            "payload": payload_with("overlay", sunset())
        }))
        .value();
    assert_eq!(text(&landed, "/clips/1/video/blend"), "overlay");
    assert_eq!(num(&landed, "/clips/1/video/opacity"), 0.4);
    assert_eq!(at(&landed, "/clips/1/shape/gradient"), &sunset());
    // ...and the clip the payload was not aimed at is untouched.
    assert_eq!(text(&landed, "/clips/0/video/blend"), "normal");

    // The payload is the one caller that runs `Project::check_group` rather
    // than the patch path, so a gradient the inspector would refuse is
    // refused here too, with the same message, rather than being smuggled
    // past the ranges by a hand-written pasteboard.
    let msg = plain().errors(&json!({
        "op": "paste_attributes", "clips": [12],
        "payload": payload_with("screen", json!({ "stops": [{ "at": 0.0 }] }))
    }));
    assert_eq!(
        msg,
        "shape.gradient.stops must hold at least 2 stops, not 1"
    );
}
