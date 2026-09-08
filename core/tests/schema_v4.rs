//! Black-box tests for what format version 4 added — `video.obscure`, the
//! regions of a layer hidden behind a blur or a pixelation (road map 2,
//! phase 3c) — driven through the C FFI exactly as `ReelCore.swift` drives
//! it.
//!
//! Seven things are pinned here, and each is a promise the rest of phase 3
//! leans on:
//!
//! - **Every older file still opens.** The list carries a serde default —
//!   the empty one — so there is no migration step and a version-1, -2 or
//!   -3 file reads back with no regions at all, stamped at the current
//!   version — 5 since phase 4c, which is why the assertions below name it
//!   rather than 4. The
//!   BUMP is still the point: unknown keys are ignored at every level by
//!   design (`model.rs`'s module doc), so without the version gate a
//!   version-3 build would open a version-4 file, drop every region, and
//!   write the loss back over the original on the next save. That gate is
//!   `schema_v3.rs`'s claim and is not restated here.
//! - **`obscure` is the LAST key of the `video` object**, read off the
//!   written TEXT, because a parsed `Value` sorts its keys and cannot tell.
//!   Declaration order is key order, so a version-3 file diffed against a
//!   version-4 one differs by a trailing key rather than by a re-ordering.
//! - **A region added with nothing said takes the documented defaults** —
//!   the spotlight's 480 × 270 box, pixelated at full strength. Those two
//!   are the schema's only opinionated numbers here and the whole feature
//!   is judged on them: a region that only half hides has failed at the one
//!   job it has.
//! - **Every value is policed by `set_video`, naming the offending key and
//!   number**, including the `MAX_OBSCURE` shader budget — which is NAMED
//!   rather than trimmed, for `MAX_FILTERS`' reason sharpened: a dropped
//!   region is not a control that does nothing, it is the face it was drawn
//!   over, still on screen.
//! - **A misspelt key INSIDE a region is refused by name.** `obscure` is
//!   the schema's second array of objects, and the unknown-key check can
//!   only descend into an array against a reference element, so the region
//!   in `Group::template()` is what stands between a typo and serde
//!   dropping it while `set_video` reports success.
//! - **The same check is reachable from `paste_attributes`**, which copies
//!   the video group whole out of a payload written by hand. It runs
//!   `Project::check_group`, not the patch path, so a payload cannot smuggle
//!   in a region the inspector would refuse.
//! - **Every layer of the frame recipe carries the list**, present or
//!   empty, because a stored region the compositor is never told about
//!   hides nothing.
//!
//! What a region DOES to the picture is the compositor's claim and cannot be
//! made here — the core touches no pixel (spec §7). This file owns the
//! SHAPE, the RANGES and where the field travels.

mod common;

use serde_json::{json, Value};

use common::{array, at, num, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails these tests instead of moving with
/// them.
const SEC: i64 = 600_000;

// ---- fixtures ------------------------------------------------------------

fn video_media(id: u32) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/{id}.mov"), "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

/// One media, one track (id 2), one 10 s media clip (id 11), at `version`
/// and spelled the way a file of that version was written: no `obscure` key
/// anywhere.
fn one_clip(version: u32) -> Value {
    json!({
        "version": version,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [video_media(1)],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": {}, "audio": {}
        }],
        "next_id": 12
    })
}

/// [`one_clip`] with the video group present and empty — the handle the op
/// tests patch.
fn plain() -> Handle {
    Handle::from_value(&one_clip(4))
}

/// Two regions, every field away from its default and the two of each
/// closed enum both used: an ellipse blurring a face, a rectangle
/// pixelating a password field. A field that silently fell back to its
/// default on read would fail the round trip rather than pass it by luck.
fn two_regions() -> Value {
    json!([
        { "shape": "ellipse", "x": -220.5, "y": 140.25, "width": 260.0, "height": 320.0,
          "feather": 36.0, "kind": "blur", "amount": 0.75 },
        { "shape": "rect", "x": 310.0, "y": -80.0, "width": 640.0, "height": 96.0,
          "feather": 0.0, "kind": "pixelate", "amount": 0.25 }
    ])
}

/// [`one_clip`] as a version-4 file holds it: the clip carrying both
/// regions, and a spotlight too, so the key-order claim below is about two
/// keys that both exist.
fn hidden() -> Value {
    let mut project = one_clip(4);
    project["clips"][0]["video"] = json!({
        "spotlight": { "shape": "rect", "x": 0.0, "y": 0.0, "width": 480.0,
                       "height": 270.0, "feather": 40.0, "dim": 0.6, "zoom": 1.0 },
        "obscure": two_regions()
    });
    project
}

// ---- reading older files -------------------------------------------------

fn assert_no_regions(project: &Value) {
    assert_eq!(at(project, "/version"), &json!(5));
    assert_eq!(at(project, "/clips/0/video/obscure"), &json!([]));
    // The neighbours a version-4 reader adds nothing to, so a file that
    // gained an empty list gained ONLY that.
    assert_eq!(at(project, "/clips/0/video/spotlight"), &Value::Null);
    assert_eq!(at(project, "/clips/0/video/filters"), &json!([]));
}

#[test]
fn a_version_three_file_reads_with_no_hidden_regions() {
    // The list carries a serde default, so a file written before the
    // feature existed opens untouched and comes back as a version-4
    // project hiding nothing.
    assert_no_regions(&Handle::from_value(&one_clip(3)).value());
}

#[test]
fn a_version_two_file_and_a_version_one_file_read_the_same_way() {
    // The migration chain still runs underneath: a version-1 file reaches
    // the current version through `migrate_1_to_2` and then through nothing
    // at all, because no version since — 3, 4 or 5 — has needed a rewrite.
    assert_no_regions(&Handle::from_value(&one_clip(2)).value());
    assert_no_regions(&Handle::from_value(&one_clip(1)).value());
}

// ---- the round trip ------------------------------------------------------

#[test]
fn the_regions_round_trip_exactly() {
    let written = Handle::from_value(&hidden()).value();
    assert_eq!(at(&written, "/version"), &json!(5));

    let regions = array(&written, "/clips/0/video/obscure");
    assert_eq!(regions.len(), 2, "both regions survived");

    assert_eq!(text(&regions[0], "/shape"), "ellipse");
    assert_eq!(text(&regions[0], "/kind"), "blur");
    assert_eq!(num(&regions[0], "/x"), -220.5);
    assert_eq!(num(&regions[0], "/y"), 140.25);
    assert_eq!(num(&regions[0], "/width"), 260.0);
    assert_eq!(num(&regions[0], "/height"), 320.0);
    assert_eq!(num(&regions[0], "/feather"), 36.0);
    assert_eq!(num(&regions[0], "/amount"), 0.75);

    assert_eq!(text(&regions[1], "/shape"), "rect");
    assert_eq!(text(&regions[1], "/kind"), "pixelate");
    assert_eq!(num(&regions[1], "/x"), 310.0);
    assert_eq!(num(&regions[1], "/y"), -80.0);
    assert_eq!(num(&regions[1], "/width"), 640.0);
    assert_eq!(num(&regions[1], "/height"), 96.0);
    assert_eq!(num(&regions[1], "/feather"), 0.0);
    assert_eq!(num(&regions[1], "/amount"), 0.25);

    // Order is the list's own: the regions are applied in it, and the
    // inspector's rows are it, so a writer that sorted would reorder the
    // user's rows under them.
    assert_eq!(
        [text(&regions[0], "/kind"), text(&regions[1], "/kind")],
        ["blur", "pixelate"],
        "the list kept its order"
    );
}

#[test]
fn obscure_is_the_last_key_of_the_video_object() {
    // Declaration order IS key order, and `obscure` is the last field of
    // `VideoProps`, so a version-3 file diffed against a version-4 one
    // differs by a trailing key rather than by a re-ordering. Read off the
    // written TEXT, because a `Value` sorts its keys and cannot tell.
    let first = Handle::from_value(&hidden()).to_json();
    let position = |needle: &str| {
        first
            .find(needle)
            .unwrap_or_else(|| panic!("no {needle:?} in the written text"))
    };
    assert!(position("\"filters\"") < position("\"spotlight\""));
    assert!(position("\"spotlight\"") < position("\"obscure\""));
    // ...and it CLOSES the object: the last region's closing brace, the
    // array's closing bracket and the video object's closing brace, with
    // nothing between them.
    assert!(
        first.contains("\"amount\": 0.25\n          }\n        ]\n      }"),
        "obscure does not close the video object:\n{first}"
    );

    // A second trip through the text is byte-identical to the first, which
    // is what lets Swift compare project strings at all.
    let second = Handle::from_json(&first).to_json();
    assert_eq!(first, second, "a second round trip changed the bytes");
}

// ---- the defaults --------------------------------------------------------

#[test]
fn a_region_added_with_nothing_said_takes_the_documented_defaults() {
    // What the inspector's Add button produces, and the whole feature's
    // one opinion: the spotlight's own 480 x 270 box, so the two region
    // controls put the same rectangle on screen, PIXELATED at full
    // strength. Not the filter's half-strength blur — a region that only
    // half hides has failed at its one job, and a blur at the shader's
    // maximum radius is soft enough to read a large password field
    // through.
    let applied = plain()
        .apply(&json!({ "op": "set_video", "clips": [11], "patch": { "obscure": [{}] } }))
        .value();
    assert_eq!(
        at(&applied, "/clips/0/video/obscure/0"),
        &json!({
            "shape": "rect", "x": 0.0, "y": 0.0, "width": 480.0, "height": 270.0,
            "feather": 20.0, "kind": "pixelate", "amount": 1.0
        }),
        "ObscureRegion defaults"
    );
}

// ---- the range checks ----------------------------------------------------

#[test]
fn every_region_value_is_range_checked_and_the_message_names_it() {
    // The element key is spelled without an index — `video.obscure[].x` —
    // exactly as `video.filters[].amount` is, because the check walks the
    // list and the caller is being told which FIELD it got wrong.
    //
    // `x` and `y` are only required to be finite, which JSON cannot spell,
    // so they have no case here: a centre outside the layer is legitimate
    // (half a region running off the edge of the frame is a picture), and
    // `clamp_video` is what catches an infinity arriving through an
    // action's `end` patch.
    let project = plain();
    let cases: [(Value, &str); 5] = [
        (
            json!({ "obscure": [{ "width": 0.0 }] }),
            "video.obscure[].width must be greater than 0, not 0",
        ),
        (
            json!({ "obscure": [{ "height": -10.0 }] }),
            "video.obscure[].height must be greater than 0, not -10",
        ),
        (
            json!({ "obscure": [{ "feather": -1.0 }] }),
            "video.obscure[].feather must be at least 0, not -1",
        ),
        (
            json!({ "obscure": [{ "amount": 1.5 }] }),
            "video.obscure[].amount must be between 0 and 1, not 1.5",
        ),
        (
            json!({ "obscure": [{ "amount": -0.5 }] }),
            "video.obscure[].amount must be between 0 and 1, not -0.5",
        ),
    ];
    for (patch, expected) in cases {
        let msg = project.errors(&json!({ "op": "set_video", "clips": [11], "patch": patch }));
        assert_eq!(msg, expected);
    }

    // The check reaches the SECOND region too, not just the first: the
    // loop is over the list, and a payload that hid its bad number behind a
    // good one would otherwise walk straight in.
    let msg = project.errors(&json!({
        "op": "set_video", "clips": [11],
        "patch": { "obscure": [{ "amount": 0.5 }, { "amount": 2.0 }] }
    }));
    assert_eq!(msg, "video.obscure[].amount must be between 0 and 1, not 2");
}

#[test]
fn the_region_budget_is_named_rather_than_silently_trimmed() {
    // MAX_OBSCURE is the uniform block's four region slots. The fifth is
    // refused by name for MAX_FILTERS' reason, sharpened: a filter dropped
    // from the next write is a control that did nothing, while a region
    // dropped from the next write is the face it was drawn over, back on
    // screen with nobody told.
    let project = plain();
    let five = json!({ "obscure": [{}, {}, {}, {}, {}] });
    let msg = project.errors(&json!({ "op": "set_video", "clips": [11], "patch": five }));
    assert_eq!(msg, "video.obscure must hold at most 4 regions, not 5");

    // Four is the boundary and it is inclusive.
    let four = json!({ "obscure": [{}, {}, {}, { "kind": "blur" }] });
    let applied = project
        .apply(&json!({ "op": "set_video", "clips": [11], "patch": four }))
        .value();
    assert_eq!(array(&applied, "/clips/0/video/obscure").len(), 4);
    assert_eq!(text(&applied, "/clips/0/video/obscure/3/kind"), "blur");
}

#[test]
fn an_unknown_key_inside_a_region_is_named_like_any_other() {
    // `video.obscure` is the schema's SECOND array of objects, after
    // `video.filters`, and `check_keys` can only look inside an array's
    // elements against a reference element — the first entry of the
    // group's template. That is why `Group::template()` populates one
    // region: without it there is no reference, the array arm returns
    // early, serde drops `amont` on the floor, and `set_video` answers
    // that the patch applied while the region kept the amount it had.
    // Every other misspelling in the crate is an `Err` naming the key, and
    // one inside a region is no different.
    let project = plain();
    let msg = project.errors(&json!({
        "op": "set_video", "clips": [11],
        "patch": { "obscure": [{ "kind": "blur", "amont": 0.5 }] }
    }));
    assert_eq!(msg, "unknown key \"obscure.amont\" in a video patch");

    // Every element is checked against that one reference, not just the
    // first, so a typo hiding behind a good region is caught too. The
    // dotted path carries no index for the same reason `props_check.rs`'s
    // messages do not: the caller is being told which FIELD it got wrong.
    let msg = project.errors(&json!({
        "op": "set_video", "clips": [11],
        "patch": { "obscure": [{ "amount": 0.5 }, { "shape": "rect", "kynd": "blur" }] }
    }));
    assert_eq!(msg, "unknown key \"obscure.kynd\" in a video patch");
}

#[test]
fn an_empty_list_clears_the_regions() {
    // `obscure` is a `Vec`, like `filters`: the array REPLACES rather than
    // merges, so `[]` is how a caller clears the stack and there is no
    // `null` form to send. Every write carries the whole list.
    let hidden = plain().apply(&json!({
        "op": "set_video", "clips": [11], "patch": { "obscure": two_regions() }
    }));
    assert_eq!(array(&hidden.value(), "/clips/0/video/obscure").len(), 2);

    let cleared = hidden
        .apply(&json!({ "op": "set_video", "clips": [11], "patch": { "obscure": [] } }))
        .value();
    assert_eq!(at(&cleared, "/clips/0/video/obscure"), &json!([]));

    // And clearing an already empty list changes nothing, so it registers
    // no undo step — the identity answer every op owes.
    Handle::from_value(&cleared)
        .refuses(&json!({ "op": "set_video", "clips": [11], "patch": { "obscure": [] } }));
}

// ---- where the regions travel --------------------------------------------

/// A Copy payload whose one clip carries `obscure` — the shape
/// `paste_attributes` reads, written by hand the way a pasteboard from
/// another document would be.
fn payload_with(regions: Value) -> Value {
    json!({
        "clips": [{
            "id": 90, "track": 0, "start": 0, "duration": 2 * SEC,
            "source": { "kind": "text" },
            "video": { "opacity": 0.4, "obscure": regions }
        }],
        "media": [], "nests": []
    })
}

#[test]
fn paste_attributes_carries_the_regions_and_re_checks_them() {
    // `paste_attributes` replaces the video group WHOLE out of a payload
    // that never went through a patch, so it is the one caller that runs
    // `Project::check_group` rather than `set_video`'s own check. Both
    // arms matter: a legal list lands...
    let landed = plain()
        .apply(&json!({
            "op": "paste_attributes", "clips": [11], "payload": payload_with(two_regions())
        }))
        .value();
    assert_eq!(array(&landed, "/clips/0/video/obscure").len(), 2);
    assert_eq!(text(&landed, "/clips/0/video/obscure/0/kind"), "blur");
    assert_eq!(num(&landed, "/clips/0/video/opacity"), 0.4);

    // ...and one the inspector would refuse is refused here too, with the
    // same message, rather than being smuggled past the ranges by a
    // hand-written pasteboard.
    let msg = plain().errors(&json!({
        "op": "paste_attributes", "clips": [11],
        "payload": payload_with(json!([{}, {}, {}, {}, {}]))
    }));
    assert_eq!(msg, "video.obscure must hold at most 4 regions, not 5");

    let msg = plain().errors(&json!({
        "op": "paste_attributes", "clips": [11],
        "payload": payload_with(json!([{ "width": -5.0 }]))
    }));
    assert_eq!(msg, "video.obscure[].width must be greater than 0, not -5");
}

// ---- the recipe ----------------------------------------------------------

#[test]
fn every_layer_carries_the_regions_to_the_compositor() {
    // The last hop the core owns: `frame_recipe` is the whole of what the
    // compositor is told about a layer, so a region stored, range-checked,
    // clamped and interpolated but never written here would be a control
    // that changes the document and nothing on screen.
    //
    // The values arrive raw — the recipe's are the EVALUATED props, and
    // `clamp_video` leaves an in-range list alone — so the layer's list is
    // the clip's list, region for region and field for field.
    let handle = plain().apply(&json!({
        "op": "set_video", "clips": [11], "patch": { "obscure": two_regions() }
    }));
    let recipe = handle.recipe(SEC);
    let layer = &array(&recipe, "/layers")[0];
    assert_eq!(at(layer, "/obscure"), &two_regions(), "the layer's regions");
    // And the neighbour it sits beside is untouched: `obscure` is a key of
    // its own, not something folded into the spotlight it shares a frame
    // with.
    assert_eq!(at(layer, "/spotlight"), &Value::Null);
}

#[test]
fn a_layer_with_no_regions_still_carries_the_key() {
    // Emitted unconditionally, exactly as `filters` is (`schema_v2.rs`
    // pins that one): the compositor decodes one recipe shape whether a
    // layer hides anything or not, and a key that came and went with the
    // list would make an absent key mean two different things — no regions
    // here, or an older core that never had them.
    let recipe = plain().recipe(SEC);
    let layer = &array(&recipe, "/layers")[0];
    assert_eq!(at(layer, "/obscure"), &json!([]));
}
