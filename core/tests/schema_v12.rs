//! Black-box tests for what format version 12 added — three word-caption
//! looks as keys of `text.word_style` (spec §11 W-12): `active_pill.glide`,
//! `active_fill` and `pause_dim` — driven through the C FFI exactly as
//! `ReelCore.swift` drives it.
//!
//! Pinned here: the SHAPE (every older file opens with the three keys off,
//! stamped the current version, and a version-11 style keeps every key it
//! had), the KEY ORDER read off the written text (`glide` closes the pill;
//! `active_fill` then `pause_dim` close the style), the ROUND TRIP (a page
//! with all three set, the same bytes twice) and the DOOR's merge (each key
//! patched alone leaves the others). What the keys DO over time — the
//! recipe's three answers — and the `pause_dim` refusals are
//! `word_looks.rs`'s.

mod common;

use reelcut_core::format::RC_FORMAT_VERSION;
use serde_json::{json, Value};

use common::{at, flag, num, Handle};

/// Ticks per second (spec §5.1), written out rather than imported.
const SEC: i64 = 600_000;

/// A version-11 word style: every one of its six keys filled, the pill's
/// three with it, and nothing at its default.
fn v11_style() -> Value {
    json!({
        "mode": "build",
        "active_color": [1.0, 0.85, 0.0, 1.0],
        "active_scale": 1.2,
        "active_pill": {"color": [0.1, 0.2, 0.3, 1.0], "padding": 0.18, "radius": 0.3},
        "spoken_color": [0.9, 0.9, 0.9, 1.0],
        "upcoming_color": [0.5, 0.5, 0.5, 1.0]
    })
}

/// The same style with the three looks on.
fn looks_style() -> Value {
    let mut style = v11_style();
    style["active_pill"]["glide"] = json!(true);
    style["active_fill"] = json!(true);
    style["pause_dim"] = json!(0.4);
    style
}

/// One track (id 2) and one six-second two-word page (id 11) carrying
/// `style`, or no `word_style` key at all for `None`, in a file of `version`.
fn page(version: u32, style: Option<Value>) -> Value {
    let mut group = json!({
        "content": "so here",
        "words": [{"start": 0, "end": 100000}, {"start": 120000, "end": 260000}]
    });
    if let Some(style) = style {
        group["word_style"] = style;
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

fn set_style(style: Value) -> Value {
    json!({ "op": "set_text", "clips": [11], "patch": { "word_style": style } })
}

const STYLE: &str = "/clips/0/text/word_style";

/// The keys of the first object opened by `opener`, in the order the
/// writer put them, read off the pretty-printed TEXT by indentation.
fn written_keys(written: &str, opener: &str) -> Vec<String> {
    let lines: Vec<&str> = written.lines().collect();
    let open = lines
        .iter()
        .position(|line| line.trim_start().starts_with(opener))
        .unwrap_or_else(|| panic!("no {opener} in:\n{written}"));
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

// ---- reading older files -------------------------------------------------

#[test]
fn every_older_styled_page_reads_with_the_three_looks_off() {
    // `word_style` arrived with version 9; an older file has no page to style.
    for version in [11, 10, 9] {
        let project = Handle::from_value(&page(version, Some(v11_style()))).value();
        assert_eq!(
            at(&project, "/version"),
            &json!(RC_FORMAT_VERSION),
            "version {version}"
        );
        let style = at(&project, STYLE);
        assert!(!flag(style, "/active_pill/glide"), "version {version}");
        assert!(!flag(style, "/active_fill"), "version {version}");
        assert_eq!(num(style, "/pause_dim"), 0.0, "version {version}");
    }
    for version in [8, 7, 6, 5, 4, 3, 2, 1] {
        let project = Handle::from_value(&page(version, None)).value();
        assert_eq!(at(&project, STYLE), &Value::Null, "version {version}");
    }
}

#[test]
fn a_version_11_style_keeps_its_keys_and_gains_three() {
    let before = v11_style();
    let project = Handle::from_value(&page(11, Some(before.clone()))).value();
    let had = before.as_object().expect("a style");
    let has = at(&project, STYLE).as_object().expect("a style");
    for (key, value) in had {
        if key != "active_pill" {
            assert_eq!(has.get(key), Some(value), "style key {key}");
        }
    }
    let had_pill = before["active_pill"].as_object().expect("a pill");
    let has_pill = has["active_pill"].as_object().expect("a pill");
    for (key, value) in had_pill {
        assert_eq!(has_pill.get(key), Some(value), "pill key {key}");
    }
    assert_eq!((had.len(), has.len()), (6, 8), "the style's keys");
    assert_eq!((had_pill.len(), has_pill.len()), (3, 4), "the pill's keys");
}

#[test]
fn the_derived_default_is_the_absence_of_the_keys() {
    let absent = Handle::from_value(&page(11, Some(v11_style())));
    let mut spelled = v11_style();
    spelled["active_pill"]["glide"] = json!(false);
    spelled["active_fill"] = json!(false);
    spelled["pause_dim"] = json!(0.0);
    let explicit = Handle::from_value(&page(RC_FORMAT_VERSION, Some(spelled)));
    assert_eq!(absent.to_json(), explicit.to_json());
}

// ---- the key order -------------------------------------------------------

#[test]
fn glide_closes_the_pill_and_active_fill_then_pause_dim_close_the_style() {
    for style in [v11_style(), looks_style()] {
        let written = Handle::from_value(&page(11, Some(style))).to_json();
        assert_eq!(
            written_keys(&written, "\"word_style\": {"),
            [
                "mode",
                "active_color",
                "active_scale",
                "active_pill",
                "spoken_color",
                "upcoming_color",
                "active_fill",
                "pause_dim"
            ],
            "the style's keys, in written order"
        );
        assert_eq!(
            written_keys(&written, "\"active_pill\": {"),
            ["color", "padding", "radius", "glide"],
            "the pill's keys, in written order"
        );
    }
}

#[test]
fn the_text_object_still_ends_with_word_style() {
    let written = Handle::from_value(&page(11, Some(looks_style()))).to_json();
    let keys = written_keys(&written, "\"text\": {");
    assert_eq!(keys.last().map(String::as_str), Some("word_style"));
}

// ---- the round trip ------------------------------------------------------

#[test]
fn a_page_with_all_three_looks_round_trips_twice() {
    let first = Handle::from_value(&page(RC_FORMAT_VERSION, Some(looks_style())));
    assert_eq!(at(&first.value(), STYLE), &looks_style());
    let written = first.to_json();
    let second = Handle::from_json(&written).to_json();
    assert_eq!(written, second, "the second write changed the bytes");
    let third = Handle::from_json(&second).to_json();
    assert_eq!(written, third, "the third write changed the bytes");
}

#[test]
fn a_style_with_no_pill_has_nowhere_to_glide() {
    let mut style = looks_style();
    style["active_pill"] = Value::Null;
    let project = Handle::from_value(&page(RC_FORMAT_VERSION, Some(style))).value();
    assert_eq!(
        at(&project, "/clips/0/text/word_style/active_pill"),
        &Value::Null
    );
    assert!(flag(&project, "/clips/0/text/word_style/active_fill"));
}

// ---- the patch door ------------------------------------------------------

#[test]
fn each_key_is_patched_alone_and_the_others_are_kept() {
    let handle = Handle::from_value(&page(11, Some(v11_style())));
    let glide = handle.apply(&set_style(json!({ "active_pill": { "glide": true } })));
    let mut expected = v11_style();
    expected["active_pill"]["glide"] = json!(true);
    expected["active_fill"] = json!(false);
    expected["pause_dim"] = json!(0.0);
    assert_eq!(at(&glide.value(), STYLE), &expected);

    let fill = glide.apply(&set_style(json!({ "active_fill": true })));
    expected["active_fill"] = json!(true);
    assert_eq!(at(&fill.value(), STYLE), &expected);

    let dim = fill.apply(&set_style(json!({ "pause_dim": 0.4 })));
    expected["pause_dim"] = json!(0.4);
    assert_eq!(at(&dim.value(), STYLE), &expected);
    assert_eq!(&expected, &looks_style());

    // Clearing the pill takes its `glide` with it; the other two stay.
    let cleared = dim
        .apply(&set_style(json!({ "active_pill": null })))
        .value();
    assert_eq!(
        at(&cleared, "/clips/0/text/word_style/active_pill"),
        &Value::Null
    );
    assert!(flag(&cleared, "/clips/0/text/word_style/active_fill"));
    assert_eq!(num(&cleared, "/clips/0/text/word_style/pause_dim"), 0.4);
}

#[test]
fn a_new_style_from_a_patch_has_the_three_looks_off() {
    let handle = Handle::from_value(&page(RC_FORMAT_VERSION, None));
    let styled = handle
        .apply(&set_style(json!({ "active_pill": {} })))
        .value();
    assert!(!flag(&styled, "/clips/0/text/word_style/active_pill/glide"));
    assert!(!flag(&styled, "/clips/0/text/word_style/active_fill"));
    assert_eq!(num(&styled, "/clips/0/text/word_style/pause_dim"), 0.0);
}

#[test]
fn a_wrong_kind_is_refused_naming_its_path() {
    let handle = Handle::from_value(&page(RC_FORMAT_VERSION, Some(v11_style())));
    for (style, path) in [
        (
            json!({ "active_pill": { "glide": 1 } }),
            "word_style.active_pill.glide",
        ),
        (json!({ "active_fill": "yes" }), "word_style.active_fill"),
        (json!({ "pause_dim": true }), "word_style.pause_dim"),
    ] {
        let message = handle.errors(&set_style(style));
        assert!(
            message.starts_with(&format!("bad value at \"{path}\" in a text patch")),
            "{message}"
        );
    }
    // The pill has no fifth key, and the style no ninth.
    assert_eq!(
        handle.errors(&set_style(json!({ "active_pill": { "slide": true } }))),
        "unknown key \"word_style.active_pill.slide\" in a text patch"
    );
    assert_eq!(
        handle.errors(&set_style(json!({ "glide": true }))),
        "unknown key \"word_style.glide\" in a text patch"
    );
}
