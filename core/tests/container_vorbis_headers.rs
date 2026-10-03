//! A Vorbis track whose headers cannot be read is not copied (spec §11
//! #228-V): it is described with no fourcc and no samples, its codec ID
//! kept, so the app refuses it in #216-R's sentence and the opt-in ffmpeg
//! step may take it. Black box over `rc_container_*`, each header written
//! by `common/vorbis.rs` with one thing broken, and every strict prefix of a
//! real encoder's setup header.

mod common;

use std::time::{Duration, Instant};

use common::ebml::{cluster, file, info, simple_block, tracks, Lacing, Track};
use common::vorbis::{codec_private, comment, packet, packets, private, Ident};
use common::vorbis_setup::{Codebook, Floor, Lengths, Mapping, Mode, Residue, Setup};
use reelcut_core::container::AUDIO;

const LIBVORBIS: &[u8] = include_bytes!("fixtures/vorbis/libvorbis.webm");

/// A WebM of one Vorbis track carrying `private` and three packets.
fn webm(private: &[u8]) -> Vec<u8> {
    let mut t = Track::audio(1, "A_VORBIS", 48_000.0);
    t.private = private.to_vec();
    let blocks: Vec<Vec<u8>> = (0..3)
        .map(|i| simple_block(1, i * 20, true, Lacing::None, &[packet(0, 0, 12)]))
        .collect();
    file(
        "webm",
        &[info(1_000_000), tracks(&[t]), cluster(0, &blocks)],
        false,
    )
}

/// Asserts the track with `private` is described and not copied, and that
/// opening it took under a second.
fn refused(name: &str, private: &[u8]) {
    let started = Instant::now();
    let c = common::ebml::open(name, &webm(private)).expect(name);
    assert!(
        started.elapsed() < Duration::from_secs(1),
        "{name} took {:?}",
        started.elapsed()
    );
    let a = &c.describe()["audio"];
    assert_eq!(a["codec_id"], "A_VORBIS", "{name}");
    assert!(a["fourcc"].is_null(), "{name}: {}", a["fourcc"]);
    assert_eq!(a["samples"], 0, "{name}");
    assert!(c.samples(AUDIO).is_empty(), "{name}");
}

fn ident() -> Ident {
    Ident::new(2, 48_000)
}

/// A whole CodecPrivate from an identification header and a setup.
fn with(ident: &Ident, setup: &Setup) -> Vec<u8> {
    private(&ident.bytes(), &comment(), &setup.bytes(ident.channels))
}

fn plain() -> Setup {
    Setup::plain(&[false, true])
}

#[test]
fn the_plain_headers_this_file_breaks_are_copied() {
    let c = common::ebml::open("plain.webm", &webm(&with(&ident(), &plain()))).expect("opens");
    assert_eq!(c.describe()["audio"]["fourcc"], "vorb");
    assert_eq!(c.samples(AUDIO).len(), 3);
}

#[test]
fn a_damaged_split_or_identification_header_is_refused() {
    let good = with(&ident(), &plain());
    let mut count = good.clone();
    count[0] = 1;
    refused("lacing-count", &count);
    // A first lacing size past the end.
    refused("lacing-size", &[2, 255, 255, 255, 1]);
    let mut magic = good.clone();
    magic[4] = b'V'; // "vorbis" → "Vorbis" in the identification header
    refused("ident-magic", &magic);
    for (name, damage) in [
        (
            "version",
            Ident {
                version: 1,
                ..ident()
            },
        ),
        (
            "no-channels",
            Ident {
                channels: 0,
                ..ident()
            },
        ),
        ("rate-zero", Ident { rate: 0, ..ident() }),
        (
            "rate-max",
            Ident {
                rate: 0xFFFF_FFFF,
                ..ident()
            },
        ),
        (
            "rate-past-cap",
            Ident {
                rate: 10_000_001,
                ..ident()
            },
        ),
        (
            "exp-low",
            Ident {
                exps: (5, 11),
                ..ident()
            },
        ),
        (
            "exp-high",
            Ident {
                exps: (8, 14),
                ..ident()
            },
        ),
        (
            "exp-reversed",
            Ident {
                exps: (11, 8),
                ..ident()
            },
        ),
        (
            "ident-framing",
            Ident {
                framing: false,
                ..ident()
            },
        ),
    ] {
        refused(name, &with(&damage, &plain()));
    }
    // The comment header's and the setup header's magic.
    let mut comment_magic = comment();
    comment_magic[0] = 4;
    refused(
        "comment-magic",
        &private(&ident().bytes(), &comment_magic, &plain().bytes(2)),
    );
    let mut setup_magic = plain().bytes(2);
    setup_magic[6] = b'z';
    refused(
        "setup-magic",
        &private(&ident().bytes(), &comment(), &setup_magic),
    );
}

#[test]
fn a_damaged_codebook_is_refused() {
    let book = |c: Codebook| Setup {
        codebooks: vec![c],
        ..plain()
    };
    let cases = [
        (
            "sync",
            Codebook {
                sync: 0x56_4343,
                ..Codebook::plain()
            },
        ),
        (
            "lookup-3",
            Codebook {
                lookup: 3,
                ..Codebook::plain()
            },
        ),
        // Dimensions 0 makes every r a root of `entries`: refused at once.
        (
            "dims-0-lookup-1",
            Codebook {
                dimensions: 0,
                lookup: 1,
                ..Codebook::plain()
            },
        ),
        (
            "dims-0-lookup-2",
            Codebook {
                dimensions: 0,
                lookup: 2,
                ..Codebook::plain()
            },
        ),
        // Runs of 3 then 3 over 5 entries pass the end.
        (
            "ordered-past",
            Codebook {
                entries: 5,
                lengths: Lengths::Ordered(1, vec![3, 3]),
                ..Codebook::plain()
            },
        ),
        // 2^24 − 1 entries claimed, two listed: the bits run out.
        (
            "dense-claim",
            Codebook {
                entries: 0xFF_FFFF,
                ..Codebook::plain()
            },
        ),
        (
            "sparse-claim",
            Codebook {
                entries: 0xFF_FFFF,
                lengths: Lengths::Sparse(vec![Some(1), None]),
                ..Codebook::plain()
            },
        ),
    ];
    for (name, c) in cases {
        refused(name, &with(&ident(), &book(c)));
    }
}

#[test]
fn a_damaged_time_floor_residue_mapping_or_mode_is_refused() {
    let cases = [
        (
            "time",
            Setup {
                times: vec![0, 3],
                ..plain()
            },
        ),
        (
            "floor-2",
            Setup {
                floors: vec![Floor::Other(2)],
                ..plain()
            },
        ),
        (
            "floor-book",
            Setup {
                floors: vec![Floor::Zero(vec![1])],
                ..plain()
            },
        ),
        (
            "residue-3",
            Setup {
                residues: vec![Residue::plain(3)],
                ..plain()
            },
        ),
        (
            "residue-book",
            Setup {
                residues: vec![Residue {
                    book: 4,
                    ..Residue::plain(1)
                }],
                ..plain()
            },
        ),
        (
            "mapping-1",
            Setup {
                mappings: vec![Mapping {
                    kind: 1,
                    ..Mapping::plain()
                }],
                ..plain()
            },
        ),
        (
            "mapping-reserved",
            Setup {
                mappings: vec![Mapping {
                    reserved: 2,
                    ..Mapping::plain()
                }],
                ..plain()
            },
        ),
        (
            "coupling-same",
            Setup {
                mappings: vec![Mapping {
                    coupling: vec![(1, 1)],
                    ..Mapping::plain()
                }],
                ..plain()
            },
        ),
        (
            "mux",
            Setup {
                mappings: vec![Mapping {
                    mux: vec![0, 2],
                    submaps: vec![(0, 0), (0, 0)],
                    ..Mapping::plain()
                }],
                ..plain()
            },
        ),
        (
            "submap-floor",
            Setup {
                mappings: vec![Mapping {
                    submaps: vec![(1, 0)],
                    ..Mapping::plain()
                }],
                ..plain()
            },
        ),
        (
            "window",
            Setup {
                modes: vec![Mode {
                    window: 1,
                    ..Mode::new(false)
                }],
                ..plain()
            },
        ),
        (
            "transform",
            Setup {
                modes: vec![Mode {
                    transform: 1,
                    ..Mode::new(false)
                }],
                ..plain()
            },
        ),
        (
            "mode-mapping",
            Setup {
                modes: vec![Mode {
                    mapping: 1,
                    ..Mode::new(true)
                }],
                ..plain()
            },
        ),
        (
            "setup-framing",
            Setup {
                framing: false,
                ..plain()
            },
        ),
    ];
    for (name, setup) in cases {
        refused(name, &with(&ident(), &setup));
    }
}

#[test]
fn every_strict_prefix_of_a_real_setup_header_is_refused() {
    let [ident, comment, setup] = packets(&codec_private(LIBVORBIS));
    let whole = private(&ident, &comment, &setup);
    let c = common::ebml::open("whole.webm", &webm(&whole)).expect("opens");
    assert_eq!(
        c.describe()["audio"]["fourcc"],
        "vorb",
        "the whole one reads"
    );
    for cut in 0..setup.len() {
        refused("prefix.webm", &private(&ident, &comment, &setup[..cut]));
    }
}
