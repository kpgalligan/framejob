//! Opaque tick payloads: picture times snap; source and audio times do not.
mod common;
#[path = "common/op_ticks.rs"]
mod fixture;

use common::Handle;
use serde_json::{json, Value};

fn text_project() -> Handle {
    let mut project = fixture::project(
        [30, 1],
        20_000,
        vec![json!({
            "id":10,"track":1,"start":0,"duration":600_000,
            "source":{"kind":"text"},"video":{},"text":{"content":"Title"},
            "audio":{}
        })],
    );
    project["next_id"] = json!(100);
    Handle::from_value(&project)
}

fn at<'a>(value: &'a Value, pointer: &str) -> &'a Value {
    value
        .pointer(pointer)
        .unwrap_or_else(|| panic!("missing {pointer}: {value}"))
}

#[test]
fn creation_and_property_patches_snap_picture_payload_times() {
    let base = text_project();
    let created = base.apply(&json!({"op":"add_text_clip","track":3,"at":800_000,
        "duration":400_000,"text":{"animation":{"kind":"typewriter",
            "in":31_000,"out":51_000}}}));
    let value = created.value();
    assert_eq!(at(&value, "/clips/1/text/animation/in"), &json!(40_000));
    assert_eq!(at(&value, "/clips/1/text/animation/out"), &json!(60_000));

    let motion = base.apply(&json!({"op":"set_video","clips":[10],
        "patch":{"motion":{"in":{"kind":"fade","duration":31_000},
                            "during":{"kind":"pulse","period":51_000,"amount":0.5}}}}));
    let v = motion.value();
    assert_eq!(at(&v, "/clips/0/video/motion/in/duration"), &json!(40_000));
    assert_eq!(
        at(&v, "/clips/0/video/motion/during/period"),
        &json!(60_000)
    );

    let animation = base.apply(&json!({"op":"set_text","clips":[10],
        "patch":{"animation":{"kind":"typewriter","in":31_000,"out":51_000}}}));
    let v = animation.value();
    assert_eq!(at(&v, "/clips/0/text/animation/in"), &json!(40_000));
    assert_eq!(at(&v, "/clips/0/text/animation/out"), &json!(60_000));
}

#[test]
fn audio_envelope_and_measured_media_duration_keep_source_precision() {
    let base = text_project();
    let audio = base.apply(&json!({"op":"set_audio","clips":[10],
        "patch":{"fade_in":10_001,"fade_out":12_501}}));
    let v = audio.value();
    assert_eq!(at(&v, "/clips/0/audio/fade_in"), &json!(10_001));
    assert_eq!(at(&v, "/clips/0/audio/fade_out"), &json!(12_501));
    let media = base.apply(&json!({"op":"add_media","descriptor":{
        "path":"/fixtures/measured.mov","kind":"video","duration":123_457,
        "width":640,"height":360,"fps":[30,1],"has_video":true}}));
    assert_eq!(at(&media.value(), "/media/2/duration"), &json!(123_457));
}

#[test]
fn action_end_keeps_permitted_timing_payload_but_rejects_motion() {
    let base = text_project();
    let with_action = base.apply(&json!({"op":"add_action","clip":10,"at":0,"duration":200_000}));
    let action = at(&with_action.value(), "/clips/0/actions/0/id")
        .as_u64()
        .unwrap();
    let audio = with_action.apply(&json!({"op":"set_action_end","clip":10,"action":action,
        "patch":{"audio":{"fade_in":10_001},
            "text":{"animation":{"kind":"typewriter","in":31_000,"out":51_000}}}}));
    assert_eq!(
        at(&audio.value(), "/clips/0/actions/0/end/audio/fade_in"),
        &json!(10_001)
    );
    assert_eq!(
        at(&audio.value(), "/clips/0/actions/0/end/text/animation/in"),
        &json!(31_000)
    );
    assert_eq!(
        with_action
            .try_apply(&json!({"op":"set_action_end","clip":10,"action":action,
        "patch":{"video":{"motion":{"in":{"kind":"fade","duration":31_000}}}}}))
            .unwrap_err(),
        "video.motion is not an animation target"
    );
}
