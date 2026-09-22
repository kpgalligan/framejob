//! Composition callers keep their own fallback and placement decisions.
mod common;
#[path = "common/commit_placement.rs"]
mod fixtures;

use fixtures::{clip, clip_mut, media_clip, nested_pair, nested_single, project, text_clip, track};
use serde_json::json;

#[test]
fn nest_then_unnest_preserves_content_and_allocates_in_order() {
    let before = project();
    let nested = before.apply(&json!({"op":"nest","clips":[10]}));
    let n = nested.value();
    assert_eq!(n["clips"].as_array().unwrap().len(), 3);
    assert_eq!(n["nests"].as_array().unwrap().len(), 1);
    assert_eq!(clip(&n, 52)["source"]["kind"], "nest");
    assert_eq!(n, nested_single(&before.value()), "whole nested document");
    let opened = nested.apply(&json!({"op":"unnest","clip":52}));
    let o = opened.value();
    assert_eq!(o["nests"].as_array().unwrap().len(), 0);
    assert_eq!(o["clips"].as_array().unwrap().len(), 3);
    assert_eq!(clip(&o, 53)["start"], 0);
    assert_eq!(clip(&o, 53)["track"], 2);
    assert_eq!(o["next_id"], 54);
    let mut expected = n;
    expected["nests"] = json!([]);
    expected["clips"].as_array_mut().unwrap().pop();
    expected["clips"].as_array_mut().unwrap().push(media_clip(
        &before.value(),
        53,
        2,
        0,
        1_000_000,
    ));
    expected["next_id"] = json!(54);
    assert_eq!(o, expected, "whole opened document");
}

#[test]
fn paste_falls_back_when_destination_is_occupied() {
    let before = project();
    let payload = json!({"clips":[{"id":7,"track":0,"start":0,"duration":1000000,
        "source":{"kind":"text"},"video":{},"text":{"content":"Pasted"}}]});
    let pasted = before.apply(&json!({"op":"paste","at":0,"track":2,"payload":payload}));
    let p = pasted.value();
    assert_eq!(p["tracks"].as_array().unwrap().len(), 4);
    assert_eq!(p["clips"][3]["track"], 51);
    assert_eq!(p["clips"][3]["id"], 50);
    assert_eq!(p["next_id"], 52);
    assert_eq!(clip(&p, 10), clip(&before.value(), 10));
    let mut expected = before.value();
    let new_track = track(&expected, 51, "Track 4");
    expected["tracks"].as_array_mut().unwrap().push(new_track);
    let pasted = text_clip(
        &expected,
        50,
        51,
        0,
        1_000_000,
        "SourceSans3-SemiBold",
        "Pasted",
    );
    expected["clips"].as_array_mut().unwrap().push(pasted);
    expected["next_id"] = json!(52);
    assert_eq!(p, expected, "whole pasted document");
}

#[test]
fn unnest_falls_back_after_its_requested_track_fails() {
    let before = project();
    let nested = before.apply(&json!({"op":"nest","clips":[10]}));
    assert_eq!(
        nested.value(),
        nested_single(&before.value()),
        "whole nested document before fallback"
    );
    let mut displaced = nested.value();
    displaced["clips"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .find(|c| c["id"] == 52)
        .unwrap()["start"] = json!(2_000_000);
    let displaced = common::Handle::from_value(&displaced);
    let opened = displaced.apply(&json!({"op":"unnest","clip":52}));
    let o = opened.value();
    assert_eq!(clip(&o, 53)["start"], 2_000_000);
    assert_eq!(clip(&o, 53)["track"], 54);
    assert_eq!(o["tracks"][3]["id"], 54);
    assert_eq!(o["next_id"], 55);
    assert_eq!(clip(&o, 11), clip(&displaced.value(), 11));
    let mut expected = displaced.value();
    expected["nests"] = json!([]);
    expected["clips"].as_array_mut().unwrap().pop();
    let new_track = track(&expected, 54, "Track 4");
    expected["tracks"].as_array_mut().unwrap().push(new_track);
    expected["clips"].as_array_mut().unwrap().push(media_clip(
        &before.value(),
        53,
        54,
        2_000_000,
        1_000_000,
    ));
    expected["next_id"] = json!(55);
    assert_eq!(o, expected, "whole fallback unnest document");
}

#[test]
fn composed_insert_overwrite_and_shift_transition_keep_their_answers() {
    let before = project();
    let inserted = before.apply(&json!({"op":"insert_clip","track":4,"media":1,"at":1_000_000}));
    assert_eq!(inserted.value()["clips"][3]["id"], 50);
    assert_eq!(inserted.value()["next_id"], 51);
    let mut expected_insert = before.value();
    clip_mut(&mut expected_insert, 11)["start"] = json!(8_000_000);
    let added = media_clip(&expected_insert, 50, 4, 1_000_000, 6_000_000);
    expected_insert["clips"].as_array_mut().unwrap().push(added);
    expected_insert["next_id"] = json!(51);
    assert_eq!(inserted.value(), expected_insert, "whole inserted document");

    let overwritten =
        before.apply(&json!({"op":"overwrite_clip","track":4,"media":1,"at":1_000_000}));
    assert_eq!(overwritten.value()["clips"][3]["id"], 50);
    assert_eq!(overwritten.value()["next_id"], 51);
    let mut expected_overwrite = before.value();
    let added = media_clip(&expected_overwrite, 50, 4, 1_000_000, 6_000_000);
    expected_overwrite["clips"]
        .as_array_mut()
        .unwrap()
        .push(added);
    expected_overwrite["next_id"] = json!(51);
    assert_eq!(
        overwritten.value(),
        expected_overwrite,
        "whole overwritten document"
    );

    let mut contiguous = before.value();
    contiguous["clips"][1]["start"] = json!(1_000_000);
    let contiguous = common::Handle::from_value(&contiguous);
    let shifted = contiguous.apply(
        &json!({"op":"add_transition","clip":11,"duration":200_000,"ripple":true,"kind":"wipe"}),
    );
    let s = shifted.value();
    assert_eq!(clip(&s, 11)["start"], 800_000);
    assert_eq!(clip(&s, 11)["transition_in"]["kind"], "wipe");
    assert_eq!(s["next_id"], 50);
    let mut expected_shift = contiguous.value();
    let clip = clip_mut(&mut expected_shift, 11);
    clip["start"] = json!(800_000);
    clip["transition_in"] = json!({"kind":"wipe","curve":"ease_in_out","audio":true});
    assert_eq!(s, expected_shift, "whole ripple-transition document");
}

#[test]
fn scoped_applied_placement_and_parent_cap_error_are_distinct() {
    let nested = project().apply(&json!({"op":"nest","clips":[10]}));
    let n = nested.value();
    assert_eq!(
        n,
        nested_single(&project().value()),
        "whole nested document before scoped edit"
    );
    let inside_track = n["nests"][0]["tracks"][0]["id"].as_u64().unwrap();
    let nest_id = n["nests"][0]["id"].as_u64().unwrap();
    let placed = nested.apply(&json!({"op":"add_text_clip","track":inside_track,"at":2_000_000,"duration":100_000,"scope":nest_id}));
    let p = placed.value();
    assert_eq!(p["nests"][0]["clips"][1]["id"], 53);
    assert_eq!(p["nests"][0]["clips"][1]["start"], 2_000_000);
    assert_eq!(p["next_id"], 54);
    let mut expected = n.clone();
    let added = text_clip(
        &project().value(),
        53,
        inside_track,
        2_000_000,
        100_000,
        "SourceSans3-Bold",
        "Title",
    );
    expected["nests"][0]["clips"]
        .as_array_mut()
        .unwrap()
        .push(added);
    expected["next_id"] = json!(54);
    assert_eq!(p, expected, "whole scoped placement document");

    let mut packed = n;
    let template = clip(&packed, 12).clone();
    for id in 100..4192u64 {
        let mut extra = template.clone();
        extra["id"] = json!(id);
        extra["start"] = json!(id * 1_000_000);
        packed["clips"].as_array_mut().unwrap().push(extra);
    }
    packed["next_id"] = json!(5000);
    let full = common::Handle::from_value(&packed);
    assert_eq!(full.value()["clips"].as_array().unwrap().len(), 4095);
    // The timeline's 4095 clips plus one in the nest fill the 4096 cap.
    assert_eq!(
        full.errors(&json!({"op":"add_text_clip","track":inside_track,"at":2_000_000,"duration":100_000,"scope":nest_id})),
        "too many clips: 4097 (max 4096)"
    );
}

#[test]
fn ripple_and_gap_compositions_touch_expected_tracks_only() {
    let before = project();
    let cut = before.apply(&json!({"op":"ripple_delete","clips":[10]}));
    assert_eq!(clip(&cut.value(), 11)["start"], 1000000);
    let mut expected_cut = before.value();
    expected_cut["clips"].as_array_mut().unwrap().remove(0);
    clip_mut(&mut expected_cut, 11)["start"] = json!(1_000_000);
    assert_eq!(cut.value(), expected_cut, "whole ripple-delete document");
    let range = before.apply(&json!({"op":"ripple_delete_ranges","ranges":[[1000000,2000000]]}));
    assert_eq!(clip(&range.value(), 11)["start"], 1000000);
    let mut expected_range = before.value();
    clip_mut(&mut expected_range, 11)["start"] = json!(1_000_000);
    assert_eq!(range.value(), expected_range, "whole range-delete document");
    let gap = before.apply(&json!({"op":"close_gap","track":2,"at":1500000}));
    assert_eq!(clip(&gap.value(), 11)["start"], 1000000);
    assert_eq!(clip(&gap.value(), 12), clip(&before.value(), 12));
    let mut expected_gap = before.value();
    clip_mut(&mut expected_gap, 11)["start"] = json!(1_000_000);
    assert_eq!(gap.value(), expected_gap, "whole close-gap document");
}

#[test]
fn scoped_refusal_keeps_parent_and_error_uses_error_channel() {
    let before = project();
    let nested = before.apply(&json!({"op":"nest","clips":[10,11]}));
    assert_eq!(
        nested.value(),
        nested_pair(&before.value()),
        "whole two-clip nested document"
    );
    let nest = nested.value()["nests"][0]["id"].as_u64().unwrap();
    let inside = nested.value()["nests"][0]["clips"]
        .as_array()
        .unwrap()
        .clone();
    let later = inside.iter().find(|c| c["id"] == 11).unwrap();
    assert_eq!(later["start"], 2000000);
    let refused = json!({"op":"move_clip","clips":[11],"delta":-1500001,"scope":nest});
    assert!(matches!(
        nested.try_apply(&refused),
        Ok(common::Outcome::Refused(_))
    ));
    assert_eq!(nested.value()["nests"][0]["clips"], json!(inside));
    assert_eq!(
        nested.errors(&json!({"op":"move_clip","clips":[99],"delta":0,"scope":nest})),
        "no clip with id 99"
    );
}

#[test]
fn roll_and_freeze_keep_their_own_no_mint_behavior() {
    let before = project();
    let mut contiguous = before.value();
    contiguous["clips"][1]["start"] = json!(1000000);
    let contiguous = common::Handle::from_value(&contiguous);
    let rolled = contiguous.apply(&json!({"op":"roll","clip":11,"to":1100000}));
    assert_eq!(
        clip(&rolled.value(), 11)["transition_in"],
        serde_json::Value::Null
    );
    let mut expected_roll = contiguous.value();
    clip_mut(&mut expected_roll, 10)["duration"] = json!(1_100_000);
    let later = clip_mut(&mut expected_roll, 11);
    later["start"] = json!(1_100_000);
    later["duration"] = json!(900_000);
    later["source"]["in"] = json!(100_000);
    assert_eq!(rolled.value(), expected_roll, "whole roll document");
    let frozen = before.apply(&json!({"op":"freeze_frame","clip":10,"at":500000}));
    assert_eq!(
        clip(&frozen.value(), 10)["transition_in"],
        serde_json::Value::Null
    );
    let mut expected_freeze = before.value();
    clip_mut(&mut expected_freeze, 10)["duration"] = json!(500_000);
    clip_mut(&mut expected_freeze, 11)["start"] = json!(3_200_000);
    let mut tail = media_clip(&before.value(), 50, 2, 1_700_000, 500_000);
    tail["source"]["in"] = json!(500_000);
    expected_freeze["clips"].as_array_mut().unwrap().push(tail);
    let mut still = media_clip(&before.value(), 51, 2, 500_000, 1_200_000);
    still["source"] = json!({"kind":"still","media":1,"at":500_000});
    still["audio"] = serde_json::Value::Null;
    still["enabled"]["audio"] = json!(false);
    expected_freeze["clips"].as_array_mut().unwrap().push(still);
    expected_freeze["next_id"] = json!(52);
    assert_eq!(frozen.value(), expected_freeze, "whole freeze document");
}
