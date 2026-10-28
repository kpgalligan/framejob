//! Black-box tests for the WebM writer's alpha — spec §11 CX-17 (codec-export
//! C5) — through `rc_webm_*` as `ExportWebMWriter` drives it for
//! `vp9_alpha_webm`: a layout with `alpha_mode` and its packets through
//! `rc_webm_add_video_with_alpha`, read back through `common/ebml_read.rs`'s
//! walk (MaxBlockAdditionID and AlphaMode, every video block a BlockGroup with
//! BlockAddID 1, the ReferenceBlock exactly on the non-keys, Clusters and Cues
//! at the keys) and through #216-R's reader (the same keys and frame count,
//! each sample the picture's frame and not its alpha), and every refusal.

mod common;

use std::ffi::c_char;
use std::ptr;

use serde_json::json;

use common::ebml_read::{blocks, segment};
use common::take_string;
use common::webm::*;
use framejob_core::container::{Container, VIDEO};
use framejob_core::ffi_webm::rc_webm_add_video_with_alpha;

#[test]
fn alpha_mode_writes_max_block_addition_id_and_alpha_mode() {
    let path = temp_path("alpha-entry");
    write_vp9_alpha(&path);
    let b = std::fs::read(&path).expect("read");
    let (_, seg) = segment(&b);
    let entries = find(&seg, 0x1654_AE6B).all(0xAE);
    let v = entries[0];
    assert_eq!(find(v, 0x86).string(&b), "V_VP9");
    assert_eq!(find(v, 0x55EE).uint(&b), 1, "MaxBlockAdditionID");
    assert_eq!(find(find(v, 0xE0), 0x53C0).uint(&b), 1, "AlphaMode");
    assert!(v.child(0x41E4).is_none(), "no BlockAdditionMapping");
    assert!(
        entries[1].child(0x55EE).is_none(),
        "the audio track has none"
    );

    // Without alpha_mode neither is written: `vp9_webm`'s file is unchanged.
    let path = temp_path("alpha-none");
    write_vp9(&path, true);
    let b = std::fs::read(&path).expect("read");
    let (_, seg) = segment(&b);
    let v = find(&seg, 0x1654_AE6B).all(0xAE)[0].clone();
    assert!(v.child(0x55EE).is_none());
    assert!(find(&v, 0xE0).child(0x53C0).is_none());
}

#[test]
fn every_video_block_is_a_block_group_carrying_its_alpha() {
    let path = temp_path("alpha-groups");
    write_vp9_alpha(&path);
    let b = std::fs::read(&path).expect("read");
    let (_, seg) = segment(&b);
    let read = blocks(&b, &seg);
    let video: Vec<_> = read.iter().filter(|r| r.track == 1).collect();
    assert_eq!(video.len(), 60);
    for (k, r) in video.iter().enumerate() {
        let key = k % 30 == 0;
        assert!(r.group, "block {k} is a BlockGroup");
        assert_eq!(r.flags, 0, "block {k}'s Block flags");
        assert_eq!(r.frame, vp9_frame(k, 0, key), "block {k}'s picture");
        assert_eq!(
            r.additions,
            vec![(1, vp9_alpha(k, key))],
            "block {k}'s alpha"
        );
        assert_eq!(r.discard, None);
    }
    for r in read.iter().filter(|r| r.track == 2) {
        assert!(!r.group, "audio stays SimpleBlocks");
        assert!(r.additions.is_empty() && r.reference.is_none());
    }
}

#[test]
fn the_reference_block_is_on_exactly_the_non_keys() {
    let path = temp_path("alpha-refs");
    write_vp9_alpha(&path);
    let b = std::fs::read(&path).expect("read");
    let (_, seg) = segment(&b);
    let video: Vec<_> = blocks(&b, &seg)
        .into_iter()
        .filter(|r| r.track == 1)
        .collect();
    for (k, r) in video.iter().enumerate() {
        if k % 30 == 0 {
            assert_eq!(r.reference, None, "key {k} has no ReferenceBlock");
        } else {
            let want = video[k - 1].ms - r.ms;
            assert!(want < 0);
            assert_eq!(r.reference, Some(want), "block {k}");
        }
    }
}

#[test]
fn clusters_and_cues_start_at_the_keys() {
    let path = temp_path("alpha-cues");
    write_vp9_alpha(&path);
    let b = std::fs::read(&path).expect("read");
    let (_, seg) = segment(&b);
    let clusters = seg.all(0x1F43_B675);
    let times: Vec<u64> = clusters.iter().map(|c| find(c, 0xE7).uint(&b)).collect();
    assert_eq!(times, vec![0, 1000]);
    let points = find(&seg, 0x1C53_BB6B).all(0xBB);
    assert_eq!(points.len(), 2);
    for (point, cluster) in points.iter().zip(&clusters) {
        let positions = find(point, 0xB7);
        assert_eq!(find(positions, 0xF7).uint(&b), 1);
        let at = find(positions, 0xF1).uint(&b) as usize;
        assert_eq!(seg.data + at, cluster.start);
    }
}

#[test]
fn the_216r_reader_reads_the_same_keys_and_frames() {
    let path = temp_path("alpha-reader");
    write_vp9_alpha(&path);
    let b = std::fs::read(&path).expect("read");
    let c = Container::open(&path).expect("the reader opens it");
    let d = c.describe();
    assert_eq!(d["video"]["codec_id"], json!("V_VP9"));
    assert_eq!(d["video"]["fourcc"], json!("vp09"));
    assert_eq!(d["video"]["samples"], json!(60));
    assert_eq!(d["audio"]["samples"], json!(100));
    for k in 0..60u64 {
        let s = c.sample(VIDEO, k).expect("a sample");
        assert_eq!(s.sync, k % 30 == 0, "sample {k}");
        let bytes = &b[s.offset as usize..s.offset as usize + s.size as usize];
        let key = k % 30 == 0;
        assert_eq!(
            bytes,
            vp9_frame(k as usize, 0, key),
            "sample {k} is the picture"
        );
    }
}

#[test]
fn every_alpha_refusal_is_its_sentence() {
    // alpha_mode on V_AV1, at open.
    let mut video = video_layout([30, 1], false);
    video["alpha_mode"] = json!(true);
    let layout = json!({"duration_ns": SECOND, "video": video});
    assert_eq!(
        Webm::open(&temp_path("alpha-av1"), &layout).err(),
        Some("alpha_mode needs V_VP9; V_AV1 carries no alpha".to_string())
    );

    // An alpha packet on a track without alpha_mode.
    let layout = json!({"duration_ns": SECOND, "video": vp9_layout([30, 1], true)});
    let w = Webm::open(&temp_path("alpha-off"), &layout).expect("open");
    assert_eq!(
        w.add_alpha(0, true, &[1], &[2]),
        Err("track 1 has no alpha_mode, so a packet cannot carry alpha".into())
    );

    // A packet without its alpha on a track with alpha_mode, an empty alpha,
    // and add_packet's own refusals through the alpha door.
    let layout = json!({"duration_ns": SECOND, "video": vp9_alpha_layout([30, 1]),
                        "audio": audio_layout()});
    let w = Webm::open(&temp_path("alpha-on"), &layout).expect("open");
    assert_eq!(
        w.add(V, 0, true, 0, &[1]),
        Err("track 1 has alpha_mode, so each packet carries its alpha".into())
    );
    assert_eq!(
        w.add_alpha(100, true, &[1], &[]),
        Err("the alpha of the packet at 100 ns is empty".into())
    );
    assert_eq!(
        w.add_alpha(-1, true, &[1], &[2]),
        Err("pts -1 ns on track 1 is negative".into())
    );
    w.add_alpha(100, true, &[1], &[2]).expect("first");
    assert_eq!(
        w.add_alpha(100, false, &[1], &[2]),
        Err("pts 100 ns on track 1 is not after its last, 100 ns".into())
    );
    let mut err: *mut c_char = ptr::null_mut();
    let byte = [1u8];
    assert!(!unsafe {
        rc_webm_add_video_with_alpha(w.0, 200, false, byte.as_ptr(), 1, ptr::null(), 0, &mut err)
    });
    assert_eq!(take_string(err).as_deref(), Some("alpha is NULL"));
    let mut err: *mut c_char = ptr::null_mut();
    assert!(!unsafe {
        rc_webm_add_video_with_alpha(w.0, 200, false, ptr::null(), 0, byte.as_ptr(), 1, &mut err)
    });
    assert_eq!(take_string(err).as_deref(), Some("bytes is NULL"));
    w.end(V).expect("end video");
    assert_eq!(
        w.add_alpha(200, false, &[1], &[2]),
        Err("track 1 has ended".into())
    );
    w.finish().expect("finish");
    assert_eq!(
        w.add_alpha(300, false, &[1], &[2]),
        Err("the file is finished".into())
    );

    // An audio-only layout has no track 1.
    let layout = json!({"duration_ns": SECOND, "audio": audio_layout()});
    let w = Webm::open(&temp_path("alpha-audio"), &layout).expect("open");
    assert_eq!(
        w.add_alpha(0, true, &[1], &[2]),
        Err("track 1 is not in the layout".into())
    );
}
