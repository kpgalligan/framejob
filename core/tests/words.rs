//! Black-box tests for what a word caption's timings DO (road map 8, W1b;
//! spec §11 W-3 to W-5), driven through the C FFI as `ReelCore.swift`
//! drives it. `schema_v9.rs` owns the shape and the checks; this file owns:
//!
//! - **W-3, the rebase**: `trim_start`, `roll`, `add_transition`'s handle
//!   form and `split`'s second half each move the words by what the clip's
//!   head moved, and nothing else does (`trim_end` leaves them). A split
//!   whose second half carries an evaluated `content` of another token count
//!   stores `words: []` there, so the half is a clip the door accepts again.
//! - **Snapping**: at the patch door (nearest, a negative start stays
//!   negative, a refusal names the caller's number) and under D7-3's
//!   normalization through `set_canvas`.
//! - **The recipe**: `word` and `word_pop` on every text layer, null unless
//!   styled; the hash folds them in only when styled; W-5's whole reveal;
//!   and `Words::of` total on an unsorted list and an `i64::MIN` start,
//!   which only the file reader and `paste` can store.

mod common;

use serde_json::{json, Value};

use common::{array, at, int, text, Handle};

/// Ticks per second (spec §5.1) and one frame at 30 fps, written out.
const SEC: i64 = 600_000;
const FRAME: i64 = 20_000;

const PAGE: &str = "so here's the thing";

/// Road map 8 §5a's timings, off the 30 fps grid on purpose.
fn timings() -> Value {
    json!([
        {"start": 0, "end": 108000},
        {"start": 120000, "end": 276000},
        {"start": 288000, "end": 348000},
        {"start": 360000, "end": 618000}
    ])
}

/// Where the door snaps [`timings`] at 30 fps — each to the NEAREST frame,
/// computed by hand: 5.4 → 5, 13.8 → 14, 14.4 → 14, 17.4 → 17, 18 → 18,
/// 30.9 → 31 frames.
fn snapped() -> Value {
    json!([
        {"start": 0, "end": 100000},
        {"start": 120000, "end": 280000},
        {"start": 280000, "end": 340000},
        {"start": 360000, "end": 620000}
    ])
}

/// `snapped()` with every time moved by `by`.
fn shifted(by: i64) -> Value {
    Value::Array(
        array(&snapped(), "")
            .iter()
            .map(|w| json!({"start": int(w, "/start") + by, "end": int(w, "/end") + by}))
            .collect(),
    )
}

/// A 30 fps project, one track (id 2), with the text clips given.
fn project(clips: Vec<Value>, next_id: u32) -> Value {
    json!({
        "version": 9,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": clips,
        "next_id": next_id
    })
}

fn text_clip(id: u32, start: i64, duration: i64, group: Value) -> Value {
    json!({
        "id": id, "track": 2, "start": start, "duration": duration,
        "source": { "kind": "text" }, "video": {}, "text": group
    })
}

/// Clip 11 alone, six seconds from 0, with `group` as its text, READ from a
/// file — so it is stored whole, as only the file reader stores.
fn page_of(group: Value) -> Handle {
    Handle::from_value(&project(vec![text_clip(11, 0, 6 * SEC, group)], 12))
}

fn set_text(id: u32, patch: Value) -> Value {
    json!({ "op": "set_text", "clips": [id], "patch": patch })
}

/// Clip 11, six seconds from 0, with the page's content and its words set
/// THROUGH THE DOOR, so they are on the grid.
fn timed() -> Handle {
    page_of(json!({ "content": PAGE })).apply(&set_text(11, json!({ "words": timings() })))
}

fn clip(project: &Value, id: i64) -> &Value {
    array(project, "/clips")
        .iter()
        .find(|c| int(c, "/id") == id)
        .unwrap_or_else(|| panic!("no clip {id} in {project}"))
}

fn words_of(project: &Value, id: i64) -> Value {
    at(clip(project, id), "/text/words").clone()
}

fn source_of(handle: &Handle, id: i64, t: i64) -> Value {
    let recipe = handle.recipe(t);
    let layer = array(&recipe, "/layers")
        .iter()
        .find(|l| int(l, "/clip") == id);
    layer.unwrap_or_else(|| panic!("no layer for clip {id} at {t}"))["source"].clone()
}

fn word_at(handle: &Handle, id: i64, t: i64) -> (Value, Value) {
    let source = source_of(handle, id, t);
    (source["word"].clone(), source["word_pop"].clone())
}

fn hash_at(handle: &Handle, id: i64, t: i64) -> String {
    text(&source_of(handle, id, t), "/hash").to_string()
}

// ---- snapping ------------------------------------------------------------

#[test]
fn the_door_snaps_word_times_to_the_nearest_frame() {
    assert_eq!(words_of(&timed().value(), 11), snapped());
    // A negative start is "already said": snapped to the nearest frame,
    // -2.25 frames to -2, never clamped to 0.
    let applied = page_of(json!({ "content": "one two" })).apply(&set_text(
        11,
        json!({ "words": [{"start": -45000, "end": -5000}, {"start": 10001, "end": 30000}] }),
    ));
    assert_eq!(
        words_of(&applied.value(), 11),
        json!([{"start": -40000, "end": 0}, {"start": 20000, "end": 40000}])
    );
}

#[test]
fn a_refusal_names_the_number_the_caller_sent_not_the_snapped_one() {
    // Both would snap to 100000 — the check runs first.
    let handle = page_of(json!({ "content": "one" }));
    assert_eq!(
        handle.errors(&set_text(
            11,
            json!({ "words": [{"start": 100001, "end": 99999}] })
        )),
        "text.words[0].end must be at least its start 100001, not 99999"
    );
}

#[test]
fn a_canvas_fps_change_resnaps_the_words_under_d7_3() {
    let resnapped = timed()
        .apply(&json!({ "op": "set_canvas", "fps": [24, 1] }))
        .value();
    // 24 fps is 25000 ticks a frame; each time to the nearest, by hand.
    assert_eq!(
        words_of(&resnapped, 11),
        json!([
            {"start": 0, "end": 100000},
            {"start": 125000, "end": 275000},
            {"start": 275000, "end": 350000},
            {"start": 350000, "end": 625000}
        ])
    );
}

// ---- W-3: the rebase -----------------------------------------------------

#[test]
fn trim_start_rebases_the_words_by_its_delta() {
    let trimmed = timed()
        .apply(&json!({ "op": "trim_start", "clip": 11, "to": 2 * FRAME }))
        .value();
    assert_eq!(int(clip(&trimmed, 11), "/start"), 2 * FRAME);
    assert_eq!(words_of(&trimmed, 11), shifted(-2 * FRAME));
}

#[test]
fn trim_end_and_nothing_else_leave_the_words_alone() {
    let trimmed = timed()
        .apply(&json!({ "op": "trim_end", "clip": 11, "to": 3 * SEC }))
        .value();
    assert_eq!(words_of(&trimmed, 11), snapped());
    let moved = timed()
        .apply(&json!({ "op": "move_clip", "clips": [11], "delta": SEC }))
        .value();
    assert_eq!(words_of(&moved, 11), snapped());
}

/// Two abutting text clips: 11 over [0, 3 s) and the timed page 12 over
/// [3 s, 6 s).
fn pair() -> Handle {
    Handle::from_value(&project(
        vec![
            text_clip(11, 0, 3 * SEC, json!({ "content": "before" })),
            text_clip(12, 3 * SEC, 3 * SEC, json!({ "content": PAGE })),
        ],
        13,
    ))
    .apply(&set_text(12, json!({ "words": timings() })))
}

#[test]
fn roll_rebases_the_later_clips_words() {
    let rolled = pair()
        .apply(&json!({ "op": "roll", "clip": 12, "to": 3 * SEC + FRAME }))
        .value();
    assert_eq!(int(clip(&rolled, 12), "/start"), 3 * SEC + FRAME);
    assert_eq!(words_of(&rolled, 12), shifted(-FRAME));
}

#[test]
fn add_transition_before_moves_the_words_with_the_new_head() {
    let handle = pair().apply(&json!({
        "op": "add_transition", "clip": 12, "duration": 10 * FRAME, "align": "before"
    }));
    let value = handle.value();
    let head = 3 * SEC - int(clip(&value, 12), "/start");
    assert_eq!(head, 10 * FRAME);
    assert_eq!(words_of(&value, 12), shifted(head));
}

#[test]
fn split_gives_the_second_half_every_word_rebased_by_the_cut() {
    let cut = 10 * FRAME;
    let split = timed()
        .apply(&json!({ "op": "split", "clips": [11], "at": cut }))
        .value();
    assert_eq!(words_of(&split, 11), snapped()); // the first half is untouched
    let second = int(&split, "/next_id") - 1;
    assert_eq!(int(clip(&split, second), "/start"), cut);
    assert_eq!(words_of(&split, second), shifted(-cut));
    // A negative start is legal and survives the door again.
    assert_eq!(int(&words_of(&split, second), "/0/start"), -cut);
    Handle::from_value(&split).apply(&set_text(
        second as u32,
        json!({ "color": [1.0, 0.0, 0.0, 1.0] }),
    ));
}

#[test]
fn split_after_a_content_action_clears_the_second_halfs_words() {
    let handle = timed().apply(&json!({ "op": "add_action", "clip": 11, "at": 0 }));
    let action = int(&handle.value(), "/clips/0/actions/0/id");
    let handle = handle.apply(&json!({
        "op": "set_action_end", "clip": 11, "action": action,
        "patch": { "text": { "content": "a b c" } }
    }));
    let split = handle
        .apply(&json!({ "op": "split", "clips": [11], "at": 2 * SEC }))
        .value();
    let second = int(&split, "/next_id") - 1;
    assert_eq!(text(clip(&split, second), "/text/content"), "a b c");
    assert_eq!(words_of(&split, second), json!([]));
    assert_eq!(words_of(&split, 11), snapped()); // the first half keeps its four
                                                 // The half is a clip the door accepts again.
    let recoloured = Handle::from_value(&split).apply(&set_text(
        second as u32,
        json!({ "color": [1.0, 0.0, 0.0, 1.0] }),
    ));
    assert_eq!(
        at(clip(&recoloured.value(), second), "/text/color"),
        &json!([1.0, 0.0, 0.0, 1.0])
    );
}

// ---- the recipe ----------------------------------------------------------

fn styled(scale: f64) -> Handle {
    timed().apply(&set_text(
        11,
        json!({ "word_style": { "active_scale": scale } }),
    ))
}

#[test]
fn word_counts_the_started_words_and_word_pop_ramps_after_each() {
    let handle = styled(1.2);
    let pop = |since: i64| json!((since as f64 / 72000.0).clamp(0.0, 1.0));
    assert_eq!(word_at(&handle, 11, 0), (json!(1), pop(0)));
    assert_eq!(word_at(&handle, 11, 100000), (json!(1), pop(100000)));
    assert_eq!(word_at(&handle, 11, 120000), (json!(2), pop(0)));
    assert_eq!(word_at(&handle, 11, 156000), (json!(2), json!(0.5)));
    // Two words may share a start; both count and the later one is active.
    assert_eq!(word_at(&handle, 11, 280000), (json!(3), pop(0)));
    assert_eq!(word_at(&handle, 11, 5 * SEC), (json!(4), json!(1.0)));
    // Before the first word has started there is nothing to pop.
    let late = timed().apply(&set_text(
        11,
        json!({ "words": shifted(SEC), "word_style": { "active_scale": 1.2 } }),
    ));
    assert_eq!(word_at(&late, 11, 0), (json!(0), Value::Null));
    // And when the active word does not grow, there is no pop at all.
    assert_eq!(word_at(&styled(1.0), 11, 130000), (json!(2), Value::Null));
}

#[test]
fn a_count_mismatch_only_a_file_can_store_degrades_to_null() {
    let handle = page_of(json!({ "content": "a b c", "words": snapped(), "word_style": {} }));
    assert_eq!(word_at(&handle, 11, 130000), (Value::Null, Value::Null));
}

#[test]
fn word_of_is_total_on_an_unsorted_list_and_an_extreme_start() {
    let unsorted = page_of(json!({
        "content": "a b c",
        "words": [
            {"start": 0, "end": 10000},
            {"start": 600000, "end": 610000},
            {"start": 100000, "end": 110000}
        ],
        "word_style": { "active_scale": 1.2 }
    }));
    let (word, pop) = word_at(&unsorted, 11, 200000);
    assert_eq!(word, json!(2));
    let pop = pop.as_f64().expect("word_pop is a number");
    assert!((0.0..=1.0).contains(&pop), "word_pop {pop} left 0..1");

    let extreme = page_of(json!({
        "content": "a",
        "words": [{"start": i64::MIN, "end": 0}],
        "word_style": { "active_scale": 1.2 }
    }));
    assert_eq!(word_at(&extreme, 11, 0), (json!(1), json!(1.0)));
}

#[test]
fn a_styled_page_is_a_whole_reveal() {
    // W-5: `word_style` and `animation` do not compose; the style wins.
    let handle = styled(1.2).apply(&set_text(
        11,
        json!({ "animation": { "kind": "typewriter", "in": SEC } }),
    ));
    let source = source_of(&handle, 11, SEC / 4);
    assert_eq!(source["reveal"], json!(1.0));
    assert_eq!(source["reveal_phase"], Value::Null);
    assert_eq!(source["reveal_kind"], Value::Null);
    // Unstyled, the same animation reveals.
    let animated = timed().apply(&set_text(
        11,
        json!({ "animation": { "kind": "typewriter", "in": SEC } }),
    ));
    assert_eq!(source_of(&animated, 11, SEC / 4)["reveal"], json!(0.25));
}

#[test]
fn a_styled_page_hashes_a_word_apart_differently() {
    let handle = styled(1.0);
    assert_ne!(
        hash_at(&handle, 11, 100000),
        hash_at(&handle, 11, 150000),
        "two words are two pictures"
    );
    assert_eq!(
        hash_at(&handle, 11, 130000),
        hash_at(&handle, 11, 150000),
        "one word with no pop is one picture"
    );
}

#[test]
fn an_unstyled_page_hashes_as_the_same_text_without_words() {
    let bare = page_of(json!({ "content": PAGE }));
    let timed = timed();
    for t in [0, 150000, 5 * SEC] {
        assert_eq!(hash_at(&timed, 11, t), hash_at(&bare, 11, 0));
        // Unstyled, both word keys are null however many words have started.
        assert_eq!(word_at(&timed, 11, t), (Value::Null, Value::Null));
    }
    // The description carries neither `words` nor an unset style or case.
    let description = source_of(&timed, 11, 0)["text"].clone();
    for key in ["words", "word_style", "case", "animation"] {
        assert!(
            description.get(key).is_none(),
            "{key} rode in {description}"
        );
    }
    // `case` rides once it changes the picture, and so does a style.
    let upper = timed.apply(&set_text(11, json!({ "case": "upper" })));
    assert_eq!(source_of(&upper, 11, 0)["text"]["case"], json!("upper"));
    assert_ne!(hash_at(&upper, 11, 0), hash_at(&bare, 11, 0));
    assert!(source_of(&styled(1.0), 11, 0)["text"]
        .get("word_style")
        .is_some());
}

#[test]
fn the_burn_in_carries_null_word_keys() {
    let recipe = timed().recipe_opts(SEC, &json!({ "burn_in_timecode": true }));
    let layers = array(&recipe, "/layers");
    let burn_in = layers.last().expect("a burn-in layer");
    assert_eq!(int(burn_in, "/clip"), 0);
    assert_eq!(burn_in["source"]["word"], Value::Null);
    assert_eq!(burn_in["source"]["word_pop"], Value::Null);
}
