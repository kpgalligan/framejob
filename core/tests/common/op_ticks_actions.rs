//! Action and transition tick vectors; floor overlap differs from nearest.
use super::vectors::{applied, off, one, pair, TickCase};
use serde_json::json;

pub fn cases(fps: [u32; 2], f: i64) -> Vec<TickCase> {
    let one = one(fps, f);
    let pair = pair(fps, f);
    let mut with_action = one.clone();
    with_action["clips"][0]["actions"] = json!([{"id":20,"start":2*f,
        "duration":5*f,"end":{"video":{"opacity":0.5}}}]);
    vec![
        applied(
            "set_transition_duration.duration",
            "duration",
            pair.clone(),
            json!({"op":"set_transition_duration","clip":11,"duration":off(4,f)}),
            vec![
                ("/clips/1/start", json!(25 * f)),
                ("/clips/0/duration", json!(20 * f)),
            ],
        ),
        applied(
            "add_transition.duration handles floor",
            "duration",
            pair.clone(),
            json!({"op":"add_transition","clip":11,"duration":off(5,f)}),
            vec![
                ("/clips/0/duration", json!(22 * f)),
                ("/clips/1/start", json!(27 * f)),
                ("/clips/1/duration", json!(23 * f)),
            ],
        ),
        applied(
            "add_transition.duration ripple floor",
            "duration",
            pair.clone(),
            json!({"op":"add_transition","clip":11,"duration":off(5,f),"ripple":true}),
            vec![
                ("/clips/0/duration", json!(20 * f)),
                ("/clips/1/start", json!(25 * f)),
                ("/clips/1/duration", json!(20 * f)),
            ],
        ),
        applied(
            "add_action.at",
            "at",
            one.clone(),
            json!({"op":"add_action","clip":10,"at":off(3,f),"duration":5*f}),
            vec![("/clips/0/actions/0/start", json!(4 * f))],
        ),
        applied(
            "add_action.duration",
            "duration",
            one.clone(),
            json!({"op":"add_action","clip":10,"at":2*f,"duration":off(4,f)}),
            vec![("/clips/0/actions/0/duration", json!(5 * f))],
        ),
        applied(
            "add_zoom_action.at region",
            "at",
            one.clone(),
            json!({"op":"add_zoom_action","clip":10,"at":off(3,f),"duration":5*f,
                   "region":{"x":0,"y":0,"width":200,"height":100}}),
            vec![
                ("/clips/0/actions/0/start", json!(4 * f)),
                ("/clips/0/actions/0/duration", json!(5 * f)),
            ],
        ),
        applied(
            "add_zoom_action.duration back",
            "duration",
            one.clone(),
            json!({"op":"add_zoom_action","clip":10,"at":2*f,"duration":off(4,f)}),
            vec![
                ("/clips/0/actions/0/start", json!(2 * f)),
                ("/clips/0/actions/0/duration", json!(5 * f)),
                ("/clips/0/actions/0/end/video/scale", json!(1.0)),
            ],
        ),
        applied(
            "set_action.start",
            "start",
            with_action.clone(),
            json!({"op":"set_action","clip":10,"action":20,"start":off(8,f)}),
            vec![
                ("/clips/0/actions/0/start", json!(9 * f)),
                ("/clips/0/actions/0/duration", json!(5 * f)),
            ],
        ),
        applied(
            "set_action.duration",
            "duration",
            with_action,
            json!({"op":"set_action","clip":10,"action":20,"duration":off(8,f)}),
            vec![
                ("/clips/0/actions/0/start", json!(2 * f)),
                ("/clips/0/actions/0/duration", json!(9 * f)),
            ],
        ),
    ]
}
