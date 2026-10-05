//! Black-box tests for `paste_attributes`' fifth group, `graphic`, and its
//! `skip_missing` flag (spec §11 G-32), through the C FFI as `ReelCore.swift`
//! drives it: what travels and what a target keeps, the props' key ORDER
//! (read off the written text), that a paste naming no group still copies
//! no props, the three sentences of a named group, what the flag skips, and
//! WHEN the copied map is read. The four layer groups are `paste.rs`'s.

mod common;

use serde_json::{json, Map, Value};

use common::{array, int, Handle, Outcome};

/// Ticks per second (spec §5.1), written out rather than imported.
const SEC: i64 = 600_000;

/// G-32 (c)'s sentence for a target drawn by another module.
const OTHER_MODULE: &str = "clip 22 is drawn by \"title-card\" and the payload clip by \
     \"lower-third\"; graphic props are pasted only between clips of one module";

/// The timeline: media clip 10; `lower-third` clips 20 (A) and 21 (B), which
/// differ in props, key order, size, `in`, `length` and video; `title-card`
/// clip 22; text clip 23; and nest clip 30 showing nest 40, which holds two
/// more `lower-third` clips, 42 and 43. Clip 21 is the LAST clip of the
/// array, so its graphic is the last `"lower-third"` the written text holds
/// before its `nests`.
fn project() -> Handle {
    Handle::from_value(&json!({
        "version": 10,
        "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "media": [{"id": 1, "path": "/m/talk.mov", "kind": "video",
                   "duration": 60 * SEC, "width": 1920, "height": 1080,
                   "fps": [30, 1], "has_video": true, "has_audio": true}],
        "tracks": [{"id": 2, "name": "V"}, {"id": 3, "name": "G"},
                   {"id": 4, "name": "T"}, {"id": 5, "name": "N"}],
        "clips": [
            {"id": 10, "track": 2, "start": 0, "duration": 2 * SEC,
             "source": {"kind": "media", "media": 1, "in": 0},
             "video": {}, "audio": {"volume": 0.5}},
            {"id": 20, "track": 3, "start": 0, "duration": 5 * SEC,
             "source": {"kind": "graphic"}, "video": {"opacity": 0.5, "x": 40.0},
             "graphic": {"name": "lower-third", "width": 1920, "height": 1080,
                         "props": {"title": "Ada", "accent": "#ff0000",
                                   "subtitle": "Host"}}},
            {"id": 22, "track": 4, "start": 0, "duration": 2 * SEC,
             "source": {"kind": "graphic"}, "video": {},
             "graphic": {"name": "title-card", "width": 1920, "height": 1080,
                         "props": {"title": "Chapter"}}},
            {"id": 23, "track": 4, "start": 3 * SEC, "duration": 2 * SEC,
             "source": {"kind": "text"}, "video": {}, "text": {"content": "hi"}},
            {"id": 30, "track": 5, "start": 0, "duration": 8 * SEC,
             "source": {"kind": "nest", "project": 40}, "video": {}},
            {"id": 21, "track": 3, "start": 6 * SEC, "duration": 3 * SEC,
             "source": {"kind": "graphic"}, "video": {},
             "graphic": {"name": "lower-third", "width": 1280, "height": 720,
                         "in": SEC, "length": 4 * SEC,
                         "props": {"subtitle": "Guest", "legacy": 3,
                                   "title": "Bob"}}}
        ],
        "nests": [
            {"id": 40, "name": "N", "width": 1920, "height": 1080,
             "tracks": [{"id": 41, "name": "A"}],
             "clips": [
                {"id": 42, "track": 41, "start": 0, "duration": 2 * SEC,
                 "source": {"kind": "graphic"}, "video": {},
                 "graphic": {"name": "lower-third", "width": 640, "height": 360,
                             "props": {"title": "Inside"}}},
                {"id": 43, "track": 41, "start": 3 * SEC, "duration": 2 * SEC,
                 "source": {"kind": "graphic"}, "video": {},
                 "graphic": {"name": "lower-third", "width": 320, "height": 180,
                             "in": 2 * SEC,
                             "props": {"extra": true, "title": "Other"}}}
             ]}
        ],
        "next_id": 100
    }))
}

/// A timeline clip as `get_project` would answer it.
fn clip(handle: &Handle, id: i64) -> Value {
    array(&handle.value(), "/clips")
        .iter()
        .find(|c| int(c, "/id") == id)
        .unwrap_or_else(|| panic!("no clip {id}"))
        .clone()
}

/// What Copy writes for these clips: each verbatim, its `track` a DEPTH.
fn payload_of(clips: Vec<Value>) -> Value {
    let clips: Vec<Value> = clips
        .into_iter()
        .map(|mut c| {
            c["track"] = json!(0);
            c
        })
        .collect();
    json!({"clips": clips, "media": [], "nests": []})
}

/// Clip 20 (A) on the clipboard.
fn copied_a() -> Value {
    payload_of(vec![clip(&project(), 20)])
}

/// Clip 20 on the clipboard with `props` in place of its own.
fn copied_with(props: Value) -> Value {
    let mut source = clip(&project(), 20);
    source["graphic"]["props"] = props;
    payload_of(vec![source])
}

/// The envelope: `groups` and `skip_missing` only when given.
fn paste(clips: &[i64], payload: &Value, groups: Option<&[&str]>, skip: Option<bool>) -> Value {
    let mut op = json!({"op": "paste_attributes", "clips": clips, "payload": payload});
    if let Some(groups) = groups {
        op["groups"] = json!(groups);
    }
    if let Some(skip) = skip {
        op["skip_missing"] = json!(skip);
    }
    op
}

const GRAPHIC: Option<&[&str]> = Some(&["graphic"]);

/// The clip with its `graphic.props` taken out, so two clips can be held
/// equal in everything else.
fn without_props(mut clip: Value) -> Value {
    clip["graphic"]
        .as_object_mut()
        .expect("a graphic")
        .remove("props");
    clip
}

/// Each listed clip reads the same in both projects.
fn unchanged(before: &Handle, after: &Handle, clips: &[i64]) {
    for id in clips {
        let (was, now) = (clip(before, *id), clip(after, *id));
        assert_eq!(now.to_string(), was.to_string(), "clip {id} changed");
    }
}

/// The op is an `Err` in exactly this sentence.
fn says(handle: &Handle, op: &Value, sentence: &str) {
    assert_eq!(handle.errors(op), sentence, "{op}");
}

fn is_identity(handle: &Handle, op: &Value) {
    match handle.try_apply(op) {
        Ok(Outcome::Identity) => {}
        other => panic!("expected an identity, got {other:?}\n{op}"),
    }
}

fn many(count: usize) -> Value {
    let mut props = Map::new();
    for i in 0..count {
        props.insert(format!("k{i}"), json!(i));
    }
    Value::Object(props)
}

// T1
#[test]
fn naming_graphic_copies_the_props_whole_and_the_target_keeps_the_rest() {
    let before = project();
    let after = before.apply(&paste(&[21], &copied_a(), GRAPHIC, None));
    let (was, now) = (clip(&before, 21), clip(&after, 21));

    // A's props, as a value: B's own `legacy` is gone.
    let props = json!({"title": "Ada", "accent": "#ff0000", "subtitle": "Host"});
    assert_eq!(clip(&before, 20)["graphic"]["props"], props);
    assert_eq!(now["graphic"]["props"], props);

    let kept = json!({"name": "lower-third", "width": 1280, "height": 720, "in": SEC,
                      "length": 4 * SEC});
    assert_eq!(without_props(now.clone())["graphic"], kept);
    // Everything but the props, `video` included: the group named was one.
    assert_eq!(
        without_props(now).to_string(),
        without_props(was).to_string()
    );

    unchanged(&before, &after, &[10, 20, 22, 23, 30]);
    assert_eq!(after.value()["nests"], before.value()["nests"]);
}

// T2
#[test]
fn a_shared_key_keeps_its_slot_the_targets_own_goes_and_a_new_one_lands_last() {
    let after = project().apply(&paste(&[21], &copied_a(), GRAPHIC, None));
    let text = after.to_json();
    // The timeline's clips are written before the nests, and clip 21 is
    // the last of them, so this is ITS graphic (the fixture's doc).
    let end = text.find("\"nests\"").expect("the nests key");
    let clips = text.get(..end).expect("a char boundary");
    let from = clips.rfind("\"lower-third\"").expect("clip 21's graphic");
    let tail = clips.get(from..).expect("a char boundary");
    let place = |key: &str| {
        tail.find(&format!("\"{key}\""))
            .unwrap_or_else(|| panic!("no {key} in {tail}"))
    };
    // B held subtitle, legacy, title; A holds title, accent, subtitle.
    assert!(place("subtitle") < place("title"), "{tail}");
    assert!(place("title") < place("accent"), "{tail}");
    assert!(!tail.contains("\"legacy\""), "{tail}");
    assert!(!tail.contains("Guest") && !tail.contains("Bob"), "{tail}");
}

// T3
#[test]
fn a_paste_that_names_no_graphic_group_copies_no_props() {
    let before = project();
    let graphic = clip(&before, 21)["graphic"].to_string();
    let video = clip(&before, 20)["video"].clone();
    for groups in [None, Some(&["video"][..])] {
        let after = before.apply(&paste(&[21], &copied_a(), groups, None));
        let now = clip(&after, 21);
        assert_eq!(now["video"], video, "{groups:?}");
        assert_eq!(now["video"]["opacity"], json!(0.5), "{groups:?}");
        assert_eq!(now["graphic"].to_string(), graphic, "{groups:?}");
    }
}

// T4
#[test]
fn a_named_graphic_group_a_side_cannot_serve_is_an_error_and_nothing_changes() {
    let before = project();
    let text = before.to_json();
    let media = payload_of(vec![clip(&before, 10)]);
    let (a, no_target) = (copied_a(), "clip 23 has no graphic properties");
    let no_source = "payload clip has no graphic properties";
    says(&before, &paste(&[21], &media, GRAPHIC, None), no_source);
    says(&before, &paste(&[23], &a, GRAPHIC, None), no_target);
    says(&before, &paste(&[22], &a, GRAPHIC, None), OTHER_MODULE);
    // All or nothing: the matching clip is listed FIRST and is not changed.
    says(&before, &paste(&[21, 22], &a, GRAPHIC, None), OTHER_MODULE);
    says(
        &before,
        &paste(&[21, 23], &a, GRAPHIC, Some(false)),
        no_target,
    );
    assert_eq!(before.to_json(), text);
}

// T5
#[test]
fn skip_missing_skips_what_cannot_take_a_named_group() {
    let before = project();
    let props = clip(&before, 20)["graphic"]["props"].clone();

    let mixed = before.apply(&paste(&[21, 22, 23], &copied_a(), GRAPHIC, Some(true)));
    assert_eq!(clip(&mixed, 21)["graphic"]["props"], props);
    unchanged(&before, &mixed, &[10, 20, 22, 23, 30]);

    // Nothing can take it: no target matches; the payload is no graphic.
    is_identity(&before, &paste(&[22, 23], &copied_a(), GRAPHIC, Some(true)));
    let media = payload_of(vec![clip(&before, 10)]);
    is_identity(&before, &paste(&[21], &media, GRAPHIC, Some(true)));

    // The flag is every group's: video lands on the text clip, graphic is
    // skipped there.
    let both = before.apply(&paste(
        &[23],
        &copied_a(),
        Some(&["video", "graphic"]),
        Some(true),
    ));
    let (was, mut now) = (clip(&before, 23), clip(&both, 23));
    assert_eq!(now["video"], clip(&before, 20)["video"]);
    now["video"] = was["video"].clone();
    assert_eq!(now.to_string(), was.to_string());

    // `audio` onto a text clip: an error without the flag, a skip with it.
    let audio = paste(&[23], &media, Some(&["audio"]), None);
    says(&before, &audio, "clip 23 has no audio properties");
    is_identity(&before, &paste(&[23], &media, Some(&["audio"]), Some(true)));
}

// T6
#[test]
fn a_malformed_copied_map_onto_a_matching_clip_is_the_maps_own_sentence() {
    let before = project();
    let mut long = Map::new();
    long.insert("title".to_string(), json!("x".repeat(4097)));
    let cases: [(Value, &str); 4] = [
        (
            json!({"title": "Ada", "list": [1]}),
            "props.list must be a string, a number or a boolean, not [1]",
        ),
        (
            json!({"bad-key": 1}),
            "props key \"bad-key\" is not a name (letters, digits and _, starting with a \
             letter or _, at most 32 characters)",
        ),
        (
            Value::Object(long),
            "props.title must be at most 4096 characters, not 4097",
        ),
        (many(65), "props has 65 keys; the most is 64"),
    ];
    for (props, sentence) in cases {
        for skip in [None, Some(true)] {
            let op = paste(&[21], &copied_with(props.clone()), GRAPHIC, skip);
            says(&before, &op, sentence);
        }
    }

    // A `null` is a key the map does not hold: it is not stored, and sixty-
    // four keys beside one are not sixty-five.
    let nulled = copied_with(json!({"title": "Ada", "gone": null, "legacy": null}));
    let after = before.apply(&paste(&[21], &nulled, GRAPHIC, None));
    let kept = clip(&after, 21)["graphic"]["props"].clone();
    assert_eq!(kept, json!({"title": "Ada"}));
    let mut full = many(64);
    full["gone"] = Value::Null;
    let after = before.apply(&paste(&[21], &copied_with(full), GRAPHIC, Some(true)));
    let stored = clip(&after, 21)["graphic"]["props"].clone();
    assert_eq!(stored.as_object().map(Map::len), Some(64));
    assert!(stored.get("gone").is_none());
}

// T7
#[test]
fn equal_props_are_an_identity_and_the_payload_clip_is_the_earliest() {
    let before = project();
    let same = payload_of(vec![clip(&before, 21)]);
    is_identity(&before, &paste(&[21], &same, GRAPHIC, None));
    is_identity(&before, &paste(&[21], &same, GRAPHIC, Some(true)));
    is_identity(&before, &paste(&[], &copied_a(), GRAPHIC, None));

    // The array's first clip is the text clip at 3 s; the earliest is A.
    let two = payload_of(vec![clip(&before, 23), clip(&before, 20)]);
    let after = before.apply(&paste(&[21], &two, GRAPHIC, None));
    let props = clip(&before, 20)["graphic"]["props"].clone();
    assert_eq!(clip(&after, 21)["graphic"]["props"], props);
}

// T8
#[test]
fn the_same_paste_inside_a_nest_goes_through_the_scope_envelope() {
    let before = project();
    let mut op = paste(&[43], &copied_a(), GRAPHIC, None);
    // Clip 43 is the nest's, so the timeline does not know it.
    assert_eq!(before.errors(&op), "no clip with id 43");
    op["scope"] = json!(40);
    let after = before.apply(&op);
    let (was, now) = (before.value(), after.value());
    assert_eq!(
        now["nests"][0]["clips"][1]["graphic"]["props"],
        clip(&before, 20)["graphic"]["props"]
    );
    assert_eq!(
        without_props(now["nests"][0]["clips"][1].clone()).to_string(),
        without_props(was["nests"][0]["clips"][1].clone()).to_string()
    );
    assert_eq!(now["nests"][0]["clips"][0], was["nests"][0]["clips"][0]);
    assert_eq!(now["clips"], was["clips"]);
}

// T10
#[test]
fn with_no_groups_skip_missing_changes_nothing_and_copies_no_props() {
    let before = project();
    let graphic = clip(&before, 21)["graphic"].to_string();
    let plain = before.apply(&paste(&[21, 23], &copied_a(), None, None));
    let flagged = before.apply(&paste(&[21, 23], &copied_a(), None, Some(true)));
    assert_eq!(flagged.to_json(), plain.to_json());
    assert_eq!(clip(&flagged, 21)["graphic"].to_string(), graphic);
    // The paste did happen: the video is A's on both targets.
    assert_eq!(clip(&flagged, 21)["video"]["opacity"], json!(0.5));
    assert_eq!(clip(&flagged, 23)["video"]["opacity"], json!(0.5));
}

// T11
#[test]
fn a_copied_map_no_target_takes_is_never_read() {
    let before = project();
    let malformed = copied_with(json!({"title": "Ada", "list": [1]}));
    // Skipped everywhere: an identity, with neither channel written.
    is_identity(&before, &paste(&[22, 23], &malformed, GRAPHIC, Some(true)));
    // One target takes it: the map's sentence, whichever side it is listed.
    let shape = "props.list must be a string, a number or a boolean, not [1]";
    for clips in [[21, 22], [22, 21]] {
        says(
            &before,
            &paste(&clips, &malformed, GRAPHIC, Some(true)),
            shape,
        );
    }
    // Refused for its module before the map is looked at.
    says(
        &before,
        &paste(&[22], &malformed, GRAPHIC, None),
        OTHER_MODULE,
    );
}
