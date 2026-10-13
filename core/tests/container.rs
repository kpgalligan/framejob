//! A WebM or Matroska file's index (spec §11 #216-R), black box over the
//! `rc_container_*` exports, every file built by `common/ebml.rs`'s writer:
//! the header and the tracks picked, every lacing, unknown sizes, a
//! truncated tail, each refusal by its sentence, and hostile bytes that
//! must never panic. The times are `container_timing.rs`'s.

mod common;

use std::path::Path;

use serde_json::Value;

use common::ebml::{
    block_group, cluster, cluster_unknown, element, file, info, master, opus_head, opus_packet,
    payload, simple_block, tracks, uint, vp9_keyframe, write_temp, Lacing, Track, CUES,
};
use framejob_core::container::{Container, RcContainerSample, AUDIO, VIDEO};

/// The bytes a sample's index entry points at, read from the file itself.
fn bytes_at(file: &[u8], s: &RcContainerSample) -> Vec<u8> {
    let start = s.offset as usize;
    file[start..start + s.size as usize].to_vec()
}

fn vp9_frame(tag: u8, key: bool) -> Vec<u8> {
    if key {
        let mut f = vp9_keyframe(0, false, 2, 0, (1, 1));
        f.extend(payload(tag, 20));
        f
    } else {
        payload(tag, 30)
    }
}

/// A WebM: a subtitle track first, then VP9 (no CodecPrivate), a second
/// video track and Opus, two Clusters.
fn webm() -> (Vec<u8>, Vec<Vec<u8>>, Vec<Vec<u8>>) {
    let mut subs = Track::video(1, "S_TEXT/UTF8");
    subs.kind = 0x11;
    let mut vp9 = Track::video(2, "V_VP9");
    vp9.default_duration = Some(33_333_333);
    let second = Track::video(3, "V_MPEG4/ISO/AVC");
    let mut opus = Track::audio(4, "A_OPUS", 48_000.0);
    opus.private = opus_head();
    let v: Vec<Vec<u8>> = (0..4).map(|i| vp9_frame(10 + i, i == 0)).collect();
    let a: Vec<Vec<u8>> = (0..3).map(|i| opus_packet(31, 0, 0, 40 + i)).collect();
    let body = vec![
        info(1_000_000),
        tracks(&[subs, vp9, second, opus]),
        cluster(
            0,
            &[
                simple_block(2, 0, true, Lacing::None, &[v[0].clone()]),
                simple_block(4, 0, true, Lacing::None, &[a[0].clone()]),
                simple_block(3, 0, true, Lacing::None, &[payload(99, 9)]),
                simple_block(1, 0, true, Lacing::None, &[b"hello".to_vec()]),
                simple_block(2, 33, false, Lacing::None, &[v[1].clone()]),
                simple_block(4, 20, true, Lacing::None, &[a[1].clone()]),
            ],
        ),
        cluster(
            67,
            &[
                simple_block(2, 0, false, Lacing::None, &[v[2].clone()]),
                simple_block(4, -7, true, Lacing::None, &[a[2].clone()]),
                simple_block(2, 33, false, Lacing::None, &[v[3].clone()]),
            ],
        ),
    ];
    (file("webm", &body, false), v, a)
}

#[test]
fn a_webm_opens_with_its_first_video_and_first_audio_track() {
    let (bytes, v, a) = webm();
    let c = common::ebml::open("p.webm", &bytes).expect("opens");
    let d = c.describe();
    assert_eq!(d["doc_type"], "webm");
    let video = &d["video"];
    assert_eq!(video["codec_id"], "V_VP9");
    assert_eq!(video["fourcc"], "vp09");
    assert_eq!(video["encoded"], false);
    assert_eq!(
        (video["width"].as_u64(), video["height"].as_u64()),
        (Some(640), Some(360))
    );
    assert_eq!(video["atom"], "vpcC");
    assert_eq!(video["vp9_profile"], 0);
    assert_eq!(video["samples"], 4);
    let video_bytes: usize = v.iter().map(Vec::len).sum();
    assert_eq!(video["bytes"].as_u64(), Some(video_bytes as u64));
    let audio = &d["audio"];
    assert_eq!(audio["codec_id"], "A_OPUS");
    assert_eq!(audio["fourcc"], "opus");
    assert_eq!(audio["sample_rate"], 48_000);
    assert_eq!(audio["channels"], 2);
    let head: String = opus_head().iter().map(|b| format!("{b:02x}")).collect();
    assert_eq!(audio["cookie_hex"], Value::String(head));
    assert_eq!(audio["frames_per_packet"], 0);
    assert_eq!(audio["samples"], 3);

    let vs = c.samples(VIDEO);
    let read: Vec<Vec<u8>> = vs.iter().map(|s| bytes_at(&bytes, s)).collect();
    assert_eq!(read, v, "every video entry points at its own frame's bytes");
    assert_eq!(
        vs.iter().map(|s| s.sync).collect::<Vec<_>>(),
        [true, false, false, false]
    );
    assert!(vs.iter().all(|s| s.frames == 0));
    let read: Vec<Vec<u8>> = c
        .samples(AUDIO)
        .iter()
        .map(|s| bytes_at(&bytes, s))
        .collect();
    assert_eq!(read, a);
    assert_eq!(c.samples(7), Vec::new(), "a third track is nothing");
}

#[test]
fn a_matroska_h264_and_aac_carry_their_codec_private() {
    let mut h264 = Track::video(1, "V_MPEG4/ISO/AVC");
    h264.private = vec![1, 0x64, 0, 0x1E, 0xFF, 0xE1, 0, 0];
    let mut aac = Track::audio(2, "A_AAC", 44_100.0);
    aac.private = vec![0x12, 0x10];
    let body = vec![
        info(1_000_000),
        tracks(&[h264, aac]),
        cluster(
            0,
            &[
                simple_block(1, 0, true, Lacing::None, &[payload(1, 50)]),
                simple_block(2, 0, true, Lacing::None, &[payload(2, 10)]),
            ],
        ),
    ];
    let c = common::ebml::open("p.mkv", &file("matroska", &body, false)).expect("opens");
    let d = c.describe();
    assert_eq!(d["doc_type"], "matroska");
    assert_eq!(d["video"]["fourcc"], "avc1");
    assert_eq!(d["video"]["atom"], "avcC");
    assert_eq!(d["video"]["atom_hex"], "016400 1effe10000".replace(' ', ""));
    assert_eq!(d["video"]["vp9_profile"], Value::Null);
    assert_eq!(d["audio"]["fourcc"], "aac ");
    assert_eq!(d["audio"]["frames_per_packet"], 1024);
    assert_eq!(d["audio"]["sample_rate"], 44_100);
    assert_eq!(d["audio"]["timescale"], 44_100);
}

#[test]
fn every_lacing_indexes_each_frame_of_the_block() {
    for (name, lacing) in [
        ("xiph", Lacing::Xiph),
        ("ebml", Lacing::Ebml),
        ("fixed", Lacing::Fixed),
    ] {
        let frames: Vec<Vec<u8>> = if lacing == Lacing::Fixed {
            (0..4).map(|i| payload(40 + i, 33)).collect()
        } else {
            // 300 bytes needs a Xiph run of 255s; a shrinking size a
            // negative EBML delta.
            vec![
                payload(40, 300),
                payload(41, 7),
                payload(42, 260),
                payload(43, 5),
            ]
        };
        let mut aac = Track::audio(1, "A_AAC", 48_000.0);
        aac.private = vec![0x11, 0x90];
        let body = vec![
            info(1_000_000),
            tracks(&[aac]),
            cluster(0, &[simple_block(1, 0, true, lacing, &frames)]),
        ];
        let bytes = file("webm", &body, false);
        let c = common::ebml::open(&format!("{name}.webm"), &bytes).expect(name);
        let read: Vec<Vec<u8>> = c
            .samples(AUDIO)
            .iter()
            .map(|s| bytes_at(&bytes, s))
            .collect();
        assert_eq!(read, frames, "{name} lacing");
        assert_eq!(c.describe()["video"], Value::Null);
    }
}

#[test]
fn unknown_sizes_end_at_the_next_level_one_element() {
    let mut aac = Track::audio(1, "A_AAC", 48_000.0);
    aac.private = vec![0x11, 0x90];
    let frames: Vec<Vec<u8>> = (0..5).map(|i| payload(60 + i, 12)).collect();
    let block = |i: usize, rel: i16| simple_block(1, rel, true, Lacing::None, &[frames[i].clone()]);
    let body = vec![
        info(1_000_000),
        tracks(&[aac]),
        cluster_unknown(0, &[block(0, 0), block(1, 21)]),
        cluster_unknown(43, &[block(2, 0)]),
        // Cues end the second Cluster; the third follows them.
        master(CUES, &[uint(0xBB, 0)]),
        cluster_unknown(64, &[block(3, 0), block(4, 21)]),
    ];
    let bytes = file("webm", &body, true);
    let c = common::ebml::open("live.webm", &bytes).expect("opens");
    let read: Vec<Vec<u8>> = c
        .samples(AUDIO)
        .iter()
        .map(|s| bytes_at(&bytes, s))
        .collect();
    assert_eq!(read, frames);
}

#[test]
fn a_block_group_is_a_keyframe_only_without_a_reference_block() {
    let mut h264 = Track::video(1, "V_MPEG4/ISO/AVC");
    h264.private = vec![1, 2, 3];
    let body = vec![
        info(1_000_000),
        tracks(&[h264]),
        cluster(
            0,
            &[
                block_group(1, 0, false, &[payload(1, 20)]),
                block_group(1, 33, true, &[payload(2, 20)]),
                block_group(1, 67, false, &[payload(3, 20)]),
            ],
        ),
    ];
    let c = common::ebml::open("g.mkv", &file("matroska", &body, false)).expect("opens");
    let sync: Vec<bool> = c.samples(VIDEO).iter().map(|s| s.sync).collect();
    assert_eq!(sync, [true, false, true]);
}

#[test]
fn a_truncated_tail_ends_the_index_with_what_came_before_it() {
    let (bytes, v, _) = webm();
    let whole = common::ebml::open("whole.webm", &bytes).expect("opens");
    let full = whole.samples(VIDEO).len();
    // Cut inside the last video frame: it goes, the others stay.
    let cut = bytes.len() - 5;
    let c = common::ebml::open("cut.webm", &bytes[..cut]).expect("a cut file still opens");
    let vs = c.samples(VIDEO);
    assert_eq!(vs.len(), full - 1);
    assert!(vs
        .iter()
        .all(|s| s.offset + u64::from(s.size) <= cut as u64));
    let read: Vec<Vec<u8>> = vs.iter().map(|s| bytes_at(&bytes, s)).collect();
    assert_eq!(read, v[..full - 1]);
    // Every cut past the Tracks element opens, never with a sample past it.
    for cut in (bytes.len() / 2)..bytes.len() {
        if let Ok(c) = common::ebml::open("cuts.webm", &bytes[..cut]) {
            for track in [VIDEO, AUDIO] {
                assert!(c
                    .samples(track)
                    .iter()
                    .all(|s| s.offset + u64::from(s.size) <= cut as u64));
            }
        }
    }
}

fn refusal(name: &str, bytes: &[u8]) -> String {
    match common::ebml::open(name, bytes) {
        Ok(_) => panic!("{name} opened"),
        Err(message) => message,
    }
}

#[test]
fn each_refusal_names_what_it_could_not_read() {
    assert_eq!(
        refusal("text.webm", b"not a movie at all"),
        "it does not begin with an EBML header"
    );
    let body = vec![info(1_000_000), tracks(&[Track::video(1, "V_VP9")])];
    assert_eq!(
        refusal("doc.webm", &file("mkv-ish", &body, false)),
        "its DocType is “mkv-ish”, not webm or matroska"
    );
    assert_eq!(
        refusal(
            "no-tracks.webm",
            &file("webm", &[info(1_000_000), cluster(0, &[])], false)
        ),
        "it has no Tracks element before its first Cluster"
    );
    let mut big = Track::video(3, "V_MPEG4/ISO/AVC");
    big.private = vec![0; (1 << 20) + 1];
    assert_eq!(
        refusal(
            "big.mkv",
            &file("matroska", &[info(1_000_000), tracks(&[big])], false)
        ),
        "track 3's CodecPrivate is 1048577 bytes, over the 1 MiB limit"
    );
    assert_eq!(
        refusal(
            "scale.mkv",
            &file("matroska", &[info(0), tracks(&[])], false)
        ),
        "its TimestampScale is 0"
    );
    let missing = common::ebml::open("missing", b"");
    assert!(missing.is_err());
    let path = std::env::temp_dir().join("framejob-no-such-file.webm");
    let unopened = Container::open(Path::new(&path))
        .err()
        .expect("no file, no container");
    assert!(
        unopened.starts_with("the file could not be opened"),
        "{unopened}"
    );
}

/// A laced Block on video: refused at open with no DefaultDuration on a
/// track that is copied; read with one; never refused on a track that is
/// not copied.
fn laced_video(codec: &str, default_duration: Option<u64>) -> Vec<u8> {
    let mut t = Track::video(1, codec);
    t.private = vec![1, 2, 3];
    t.default_duration = default_duration;
    let frames = vec![payload(1, 10), payload(2, 10), payload(3, 10)];
    let body = vec![
        info(1_000_000),
        tracks(&[t]),
        cluster(0, &[simple_block(1, 0, true, Lacing::Xiph, &frames)]),
    ];
    file("matroska", &body, false)
}

#[test]
fn a_laced_video_block_needs_a_default_duration_on_a_copied_track() {
    assert_eq!(
        refusal("laced.mkv", &laced_video("V_MPEG4/ISO/AVC", None)),
        "track 1 has laced video Blocks and no DefaultDuration, so its frames have no times"
    );
    let c = common::ebml::open(
        "laced-dd.mkv",
        &laced_video("V_MPEG4/ISO/AVC", Some(40_000_000)),
    )
    .expect("a DefaultDuration times the lace");
    assert_eq!(c.samples(VIDEO).len(), 3);
    let c = common::ebml::open("laced-mpeg2.mkv", &laced_video("V_MPEG2", None))
        .expect("a track that is not copied is not refused for its lace");
    assert_eq!(c.describe()["video"]["fourcc"], Value::Null);
}

#[test]
fn a_codec_that_is_not_copied_is_described_with_no_samples() {
    let mut vorbis = Track::audio(2, "A_VORBIS", 44_100.0);
    vorbis.private = vec![2, 30, 60];
    let mut encoded = Track::video(1, "V_MPEG4/ISO/AVC");
    encoded.private = vec![1];
    encoded.encoded = true;
    let body = vec![
        info(1_000_000),
        tracks(&[encoded, vorbis]),
        cluster(
            0,
            &[
                simple_block(1, 0, true, Lacing::None, &[payload(1, 100)]),
                simple_block(2, 0, true, Lacing::None, &[payload(2, 100)]),
            ],
        ),
    ];
    let c = common::ebml::open("vorbis.webm", &file("webm", &body, false)).expect("opens");
    let d = c.describe();
    assert_eq!(d["audio"]["codec_id"], "A_VORBIS");
    assert_eq!(d["audio"]["fourcc"], Value::Null);
    assert_eq!(
        (d["audio"]["samples"].as_u64(), d["audio"]["bytes"].as_u64()),
        (Some(0), Some(0))
    );
    assert_eq!(d["video"]["encoded"], true);
    assert_eq!(d["video"]["samples"], 0);
    assert_eq!(
        d["required_bytes"].as_u64(),
        Some(16 << 20),
        "nothing copied needs only the margin"
    );
    assert!(c.samples(AUDIO).is_empty() && c.samples(VIDEO).is_empty());

    let vp8 = Track::video(1, "V_VP8");
    let body = vec![
        info(1_000_000),
        tracks(&[vp8]),
        cluster(
            0,
            &[simple_block(1, 0, true, Lacing::None, &[payload(1, 10)])],
        ),
    ];
    let c = common::ebml::open("vp8.webm", &file("webm", &body, false)).expect("opens");
    assert_eq!(c.describe()["video"]["fourcc"], "vp08");
    assert_eq!(c.describe()["audio"], Value::Null);

    // An encoded VP9 track's keyframe is not VP9 bytes; it is described, not
    // refused, so the app's "compressed or encrypted" sentence is reached.
    let mut vp9 = Track::video(1, "V_VP9");
    vp9.encoded = true;
    let body = vec![
        info(1_000_000),
        tracks(&[vp9]),
        cluster(
            0,
            &[simple_block(1, 0, true, Lacing::None, &[payload(1, 10)])],
        ),
    ];
    let c = common::ebml::open("vp9-encoded.webm", &file("webm", &body, false))
        .expect("an encoded VP9 track opens");
    let d = c.describe();
    assert_eq!(
        (
            d["video"]["fourcc"].as_str(),
            d["video"]["encoded"].as_bool()
        ),
        (Some("vp09"), Some(true))
    );
    assert_eq!(d["video"]["samples"], 0);
}

#[test]
fn a_track_with_no_frames_is_null() {
    let mut aac = Track::audio(2, "A_AAC", 48_000.0);
    aac.private = vec![0x11, 0x90];
    let mut h264 = Track::video(1, "V_MPEG4/ISO/AVC");
    h264.private = vec![1];
    let body = vec![
        info(1_000_000),
        tracks(&[h264, aac]),
        cluster(
            0,
            &[simple_block(2, 0, true, Lacing::None, &[payload(1, 10)])],
        ),
    ];
    let c = common::ebml::open("audio-only.webm", &file("webm", &body, false)).expect("opens");
    assert_eq!(c.describe()["video"], Value::Null);
    assert_eq!(c.describe()["audio"]["samples"], 1);
    // An unknown element before the first Cluster is skipped.
    let mut body = body;
    body.insert(0, element(0x1254_C367, &[0xEC, 0x80]));
    assert!(common::ebml::open("tags.webm", &file("webm", &body, false)).is_ok());
}

/// A xorshift: the hostile-byte sweep is deterministic.
fn next(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}

#[test]
fn hostile_bytes_never_panic() {
    let (bytes, _, _) = webm();
    let path = write_temp("hostile.webm", &bytes);
    let mut state = 0x9E37_79B9_7F4A_7C15u64;
    for round in 0..3000 {
        let mut mutated = bytes.clone();
        let edits = 1 + (next(&mut state) % 8) as usize;
        for _ in 0..edits {
            let at = (next(&mut state) as usize) % mutated.len();
            mutated[at] = match round % 3 {
                0 => next(&mut state) as u8,
                1 => 0xFF,
                _ => 0x01,
            };
        }
        if round % 5 == 0 {
            let keep = (next(&mut state) as usize) % mutated.len();
            mutated.truncate(keep);
        }
        std::fs::write(&path, &mutated).expect("rewrite");
        // Called directly, so a panic fails the test rather than being
        // caught by the FFI's guard.
        if let Ok(mut c) = Container::open(&path) {
            let _ = c.describe();
            let _ = c.retime(framejob_core::Fps { num: 30, den: 1 });
            for track in [VIDEO, AUDIO] {
                for i in 0..c.sample_count(track) {
                    let s = c.sample(track, i).expect("every counted sample reads");
                    assert!(s.offset + u64::from(s.size) <= mutated.len() as u64);
                }
            }
        }
    }
    let _ = std::fs::remove_file(&path);
}
