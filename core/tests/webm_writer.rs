//! Black-box tests for the WebM writer — spec §11 CX-6 and CX-15 (codec-export
//! C3) — driven through `rc_webm_*` exactly as the app's `ExportWebMWriter`
//! drives it, and read back two independent ways:
//!
//! 1. **Through #216-R's reader** (`framejob_core::container::Container`),
//!    the import path a WebM takes into Frame Job: the codecs, the `av1C`
//!    record, the colour and HDR10 blobs, OpusHead, the audio timed from the
//!    CodecDelay, the video retimed onto the grid at five rates, every
//!    payload's bytes and every sync flag.
//! 2. **Through `common/ebml_read.rs`'s walk**, for what that reader skips:
//!    the EBML header, Info's Duration, the track entries' timing fields,
//!    Chapters, Cues against the Clusters, the SeekHead, the Segment's size,
//!    DiscardPadding, the interleave order and the 32,767 ms Cluster limit.
//!
//! The refusals, a video-only layout and two threads adding at once are
//! `webm_writer_refusals.rs`; the helpers both use are `common/webm.rs`.

mod common;

use serde_json::json;

use common::ebml_read::{self, blocks, segment};
use common::webm::*;
use framejob_core::container::{Container, AUDIO, VIDEO};
use framejob_core::time::Fps;

#[test]
fn a_file_reads_back_through_the_216r_reader() {
    let path = temp_path("full");
    write_full(&path);
    let c = Container::open(&path).expect("the reader opens it");
    let d = c.describe();
    assert_eq!(d["doc_type"], json!("webm"));
    let v = &d["video"];
    assert_eq!(v["codec_id"], json!("V_AV1"));
    assert_eq!(v["fourcc"], json!("av01"));
    assert_eq!(v["atom"], json!("av1C"));
    assert_eq!(v["atom_hex"], json!(hex(&AV1C)));
    assert_eq!(
        (v["width"].clone(), v["height"].clone()),
        (json!(640), json!(360))
    );
    assert_eq!(
        (v["transfer"].clone(), v["primaries"].clone()),
        (json!(16), json!(9))
    );
    assert_eq!(v["matrix"], json!(9));
    assert_eq!(v["mdcv_hex"], json!(MDCV));
    assert_eq!(v["clli_hex"], json!(CLLI));
    assert_eq!(v["samples"], json!(60));
    let a = &d["audio"];
    assert_eq!(a["codec_id"], json!("A_OPUS"));
    assert_eq!(a["fourcc"], json!("opus"));
    assert_eq!(a["cookie_hex"], json!(hex(&opus_head())));
    assert_eq!(
        (a["sample_rate"].clone(), a["channels"].clone()),
        (json!(48000), json!(2))
    );
    assert_eq!(a["samples"], json!(100));
}

#[test]
fn audio_is_timed_from_the_codec_delay() {
    let path = temp_path("delay");
    write_full(&path);
    let c = Container::open(&path).expect("open");
    let n = c.sample_count(AUDIO);
    assert_eq!(n, 100);
    for k in 0..n {
        let s = c.sample(AUDIO, k).expect("a sample");
        assert_eq!(s.pts, k as i64 * 960 - i64::from(PRE_SKIP), "packet {k}");
        assert_eq!(s.frames, 960, "packet {k}");
        assert!(s.sync, "packet {k}");
    }
}

#[test]
fn video_retimes_onto_the_grid_at_every_rate() {
    for (num, den) in [(24_000, 1001), (25, 1), (30, 1), (30_000, 1001), (60, 1)] {
        let path = temp_path("grid");
        let layout = json!({"duration_ns": 3 * SECOND, "video": video_layout([num, den], false)});
        let w = Webm::open(&path, &layout).expect("open");
        let count = (3 * num / den) as usize;
        let mut times = Vec::new();
        for k in 0..count {
            let ns = frame_ns(k, num, den);
            times.push(ns);
            w.add(V, ns, k % 48 == 0, 0, &frame(k)).expect("add");
        }
        w.finish().expect("finish");
        let mut c = Container::open(&path).expect("open");
        assert!(c.retime(Fps { num, den }), "{num}/{den} is off the grid");
        assert_eq!(c.describe()["video"]["timescale"], json!(num));
        for k in 0..count {
            let s = c.sample(VIDEO, k as u64).expect("a sample");
            assert_eq!(s.pts, k as i64 * i64::from(den), "{num}/{den} frame {k}");
        }
        // Each block's time is the pts rounded half up to a millisecond.
        let bytes = std::fs::read(&path).expect("read");
        let (_, seg) = segment(&bytes);
        let read: Vec<i64> = blocks(&bytes, &seg).iter().map(|b| b.ms).collect();
        let want: Vec<i64> = times.iter().map(|ns| (ns + 500_000) / 1_000_000).collect();
        assert_eq!(read, want, "{num}/{den}");
    }
}

#[test]
fn payloads_and_sync_flags_are_the_packets() {
    let path = temp_path("payload");
    write_full(&path);
    let bytes = std::fs::read(&path).expect("read");
    let c = Container::open(&path).expect("open");
    for k in 0..60usize {
        let s = c.sample(VIDEO, k as u64).expect("video");
        let at = s.offset as usize;
        assert_eq!(
            &bytes[at..at + s.size as usize],
            frame(k).as_slice(),
            "frame {k}"
        );
        assert_eq!(s.sync, k % 30 == 0, "frame {k}");
    }
    for k in 0..100usize {
        let s = c.sample(AUDIO, k as u64).expect("audio");
        let at = s.offset as usize;
        assert_eq!(
            &bytes[at..at + s.size as usize],
            opus(k).as_slice(),
            "packet {k}"
        );
    }
}

#[test]
fn the_walk_finds_the_header_info_and_track_timing() {
    let path = temp_path("walk-head");
    write_full(&path);
    let b = std::fs::read(&path).expect("read");
    let (top, seg) = segment(&b);
    let ebml = &top[0];
    assert_eq!(find(ebml, 0x4282).string(&b), "webm");
    assert_eq!(find(ebml, 0x4287).uint(&b), 4);
    assert_eq!(find(ebml, 0x4285).uint(&b), 2);
    assert_eq!(
        seg.data + seg.size,
        b.len(),
        "the Segment's size is the rest of the file"
    );
    let info = find(&seg, 0x1549_A966);
    assert_eq!(find(info, 0x2A_D7B1).uint(&b), 1_000_000);
    assert_eq!(find(info, 0x4489).float(&b), 2000.0);
    assert_eq!(find(info, 0x4D80).string(&b), "Frame Job");
    assert_eq!(find(info, 0x5741).string(&b), "Frame Job");
    let entries = find(&seg, 0x1654_AE6B).all(0xAE);
    assert_eq!(entries.len(), 2);
    let (v, a) = (entries[0], entries[1]);
    assert_eq!(find(v, 0x23_E383).uint(&b), 33_333_333);
    let colour = find(find(v, 0xE0), 0x55B0);
    assert_eq!(find(colour, 0x55B9).uint(&b), 1);
    assert_eq!(find(colour, 0x55B2).uint(&b), 10);
    assert_eq!(find(colour, 0x55BC).uint(&b), 1000);
    assert_eq!(find(colour, 0x55BD).uint(&b), 0);
    assert_eq!(find(find(colour, 0x55D0), 0x55D9).float(&b), 1000.0);
    assert_eq!(find(a, 0x56AA).uint(&b), 6_500_000);
    assert_eq!(find(a, 0x56BB).uint(&b), 80_000_000);
    assert_eq!(find(find(a, 0xE1), 0xB5).float(&b), 48_000.0);
}

#[test]
fn the_walk_finds_chapters_cues_and_the_seek_head() {
    let path = temp_path("walk");
    write_full(&path);
    let b = std::fs::read(&path).expect("read");
    let (_, seg) = segment(&b);
    // Chapters: one edition, an atom per chapter.
    let edition = find(find(&seg, 0x1043_A770), 0x45B9);
    assert_eq!(find(edition, 0x45BC).uint(&b), 1);
    let atoms = edition.all(0xB6);
    let want = [(0, SECOND, "Intro"), (SECOND, 2 * SECOND, "Body")];
    assert_eq!(atoms.len(), 2);
    for (i, (atom, (start, end, name))) in atoms.iter().zip(want).enumerate() {
        assert_eq!(find(atom, 0x73C4).uint(&b), i as u64 + 1);
        assert_eq!(find(atom, 0x91).uint(&b), start as u64);
        assert_eq!(find(atom, 0x92).uint(&b), end as u64);
        let display = find(atom, 0x80);
        assert_eq!(find(display, 0x85).string(&b), name);
        assert_eq!(find(display, 0x437C).string(&b), "und");
    }
    // Cues: one per key-started Cluster, at its time and position.
    let read = blocks(&b, &seg);
    let mut key_clusters = Vec::new();
    for cluster in seg.all(0x1F43_B675) {
        let first = read
            .iter()
            .find(|r| r.cluster_start == cluster.start)
            .expect("a block");
        if first.track == 1 && first.flags & 0x80 != 0 {
            key_clusters.push((first.ms as u64, (cluster.start - seg.data) as u64));
        }
    }
    let cues: Vec<(u64, u64)> = find(&seg, 0x1C53_BB6B)
        .all(0xBB)
        .iter()
        .map(|p| {
            let pos = find(p, 0xB7);
            assert_eq!(find(pos, 0xF7).uint(&b), 1);
            (find(p, 0xB3).uint(&b), find(pos, 0xF1).uint(&b))
        })
        .collect();
    assert_eq!(
        cues,
        vec![(0, key_clusters[0].1), (1000, key_clusters[1].1)]
    );
    assert_eq!(cues, key_clusters);
    // Every video key starts its Cluster.
    for r in read.iter().filter(|r| r.track == 1 && r.flags & 0x80 != 0) {
        let first = read
            .iter()
            .find(|x| x.cluster_start == r.cluster_start)
            .expect("first");
        assert!(
            std::ptr::eq(first, r),
            "the key at {} ms does not start its Cluster",
            r.ms
        );
    }
    // The SeekHead is the Segment's first child, and each entry resolves.
    let head = &seg.children[0];
    assert_eq!(head.id, 0x114D_9B74);
    let mut ids = Vec::new();
    for seek in head.all(0x4DBB) {
        let id = find(seek, 0x53AB).uint(&b) as u32;
        let at = seg.data + find(seek, 0x53AC).uint(&b) as usize;
        let target = seg
            .children
            .iter()
            .find(|e| e.start == at)
            .expect("an element there");
        assert_eq!(target.id, id, "the seek to {id:#x}");
        ids.push(id);
    }
    assert_eq!(ids, [0x1549_A966, 0x1654_AE6B, 0x1043_A770, 0x1C53_BB6B]);
}

#[test]
fn blocks_interleave_in_time_and_the_tail_carries_its_discard_padding() {
    let path = temp_path("order");
    write_full(&path);
    let b = std::fs::read(&path).expect("read");
    let (_, seg) = segment(&b);
    let read = blocks(&b, &seg);
    assert_eq!(read.len(), 160);
    for pair in read.windows(2) {
        let (x, y) = (&pair[0], &pair[1]);
        assert!(x.ms <= y.ms, "{} ms before {} ms", x.ms, y.ms);
        if x.ms == y.ms {
            assert!(x.track <= y.track, "audio before video at {} ms", x.ms);
        }
    }
    let audio: Vec<&ebml_read::BlockRead> = read.iter().filter(|r| r.track == 2).collect();
    for (k, r) in audio.iter().enumerate() {
        if k == 99 {
            assert_eq!(r.discard, Some(5_000_000));
        } else {
            assert_eq!((r.discard, r.flags), (None, 0x80), "packet {k}");
        }
    }
}

#[test]
fn a_cluster_starts_before_its_relative_time_passes_32767_ms() {
    let path = temp_path("long");
    let layout = json!({"duration_ns": 40 * SECOND, "video": video_layout([1, 1], false)});
    let w = Webm::open(&path, &layout).expect("open");
    for k in 0..40usize {
        w.add(V, k as i64 * SECOND, k == 0, 0, &frame(k))
            .expect("add");
    }
    w.finish().expect("finish");
    let b = std::fs::read(&path).expect("read");
    let (_, seg) = segment(&b);
    let clusters = seg.all(0x1F43_B675);
    let times: Vec<u64> = clusters.iter().map(|c| find(c, 0xE7).uint(&b)).collect();
    assert_eq!(times, vec![0, 33_000]);
    assert_eq!(
        find(&seg, 0x1C53_BB6B).all(0xBB).len(),
        1,
        "only the key-started one"
    );
}
