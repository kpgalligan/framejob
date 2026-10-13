//! A WebM or Matroska file's Vorbis sound, copied (spec §11 #228-V), black
//! box over `rc_container_*`: two real encoders' files, whose packet counts
//! ffmpeg's own Vorbis parser read (`fixtures/vorbis/PROVENANCE.md`), and
//! files built by `common/ebml.rs` around headers `common/vorbis.rs` wrote —
//! every setup section, the overlap rule, the lead, a lace, the
//! identification header's rate and channels, an encoded track, packet
//! edges and hostile bytes. The refusals are `container_vorbis_headers.rs`.

mod common;

use serde_json::Value;

use common::ebml::{cluster, file, info, simple_block, tracks, write_temp, Lacing, Track};
use common::vorbis::{codec_private, comment, packet, private, Ident};
use common::vorbis_setup::{Class, Codebook, Floor, Lengths, Mapping, Mode, Residue, Setup};
use framejob_core::container::{Container, AUDIO};

const FFMPEG: &[u8] = include_bytes!("fixtures/vorbis/ffmpeg.webm");
const LIBVORBIS: &[u8] = include_bytes!("fixtures/vorbis/libvorbis.webm");
const EXPECTED: &str = include_str!("fixtures/vorbis/expected.json");

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Opens a real fixture and holds it to `expected.json`: ffmpeg's packet
/// counts but the last (whose count the Ogg granule trims), and each packet
/// at its Block's time × 48 plus packet 0's count, the lead.
fn real(name: &str, bytes: &[u8]) -> Vec<u32> {
    let expected: Value = serde_json::from_str(EXPECTED).expect("expected.json");
    let e = &expected[name];
    let c = common::ebml::open(name, bytes).expect(name);
    let a = &c.describe()["audio"];
    assert_eq!(a["codec_id"], "A_VORBIS");
    assert_eq!(a["fourcc"], "vorb", "{name}");
    assert_eq!(a["frames_per_packet"], 0);
    assert_eq!(a["sample_rate"], 48_000);
    assert_eq!(a["timescale"], 48_000);
    assert_eq!(a["channels"], 2);
    assert_eq!(a["cookie_hex"], Value::String(hex(&codec_private(bytes))));
    let samples = c.samples(AUDIO);
    assert_eq!(Some(samples.len() as u64), e["packets"].as_u64(), "{name}");
    let counts: Vec<u32> = samples.iter().map(|s| s.frames).collect();
    let but_last: Vec<u32> = e["counts_but_last"]
        .as_array()
        .expect("counts")
        .iter()
        .map(|n| n.as_u64().expect("a count") as u32)
        .collect();
    assert_eq!(counts[..counts.len() - 1], but_last[..], "{name}");
    let lead = i64::from(counts[0]);
    let pts: Vec<i64> = samples.iter().map(|s| s.pts).collect();
    let want: Vec<i64> = e["block_ms"]
        .as_array()
        .expect("block times")
        .iter()
        .map(|ms| ms.as_i64().expect("ms") * 48 + lead)
        .collect();
    assert_eq!(pts, want, "{name}");
    assert!(samples.iter().all(|s| s.sync && s.dts == s.pts));
    let durations: Vec<i64> = samples.iter().map(|s| s.duration).collect();
    let as_counts: Vec<i64> = counts.iter().map(|n| i64::from(*n)).collect();
    assert_eq!(durations, as_counts, "a packet lasts its count");
    counts
}

#[test]
fn ffmpegs_vorbis_is_copied_with_ffmpegs_own_counts() {
    let counts = real("ffmpeg.webm", FFMPEG);
    // ffmpeg's encoder uses 2048-sample blocks only: 512 + 512 each.
    assert_eq!(counts[0], 1024);
}

#[test]
fn libvorbis_is_copied_with_its_mixed_blocks_counted() {
    let counts = real("libvorbis.webm", LIBVORBIS);
    // 256/2048 blocks: short-short 128, short-long 576, long-long 1024, and
    // packet 0 a short block, 64 + 64.
    assert_eq!(counts[0], 128);
    for n in [128, 576, 1024] {
        assert!(counts.contains(&n), "{n}");
    }
}

/// A WebM of one Vorbis track (TrackEntry 44.1 kHz stereo) with `private`,
/// one Block per packet at `rel` ms in one Cluster at 0.
fn vorbis_file(private: Vec<u8>, packets: &[(i16, Vec<u8>)], encoded: bool) -> Vec<u8> {
    let mut t = Track::audio(1, "A_VORBIS", 44_100.0);
    t.private = private;
    t.encoded = encoded;
    let blocks: Vec<Vec<u8>> = packets
        .iter()
        .map(|(rel, p)| simple_block(1, *rel, true, Lacing::None, std::slice::from_ref(p)))
        .collect();
    let body = vec![info(1_000_000), tracks(&[t]), cluster(0, &blocks)];
    file("webm", &body, false)
}

/// Six channels, every setup section in more than one form: codebooks
/// dense, ordered and sparse with lookups 0, 1 and 2; floor 0 and floor 1
/// with subclasses; residues 0, 1 and 2 with cascade high bits; a mapping
/// with coupling and three submaps; three modes, 2 mode bits.
fn rich_setup() -> Setup {
    let class = |dimensions, subclasses, masterbook, books: Vec<i32>| Class {
        dimensions,
        subclasses,
        masterbook,
        books,
    };
    Setup {
        codebooks: vec![
            Codebook::plain(),
            // 8 entries in runs of 2, 0 and 6; lookup1_values(8, 2) = 2.
            Codebook {
                dimensions: 2,
                entries: 8,
                lengths: Lengths::Ordered(2, vec![2, 0, 6]),
                lookup: 1,
                value_bits: 3,
                ..Codebook::plain()
            },
            // Five entries, two unused; 5 × 3 values.
            Codebook {
                dimensions: 3,
                entries: 5,
                lengths: Lengths::Sparse(vec![Some(3), None, Some(4), None, Some(2)]),
                lookup: 2,
                value_bits: 4,
                ..Codebook::plain()
            },
            Codebook {
                entries: 4,
                lengths: Lengths::Dense(vec![2, 2, 2, 2]),
                lookup: 1,
                value_bits: 5,
                ..Codebook::plain()
            },
        ],
        times: vec![0],
        floors: vec![
            Floor::Zero(vec![0, 1]),
            Floor::One(
                vec![0, 1, 1],
                vec![class(2, 0, 0, vec![-1]), class(3, 2, 3, vec![-1, 0, 1, 2])],
                7,
            ),
        ],
        residues: vec![
            Residue {
                book: 1,
                ..Residue::plain(0)
            },
            Residue {
                kind: 1,
                classbook: 1,
                cascades: vec![0x09, 0xFF],
                book: 2,
            },
            Residue {
                kind: 2,
                classbook: 2,
                cascades: vec![0x45],
                book: 3,
            },
        ],
        mappings: vec![
            Mapping {
                coupling: vec![(0, 2), (1, 2), (3, 4)],
                mux: vec![0, 1, 2, 0, 1, 2],
                submaps: vec![(0, 0), (1, 1), (1, 2)],
                ..Mapping::plain()
            },
            Mapping {
                submaps: vec![(1, 2)],
                ..Mapping::plain()
            },
        ],
        modes: vec![
            Mode::new(false),
            Mode {
                mapping: 1,
                ..Mode::new(true)
            },
            Mode::new(true),
        ],
        framing: true,
    }
}

#[test]
fn every_setup_section_is_walked_to_the_mode_table() {
    let ident = Ident::new(6, 48_000);
    let head = private(&ident.bytes(), &comment(), &rich_setup().bytes(6));
    // Modes 1, 0, 2, 2, 0, 0, 1 in 2 bits: blocks 2048, 256, 2048, 2048,
    // 256, 256, 2048 (exponents 8 and 11).
    let modes = [1, 0, 2, 2, 0, 0, 1];
    let rels = [0i16, 5, 9, 30, 52, 57, 60];
    let packets: Vec<(i16, Vec<u8>)> = modes
        .iter()
        .zip(rels)
        .map(|(m, rel)| (rel, packet(*m, 2, 20)))
        .collect();
    let c = common::ebml::open("rich.webm", &vorbis_file(head.clone(), &packets, false))
        .expect("opens");
    let a = &c.describe()["audio"];
    assert_eq!(a["fourcc"], "vorb");
    assert_eq!(a["cookie_hex"], Value::String(hex(&head)));
    // n0 = 256/4 + 2048/4 = 576; then prev/4 + cur/4: 512 + 64, 64 + 512,
    // 512 + 512, 512 + 64, 64 + 64, 64 + 512.
    let counts = [576, 576, 576, 1024, 576, 128, 576];
    let samples = c.samples(AUDIO);
    assert_eq!(samples.iter().map(|s| s.frames).collect::<Vec<_>>(), counts);
    // Each Block's ms × 48, then 576 later.
    let pts: Vec<i64> = rels.iter().map(|r| i64::from(*r) * 48 + 576).collect();
    assert_eq!(samples.iter().map(|s| s.pts).collect::<Vec<_>>(), pts);
}

#[test]
fn the_identification_header_sets_the_rate_and_the_channels() {
    // The TrackEntry says 44.1 kHz stereo; the header says 32 kHz, six.
    let ident = Ident::new(6, 32_000);
    let head = private(&ident.bytes(), &comment(), &rich_setup().bytes(6));
    let bytes = vorbis_file(head, &[(0, packet(0, 2, 9)), (10, packet(0, 2, 9))], false);
    let c = common::ebml::open("rate.webm", &bytes).expect("opens");
    let a = &c.describe()["audio"];
    assert_eq!(
        (&a["sample_rate"], &a["timescale"], &a["channels"]),
        (&Value::from(32_000), &Value::from(32_000), &Value::from(6))
    );
    // Short blocks only: 64 + 64 = 128 each; 10 ms at 32 kHz is 320.
    let pts: Vec<i64> = c.samples(AUDIO).iter().map(|s| s.pts).collect();
    assert_eq!(pts, [128, 320 + 128]);
}

#[test]
fn a_laced_block_places_each_packet_after_the_ones_before_it() {
    // Two modes, 1 bit: mode 0 short (256), mode 1 long (2048).
    let ident = Ident::new(2, 48_000);
    let head = private(
        &ident.bytes(),
        &comment(),
        &Setup::plain(&[false, true]).bytes(2),
    );
    let mut t = Track::audio(1, "A_VORBIS", 48_000.0);
    t.private = head;
    let lace = vec![packet(1, 1, 30), packet(1, 1, 31), packet(0, 1, 32)];
    let body = vec![
        info(1_000_000),
        tracks(&[t]),
        cluster(
            0,
            &[
                simple_block(1, 10, true, Lacing::Xiph, &lace),
                simple_block(1, 30, true, Lacing::None, &[packet(0, 1, 12)]),
            ],
        ),
    ];
    let c = common::ebml::open("laced.webm", &file("webm", &body, false)).expect("opens");
    let s = c.samples(AUDIO);
    // Counts: 64 + 512 = 576, 512 + 512 = 1024, 512 + 64 = 576, 64 + 64.
    assert_eq!(
        s.iter().map(|s| s.frames).collect::<Vec<_>>(),
        [576, 1024, 576, 128]
    );
    // 10 ms = 480; the lace adds 0, 576, 576 + 1024; 30 ms = 1440; all +576.
    assert_eq!(
        s.iter().map(|s| s.pts).collect::<Vec<_>>(),
        [1056, 1632, 2656, 2016]
    );
}

#[test]
fn a_packet_whose_mode_cannot_be_read_counts_as_a_short_block() {
    // Three modes (2 bits): 0 short, 1 and 2 long; mode 3 is past the table.
    let ident = Ident::new(2, 48_000);
    let setup = Setup::plain(&[false, true, true]);
    let head = private(&ident.bytes(), &comment(), &setup.bytes(2));
    let not_audio = vec![0x03, 0x10, 0x20]; // packet type bit 1
    let mut t = Track::audio(1, "A_VORBIS", 48_000.0);
    t.private = head;
    let body = vec![
        info(1_000_000),
        tracks(&[t]),
        cluster(
            0,
            &[
                simple_block(1, 0, true, Lacing::None, &[packet(1, 2, 10)]),
                simple_block(1, 20, true, Lacing::None, &[not_audio]),
                simple_block(1, 25, true, Lacing::None, &[packet(2, 2, 10)]),
                simple_block(1, 40, true, Lacing::None, &[packet(3, 2, 10)]),
                // An empty packet is no frame: the index keeps none of a
                // zero-byte lace frame, so the next packet follows mode 1.
                simple_block(1, 50, true, Lacing::Xiph, &[Vec::new(), packet(1, 2, 8)]),
            ],
        ),
    ];
    let c = common::ebml::open("edges.webm", &file("webm", &body, false)).expect("opens");
    // Blocks: 2048, short (not audio), 2048, short (mode 3), 2048.
    // n0 = 64 + 512; 512 + 64; 64 + 512; 512 + 64; 64 + 512.
    let counts: Vec<u32> = c.samples(AUDIO).iter().map(|s| s.frames).collect();
    assert_eq!(counts, [576, 576, 576, 576, 576]);
}

#[test]
fn an_encoded_vorbis_track_is_described_and_not_copied() {
    let ident = Ident::new(2, 48_000);
    let head = private(&ident.bytes(), &comment(), &Setup::plain(&[false]).bytes(2));
    let bytes = vorbis_file(head, &[(0, packet(0, 0, 10))], true);
    let c = common::ebml::open("encoded.webm", &bytes).expect("opens");
    let a = &c.describe()["audio"];
    assert_eq!(
        (a["fourcc"].as_str(), a["encoded"].as_bool()),
        (Some("vorb"), Some(true))
    );
    assert_eq!(a["samples"], 0);
    assert!(c.samples(AUDIO).is_empty());
}

/// A xorshift: the hostile-byte sweep is deterministic.
fn next(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}

#[test]
fn hostile_vorbis_bytes_never_panic() {
    let ident = Ident::new(6, 48_000);
    let head = private(&ident.bytes(), &comment(), &rich_setup().bytes(6));
    let packets: Vec<(i16, Vec<u8>)> = (0..12)
        .map(|i| (i * 5, packet(i as u32 % 3, 2, 16)))
        .collect();
    let bytes = vorbis_file(head.clone(), &packets, false);
    // Only the CodecPrivate and what follows it — the packets — are hit.
    let from = bytes
        .windows(head.len())
        .position(|w| w == head.as_slice())
        .expect("the CodecPrivate");
    let path = write_temp("hostile-vorbis.webm", &bytes);
    let mut state = 0x2545_F491_4F6C_DD1Du64;
    for round in 0..3000 {
        let mut mutated = bytes.clone();
        let edits = 1 + (next(&mut state) % 8) as usize;
        for _ in 0..edits {
            let at = from + (next(&mut state) as usize) % (mutated.len() - from);
            mutated[at] = match round % 3 {
                0 => next(&mut state) as u8,
                1 => 0xFF,
                _ => 0x00,
            };
        }
        std::fs::write(&path, &mutated).expect("rewrite");
        // Called directly, so a panic fails the test rather than being
        // caught by the FFI's guard.
        if let Ok(c) = Container::open(&path) {
            let _ = c.describe();
            for i in 0..c.sample_count(AUDIO) {
                let s = c.sample(AUDIO, i).expect("every counted sample reads");
                assert!(s.frames > 0);
                assert!(s.offset + u64::from(s.size) <= mutated.len() as u64);
            }
        }
    }
    let _ = std::fs::remove_file(&path);
}
