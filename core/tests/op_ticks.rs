//! Complete FFI audit of arguments declared as Ticks or Ranges in OP_TABLE.
#[path = "common/op_ticks_actions.rs"]
mod actions;
#[path = "common/op_ticks_clips.rs"]
mod clips;
mod common;
#[path = "common/op_ticks_timeline.rs"]
mod timeline;
#[path = "common/op_ticks.rs"]
mod vectors;

use common::{Handle, Outcome};
use framejob_core::op_table::{Kind, OP_TABLE};
use serde_json::{json, Value};
use std::collections::BTreeSet;
use vectors::{TickAnswer, TickCase};

fn execute(case: TickCase) {
    let op_name = case.op["op"].as_str().expect("named op");
    assert!(
        case.op.get(case.argument).is_some(),
        "{}: missing vector argument",
        case.label
    );
    let input = Handle::from_value(&case.project);
    let original = input.to_json();
    match (case.answer, input.try_apply(&case.op)) {
        (TickAnswer::Applied(expected), Ok(Outcome::Applied(next))) => {
            let value = next.value();
            for (pointer, wanted) in expected {
                assert_eq!(
                    value.pointer(pointer),
                    Some(&wanted),
                    "{} {}.{}, {pointer}",
                    case.label,
                    op_name,
                    case.argument
                );
            }
        }
        (TickAnswer::Identity, Ok(Outcome::Identity)) => {}
        (TickAnswer::Error(expected), Err(message)) => {
            assert_eq!(message, expected, "{}", case.label)
        }
        (_, answer) => panic!(
            "{} {}.{}: unexpected {answer:?}",
            case.label, op_name, case.argument
        ),
    }
    assert_eq!(
        input.to_json(),
        original,
        "{}: input handle mutated",
        case.label
    );
}

#[test]
fn every_published_tick_pair_executes_on_both_frame_grids() {
    let declared: BTreeSet<(&str, &str)> = OP_TABLE
        .iter()
        .flat_map(|row| {
            row.arguments
                .iter()
                .filter(|a| matches!(a.kind, Kind::Ticks | Kind::Ranges))
                .map(|a| (row.name, a.name))
        })
        .collect();
    assert_eq!(declared.len(), 41, "declared tick arguments changed");
    assert_eq!(
        declared
            .iter()
            .map(|(op, _)| *op)
            .collect::<BTreeSet<_>>()
            .len(),
        30
    );
    for (fps, frame) in [([30, 1], 20_000), ([30_000, 1_001], 20_020)] {
        let cases = clips::cases(fps, frame)
            .into_iter()
            .chain(timeline::cases(fps, frame))
            .chain(actions::cases(fps, frame))
            .collect::<Vec<_>>();
        let covered: BTreeSet<(&str, &str)> = cases
            .iter()
            .map(|case| (case.op["op"].as_str().unwrap(), case.argument))
            .collect();
        assert_eq!(covered, declared, "{fps:?}: missing or extra tick vector");
        assert_eq!(
            cases.len(),
            46,
            "{fps:?}: expected 41 primary plus 5 branch vectors"
        );
        for case in cases {
            execute(case);
        }
    }
}

#[test]
fn exact_half_frames_signed_motion_and_zero_clamp() {
    for (fps, frame) in [([30, 1], 20_000), ([30_000, 1_001], 20_020)] {
        let p = vectors::one(fps, frame);
        let controls: Vec<(&str, Value, TickAnswer)> = vec![
            (
                "below half",
                json!({"op":"move_clip","clips":[10],"delta":frame*2/5}),
                TickAnswer::Identity,
            ),
            (
                "above half",
                json!({"op":"move_clip","clips":[10],"delta":frame*3/5}),
                TickAnswer::Applied(vec![("/clips/0/start", json!(11 * frame))]),
            ),
            (
                "exact positive tie",
                json!({"op":"move_clip","clips":[10],"delta":frame/2}),
                TickAnswer::Applied(vec![("/clips/0/start", json!(11 * frame))]),
            ),
            (
                "negative",
                json!({"op":"move_clip","clips":[10],"delta":-frame*3/5}),
                TickAnswer::Applied(vec![("/clips/0/start", json!(9 * frame))]),
            ),
            (
                "exact negative tie",
                json!({"op":"move_clip","clips":[10],"delta":-frame/2}),
                TickAnswer::Applied(vec![("/clips/0/start", json!(9 * frame))]),
            ),
            (
                "clamped zero",
                json!({"op":"move_clip","clips":[10],"delta":-30*frame}),
                TickAnswer::Applied(vec![("/clips/0/start", json!(0))]),
            ),
        ];
        for (label, op, answer) in controls {
            execute(TickCase {
                label,
                argument: "delta",
                project: p.clone(),
                op,
                answer,
            });
        }
        let empty = vectors::project(fps, frame, vec![]);
        execute(TickCase {
            label: "negative marker clamp",
            argument: "at",
            project: empty.clone(),
            op: json!({"op":"add_marker","at":-frame*3/5}),
            answer: TickAnswer::Applied(vec![("/markers/0/time", json!(0))]),
        });
        execute(TickCase {
            label: "zero action duration",
            argument: "duration",
            project: p.clone(),
            op: json!({"op":"add_action","clip":10,"at":0,"duration":0}),
            answer: TickAnswer::Error("action duration must be positive, not 0"),
        });
        execute(TickCase {
            label: "small negative action start snaps to zero",
            argument: "at",
            project: p.clone(),
            op: json!({"op":"add_action","clip":10,
                "at":-frame*2/5,"duration":5*frame}),
            answer: TickAnswer::Applied(vec![("/clips/0/actions/0/start", json!(0))]),
        });
        execute(TickCase {
            label: "negative transition duration",
            argument: "duration",
            project: vectors::pair(fps, frame),
            op: json!({"op":"add_transition","clip":11,"duration":-frame}),
            answer: TickAnswer::Error(if frame == 20_000 {
                "duration must be positive, not -20000"
            } else {
                "duration must be positive, not -20020"
            }),
        });
        execute(TickCase {
            label: "negative insert length",
            argument: "length",
            project: p,
            op: json!({"op":"insert_time","at":0,"length":-2*frame}),
            answer: TickAnswer::Error(if frame == 20_000 {
                "insert length must not be negative, not -40000"
            } else {
                "insert length must not be negative, not -40040"
            }),
        });
    }
}

#[test]
fn scoped_time_uses_parent_grid_and_preserves_the_outer_clip() {
    for (fps, frame) in [([30, 1], 20_000), ([30_000, 1_001], 20_020)] {
        let mut p = vectors::project(
            fps,
            frame,
            vec![json!({
                "id":30,"track":1,"start":0,"duration":20*frame,
                "source":{"kind":"nest","project":20},"video":{}
            })],
        );
        p["nests"] = json!([{"id":20,"name":"Inside","width":640,"height":360,
            "tracks":[{"id":21,"name":"Inner"}],
            "clips":[vectors::clip(22,21,2*frame,10*frame,40*frame)]}]);
        execute(TickCase {
            label: "scoped move on parent grid",
            argument: "delta",
            project: p,
            op: json!({"op":"move_clip","clips":[22],"delta":vectors::off(1,frame),"scope":20}),
            answer: TickAnswer::Applied(vec![
                ("/nests/0/clips/0/start", json!(4 * frame)),
                ("/clips/0/start", json!(0)),
            ]),
        });
    }
}

#[test]
fn transition_floor_handle_mode() {
    for (fps, frame) in [([30, 1], 20_000), ([30_000, 1_001], 20_020)] {
        execute(
            actions::cases(fps, frame)
                .into_iter()
                .find(|c| c.label == "add_transition.duration handles floor")
                .unwrap(),
        );
    }
}

#[test]
fn transition_floor_ripple_mode() {
    for (fps, frame) in [([30, 1], 20_000), ([30_000, 1_001], 20_020)] {
        execute(
            actions::cases(fps, frame)
                .into_iter()
                .find(|c| c.label == "add_transition.duration ripple floor")
                .unwrap(),
        );
    }
}

#[test]
fn marker_off_grid_rounds_before_storage() {
    for (fps, frame) in [([30, 1], 20_000), ([30_000, 1_001], 20_020)] {
        execute(
            timeline::cases(fps, frame)
                .into_iter()
                .find(|c| c.label == "add_marker.at")
                .unwrap(),
        );
    }
}
