//! Black-box tests for what format version 9 added — `text.case`,
//! `text.words` and `text.word_style`, a word caption's page (road map 8,
//! W1b) — driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Pinned here: the SHAPE (every older file opens with the three keys at
//! their defaults, stamped version 9; the derived default is the absence of
//! the key; a full page round-trips key for key; every spelling survives),
//! the KEY ORDER (`animation`, `case`, `words`, `word_style`, and
//! `word_style` closes the text object — read off the written text), every
//! `check_text` rule by NAME as an `Err` (spec §11 W-2: an error, no undo
//! step), `words[]` entry completeness, W-6 (`words` is not an animation
//! target; `paste_attributes` keeps it with `content`). What the words DO
//! over time — the rebases, the snapping, the recipe — is `words.rs`'s.

mod common;

use reelcut_core::format::RC_FORMAT_VERSION;
use serde_json::{json, Value};

use common::{array, at, int, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported.
const SEC: i64 = 600_000;

/// Four words, the page road map 8 §5a draws.
const PAGE: &str = "so here's the thing";

/// Road map 8 §5a's four timings — deliberately OFF the 30 fps grid, so the
/// door's snap is visible (`words.rs` pins where they land).
fn timings() -> Value {
    json!([
        {"start": 0, "end": 108000},
        {"start": 120000, "end": 276000},
        {"start": 288000, "end": 348000},
        {"start": 360000, "end": 618000}
    ])
}

/// A word style with every slot filled and nothing at its default, so no
/// round trip can pass by accident.
fn full_style() -> Value {
    json!({
        "mode": "build",
        "active_color": [1.0, 0.85, 0.0, 1.0],
        "active_scale": 1.2,
        "active_pill": {"color": [0.1, 0.2, 0.3, 1.0], "padding": 0.18, "radius": 0.3, "glide": true},
        "spoken_color": [0.9, 0.9, 0.9, 1.0],
        "upcoming_color": [0.5, 0.5, 0.5, 1.0],
        "active_fill": true,
        "pause_dim": 0.4
    })
}

/// One track (id 2) and one six-second text clip (id 11) whose text group
/// is `text` merged over the page's content, written as a file of `version`.
fn page(version: u32, extra: Value) -> Value {
    let mut group = json!({ "content": PAGE, "size": 96.0 });
    if let (Some(into), Some(from)) = (group.as_object_mut(), extra.as_object()) {
        for (key, value) in from {
            into.insert(key.clone(), value.clone());
        }
    }
    json!({
        "version": version,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [{
            "id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
            "source": { "kind": "text" }, "video": {}, "text": group
        }],
        "next_id": 12
    })
}

fn plain() -> Handle {
    Handle::from_value(&page(9, json!({})))
}

fn set_text(patch: Value) -> Value {
    json!({ "op": "set_text", "clips": [11], "patch": patch })
}

// ---- reading older files -------------------------------------------------

#[test]
fn every_older_version_reads_with_the_three_keys_at_their_defaults() {
    for version in [9, 8, 7, 6, 5, 4, 3, 2, 1] {
        let project = Handle::from_value(&page(version, json!({}))).value();
        assert_eq!(
            at(&project, "/version"),
            &json!(RC_FORMAT_VERSION),
            "version {version}"
        );
        assert_eq!(text(&project, "/clips/0/text/case"), "as_written");
        assert_eq!(at(&project, "/clips/0/text/words"), &json!([]));
        assert_eq!(at(&project, "/clips/0/text/word_style"), &Value::Null);
        assert_eq!(text(&project, "/clips/0/text/content"), PAGE);
    }
}

#[test]
fn the_derived_default_is_the_absence_of_the_keys() {
    let absent = Handle::from_value(&page(9, json!({}))).value();
    let explicit = Handle::from_value(&page(
        9,
        json!({ "case": "as_written", "words": [], "word_style": null }),
    ))
    .value();
    assert_eq!(at(&absent, "/clips/0/text"), at(&explicit, "/clips/0/text"));
}

#[test]
fn an_empty_style_and_an_empty_pill_take_the_documented_defaults() {
    let written =
        Handle::from_value(&page(9, json!({ "word_style": { "active_pill": {} } }))).value();
    assert_eq!(
        at(&written, "/clips/0/text/word_style"),
        &json!({
            "mode": "highlight",
            "active_color": null,
            "active_scale": 1.0,
            "active_pill": {"color": [0.55, 0.27, 0.93, 1.0], "padding": 0.2, "radius": 0.25, "glide": false},
            "spoken_color": null,
            "upcoming_color": null,
            "active_fill": false,
            "pause_dim": 0.0
        })
    );
}

// ---- the round trip ------------------------------------------------------

#[test]
fn a_full_page_round_trips_exactly() {
    let source = page(
        9,
        json!({ "case": "upper", "words": timings(), "word_style": full_style() }),
    );
    let first = Handle::from_value(&source);
    let written = first.value();
    assert_eq!(text(&written, "/clips/0/text/case"), "upper");
    assert_eq!(at(&written, "/clips/0/text/words"), &timings());
    assert_eq!(at(&written, "/clips/0/text/word_style"), &full_style());
    let text_json = first.to_json();
    let second = Handle::from_json(&text_json).to_json();
    assert_eq!(text_json, second, "a second round trip changed the bytes");
}

#[test]
fn every_spelling_survives_a_write_and_a_read() {
    for case in ["as_written", "upper"] {
        let written = Handle::from_value(&page(9, json!({ "case": case }))).value();
        assert_eq!(text(&written, "/clips/0/text/case"), case);
    }
    for mode in ["highlight", "build"] {
        let written =
            Handle::from_value(&page(9, json!({ "word_style": { "mode": mode } }))).value();
        assert_eq!(text(&written, "/clips/0/text/word_style/mode"), mode);
    }
}

/// The keys of the text object, in the order the writer put them, read off
/// the pretty-printed TEXT by indentation.
fn written_text_keys(written: &str) -> Vec<String> {
    let lines: Vec<&str> = written.lines().collect();
    let open = lines
        .iter()
        .position(|line| line.trim_start().starts_with("\"text\": {"))
        .unwrap_or_else(|| panic!("no text object in:\n{written}"));
    let indent = lines[open].len() - lines[open].trim_start().len();
    let mut keys = Vec::new();
    for line in &lines[open + 1..] {
        let here = line.len() - line.trim_start().len();
        if here == indent {
            break;
        }
        if here == indent + 2 {
            if let Some(rest) = line.trim_start().strip_prefix('"') {
                keys.push(rest.split('"').next().unwrap_or_default().to_string());
            }
        }
    }
    keys
}

#[test]
fn word_style_closes_the_text_object_after_animation_case_and_words() {
    for extra in [
        json!({}),
        json!({ "animation": {"kind": "word_fade"}, "words": timings(), "word_style": full_style() }),
    ] {
        let written = Handle::from_value(&page(9, extra)).to_json();
        let keys = written_text_keys(&written);
        let tail: Vec<&str> = keys
            .iter()
            .rev()
            .take(5)
            .rev()
            .map(String::as_str)
            .collect();
        assert_eq!(
            tail,
            ["width", "animation", "case", "words", "word_style"],
            "the text object's keys, in written order: {keys:?}"
        );
    }
}

// ---- check_text, by name -------------------------------------------------

#[test]
fn a_count_mismatch_is_an_error_in_the_rules_own_words() {
    let handle = plain();
    let three = json!([
        {"start": 0, "end": 100000},
        {"start": 100000, "end": 200000},
        {"start": 200000, "end": 300000}
    ]);
    assert_eq!(
        handle.errors(&set_text(json!({ "words": three }))),
        "this text is timed word by word: 3 timings for 4 words"
    );
    // The count is `split_whitespace`: runs of spaces, tabs and newlines are
    // one separator, and leading and trailing ones are none.
    let timed = handle.apply(&set_text(json!({ "words": timings() })));
    assert_eq!(
        timed.errors(&set_text(json!({ "content": "so here's the thing now" }))),
        "this text is timed word by word: 4 timings for 5 words"
    );
    timed.apply(&set_text(
        json!({ "content": "  so\there's\n the   thing " }),
    ));
    // An empty list is untimed, whatever the content.
    timed.apply(&set_text(json!({ "content": "one", "words": [] })));
}

#[test]
fn every_word_rule_refuses_by_name() {
    let handle = plain();
    let max = 9_000_000_000_000_000_i64;
    let over = format!("must be between -{max} and {max} ticks, not");
    #[rustfmt::skip]
    let cases = [
        (json!([{"start": 0, "end": 1}, {"start": -max - 1, "end": 2}, {"start": 3, "end": 4}, {"start": 5, "end": 6}]),
         format!("text.words[1].start {over} {}", -max - 1)),
        (json!([{"start": 0, "end": 1}, {"start": 1, "end": 2}, {"start": 3, "end": max + 1}, {"start": 5, "end": 6}]),
         format!("text.words[2].end {over} {}", max + 1)),
        (json!([{"start": 0, "end": 1}, {"start": 200000, "end": 100000}, {"start": 300000, "end": 400000}, {"start": 400000, "end": 500000}]),
         "text.words[1].end must be at least its start 200000, not 100000".to_string()),
        (json!([{"start": 0, "end": 1}, {"start": 300000, "end": 400000}, {"start": 200000, "end": 400000}, {"start": 400000, "end": 500000}]),
         "text.words[2].start must not precede text.words[1].start 300000, not 200000".to_string()),
    ];
    for (words, message) in cases {
        assert_eq!(handle.errors(&set_text(json!({ "words": words }))), message);
    }
    // Equal starts, a zero-length word and a negative start are all legal.
    handle.apply(&set_text(json!({ "words": [
        {"start": -60000, "end": 0}, {"start": 0, "end": 0},
        {"start": 0, "end": 40000}, {"start": 40000, "end": 80000}
    ]})));
}

#[test]
fn every_style_rule_refuses_by_name() {
    let handle = plain();
    // Every sentence names the dotted key under `text.word_style.`.
    #[rustfmt::skip]
    let cases = [
        (json!({ "active_scale": 2.0 }), "active_scale must be between 1 and 1.5, not 2"),
        (json!({ "active_scale": 0.9 }), "active_scale must be between 1 and 1.5, not 0.9"),
        (json!({ "active_color": [2.0, 0.0, 0.0, 1.0] }), "active_color must be between 0 and 1, not 2"),
        (json!({ "spoken_color": [0.0, -1.0, 0.0, 1.0] }), "spoken_color must be between 0 and 1, not -1"),
        (json!({ "upcoming_color": [0.0, 0.0, 255.0, 1.0] }), "upcoming_color must be between 0 and 1, not 255"),
        (json!({ "active_pill": { "color": [0.0, 0.0, 0.0, 3.0] } }), "active_pill.color must be between 0 and 1, not 3"),
        (json!({ "active_pill": { "padding": -0.1 } }), "active_pill.padding must be at least 0, not -0.1"),
        (json!({ "active_pill": { "radius": -1.0 } }), "active_pill.radius must be at least 0, not -1"),
    ];
    for (style, message) in cases {
        let refused = handle.errors(&set_text(json!({ "word_style": style })));
        assert_eq!(refused, format!("text.word_style.{message}"));
    }
    // The bounds themselves are legal.
    for scale in [1.0, 1.5] {
        handle.apply(&set_text(
            json!({ "word_style": { "active_scale": scale } }),
        ));
    }
}

#[test]
fn a_new_title_is_held_to_the_same_rules() {
    let handle = plain();
    let add = |words: Value| {
        json!({ "op": "add_text_clip", "track": 2, "at": 7 * SEC,
                "text": { "content": "a b", "words": words } })
    };
    assert_eq!(
        handle.errors(&add(json!([{"start": 0, "end": 1}]))),
        "this text is timed word by word: 1 timings for 2 words"
    );
    let added = handle.apply(&add(
        json!([{"start": 0, "end": 20000}, {"start": 20000, "end": 40000}]),
    ));
    assert_eq!(array(&added.value(), "/clips/1/text/words").len(), 2);
}

#[test]
fn a_word_entry_must_name_both_its_times() {
    let handle = plain();
    let mut words = timings();
    words[0] = json!({ "start": 0 });
    assert_eq!(
        handle.errors(&set_text(json!({ "words": words }))),
        "missing key \"words[0].end\" in a text patch"
    );
    let mut words = timings();
    words[2] = json!({ "end": 348000 });
    assert_eq!(
        handle.errors(&set_text(json!({ "words": words }))),
        "missing key \"words[2].start\" in a text patch"
    );
}

#[test]
fn a_misspelt_or_mistyped_key_is_refused_by_name() {
    let handle = plain();
    let mut words = timings();
    words[1] = json!({ "start": 120000, "end": 276000, "stop": 1 });
    assert_eq!(
        handle.errors(&set_text(json!({ "words": words }))),
        "unknown key \"words[1].stop\" in a text patch"
    );
    let mut words = timings();
    words[3] = json!({ "start": 360000.5, "end": 618000 });
    common::assert_contains(
        &handle.errors(&set_text(json!({ "words": words }))),
        "bad value at \"words[3].start\" in a text patch: expected a whole number",
    );
    assert_eq!(
        handle.errors(&set_text(json!({ "word_style": { "active_pil": {} } }))),
        "unknown key \"word_style.active_pil\" in a text patch"
    );
    assert_eq!(
        handle.errors(&set_text(
            json!({ "word_style": { "active_pill": { "pad": 1.0 } } })
        )),
        "unknown key \"word_style.active_pill.pad\" in a text patch"
    );
    common::assert_contains(
        &handle.errors(&set_text(json!({ "case": "shouting" }))),
        "bad value at \"case\" in a text patch",
    );
    common::assert_contains(
        &handle.errors(&set_text(json!({ "word_style": { "mode": "karaoke" } }))),
        "bad value at \"word_style.mode\" in a text patch",
    );
}

// ---- W-6 -----------------------------------------------------------------

#[test]
fn words_are_not_an_animation_target() {
    let handle = plain()
        .apply(&set_text(json!({ "words": timings() })))
        .apply(&json!({ "op": "add_action", "clip": 11, "at": 0 }));
    let action = int(&handle.value(), "/clips/0/actions/0/id");
    let end = |patch: Value| json!({ "op": "set_action_end", "clip": 11, "action": action, "patch": patch });
    for patch in [
        json!({ "text": { "words": [] } }),
        json!({ "text": { "words": null } }),
        json!({ "text": { "color": [1.0, 0.0, 0.0, 1.0], "words": timings() } }),
    ] {
        assert_eq!(
            handle.errors(&end(patch)),
            "text.words is not an animation target"
        );
    }
    // The rest of the text group still animates.
    handle.apply(&end(json!({ "text": { "color": [1.0, 0.0, 0.0, 1.0] } })));
}

#[test]
fn paste_attributes_keeps_the_targets_words_with_its_content() {
    let styled = page(
        9,
        json!({ "case": "upper", "words": timings(), "word_style": full_style() }),
    );
    let mut project = styled.clone();
    project["clips"].as_array_mut().unwrap().push(json!({
        "id": 12, "track": 2, "start": 7 * SEC, "duration": 2 * SEC,
        "source": { "kind": "text" }, "video": {},
        "text": { "content": "a b", "words": [{"start": 0, "end": 20000}, {"start": 20000, "end": 40000}] }
    }));
    project["next_id"] = json!(13);
    let handle = Handle::from_value(&project);
    let payload = json!({ "clips": [handle.value()["clips"][0].clone()] });
    let pasted = handle
        .apply(&json!({ "op": "paste_attributes", "clips": [12], "payload": payload, "groups": ["text"] }))
        .value();
    assert_eq!(text(&pasted, "/clips/1/text/content"), "a b");
    assert_eq!(
        at(&pasted, "/clips/1/text/words"),
        &json!([{"start": 0, "end": 20000}, {"start": 20000, "end": 40000}])
    );
    assert_eq!(at(&pasted, "/clips/1/text/word_style"), &full_style());
    assert_eq!(text(&pasted, "/clips/1/text/case"), "upper");
    assert_eq!(at(&pasted, "/clips/1/text/size"), &json!(96.0));
}
