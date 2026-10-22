//! Black-box tests for a PQ still's HDR10 peak reader (spec §11 HD-20 (b)),
//! `rc_hdr10_still_peak`, through the C FFI exactly as `ReelCore.swift`
//! drives it.
//!
//! The files are built here from the formats' own syntax: a PNG's chunks
//! (W3C PNG third edition, `cLLI` and `mDCV`, CRCs left zero since the
//! reader does not check them) and an ISOBMFF still's boxes (ISO/IEC
//! 23008-12: `ftyp`, then `meta` with `pitm` and `iprp`'s `ipco` and `ipma`).
//! The oracle for every peak is the number written into the file.

mod common;

use framejob_core::ffi_hdr10::rc_hdr10_still_peak;
use serde_json::{json, Value};

use common::{parse_json, take_string};

const PNG_SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];

/// What the FFI reads from `file`, as JSON.
fn peak(file: &[u8]) -> Value {
    let raw = unsafe { rc_hdr10_still_peak(file.as_ptr(), file.len()) };
    parse_json(
        &take_string(raw).expect("rc_hdr10_still_peak returned NULL"),
        "rc_hdr10_still_peak",
    )
}

/// ST 2086 with BT.2020's primaries, D65, `maximum` and a minimum of 50
/// (each luminance in 0.0001 cd/m²).
fn mastering(maximum: u32) -> Vec<u8> {
    let mut out = Vec::new();
    for c in [8500u16, 39850, 6550, 2300, 35400, 14600, 15635, 16450] {
        out.extend(c.to_be_bytes());
    }
    out.extend(maximum.to_be_bytes());
    out.extend(50u32.to_be_bytes());
    out
}

// ---- PNG -------------------------------------------------------------------

fn chunk(kind: &[u8; 4], data: &[u8]) -> Vec<u8> {
    let mut out = u32::try_from(data.len())
        .expect("len")
        .to_be_bytes()
        .to_vec();
    out.extend(kind);
    out.extend(data);
    out.extend([0u8; 4]);
    out
}

/// A PNG's cLLI: MaxCLL then MaxFALL, each a u32 in 0.0001 cd/m².
fn clli_png(max_cll: u32) -> Vec<u8> {
    let mut out = max_cll.to_be_bytes().to_vec();
    out.extend(4_000_000u32.to_be_bytes());
    out
}

/// A 1×1 PNG with `before` between IHDR and IDAT and `after` after IDAT.
fn png(before: &[Vec<u8>], after: &[Vec<u8>]) -> Vec<u8> {
    let mut out = PNG_SIGNATURE.to_vec();
    out.extend(chunk(b"IHDR", &[0, 0, 0, 1, 0, 0, 0, 1, 16, 2, 0, 0, 0]));
    for c in before {
        out.extend(c);
    }
    out.extend(chunk(b"IDAT", &[0x78, 0x9c, 0x63, 0, 0, 0, 1, 0, 1]));
    for c in after {
        out.extend(c);
    }
    out.extend(chunk(b"IEND", &[]));
    out
}

#[test]
fn a_png_s_clli_reads_max_cll() {
    let file = png(&[chunk(b"cLLI", &clli_png(40_000_000))], &[]);
    assert_eq!(peak(&file), json!({"file": 4000, "from": "max_cll"}));
}

#[test]
fn a_png_s_zero_clli_falls_to_its_mdcv() {
    let file = png(
        &[
            chunk(b"cLLI", &clli_png(0)),
            chunk(b"mDCV", &mastering(20_000_000)),
        ],
        &[],
    );
    assert_eq!(
        peak(&file),
        json!({"file": 2000, "from": "mastering_display"})
    );
}

#[test]
fn a_png_s_clli_after_idat_reads_nothing() {
    let file = png(&[], &[chunk(b"cLLI", &clli_png(40_000_000))]);
    assert_eq!(peak(&file), json!({}));
}

#[test]
fn a_png_s_largest_clli_clamps_to_10000() {
    let file = png(&[chunk(b"cLLI", &clli_png(0xFFFF_FFFF))], &[]);
    assert_eq!(peak(&file), json!({"file": 10000, "from": "max_cll"}));
}

// ---- ISOBMFF -----------------------------------------------------------------

fn boxed(kind: &[u8; 4], body: &[u8]) -> Vec<u8> {
    let mut out = u32::try_from(body.len() + 8)
        .expect("len")
        .to_be_bytes()
        .to_vec();
    out.extend(kind);
    out.extend(body);
    out
}

fn full(kind: &[u8; 4], version: u8, flags: u32, body: &[u8]) -> Vec<u8> {
    let mut inner = vec![version];
    inner.extend(&flags.to_be_bytes()[1..]);
    inner.extend(body);
    boxed(kind, &inner)
}

fn ftyp() -> Vec<u8> {
    boxed(b"ftyp", b"avifmif1avifmiaf")
}

fn clli_box(max_cll: u16) -> Vec<u8> {
    let mut out = max_cll.to_be_bytes().to_vec();
    out.extend(400u16.to_be_bytes());
    boxed(b"clli", &out)
}

/// An `ipma` of `version` and `flags`: each entry an item id and its
/// property indices.
fn ipma(version: u8, flags: u32, entries: &[(u32, &[u16])]) -> Vec<u8> {
    let mut body = u32::try_from(entries.len())
        .expect("count")
        .to_be_bytes()
        .to_vec();
    for (item, indices) in entries {
        if version == 0 {
            body.extend(u16::try_from(*item).expect("id").to_be_bytes());
        } else {
            body.extend(item.to_be_bytes());
        }
        body.push(u8::try_from(indices.len()).expect("count"));
        for index in *indices {
            if flags & 1 != 0 {
                body.extend((index | 0x8000).to_be_bytes());
            } else {
                body.push(u8::try_from(*index).expect("index") | 0x80);
            }
        }
    }
    full(b"ipma", version, flags, &body)
}

/// A `meta` body (after its FullBox header) whose primary item is 1, its
/// properties `properties` (1-based) and its associations `ipma`.
fn meta_body(properties: &[Vec<u8>], ipma: Vec<u8>, pitm_version: u8) -> Vec<u8> {
    let pitm_id: Vec<u8> = if pitm_version == 0 {
        1u16.to_be_bytes().to_vec()
    } else {
        1u32.to_be_bytes().to_vec()
    };
    let mut out = full(b"hdlr", 0, 0, b"\0\0\0\0pict\0\0\0\0\0\0\0\0\0\0\0\0\0");
    out.extend(full(b"pitm", pitm_version, 0, &pitm_id));
    let mut ipco = Vec::new();
    for p in properties {
        ipco.extend(p);
    }
    let mut iprp = boxed(b"ipco", &ipco);
    iprp.extend(ipma);
    out.extend(boxed(b"iprp", &iprp));
    out
}

fn heif(meta: Vec<u8>) -> Vec<u8> {
    let mut out = ftyp();
    out.extend(full(b"meta", 0, 0, &meta));
    out.extend(boxed(b"mdat", &[1, 2, 3, 4]));
    out
}

fn ispe() -> Vec<u8> {
    full(b"ispe", 0, 0, &[0, 0, 0, 1, 0, 0, 0, 1])
}

#[test]
fn the_primary_item_s_clli_reads_max_cll() {
    let file = heif(meta_body(
        &[
            ispe(),
            clli_box(600),
            boxed(b"mdcv", &mastering(10_000_000)),
        ],
        ipma(0, 0, &[(1, &[1, 2, 3])]),
        0,
    ));
    assert_eq!(peak(&file), json!({"file": 600, "from": "max_cll"}));
}

#[test]
fn an_mdcv_alone_reads_the_mastering_maximum() {
    let file = heif(meta_body(
        &[ispe(), boxed(b"mdcv", &mastering(20_000_000))],
        ipma(0, 0, &[(1, &[1, 2])]),
        0,
    ));
    assert_eq!(
        peak(&file),
        json!({"file": 2000, "from": "mastering_display"})
    );
}

#[test]
fn a_clli_on_another_item_reads_nothing() {
    let file = heif(meta_body(
        &[ispe(), clli_box(600)],
        ipma(0, 0, &[(1, &[1]), (2, &[1, 2])]),
        0,
    ));
    assert_eq!(peak(&file), json!({}));
}

#[test]
fn ipma_version_1_with_wide_indices_reads() {
    let file = heif(meta_body(
        &[ispe(), clli_box(1600)],
        ipma(1, 1, &[(1, &[1, 2])]),
        1,
    ));
    assert_eq!(peak(&file), json!({"file": 1600, "from": "max_cll"}));
}

#[test]
fn a_meta_with_a_64_bit_size_reads() {
    let body = meta_body(&[ispe(), clli_box(900)], ipma(0, 0, &[(1, &[1, 2])]), 0);
    let mut meta = 1u32.to_be_bytes().to_vec();
    meta.extend(b"meta");
    meta.extend(
        u64::try_from(body.len() + 4 + 16)
            .expect("len")
            .to_be_bytes(),
    );
    meta.extend([0u8; 4]);
    meta.extend(body);
    let mut file = ftyp();
    file.extend(meta);
    assert_eq!(peak(&file), json!({"file": 900, "from": "max_cll"}));
}

#[test]
fn a_meta_of_size_0_runs_to_the_end() {
    let body = meta_body(&[ispe(), clli_box(700)], ipma(0, 0, &[(1, &[1, 2])]), 0);
    let mut file = ftyp();
    file.extend(0u32.to_be_bytes());
    file.extend(b"meta");
    file.extend([0u8; 4]);
    file.extend(body);
    assert_eq!(peak(&file), json!({"file": 700, "from": "max_cll"}));
}

// ---- neither, NULL, and every prefix ----------------------------------------------

#[test]
fn neither_format_and_null_read_nothing() {
    assert_eq!(peak(b"GIF89a not a png at all"), json!({}));
    assert_eq!(peak(&[]), json!({}));
    let raw = unsafe { rc_hdr10_still_peak(std::ptr::null(), 64) };
    assert_eq!(
        parse_json(&take_string(raw).expect("not NULL"), "NULL"),
        json!({})
    );
}

#[test]
fn every_prefix_of_every_file_reads_without_a_panic() {
    let files = [
        png(&[chunk(b"cLLI", &clli_png(40_000_000))], &[]),
        png(&[chunk(b"mDCV", &mastering(20_000_000))], &[]),
        heif(meta_body(
            &[
                ispe(),
                clli_box(600),
                boxed(b"mdcv", &mastering(10_000_000)),
            ],
            ipma(0, 0, &[(1, &[1, 2, 3])]),
            0,
        )),
        heif(meta_body(
            &[ispe(), clli_box(1600)],
            ipma(1, 1, &[(1, &[1, 2])]),
            1,
        )),
    ];
    for file in files {
        for end in 0..=file.len() {
            let read = peak(&file[..end]);
            assert!(read.is_object(), "{end}: {read}");
        }
    }
}
