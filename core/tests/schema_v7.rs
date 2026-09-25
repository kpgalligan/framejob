//! Black-box tests for what format version 7 added — a transition's `curve`,
//! how the progress the compositor is handed is eased, and `audio`, whether
//! the two clips' sound crosses over with the picture (road map 5, E1) —
//! driven through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Seven things are pinned here:
//!
//! - **Every older file still opens, and opens as what it always drew.**
//!   Both fields carry a serde default, so there is no migration step and a
//!   version-1 … version-6 file reads back `linear` and `audio: false`,
//!   stamped version 7. The gate itself is `schema_v3.rs`'s claim and is
//!   not restated here.
//! - **`audio` is the LAST key of `transition_in` and `curve` the one
//!   before it**, read off the written TEXT, because a parsed `Value` sorts
//!   its keys and cannot tell. Declaration order is key order, so a
//!   version-6 file diffed against a version-7 one differs by two trailing
//!   keys rather than by a re-ordering.
//! - **The file default is the DERIVED default**, which is what makes the
//!   two fields safe to append to a shipped schema: an absent key and an
//!   explicit `linear` / `false` are the same value.
//! - **What the core MINTS is deliberately not that** (spec §11, R5-2):
//!   `Transition::minted` writes `ease_in_out` and `audio: true`, and the
//!   three sites that mint — `set_transition` on a clip that had none,
//!   `set_gained_transitions` when a clip gains an overlap, and (T2)
//!   `add_transition` — all agree. This file pins the first two; the third
//!   is `add_transition.rs`'s.
//! - **A kind change KEEPS the style.** `set_transition` on a clip that
//!   already has one moves only `kind`, which is the whole reason
//!   `set_transition_style` exists as a second op rather than as two more
//!   arguments on this one.
//! - **Every kind's spelling round-trips**, all thirteen, including the
//!   three wipe directions appended here. The JSON spelling is persisted,
//!   so a rename is silent data loss in a shipped file.
//! - **A version-6 overlap still renders LINEAR.** The eased progress is
//!   `transition.rs`'s and is proved against the recipe in `crossfade.rs`;
//!   what is pinned here is the other half of it — that a file written
//!   before the curve existed hands the compositor exactly the raw
//!   fraction it always did.
//!
//! What a curve or a crossfade DOES to a picture or to a mix is not a claim
//! this file can make: the eased recipe and the constant-power ramps are
//! `core/tests/crossfade.rs`'s, and the pixels are the compositor's. This
//! file owns the SHAPE, the DEFAULTS and where the two fields travel.

mod common;

use serde_json::{json, Value};

use common::{at, num, text, Handle};

/// Ticks per second (spec §5.1), written out rather than imported so a
/// change to `time::TIMESCALE` fails these tests instead of moving with
/// them.
const SEC: i64 = 600_000;

/// Every `TransitionKind` spelling, in declaration order — the last three
/// being version 7's. A kind added to the model and not to this line is a
/// kind this file does not round-trip.
const TRANSITION_KINDS: [&str; 13] = [
    "cross_dissolve",
    "fade_black",
    "fade_white",
    "push_left",
    "push_right",
    "push_up",
    "push_down",
    "wipe",
    "slide",
    "zoom",
    "wipe_left",
    "wipe_up",
    "wipe_down",
];

/// Every `Curve` spelling, in declaration order.
const CURVES: [&str; 4] = ["linear", "ease_in", "ease_out", "ease_in_out"];

// ---- fixtures ------------------------------------------------------------

fn video_media(id: u32) -> Value {
    json!({
        "id": id, "path": format!("/fixtures/{id}.mov"), "kind": "video",
        "duration": 60 * SEC, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": true, "has_audio": true
    })
}

/// One media, one track (id 2), and two clips that OVERLAP by one second —
/// 0…6 s and 5…11 s — with the later one carrying a `transition_in` spelled
/// the way a file of `version` was written: a bare `kind` and nothing else.
///
/// An overlap rather than a hard cut, because a `transition_in` only means
/// anything where there is one, and because the recipe claim at the foot of
/// the file needs a frame inside it.
fn overlapping(version: u32, kind: &str) -> Value {
    json!({
        "version": version,
        "canvas": { "width": 1920, "height": 1080, "fps": [30, 1] },
        "media": [video_media(1)],
        "tracks": [{ "id": 2, "name": "Track 1" }],
        "clips": [
            {
                "id": 11, "track": 2, "start": 0, "duration": 6 * SEC,
                "source": { "kind": "media", "media": 1, "in": 0 },
                "video": {}, "audio": {}
            },
            {
                "id": 12, "track": 2, "start": 5 * SEC, "duration": 6 * SEC,
                "source": { "kind": "media", "media": 1, "in": 5 * SEC },
                "video": {}, "audio": {},
                "transition_in": { "kind": kind }
            }
        ],
        "next_id": 13
    })
}

/// [`overlapping`] at the current version, wiping — the handle the op tests
/// patch.
fn plain() -> Handle {
    Handle::from_value(&overlapping(7, "wipe"))
}

/// Two clips that merely TOUCH — a hard cut at 6 s — so `set_transition` and
/// `set_transition_style` can be asked about a clip with no overlap, which
/// they are both defined to accept.
fn abutting() -> Handle {
    let mut project = overlapping(7, "wipe");
    project["clips"][1]["start"] = json!(6 * SEC);
    project["clips"][1]["transition_in"] = Value::Null;
    Handle::from_value(&project)
}

fn set_transition(kind: Value) -> Value {
    json!({ "op": "set_transition", "clip": 12, "kind": kind })
}

// ---- reading older files -------------------------------------------------

fn assert_file_default(project: &Value) {
    assert_eq!(at(project, "/version"), &json!(10));
    let transition = at(project, "/clips/1/transition_in");
    assert_eq!(text(transition, "/kind"), "wipe");
    assert_eq!(text(transition, "/curve"), "linear");
    assert_eq!(at(transition, "/audio"), &json!(false));
    // The neighbours a version-7 reader adds nothing to, so a file that
    // gained two defaulted keys gained ONLY those.
    assert_eq!(at(project, "/clips/0/transition_in"), &Value::Null);
    assert_eq!(num(project, "/clips/1/start"), (5 * SEC) as f64);
}

#[test]
fn a_version_six_file_reads_linear_and_silent() {
    // Both fields carry a serde default, so a file written before the
    // feature existed opens untouched and comes back as a version-7 project
    // drawing and sounding exactly what it did: a raw progress, and no
    // crossfade.
    assert_file_default(&Handle::from_value(&overlapping(6, "wipe")).value());
}

#[test]
fn every_older_version_reads_the_same_way() {
    // The migration chain still runs underneath: a version-1 file reaches
    // version 7 through `migrate_1_to_2` and then through nothing at all,
    // because none of versions 3, 4, 5, 6 and 7 needed a rewrite.
    for version in [5, 4, 3, 2, 1] {
        assert_file_default(&Handle::from_value(&overlapping(version, "wipe")).value());
    }
}

#[test]
fn the_derived_default_is_the_absence_of_the_keys() {
    // The property the two fields rest on, and the reason they were safe to
    // append: a transition written with only a `kind`, one written with
    // both keys at their defaults, and one the reader filled in must all be
    // the same value.
    let absent = Handle::from_value(&overlapping(7, "slide")).value();
    let mut explicit_source = overlapping(7, "slide");
    explicit_source["clips"][1]["transition_in"] =
        json!({ "kind": "slide", "curve": "linear", "audio": false });
    let explicit = Handle::from_value(&explicit_source).value();
    assert_eq!(
        at(&absent, "/clips/1/transition_in"),
        at(&explicit, "/clips/1/transition_in")
    );
}

// ---- the round trip ------------------------------------------------------

#[test]
fn a_curve_and_a_crossfade_round_trip_exactly() {
    let mut source = overlapping(7, "wipe_up");
    source["clips"][1]["transition_in"] =
        json!({ "kind": "wipe_up", "curve": "ease_out", "audio": true });
    let written = Handle::from_value(&source).value();
    assert_eq!(at(&written, "/version"), &json!(10));
    assert_eq!(
        at(&written, "/clips/1/transition_in"),
        &json!({ "kind": "wipe_up", "curve": "ease_out", "audio": true }),
        "the whole object, key for key"
    );
}

#[test]
fn every_transition_kind_survives_a_write_and_a_read() {
    // Thirteen spellings, each persisted. The declaration order is NOT a
    // shader discriminant here — `Compositor.swift` maps each name to a code
    // by hand — but the SPELLING is the wire format, so a renamed variant is
    // silent data loss in a shipped file. Naming all thirteen is what makes
    // that fail a test instead of a project.
    for kind in TRANSITION_KINDS {
        let written = Handle::from_value(&overlapping(7, kind)).value();
        assert_eq!(text(&written, "/clips/1/transition_in/kind"), kind);
    }
}

#[test]
fn every_curve_survives_a_write_and_a_read() {
    for curve in CURVES {
        let mut source = overlapping(7, "wipe");
        source["clips"][1]["transition_in"] = json!({ "kind": "wipe", "curve": curve });
        let written = Handle::from_value(&source).value();
        assert_eq!(text(&written, "/clips/1/transition_in/curve"), curve);
        // ...and `audio` still defaults beside it, so neither key's presence
        // drags the other along.
        assert_eq!(at(&written, "/clips/1/transition_in/audio"), &json!(false));
    }
}

#[test]
fn audio_is_the_last_key_of_the_transition_object() {
    // Declaration order IS key order, and `audio` is the last field of
    // `Transition` with `curve` before it, so a version-6 file diffed
    // against a version-7 one differs by two trailing keys rather than by a
    // re-ordering. Read off the written TEXT, because a `Value` sorts its
    // keys and cannot tell.
    let mut source = overlapping(7, "zoom");
    source["clips"][1]["transition_in"] =
        json!({ "kind": "zoom", "curve": "ease_in", "audio": true });
    let first = Handle::from_value(&source).to_json();
    let group = &first[first
        .find("\"transition_in\": {")
        .unwrap_or_else(|| panic!("no transition_in in the written text:\n{first}"))..];
    let position = |needle: &str| {
        group
            .find(needle)
            .unwrap_or_else(|| panic!("no {needle:?} in the transition object:\n{group}"))
    };
    assert!(position("\"kind\"") < position("\"curve\""));
    assert!(position("\"curve\"") < position("\"audio\""));
    // ...and it CLOSES the object: the flag, then the transition object's
    // own closing brace, with nothing between them.
    assert!(
        first.contains("\"audio\": true\n      }"),
        "audio does not close the transition object:\n{first}"
    );

    // A second trip through the text is byte-identical to the first, which
    // is what lets Swift compare project strings at all.
    let second = Handle::from_json(&first).to_json();
    assert_eq!(first, second, "a second round trip changed the bytes");
}

// ---- what the core mints -------------------------------------------------

#[test]
fn set_transition_on_a_clip_with_none_mints_an_eased_crossfading_transition() {
    // Spec §11, R5-2: what a NEW transition is differs from what an OLD
    // file's transition is, on purpose. A person choosing a kind on a clip
    // that had none is asking for a transition NOW.
    let minted = abutting()
        .apply(&set_transition(json!("wipe_down")))
        .value();
    assert_eq!(
        at(&minted, "/clips/1/transition_in"),
        &json!({ "kind": "wipe_down", "curve": "ease_in_out", "audio": true })
    );
}

#[test]
fn a_kind_change_keeps_the_curve_and_the_crossfade() {
    // The collision this rule exists to prevent: a kind chosen from the
    // popup, the Clip menu or MCP must not reset a curve somebody set.
    let mut source = overlapping(7, "wipe");
    source["clips"][1]["transition_in"] =
        json!({ "kind": "wipe", "curve": "ease_out", "audio": true });
    let changed = Handle::from_value(&source)
        .apply(&set_transition(json!("slide")))
        .value();
    assert_eq!(
        at(&changed, "/clips/1/transition_in"),
        &json!({ "kind": "slide", "curve": "ease_out", "audio": true })
    );

    // Including the style a version-6 file brought with it, which is the
    // case that would otherwise silently gain a crossfade.
    let older = Handle::from_value(&overlapping(6, "wipe"))
        .apply(&set_transition(json!("zoom")))
        .value();
    assert_eq!(
        at(&older, "/clips/1/transition_in"),
        &json!({ "kind": "zoom", "curve": "linear", "audio": false })
    );
}

#[test]
fn clearing_and_re_setting_a_kind_mints_rather_than_restores() {
    // The honest consequence of the rule above, said out loud: a clear
    // throws the style away with the kind, so setting one again is a NEW
    // transition and comes back minted. There is nowhere for a cleared
    // curve to have been kept.
    let cleared = plain().apply(&set_transition(Value::Null));
    assert_eq!(at(&cleared.value(), "/clips/1/transition_in"), &Value::Null);
    let again = cleared.apply(&set_transition(json!("wipe"))).value();
    assert_eq!(
        at(&again, "/clips/1/transition_in"),
        &json!({ "kind": "wipe", "curve": "ease_in_out", "audio": true })
    );
}

#[test]
fn a_clip_that_gains_an_overlap_gains_a_minted_transition() {
    // `set_gained_transitions` is the second minting site: an overlap IS a
    // transition (spec §5.2), so a clip dragged onto its predecessor gets
    // one — and from version 7 it is minted rather than the file default.
    let moved = abutting()
        .apply(&json!({ "op": "move_clip", "clips": [12], "delta": -SEC }))
        .value();
    assert_eq!(
        at(&moved, "/clips/1/transition_in"),
        &json!({ "kind": "cross_dissolve", "curve": "ease_in_out", "audio": true })
    );
}

// ---- what the recipe carries ---------------------------------------------

#[test]
fn a_version_six_overlap_still_hands_the_compositor_the_raw_progress() {
    // The other half of the easing claim (`crossfade.rs` owns the eased
    // one): a file written before the curve existed is `linear`, and
    // `actions::ease(Linear, p)` is the identity, so every frame of every
    // shipped project's transitions is exactly what it was.
    let handle = Handle::from_value(&overlapping(6, "push_left"));
    let start = 5 * SEC;
    for step in [0, SEC / 4, SEC / 2, 3 * SEC / 4] {
        let recipe = handle.recipe(start + step);
        let layers = common::array(&recipe, "/layers");
        let incoming = layers
            .iter()
            .find(|l| l["clip"] == json!(12))
            .expect("the incoming clip draws inside the overlap");
        let progress = num(incoming, "/transition/progress");
        let expected = step as f64 / SEC as f64;
        assert!(
            (progress - expected).abs() < 1e-9,
            "progress at +{step} is {progress}, expected the raw {expected}"
        );
    }
}
