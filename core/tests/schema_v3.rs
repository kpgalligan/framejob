//! Black-box tests for what format version 3 added — clip identity: a
//! clip's own `name` and colour `label`, and a track's `solo` — driven
//! through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! Four things are pinned here, and each is a promise the rest of phase 2
//! leans on:
//!
//! - **A version-2 file still opens, and a version-1 one too.** All three
//!   fields carry a serde default, so there is no migration step; what a
//!   file that never heard of them reads back as is `null`, `null` and
//!   `false`, stamped version 3.
//! - **The schema stores what it is given.** A name round-trips with its
//!   surrounding spaces: trimming is an OP's job (`set_clip`), never the
//!   reader's, so a file is never rewritten just by being opened.
//! - **A file from the future is refused with the exact message.** The
//!   version gate is the only thing that stops a version-2 build from
//!   silently dropping every name and label in a newer file (unknown keys
//!   are ignored, by design — `model.rs`'s module doc), so the bump has to
//!   be there even though no field needed rewriting. The number the test
//!   uses tracks `RC_FORMAT_VERSION` + 1; the claim is about the gate, not
//!   about any one version.
//! - **Identity travels with the clip, and no further.** A split clone
//!   carries name and label to both halves (`duplicate`, `detach_audio` and
//!   `paste` clone the same way); `nest` copies `solo` into the nest's own
//!   track the way it copies `muted`, while the nest CLIP it makes has no
//!   name of its own; and a clip or track an op creates has none either —
//!   the literal defaults, as distinct from the serde ones.
//!
//! What a solo DOES — which tracks fall silent — is `audio.rs`'s claim and
//! is proved beside the other envelope rules in `evaluate_tests.rs` and
//! `nest.rs`. This file owns the SHAPE.

mod common;

use serde_json::{json, Value};

use common::{array, at, by_id, flag, int, text, Handle};

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
/// and spelled the way a file of that version was written: no `name`,
/// `label` or `solo` key anywhere.
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

/// The name every identified clip below carries, with surrounding spaces
/// on purpose: the schema must hand them back untouched.
const NAME: &str = "  Talk, take 2  ";

/// [`one_clip`] as a version-3 file holds it: the track soloed, the clip
/// named and labelled.
fn identified() -> Value {
    let mut project = one_clip(3);
    project["tracks"][0]["solo"] = json!(true);
    project["clips"][0]["name"] = json!(NAME);
    project["clips"][0]["label"] = json!("blue");
    project
}

fn assert_identity_defaults(project: &Value) {
    assert_eq!(at(project, "/version"), &json!(9));
    assert_eq!(at(project, "/clips/0/name"), &Value::Null);
    assert_eq!(at(project, "/clips/0/label"), &Value::Null);
    assert_eq!(at(project, "/tracks/0/solo"), &json!(false));
}

// ---- reading older files -------------------------------------------------

#[test]
fn a_version_two_file_reads_with_the_identity_fields_at_their_defaults() {
    // Every new field carries a serde default, so a file written before
    // any of this existed opens untouched and comes back as a
    // current-version project with no names, no labels and nothing soloed.
    assert_identity_defaults(&Handle::from_value(&one_clip(2)).value());
}

#[test]
fn a_version_one_file_reads_the_same_way() {
    // The migration chain still runs underneath: a version-1 file reaches
    // the current version through `migrate_1_to_2` and then through
    // nothing at all, because no version since has needed a rewrite.
    assert_identity_defaults(&Handle::from_value(&one_clip(1)).value());
}

#[test]
fn a_file_one_version_newer_is_refused_with_the_exact_message() {
    // 10 is ONE PAST the current version, and it has to move with every
    // bump: the moment RC_FORMAT_VERSION reaches the number written here,
    // this stops testing the gate and starts testing that a current file
    // opens. The comment says "one past the current version" rather than a
    // number so the next bump does not have to rediscover that.
    let msg = Handle::try_from_value(&json!({ "version": 10 }))
        .expect_err("a newer format version must be refused");
    assert_eq!(
        msg,
        "project format version 10 is newer than this build understands (version 9); \
         update Reelcut to open it"
    );
}

// ---- the round trip ------------------------------------------------------

#[test]
fn name_label_and_solo_round_trip_exactly() {
    // The schema stores what it is given. The name keeps its surrounding
    // spaces: trimming is `set_clip`'s job, and a reader that tidied would
    // rewrite a file just by opening it.
    let written = Handle::from_value(&identified()).value();
    assert_eq!(at(&written, "/version"), &json!(9));
    assert_eq!(text(&written, "/clips/0/name"), NAME);
    assert_eq!(text(&written, "/clips/0/label"), "blue");
    assert!(flag(&written, "/tracks/0/solo"));

    // The keys sit at the END of their objects — declaration order is key
    // order, so a version-2 file diffed against this one differs by
    // trailing keys, not by a re-ordering. Read off the written TEXT,
    // because a `Value` sorts its keys and cannot tell.
    let first = Handle::from_value(&identified()).to_json();
    let position = |needle: &str| {
        first
            .find(needle)
            .unwrap_or_else(|| panic!("no {needle:?} in the written text"))
    };
    let name = format!("\"name\": \"{NAME}\"");
    assert!(position("\"transition_in\": null") < position(&name));
    assert!(position(&name) < position("\"label\": \"blue\""));
    // ...and each is the LAST key of its object: the next thing after it
    // is the object's closing brace.
    assert!(
        first.contains("\"label\": \"blue\"\n    }"),
        "label closes the clip"
    );
    assert!(
        first.contains("\"solo\": true\n    }"),
        "solo closes the track"
    );

    // A second trip through the text is byte-identical to the first, which
    // is what lets Swift compare project strings at all.
    let second = Handle::from_json(&first).to_json();
    assert_eq!(first, second, "a second round trip changed the bytes");
}

#[test]
fn an_explicit_null_reads_as_no_name_and_no_label() {
    // An explicit `null` and an absent key are the same thing, and both are
    // written back as `null` — there is no third state for a name to be
    // in, which is what lets `set_clip` clear one with a null.
    let mut cleared = identified();
    cleared["clips"][0]["name"] = Value::Null;
    cleared["clips"][0]["label"] = Value::Null;
    let written = Handle::from_value(&cleared).value();
    assert_eq!(at(&written, "/clips/0/name"), &Value::Null);
    assert_eq!(at(&written, "/clips/0/label"), &Value::Null);
    assert!(
        flag(&written, "/tracks/0/solo"),
        "the track was not touched"
    );
}

// ---- where identity travels ----------------------------------------------

#[test]
fn a_split_carries_the_name_and_label_to_both_halves() {
    // `split` clones the clip into its second half, so identity travels:
    // both halves of "Talk, take 2" are "Talk, take 2", and both are blue.
    // The same clone is what `duplicate`, `detach_audio` and `paste` do.
    let project = Handle::from_value(&identified());
    let after = project.apply(&json!({ "op": "split", "clips": [11], "at": 4 * SEC }));
    let value = after.value();
    let clips = array(&value, "/clips");
    assert_eq!(clips.len(), 2, "one cut makes two clips");
    for clip in clips {
        let id = int(clip, "/id");
        assert_eq!(text(clip, "/name"), NAME, "clip {id}'s name");
        assert_eq!(text(clip, "/label"), "blue", "clip {id}'s label");
    }
    let starts: Vec<i64> = clips.iter().map(|c| int(c, "/start")).collect();
    assert_eq!(
        starts,
        [0, 4 * SEC],
        "the halves sit either side of the cut"
    );
}

#[test]
fn nesting_carries_a_soloed_track_into_the_nest() {
    // The mirror of `nest.rs`'s muted test: the solo belongs to the track,
    // the timeline's track stays behind, and the nest's own track takes a
    // copy — so what played before nesting plays after, judged now among
    // the nest's own tracks. The nest CLIP itself is a new clip and has no
    // name; the clip inside keeps its own.
    let project = Handle::from_value(&identified());
    let nest_id = int(&project.value(), "/next_id") as u64;
    let after = project.apply(&json!({ "op": "nest", "clips": [11] }));

    let value = after.value();
    let nest = by_id(&value, "/nests", nest_id);
    assert!(
        flag(&array(nest, "/tracks")[0], "/solo"),
        "the solo came too"
    );
    assert!(
        flag(&value, "/tracks/0/solo"),
        "the timeline's track keeps its own"
    );
    assert_eq!(text(&array(nest, "/clips")[0], "/name"), NAME);
    assert_eq!(text(&array(nest, "/clips")[0], "/label"), "blue");
    assert_eq!(
        at(&value, "/clips/0/name"),
        &Value::Null,
        "the nest clip is unnamed"
    );
    assert_eq!(at(&value, "/clips/0/label"), &Value::Null);
}

#[test]
fn a_clip_or_track_an_op_creates_has_no_identity_of_its_own() {
    // The literal defaults, as distinct from the serde ones: a new text
    // clip is unnamed and unlabelled, and a new track is not soloed.
    let project = Handle::from_value(&one_clip(3));
    let after = project.apply_all(&[
        json!({ "op": "add_text_clip", "track": 2, "at": 20 * SEC }),
        json!({ "op": "add_track" }),
    ]);
    let value = after.value();
    assert_eq!(at(&value, "/clips/1/name"), &Value::Null);
    assert_eq!(at(&value, "/clips/1/label"), &Value::Null);
    assert_eq!(at(&value, "/tracks/1/solo"), &json!(false));
}
