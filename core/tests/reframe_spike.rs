//! Spike VR-S2's grid run (road map "creator-jobs" VR2a1, spec §11 VR-23):
//! `tools/proof/creator_spike/reframe_spike.py` writes the canned inputs and
//! runs this, ignored, with `FRAMEJOB_REFRAME_SPIKE` naming its folder. For
//! each of the 27 settings and each input it plans the framing and writes
//! `metrics.json`: the samples counted (a face chosen), those contained (the
//! chosen face's centre inside the window's central 60 % in both axes at the
//! path's value there), the moves and the input's minutes. The rule is the
//! script's.
//!
//! The canned clips are forward ×1 from `in` 0, so a sample's media tick is
//! its clip tick and the choice is read straight from `choose_subject`.

use std::fs;
use std::path::Path;

use framejob_core::model::Project;
use framejob_core::reframe::{plan_framing, FramingRequest, FramingTuning, Subjects};
use framejob_core::reframe_tracks::{
    choose_subject, Follow, SubjectBox, SubjectKind, SubjectSample,
};
use serde_json::{json, Map, Value};

const DEAD_ZONES: [f64; 3] = [0.06, 0.10, 0.15];
const SPEEDS: [f64; 3] = [0.3, 0.5, 0.8];
const HEADROOMS: [f64; 3] = [0.33, 0.38, 0.42];

fn boxes(value: &Value) -> Vec<SubjectBox> {
    value
        .as_array()
        .unwrap()
        .iter()
        .map(|b| SubjectBox {
            x: b["x"].as_f64().unwrap(),
            y: b["y"].as_f64().unwrap(),
            w: b["w"].as_f64().unwrap(),
            h: b["h"].as_f64().unwrap(),
            c: b["c"].as_f64().unwrap(),
        })
        .collect()
}

struct Input {
    name: String,
    minutes: f64,
    project: Project,
    clip: u32,
    from: (u32, u32),
    zoom: f64,
    subjects: Subjects,
}

fn read(path: &Path) -> Input {
    let doc: Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
    let samples = doc["samples"]
        .as_array()
        .unwrap()
        .iter()
        .map(|s| SubjectSample {
            t: s["t"].as_i64().unwrap(),
            faces: boxes(&s["faces"]),
            people: boxes(&s["people"]),
            salient: boxes(&s["salient"]),
        })
        .collect();
    let shots = doc["shots"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t.as_i64().unwrap())
        .collect();
    Input {
        name: doc["name"].as_str().unwrap().to_string(),
        minutes: doc["seconds"].as_f64().unwrap() / 60.0,
        project: serde_json::from_value(doc["project"].clone()).unwrap(),
        clip: doc["clip"].as_u64().unwrap() as u32,
        from: (
            doc["from"][0].as_u64().unwrap() as u32,
            doc["from"][1].as_u64().unwrap() as u32,
        ),
        zoom: doc["zoom"].as_f64().unwrap(),
        subjects: Subjects { samples, shots },
    }
}

fn measure(input: &Input, tuning: &FramingTuning) -> Value {
    let request = FramingRequest {
        follow: Follow::Subject,
        zoom: input.zoom,
        from_width: input.from.0,
        from_height: input.from.1,
    };
    let path = plan_framing(
        &input.project,
        input.clip,
        &input.subjects,
        &request,
        tuning,
    )
    .expect("a canned input plans");
    let media = &input.project.media[0];
    let (mw, mh) = (f64::from(media.width), f64::from(media.height));
    let (ws, hs) = (f64::from(input.from.0) / 2.0, f64::from(input.from.1) / 2.0);
    let (w, h) = (
        f64::from(input.project.canvas.width),
        f64::from(input.project.canvas.height),
    );
    let chosen = choose_subject(
        &input.subjects.samples,
        &input.subjects.shots,
        Follow::Subject,
    );
    let (mut counted, mut contained) = (0u64, 0u64);
    for c in &chosen {
        let (Some(SubjectKind::Face), Some(b)) = (c.kind, c.subject) else {
            continue;
        };
        counted += 1;
        let (k, x, y) = path.at(c.t);
        let (cx, cy) = (ws - x / k, hs - y / k);
        let (fx, fy) = ((b.x + b.w / 2.0) * mw, (b.y + b.h / 2.0) * mh);
        if (fx - cx).abs() <= 0.3 * w / k && (fy - cy).abs() <= 0.3 * h / k {
            contained += 1;
        }
    }
    json!({"counted": counted, "contained": contained, "moves": path.moves(),
           "minutes": input.minutes})
}

#[test]
#[ignore]
fn vr_s2_grid() {
    let dir =
        std::env::var("FRAMEJOB_REFRAME_SPIKE").expect("FRAMEJOB_REFRAME_SPIKE names the folder");
    let dir = Path::new(&dir);
    let mut paths: Vec<_> = fs::read_dir(dir.join("canned"))
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .collect();
    paths.sort();
    let inputs: Vec<Input> = paths.iter().map(|p| read(p)).collect();
    let mut settings = Vec::new();
    for dz in DEAD_ZONES {
        for speed in SPEEDS {
            for headroom in HEADROOMS {
                let tuning = FramingTuning {
                    dead_zone_width: dz,
                    dead_zone_height: 0.8 * dz,
                    speed,
                    headroom,
                };
                let mut per = Map::new();
                for input in &inputs {
                    per.insert(input.name.clone(), measure(input, &tuning));
                }
                println!(
                    "dead zone {dz} speed {speed} headroom {headroom}: {}",
                    Value::Object(per.clone())
                );
                settings.push(
                    json!({"dead_zone": dz, "speed": speed, "headroom": headroom,
                                     "inputs": per}),
                );
            }
        }
    }
    let out = json!({"settings": settings});
    fs::write(
        dir.join("metrics.json"),
        serde_json::to_vec_pretty(&out).unwrap(),
    )
    .unwrap();
}
