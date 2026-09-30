//! Small independent enumeration of the old handle path on varied sources.

use serde_json::{json, Value};

use super::common::{by_id, int, Handle, Outcome};

const FRAME: i64 = 20_000;

fn round(n: i128, d: i128) -> i128 {
    if n >= 0 {
        (n + d / 2) / d
    } else {
        -((-n + d / 2) / d)
    }
}

fn grid(t: i64, fps: i64) -> i64 {
    round(
        round(i128::from(t) * i128::from(fps), 600_000) * 600_000,
        i128::from(fps),
    ) as i64
}

fn up(t: i64, fps: i64) -> i64 {
    let nearest = grid(t, fps);
    if nearest >= t {
        nearest
    } else {
        let index = round(i128::from(t) * i128::from(fps), 600_000);
        round((index + 1) * 600_000, i128::from(fps)) as i64
    }
}

fn down(t: i64, fps: i64) -> i64 {
    let nearest = grid(t, fps);
    if nearest <= t {
        nearest
    } else {
        let index = round(i128::from(t) * i128::from(fps), 600_000);
        round((index - 1) * 600_000, i128::from(fps)) as i64
    }
}

/// The frame `t` is nearest on the canvas grid: `round(t·fps/600000)`.
fn index(t: i64, fps: i64) -> i64 {
    round(i128::from(t) * i128::from(fps), 600_000) as i64
}

/// The tick frame `k` begins at: `round(k·600000/fps)`.
fn tick(k: i64, fps: i64) -> i64 {
    round(i128::from(k) * 600_000, i128::from(fps)) as i64
}

/// Whole grid frames in a non-negative length, counted one by one.
fn frames_in(length: i64, fps: i64) -> i64 {
    let mut k = 0;
    while tick(k + 1, fps) <= length {
        k += 1;
    }
    k
}

/// Whole grid frames lying inside `[from, to]`, counted one by one.
fn frames_inside(from: i64, to: i64, fps: i64) -> i64 {
    (index(from, fps) - 2..=index(to, fps) + 2)
        .filter(|&k| tick(k, fps) >= from && tick(k + 1, fps) <= to)
        .count() as i64
}

/// Enumerates the historical larger-side decrement, including split,
/// redistribution, neighbour bounds, and inward rational grid conversion,
/// every count in whole frames of the canvas's own grid (spec §11 #174).
/// `None` is an unbounded source handle; supplied caps are fixture facts.
fn old_path(
    project: &Value,
    asked: i64,
    align: &str,
    tail_cap: Option<i64>,
    head_cap: Option<i64>,
) -> (i64, i64) {
    let a = by_id(project, "/clips", 10);
    let b = by_id(project, "/clips", 11);
    let a_start = int(a, "/start");
    let a_duration = int(a, "/duration");
    let b_start = int(b, "/start");
    let b_duration = int(b, "/duration");
    let fps = project.pointer("/canvas/fps/0").unwrap().as_i64().unwrap();
    let mut split = frames_in(asked, fps).min(frames_in((a_duration + b_duration) / 3, fps));
    let (want_tail, want_head) = match align {
        "before" => (0, split),
        "after" => (split, 0),
        _ => (split / 2, split - split / 2),
    };
    let mut tail = tail_cap.map_or(want_tail, |cap| want_tail.min(cap));
    let mut head = head_cap.map_or(want_head, |cap| want_head.min(cap));
    if align == "center" {
        let mut missing = split - tail - head;
        let room_head = head_cap.map_or(missing, |cap| (cap - head).max(0));
        let moved = missing.min(room_head);
        head += moved;
        missing -= moved;
        let room_tail = tail_cap.map_or(missing, |cap| (cap - tail).max(0));
        tail += missing.min(room_tail);
    }
    if let Some(next) = project["clips"]
        .as_array()
        .unwrap()
        .iter()
        .find(|clip| clip["id"] == 13)
    {
        tail = tail.min(frames_inside(
            a_start + a_duration,
            int(next, "/start"),
            fps,
        ));
    }
    if let Some(previous) = project["clips"]
        .as_array()
        .unwrap()
        .iter()
        .find(|clip| clip["id"] == 12)
    {
        let previous_end = int(previous, "/start") + int(previous, "/duration");
        head = head.min(frames_inside(previous_end, b_start, fps));
    }
    split = tail + head;
    loop {
        let a_end = a_start + a_duration;
        let tail_ticks = (tick(index(down(a_end, fps), fps) + tail, fps) - a_end).max(0);
        let head_ticks = (b_start - tick(index(up(b_start, fps), fps) - head, fps)).max(0);
        if split == 0
            || (tail_ticks + 2 * head_ticks <= a_duration
                && 2 * tail_ticks + head_ticks <= b_duration)
        {
            return (tail_ticks, head_ticks);
        }
        if head >= tail {
            head -= 1;
        } else {
            tail -= 1;
        }
        split -= 1;
    }
}

fn verify(
    label: &str,
    project: Value,
    asked: i64,
    align: &str,
    tail_cap: Option<i64>,
    head_cap: Option<i64>,
) {
    let (tail, head) = old_path(&project, asked, align, tail_cap, head_cap);
    let a = by_id(&project, "/clips", 10);
    let b = by_id(&project, "/clips", 11);
    let a_duration = int(a, "/duration");
    let b_start = int(b, "/start");
    let b_duration = int(b, "/duration");
    let original_action = b["actions"]
        .as_array()
        .and_then(|actions| actions.first())
        .cloned();
    let original_style = b.get("transition_in").cloned();
    let h = Handle::from_value(&project);
    let op = json!({"op": "add_transition", "clip": 11,
                    "duration": asked, "align": align});
    match h.try_apply(&op).unwrap() {
        Outcome::Applied(next) => {
            assert!(tail + head > 0, "{label}: applied without overlap");
            let value = next.value();
            let new_a = by_id(&value, "/clips", 10);
            let new_b = by_id(&value, "/clips", 11);
            assert_eq!(int(new_a, "/duration"), a_duration + tail, "{label}: tail");
            assert_eq!(int(new_b, "/start"), b_start - head, "{label}: head");
            assert_eq!(
                int(new_b, "/duration"),
                b_duration + head,
                "{label}: B duration"
            );
            if let Some(mut action) = original_action {
                action["start"] = json!(int(&action, "/start") + head);
                assert_eq!(new_b["actions"][0], action, "{label}: action rebase");
            }
            if let Some(style) = original_style {
                assert_eq!(new_b["transition_in"], style, "{label}: stored style");
            }
        }
        Outcome::Refused(_) => assert_eq!(tail + head, 0, "{label}: unexpected refusal"),
        Outcome::Identity => panic!("{label}: unexpected identity"),
    }
}

fn base(a: i64, b: i64) -> Value {
    json!({
        "version": 8, "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "tracks": [{"id": 1}], "clips": [
            {"id": 10, "track": 1, "start": 1_200_000, "duration": a * FRAME,
             "source": {"kind": "text"}},
            {"id": 11, "track": 1, "start": 1_200_000 + a * FRAME,
             "duration": b * FRAME, "source": {"kind": "shape"},
             "actions": [{"id": 40, "start": 0, "duration": FRAME,
                          "curve": "linear", "end": {}}],
             "transition_in": {"kind": "slide", "curve": "ease_out", "audio": false}}
        ], "next_id": 50
    })
}

#[test]
fn source_handles_neighbours_and_styles_match_the_old_path() {
    let mut generated = base(11, 7);
    generated["clips"].as_array_mut().unwrap().insert(
        0,
        json!({
            "id": 12, "track": 1, "start": 0, "duration": 1_180_000,
            "source": {"kind": "text"}
        }),
    );
    generated["clips"].as_array_mut().unwrap().push(json!({
        "id": 13, "track": 1, "start": 1_200_000 + 18 * FRAME + FRAME,
        "duration": FRAME, "source": {"kind": "shape"}
    }));
    for align in ["before", "center", "after"] {
        verify(
            "generated with neighbours",
            generated.clone(),
            17 * FRAME,
            align,
            None,
            None,
        );
    }

    let mut media = base(10, 10);
    media["media"] = json!([{"id": 2, "path": "/missing.mov", "kind": "video",
                            "duration": 15 * FRAME, "width": 1920, "height": 1080,
                            "fps": [30, 1], "has_video": true, "has_audio": true}]);
    media["clips"][0]["source"] = json!({"kind": "media", "media": 2, "in": 0});
    media["clips"][1]["source"] = json!({"kind": "media", "media": 2,
                                          "in": 3 * FRAME, "reversed": true});
    for align in ["before", "center", "after"] {
        verify(
            "media and reversed limited handles",
            media.clone(),
            16 * FRAME,
            align,
            Some(5),
            Some(3),
        );
    }

    let mut nest = base(10, 10);
    nest["clips"][0]["source"] = json!({"kind": "nest", "project": 60});
    nest["clips"][1]["source"] = json!({"kind": "nest", "project": 61});
    nest["nests"] = json!([
        {"id": 60, "tracks": [{"id": 62}], "clips": [{"id": 63, "track": 62,
            "start": 0, "duration": 14 * FRAME, "source": {"kind": "text"}}]},
        {"id": 61, "tracks": [{"id": 64}], "clips": [{"id": 65, "track": 64,
            "start": 0, "duration": 10 * FRAME, "source": {"kind": "shape"}}]}
    ]);
    nest["next_id"] = json!(66);
    for align in ["before", "center", "after"] {
        verify(
            "nested limited handles",
            nest.clone(),
            12 * FRAME,
            align,
            Some(4),
            Some(0),
        );
    }
}

#[test]
fn inexact_seven_fps_grid_matches_the_enumerated_path() {
    let mut project = base(120, 120);
    project["canvas"]["fps"] = json!([7, 1]);
    project["clips"][0]["start"] = json!(1_200_000);
    project["clips"][0]["duration"] = json!(2_400_000);
    project["clips"][1]["start"] = json!(3_600_000);
    project["clips"][1]["duration"] = json!(2_400_000);
    for align in ["before", "center", "after"] {
        for asked in [37 * FRAME, 61 * FRAME, 180 * FRAME] {
            verify(
                "7 fps rational grid",
                project.clone(),
                asked,
                align,
                None,
                None,
            );
        }
    }
}

fn valid_shift(project: &Value, shift: i64) -> bool {
    let cut = 40 * FRAME;
    let clips = project["clips"].as_array().unwrap();
    for a in clips {
        for b in clips {
            if a["id"] == b["id"] || a["track"] != b["track"] {
                continue;
            }
            let track = a["track"].as_u64().unwrap();
            if track == 4 {
                continue;
            } // locked track is outside the shift set
            let a_start = int(a, "/start") - if int(a, "/start") >= cut { shift } else { 0 };
            let b_start = int(b, "/start") - if int(b, "/start") >= cut { shift } else { 0 };
            let a_len = int(a, "/duration");
            let b_len = int(b, "/duration");
            let overlap = (a_start + a_len).min(b_start + b_len) - a_start.max(b_start);
            if overlap > a_len.min(b_len) / 2 {
                return false;
            }
        }
    }
    true
}

#[test]
fn ripple_old_descending_oracle_covers_multiple_tracks_locked_straddling_and_one_tick() {
    let mut project = base(40, 40);
    project["clips"][0]["start"] = json!(0);
    project["clips"][1]["start"] = json!(40 * FRAME);
    project["tracks"] = json!([{"id": 1}, {"id": 2}, {"id": 3},
                                 {"id": 4, "locked": true}]);
    project["clips"].as_array_mut().unwrap().extend([
        json!({"id": 20, "track": 2, "start": 30 * FRAME,
               "duration": 10 * FRAME, "source": {"kind": "text"}}),
        json!({"id": 21, "track": 2, "start": 55 * FRAME,
               "duration": 10 * FRAME, "source": {"kind": "shape"}}),
        json!({"id": 22, "track": 3, "start": 30 * FRAME,
               "duration": 20 * FRAME, "source": {"kind": "text"}}),
        json!({"id": 23, "track": 3, "start": 60 * FRAME,
               "duration": 20 * FRAME, "source": {"kind": "shape"}}),
        json!({"id": 24, "track": 4, "start": 60 * FRAME,
               "duration": 10 * FRAME, "source": {"kind": "text"}}),
    ]);
    project["markers"] = json!([{"id": 25, "time": 60 * FRAME}]);
    for off_grid_tick in [0, 1] {
        let mut p = project.clone();
        p["clips"][3]["start"] = json!(55 * FRAME - off_grid_tick);
        let h = Handle::from_value(&p);
        for asked in [15, 16, 20] {
            let maximum = asked.min(20);
            let expected = (1..=maximum)
                .rev()
                .find(|frames| valid_shift(&p, frames * FRAME))
                .unwrap_or(0);
            let op = json!({"op": "add_transition", "clip": 11,
                            "duration": asked * FRAME, "ripple": true,
                            "align": "before"});
            let next = h.apply(&op).value();
            let shift = expected * FRAME;
            assert_eq!(
                int(by_id(&next, "/clips", 11), "/start"),
                40 * FRAME - shift
            );
            assert_eq!(
                int(by_id(&next, "/clips", 21), "/start"),
                55 * FRAME - off_grid_tick - shift
            );
            assert_eq!(
                int(by_id(&next, "/clips", 23), "/start"),
                60 * FRAME - shift
            );
            for id in [20, 22, 24] {
                assert_eq!(
                    int(by_id(&next, "/clips", id), "/start"),
                    int(by_id(&p, "/clips", id), "/start"),
                    "fixed clip {id}"
                );
            }
            assert_eq!(
                by_id(&next, "/clips", 11)["actions"],
                by_id(&p, "/clips", 11)["actions"]
            );
            assert_eq!(
                by_id(&next, "/clips", 11)["transition_in"],
                by_id(&p, "/clips", 11)["transition_in"]
            );
            assert_eq!(next["markers"], h.value()["markers"]);
        }
        // Exactly half of the shorter clip is legal; one tick more is not.
        let expected = if off_grid_tick == 0 { 20 } else { 19 };
        assert_eq!(
            (1..=20)
                .rev()
                .find(|frames| valid_shift(&p, frames * FRAME)),
            Some(expected)
        );
    }
}
