//! Black-box tests for the WebM writer's VP9 track — spec §11 CX-16
//! (codec-export C4) — through `rc_webm_*` as `ExportWebMWriter` drives it for
//! `vp9_webm`: a Profile 0 SDR file and a Profile 2 PQ file, each read back
//! through #216-R's reader (`V_VP9` as `vp09`, the `vpcC` it builds from the
//! first keyframe and the Colour, the key flags) and through
//! `common/ebml_read.rs`'s walk (no CodecPrivate, the Colour's codes,
//! BitsPerChannel and the mastering metadata, the blocks' key flags).

mod common;

use serde_json::json;

use common::ebml_read::{blocks, segment};
use common::webm::*;
use framejob_core::container::{Container, VIDEO};

/// What the reader's `vpcC` is for a profile, depth and CICP: version 1,
/// level 0, 4:2:0 co-sited, studio range, no codec initialisation data.
fn vpcc(profile: u8, depth: u8, cicp: [u8; 3]) -> String {
    hex(&[
        1,
        0,
        0,
        0,
        profile,
        0,
        (depth << 4) | (1 << 1),
        cicp[0],
        cicp[1],
        cicp[2],
        0,
        0,
    ])
}

#[test]
fn a_profile_0_sdr_file_reads_back_as_vp09() {
    let path = temp_path("vp9-sdr");
    write_vp9(&path, true);
    let c = Container::open(&path).expect("the reader opens it");
    let d = c.describe();
    let v = &d["video"];
    assert_eq!(v["codec_id"], json!("V_VP9"));
    assert_eq!(v["fourcc"], json!("vp09"));
    assert_eq!(v["atom"], json!("vpcC"));
    assert_eq!(v["vp9_profile"], json!(0));
    assert_eq!(v["atom_hex"], json!(vpcc(0, 8, [1, 1, 1])));
    assert_eq!(
        (
            v["matrix"].clone(),
            v["transfer"].clone(),
            v["primaries"].clone()
        ),
        (json!(1), json!(1), json!(1))
    );
    assert!(v["mdcv_hex"].is_null() && v["clli_hex"].is_null());
    assert_eq!(v["stream_matrix"], json!(1), "CS_BT_709");
    assert_eq!(v["samples"], json!(60));
    assert_eq!(d["audio"]["samples"], json!(100));
}

#[test]
fn a_profile_2_pq_file_reads_back_as_vp09_with_its_hdr10() {
    let path = temp_path("vp9-pq");
    write_vp9(&path, false);
    let c = Container::open(&path).expect("the reader opens it");
    let d = c.describe();
    let v = &d["video"];
    assert_eq!(v["codec_id"], json!("V_VP9"));
    assert_eq!(v["fourcc"], json!("vp09"));
    assert_eq!(v["vp9_profile"], json!(2));
    assert_eq!(v["atom_hex"], json!(vpcc(2, 10, [9, 16, 9])));
    assert_eq!(v["stream_matrix"], json!(9), "CS_BT_2020");
    assert_eq!(v["mdcv_hex"], json!(MDCV));
    assert_eq!(v["clli_hex"], json!(CLLI));
}

#[test]
fn the_walk_finds_no_codec_private_and_the_colour() {
    for (sdr, cicp, bits) in [(true, [1, 1, 1], 8), (false, [9, 16, 9], 10)] {
        let path = temp_path("vp9-walk");
        write_vp9(&path, sdr);
        let b = std::fs::read(&path).expect("read");
        let (_, seg) = segment(&b);
        let entries = find(&seg, 0x1654_AE6B).all(0xAE);
        let v = entries[0];
        assert_eq!(find(v, 0x86).string(&b), "V_VP9");
        assert!(v.child(0x63A2).is_none(), "a V_VP9 CodecPrivate");
        assert!(entries[1].child(0x63A2).is_some(), "OpusHead stays");
        let colour = find(find(v, 0xE0), 0x55B0);
        assert_eq!(find(colour, 0x55B1).uint(&b), cicp[0]);
        assert_eq!(find(colour, 0x55BA).uint(&b), cicp[1]);
        assert_eq!(find(colour, 0x55BB).uint(&b), cicp[2]);
        assert_eq!(find(colour, 0x55B9).uint(&b), 1);
        assert_eq!(find(colour, 0x55B2).uint(&b), bits);
        if sdr {
            assert!(colour.child(0x55D0).is_none() && colour.child(0x55BC).is_none());
        } else {
            assert_eq!(find(colour, 0x55BC).uint(&b), 1000);
            assert_eq!(find(colour, 0x55BD).uint(&b), 0);
            let m = find(colour, 0x55D0);
            assert_eq!(find(m, 0x55D9).float(&b), 1000.0);
            assert_eq!(find(m, 0x55DA).float(&b), 0.005);
        }
    }
}

#[test]
fn key_flags_are_the_packets_in_the_walk_and_the_reader() {
    for sdr in [true, false] {
        let path = temp_path("vp9-keys");
        write_vp9(&path, sdr);
        let b = std::fs::read(&path).expect("read");
        let (_, seg) = segment(&b);
        let video: Vec<_> = blocks(&b, &seg)
            .into_iter()
            .filter(|r| r.track == 1)
            .collect();
        assert_eq!(video.len(), 60);
        let profile = if sdr { 0 } else { 2 };
        for (k, r) in video.iter().enumerate() {
            let key = k % 30 == 0;
            assert_eq!(r.flags & 0x80 != 0, key, "block {k}");
            assert_eq!(r.frame, vp9_frame(k, profile, key), "block {k}");
        }
        let c = Container::open(&path).expect("open");
        for k in 0..60u64 {
            let s = c.sample(VIDEO, k).expect("a sample");
            assert_eq!(s.sync, k % 30 == 0, "sample {k}");
        }
    }
}

#[test]
fn the_keyframe_colour_space_is_published_as_the_stream_matrix() {
    // Spec §11 CX-16 (10): CS_BT_709 → 1, CS_BT_601 and CS_SMPTE_170 → 6, CS_BT_2020 → 9,
    // CS_UNKNOWN and every other space (240M, reserved, RGB) → null.
    for (space, want) in [
        (0u8, json!(null)),
        (1, json!(6)),
        (2, json!(1)),
        (3, json!(6)),
        (4, json!(null)),
        (5, json!(9)),
        (6, json!(null)),
    ] {
        let path = temp_path("vp9-space");
        let mut video = vp9_layout([30, 1], true);
        video.as_object_mut().unwrap().remove("colour");
        video["colour"] = json!({"matrix": 2, "range": 1, "transfer": 2, "primaries": 2,
                                 "bits_per_channel": 8});
        let layout = json!({"duration_ns": SECOND, "video": video});
        let w = Webm::open(&path, &layout).expect("open");
        for k in 0..30 {
            w.add(
                V,
                frame_ns(k, 30, 1),
                k == 0,
                0,
                &vp9_frame_in(k, 0, k == 0, space),
            )
            .expect("add");
        }
        w.finish().expect("finish");
        let c = Container::open(&path).expect("open");
        assert_eq!(
            c.describe()["video"]["stream_matrix"],
            want,
            "space {space}"
        );
    }
}
