//! Black-box tests for the PQ peak of the two containers HD-12 left out
//! (spec §11 HD-18): an AV1 stream's HDR metadata OBUs through
//! `rc_hdr10_av1_peak`, and a WebM/Matroska Colour element's HDR10 fields
//! through `rc_container_describe`'s `mdcv_hex` and `clli_hex`.
//!
//! The oracles come from the specifications, never from the reader: the
//! OBUs are built here from AV1 §5.3 (the OBU header, `obu_size` as leb128),
//! §5.8 (`metadata_type`, HDR_CLL and HDR_MDCV, `luminance_max` in 24.8
//! fixed point) and AV1-ISOBMFF §2.3 (the `av1C` record's four-byte header,
//! byte 0 the marker and version 0x81, then configOBUs); the Matroska files
//! by `common/ebml.rs` from RFC 9559 (MaxCLL 0x55BC, MaxFALL 0x55BD,
//! MasteringMetadata 0x55D0 and its float children 0x55D1–0x55DA), and the
//! expected blobs written out byte by byte from ST 2086 (G, B, R, white as
//! u16 in 0.00002, the luminance as u32 in 0.0001 cd/m²) and CTA-861.3.

mod common;

use framejob_core::ffi_hdr10::rc_hdr10_av1_peak;
use serde_json::{json, Value};

use common::ebml::{
    cluster, element, file, float, info, master, simple_block, tracks, uint, vp9_keyframe, Lacing,
    Track,
};
use common::{parse_json, take_string};

// ---- AV1 -----------------------------------------------------------------------

const OBU_SEQUENCE_HEADER: u8 = 1;
const OBU_TEMPORAL_DELIMITER: u8 = 2;
const OBU_METADATA: u8 = 5;
const OBU_FRAME: u8 = 6;

fn leb128(mut value: u64) -> Vec<u8> {
    let mut out = Vec::new();
    loop {
        let byte = (value & 0x7f) as u8;
        value >>= 7;
        if value == 0 {
            out.push(byte);
            return out;
        }
        out.push(byte | 0x80);
    }
}

/// One OBU: its header (type in bits 6–3, the extension and size flags),
/// the extension byte when given, `obu_size` when `sized`, the payload.
fn obu(kind: u8, extension: Option<u8>, sized: bool, payload: &[u8]) -> Vec<u8> {
    let mut header = kind << 3;
    if extension.is_some() {
        header |= 0x04;
    }
    if sized {
        header |= 0x02;
    }
    let mut out = vec![header];
    out.extend(extension);
    if sized {
        out.extend(leb128(payload.len() as u64));
    }
    out.extend_from_slice(payload);
    out
}

/// An HDR_CLL metadata OBU's payload: `metadata_type` 1, `max_cll`,
/// `max_fall`.
fn cll(max_cll: u16, max_fall: u16) -> Vec<u8> {
    let mut out = leb128(1);
    out.extend(max_cll.to_be_bytes());
    out.extend(max_fall.to_be_bytes());
    out
}

/// An HDR_MDCV metadata OBU's payload: `metadata_type` 2, BT.2020's
/// primaries and D65 in 0.00002 units, `luminance_max` (24.8) and
/// `luminance_min` (18.14).
fn mdcv(luminance_max: u32) -> Vec<u8> {
    let mut out = leb128(2);
    for v in [35400u16, 14600, 8500, 39850, 6550, 2300, 15635, 16450] {
        out.extend(v.to_be_bytes());
    }
    out.extend(luminance_max.to_be_bytes());
    out.extend(82u32.to_be_bytes());
    out
}

/// A metadata OBU, sized, no extension.
fn metadata(payload: &[u8]) -> Vec<u8> {
    obu(OBU_METADATA, None, true, payload)
}

/// An `av1C` record: marker and version 0x81, profile/level, flags, the
/// reserved/delay byte, then `obus`.
fn av1c(obus: &[Vec<u8>]) -> Vec<u8> {
    let mut out = vec![0x81, 0x08, 0x0c, 0x00];
    out.extend(obu(
        OBU_SEQUENCE_HEADER,
        None,
        true,
        &[0x00, 0x00, 0x00, 0x42, 0xab],
    ));
    out.extend(obus.concat());
    out
}

/// A temporal unit: a temporal delimiter, `obus`, then a frame stand-in.
fn sample(obus: &[Vec<u8>]) -> Vec<u8> {
    let mut out = obu(OBU_TEMPORAL_DELIMITER, None, true, &[]);
    out.extend(obus.concat());
    out.extend(obu(OBU_FRAME, None, true, &[0x10, 0x00, 0x05, 0x06, 0x07]));
    out
}

fn av1_peak(config: Option<&[u8]>, sample: Option<&[u8]>) -> Value {
    let (cp, cl) = config.map_or((std::ptr::null(), 0), |b| (b.as_ptr(), b.len()));
    let (sp, sl) = sample.map_or((std::ptr::null(), 0), |b| (b.as_ptr(), b.len()));
    let raw = unsafe { rc_hdr10_av1_peak(cp, cl, sp, sl) };
    parse_json(
        &take_string(raw).expect("rc_hdr10_av1_peak returned NULL"),
        "rc_hdr10_av1_peak",
    )
}

/// `nits` in 24.8 fixed point.
fn fixed(nits: u32) -> u32 {
    nits * 256
}

#[test]
fn max_cll_comes_before_the_mastering_maximum() {
    let config = av1c(&[metadata(&mdcv(fixed(4000))), metadata(&cll(600, 200))]);
    assert_eq!(
        av1_peak(Some(&config), None),
        json!({"file": 600, "from": "max_cll"})
    );
    // A MaxCLL of 0 is no reading (CTA-861.3), so the mastering maximum reads.
    let config = av1c(&[metadata(&cll(0, 200)), metadata(&mdcv(fixed(4000)))]);
    assert_eq!(
        av1_peak(Some(&config), None),
        json!({"file": 4000, "from": "mastering_display"})
    );
}

#[test]
fn the_mastering_maximum_alone_is_the_peak() {
    let sample = sample(&[metadata(&mdcv(fixed(2000)))]);
    assert_eq!(
        av1_peak(None, Some(&sample)),
        json!({"file": 2000, "from": "mastering_display"})
    );
}

#[test]
fn the_config_is_read_before_the_sample() {
    let config = av1c(&[metadata(&cll(600, 200))]);
    let later = sample(&[metadata(&cll(1000, 400))]);
    assert_eq!(
        av1_peak(Some(&config), Some(&later)),
        json!({"file": 600, "from": "max_cll"})
    );
    let config = av1c(&[metadata(&mdcv(fixed(2000)))]);
    let later = sample(&[metadata(&mdcv(fixed(4000)))]);
    assert_eq!(
        av1_peak(Some(&config), Some(&later)),
        json!({"file": 2000, "from": "mastering_display"})
    );
    // The first of each kind is kept across the two: the config's mastering
    // display and the sample's MaxCLL, so MaxCLL answers.
    let later = sample(&[metadata(&cll(1000, 400))]);
    assert_eq!(
        av1_peak(Some(&config), Some(&later)),
        json!({"file": 1000, "from": "max_cll"})
    );
}

#[test]
fn an_obu_with_no_size_field_runs_to_the_end() {
    let mut bytes = obu(OBU_TEMPORAL_DELIMITER, None, true, &[]);
    bytes.extend(obu(OBU_METADATA, None, false, &cll(800, 100)));
    assert_eq!(
        av1_peak(None, Some(&bytes)),
        json!({"file": 800, "from": "max_cll"})
    );
}

#[test]
fn an_extension_byte_is_skipped() {
    // temporal_id 1, spatial_id 0: 0b001_00_000.
    let ext = obu(OBU_METADATA, Some(0x20), true, &cll(700, 100));
    assert_eq!(
        av1_peak(None, Some(&sample(&[ext]))),
        json!({"file": 700, "from": "max_cll"})
    );
}

#[test]
fn only_metadata_obus_of_the_two_types_are_read() {
    // A sequence header and a frame whose payloads look like HDR_CLL.
    let lookalike = [
        obu(OBU_SEQUENCE_HEADER, None, true, &cll(900, 100)),
        obu(OBU_FRAME, None, true, &cll(900, 100)),
        // metadata_type 4 (ITU-T T.35) and 3 (scalability).
        metadata(&[&leb128(4)[..], &[0x02, 0x58, 0x00, 0xc8]].concat()),
        metadata(&[&leb128(3)[..], &[0x02, 0x58, 0x00, 0xc8]].concat()),
    ];
    assert_eq!(av1_peak(None, Some(&sample(&lookalike))), json!({}));
}

#[test]
fn a_config_without_its_marker_and_version_reads_nothing() {
    let mut config = av1c(&[metadata(&cll(600, 200))]);
    config[0] = 0x80;
    assert_eq!(av1_peak(Some(&config), None), json!({}));
    config[0] = 0x01;
    assert_eq!(av1_peak(Some(&config), None), json!({}));
    // The sample still reads.
    let later = sample(&[metadata(&cll(1000, 400))]);
    assert_eq!(
        av1_peak(Some(&config), Some(&later)),
        json!({"file": 1000, "from": "max_cll"})
    );
}

#[test]
fn the_maximum_rounds_to_whole_nits_and_clamps() {
    let read = |v: u32| av1_peak(None, Some(&sample(&[metadata(&mdcv(v))])));
    // (v + 128) / 256: 127 rounds to 0 (no reading), 128 to 1.
    assert_eq!(read(127), json!({}));
    assert_eq!(read(128), json!({"file": 1, "from": "mastering_display"}));
    // 1000.5 cd/m² rounds up; 1000.49… down.
    assert_eq!(
        read(256_128),
        json!({"file": 1001, "from": "mastering_display"})
    );
    assert_eq!(
        read(256_127),
        json!({"file": 1000, "from": "mastering_display"})
    );
    // 0xFFFFFFFF cannot wrap: 16777216 cd/m², clamped to 10000.
    assert_eq!(
        read(u32::MAX),
        json!({"file": 10000, "from": "mastering_display"})
    );
    let light = |v: u16| av1_peak(None, Some(&sample(&[metadata(&cll(v, 0))])));
    assert_eq!(light(20000), json!({"file": 10000, "from": "max_cll"}));
    assert_eq!(light(10000), json!({"file": 10000, "from": "max_cll"}));
}

#[test]
fn a_short_payload_is_not_read() {
    // HDR_CLL needs 4 bytes, HDR_MDCV 24.
    let short_cll = metadata(&[&leb128(1)[..], &[0x02, 0x58, 0x00]].concat());
    let mut long = mdcv(fixed(2000));
    long.pop();
    let short_mdcv = metadata(&long);
    assert_eq!(
        av1_peak(None, Some(&sample(&[short_cll, short_mdcv]))),
        json!({})
    );
}

#[test]
fn nothing_given_reads_nothing() {
    assert_eq!(av1_peak(None, None), json!({}));
    let raw = unsafe { rc_hdr10_av1_peak(std::ptr::null(), 40, std::ptr::null(), 40) };
    assert_eq!(
        parse_json(&take_string(raw).expect("not NULL"), "null"),
        json!({})
    );
}

#[test]
fn no_prefix_of_a_fixture_panics() {
    let config = av1c(&[
        metadata(&mdcv(fixed(4000))),
        obu(OBU_METADATA, Some(0x20), true, &cll(600, 200)),
    ]);
    let tail = sample(&[
        metadata(&cll(1000, 400)),
        obu(OBU_METADATA, None, false, &mdcv(u32::MAX)),
    ]);
    for n in 0..=config.len() {
        av1_peak(Some(&config[..n]), None);
    }
    for n in 0..=tail.len() {
        av1_peak(Some(&config), Some(&tail[..n]));
        av1_peak(None, Some(&tail[..n]));
    }
    // An oversized obu_size and a leb128 of nine continuation bytes.
    let huge = [
        0x2a, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0x01,
    ];
    assert_eq!(av1_peak(None, Some(&huge)), json!({}));
    let past = [0x2a, 0x10, 0x01, 0x02, 0x58];
    assert_eq!(av1_peak(None, Some(&past)), json!({}));
}

// ---- Matroska ------------------------------------------------------------------

/// A one-frame VP9 Profile 2 WebM whose Colour is `colour` plus `extra`;
/// describe's video.
fn webm(colour: Option<(u64, u64, u64, u64)>, extra: Vec<Vec<u8>>) -> Value {
    let mut t = Track::video(1, "V_VP9");
    t.colour = colour;
    t.colour_extra = extra;
    let frame = vp9_keyframe(2, false, 5, 0, (1, 1));
    let body = vec![
        info(1_000_000),
        tracks(&[t]),
        cluster(0, &[simple_block(1, 0, true, Lacing::None, &[frame])]),
    ];
    let c = common::ebml::open("hdr10.webm", &file("webm", &body, false)).expect("opens");
    c.describe()["video"].clone()
}

/// A MasteringMetadata element of (ID, value) float children.
fn mastering(children: &[(u32, f64)]) -> Vec<u8> {
    let list: Vec<Vec<u8>> = children.iter().map(|(id, v)| float(*id, *v)).collect();
    master(0x55D0, &list)
}

/// BT.2020's primaries and D65 (R, G, B, white), 4,000 to 0.005 cd/m².
fn bt2020_mastering() -> Vec<u8> {
    mastering(&[
        (0x55D1, 0.708),
        (0x55D2, 0.292),
        (0x55D3, 0.170),
        (0x55D4, 0.797),
        (0x55D5, 0.131),
        (0x55D6, 0.046),
        (0x55D7, 0.3127),
        (0x55D8, 0.3290),
        (0x55D9, 4000.0),
        (0x55DA, 0.005),
    ])
}

#[test]
fn a_colour_elements_hdr10_fields_are_described_as_the_two_blobs() {
    let v = webm(
        Some((9, 1, 16, 9)),
        vec![uint(0x55BC, 600), uint(0x55BD, 200), bt2020_mastering()],
    );
    // G (8500, 39850), B (6550, 2300), R (35400, 14600), white (15635,
    // 16450), then 40000000 and 50.
    assert_eq!(
        v["mdcv_hex"],
        "21349baa199608fc8a4839083d13404202625a0000000032"
    );
    assert_eq!(v["clli_hex"], "025800c8");
    assert_eq!(v["transfer"], 16);
    assert_eq!(v["primaries"], 9);
    assert_eq!(v["matrix"], 9);
    // The vpcC still carries the Colour's codes, as before.
    assert_eq!(v["atom_hex"], "010000000200a2091009 0000".replace(' ', ""));
}

#[test]
fn the_five_keys_are_null_when_the_file_has_none() {
    let v = webm(None, Vec::new());
    for key in ["mdcv_hex", "clli_hex", "transfer", "primaries", "matrix"] {
        assert_eq!(v[key], Value::Null, "{key}");
    }
    let v = webm(Some((1, 1, 1, 1)), Vec::new());
    assert_eq!(v["mdcv_hex"], Value::Null);
    assert_eq!(v["clli_hex"], Value::Null);
    assert_eq!(
        (v["transfer"].clone(), v["primaries"].clone()),
        (json!(1), json!(1))
    );
    assert_eq!(v["matrix"], 1);
}

#[test]
fn an_absent_field_is_zero_in_its_blob() {
    let v = webm(Some((9, 1, 16, 9)), vec![uint(0x55BC, 600)]);
    assert_eq!(v["clli_hex"], "02580000");
    assert_eq!(v["mdcv_hex"], Value::Null);
    let v = webm(Some((9, 1, 16, 9)), vec![uint(0x55BD, 200)]);
    assert_eq!(v["clli_hex"], "000000c8");
    // LuminanceMax alone, as a 4-byte float: 2000 → 20000000 = 0x01312d00.
    let alone = master(0x55D0, &[element(0x55D9, &2000f32.to_be_bytes())]);
    let v = webm(Some((9, 1, 16, 9)), vec![alone]);
    assert_eq!(
        v["mdcv_hex"],
        "0000000000000000000000000000000001312d0000000000"
    );
    assert_eq!(v["clli_hex"], Value::Null);
    // An empty MasteringMetadata is present: all zeros.
    let v = webm(Some((9, 1, 16, 9)), vec![master(0x55D0, &[])]);
    assert_eq!(v["mdcv_hex"], "0".repeat(48));
}

#[test]
fn each_field_is_clamped_to_its_blob() {
    let v = webm(
        Some((9, 1, 16, 9)),
        vec![
            uint(0x55BC, 70_000),
            uint(0x55BD, 1 << 40),
            mastering(&[
                (0x55D1, 1.5),
                (0x55D2, -0.1),
                (0x55D3, f64::NAN),
                (0x55D9, 1e9),
                (0x55DA, f64::NAN),
            ]),
        ],
    );
    assert_eq!(v["clli_hex"], "ffffffff");
    // G NaN → 0; R x 1.5 → 50000 (0xc350), y −0.1 → 0; max 1e13 units →
    // 0xFFFFFFFF; min NaN → 0.
    assert_eq!(
        v["mdcv_hex"],
        "000000000000000 0c350000000000000ffffffff00000000".replace(' ', "")
    );
}

#[test]
fn an_sdr_files_fields_are_still_described() {
    // The copy's description gates them on transfer 16 (the app's); the
    // description reports what the file says.
    let v = webm(Some((1, 1, 1, 1)), vec![uint(0x55BC, 600)]);
    assert_eq!(v["clli_hex"], "02580000");
    assert_eq!(v["transfer"], 1);
}

#[test]
fn a_damaged_mastering_element_is_ignored_not_refused() {
    // A child header whose size runs past its parent's end.
    let damaged = element(0x55D0, &[0x55, 0xD9, 0x88]);
    let v = webm(Some((9, 1, 16, 9)), vec![damaged, uint(0x55BC, 600)]);
    assert_eq!(v["mdcv_hex"], Value::Null);
    assert_eq!(v["clli_hex"], "02580000");
}
