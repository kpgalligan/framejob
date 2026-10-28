//! Black-box tests for AV1 in MP4's container bytes (spec §11 CX-12 (4)):
//! `rc_av1_config`, `rc_av1_strip_temporal_delimiters` and
//! `rc_av1_ftyp_brand`, through the C FFI exactly as `ReelCore.swift`'s
//! `ReelAV1` drives them.
//!
//! The oracles are independent of the parser: the codec spike's `av1C`
//! records, which its `av1c.py` built and AVFoundation and ffmpeg both read
//! (`tools/proof/work/codec-spike/probe/mux/aom8.av1c`, `aom10hlg.av1c`);
//! an SVT-AV1 v4.2.0 sequence header taken from the spike's
//! `out/gh5-svt-6-8b-1667k-r1.ivf`, whose fields ffmpeg's `trace_headers`
//! printed (profile 0, level 8, tier 0, 8-bit, no colour description,
//! chroma position 0; `frame_height_bits_minus_1` at payload bit 39); and a
//! header built here bit by bit with timing info, a decoder model and two
//! operating points, so every optional branch before `color_config` is
//! walked.

mod common;

use std::ffi::c_char;
use std::ptr;

use framejob_core::ffi_av1::{rc_av1_config, rc_av1_ftyp_brand, rc_av1_strip_temporal_delimiters};
use serde_json::{json, Value};

use common::{parse_json, take_string};

/// The spike's 8-bit libaom record: `81080c00`, then the sequence header OBU.
const AOM8: &str = "81080c000a0b00000042abbfc3776be401";
/// The spike's 10-bit HLG libaom record (BT.2020, HLG, BT.2020 NCL).
const AOM10_HLG: &str = "81084c000a0e00000042abbfc3776be542448241";
/// SVT-AV1's sequence header OBU (with its size field), 1920 × 1080 preset 6.
const SVT_HEADER: &str = "0a0c02000042955dfe1b8d5f3008";

fn bytes(hex: &str) -> Vec<u8> {
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).expect("hex"))
        .collect()
}

/// `rc_av1_config` over `obus`: the JSON, or the message.
fn config(obus: &[u8]) -> Result<Value, String> {
    let mut err: *mut c_char = ptr::null_mut();
    let raw = unsafe { rc_av1_config(obus.as_ptr(), obus.len(), &mut err) };
    match take_string(raw) {
        Some(text) => {
            assert!(err.is_null(), "an answer and a message both");
            Ok(parse_json(&text, "rc_av1_config"))
        }
        None => Err(take_string(err).expect("NULL with no message")),
    }
}

fn strip(packet: &mut [u8]) -> usize {
    unsafe { rc_av1_strip_temporal_delimiters(packet.as_mut_ptr(), packet.len()) }
}

fn brand(head: &mut [u8]) -> i32 {
    unsafe { rc_av1_ftyp_brand(head.as_mut_ptr(), head.len()) }
}

/// A temporal delimiter OBU with its (zero) size.
const TD: &str = "1200";
/// A frame OBU (type 6) of three bytes.
const FRAME: &str = "3203aabbcc";

#[test]
fn the_spikes_records_are_rebuilt_from_their_own_obus() {
    for (record, depth, color) in [
        (
            AOM8,
            8,
            json!({"primaries": 2, "transfer": 2, "matrix": 2, "full_range": false}),
        ),
        (
            AOM10_HLG,
            10,
            json!({"primaries": 9, "transfer": 18, "matrix": 9, "full_range": false}),
        ),
    ] {
        let obu = bytes(&record[8..]);
        let out = config(&obu).unwrap_or_else(|m| panic!("{record}: {m}"));
        assert_eq!(out["av1c_hex"], json!(record), "{record}");
        assert_eq!(out["seq_profile"], json!(0));
        assert_eq!(out["seq_level_idx"], json!(8));
        assert_eq!(out["seq_tier"], json!(0));
        assert_eq!(out["bit_depth"], json!(depth));
        assert_eq!(out["monochrome"], json!(false));
        assert_eq!(out["color"], color, "{record}");
    }
}

#[test]
fn svts_sequence_header_after_a_temporal_delimiter() {
    let mut obus = bytes(TD);
    obus.extend(bytes(SVT_HEADER));
    obus.extend(bytes(FRAME));
    let out = config(&obus).expect("SVT's header parses");
    assert_eq!(
        out,
        json!({
            "av1c_hex": format!("81080c00{SVT_HEADER}"),
            "seq_profile": 0,
            "seq_level_idx": 8,
            "seq_tier": 0,
            "bit_depth": 8,
            "monochrome": false,
            "color": {"primaries": 2, "transfer": 2, "matrix": 2, "full_range": false}
        })
    );
}

/// Big-endian bits, for a header built field by field.
#[derive(Default)]
struct Writer {
    bits: Vec<bool>,
}

impl Writer {
    fn f(&mut self, n: u32, value: u64) -> &mut Self {
        for i in (0..n).rev() {
            self.bits.push((value >> i) & 1 == 1);
        }
        self
    }

    fn bytes(&self) -> Vec<u8> {
        self.bits
            .chunks(8)
            .map(|c| {
                c.iter()
                    .enumerate()
                    .fold(0u8, |b, (i, on)| b | (u8::from(*on) << (7 - i)))
            })
            .collect()
    }
}

/// A sequence header with timing info, a decoder model, two operating
/// points (the first at level 13, tier 1), frame ids, forced screen-content
/// tools, 10 bits, BT.709 full range and chroma position 1.
fn full_header() -> Vec<u8> {
    let mut w = Writer::default();
    w.f(3, 0).f(1, 0).f(1, 0); // profile, still, reduced
    w.f(1, 1).f(32, 1001).f(32, 30000).f(1, 1).f(1, 1); // timing, uvlc 0
    w.f(1, 1).f(5, 9).f(32, 1).f(5, 4).f(5, 4); // decoder model, delay 10 bits
    w.f(1, 1).f(5, 1); // initial display delay, two operating points
    w.f(12, 0x103).f(5, 13).f(1, 1); // op 0: level 13, tier 1
    w.f(1, 1).f(10, 500).f(10, 300).f(1, 0); // its decoder model
    w.f(1, 1).f(4, 3); // its display delay
    w.f(12, 0x101).f(5, 5).f(1, 0).f(1, 0); // op 1: level 5, no tier, none
    w.f(4, 10).f(4, 10).f(11, 1919).f(11, 1079); // frame size
    w.f(1, 1).f(4, 5).f(3, 2); // frame ids
    w.f(1, 0).f(1, 0).f(1, 1); // 128 sb, filter intra, intra edge
    w.f(1, 0).f(1, 0).f(1, 0).f(1, 0).f(1, 1).f(1, 0).f(1, 1); // tools, order hint
    w.f(1, 0).f(1, 1).f(1, 0).f(1, 0).f(3, 6); // screen content, integer mv, hint bits
    w.f(1, 0).f(1, 1).f(1, 1); // superres, cdef, restoration
    w.f(1, 1).f(1, 0).f(1, 1).f(8, 1).f(8, 1).f(8, 1); // 10-bit, colour 1/1/1
    w.f(1, 1).f(2, 1).f(1, 0).f(1, 0).f(1, 1); // full range, csp 1, uv, grain, trailing
    w.bytes()
}

#[test]
fn a_header_with_every_optional_branch_is_walked() {
    let payload = full_header();
    // No size field: the record re-emits the OBU with one.
    let mut obu = vec![0x08];
    obu.extend(&payload);
    let out = config(&obu).expect("the full header parses");
    let mut record = bytes("810dcd00");
    record.push(0x0a);
    record.push(payload.len() as u8);
    record.extend(&payload);
    let hex: String = record.iter().map(|b| format!("{b:02x}")).collect();
    assert_eq!(
        out,
        json!({
            "av1c_hex": hex,
            "seq_profile": 0,
            "seq_level_idx": 13,
            "seq_tier": 1,
            "bit_depth": 10,
            "monochrome": false,
            "color": {"primaries": 1, "transfer": 1, "matrix": 1, "full_range": true}
        })
    );
}

#[test]
fn a_record_names_what_is_missing() {
    assert_eq!(
        config(&bytes(TD)).unwrap_err(),
        "no sequence header OBU in 2 bytes"
    );
    assert_eq!(
        config(&bytes("0a0c02")).unwrap_err(),
        "the OBU at byte 0 runs past the end"
    );
    let mut obus = bytes(TD);
    obus.extend(bytes("0a0c02"));
    assert_eq!(
        config(&obus).unwrap_err(),
        "the OBU at byte 2 runs past the end"
    );
    // SVT's payload cut to five bytes, with no size field: ffmpeg's trace
    // puts frame_height_bits_minus_1 at payload bits 39–42.
    let mut short = vec![0x08];
    short.extend(&bytes(SVT_HEADER)[2..7]);
    assert_eq!(
        config(&short).unwrap_err(),
        "the sequence header ends at bit 40, inside frame_height_bits_minus_1"
    );
    let mut err: *mut c_char = ptr::null_mut();
    let raw = unsafe { rc_av1_config(ptr::null(), 4, &mut err) };
    assert!(raw.is_null());
    assert!(take_string(err).is_some(), "NULL obus names itself");
}

#[test]
fn temporal_delimiters_are_stripped_in_place() {
    let mut packet = bytes(&format!("{TD}{SVT_HEADER}{FRAME}"));
    let kept = strip(&mut packet);
    assert_eq!(&packet[..kept], &bytes(&format!("{SVT_HEADER}{FRAME}"))[..]);

    let mut two = bytes(&format!("{TD}{FRAME}{TD}{FRAME}"));
    let kept = strip(&mut two);
    assert_eq!(&two[..kept], &bytes(&format!("{FRAME}{FRAME}"))[..]);

    let mut none = bytes(FRAME);
    assert_eq!(strip(&mut none), 5);
    assert_eq!(none, bytes(FRAME));
}

#[test]
fn a_packet_that_is_not_whole_obus_is_left_untouched() {
    for hex in [
        format!("{TD}3209aabb"),
        format!("{TD}32"),
        "12ff".to_string(),
    ] {
        let mut packet = bytes(&hex);
        let before = packet.clone();
        assert_eq!(strip(&mut packet), 0, "{hex}");
        assert_eq!(packet, before, "{hex}");
    }
    assert_eq!(
        unsafe { rc_av1_strip_temporal_delimiters(ptr::null_mut(), 4) },
        0
    );
    let mut empty: [u8; 0] = [];
    assert_eq!(strip(&mut empty), 0);
}

/// AVAssetWriter's `ftyp` as the spike read it: `mp42`, minor 1,
/// `isom mp41 mp42`, then the start of the next box.
fn writer_ftyp() -> Vec<u8> {
    let mut head = 28u32.to_be_bytes().to_vec();
    head.extend(b"ftypmp42");
    head.extend(1u32.to_be_bytes());
    head.extend(b"isommp41mp42");
    head.extend(8u32.to_be_bytes());
    head.extend(b"free");
    head
}

#[test]
fn the_ftyp_gains_av01_in_place_of_mp41() {
    let mut head = writer_ftyp();
    assert_eq!(brand(&mut head), 1);
    let mut want = writer_ftyp();
    want[20..24].copy_from_slice(b"av01");
    assert_eq!(head, want);
    assert_eq!(&head[16..28], b"isomav01mp42");
    // Already carried: nothing to do.
    assert_eq!(brand(&mut head), 0);
    assert_eq!(head, want);
}

#[test]
fn an_ftyp_that_cannot_take_av01_is_refused_untouched() {
    let mut no_mp41 = writer_ftyp();
    no_mp41[20..24].copy_from_slice(b"iso2");
    let before = no_mp41.clone();
    assert_eq!(brand(&mut no_mp41), -1);
    assert_eq!(no_mp41, before);

    let mut moov_first = writer_ftyp();
    moov_first[4..8].copy_from_slice(b"moov");
    assert_eq!(brand(&mut moov_first), -1);

    let mut cut = writer_ftyp()[..24].to_vec();
    assert_eq!(brand(&mut cut), -1);

    assert_eq!(unsafe { rc_av1_ftyp_brand(ptr::null_mut(), 32) }, -1);
}
