//! FFI differential checks and hard watchdogs for transition fitting.

use serde_json::{json, Value};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

mod common;
use common::{by_id, int, Handle, Outcome};
#[path = "common/transition_oracle.rs"]
mod transition_oracle;

const FRAME: i64 = 20_000;
const M: i64 = 9_000_000_000_000_000;

fn pair(a_frames: i64, b_frames: i64, other: Vec<Value>) -> Handle {
    let a = a_frames * FRAME;
    let b = b_frames * FRAME;
    let mut clips = vec![
        json!({"id": 10, "track": 1, "start": 0, "duration": a,
               "source": {"kind": "text"}, "text": {"content": "A"}}),
        json!({"id": 11, "track": 1, "start": a, "duration": b,
               "source": {"kind": "text"}, "text": {"content": "B"}}),
    ];
    clips.extend(other);
    Handle::from_value(&json!({
        "version": 8, "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "tracks": [{"id": 1}, {"id": 2}], "clips": clips, "next_id": 5000
    }))
}

fn old_handle(a: i64, b: i64, asked: i64, align: &str) -> (i64, i64) {
    let mut total = asked.min((a + b) / 3);
    let (mut tail, mut head) = match align {
        "before" => (0, total),
        "after" => (total, 0),
        _ => (total / 2, total - total / 2),
    };
    loop {
        if total == 0 || (tail + 2 * head <= a && 2 * tail + head <= b) {
            return (tail, head);
        }
        if head >= tail {
            head -= 1;
        } else {
            tail -= 1;
        }
        total -= 1;
    }
}

#[test]
fn handle_search_matches_independent_small_step_oracle() {
    for a in 2..=14 {
        for b in 2..=14 {
            let h = pair(a, b, vec![]);
            for asked in 1..=18 {
                for align in ["center", "before", "after"] {
                    let (tail, head) = old_handle(a, b, asked, align);
                    let op = json!({"op": "add_transition", "clip": 11,
                                    "duration": asked * FRAME, "align": align});
                    match h.try_apply(&op).unwrap() {
                        Outcome::Applied(next) => {
                            let value = next.value();
                            assert_eq!(
                                int(by_id(&value, "/clips", 10), "/duration"),
                                (a + tail) * FRAME
                            );
                            assert_eq!(
                                int(by_id(&value, "/clips", 11), "/start"),
                                (a - head) * FRAME
                            );
                        }
                        Outcome::Refused(_) => assert_eq!(tail + head, 0),
                        Outcome::Identity => panic!("unexpected identity: {op}"),
                    }
                }
            }
        }
    }
}

#[test]
fn ripple_can_be_valid_after_crossing_a_forbidden_interval() {
    let fixed = json!({"id": 20, "track": 2, "start": 5 * 600_000,
                       "duration": 600_000, "source": {"kind": "shape"}});
    let moved = json!({"id": 21, "track": 2, "start": 8 * 600_000,
                       "duration": 600_000, "source": {"kind": "shape"}});
    let h = pair(240, 240, vec![fixed, moved]);
    // 3 seconds is inside the forbidden interval; the greatest passing
    // count below it is 2.5 seconds, where overlap equals half-shorter.
    let near = h
        .apply(&json!({"op": "add_transition", "clip": 11,
                               "duration": 3 * 600_000, "ripple": true}))
        .value();
    assert_eq!(
        int(by_id(&near, "/clips", 21), "/start"),
        8 * 600_000 - (2 * 600_000 + 300_000)
    );
    // At 4 seconds the moved clip has crossed to the other side and the
    // result is valid again. A whole-predicate binary search misses this.
    let far = h
        .apply(&json!({"op": "add_transition", "clip": 11,
                              "duration": 4 * 600_000, "ripple": true}))
        .value();
    assert_eq!(int(by_id(&far, "/clips", 21), "/start"), 4 * 600_000);
}

fn overlap(a_start: i64, a_length: i64, b_start: i64, b_length: i64) -> i64 {
    (a_start + a_length).min(b_start + b_length) - a_start.max(b_start)
}

#[test]
fn ripple_search_matches_independent_descending_small_oracle() {
    // Each possible shift is checked independently by interval arithmetic,
    // with no call to the production interval solver or overlap checker.
    for fixed_start in 0..10_i64 {
        for fixed_length in 1..=10_i64 {
            for offset in 0..=4_i64 {
                for moved_length in 1..=10_i64 {
                    let moved_start = 10 + offset;
                    let allowance = fixed_length.min(moved_length) / 2;
                    let initial =
                        overlap(fixed_start, fixed_length, moved_start, moved_length).max(0);
                    if initial > allowance {
                        continue;
                    }
                    let fixed = json!({"id": 20, "track": 2,
                                       "start": fixed_start * FRAME,
                                       "duration": fixed_length * FRAME,
                                       "source": {"kind": "text"}});
                    let moved = json!({"id": 21, "track": 2,
                                       "start": moved_start * FRAME,
                                       "duration": moved_length * FRAME,
                                       "source": {"kind": "shape"}});
                    let h = pair(10, 10, vec![fixed, moved]);
                    for asked in 1..=5_i64 {
                        let expected = (1..=asked)
                            .rev()
                            .find(|shift| {
                                let overlap = overlap(
                                    fixed_start,
                                    fixed_length,
                                    moved_start - shift,
                                    moved_length,
                                )
                                .max(0);
                                overlap <= allowance
                            })
                            .unwrap_or(0);
                        let op = json!({"op": "add_transition", "clip": 11,
                                        "duration": asked * FRAME, "ripple": true});
                        match h.try_apply(&op).unwrap() {
                            Outcome::Applied(next) => {
                                assert!(expected > 0, "{op}");
                                assert_eq!(
                                    int(by_id(&next.value(), "/clips", 21), "/start"),
                                    (moved_start - expected) * FRAME,
                                    "{op}"
                                );
                            }
                            Outcome::Refused(_) => assert_eq!(expected, 0, "{op}"),
                            Outcome::Identity => panic!("unexpected identity: {op}"),
                        }
                    }
                }
            }
        }
    }
}

#[test]
fn only_invalid_affected_tracks_preflight_and_name_the_existing_rule() {
    let invalid = |track: i64, start: i64, id: i64| {
        json!({
            "id": id, "track": track, "start": start,
            "duration": 10 * FRAME, "source": {"kind": "text"}
        })
    };
    let project = json!({
        "version": 8, "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "tracks": [{"id": 1}, {"id": 2}],
        "clips": [
            invalid(1, 0, 10), invalid(1, 4 * FRAME, 11),
            invalid(1, 20 * FRAME, 12), invalid(1, 30 * FRAME, 13),
            invalid(2, 0, 20), invalid(2, 4 * FRAME, 21),
        ], "next_id": 30
    });
    let h = Handle::from_value(&project);
    let op = |ripple| {
        json!({"op": "add_transition", "clip": 13,
                             "duration": 2 * FRAME, "ripple": ripple})
    };
    for ripple in [false, true] {
        match h.try_apply(&op(ripple)).unwrap() {
            Outcome::Refused(why) => {
                assert!(
                    why.contains("clips 10 and 11 would overlap by 120000 ticks"),
                    "{why}"
                );
            }
            other => panic!("invalid affected track was not refused: {other:?}"),
        }
    }
    // The same invalid pair on an untouched track does not block either
    // form of the valid hard cut on track 1.
    let mut unrelated = project;
    unrelated["clips"] = json!([
        invalid(1, 0, 10),
        invalid(1, 10 * FRAME, 13),
        invalid(2, 0, 20),
        invalid(2, 4 * FRAME, 21)
    ]);
    let u = Handle::from_value(&unrelated);
    for ripple in [false, true] {
        assert!(matches!(
            u.try_apply(&op(ripple)).unwrap(),
            Outcome::Applied(_)
        ));
    }
}

#[test]
fn handle_action_rebase_obeys_final_admission_and_ripple_keeps_it() {
    let mut project = pair(10, 10, vec![]).value();
    project["clips"][1]["actions"] = json!([{
        "id": 30, "start": M - 2 * FRAME, "duration": 2 * FRAME, "end": {}
    }]);
    let h = Handle::from_value(&project);
    let before = h.to_json();
    let handle = json!({"op": "add_transition", "clip": 11,
                        "duration": 2 * FRAME, "align": "before"});
    let error = h.try_apply(&handle).unwrap_err();
    assert_eq!(
        error,
        format!(
            "clip 11.action 30.end must be between -{M} and {M} ticks, not {}",
            M + 2 * FRAME
        )
    );
    assert_eq!(h.to_json(), before);
    let shifted = h.apply(&json!({"op": "add_transition", "clip": 11,
                                  "duration": 2 * FRAME, "ripple": true}));
    assert_eq!(
        shifted.value()["clips"][1]["actions"],
        h.value()["clips"][1]["actions"]
    );
}

fn watchdog(name: &str, seconds: u64) {
    let mut child = Command::new(std::env::current_exe().unwrap())
        .arg("--exact")
        .arg(name)
        .arg("--nocapture")
        .env("REELCUT_EXTREME_CHILD", "1")
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            assert!(status.success(), "{name} child failed: {status}");
            eprintln!("{name}: {:.3}s", start.elapsed().as_secs_f64());
            return;
        }
        if start.elapsed() > Duration::from_secs(seconds) {
            child.kill().unwrap();
            let _ = child.wait();
            panic!("{name} exceeded {seconds}s watchdog");
        }
        thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn huge_transition_paths_finish_under_watchdog() {
    watchdog("child_huge_paths", 5);
}

#[test]
fn child_huge_paths() {
    if std::env::var_os("REELCUT_EXTREME_CHILD").is_none() {
        return;
    }
    let half: i64 = 4_500_000_000_000_000;
    let h = Handle::from_value(&json!({
        "version": 8, "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "tracks": [{"id": 1}, {"id": 2}],
        "clips": [
            {"id": 10, "track": 1, "start": 0, "duration": half,
             "source": {"kind": "text"}},
            {"id": 11, "track": 1, "start": half, "duration": half,
             "source": {"kind": "shape"}},
            {"id": 20, "track": 2, "start": half - 3_000_000_000_000_000_i64,
             "duration": 2_000_000_000_000_000_i64, "source": {"kind": "text"}},
            {"id": 21, "track": 2, "start": half + 2_000_000,
             "duration": 1_000_000_000_000_000_i64, "source": {"kind": "shape"}}
        ], "next_id": 22
    }));
    for ripple in [false, true] {
        let next = h.apply(&json!({"op": "add_transition", "clip": 11,
                                   "duration": M, "ripple": ripple,
                                   "align": "before"}));
        Handle::from_json(&next.to_json());
    }
}

#[test]
fn cap_sized_pair_search_finishes_under_watchdog() {
    watchdog("child_cap_stress", 30);
}

#[test]
fn child_cap_stress() {
    if std::env::var_os("REELCUT_EXTREME_CHILD").is_none() {
        return;
    }
    let cut = 4_500_000_000_000_000;
    let mut clips = vec![
        json!({"id": 10, "track": 1, "start": 0, "duration": cut,
               "source": {"kind": "text"}}),
        json!({"id": 11, "track": 1, "start": cut, "duration": cut,
               "source": {"kind": "shape"}}),
    ];
    for i in 0..2047_i64 {
        clips.push(json!({"id": 100 + i, "track": 2,
                          "start": i * FRAME, "duration": FRAME,
                          "source": {"kind": "text"}}));
        clips.push(json!({"id": 2200 + i, "track": 2,
                          "start": cut + i * FRAME, "duration": FRAME,
                          "source": {"kind": "shape"}}));
    }
    let h = Handle::from_value(&json!({
        "version": 8, "canvas": {"width": 1920, "height": 1080, "fps": [30, 1]},
        "tracks": [{"id": 1}, {"id": 2}], "clips": clips, "next_id": 5000
    }));
    let result = h
        .try_apply(&json!({"op": "add_transition", "clip": 11,
                                    "duration": M, "ripple": true}))
        .unwrap();
    assert!(!matches!(result, Outcome::Identity));
}
