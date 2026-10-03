//! A media's `original` (spec §11 #228-O), through the FFI: the WebM or
//! Matroska file a playable copy was made from. `add_media` stores it with
//! its path trimmed and a blank bookmark dropped, and refuses an empty path
//! in its own words; a relink's probe carries it, so a probe with one sets
//! it, a probe without one clears it, and no probe keeps it; a paste brings
//! the media row along with it. The schema and key order are
//! `schema_v11.rs`'s.

mod common;

use serde_json::{json, Value};

use common::{at, Handle};

/// Ticks per second (spec §5.1), written out rather than imported.
const SEC: i64 = 600_000;

const COPY: &str = "/r/talk-0123456789abcdef.mov";
const ORIGINAL: &str = "/m/talk.webm";

/// A five-second 1280×720 video descriptor at `path`, with `original`
/// merged in when it is not `Value::Null`.
fn descriptor(path: &str, original: Value) -> Value {
    let mut given = json!({
        "path": path, "kind": "video", "duration": 5 * SEC, "width": 1280,
        "height": 720, "fps": [30, 1], "has_video": true, "has_audio": true,
        "has_alpha": false
    });
    if !original.is_null() {
        given["original"] = original;
    }
    given
}

/// The probe a relink carries: the descriptor minus `path` and `bookmark`.
fn probe(original: Value) -> Value {
    let mut given = descriptor(COPY, original);
    if let Some(fields) = given.as_object_mut() {
        fields.remove("path");
    }
    given
}

fn add(original: Value) -> Value {
    json!({"op": "add_media", "descriptor": descriptor(COPY, original)})
}

/// A project whose media 2 is the copy, made from `ORIGINAL`.
fn with_copy() -> Handle {
    Handle::new(1920, 1080, 30, 1).apply(&add(json!({"path": ORIGINAL, "bookmark": "T1JJRw=="})))
}

fn relink(probe: Option<Value>) -> Value {
    let mut op = json!({"op": "relink_media", "media": 2, "path": "/r/next.mov",
                        "bookmark": "TkVYVA=="});
    if let Some(probe) = probe {
        op["probe"] = probe;
    }
    op
}

// ---- add_media -----------------------------------------------------------

#[test]
fn add_media_stores_the_original() {
    let project = with_copy().value();
    assert_eq!(at(&project, "/media/0/path"), &json!(COPY));
    assert_eq!(
        at(&project, "/media/0/original"),
        &json!({"path": ORIGINAL, "bookmark": "T1JJRw=="})
    );
}

#[test]
fn add_media_trims_the_original_path() {
    let project = Handle::new(1920, 1080, 30, 1)
        .apply(&add(json!({"path": "  /m/talk.webm \n"})))
        .value();
    assert_eq!(
        at(&project, "/media/0/original"),
        &json!({"path": ORIGINAL, "bookmark": null})
    );
}

#[test]
fn a_blank_original_path_is_an_error_in_its_own_words() {
    let project = Handle::new(1920, 1080, 30, 1);
    for blank in ["", "   "] {
        assert_eq!(
            project.errors(&add(json!({"path": blank}))),
            "media original path must not be empty"
        );
    }
}

#[test]
fn a_blank_original_bookmark_is_stored_as_null() {
    let project = Handle::new(1920, 1080, 30, 1)
        .apply(&add(json!({"path": ORIGINAL, "bookmark": "  "})))
        .value();
    assert_eq!(
        at(&project, "/media/0/original"),
        &json!({"path": ORIGINAL, "bookmark": null})
    );
}

#[test]
fn an_original_with_no_path_is_a_schema_error() {
    let message = Handle::new(1920, 1080, 30, 1).errors(&add(json!({"bookmark": "QQ=="})));
    assert!(
        message.starts_with("media descriptor does not match the schema: "),
        "{message}"
    );
}

// ---- relink_media --------------------------------------------------------

#[test]
fn a_probe_with_an_original_sets_it() {
    let project = with_copy()
        .apply(&relink(Some(probe(json!({"path": "/m/next.mkv"})))))
        .value();
    assert_eq!(at(&project, "/media/0/path"), &json!("/r/next.mov"));
    assert_eq!(
        at(&project, "/media/0/original"),
        &json!({"path": "/m/next.mkv", "bookmark": null})
    );
}

#[test]
fn a_probe_without_an_original_clears_it() {
    let project = with_copy().apply(&relink(Some(probe(Value::Null)))).value();
    assert_eq!(at(&project, "/media/0/original"), &Value::Null);
}

#[test]
fn no_probe_keeps_the_original() {
    let project = with_copy().apply(&relink(None)).value();
    assert_eq!(at(&project, "/media/0/path"), &json!("/r/next.mov"));
    assert_eq!(
        at(&project, "/media/0/original"),
        &json!({"path": ORIGINAL, "bookmark": "T1JJRw=="})
    );
}

#[test]
fn original_in_a_probe_is_not_an_unknown_key() {
    let answer = with_copy().try_apply(&relink(Some(probe(json!({"path": ORIGINAL})))));
    assert!(answer.is_ok(), "{answer:?}");
}

#[test]
fn a_blank_original_path_in_a_probe_is_the_same_error() {
    assert_eq!(
        with_copy().errors(&relink(Some(probe(json!({"path": " "}))))),
        "media original path must not be empty"
    );
}

// ---- paste ---------------------------------------------------------------

#[test]
fn paste_carries_the_original() {
    let payload = json!({
        "clips": [{"id": 7, "track": 0, "start": 0, "duration": 2 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0},
                   "video": {}, "audio": {}}],
        "media": [{"id": 1, "path": COPY, "kind": "video", "duration": 5 * SEC,
                   "width": 1280, "height": 720, "fps": [30, 1],
                   "has_video": true, "has_audio": true, "has_alpha": false,
                   "original": {"path": ORIGINAL, "bookmark": "T1JJRw=="}}]
    });
    let project = Handle::new(1920, 1080, 30, 1)
        .apply(&json!({"op": "paste", "at": 0, "payload": payload}))
        .value();
    assert_eq!(at(&project, "/media/0/path"), &json!(COPY));
    assert_eq!(
        at(&project, "/media/0/original"),
        &json!({"path": ORIGINAL, "bookmark": "T1JJRw=="})
    );
}
