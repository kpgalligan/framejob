//! A PQ file's HDR10 peak (spec §11 HD-6, HD-12): a pure reader of the two
//! places HDR10 static metadata lives, from bytes Swift hands it, so import
//! reads one answer whatever wrote the file. Reached through `rc_hdr10_peak`
//! (`ffi_hdr10.rs`); what the answer becomes on the media is
//! `media_color.rs`'s.
//!
//! - **The sample description** (what Apple's writer stores, and the only
//!   place AVFoundation reads): the `MasteringDisplayColorVolume` extension,
//!   24 bytes of SMPTE ST 2086 in the order H.265's SEI 137 carries them —
//!   three primaries and the white point as u16 pairs, then the maximum and
//!   minimum luminance as big-endian u32 in 0.0001 cd/m² (the maximum at
//!   bytes 16–19) — and the `ContentLightLevelInfo` extension, 4 bytes of
//!   CTA-861.3: MaxCLL then MaxFALL, big-endian u16 cd/m².
//! - **The HEVC stream** (where ffmpeg, HandBrake and x265 write it): the
//!   first sample's length-prefixed NAL units, the prefix SEI units (type 39)
//!   before its first VCL unit (type below 32), their emulation-prevention
//!   bytes removed, each `sei_message`'s `ff`-extended type and size
//!   (ITU-T H.265 §7.3.5), payloads 137 (`mastering_display_colour_volume`,
//!   the same 24 bytes) and 144 (`content_light_level_info`, the same 4).
//!
//! - **The AV1 stream** (spec §11 HD-18 (c); AV1 §5.3, §5.8, §6.7;
//!   AV1-ISOBMFF §2.3): the `av1C` record's configOBUs (bytes 4 on, when its
//!   first byte is 0x81, the marker and version 1), then the first sample's
//!   OBUs — each OBU's type in its header's bits 6–3, an extension byte
//!   skipped, its leb128 `obu_size` when it has one, else the rest of the
//!   bytes — and in each OBU_METADATA (type 5) its leb128 `metadata_type`:
//!   HDR_CLL (1; `max_cll` then `max_fall`, CTA-861.3's 4 bytes) and
//!   HDR_MDCV (2; ST 2086's 24 bytes, but `luminance_max` in 24.8 fixed
//!   point), the first of each kept, the config's first. Reached through
//!   `rc_hdr10_av1_peak` for an `av01` track whose description carries
//!   neither extension.
//!
//! The description is read when the caller has either extension; only when
//! it has neither is the stream read, and the two are never mixed. Within
//! the route read, the peak is MaxCLL when present and non-zero, else the
//! mastering maximum (HD-6's choice: MaxCLL is what the content reaches,
//! the display what it was graded on). The maximum rounds to whole cd/m² in
//! 64 bits, so `0xFFFFFFFF` cannot wrap; a value above [`PEAK_MAX`] is
//! clamped to it and 0 is no reading. Every index is bounds-checked: no
//! input panics, a short or malformed one reads nothing.

use crate::model_media_color::{PeakSource, PqColor, PEAK_MAX};

/// H.265's SEI payload types for the two HDR10 messages (Annex D).
const MASTERING_DISPLAY: usize = 137;
const CONTENT_LIGHT_LEVEL: usize = 144;
/// The bytes each payload must hold to be read.
const MASTERING_BYTES: usize = 24;
const CONTENT_LIGHT_BYTES: usize = 4;
/// NAL unit types: a prefix SEI, and the first non-VCL type (every type
/// below it is a coded slice, which ends the search).
const PREFIX_SEI: u8 = 39;
const FIRST_NON_VCL: u8 = 32;
/// The mastering luminance's unit: 0.0001 cd/m².
const LUMINANCE_UNITS: u64 = 10_000;
/// AV1's OBU_METADATA type and its two HDR10 metadata types (AV1 §6.2.2,
/// §6.7.1).
const OBU_METADATA: u8 = 5;
const METADATA_HDR_CLL: u64 = 1;
const METADATA_HDR_MDCV: u64 = 2;
/// An `av1C` record's first byte, its marker bit and version 1, and the
/// length of its fixed header, after which its configOBUs lie
/// (AV1-ISOBMFF §2.3.3).
const AV1C_MARKER_VERSION: u8 = 0x81;
const AV1C_HEADER: usize = 4;
/// AV1's mastering luminance: 24.8 fixed point, so 1/256 cd/m².
const AV1_LUMINANCE_UNITS: u64 = 256;
/// The longest leb128 AV1 allows (§4.10.5).
const LEB128_MAX_BYTES: usize = 8;

/// The peak of a PQ file: the description's two extensions (`mastering`,
/// `content_light`; `None` for one the file lacks) when either is given,
/// else the first sample's SEI (`sample`, its NAL units prefixed by
/// `nal_length_size` bytes: 1, 2 or 4, anything else reading nothing).
/// `peak` is always `None`: the override is the person's, never the file's.
pub fn peak(
    mastering: Option<&[u8]>,
    content_light: Option<&[u8]>,
    sample: Option<&[u8]>,
    nal_length_size: usize,
) -> PqColor {
    if mastering.is_some() || content_light.is_some() {
        return choose(
            mastering.and_then(mastering_max),
            content_light.and_then(max_cll),
        );
    }
    let Some(sample) = sample else {
        return PqColor::default();
    };
    let (mastering, light) = sei_payloads(sample, nal_length_size);
    choose(mastering, light)
}

/// The peak of an AV1 PQ file whose description carries neither extension
/// (spec §11 HD-18 (c)): the metadata OBUs of its `av1C` record (`config`)
/// and then of its first sample with data (`sample`), the first HDR_CLL and
/// the first HDR_MDCV kept; MaxCLL when present and non-zero, else the
/// mastering maximum. `peak` is always `None`.
pub fn av1_peak(config: Option<&[u8]>, sample: Option<&[u8]>) -> PqColor {
    let mut readings = Readings::default();
    let config_obus = config
        .filter(|record| record.first() == Some(&AV1C_MARKER_VERSION))
        .and_then(|record| record.get(AV1C_HEADER..));
    for obus in [config_obus, sample].into_iter().flatten() {
        readings.read_obus(obus);
    }
    choose(readings.mastering.flatten(), readings.light.flatten())
}

/// MaxCLL when there is one, else the mastering maximum, else nothing.
fn choose(mastering: Option<u32>, content_light: Option<u32>) -> PqColor {
    content_light
        .map(|cll| found(cll, PeakSource::MaxCll))
        .or_else(|| mastering.map(|max| found(max, PeakSource::MasteringDisplay)))
        .unwrap_or_default()
}

fn found(nits: u32, from: PeakSource) -> PqColor {
    PqColor {
        file: Some(nits.min(PEAK_MAX)),
        from: Some(from),
        peak: None,
    }
}

/// ST 2086's maximum luminance in whole cd/m², rounded to nearest and
/// clamped to [`PEAK_MAX`]; `None` for a short payload or a maximum that
/// rounds to 0.
fn mastering_max(bytes: &[u8]) -> Option<u32> {
    let field: [u8; 4] = bytes.get(16..20)?.try_into().ok()?;
    if bytes.len() < MASTERING_BYTES {
        return None;
    }
    let units = u64::from(u32::from_be_bytes(field));
    let nits = (units + LUMINANCE_UNITS / 2) / LUMINANCE_UNITS;
    let nits = u32::try_from(nits.min(u64::from(PEAK_MAX))).ok()?;
    (nits > 0).then_some(nits)
}

/// AV1's HDR_MDCV maximum luminance (24.8 fixed point at bytes 16–19) in
/// whole cd/m², rounded to nearest in 64 bits and clamped to [`PEAK_MAX`];
/// `None` for a short payload or a maximum that rounds to 0.
fn av1_mastering_max(bytes: &[u8]) -> Option<u32> {
    let field: [u8; 4] = bytes.get(16..20)?.try_into().ok()?;
    if bytes.len() < MASTERING_BYTES {
        return None;
    }
    let units = u64::from(u32::from_be_bytes(field));
    let nits = (units + AV1_LUMINANCE_UNITS / 2) / AV1_LUMINANCE_UNITS;
    let nits = u32::try_from(nits.min(u64::from(PEAK_MAX))).ok()?;
    (nits > 0).then_some(nits)
}

/// CTA-861.3's MaxCLL; `None` for a short payload or 0 (unknown, by the
/// standard).
fn max_cll(bytes: &[u8]) -> Option<u32> {
    let field: [u8; 2] = bytes.get(0..2)?.try_into().ok()?;
    if bytes.len() < CONTENT_LIGHT_BYTES {
        return None;
    }
    let nits = u32::from(u16::from_be_bytes(field));
    (nits > 0).then_some(nits)
}

/// The first sample's two HDR10 readings from its prefix SEI: (the mastering
/// maximum, MaxCLL), the first payload of each type long enough to read.
fn sei_payloads(sample: &[u8], nal_length_size: usize) -> (Option<u32>, Option<u32>) {
    let mut readings = Readings::default();
    if !matches!(nal_length_size, 1 | 2 | 4) {
        return (None, None);
    }
    let mut at = 0usize;
    while let Some(prefix) = sample.get(at..at.saturating_add(nal_length_size)) {
        let length = prefix
            .iter()
            .fold(0usize, |value, byte| (value << 8) | usize::from(*byte));
        at += nal_length_size;
        let Some(unit) = at.checked_add(length).and_then(|end| sample.get(at..end)) else {
            break;
        };
        at += length;
        let Some(header) = unit.first() else {
            continue;
        };
        let kind = (header >> 1) & 0x3f;
        if kind < FIRST_NON_VCL {
            break;
        }
        if kind == PREFIX_SEI {
            if let Some(body) = unit.get(2..) {
                readings.read(&unescaped(body));
            }
        }
    }
    (readings.mastering.flatten(), readings.light.flatten())
}

/// The first payload of each type seen (its reading, which may be none).
#[derive(Default)]
struct Readings {
    mastering: Option<Option<u32>>,
    light: Option<Option<u32>>,
}

impl Readings {
    /// Every `sei_message` of one SEI unit's RBSP, up to its trailing bits.
    fn read(&mut self, rbsp: &[u8]) {
        let mut at = 0usize;
        while more_data(rbsp, at) {
            let (Some(kind), Some(size)) = (ff_value(rbsp, &mut at), ff_value(rbsp, &mut at))
            else {
                return;
            };
            let Some(payload) = at.checked_add(size).and_then(|end| rbsp.get(at..end)) else {
                return;
            };
            at += size;
            match kind {
                MASTERING_DISPLAY if payload.len() >= MASTERING_BYTES => {
                    self.mastering.get_or_insert(mastering_max(payload));
                }
                CONTENT_LIGHT_LEVEL if payload.len() >= CONTENT_LIGHT_BYTES => {
                    self.light.get_or_insert(max_cll(payload));
                }
                _ => {}
            }
        }
    }
}

impl Readings {
    /// Every OBU of `bytes` (AV1 §5.3.1): an OBU_METADATA's HDR_CLL and
    /// HDR_MDCV read, every other OBU passed over; a size past the end, or a
    /// header or size cut short, ends the walk.
    fn read_obus(&mut self, mut bytes: &[u8]) {
        while let Some((&header, rest)) = bytes.split_first() {
            let kind = (header >> 3) & 0x0f;
            let has_extension = header & 0x04 != 0;
            let has_size = header & 0x02 != 0;
            let Some(rest) = rest.get(usize::from(has_extension)..) else {
                return;
            };
            let (payload, next) = if has_size {
                let Some((size, used)) = leb128(rest) else {
                    return;
                };
                let end = usize::try_from(size)
                    .ok()
                    .and_then(|size| used.checked_add(size));
                let Some(end) = end.filter(|end| *end <= rest.len()) else {
                    return;
                };
                (&rest[used..end], &rest[end..])
            } else {
                (rest, &rest[rest.len()..])
            };
            if kind == OBU_METADATA {
                self.read_metadata(payload);
            }
            bytes = next;
        }
    }

    /// One OBU_METADATA's payload (AV1 §5.8.1): its leb128 `metadata_type`,
    /// then an HDR_CLL or HDR_MDCV body long enough to read.
    fn read_metadata(&mut self, payload: &[u8]) {
        let Some((kind, used)) = leb128(payload) else {
            return;
        };
        let body = &payload[used..];
        match kind {
            METADATA_HDR_CLL if body.len() >= CONTENT_LIGHT_BYTES => {
                self.light.get_or_insert(max_cll(body));
            }
            METADATA_HDR_MDCV if body.len() >= MASTERING_BYTES => {
                self.mastering.get_or_insert(av1_mastering_max(body));
            }
            _ => {}
        }
    }
}

/// An unsigned leb128 (AV1 §4.10.5): its value and its length in bytes;
/// `None` when it is cut short or longer than 8 bytes.
fn leb128(bytes: &[u8]) -> Option<(u64, usize)> {
    let mut value = 0u64;
    for (i, byte) in bytes.iter().take(LEB128_MAX_BYTES).enumerate() {
        value |= u64::from(byte & 0x7f) << (7 * i);
        if byte & 0x80 == 0 {
            return Some((value, i + 1));
        }
    }
    None
}

/// Whether a message starts at `at`: bytes remain and they are not only the
/// RBSP's stop bit (`0x80`) and zero padding.
fn more_data(rbsp: &[u8], at: usize) -> bool {
    match rbsp.get(at..) {
        None | Some([]) => false,
        Some([0x80, rest @ ..]) => rest.iter().any(|byte| *byte != 0),
        Some(_) => true,
    }
}

/// A `sei_message`'s type or size: `0xFF` bytes each adding 255, then a
/// last byte; `None` past the end.
fn ff_value(bytes: &[u8], at: &mut usize) -> Option<usize> {
    let mut value = 0usize;
    loop {
        let byte = *bytes.get(*at)?;
        *at += 1;
        value = value.checked_add(usize::from(byte))?;
        if byte != 0xff {
            return Some(value);
        }
    }
}

/// A NAL unit's payload with its emulation-prevention bytes removed: each
/// `0x03` after two zero bytes (H.265 §7.4.2).
fn unescaped(bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(bytes.len());
    let mut zeros = 0;
    for &byte in bytes {
        if zeros >= 2 && byte == 0x03 {
            zeros = 0;
            continue;
        }
        out.push(byte);
        zeros = if byte == 0 { zeros + 1 } else { 0 };
    }
    out
}
