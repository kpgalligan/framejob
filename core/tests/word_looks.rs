//! Black-box tests for the three word-caption looks' recipe keys (issue
//! batch B86; spec §11 W-12, W-13), driven through the C FFI as
//! `ReelCore.swift` drives it. `schema_v12.rs` owns the three persisted
//! keys' shape; this file owns what they make the recipe answer:
//!
//! - **`word_glide`**: null until a second word has started, then a ramp
//!   from the active word's start over 0.2 s, or over the time to the next
//!   word when that is sooner.
//! - **`word_fill`**: a ramp from the active word's start to its end, at
//!   most 0.6 s long, holding 1.0 after.
//! - **`word_dim`**: 0.0 inside a word and in a pause under 0.25 s; in a
//!   longer one a 0.1 s ramp down from the word's end and a 0.1 s ramp up
//!   to the next start, with no ramp on a side that has no word.
//! - All three null off a timed, styled page; the hash folding them; the
//!   functions total on lists only a file can store; `pause_dim`'s range.
//!
//! Every expected number is computed HERE from the constants written out
//! below, never read back from the core.

mod common;

use serde_json::{json, Value};

use common::{array, int, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported, and the
/// four durations of spec §11 W-13.
const SEC: i64 = 600_000;
const GLIDE: i64 = 120_000;
const FILL_MAX: i64 = 360_000;
const DIM: i64 = 60_000;
const DIM_GAP: i64 = 150_000;

/// Four words: a 0.1 s gap after the first two, a 0.1 s word, a 0.9 s pause,
/// then a 2 s word that ends 2 s before the six-second clip does.
const A: (i64, i64) = (120_000, 300_000);
const B: (i64, i64) = (360_000, 540_000);
const C: (i64, i64) = (600_000, 660_000);
const D: (i64, i64) = (1_200_000, 2_400_000);
const CLIP: i64 = 6 * SEC;

fn words(list: &[(i64, i64)]) -> Value {
    Value::Array(
        list.iter()
            .map(|(start, end)| json!({ "start": start, "end": end }))
            .collect(),
    )
}

/// Every look on.
fn all_on() -> Value {
    json!({ "active_pill": { "glide": true }, "active_fill": true, "pause_dim": 0.5 })
}

fn text_clip(id: u32, start: i64, duration: i64, group: Value) -> Value {
    json!({
        "id": id, "track": 2, "start": start, "duration": duration,
        "source": { "kind": "text" }, "video": {}, "text": group
    })
}

/// A 30 fps project, one track (id 2), READ from a file — so its words are
/// stored whole, off the grid or out of order, as only the file reader stores.
fn project(clips: Vec<Value>) -> Handle {
    Handle::from_value(&json!({
        "version": 9,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": clips,
        "next_id": 50
    }))
}

/// Clip 11 alone, `duration` long from 0, one single-letter token per word.
fn page_for(list: &[(i64, i64)], style: Value, duration: i64) -> Handle {
    let content: Vec<&str> = ["a", "b", "c", "d", "e"][..list.len()].to_vec();
    project(vec![text_clip(
        11,
        0,
        duration,
        json!({ "content": content.join(" "), "words": words(list), "word_style": style }),
    )])
}

fn page(style: Value) -> Handle {
    page_for(&[A, B, C, D], style, CLIP)
}

fn source_of(handle: &Handle, id: i64, t: i64) -> Value {
    let recipe = handle.recipe(t);
    let layer = array(&recipe, "/layers")
        .iter()
        .find(|l| int(l, "/clip") == id);
    layer.unwrap_or_else(|| panic!("no layer for clip {id} at {t}"))["source"].clone()
}

/// A recipe number to nine decimal places: the JSON text the FFI answers is
/// read back an ulp away from the f64 that was written, so the oracle and
/// the answer are compared at a precision no ramp here needs.
fn nine(value: f64) -> f64 {
    (value * 1e9).round() / 1e9
}

/// One of the three keys of clip 11 at `t`: `None` for null.
fn key(handle: &Handle, name: &str, t: i64) -> Option<f64> {
    let source = source_of(handle, 11, t);
    let value = source
        .get(name)
        .unwrap_or_else(|| panic!("no {name} in {source}"));
    if value.is_null() {
        return None;
    }
    let number = value
        .as_f64()
        .unwrap_or_else(|| panic!("{name} is {value}"));
    Some(nine(number))
}

fn hash_at(handle: &Handle, t: i64) -> String {
    text(&source_of(handle, 11, t), "/hash").to_string()
}

/// The oracle's one division: how far `elapsed` is through `over`, 0..1.
fn part(elapsed: i64, over: i64) -> Option<f64> {
    Some(nine((elapsed as f64 / over as f64).clamp(0.0, 1.0)))
}

// ---- word_glide ----------------------------------------------------------

#[test]
fn glide_is_null_until_a_second_word_has_started() {
    let handle = page(all_on());
    // Before the first word, at its start, inside it and in the gap after.
    for t in [0, A.0, A.0 + 90_000, A.1 + 30_000] {
        assert_eq!(key(&handle, "word_glide", t), None, "t {t}");
    }
}

#[test]
fn glide_ramps_from_each_later_words_start_over_a_fifth_of_a_second() {
    let handle = page(all_on());
    // The second word: at its boundary, a quarter in, half in, done, held.
    assert_eq!(key(&handle, "word_glide", B.0), part(0, GLIDE));
    assert_eq!(key(&handle, "word_glide", B.0 + 30_000), Some(0.25));
    assert_eq!(key(&handle, "word_glide", B.0 + 60_000), Some(0.5));
    assert_eq!(key(&handle, "word_glide", B.0 + GLIDE), Some(1.0));
    assert_eq!(key(&handle, "word_glide", C.0 - 1), Some(1.0));
    // The third starts again from 0, a frame after the second's 1.0.
    assert_eq!(key(&handle, "word_glide", C.0), Some(0.0));
    assert_eq!(
        key(&handle, "word_glide", C.0 + 20_000),
        part(20_000, GLIDE)
    );
    // The LAST word has no next start to be done by, and takes the 0.2 s.
    assert_eq!(key(&handle, "word_glide", D.0), Some(0.0));
    assert_eq!(key(&handle, "word_glide", D.0 + 60_000), Some(0.5));
    assert_eq!(key(&handle, "word_glide", CLIP - 1), Some(1.0));
}

#[test]
fn glide_is_done_by_the_next_words_start_when_that_is_sooner() {
    // Three words 0.1 s apart: each slide has 0.1 s, not 0.2 s.
    let quick = [(0, 10_000), (60_000, 70_000), (120_000, 130_000)];
    let handle = page_for(&quick, all_on(), CLIP);
    assert_eq!(key(&handle, "word_glide", 60_000), Some(0.0));
    assert_eq!(key(&handle, "word_glide", 90_000), part(30_000, 60_000));
    assert_eq!(key(&handle, "word_glide", 90_000), Some(0.5));
    assert_eq!(key(&handle, "word_glide", 119_999), part(59_999, 60_000));
    // The last of them has the full 0.2 s again.
    assert_eq!(key(&handle, "word_glide", 180_000), part(60_000, GLIDE));
}

#[test]
fn glide_needs_a_pill_that_says_so() {
    for style in [
        json!({ "active_pill": {}, "active_fill": true, "pause_dim": 0.5 }),
        json!({ "active_pill": { "glide": false } }),
        json!({ "active_pill": null, "active_fill": true }),
        json!({}),
    ] {
        let handle = page(style.clone());
        for t in [B.0, B.0 + 60_000, D.0 + 60_000] {
            assert_eq!(key(&handle, "word_glide", t), None, "{style} at {t}");
        }
    }
}

// ---- word_fill -----------------------------------------------------------

#[test]
fn fill_runs_from_a_words_start_to_its_end_and_holds() {
    let handle = page(all_on());
    assert_eq!(key(&handle, "word_fill", 0), None, "no word has started");
    let length = A.1 - A.0;
    assert_eq!(key(&handle, "word_fill", A.0), Some(0.0));
    assert_eq!(
        key(&handle, "word_fill", A.0 + 45_000),
        part(45_000, length)
    );
    assert_eq!(key(&handle, "word_fill", A.0 + 90_000), Some(0.5));
    assert_eq!(key(&handle, "word_fill", A.1), Some(1.0));
    // In the gap after it the word stays full until the next one starts.
    assert_eq!(key(&handle, "word_fill", B.0 - 1), Some(1.0));
    assert_eq!(key(&handle, "word_fill", B.0), Some(0.0));
}

#[test]
fn a_word_shorter_than_the_cap_is_full_at_its_end() {
    let handle = page(all_on());
    let length = C.1 - C.0;
    assert!(length < FILL_MAX);
    assert_eq!(key(&handle, "word_fill", C.0), Some(0.0));
    assert_eq!(key(&handle, "word_fill", C.0 + 30_000), Some(0.5));
    assert_eq!(
        key(&handle, "word_fill", C.1 - 6_000),
        part(length - 6_000, length)
    );
    assert_eq!(key(&handle, "word_fill", C.1), Some(1.0));
    assert_eq!(key(&handle, "word_fill", C.1 + 300_000), Some(1.0));
}

#[test]
fn a_word_longer_than_the_cap_is_full_at_the_cap() {
    let handle = page(all_on());
    assert!(D.1 - D.0 > FILL_MAX);
    assert_eq!(
        key(&handle, "word_fill", D.0 + 90_000),
        part(90_000, FILL_MAX)
    );
    assert_eq!(key(&handle, "word_fill", D.0 + 180_000), Some(0.5));
    assert_eq!(
        key(&handle, "word_fill", D.0 + FILL_MAX - 1),
        part(FILL_MAX - 1, FILL_MAX)
    );
    assert_eq!(key(&handle, "word_fill", D.0 + FILL_MAX), Some(1.0));
    // Long before its stored end, and after it, it is still 1.0.
    assert_eq!(key(&handle, "word_fill", D.0 + SEC), Some(1.0));
    assert_eq!(key(&handle, "word_fill", D.1 + SEC), Some(1.0));
}

#[test]
fn fill_is_null_unless_the_style_asks_for_it() {
    for style in [
        json!({ "active_pill": { "glide": true }, "pause_dim": 0.5 }),
        json!({ "active_fill": false }),
    ] {
        let handle = page(style);
        for t in [0, A.0 + 90_000, D.0 + SEC] {
            assert_eq!(key(&handle, "word_fill", t), None, "t {t}");
        }
    }
}

// ---- word_dim ------------------------------------------------------------

#[test]
fn dim_is_zero_inside_a_word_and_in_a_short_pause() {
    let handle = page(all_on());
    // A 0.2 s lead before the first word is under the gap: no dim there.
    assert!(A.0 < DIM_GAP);
    for t in [0, A.0 - 1, A.0, A.0 + 90_000, A.1 - 1] {
        assert_eq!(key(&handle, "word_dim", t), Some(0.0), "t {t}");
    }
    // The 0.1 s gaps after the first and second words.
    for t in [A.1, A.1 + 30_000, B.0 - 1, B.1 + 30_000] {
        assert_eq!(key(&handle, "word_dim", t), Some(0.0), "t {t}");
    }
}

#[test]
fn dim_ramps_down_after_a_word_and_back_up_before_the_next() {
    let handle = page(all_on());
    assert!(D.0 - C.1 >= DIM_GAP);
    // Down, from the word's end.
    assert_eq!(key(&handle, "word_dim", C.1), Some(0.0));
    assert_eq!(key(&handle, "word_dim", C.1 + 15_000), part(15_000, DIM));
    assert_eq!(key(&handle, "word_dim", C.1 + 30_000), Some(0.5));
    assert_eq!(key(&handle, "word_dim", C.1 + DIM), Some(1.0));
    // The plateau.
    assert_eq!(key(&handle, "word_dim", C.1 + 240_000), Some(1.0));
    assert_eq!(key(&handle, "word_dim", D.0 - DIM), Some(1.0));
    // Back up, to the next word's start.
    assert_eq!(key(&handle, "word_dim", D.0 - 30_000), Some(0.5));
    assert_eq!(key(&handle, "word_dim", D.0 - 1), part(1, DIM));
    assert_eq!(key(&handle, "word_dim", D.0), Some(0.0));
}

#[test]
fn a_pause_dims_from_a_quarter_second_and_not_a_tick_under() {
    let dims = [(0, 100_000), (100_000 + DIM_GAP, 400_000)];
    let handle = page_for(&dims, all_on(), CLIP);
    // 0.25 s exactly: a 0.1 s ramp each way with 0.05 s between.
    assert_eq!(key(&handle, "word_dim", 100_000 + 30_000), Some(0.5));
    assert_eq!(key(&handle, "word_dim", 100_000 + 75_000), Some(1.0));
    assert_eq!(
        key(&handle, "word_dim", 100_000 + DIM_GAP - 30_000),
        Some(0.5)
    );

    let lit = [(0, 100_000), (100_000 + DIM_GAP - 1, 400_000)];
    let handle = page_for(&lit, all_on(), CLIP);
    for t in [100_000, 130_000, 175_000, 249_998] {
        assert_eq!(key(&handle, "word_dim", t), Some(0.0), "t {t}");
    }
}

#[test]
fn a_late_first_word_opens_the_page_dim_with_no_ramp_down() {
    let late = [(300_000, 400_000)];
    let handle = page_for(&late, json!({ "pause_dim": 0.5 }), 400_000);
    assert_eq!(key(&handle, "word_dim", 0), Some(1.0));
    assert_eq!(key(&handle, "word_dim", 30_000), Some(1.0));
    assert_eq!(key(&handle, "word_dim", 300_000 - DIM), Some(1.0));
    assert_eq!(key(&handle, "word_dim", 270_000), Some(0.5));
    assert_eq!(key(&handle, "word_dim", 300_000), Some(0.0));
    // The clip ends with the word: no tail.
    assert_eq!(key(&handle, "word_dim", 399_999), Some(0.0));
}

#[test]
fn the_tail_after_the_last_word_dims_against_the_clips_duration() {
    let handle = page(all_on());
    assert!(CLIP - D.1 >= DIM_GAP);
    assert_eq!(key(&handle, "word_dim", D.1 - 1), Some(0.0));
    assert_eq!(key(&handle, "word_dim", D.1), Some(0.0));
    assert_eq!(key(&handle, "word_dim", D.1 + 30_000), Some(0.5));
    assert_eq!(key(&handle, "word_dim", D.1 + DIM), Some(1.0));
    // No ramp back up: nothing follows on this page.
    assert_eq!(key(&handle, "word_dim", CLIP - 30_000), Some(1.0));
    assert_eq!(key(&handle, "word_dim", CLIP - 1), Some(1.0));

    // A clip that ends 0.25 s less a tick after its last word never dims.
    let short = page_for(&[A, B, C, D], all_on(), D.1 + DIM_GAP - 1);
    for t in [D.1, D.1 + 30_000, D.1 + DIM_GAP - 2] {
        assert_eq!(key(&short, "word_dim", t), Some(0.0), "t {t}");
    }
    // And one that ends exactly 0.25 s after it does.
    let long = page_for(&[A, B, C, D], all_on(), D.1 + DIM_GAP);
    assert_eq!(key(&long, "word_dim", D.1 + 30_000), Some(0.5));
}

#[test]
fn dim_is_null_at_pause_dim_zero() {
    for style in [
        json!({ "active_fill": true, "active_pill": { "glide": true } }),
        json!({ "pause_dim": 0.0 }),
    ] {
        let handle = page(style);
        for t in [0, A.0, C.1 + DIM, CLIP - 1] {
            assert_eq!(key(&handle, "word_dim", t), None, "t {t}");
        }
    }
}

// ---- pages side by side --------------------------------------------------

#[test]
fn of_two_abutting_pages_the_first_ends_dim_and_the_second_opens_lit() {
    let group = |list: &[(i64, i64)]| json!({ "content": "a b", "words": words(list), "word_style": all_on() });
    let first = [(0, 200_000), (300_000, 500_000)];
    let second = [(0, 200_000), (300_000, 400_000)];
    let handle = project(vec![
        text_clip(11, 0, 2 * SEC, group(&first)),
        text_clip(12, 2 * SEC, 2 * SEC, group(&second)),
    ]);
    // The first page's last frame: 0.7 s of tail, long since dim.
    let tail = source_of(&handle, 11, 2 * SEC - 20_000);
    assert_eq!(tail["word"], json!(2));
    assert_eq!(tail["word_dim"], json!(1.0));
    assert_eq!(tail["word_fill"], json!(1.0));
    // The second page's first: its pill has no word to come from, its first
    // word has just begun, and nothing of the page before reaches it.
    let opens = source_of(&handle, 12, 2 * SEC);
    assert_eq!(opens["word"], json!(1));
    assert_eq!(opens["word_glide"], Value::Null);
    assert_eq!(opens["word_fill"], json!(0.0));
    assert_eq!(opens["word_dim"], json!(0.0));
}

// ---- lists only a file can store -----------------------------------------

fn in_range(handle: &Handle, t: i64) {
    for name in ["word_glide", "word_fill", "word_dim"] {
        if let Some(value) = key(handle, name, t) {
            assert!((0.0..=1.0).contains(&value), "{name} {value} at {t}");
        }
    }
}

#[test]
fn two_words_on_one_start_slide_and_fill_as_the_later_one() {
    let same = [(0, 100_000), (200_000, 300_000), (200_000, 400_000)];
    let handle = page_for(&same, all_on(), CLIP);
    // Both count, so the third is active: its length is the fill's.
    assert_eq!(source_of(&handle, 11, 200_000)["word"], json!(3));
    assert_eq!(key(&handle, "word_glide", 200_000), Some(0.0));
    assert_eq!(key(&handle, "word_glide", 260_000), Some(0.5));
    assert_eq!(key(&handle, "word_fill", 260_000), part(60_000, 200_000));
    assert_eq!(key(&handle, "word_dim", 260_000), Some(0.0));
}

#[test]
fn every_key_is_total_on_an_unsorted_list_and_extreme_ticks() {
    let unsorted = [(0, 10_000), (600_000, 610_000), (100_000, 110_000)];
    let handle = page_for(&unsorted, all_on(), CLIP);
    for t in [
        0,
        50_000,
        100_000,
        200_000,
        599_999,
        600_000,
        700_000,
        CLIP - 1,
    ] {
        in_range(&handle, t);
    }
    // At 0.33 s two words have "started" and the active one is in the future.
    assert_eq!(source_of(&handle, 11, 200_000)["word"], json!(2));
    assert!(key(&handle, "word_glide", 200_000).is_some());

    for extreme in [
        (i64::MIN, 0),
        (i64::MIN, i64::MIN),
        (i64::MIN, i64::MAX),
        (0, i64::MAX),
        (0, i64::MIN),
    ] {
        let handle = page_for(&[extreme], all_on(), CLIP);
        for t in [0, 1, SEC, CLIP - 1] {
            in_range(&handle, t);
            assert!(key(&handle, "word_fill", t).is_some(), "{extreme:?} at {t}");
            assert!(key(&handle, "word_dim", t).is_some(), "{extreme:?} at {t}");
        }
    }
    // Two extreme words, so the glide's subtraction saturates too.
    let pair = [(i64::MIN, i64::MIN), (i64::MIN, i64::MAX)];
    let handle = page_for(&pair, all_on(), CLIP);
    for t in [0, SEC] {
        in_range(&handle, t);
        assert!(key(&handle, "word_glide", t).is_some());
    }
}

// ---- where the keys are null ---------------------------------------------

#[test]
fn all_three_are_null_off_a_timed_styled_page() {
    let null = |handle: &Handle, t: i64| {
        let source = source_of(handle, 11, t);
        for name in ["word", "word_pop", "word_glide", "word_fill", "word_dim"] {
            assert_eq!(source[name], Value::Null, "{name} at {t} in {source}");
        }
    };
    // Unstyled, timed or not.
    let timed = project(vec![text_clip(
        11,
        0,
        CLIP,
        json!({ "content": "a b c d", "words": words(&[A, B, C, D]) }),
    )]);
    let plain = project(vec![text_clip(11, 0, CLIP, json!({ "content": "a b" }))]);
    // Styled with every look on, but untimed; and with a count mismatch.
    let untimed = project(vec![text_clip(
        11,
        0,
        CLIP,
        json!({ "content": "a b", "word_style": all_on() }),
    )]);
    let mismatch = project(vec![text_clip(
        11,
        0,
        CLIP,
        json!({ "content": "a b c", "words": words(&[A, B]), "word_style": all_on() }),
    )]);
    for handle in [&timed, &plain, &untimed, &mismatch] {
        for t in [0, B.0 + 60_000, C.1 + DIM] {
            null(handle, t);
        }
    }
}

#[test]
fn the_burn_in_carries_the_three_keys_null() {
    let recipe = page(all_on()).recipe_opts(SEC, &json!({ "burn_in_timecode": true }));
    let layers = array(&recipe, "/layers");
    let burn_in = layers.last().expect("a burn-in layer");
    assert_eq!(int(burn_in, "/clip"), 0);
    for name in ["word_glide", "word_fill", "word_dim"] {
        assert_eq!(burn_in["source"][name], Value::Null, "{name}");
    }
}

#[test]
fn the_three_keys_follow_word_pop_in_the_source() {
    let written = page(all_on()).recipe_text(B.0);
    let order = [
        "\"word\"",
        "\"word_pop\"",
        "\"word_glide\"",
        "\"word_fill\"",
        "\"word_dim\"",
    ];
    let places: Vec<usize> = order
        .iter()
        .map(|name| {
            written
                .find(name)
                .unwrap_or_else(|| panic!("no {name} in {written}"))
        })
        .collect();
    assert!(
        places.windows(2).all(|pair| pair[0] < pair[1]),
        "{places:?}"
    );
}

// ---- the hash ------------------------------------------------------------

#[test]
fn the_hash_follows_the_picture_and_only_the_picture() {
    let handle = page(all_on());
    assert_ne!(
        hash_at(&handle, A.0 + 45_000),
        hash_at(&handle, A.0 + 90_000),
        "two fill fractions are two pictures"
    );
    assert_ne!(
        hash_at(&handle, B.0 + 30_000),
        hash_at(&handle, B.0 + 60_000),
        "two glide fractions are two pictures"
    );
    assert_ne!(
        hash_at(&handle, C.1 + 15_000),
        hash_at(&handle, C.1 + 30_000),
        "two dim levels are two pictures"
    );
    assert_eq!(
        hash_at(&handle, C.1 + DIM),
        hash_at(&handle, D.0 - DIM),
        "a dim plateau is one picture from its first instant to its last"
    );
    assert_eq!(
        hash_at(&handle, D.0 + FILL_MAX),
        hash_at(&handle, D.0 + SEC),
        "past the cap a long word is one picture"
    );
    // A page that asks for none of the three is one picture per word.
    let off = page(json!({}));
    assert_eq!(hash_at(&off, A.0), hash_at(&off, A.1 + 30_000));
    assert_ne!(hash_at(&off, A.0), hash_at(&handle, A.0));
}

// ---- the door ------------------------------------------------------------

#[test]
fn pause_dim_outside_zero_to_one_is_refused_by_name() {
    let handle = page(json!({}));
    let set = |value: Value| {
        json!({ "op": "set_text", "clips": [11],
                "patch": { "word_style": { "pause_dim": value } } })
    };
    for (value, spelled) in [(2.0, "2"), (-0.1, "-0.1"), (1.01, "1.01")] {
        assert_eq!(
            handle.errors(&set(json!(value))),
            format!("text.word_style.pause_dim must be between 0 and 1, not {spelled}")
        );
    }
    // The bounds themselves are legal: 1 makes a pause invisible, 0 is off.
    handle.apply(&set(json!(1.0))).apply(&set(json!(0.0)));
    // A new title is held to the same rule.
    let add = json!({ "op": "add_text_clip", "track": 2, "at": 7 * SEC,
                      "text": { "content": "a", "word_style": { "pause_dim": 1.5 } } });
    assert_eq!(
        handle.errors(&add),
        "text.word_style.pause_dim must be between 0 and 1, not 1.5"
    );
}
