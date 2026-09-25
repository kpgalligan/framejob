//! Black-box tests for what format version 5 added — `text.animation`, the
//! reveal a text layer arrives and leaves with (road map 2, phase 4c) —
//! driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Seven things are pinned here, and each is a promise the rest of phase 4
//! leans on:
//!
//! - **Every older file still opens.** The field is an `Option` and
//!   defaults to `None`, so there is no migration step and a version-1, -2,
//!   -3 or -4 file reads back with no animation at all, stamped at the
//!   current version — 6 since phase 6, which is why the assertions below
//!   name it rather than 5.
//!   The BUMP is still the point, and this is the version where it looks
//!   most like paperwork: unknown keys are ignored at every level by design
//!   (`model.rs`'s module doc), so without the version gate a version-4
//!   build would open a version-5 file, drop every animation, and write the
//!   loss back over the original on the next save — with the project still
//!   opening and the text still on screen, which is what makes it quiet.
//!   That gate itself is `schema_v3.rs`'s claim and is not restated here.
//! - **`animation` follows `width` and precedes version 9's `case`**, read
//!   off the written TEXT, because a parsed `Value` sorts its keys and
//!   cannot tell. Declaration order is key order, so a version-4 file
//!   diffed against a version-5 one differed by a trailing key rather than
//!   by a re-ordering; which key CLOSES the object is `schema_v9.rs`'s
//!   claim now.
//! - **An animation added with nothing said takes the documented
//!   defaults** — a one-second typewriter that does not un-reveal. That is
//!   the schema's one opinion here, and `TextAnimation::default` argues it:
//!   a default has to be visibly something the moment it is switched on,
//!   and `out` has to be nothing, because an un-reveal is a choice about
//!   the end of a shot rather than a convenience.
//! - **Both durations are policed by `set_text`, naming the offending key
//!   and number.** They are durations, so 0 is legal and a negative one is
//!   a sign mistake; `Ticks` is an `i64`, so the sign is the only thing
//!   left for a check to make.
//! - **A misspelt key INSIDE the animation is refused by name.** The
//!   unknown-key check can only descend into an optional object against a
//!   populated reference, so the `animation` in `Group::template()` is what
//!   stands between a typo and serde dropping it while `set_text` reports
//!   success — `schema_v4.rs` makes the same claim for a region, and it is
//!   the same trap.
//! - **An unknown KIND is refused too**, by serde rather than by a range
//!   check, which is the whole argument for closing the enum: there is no
//!   neutral animation to fall back to.
//! - **The same checks are reachable from `paste_attributes`**, which
//!   replaces the text group whole out of a payload written by hand and
//!   therefore carries an animation from one clip to another for free.
//!
//! What an animation DOES to the picture is the compositor's claim and
//! cannot be made here — the core touches no pixel (spec §7). The per-frame
//! reveal the core computes FROM this field is `recipe.rs`'s, and its tests
//! are with it. This file owns the SHAPE, the RANGES and where the field
//! travels.

mod common;

use serde_json::{json, Value};

use common::{array, at, int, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails these tests instead of moving with
/// them.
const SEC: i64 = 600_000;

// ---- fixtures ------------------------------------------------------------

/// One track (id 2) and one 10 s text clip (id 11) carrying a text group
/// with a `width` and a `backdrop`, at `version` and spelled the way a file
/// of that version was written: no `animation` key anywhere.
///
/// The two neighbours are deliberate. `width` is the field `animation` now
/// follows, so the key-order claim is about two keys that both exist, and
/// `backdrop` is the optional sub-object the reader must leave alone while
/// it adds an absent one beside it.
fn one_clip(version: u32) -> Value {
    json!({
        "version": version,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "text" },
            "video": {},
            "text": {
                "content": "Hello",
                "width": 900.0,
                "backdrop": { "color": [0.0, 0.0, 0.0, 0.5], "padding": 10.0, "radius": 4.0 }
            }
        }],
        "next_id": 12
    })
}

/// [`one_clip`] at the current version — the handle the op tests patch.
fn plain() -> Handle {
    Handle::from_value(&one_clip(6))
}

/// Every field away from its default: a word fade rather than the default
/// typewriter, a non-default `in`, and an `out` that is not 0. A field that
/// silently fell back to its default on read would fail the round trip
/// rather than pass it by luck.
fn word_fade() -> Value {
    json!({ "kind": "word_fade", "in": SEC / 2, "out": (3 * SEC) / 4 })
}

/// [`one_clip`] as a version-5 file holds it.
fn animated() -> Value {
    let mut project = one_clip(5);
    project["clips"][0]["text"]["animation"] = word_fade();
    project
}

/// A `set_text` op carrying `patch`.
fn set_text(patch: Value) -> Value {
    json!({ "op": "set_text", "clips": [11], "patch": patch })
}

// ---- reading older files -------------------------------------------------

fn assert_no_animation(project: &Value) {
    assert_eq!(at(project, "/version"), &json!(10));
    assert_eq!(at(project, "/clips/0/text/animation"), &Value::Null);
    // The neighbours a version-5 reader adds nothing to, so a file that
    // gained an absent animation gained ONLY that.
    assert_eq!(at(project, "/clips/0/text/width"), &json!(900.0));
    assert_eq!(at(project, "/clips/0/text/backdrop/padding"), &json!(10.0));
    assert_eq!(at(project, "/clips/0/text/outline"), &Value::Null);
}

#[test]
fn a_version_four_file_reads_with_no_animation() {
    // The field carries a serde default, so a file written before the
    // feature existed opens untouched and comes back as a version-5
    // project animating nothing.
    assert_no_animation(&Handle::from_value(&one_clip(4)).value());
}

#[test]
fn every_older_version_reads_the_same_way() {
    // The migration chain still runs underneath: a version-1 file reaches
    // version 5 through `migrate_1_to_2` and then through nothing at all,
    // because none of versions 3, 4 and 5 needed a rewrite.
    assert_no_animation(&Handle::from_value(&one_clip(3)).value());
    assert_no_animation(&Handle::from_value(&one_clip(2)).value());
    assert_no_animation(&Handle::from_value(&one_clip(1)).value());
}

// ---- the round trip ------------------------------------------------------

#[test]
fn the_animation_round_trips_exactly() {
    let written = Handle::from_value(&animated()).value();
    assert_eq!(at(&written, "/version"), &json!(10));

    let animation = at(&written, "/clips/0/text/animation");
    assert_eq!(text(animation, "/kind"), "word_fade");
    assert_eq!(int(animation, "/in"), SEC / 2);
    assert_eq!(int(animation, "/out"), (3 * SEC) / 4);
    assert_eq!(animation, &word_fade(), "the whole object, key for key");
}

#[test]
fn every_kind_survives_a_write_and_a_read() {
    // The enum is closed at three and each spelling is persisted, so a
    // renamed variant is a silent data loss in a shipped file. Naming all
    // three here is what makes a rename fail a test instead of a user's
    // project.
    for kind in ["typewriter", "word_fade", "line_rise"] {
        let applied = plain()
            .apply(&set_text(json!({ "animation": { "kind": kind } })))
            .value();
        assert_eq!(text(&applied, "/clips/0/text/animation/kind"), kind);
    }
}

#[test]
fn animation_follows_width_and_precedes_the_version_nine_keys() {
    // Declaration order IS key order. `animation` was the last field of
    // `TextProps` at version 5, so a version-4 file diffed against a
    // version-5 one differed by a trailing key rather than by a
    // re-ordering; version 9 appended `case`, `words` and `word_style`
    // after it, and the claim about which key CLOSES the text object moved
    // to `schema_v9.rs` with them. Read off the written TEXT, because a
    // `Value` sorts its keys and cannot tell.
    let first = Handle::from_value(&animated()).to_json();
    // Scoped to the text object, because `width` is also a key of the
    // canvas and of every media entry, and the first match in the whole
    // file would be one of those rather than the one being placed.
    let group = &first[first
        .find("\"text\": {")
        .unwrap_or_else(|| panic!("no text group in the written text:\n{first}"))..];
    let position = |needle: &str| {
        group
            .find(needle)
            .unwrap_or_else(|| panic!("no {needle:?} in the text group:\n{group}"))
    };
    assert!(position("\"backdrop\"") < position("\"width\""));
    assert!(position("\"width\"") < position("\"animation\""));
    assert!(position("\"animation\"") < position("\"case\""));

    // A second trip through the text is byte-identical to the first, which
    // is what lets Swift compare project strings at all.
    let second = Handle::from_json(&first).to_json();
    assert_eq!(first, second, "a second round trip changed the bytes");
}

// ---- the defaults --------------------------------------------------------

#[test]
fn an_animation_added_with_nothing_said_takes_the_documented_defaults() {
    // What the inspector's checkbox produces, and the schema's one opinion
    // here: a one-second typewriter that does not un-reveal. The kind is
    // `Filter::default`'s argument — a default has to be visibly something
    // the moment it is switched on — and `out` is 0 because an un-reveal is
    // a decision about the end of a shot, not a convenience.
    let applied = plain().apply(&set_text(json!({ "animation": {} }))).value();
    assert_eq!(
        at(&applied, "/clips/0/text/animation"),
        &json!({ "kind": "typewriter", "in": SEC, "out": 0 }),
        "TextAnimation defaults"
    );
}

// ---- the range checks ----------------------------------------------------

#[test]
fn both_durations_are_range_checked_and_the_message_names_them() {
    // `in` and `out` are DURATIONS, so 0 is legal — it means that end of
    // the animation does not happen — and a negative one is a sign mistake
    // rather than a request to run the reveal backwards. The message names
    // the dotted JSON path, never the Rust one, so `in` is spelled the way
    // the file spells it and not `r#in`.
    let project = plain();
    let cases: [(Value, &str); 2] = [
        (
            json!({ "animation": { "in": -1 } }),
            "text.animation.in must not be negative, not -1",
        ),
        (
            json!({ "animation": { "kind": "line_rise", "out": -600000 } }),
            "text.animation.out must not be negative, not -600000",
        ),
    ];
    for (patch, expected) in cases {
        assert_eq!(project.errors(&set_text(patch)), expected);
    }

    // Zero is the boundary and it is inclusive, on both ends at once: an
    // animation with neither half is legal for the same reason a filter at
    // amount 0 is, and refusing it would make the inspector's two fields
    // unable to reach their own minimum.
    let applied = project
        .apply(&set_text(json!({ "animation": { "in": 0, "out": 0 } })))
        .value();
    assert_eq!(
        at(&applied, "/clips/0/text/animation"),
        &json!({ "kind": "typewriter", "in": 0, "out": 0 })
    );
}

#[test]
fn an_unknown_key_inside_the_animation_is_named_like_any_other() {
    // `check_keys` can only look inside an optional object against a
    // POPULATED reference — the group's template — and a clip whose
    // `animation` is `null` gives it none of its own. That is why
    // `Group::template()` populates one, beside `outline`, `backdrop` and
    // `width`: without it the object arm falls through, serde drops `kynd`
    // on the floor, and `set_text` answers that the patch applied while the
    // clip kept the animation it had. `schema_v4.rs` makes the same claim
    // for a misspelling inside a region, and it is the same trap.
    let project = plain();
    let msg = project.errors(&set_text(json!({
        "animation": { "kind": "typewriter", "kynd": "line_rise" }
    })));
    assert_eq!(msg, "unknown key \"animation.kynd\" in a text patch");

    // And it is found on a clip that already HAS an animation too, so the
    // check is the template's and not the clip's current value.
    let animated = project.apply(&set_text(json!({ "animation": word_fade() })));
    let msg = animated.errors(&set_text(json!({ "animation": { "duration": 1 } })));
    assert_eq!(msg, "unknown key \"animation.duration\" in a text patch");
}

#[test]
fn an_unknown_kind_is_refused_by_the_enum_itself() {
    // The enum is closed, and this is what that bought: there is no neutral
    // animation to fall back to the way a filter's `amount` can fall back
    // to 0, so a kind nothing downstream could draw is refused at the serde
    // boundary rather than range-checked a long way from the type. The
    // refusal names the path in the key walk's spelling (D1·1,
    // kpgalligan/reelcut#2; it used to open "text patch does not match the
    // schema:" and say nothing of where).
    let msg = plain().errors(&set_text(json!({ "animation": { "kind": "fade" } })));
    assert!(
        msg.starts_with("bad value at \"animation.kind\" in a text patch: "),
        "the schema refusal, with its path, got {msg:?}"
    );
    assert!(
        msg.contains("unknown variant `fade`"),
        "the message names the variant, got {msg:?}"
    );
}

#[test]
fn an_explicit_null_clears_the_animation() {
    // `animation` is an `Option`, like `outline` and `backdrop`, so the
    // op-table rule applies to it unchanged: absent keeps, `null` clears.
    // That is the whole reason the inspector's Reset and the agent's patch
    // can turn an animation off at all.
    let animated = plain().apply(&set_text(json!({ "animation": word_fade() })));
    assert_eq!(
        text(&animated.value(), "/clips/0/text/animation/kind"),
        "word_fade"
    );

    let cleared = animated
        .apply(&set_text(json!({ "animation": null })))
        .value();
    assert_eq!(at(&cleared, "/clips/0/text/animation"), &Value::Null);

    // And clearing an animation that is already absent changes nothing, so
    // it registers no undo step — the identity answer every op owes.
    Handle::from_value(&cleared).refuses(&set_text(json!({ "animation": null })));
}

// ---- where the animation travels -----------------------------------------

/// A Copy payload whose one clip carries an animation — the shape
/// `paste_attributes` reads, written by hand the way a pasteboard from
/// another document would be.
fn payload_with(animation: Value) -> Value {
    json!({
        "clips": [{
            "id": 90, "track": 0, "start": 0, "duration": 2 * SEC,
            "source": { "kind": "text" },
            "text": { "content": "the source's words", "size": 48.0, "animation": animation }
        }],
        "media": [], "nests": []
    })
}

#[test]
fn paste_attributes_carries_the_animation_and_re_checks_it() {
    // `paste_attributes` replaces the text group WHOLE out of a payload
    // that never went through a patch — struct-update syntax keeping only
    // `content` — so an animation travels with Paste Attributes with no
    // code of its own, which is right (it is styling, like the backdrop)
    // but ships silently unless something pins it.
    let landed = plain()
        .apply(&json!({
            "op": "paste_attributes", "clips": [11], "payload": payload_with(word_fade())
        }))
        .value();
    // A copied group now uses the same check-then-snap rule as a patch:
    // 450 000 is halfway between 440 000 and 460 000 at 30 fps.
    assert_eq!(
        at(&landed, "/clips/0/text/animation"),
        &json!({ "kind": "word_fade", "in": 300_000, "out": 460_000 })
    );
    assert_eq!(at(&landed, "/clips/0/text/size"), &json!(48.0));
    // ...and `content` is the one thing that stays behind, so pasting a
    // look does not paste the words.
    assert_eq!(text(&landed, "/clips/0/text/content"), "Hello");

    // The payload is the one caller that runs `Project::check_group` rather
    // than the patch path, so a value the inspector would refuse is refused
    // here too, with the same message, rather than being smuggled past the
    // ranges by a hand-written pasteboard.
    let msg = plain().errors(&json!({
        "op": "paste_attributes", "clips": [11],
        "payload": payload_with(json!({ "kind": "line_rise", "in": -2 }))
    }));
    assert_eq!(msg, "text.animation.in must not be negative, not -2");
}

// ---- the frame grid ------------------------------------------------------

#[test]
fn the_animations_timings_are_snapped_to_the_frame_grid_by_the_patch_door() {
    // The core's Times rule — every tick value that reaches the model is
    // snapped first (core/CLAUDE.md) — holds for these two as of D1·2
    // (kpgalligan/reelcut#3). It did not before: the comment beside the
    // check in `props_check.rs` said the inspector snapped, which left an
    // agent's value sub-frame and made two callers of one op disagree.
    // The canvas is 30 fps, so a frame is 20 000 ticks.
    let project = plain();
    let snapped = project
        .apply(&set_text(json!({
            "animation": { "kind": "line_rise", "in": 310_000, "out": 9_999 }
        })))
        .value();
    assert_eq!(
        at(&snapped, "/clips/0/text/animation"),
        &json!({ "kind": "line_rise", "in": 320_000, "out": 0 }),
        "15.5 frames rounds half away from zero; half a frame is no un-reveal at all"
    );

    // The sign check runs on what the CALLER sent, so a negative timing is
    // still named rather than snapped into a legal 0.
    assert_eq!(
        project.errors(&set_text(
            json!({ "animation": { "kind": "typewriter", "in": -1 } })
        )),
        "text.animation.in must not be negative, not -1"
    );

    // A value already on the grid that changes nothing is an identity —
    // no undo step — and so is a sub-frame value that snaps onto it.
    let on_the_grid = json!({ "kind": "line_rise", "in": 320_000, "out": 0 });
    let handle = Handle::from_value(&snapped);
    handle.refuses(&set_text(json!({ "animation": on_the_grid })));
    handle.refuses(&set_text(json!({ "animation": { "in": 320_000 + 9_999 } })));

    // A NEW text clip's animation lands on the same grid: it is the same
    // merge and the same check one file over (`edit_clip.rs`), and a door
    // that snapped only some of the time would be the exception this
    // ticket removed.
    let born = plain().apply(&json!({
        "op": "add_text_clip", "track": 2, "at": 12 * SEC,
        "text": { "content": "New", "animation": { "kind": "typewriter", "in": 310_000 } }
    }));
    let project = born.value();
    let clips = array(&project, "/clips");
    assert_eq!(
        at(clips.last().expect("the new clip"), "/text/animation/in"),
        &json!(320_000)
    );

    // The FILE is not snapped, which is the same split the filter entry
    // has: `word_fade`'s `out` is 22.5 frames and opens exactly as written
    // (`an_animation_round_trips_whole` reads it back key for key). A file
    // opens as what it says; an op is what puts a value on the grid.
    let from_a_file = Handle::from_value(&animated()).value();
    assert_eq!(
        at(&from_a_file, "/clips/0/text/animation/out"),
        &json!(450_000)
    );
}
