mod common;
#[path = "common/frame_grid.rs"]
mod fixture;

use common::{Handle, Outcome};
use fixture::{action, media, nest, nest_clip, project, text_clip, track};
use serde_json::{json, Value};

fn one(clips: &Value, id: u64) -> &Value {
    clips
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == id)
        .unwrap()
}

fn added<'a>(before: &Value, after: &'a Value) -> &'a Value {
    after["clips"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| {
            !before["clips"]
                .as_array()
                .unwrap()
                .iter()
                .any(|b| b["id"] == c["id"])
        })
        .unwrap()
}

#[test]
fn paste_normalizes_full_clip_but_preserves_source_audio_and_existing_clips() {
    let existing = text_clip(2, 1, 0, 200_000);
    let base = Handle::from_value(&project([24, 1], vec![existing], vec![], 50));
    let before = base.value();
    let mut incoming = text_clip(7, 0, 20_000, 60_000);
    incoming["source"] = json!({"kind":"text"});
    let payload = json!({"clips":[incoming],"media":[]});
    let after = base.apply(&json!({"op":"paste","at":20_000,"payload":payload}));
    let value = after.value();
    let c = added(&before, &value);
    assert_ne!(c["id"], 7);
    assert_eq!(c["start"], 25_000);
    assert_eq!(c["duration"], 50_000);
    assert_eq!(c["actions"][0]["start"], 0);
    assert_eq!(c["actions"][0]["duration"], 25_000);
    assert_ne!(c["actions"][0]["id"], 8);
    assert_eq!(c["video"]["motion"]["out"]["duration"], 25_000);
    assert_eq!(c["text"]["animation"]["in"], 25_000);
    assert_eq!(c["audio"]["fade_in"], 10_001);
    assert_eq!(
        c["actions"][0]["end"]["video"]["motion"]["in"]["duration"],
        12_500
    );
    assert_ne!(c["track"], 1, "busy destination gets a fallback track");
    assert_eq!(one(&value["clips"], 2), &before["clips"][0]);
    assert_eq!(base.value(), before);
}

#[test]
fn nested_paste_remaps_media_before_bounding_and_scoped_paste_uses_parent_grid() {
    let base = Handle::from_value(&project([24, 1], vec![], vec![], 50));
    let inner = json!({"id":41,"track":42,"start":20_000,"duration":100_000,
        "speed":2.0,"source":{"kind":"media","media":7,"in":20_000},
        "video":{"motion":{"in":{"kind":"fade","duration":12_500}}},
        "audio":{"fade_in":10_001}});
    let payload = json!({"clips":[{"id":40,"track":0,"start":0,
        "duration":60_000,"source":{"kind":"nest","project":43},"video":{}}],
        "media":[media(7,120_000)],
        "nests":[{"id":43,"width":640,"height":360,
            "tracks":[track(42)],"clips":[inner]}]});
    let pasted = base.apply(&json!({"op":"paste","at":0,"payload":payload}));
    let v = pasted.value();
    assert_eq!(v["media"].as_array().unwrap().len(), 1);
    let nested = &v["nests"][0]["clips"][0];
    assert_eq!(nested["start"], 25_000);
    // Ordinary snapping leaves 100_000. Only the remapped source's
    // remaining 100_000 ticks at speed 2 can bound this to 50_000.
    assert_eq!(nested["duration"], 50_000);
    assert_eq!(nested["video"]["motion"]["in"]["duration"], 25_000);
    assert_eq!(nested["audio"]["fade_in"], 10_001);
    assert_eq!(nested["source"]["in"], 20_000);
    assert_ne!(nested["source"]["media"], 7);
    assert_ne!(nested["id"], 41);
    assert_eq!(v["clips"][0]["duration"], 50_000);

    let scoped_input = project(
        [24, 1],
        vec![nest_clip(2, 0, 200_000, 10)],
        vec![nest(10, 11, vec![text_clip(12, 11, 0, 100_000)])],
        50,
    );
    let scoped = Handle::from_value(&scoped_input);
    let source = text_clip(70, 0, 20_000, 60_000);
    let after = scoped.apply(&json!({"op":"paste","at":200_000,
        "payload":{"clips":[source]},"scope":10}));
    let v = after.value();
    assert_eq!(v["clips"], scoped.value()["clips"]);
    let c = v["nests"][0]["clips"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] != 12)
        .unwrap();
    assert_eq!(c["start"], 200_000);
    assert_eq!(c["duration"], 50_000);
    assert_eq!(c["video"]["motion"]["out"]["duration"], 25_000);
    assert_eq!(c["text"]["animation"]["out"], 50_000);
}

#[test]
fn unnest_normalizes_translated_contents_and_preserves_shared_nest_with_fallback() {
    let mut child = text_clip(12, 11, 40_000, 60_000);
    child["actions"] = json!([action(13, 60_000, 20_000)]);
    let blocker = json!({"id":4,"track":1,"start":260_000,"duration":100_000,
        "source":{"kind":"shape"},"video":{},"shape":{}});
    let base = Handle::from_value(&project(
        [24, 1],
        vec![
            nest_clip(2, 200_000, 60_000, 10),
            nest_clip(3, 600_000, 60_000, 10),
            blocker,
        ],
        vec![nest(10, 11, vec![child])],
        50,
    ));
    let before = base.value();
    let after = base.apply(&json!({"op":"unnest","clip":2}));
    let v = after.value();
    let c = added(&before, &v);
    assert_eq!(c["start"], 250_000);
    assert_eq!(c["duration"], 50_000);
    assert_eq!(c["actions"][0]["start"], 25_000);
    assert_eq!(c["actions"][0]["duration"], 25_000);
    assert_eq!(c["video"]["motion"]["out"]["duration"], 25_000);
    assert_eq!(c["text"]["animation"]["in"], 25_000);
    assert_ne!(c["id"], 12);
    assert_ne!(c["actions"][0]["id"], 13);
    assert_ne!(c["track"], 1, "overlap fallback survives normalization");
    assert_eq!(
        v["nests"][0], before["nests"][0],
        "the other reference retains the nest"
    );
    assert_eq!(one(&v["clips"], 3), one(&before["clips"], 3));
}

#[test]
fn paste_attributes_checks_original_then_snaps_copied_video_text_only() {
    let mut target = text_clip(2, 1, 100_000, 200_000);
    target["video"] = json!({"opacity":0.8});
    target["text"] = json!({"content":"Target"});
    target["audio"] = json!({"fade_in":12345,"fade_out":23456});
    let base = Handle::from_value(&project([24, 1], vec![target], vec![], 50));
    let before = base.value();
    let source = text_clip(7, 0, 0, 60_000);
    let payload = json!({"clips":[source]});
    let op = json!({"op":"paste_attributes","clips":[2],"payload":payload});
    let after = base.apply(&op);
    let c = &after.value()["clips"][0];
    assert_eq!(c["video"]["motion"]["out"]["duration"], 25_000);
    assert_eq!(c["text"]["animation"]["in"], 25_000);
    assert_eq!(c["text"]["animation"]["out"], 50_000);
    assert_eq!(c["text"]["content"], "Target");
    assert_eq!(c["audio"]["fade_in"], 10_001);
    assert_eq!(c["start"], 100_000);
    assert_eq!(c["actions"], before["clips"][0]["actions"]);
    assert!(matches!(after.try_apply(&op), Ok(Outcome::Identity)));
    let mut negative = op.clone();
    negative["payload"]["clips"][0]["video"]["motion"]["in"]["duration"] = json!(-1);
    let error = base.errors(&negative);
    assert!(
        error.contains("video.motion.in.duration") && error.contains("-1"),
        "{error}"
    );
    assert_eq!(base.value(), before);
    negative = op.clone();
    negative["payload"]["clips"][0]["text"]["animation"]["in"] = json!(-1);
    let error = base.errors(&negative);
    assert!(
        error.contains("text.animation.in") && error.contains("-1"),
        "{error}"
    );
    assert_eq!(base.value(), before);
}

#[test]
fn scoped_attributes_and_unnest_obey_the_same_parent_grid() {
    let mut target = text_clip(12, 11, 0, 100_000);
    target["video"] = json!({});
    target["text"] = json!({"content":"Nested target"});
    let base = Handle::from_value(&project(
        [24, 1],
        vec![nest_clip(2, 0, 200_000, 10)],
        vec![nest(10, 11, vec![target])],
        50,
    ));
    let after = base.apply(&json!({"op":"paste_attributes","clips":[12],
        "payload":{"clips":[text_clip(7,0,0,60_000)]},"scope":10}));
    let c = &after.value()["nests"][0]["clips"][0];
    assert_eq!(c["video"]["motion"]["in"]["duration"], 0);
    assert_eq!(c["text"]["animation"]["in"], 25_000);
    assert_eq!(c["text"]["content"], "Nested target");

    let mut inner = nest_clip(13, 20_000, 60_000, 20);
    inner["track"] = json!(11);
    let nested = Handle::from_value(&project(
        [24, 1],
        vec![nest_clip(2, 0, 200_000, 10)],
        vec![
            nest(10, 11, vec![inner]),
            nest(20, 21, vec![text_clip(22, 21, 20_000, 60_000)]),
        ],
        50,
    ));
    let opened = nested.apply(&json!({"op":"unnest","clip":13,"scope":10}));
    let c = &opened.value()["nests"][0]["clips"][0];
    assert_eq!(c["start"], 50_000);
    assert_eq!(c["duration"], 50_000);
    assert_eq!(c["video"]["motion"]["out"]["duration"], 25_000);
}

#[test]
fn full_paste_and_unnest_keep_the_loaded_empty_motion_spelling() {
    let mut incoming = text_clip(7, 0, 20_000, 60_000);
    incoming["video"]["motion"] = json!({});
    let pasted = Handle::new(640, 360, 24, 1).apply(&json!({"op":"paste","at":0,
        "payload":{"clips":[incoming]}}));
    assert_eq!(
        pasted.value()["clips"][0]["video"]["motion"],
        json!({"in":null,"out":null,"during":null})
    );
    let mut child = text_clip(12, 11, 20_000, 60_000);
    child["video"]["motion"] = json!({});
    let base = Handle::from_value(&project(
        [24, 1],
        vec![nest_clip(2, 0, 100_000, 10)],
        vec![nest(10, 11, vec![child])],
        50,
    ));
    let after = base.apply(&json!({"op":"unnest","clip":2}));
    assert_eq!(
        after.value()["clips"][0]["video"]["motion"],
        json!({"in":null,"out":null,"during":null})
    );
}
