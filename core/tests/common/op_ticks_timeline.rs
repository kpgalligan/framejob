//! Range, gap, insertion and marker tick vectors.
use super::vectors::{applied, clip, off, project, TickCase};
use serde_json::json;

pub fn cases(fps: [u32; 2], f: i64) -> Vec<TickCase> {
    let two = project(
        fps,
        f,
        vec![
            clip(10, 1, 20 * f, 10 * f, 40 * f),
            clip(11, 1, 40 * f, 10 * f, 80 * f),
        ],
    );
    let one = project(fps, f, vec![clip(10, 1, 20 * f, 10 * f, 40 * f)]);
    let mut marked = two.clone();
    marked["markers"] = json!([{"id":12,"time":30*f,"name":"One"}]);
    vec![
        applied(
            "ripple_delete_range.from",
            "from",
            two.clone(),
            json!({"op":"ripple_delete_range","from":off(9,f),"to":15*f}),
            vec![
                ("/clips/0/start", json!(15 * f)),
                ("/clips/1/start", json!(35 * f)),
            ],
        ),
        applied(
            "ripple_delete_range.to",
            "to",
            two.clone(),
            json!({"op":"ripple_delete_range","from":10*f,"to":off(14,f)}),
            vec![
                ("/clips/0/start", json!(15 * f)),
                ("/clips/1/start", json!(35 * f)),
            ],
        ),
        applied(
            "ripple_delete_ranges.ranges",
            "ranges",
            two.clone(),
            json!({"op":"ripple_delete_ranges","ranges":[[off(4,f),10*f],[15*f,off(19,f)]]}),
            vec![
                ("/clips/0/start", json!(10 * f)),
                ("/clips/1/start", json!(30 * f)),
            ],
        ),
        applied(
            "ripple_delete_ranges.ranges second bounds",
            "ranges",
            two.clone(),
            json!({"op":"ripple_delete_ranges","ranges":[[5*f,off(9,f)],[off(14,f),20*f]]}),
            vec![
                ("/clips/0/start", json!(10 * f)),
                ("/clips/1/start", json!(30 * f)),
            ],
        ),
        applied(
            "lift_range.from",
            "from",
            one.clone(),
            json!({"op":"lift_range","from":off(21,f),"to":25*f}),
            vec![
                ("/clips/0/duration", json!(2 * f)),
                ("/clips/1/start", json!(25 * f)),
            ],
        ),
        applied(
            "lift_range.to",
            "to",
            one.clone(),
            json!({"op":"lift_range","from":22*f,"to":off(24,f)}),
            vec![
                ("/clips/0/duration", json!(2 * f)),
                ("/clips/1/start", json!(25 * f)),
            ],
        ),
        applied(
            "insert_time.at beside edge",
            "at",
            two.clone(),
            json!({"op":"insert_time","at":20*f+f*2/5,"length":4*f}),
            vec![
                ("/clips/0/start", json!(24 * f)),
                ("/clips/1/start", json!(44 * f)),
            ],
        ),
        applied(
            "insert_time.length",
            "length",
            two.clone(),
            json!({"op":"insert_time","at":20*f,"length":off(3,f)}),
            vec![
                ("/clips/0/start", json!(24 * f)),
                ("/clips/1/start", json!(44 * f)),
            ],
        ),
        applied(
            "close_gap.at beside edge",
            "at",
            two.clone(),
            json!({"op":"close_gap","track":1,"at":30*f-f*2/5}),
            vec![("/clips/1/start", json!(30 * f))],
        ),
        applied(
            "add_marker.at",
            "at",
            two.clone(),
            json!({"op":"add_marker","at":off(12,f)}),
            vec![("/markers/0/time", json!(13 * f))],
        ),
        applied(
            "set_marker.time",
            "time",
            marked,
            json!({"op":"set_marker","marker":12,"time":off(32,f)}),
            vec![("/markers/0/time", json!(33 * f))],
        ),
    ]
}
