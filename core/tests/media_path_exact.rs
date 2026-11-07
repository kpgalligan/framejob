//! A media path is stored and compared as given, never trimmed (spec §11
//! #534), through `rc_project_apply`: `add_media`'s `path` and `original`,
//! a pasted media row's `path` and `relink_media`'s `path`. A file whose
//! name ends in a space (`A.mov `) is a file of its own beside `A.mov`, and
//! a path that is blank, or only spaces, is still refused.

mod common;

use serde_json::{json, Value};

use common::{array, at, Handle, Outcome};

const SEC: i64 = 600_000;

fn descriptor(path: &str) -> Value {
    json!({"path": path, "kind": "video", "duration": 36_000_000, "width": 1920,
           "height": 1080, "fps": [30, 1], "has_video": true, "has_audio": false})
}

fn add(path: &str) -> Value {
    json!({"op": "add_media", "descriptor": descriptor(path)})
}

fn paths(project: &Handle) -> Vec<String> {
    array(&project.value(), "/media")
        .iter()
        .map(|m| m["path"].as_str().unwrap().to_string())
        .collect()
}

fn empty() -> Handle {
    Handle::new(1920, 1080, 30, 1)
}

#[test]
fn add_media_keeps_trailing_and_leading_spaces() {
    for path in ["/m/A.mov ", "  /m/A.mov", " /m/A.mov \n"] {
        let project = empty().apply(&add(path));
        assert_eq!(paths(&project), vec![path.to_string()]);
    }
}

#[test]
fn a_spaced_name_and_its_sibling_are_two_rows_in_either_order() {
    for (first, second) in [("/m/A.mov ", "/m/A.mov"), ("/m/A.mov", "/m/A.mov ")] {
        let project = empty().apply(&add(first)).apply(&add(second));
        assert_eq!(paths(&project), vec![first.to_string(), second.to_string()]);
    }
}

#[test]
fn the_same_path_byte_for_byte_is_still_an_identity() {
    let project = empty().apply(&add("/m/A.mov "));
    assert!(matches!(
        project.try_apply(&add("/m/A.mov ")),
        Ok(Outcome::Identity)
    ));
}

#[test]
fn an_original_keeps_its_spaces() {
    let mut d = descriptor("/r/A-0123.mov");
    d["original"] = json!({"path": "/m/A.mov "});
    let project = empty().apply(&json!({"op": "add_media", "descriptor": d}));
    assert_eq!(
        at(&project.value(), "/media/0/original/path"),
        &json!("/m/A.mov ")
    );
}

#[test]
fn a_blank_path_is_still_refused_at_every_door() {
    for blank in ["", "   "] {
        assert_eq!(empty().errors(&add(blank)), "media path must not be empty");
    }
    let project = empty().apply(&add("/m/A.mov"));
    let id = at(&project.value(), "/media/0/id").clone();
    assert_eq!(
        project.errors(&json!({"op": "relink_media", "media": id, "path": "   "})),
        "media path must not be empty"
    );
    assert_eq!(
        project.errors(&paste_of("   ")),
        "a pasted media path must not be empty"
    );
}

/// A paste of one clip showing payload media 7 at `path`.
fn paste_of(path: &str) -> Value {
    let mut row = descriptor(path);
    row["id"] = json!(7);
    json!({"op": "paste", "at": 0, "payload": {
        "clips": [{"id": 3, "track": 0, "start": 0, "duration": SEC, "speed": 1.0,
                   "source": {"kind": "media", "media": 7, "in": 0},
                   "enabled": {"video": true, "audio": false}, "video": {}}],
        "media": [row]
    }})
}

#[test]
fn a_pasted_row_is_matched_and_stored_as_given() {
    // A spaced row beside its sibling is appended, not matched.
    let project = empty().apply(&add("/m/A.mov"));
    let pasted = project.apply(&paste_of("/m/A.mov "));
    assert_eq!(
        paths(&pasted),
        vec!["/m/A.mov".to_string(), "/m/A.mov ".to_string()]
    );
    // The same spaced path is matched.
    let again = pasted.apply(&paste_of("/m/A.mov "));
    assert_eq!(paths(&again).len(), 2);
}

#[test]
fn relink_media_stores_the_path_as_given() {
    let project = empty().apply(&add("/m/A.mov"));
    let id = at(&project.value(), "/media/0/id").clone();
    let relinked = project.apply(&json!({"op": "relink_media", "media": id, "path": " /m/B.mov "}));
    assert_eq!(paths(&relinked), vec![" /m/B.mov ".to_string()]);
}
