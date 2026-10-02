//! The times a WebM or Matroska frame is copied with, and the space a copy
//! needs (spec §11 #216-R), black box over `rc_container_*`, each file built
//! by `common/ebml.rs`. Every expected number is worked by hand in the
//! comments from what the writer put in the file: the frame grid and a
//! variable rate, decode times under B-frames, CodecDelay, Opus TOC counts,
//! laced audio and video, the `vpcC` record, the AAC ES_Descriptor and
//! `required_bytes`.

mod common;

use serde_json::Value;

use common::ebml::{
    cluster, file, info, opus_head, opus_packet, payload, simple_block, tracks, vp9_keyframe,
    Lacing, Opened, Track,
};
use reelcut_core::container::{AUDIO, VIDEO};

/// An H.264 track whose frames sit at `times` ms (in file order) in one
/// Cluster per frame, each Cluster at the frame's own time.
fn video_at(times: &[i64], default_duration: Option<u64>, scale: u64) -> Opened {
    let mut t = Track::video(1, "V_MPEG4/ISO/AVC");
    t.private = vec![1, 0x42, 0, 0x1E];
    t.default_duration = default_duration;
    let mut body = vec![info(scale), tracks(&[t])];
    for (i, at) in times.iter().enumerate() {
        let frame = payload(i as u8, 10);
        body.push(cluster(
            *at as u64,
            &[simple_block(1, 0, i == 0, Lacing::None, &[frame])],
        ));
    }
    common::ebml::open("timing.mkv", &file("matroska", &body, false)).expect("opens")
}

fn pts(c: &Opened, track: u32) -> Vec<i64> {
    c.samples(track).iter().map(|s| s.pts).collect()
}

#[test]
fn a_steady_rate_in_milliseconds_snaps_to_its_grid() {
    // 30 fps written in ms: frame i at round(i × 1000 / 30).
    let times: Vec<i64> = (0..90).map(|i| (i * 1000 + 15) / 30).collect();
    let mut c = video_at(&times, Some(33_333_333), 1_000_000);
    let d = c.describe();
    assert_eq!(d["video"]["timescale"], 1000, "raw: 1e9 / 1e6");
    assert_eq!(d["video"]["grid"], false);
    let fps = d["video"]["nominal_fps"]
        .as_f64()
        .expect("from DefaultDuration");
    assert!((fps - 30.0).abs() < 1e-5, "{fps}");
    assert_eq!(pts(&c, VIDEO), times, "raw times are the file's own ms");

    assert!(c.retime(30, 1));
    let d = c.describe();
    assert_eq!(d["video"]["timescale"], 30);
    assert_eq!(d["video"]["grid"], true);
    assert_eq!(
        pts(&c, VIDEO),
        (0..90).collect::<Vec<i64>>(),
        "frame k at k × 1 / 30"
    );
    assert!(c.samples(VIDEO).iter().all(|s| s.duration == 1));
}

#[test]
fn an_ntsc_rate_snaps_at_its_own_numerator() {
    // 29.97 in ms: frame i at round(i × 1001 / 30).
    let times: Vec<i64> = (0..60).map(|i| (i * 1001 + 15) / 30).collect();
    let mut c = video_at(&times, None, 1_000_000);
    let fps = c.describe()["video"]["nominal_fps"]
        .as_f64()
        .expect("from the median gap");
    // The median of 33 and 34 ms gaps, mostly 33 or 34: within a frame of 29.97.
    assert!((29.0..31.0).contains(&fps), "{fps}");
    assert!(c.retime(30_000, 1001));
    let expected: Vec<i64> = (0..60).map(|k| k * 1001).collect();
    assert_eq!(pts(&c, VIDEO), expected);
    assert!(c.samples(VIDEO).iter().all(|s| s.duration == 1001));
}

#[test]
fn a_variable_rate_keeps_its_raw_times() {
    // 30 fps with 0–13 ms of jitter: (i/30 + 0.013 × ((i × 7) mod 5) / 4) s.
    let times: Vec<i64> = (0..40)
        .map(|i| (i * 1000 + 15) / 30 + 13 * ((i * 7) % 5) / 4)
        .collect();
    let mut c = video_at(&times, None, 1_000_000);
    assert!(
        !c.retime(30, 1),
        "a frame 9 ms off a 33 ms grid is past a quarter frame"
    );
    let d = c.describe();
    assert_eq!(d["video"]["timescale"], 1000);
    assert_eq!(d["video"]["grid"], false);
    assert_eq!(pts(&c, VIDEO), times);
    // Each duration is the gap to the next frame; the last keeps the gap
    // before it.
    let durations: Vec<i64> = c.samples(VIDEO).iter().map(|s| s.duration).collect();
    let mut expected: Vec<i64> = times.windows(2).map(|w| w[1] - w[0]).collect();
    expected.push(*expected.last().expect("gaps"));
    assert_eq!(durations, expected);
}

#[test]
fn a_timestamp_scale_that_does_not_divide_a_second_reads_in_microseconds() {
    // TimestampScale 3 ms + 1 ns: 1e9 / 3_000_001 is not whole, so µs.
    let c = video_at(&[0, 10, 20], None, 3_000_001);
    assert_eq!(c.describe()["video"]["timescale"], 1_000_000);
    // 10 units × 3_000_001 ns = 30_000_010 ns = 30_000.01 µs → 30_000.
    assert_eq!(pts(&c, VIDEO), [0, 30_000, 60_000]);
}

#[test]
fn b_frames_decode_before_they_present() {
    // Presentation indexes in decode order 0 3 1 2 6 4 5, 40 ms apart. Sorted
    // 0..6; sorted[i] − pts[i] = 0 −2 1 1 −2 1 1, so the shift is 1 frame and
    // the decode times are (0..6) − 1.
    let order = [0i64, 3, 1, 2, 6, 4, 5];
    let times: Vec<i64> = order.iter().map(|k| k * 40).collect();
    let mut c = video_at(&times, Some(40_000_000), 1_000_000);
    assert!(c.retime(25, 1));
    let samples = c.samples(VIDEO);
    let p: Vec<i64> = samples.iter().map(|s| s.pts).collect();
    let d: Vec<i64> = samples.iter().map(|s| s.dts).collect();
    assert_eq!(p, order);
    assert_eq!(d, [-1, 0, 1, 2, 3, 4, 5]);
    assert!(samples.iter().all(|s| s.dts <= s.pts));
}

#[test]
fn a_duplicate_raw_time_moves_one_unit_later() {
    let mut c = video_at(&[0, 33, 33, 67], None, 1_000_000);
    assert!(!c.retime(30, 1), "two frames on one grid point never snap");
    assert_eq!(pts(&c, VIDEO), [0, 33, 34, 67]);
}

#[test]
fn laced_video_frames_follow_by_their_default_duration() {
    let mut t = Track::video(1, "V_MPEG4/ISO/AVC");
    t.private = vec![1];
    t.default_duration = Some(40_000_000);
    let frames = vec![payload(1, 10), payload(2, 11), payload(3, 12)];
    let body = vec![
        info(1_000_000),
        tracks(&[t]),
        cluster(200, &[simple_block(1, 0, true, Lacing::Ebml, &frames)]),
    ];
    let c = common::ebml::open("lace.mkv", &file("matroska", &body, false)).expect("opens");
    // 200 ms, then 40 ms a frame.
    assert_eq!(pts(&c, VIDEO), [200, 240, 280]);
}

fn opus_file(packets: &[(i16, Vec<Vec<u8>>)], codec_delay: Option<u64>) -> Opened {
    let mut t = Track::audio(1, "A_OPUS", 48_000.0);
    t.private = opus_head();
    t.codec_delay = codec_delay;
    let blocks: Vec<Vec<u8>> = packets
        .iter()
        .map(|(rel, frames)| {
            let lacing = if frames.len() > 1 {
                Lacing::Xiph
            } else {
                Lacing::None
            };
            simple_block(1, *rel, true, lacing, frames)
        })
        .collect();
    let body = vec![info(1_000_000), tracks(&[t]), cluster(0, &blocks)];
    common::ebml::open("opus.webm", &file("webm", &body, false)).expect("opens")
}

#[test]
fn codec_delay_is_taken_off_every_opus_time() {
    // CodecDelay 6.5 ms = 312 samples at 48 kHz.
    let p = |len| vec![opus_packet(31, 0, 0, len)];
    let c = opus_file(&[(0, p(20)), (20, p(21)), (40, p(22))], Some(6_500_000));
    let d = c.describe();
    assert_eq!(d["audio"]["timescale"], 48_000);
    assert_eq!(pts(&c, AUDIO), [-312, 648, 1608]);
    assert!(c.samples(AUDIO).iter().all(|s| s.sync && s.dts == s.pts));
}

#[test]
fn an_opus_packet_counts_its_samples_from_its_toc() {
    // Config 3 SILK 60 ms = 2880; config 31 CELT 20 ms × code 3 count 3 =
    // 2880; config 16 CELT 2.5 ms = 120; config 13 hybrid 20 ms × code 1 =
    // 1920; config 0 SILK 10 ms × code 2 = 960.
    let packets = [
        (0, vec![opus_packet(3, 0, 0, 30)]),
        (60, vec![opus_packet(31, 3, 3, 30)]),
        (120, vec![opus_packet(16, 0, 0, 30)]),
        (123, vec![opus_packet(13, 1, 0, 30)]),
        (163, vec![opus_packet(0, 2, 0, 30)]),
    ];
    let c = opus_file(&packets, None);
    let samples = c.samples(AUDIO);
    let frames: Vec<u32> = samples.iter().map(|s| s.frames).collect();
    assert_eq!(frames, [2880, 2880, 120, 1920, 960]);
    let durations: Vec<i64> = samples.iter().map(|s| s.duration).collect();
    assert_eq!(durations, [2880, 2880, 120, 1920, 960]);
    assert_eq!(c.describe()["audio"]["frames_per_packet"], 0);
}

#[test]
fn an_opus_lace_is_spaced_by_its_toc_counts() {
    // One Block at 100 ms = 4800 samples: 20 ms (960), 10 ms (480), 60 ms.
    let lace = vec![
        opus_packet(31, 0, 0, 25),
        opus_packet(30, 0, 0, 26),
        opus_packet(3, 0, 0, 27),
    ];
    let c = opus_file(&[(100, lace)], None);
    assert_eq!(pts(&c, AUDIO), [4800, 5760, 6240]);
}

#[test]
fn a_lace_whose_first_frame_is_empty_starts_at_its_own_block() {
    // Two 20 ms frames at 0 ms, then a Block at 100 ms whose frame 0 is zero
    // bytes: its frames start at 4800, not after the first Block's 1920.
    let p = |len| opus_packet(31, 0, 0, len);
    let c = opus_file(
        &[
            (0, vec![p(20), p(21)]),
            (100, vec![Vec::new(), p(22), p(23)]),
        ],
        None,
    );
    assert_eq!(pts(&c, AUDIO), [0, 960, 4800, 5760]);
}

#[test]
fn laced_aac_frames_are_1024_samples_apart() {
    let mut t = Track::audio(1, "A_AAC", 48_000.0);
    t.private = vec![0x11, 0x90];
    let frames: Vec<Vec<u8>> = (0..4).map(|i| payload(i, 50 + i as usize)).collect();
    let body = vec![
        info(1_000_000),
        tracks(&[t]),
        cluster(100, &[simple_block(1, 0, true, Lacing::Xiph, &frames)]),
    ];
    let c = common::ebml::open("aac-lace.mkv", &file("matroska", &body, false)).expect("opens");
    // 100 ms at 48 kHz is 4800; then 1024 a frame.
    assert_eq!(pts(&c, AUDIO), [4800, 5824, 6848, 7872]);
    assert!(c
        .samples(AUDIO)
        .iter()
        .all(|s| s.frames == 0 && s.duration == 1024));
}

fn vp9_with(header: Vec<u8>, colour: Option<(u64, u64, u64, u64)>) -> Value {
    let mut t = Track::video(1, "V_VP9");
    t.colour = colour;
    let body = vec![
        info(1_000_000),
        tracks(&[t]),
        cluster(0, &[simple_block(1, 0, true, Lacing::None, &[header])]),
    ];
    let c = common::ebml::open("vpcc.webm", &file("webm", &body, false)).expect("opens");
    c.describe()["video"].clone()
}

#[test]
fn a_vpcc_record_is_built_from_the_first_keyframe() {
    // vpcC v1: version 1, flags 0, profile, level 0, bitDepth(4) |
    // chroma(3) | fullRange(1), primaries, transfer, matrix, init size 0.
    // Profile 0, BT.709 (space 2), limited, 4:2:0: 8<<4 | 1<<1 | 0 = 0x82.
    let v = vp9_with(vp9_keyframe(0, false, 2, 0, (1, 1)), None);
    assert_eq!(v["atom_hex"], "010000000000820202010000");
    assert_eq!(v["vp9_profile"], 0);
    // Profile 2, 10-bit, BT.2020 (space 5), full: 10<<4 | 1<<1 | 1 = 0xA3.
    let v = vp9_with(vp9_keyframe(2, false, 5, 1, (1, 1)), None);
    assert_eq!(v["atom_hex"], "01000000020 0a3020209 0000".replace(' ', ""));
    // Profile 1, 4:4:4, BT.601 (space 1): 8<<4 | 3<<1 | 0 = 0x86, matrix 6.
    let v = vp9_with(vp9_keyframe(1, false, 1, 0, (0, 0)), None);
    assert_eq!(v["atom_hex"], "010000000100860202060000");
    assert_eq!(v["vp9_profile"], 1);
    // The Colour element overrides: matrix 9, range 2 (full), transfer 16,
    // primaries 9.
    let v = vp9_with(vp9_keyframe(0, false, 2, 0, (1, 1)), Some((9, 2, 16, 9)));
    assert_eq!(v["atom_hex"], "010000000000830910090000");
    // Not a keyframe header: refused, naming the track.
    let mut t = Track::video(1, "V_VP9");
    t.colour = None;
    let body = vec![
        info(1_000_000),
        tracks(&[t]),
        cluster(
            0,
            &[simple_block(1, 0, true, Lacing::None, &[payload(0, 30)])],
        ),
    ];
    let refused = common::ebml::open("bad.webm", &file("webm", &body, false));
    assert_eq!(
        refused.err().as_deref(),
        Some("the first VP9 keyframe on track 1 could not be read")
    );
}

#[test]
fn an_aac_cookie_is_an_es_descriptor_around_its_audio_specific_config() {
    let mut t = Track::audio(1, "A_AAC", 44_100.0);
    t.private = vec![0x12, 0x10];
    let body = vec![
        info(1_000_000),
        tracks(&[t]),
        cluster(
            0,
            &[simple_block(1, 0, true, Lacing::None, &[payload(1, 9)])],
        ),
    ];
    let c = common::ebml::open("esds.mkv", &file("matroska", &body, false)).expect("opens");
    // ES_Descriptor (03, 25 bytes): ES_ID 1, flags 0; DecoderConfig (04, 17):
    // MPEG-4 audio 0x40, audio stream 0x15, buffer 0, bitrates 0; its
    // DecSpecificInfo (05, 2) = the ASC; SLConfig (06, 1) predefined 2.
    let expected = "0319 000100 0411 4015 000000 00000000 00000000 0502 1210 060102";
    assert_eq!(
        c.describe()["audio"]["cookie_hex"],
        expected.replace(' ', "")
    );
}

#[test]
fn required_bytes_is_the_payload_plus_sixty_four_a_sample_plus_sixteen_mib() {
    let mut h264 = Track::video(1, "V_MPEG4/ISO/AVC");
    h264.private = vec![1];
    let mut aac = Track::audio(2, "A_AAC", 48_000.0);
    aac.private = vec![0x11, 0x90];
    let body = vec![
        info(1_000_000),
        tracks(&[h264, aac]),
        cluster(
            0,
            &[
                simple_block(1, 0, true, Lacing::None, &[payload(1, 1000)]),
                simple_block(2, 0, true, Lacing::None, &[payload(2, 300)]),
                simple_block(1, 33, false, Lacing::None, &[payload(3, 500)]),
                simple_block(2, 21, true, Lacing::None, &[payload(4, 301)]),
                simple_block(2, 43, true, Lacing::None, &[payload(5, 302)]),
            ],
        ),
    ];
    let c = common::ebml::open("space.mkv", &file("matroska", &body, false)).expect("opens");
    // 1500 + 903 payload, 5 samples × 64, 16 MiB.
    let expected = 1500 + 903 + 5 * 64 + (16 << 20);
    assert_eq!(c.describe()["required_bytes"].as_u64(), Some(expected));
}
