//! Spike VR-S3's still arm (road map "creator-jobs" VR6a, spec §11 VR-62):
//! `tools/proof/creator_spike/speaker_spike.py` writes `input.json` — the
//! moving still's face samples with their `mouth`, in clip ticks, the
//! synthetic turns and the two microphones — and runs this, ignored, with
//! `FRAMEJOB_SPEAKER_SPIKE` naming its folder. It answers `metrics.json`:
//! the faces, every agreement (`[mic][face]`), the assignment and `sure`,
//! through `speaker_match`, the planner's own match. The rule is the
//! script's.

use std::fs;
use std::path::Path;

use framejob_core::reframe_speaker::speaker_match;
use framejob_core::reframe_subjects::{SubjectSample, Turn};
use serde_json::{json, Value};

#[test]
#[ignore]
fn vr_s3_still_arm() {
    let dir =
        std::env::var("FRAMEJOB_SPEAKER_SPIKE").expect("FRAMEJOB_SPEAKER_SPIKE names the folder");
    let dir = Path::new(&dir);
    let input: Value =
        serde_json::from_slice(&fs::read(dir.join("input.json")).expect("input.json")).unwrap();
    let samples: Vec<SubjectSample> = serde_json::from_value(input["samples"].clone()).unwrap();
    let turns: Vec<Turn> = serde_json::from_value(input["turns"].clone()).unwrap();
    let mics: Vec<u32> = serde_json::from_value(input["mics"].clone()).unwrap();
    let out = match speaker_match(&samples, &turns, &mics) {
        None => json!({"matched": false, "samples": samples.len()}),
        Some(m) => json!({
            "matched": true,
            "samples": samples.len(),
            "faces": m.faces.iter().map(|f| json!({"face": f.face, "x": f.x,
                                                    "samples": f.samples})).collect::<Vec<_>>(),
            "agreement": m.agreement,
            "assignment": m.assignment,
            "sure": m.sure,
        }),
    };
    println!("{out}");
    fs::write(
        dir.join("metrics.json"),
        serde_json::to_vec_pretty(&out).unwrap(),
    )
    .unwrap();
}
