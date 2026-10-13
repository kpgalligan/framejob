//! Black-box tests for `rc_normalise_color` (spec §11 G-25 (c)), through the
//! C FFI as `ReelCore.swift`'s `ReelColor` drives it: G-12's one fixture,
//! `graphic/tests/colours.json`, which the engine's stdlib and the core's
//! `set_graphic` also answer — every accepted text to its stored hex, every
//! refused one to NULL.

mod common;

use std::ptr;

use serde_json::Value;

use common::{cstring, take_string};
use framejob_core::ffi::rc_normalise_color;

/// G-12's shared colour fixture, the engine's test file.
const COLOURS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../graphic/tests/colours.json");

fn normalise(text: &str) -> Option<String> {
    let text = cstring(text);
    take_string(unsafe { rc_normalise_color(text.as_ptr()) })
}

#[test]
fn the_export_answers_the_shared_colour_fixture() {
    let text = std::fs::read_to_string(COLOURS).expect("graphic/tests/colours.json");
    let fixture: Value = serde_json::from_str(&text).expect("the colour fixture is JSON");
    let accepted = fixture["accepted"].as_array().expect("accepted");
    let refused = fixture["refused"].as_array().expect("refused");
    assert!(!accepted.is_empty() && !refused.is_empty());
    for case in accepted {
        let sent = case[0].as_str().expect("a text");
        assert_eq!(normalise(sent).as_deref(), case[1].as_str(), "{sent:?}");
    }
    for sent in refused {
        let sent = sent.as_str().expect("a text");
        assert_eq!(normalise(sent), None, "{sent:?}");
    }
}

#[test]
fn a_null_or_non_utf8_text_is_null() {
    assert!(unsafe { rc_normalise_color(ptr::null()) }.is_null());
    let bytes = [0xffu8, 0xfe, 0];
    assert!(unsafe { rc_normalise_color(bytes.as_ptr().cast()) }.is_null());
}
