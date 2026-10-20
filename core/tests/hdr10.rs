//! Black-box tests for a PQ file's HDR10 peak reader (spec §11 HD-12),
//! `rc_hdr10_peak`, through the C FFI exactly as `ReelCore.swift` drives it.
//!
//! The oracles are bytes the x265 CLI wrote (hdr H-1's spec, measured: the
//! first 47 bytes of sample 0 of a file made with `--master-display
//! G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(40000000,50)
//! --max-cll 4000,400`, muxed by ffmpeg's stream copy, NAL length 4, an
//! emulation-prevention byte inside the maximum), the two description blobs
//! Apple's writer stored for M5's 600 cd/m² file, and samples built here
//! from H.265's SEI syntax.

mod common;

use framejob_core::ffi_hdr10::rc_hdr10_peak;
use serde_json::{json, Value};

use common::{parse_json, take_string};

/// x265's sample 0, its first 47 bytes: a prefix SEI (144: 4000, 400) and a
/// prefix SEI (137, with `00 00 03` inside the maximum 40000000).
const X265: &str = "000000094e0190040fa00190800000001e4e01891833c286c41d4c0bb884d03e803d13\
                    404202625a00000300003280";
/// M5's description blobs: ST 2086 with a 6000000 maximum, CTA-861.3 600, 200.
const M5_MASTERING: &str = "33c286c41d4c0bb884d03e803d134042005b8d8000000032";
const M5_LIGHT: &str = "025800c8";

fn bytes(hex: &str) -> Vec<u8> {
    let digits: Vec<u8> = hex.bytes().filter(u8::is_ascii_hexdigit).collect();
    digits
        .chunks(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).expect("hex"), 16).expect("hex"))
        .collect()
}

fn parts(blob: Option<&[u8]>) -> (*const u8, usize) {
    blob.map_or((std::ptr::null(), 0), |b| (b.as_ptr(), b.len()))
}

/// What the FFI reads, as JSON.
fn peak(mastering: Option<&[u8]>, light: Option<&[u8]>, sample: Option<&[u8]>, nal: u32) -> Value {
    let (mp, ml) = parts(mastering);
    let (lp, ll) = parts(light);
    let (sp, sl) = parts(sample);
    let raw = unsafe { rc_hdr10_peak(mp, ml, lp, ll, sp, sl, nal) };
    parse_json(
        &take_string(raw).expect("rc_hdr10_peak returned NULL"),
        "rc_hdr10_peak",
    )
}

/// ST 2086 with x265's primaries and `maximum` (0.0001 cd/m²), minimum 50.
fn mastering(maximum: u32) -> Vec<u8> {
    let mut out = bytes("33c286c41d4c0bb884d03e803d134042");
    out.extend(maximum.to_be_bytes());
    out.extend(50u32.to_be_bytes());
    out
}

fn light(max_cll: u16, max_fall: u16) -> Vec<u8> {
    let mut out = max_cll.to_be_bytes().to_vec();
    out.extend(max_fall.to_be_bytes());
    out
}

/// One `sei_message`: type and size (`ff`-extended), then the payload.
fn message(kind: usize, payload: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    for mut value in [kind, payload.len()] {
        while value >= 255 {
            out.push(0xff);
            value -= 255;
        }
        out.push(value as u8);
    }
    out.extend(payload);
    out
}

/// A NAL unit of `kind` (two header bytes) holding `rbsp` and the stop bit,
/// with no emulation prevention needed by the payloads built here.
fn nal(kind: u8, rbsp: &[u8]) -> Vec<u8> {
    let mut out = vec![kind << 1, 0x01];
    out.extend(rbsp);
    out.push(0x80);
    out
}

/// `units` length-prefixed in `size` bytes.
fn sample(size: usize, units: &[Vec<u8>]) -> Vec<u8> {
    let mut out = Vec::new();
    for unit in units {
        let length = unit.len().to_be_bytes();
        out.extend(&length[length.len() - size..]);
        out.extend(unit);
    }
    out
}

fn found(file: u32, from: &str) -> Value {
    json!({"file": file, "from": from})
}

#[test]
fn x265s_own_bytes_read_maxcll_4000() {
    assert_eq!(
        peak(None, None, Some(&bytes(X265)), 4),
        found(4000, "max_cll")
    );
}

#[test]
fn x265s_mastering_reads_through_its_emulation_prevention_byte() {
    // The same bytes without the 144 unit: the 137 alone, 40000000 → 4,000.
    let all = bytes(X265);
    assert_eq!(
        peak(None, None, Some(&all[13..]), 4),
        found(4000, "mastering_display")
    );
}

#[test]
fn every_prefix_of_x265s_bytes_reads_without_panicking() {
    let all = bytes(X265);
    for end in 0..=all.len() {
        let got = peak(None, None, Some(&all[..end]), 4);
        // The 144 unit is the first 13 bytes; once whole, MaxCLL reads.
        let want = if end >= 13 {
            found(4000, "max_cll")
        } else {
            json!({})
        };
        assert_eq!(got, want, "prefix {end}");
    }
    let mastering_only = &all[13..];
    for end in 0..=mastering_only.len() {
        let got = peak(None, None, Some(&mastering_only[..end]), 4);
        let want = if end == mastering_only.len() {
            found(4000, "mastering_display")
        } else {
            json!({})
        };
        assert_eq!(got, want, "mastering prefix {end}");
    }
}

#[test]
fn m5s_description_reads_600_maxcll_first() {
    let (m, l) = (bytes(M5_MASTERING), bytes(M5_LIGHT));
    assert_eq!(peak(Some(&m), Some(&l), None, 0), found(600, "max_cll"));
    assert_eq!(
        peak(Some(&m), None, None, 0),
        found(600, "mastering_display")
    );
    assert_eq!(peak(None, Some(&l), None, 0), found(600, "max_cll"));
}

#[test]
fn the_description_is_read_before_the_sample_and_never_mixed_with_it() {
    let x265 = bytes(X265);
    let (m, l) = (bytes(M5_MASTERING), bytes(M5_LIGHT));
    // pq_both: a 600 description over a 4,000 SEI.
    assert_eq!(
        peak(Some(&m), Some(&l), Some(&x265), 4),
        found(600, "max_cll")
    );
    // The description's mastering alone: its 600, not the SEI's MaxCLL.
    assert_eq!(
        peak(Some(&m), None, Some(&x265), 4),
        found(600, "mastering_display")
    );
    // A description that reads nothing still decides the route.
    assert_eq!(peak(Some(&[1, 2, 3]), None, Some(&x265), 4), json!({}));
    // An empty blob is absent: the sample is read.
    assert_eq!(
        peak(Some(&[]), Some(&[]), Some(&x265), 4),
        found(4000, "max_cll")
    );
}

#[test]
fn maxcll_0_is_unknown_and_falls_to_the_mastering_maximum() {
    let m = mastering(20_000_000);
    assert_eq!(
        peak(Some(&m), Some(&light(0, 0)), None, 0),
        found(2000, "mastering_display")
    );
    let sei = sample(
        4,
        &[nal(
            39,
            &[message(137, &m), message(144, &light(0, 0))].concat(),
        )],
    );
    assert_eq!(
        peak(None, None, Some(&sei), 4),
        found(2000, "mastering_display")
    );
    assert_eq!(peak(None, Some(&light(0, 0)), None, 0), json!({}));
}

#[test]
fn the_maximum_rounds_in_64_bits_and_clamps_to_10000() {
    for (units, want) in [
        (0xFFFF_FFFFu32, Some(10_000)),
        (100_005_000, Some(10_000)),
        (100_000_000, Some(10_000)),
        (99_995_000, Some(10_000)),
        (99_994_999, Some(9_999)),
        (15_000, Some(2)),
        (14_999, Some(1)),
        (5_000, Some(1)),
        (4_999, None),
        (0, None),
    ] {
        let got = peak(Some(&mastering(units)), None, None, 0);
        let expected = want.map_or(json!({}), |n| found(n, "mastering_display"));
        assert_eq!(got, expected, "maximum {units}");
    }
    assert_eq!(
        peak(None, Some(&light(65_535, 0)), None, 0),
        found(10_000, "max_cll")
    );
    assert_eq!(
        peak(None, Some(&light(10_000, 0)), None, 0),
        found(10_000, "max_cll")
    );
    assert_eq!(peak(None, Some(&light(1, 0)), None, 0), found(1, "max_cll"));
}

#[test]
fn short_payloads_read_nothing() {
    assert_eq!(
        peak(Some(&mastering(6_000_000)[..23]), None, None, 0),
        json!({})
    );
    assert_eq!(peak(None, Some(&[0x02, 0x58, 0x00]), None, 0), json!({}));
    let short = sample(4, &[nal(39, &message(144, &[0x0f, 0xa0, 0x01]))]);
    assert_eq!(peak(None, None, Some(&short), 4), json!({}));
}

#[test]
fn nal_lengths_1_2_and_4_read_and_3_and_0_do_not() {
    let units = [nal(39, &message(144, &light(4000, 400)))];
    for size in [1usize, 2, 4] {
        let got = peak(None, None, Some(&sample(size, &units)), size as u32);
        assert_eq!(got, found(4000, "max_cll"), "length size {size}");
    }
    assert_eq!(peak(None, None, Some(&sample(3, &units)), 3), json!({}));
    assert_eq!(peak(None, None, Some(&sample(4, &units)), 0), json!({}));
    assert_eq!(peak(None, None, Some(&sample(4, &units)), 8), json!({}));
}

#[test]
fn only_prefix_sei_before_the_first_vcl_unit_is_read() {
    let sei = nal(39, &message(144, &light(4000, 400)));
    let slice = nal(1, &[0xaf, 0x12, 0x34]);
    let parameters = nal(33, &[0x01, 0x02]);
    assert_eq!(
        peak(
            None,
            None,
            Some(&sample(4, &[parameters.clone(), sei.clone()])),
            4
        ),
        found(4000, "max_cll")
    );
    assert_eq!(
        peak(None, None, Some(&sample(4, &[slice, sei.clone()])), 4),
        json!({})
    );
    let suffix = nal(40, &message(144, &light(4000, 400)));
    assert_eq!(peak(None, None, Some(&sample(4, &[suffix])), 4), json!({}));
    let empty = Vec::new();
    assert_eq!(
        peak(None, None, Some(&sample(4, &[empty, sei])), 4),
        found(4000, "max_cll")
    );
}

#[test]
fn ff_extended_types_and_sizes_are_skipped_and_the_first_of_each_wins() {
    let unknown = message(300, &[0x55; 400]);
    let rbsp = [
        unknown,
        message(144, &light(4000, 400)),
        message(144, &light(600, 200)),
        message(137, &mastering(6_000_000)),
        message(137, &mastering(40_000_000)),
    ]
    .concat();
    let read = sample(4, &[nal(39, &rbsp)]);
    assert_eq!(peak(None, None, Some(&read), 4), found(4000, "max_cll"));
    let masters = [
        message(137, &mastering(6_000_000)),
        message(137, &mastering(40_000_000)),
    ]
    .concat();
    let read = sample(4, &[nal(39, &masters)]);
    assert_eq!(
        peak(None, None, Some(&read), 4),
        found(600, "mastering_display")
    );
}

#[test]
fn nulls_and_zero_lengths_are_absent() {
    let x265 = bytes(X265);
    assert_eq!(peak(None, None, None, 4), json!({}));
    let raw = unsafe {
        rc_hdr10_peak(
            std::ptr::null(),
            24,
            std::ptr::null(),
            4,
            x265.as_ptr(),
            0,
            4,
        )
    };
    assert_eq!(take_string(raw).as_deref(), Some("{}"));
    let raw = unsafe {
        rc_hdr10_peak(
            std::ptr::null(),
            24,
            std::ptr::null(),
            4,
            x265.as_ptr(),
            x265.len(),
            4,
        )
    };
    assert_eq!(
        take_string(raw).as_deref(),
        Some(r#"{"file":4000,"from":"max_cll"}"#)
    );
}
