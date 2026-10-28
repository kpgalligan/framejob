//! Black-box tests for the WebM writer's edges — spec §11 CX-15 (codec-export
//! C3) and CX-16 (C4's V_VP9), through `rc_webm_*`: a video-only layout (the silent movie) writes each
//! packet as it arrives and refuses the audio track as unknown; every layout and
//! packet refusal by its sentence, with no file made for a refused layout; and two
//! threads adding at once, as the app's video and audio queues do. The round trips
//! are `webm_writer.rs`; the helpers both use are `common/webm.rs`.

mod common;

use std::path::Path;

use serde_json::{json, Value};

use common::ebml_read::{blocks, segment};
use common::webm::*;
use framejob_core::container::{Container, AUDIO, VIDEO};

#[test]
fn a_video_only_layout_writes_each_packet_as_it_arrives() {
    let path = temp_path("video-only");
    let layout = json!({"duration_ns": SECOND, "video": video_layout([30, 1], false)});
    let w = Webm::open(&path, &layout).expect("open");
    for k in 0..30usize {
        w.add(V, frame_ns(k, 30, 1), k == 0, 0, &frame(k))
            .expect("add");
        let on_disk = std::fs::read(&path).expect("read");
        let packet = frame(k);
        assert!(
            on_disk
                .windows(packet.len())
                .any(|w| w == packet.as_slice()),
            "frame {k} is not on disk before the next add"
        );
    }
    assert_eq!(
        w.add(A, 0, true, 0, &opus(0)),
        Err("track 2 is not in the layout".into())
    );
    w.finish().expect("finish");
    let b = std::fs::read(&path).expect("read");
    let (_, seg) = segment(&b);
    assert_eq!(find(&seg, 0x1654_AE6B).all(0xAE).len(), 1);
    let c = Container::open(&path).expect("open");
    assert!(c.describe()["audio"].is_null());
    assert_eq!(c.sample_count(VIDEO), 30);
}

#[test]
fn every_layout_refusal_is_its_sentence() {
    let video = video_layout([30, 1], false);
    let mut cases: Vec<(Value, String)> = Vec::new();
    let with = |key: &str, value: Value| {
        let mut l = full_layout();
        l["video"][key] = value;
        l
    };
    cases.push((
        json!({"duration_ns": SECOND}),
        "the layout has no video and no audio track".into(),
    ));
    cases.push((
        with("codec_id", json!("V_HEVC")),
        "video codec_id \"V_HEVC\" is not V_AV1 or V_VP9".into(),
    ));
    cases.push((
        with("codec_id", json!("V_VP9")),
        "a V_VP9 track takes no codec_private_hex".into(),
    ));
    let mut l = full_layout();
    l["video"]
        .as_object_mut()
        .unwrap()
        .remove("codec_private_hex");
    cases.push((l, "the V_AV1 codec_private_hex is empty".into()));
    let mut l = full_layout();
    l["video"]["colour"]["bits_per_channel"] = json!(12);
    cases.push((l, "colour bits_per_channel 12 is not 8 or 10".into()));
    cases.push((
        with("codec_private_hex", json!("")),
        "the V_AV1 codec_private_hex is empty".into(),
    ));
    cases.push((
        with("codec_private_hex", json!("8z")),
        "codec_private_hex \"8z\" is not hex".into(),
    ));
    cases.push((
        with("width", json!(0)),
        "the video size 0 × 360 has a side of 0".into(),
    ));
    cases.push((
        with("fps", json!([30, 0])),
        "the video fps [30, 0] is not a rate".into(),
    ));
    let mut l = full_layout();
    l["video"]["colour"]["mdcv_hex"] = json!("0011");
    cases.push((l, "mdcv_hex is 2 bytes, not 24".into()));
    let mut l = full_layout();
    l["video"]["colour"]["clli_hex"] = json!("03e8");
    cases.push((l, "clli_hex is 2 bytes, not 4".into()));
    let mut l = full_layout();
    l["video"]["colour"]["clli_hex"] = json!("03e8z0");
    cases.push((l, "clli_hex \"03e8z0\" is not hex".into()));
    let mut l = full_layout();
    l["audio"]["codec_id"] = json!("A_VORBIS");
    cases.push((l, "audio codec_id \"A_VORBIS\" is not A_OPUS".into()));
    let mut l = full_layout();
    l["audio"]["sample_rate"] = json!(44100);
    cases.push((l, "audio sample_rate 44100 is not 48000".into()));
    let mut l = full_layout();
    l["audio"]["channels"] = json!(3);
    cases.push((l, "audio channels 3 is not 1 or 2".into()));
    let mut l = json!({"duration_ns": SECOND, "video": video.clone()});
    l["chapters"] = json!([{"start_ns": 5, "end_ns": 5, "name": "A"}]);
    cases.push((
        l,
        "chapter 1 \"A\" ends at 5 ns, not after its start at 5 ns".into(),
    ));
    let mut l = json!({"duration_ns": SECOND, "video": video});
    l["chapters"] = json!([{"start_ns": 0, "end_ns": 9, "name": "A"},
                           {"start_ns": SECOND, "end_ns": 2 * SECOND, "name": "B"}]);
    cases.push((
        l,
        format!("chapter 2 \"B\" starts at {SECOND} ns, not before the duration {SECOND} ns"),
    ));
    for (layout, sentence) in cases {
        let path = temp_path("refused");
        assert_eq!(
            Webm::open(&path, &layout).err(),
            Some(sentence.clone()),
            "{layout}"
        );
        assert!(!path.exists(), "a refused layout made a file: {sentence}");
    }
    let mut l = full_layout();
    l["extra"] = json!(1);
    let read = Webm::open(&temp_path("unknown"), &l)
        .err()
        .expect("refused");
    assert!(
        read.starts_with("the layout could not be read: unknown field `extra`"),
        "{read}"
    );
    let path = Path::new("/nonexistent-framejob-folder/x.webm");
    let made = Webm::open(path, &full_layout()).err().expect("refused");
    assert!(
        made.starts_with("the file could not be created ("),
        "{made}"
    );
}

#[test]
fn every_packet_refusal_is_its_sentence() {
    let w = Webm::open(&temp_path("packets"), &full_layout()).expect("open");
    assert_eq!(
        w.add(3, 0, true, 0, &[1]),
        Err("track 3 is not in the layout".into())
    );
    assert_eq!(
        w.add(V, -1, true, 0, &[1]),
        Err("pts -1 ns on track 1 is negative".into())
    );
    w.add(V, 100, true, 0, &[1]).expect("first");
    assert_eq!(
        w.add(V, 100, false, 0, &[2]),
        Err("pts 100 ns on track 1 is not after its last, 100 ns".into())
    );
    w.end(A).expect("end audio");
    assert_eq!(w.add(A, 0, true, 0, &[1]), Err("track 2 has ended".into()));
    assert_eq!(w.end(A), Err("track 2 has ended".into()));
    w.finish().expect("finish");
    assert_eq!(
        w.add(V, 200, false, 0, &[3]),
        Err("the file is finished".into())
    );
    assert_eq!(w.end(V), Err("the file is finished".into()));
    assert_eq!(w.finish(), Err("the file is finished".into()));
}

#[test]
fn two_threads_add_at_once() {
    let path = temp_path("threads");
    let w = Webm::open(&path, &full_layout()).expect("open");
    std::thread::scope(|scope| {
        scope.spawn(|| {
            for k in 0..60 {
                w.add(V, frame_ns(k, 30, 1), k % 30 == 0, 0, &frame(k))
                    .expect("video");
            }
            w.end(V).expect("end video");
        });
        scope.spawn(|| {
            for k in 0..100 {
                w.add(A, k as i64 * 20_000_000, true, 0, &opus(k))
                    .expect("audio");
            }
            w.end(A).expect("end audio");
        });
    });
    w.finish().expect("finish");
    let b = std::fs::read(&path).expect("read");
    let (_, seg) = segment(&b);
    let read = blocks(&b, &seg);
    assert_eq!(read.len(), 160);
    assert!(
        read.windows(2).all(|p| p[0].ms <= p[1].ms),
        "the blocks are out of order"
    );
    let c = Container::open(&path).expect("open");
    assert_eq!((c.sample_count(VIDEO), c.sample_count(AUDIO)), (60, 100));
}
