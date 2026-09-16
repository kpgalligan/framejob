//! What a COPY op does with `video.motion` — road map 5 §5e's table, read
//! through the FFI.
//!
//! A preset is anchored to a clip's two ends, and a copy has new ends, so
//! the question every op here answers is which of the three slots it may
//! carry. The table is short and the reasoning is one sentence per row: a
//! SPLIT gives the first half the entrance and the second half the exit,
//! because carrying both to both makes the first half leave at the cut and
//! the second arrive again there — the most visible thing in a shot a
//! viewer is not supposed to see at all. A FREEZE and a BLURRED BACKGROUND
//! mint a new clip and take none of it. A duplicate, a detach and a paste
//! are CLONES with the same ends, so they keep the lot.
//!
//! `text.animation` is here too, and its split row is a DEFECT FIX rather
//! than a new rule: both halves have kept the whole animation since format
//! version 5, so a split caption un-revealed at the cut and re-typed
//! immediately after. It is the same arithmetic one field along, which is
//! why the two live in one file and in one place in `edit_split.rs`.
//!
//! Every claim is about the STORED clip, never about a rendered frame:
//! what a preset does once it is there is `core/tests/motion.rs`'s.

mod common;

use serde_json::{json, Value};

use common::{at, by_id, num, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported.
const SEC: i64 = 600_000;

/// A full motion, every slot filled, so a row that drops the wrong one is
/// visible.
fn full() -> Value {
    json!({
        "in": { "kind": "slide_up", "duration": SEC / 2 },
        "out": { "kind": "zoom_out", "duration": SEC },
        "during": { "kind": "shake", "amount": 0.25, "period": 2 * SEC }
    })
}

/// One ten-second media clip (id 11) on track 2 carrying `full()`, plus an
/// audio-only sibling nowhere near it so `detach_audio` has somewhere to
/// put its twin.
fn moving() -> Handle {
    Handle::from_value(&json!({
        "version": 8,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [{
            "id": 1, "path": "/fixtures/1.mov", "kind": "video",
            "duration": 60 * SEC, "width": 1280, "height": 800, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": { "x": 100.0, "scale": 0.5, "motion": full() },
            "audio": {}
        }],
        "next_id": 12
    }))
}

/// The same timeline with a TEXT clip instead, carrying a `text.animation`
/// with both ramps set.
fn animated() -> Handle {
    Handle::from_value(&json!({
        "version": 8,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "text" }, "video": {},
            "text": {
                "content": "Hello",
                "animation": { "kind": "word_fade", "in": SEC, "out": SEC / 2 }
            }
        }],
        "next_id": 12
    }))
}

/// The two halves of a project split at 5 s: the original id and the minted
/// one, in start order.
fn halves(after: &Value) -> (Value, Value) {
    let clips = common::array(after, "/clips");
    assert_eq!(clips.len(), 2, "a split makes exactly two clips");
    let mut pair = clips.clone();
    pair.sort_by_key(|c| c["start"].as_i64().unwrap_or(0));
    (pair[0].clone(), pair[1].clone())
}

// ---- split ---------------------------------------------------------------

#[test]
fn a_split_leaves_one_entrance_and_one_exit() {
    let after = moving()
        .apply(&json!({ "op": "split", "clips": [11], "at": 5 * SEC }))
        .value();
    let (first, second) = halves(&after);

    // The first half keeps the entrance and gives up the exit...
    assert_eq!(
        at(&first, "/video/motion"),
        &json!({
            "in": { "kind": "slide_up", "duration": SEC / 2 },
            "out": null,
            "during": { "kind": "shake", "amount": 0.25, "period": 2 * SEC }
        })
    );
    // ...and the second the other way round. The DURING survives on both,
    // because it is anchored to neither end — which is also the documented
    // limit (road map 5 §5h): it restarts at every cut.
    assert_eq!(
        at(&second, "/video/motion"),
        &json!({
            "in": null,
            "out": { "kind": "zoom_out", "duration": SEC },
            "during": { "kind": "shake", "amount": 0.25, "period": 2 * SEC }
        })
    );
}

#[test]
fn a_split_of_an_entrance_only_preset_leaves_the_second_half_with_no_motion() {
    // The normalisation, at the one writer besides the patch path that can
    // empty a motion: the second half's only slot is the one the rule takes
    // away, so the field is `null` rather than three nulls.
    let mut source = moving().value();
    source["clips"][0]["video"]["motion"] = json!({ "in": { "kind": "pop", "duration": SEC / 2 } });
    let after = Handle::from_value(&source)
        .apply(&json!({ "op": "split", "clips": [11], "at": 5 * SEC }))
        .value();
    let (first, second) = halves(&after);
    assert_eq!(text(&first, "/video/motion/in/kind"), "pop");
    assert_eq!(at(&second, "/video/motion"), &Value::Null);
}

#[test]
fn a_split_leaves_a_clip_without_motion_exactly_as_it_was() {
    // The rule costs a clip with no preset nothing, which is what lets
    // every existing split test in `edit_tests.rs` re-run unchanged.
    let mut source = moving().value();
    source["clips"][0]["video"]["motion"] = Value::Null;
    let plain = Handle::from_value(&source);
    let after = plain
        .apply(&json!({ "op": "split", "clips": [11], "at": 5 * SEC }))
        .value();
    let (first, second) = halves(&after);
    assert_eq!(at(&first, "/video/motion"), &Value::Null);
    assert_eq!(at(&second, "/video/motion"), &Value::Null);
}

#[test]
fn three_ripple_deleted_ranges_leave_one_arrival_and_one_exit() {
    // `ripple_delete_ranges` cuts right to left through `clear_range`, so
    // every splitter in the crate routes through the one rule — which is
    // the whole reason it lives in `edit_split.rs`. Three spans out of a
    // ten-second clip leave four fragments, and exactly ONE of them may
    // still enter and exactly one still leave.
    let after = moving()
        .apply(&json!({
            "op": "ripple_delete_ranges",
            "ranges": [[SEC, 2 * SEC], [3 * SEC, 4 * SEC], [5 * SEC, 6 * SEC]]
        }))
        .value();
    let clips = common::array(&after, "/clips");
    assert_eq!(clips.len(), 4, "three spans out of one clip leave four");
    let entrances = clips
        .iter()
        .filter(|c| !c["video"]["motion"]["in"].is_null())
        .count();
    let exits = clips
        .iter()
        .filter(|c| !c["video"]["motion"]["out"].is_null())
        .count();
    assert_eq!(entrances, 1, "exactly one fragment still enters");
    assert_eq!(exits, 1, "exactly one fragment still leaves");
    // And it is the FIRST fragment that enters and the LAST that leaves.
    let mut ordered = clips.clone();
    ordered.sort_by_key(|c| c["start"].as_i64().unwrap_or(0));
    assert_eq!(text(&ordered[0], "/video/motion/in/kind"), "slide_up");
    assert_eq!(text(&ordered[3], "/video/motion/out/kind"), "zoom_out");
}

// ---- text.animation ------------------------------------------------------

#[test]
fn a_split_caption_ends_fully_revealed_and_the_second_half_starts_that_way() {
    // The defect fix (road map 5 §5e): both halves used to keep the whole
    // animation, so the first un-revealed at the cut and the second re-typed
    // from nothing. The first half now has no `out` and the second no `in`.
    let after = animated()
        .apply(&json!({ "op": "split", "clips": [11], "at": 5 * SEC }))
        .value();
    let (first, second) = halves(&after);
    assert_eq!(
        at(&first, "/text/animation"),
        &json!({ "kind": "word_fade", "in": SEC, "out": 0 })
    );
    assert_eq!(
        at(&second, "/text/animation"),
        &json!({ "kind": "word_fade", "in": 0, "out": SEC / 2 })
    );
    // Read through the RECIPE, which is where a reveal becomes a number:
    // the first half's last frame is fully revealed and the second half's
    // first frame is too.
    let handle = Handle::from_value(&after);
    let reveal_at = |t: i64| {
        let recipe = handle.recipe(t);
        num(&common::array(&recipe, "/layers")[0], "/source/reveal")
    };
    assert_eq!(
        reveal_at(5 * SEC - 20_000),
        1.0,
        "the first half ends revealed"
    );
    assert_eq!(reveal_at(5 * SEC), 1.0, "the second half starts revealed");
}

#[test]
fn an_animation_that_loses_its_only_ramp_becomes_null() {
    // An `in`-only animation split in two: the second half has nothing left
    // to do, so the field is cleared rather than left as a zero-length
    // typewriter that no longer means anything.
    let mut source = animated().value();
    source["clips"][0]["text"]["animation"] = json!({ "kind": "typewriter", "in": SEC, "out": 0 });
    let after = Handle::from_value(&source)
        .apply(&json!({ "op": "split", "clips": [11], "at": 5 * SEC }))
        .value();
    let (first, second) = halves(&after);
    assert_eq!(text(&first, "/text/animation/kind"), "typewriter");
    assert_eq!(at(&second, "/text/animation"), &Value::Null);
}

// ---- the clips that are minted -------------------------------------------

#[test]
fn a_freeze_frame_does_not_inherit_the_clips_preset() {
    // A still is a NEW clip with new ends: one taken mid-arrival would
    // otherwise arrive again, and one taken anywhere at all would carry a
    // departure onto a frame that is meant to hold.
    let after = moving()
        .apply(&json!({
            "op": "freeze_frame", "clip": 11, "at": 5 * SEC, "duration": 2 * SEC
        }))
        .value();
    let still = common::array(&after, "/clips")
        .iter()
        .find(|c| c["source"]["kind"] == json!("still"))
        .cloned()
        .expect("the op mints a still");
    assert_eq!(at(&still, "/video/motion"), &Value::Null);
    // ...and it keeps the placement it was frozen at, which is the UN-MOVED
    // one (`evaluate_clip` never applies motion) — the documented jump.
    assert_eq!(num(&still, "/video/x"), 100.0);
    assert_eq!(num(&still, "/video/scale"), 0.5);
}

#[test]
fn a_blurred_background_does_not_inherit_the_clips_preset() {
    // A backdrop that slid in, spun or pulsed behind the clip it was copied
    // from would be two pictures of one recording disagreeing about where
    // they are — and a slide would leave the canvas showing down one side,
    // which is the one thing a background exists to prevent.
    let after = moving()
        .apply(&json!({ "op": "add_blurred_background", "clip": 11 }))
        .value();
    // The op mints TWO objects and the TRACK takes the lower id, so the
    // copy is 13 (`edit_background.rs`'s documented order).
    let copy = by_id(&after, "/clips", 13);
    assert_eq!(at(copy, "/video/motion"), &Value::Null);
    // The clip it copied is untouched.
    assert_eq!(
        at(&by_id(&after, "/clips", 11).clone(), "/video/motion"),
        &full()
    );
}

// ---- the clones ----------------------------------------------------------

#[test]
fn a_duplicate_a_detach_and_a_paste_all_keep_the_whole_preset() {
    // These have the SAME ends as the clip they came from, so there is
    // nothing to give up. None of the three needs a line of code; what is
    // pinned here is that none of them grew one.
    let duplicated = moving()
        .apply(&json!({ "op": "duplicate", "clips": [11] }))
        .value();
    let copy = by_id(&duplicated, "/clips", 12);
    assert_eq!(at(copy, "/video/motion"), &full());

    // Detach leaves the PICTURE clip carrying the preset (the twin it mints
    // has no video group at all).
    let detached = moving()
        .apply(&json!({ "op": "detach_audio", "clip": 11 }))
        .value();
    assert_eq!(
        at(&by_id(&detached, "/clips", 11).clone(), "/video/motion"),
        &full()
    );

    // A paste of the clip into the same project: the payload carries the
    // video group whole.
    let payload = json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "clips": [{
            "id": 11, "track": 0, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": { "x": 100.0, "scale": 0.5, "motion": full() },
            "audio": {}
        }],
        "media": [{
            "id": 1, "path": "/fixtures/1.mov", "kind": "video",
            "duration": 60 * SEC, "width": 1280, "height": 800, "fps": [30, 1],
            "has_video": true, "has_audio": true
        }],
        "nests": []
    });
    let pasted = moving()
        .apply(&json!({ "op": "paste", "at": 20 * SEC, "payload": payload }))
        .value();
    let landed = common::array(&pasted, "/clips")
        .iter()
        .find(|c| c["start"] == json!(20 * SEC))
        .cloned()
        .expect("the paste lands a clip");
    assert_eq!(at(&landed, "/video/motion"), &full());
}

#[test]
fn paste_attributes_copies_the_preset_with_the_rest_of_the_video_group() {
    // `paste_attributes` replaces a group WHOLE, so a motion travels with
    // it — and, like every other value in the group, it passes the same
    // range checks a patch would (`Project::check_group`).
    let mut source = moving().value();
    source["clips"].as_array_mut().unwrap().push(json!({
        "id": 12, "track": 2, "start": 20 * SEC, "duration": 5 * SEC,
        "source": { "kind": "media", "media": 1, "in": 0 },
        "video": {}, "audio": {}
    }));
    source["next_id"] = json!(13);
    let payload = json!({
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "clips": [{
            "id": 11, "track": 0, "start": 0, "duration": 10 * SEC,
            "source": { "kind": "media", "media": 1, "in": 0 },
            "video": { "x": 100.0, "scale": 0.5, "motion": full() },
            "audio": {}
        }],
        "media": [],
        "nests": []
    });
    let after = Handle::from_value(&source)
        .apply(&json!({
            "op": "paste_attributes", "clips": [12], "payload": payload,
            "groups": ["video"]
        }))
        .value();
    assert_eq!(
        at(&by_id(&after, "/clips", 12).clone(), "/video/motion"),
        &full()
    );
}

#[test]
fn speed_does_not_rescale_a_preset() {
    // `text.animation`'s rule exactly: a preset is a DURATION in project
    // time, and a speed change moves the clip's own duration, not the
    // half-second somebody asked an entrance to take. Recorded rather than
    // fixed — the tent rule is what copes when the clip becomes shorter
    // than its two edges together.
    let after = moving()
        .apply(&json!({ "op": "set_speed", "clip": 11, "rate": 2.0 }))
        .value();
    assert_eq!(
        at(&by_id(&after, "/clips", 11).clone(), "/video/motion"),
        &full()
    );
}
