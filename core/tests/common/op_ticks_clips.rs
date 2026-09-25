//! Creation, placement, edge, split, paste and freeze tick vectors.
use super::vectors::{applied, clip, off, one, pair, project, TickCase};
use serde_json::json;

pub fn cases(fps: [u32; 2], f: i64) -> Vec<TickCase> {
    let empty = project(fps, f, vec![]);
    let one = one(fps, f);
    let pair = pair(fps, f);
    let mut out = vec![
        applied(
            "add_clip.at",
            "at",
            empty.clone(),
            json!({"op":"add_clip","track":1,"media":4,"at":off(3,f)}),
            vec![
                ("/clips/0/start", json!(4 * f)),
                ("/clips/0/duration", json!(8 * f)),
            ],
        ),
        applied(
            "add_text_clip.at",
            "at",
            empty.clone(),
            json!({"op":"add_text_clip","track":1,"at":off(3,f),"duration":4*f}),
            vec![("/clips/0/start", json!(4 * f))],
        ),
        applied(
            "add_text_clip.duration",
            "duration",
            empty.clone(),
            json!({"op":"add_text_clip","track":1,"at":0,"duration":off(4,f)}),
            vec![("/clips/0/duration", json!(5 * f))],
        ),
        applied(
            "add_shape_clip.at",
            "at",
            empty.clone(),
            json!({"op":"add_shape_clip","track":1,"at":off(3,f),"duration":4*f}),
            vec![("/clips/0/start", json!(4 * f))],
        ),
        applied(
            "add_shape_clip.duration",
            "duration",
            empty.clone(),
            json!({"op":"add_shape_clip","track":1,"at":0,"duration":off(4,f)}),
            vec![("/clips/0/duration", json!(5 * f))],
        ),
        applied(
            "add_graphic_clip.at",
            "at",
            empty.clone(),
            json!({"op":"add_graphic_clip","track":1,"at":off(3,f),"duration":4*f,"name":"g"}),
            vec![("/clips/0/start", json!(4 * f))],
        ),
        applied(
            "add_graphic_clip.duration",
            "duration",
            empty.clone(),
            json!({"op":"add_graphic_clip","track":1,"at":0,"duration":off(4,f),"name":"g"}),
            vec![("/clips/0/duration", json!(5 * f))],
        ),
        applied(
            "add_background.duration",
            "duration",
            empty.clone(),
            json!({"op":"add_background","duration":off(7,f)}),
            vec![("/clips/0/duration", json!(8 * f))],
        ),
        applied(
            "insert_clip.at",
            "at",
            one.clone(),
            json!({"op":"insert_clip","track":3,"media":4,"at":off(4,f)}),
            vec![
                ("/clips/1/start", json!(5 * f)),
                ("/clips/1/duration", json!(8 * f)),
                ("/clips/0/start", json!(18 * f)),
            ],
        ),
        applied(
            "overwrite_clip.at",
            "at",
            one.clone(),
            json!({"op":"overwrite_clip","track":3,"media":4,"at":off(4,f)}),
            vec![
                ("/clips/1/start", json!(5 * f)),
                ("/clips/0/start", json!(10 * f)),
            ],
        ),
        applied(
            "move_clip.delta",
            "delta",
            one.clone(),
            json!({"op":"move_clip","clips":[10],"delta":off(3,f)}),
            vec![("/clips/0/start", json!(14 * f))],
        ),
        applied(
            "trim_start.to",
            "to",
            one.clone(),
            json!({"op":"trim_start","clip":10,"to":off(12,f)}),
            vec![
                ("/clips/0/start", json!(13 * f)),
                ("/clips/0/duration", json!(17 * f)),
                ("/clips/0/source/in", json!(43 * f)),
            ],
        ),
        applied(
            "trim_end.to",
            "to",
            one.clone(),
            json!({"op":"trim_end","clip":10,"to":off(25,f)}),
            vec![
                ("/clips/0/duration", json!(16 * f)),
                ("/clips/0/source/in", json!(40 * f)),
            ],
        ),
        applied(
            "rate_stretch.to_end",
            "to_end",
            one.clone(),
            json!({"op":"rate_stretch","clip":10,"to_end":off(25,f)}),
            vec![
                ("/clips/0/duration", json!(16 * f)),
                ("/clips/0/speed", json!(1.25)),
            ],
        ),
        applied(
            "slip.delta",
            "delta",
            one.clone(),
            json!({"op":"slip","clip":10,"delta":off(2,f)}),
            vec![
                ("/clips/0/source/in", json!(43 * f)),
                ("/clips/0/start", json!(10 * f)),
            ],
        ),
        applied(
            "roll.to",
            "to",
            pair.clone(),
            json!({"op":"roll","clip":11,"to":off(31,f)}),
            vec![
                ("/clips/0/duration", json!(22 * f)),
                ("/clips/1/start", json!(32 * f)),
                ("/clips/1/duration", json!(18 * f)),
                ("/clips/1/source/in", json!(82 * f)),
            ],
        ),
        applied(
            "split.at selected",
            "at",
            one.clone(),
            json!({"op":"split","clips":[10],"at":off(14,f)}),
            vec![
                ("/clips/0/duration", json!(5 * f)),
                ("/clips/1/start", json!(15 * f)),
                ("/clips/1/source/in", json!(45 * f)),
            ],
        ),
        applied(
            "split.at under playhead",
            "at",
            one.clone(),
            json!({"op":"split","at":off(14,f)}),
            vec![
                ("/clips/0/duration", json!(5 * f)),
                ("/clips/1/start", json!(15 * f)),
            ],
        ),
        applied(
            "freeze_frame.at",
            "at",
            one.clone(),
            json!({"op":"freeze_frame","clip":10,"at":off(14,f),"duration":4*f}),
            vec![
                ("/clips/0/duration", json!(5 * f)),
                ("/clips/2/source/at", json!(45 * f)),
            ],
        ),
        applied(
            "freeze_frame.duration",
            "duration",
            one.clone(),
            json!({"op":"freeze_frame","clip":10,"at":15*f,"duration":off(3,f)}),
            vec![("/clips/2/duration", json!(4 * f))],
        ),
        applied(
            "paste.at",
            "at",
            empty.clone(),
            json!({"op":"paste","at":off(7,f),"payload":{"clips":[
                {"id":50,"track":0,"start":0,"duration":3*f,
                 "source":{"kind":"text"},"video":{},"text":{"content":"Paste"}}]}}),
            vec![
                ("/clips/0/start", json!(8 * f)),
                ("/clips/0/duration", json!(3 * f)),
            ],
        ),
    ];
    let mut fast = clip(10, 1, 10 * f, 20 * f, 40 * f);
    fast["speed"] = json!(2.0);
    out.push(applied(
        "slip.delta at speed 2",
        "delta",
        project(fps, f, vec![fast]),
        json!({"op":"slip","clip":10,"delta":off(2,f)}),
        vec![("/clips/0/source/in", json!(46 * f))],
    ));
    let still = json!({"id":10,"track":1,"start":10*f,"duration":20*f,
        "source":{"kind":"still","media":2,"at":40*f},"video":{}});
    out.push(applied(
        "slip.delta still",
        "delta",
        project(fps, f, vec![still]),
        json!({"op":"slip","clip":10,"delta":off(2,f)}),
        vec![("/clips/0/source/at", json!(43 * f))],
    ));
    out
}
