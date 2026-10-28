//! AV1 in MP4's container bytes (spec §11 CX-12 (4); AV1-ISOBMFF §2): the
//! `av1C` record built from an encoder's sequence header OBU, the temporal
//! delimiters stripped from each sample, and the `av01` brand in the
//! written file's `ftyp`. CX-6's precedent puts container bytes in the
//! core: each is a decision about bytes the encoder handed over, read and
//! rewritten as bytes, and none touches a sample of picture.
//!
//! The encoder is the app's (CX-4); `ffi_av1.rs` exports the three readers
//! here as `rc_av1_*`.
//!
//! **The sequence header is parsed, not assumed.** The `av1C` record's
//! second and third bytes restate the profile, operating point 0's level and
//! tier, and the colour config's depth, monochrome flag, subsampling and
//! chroma position (AV1-ISOBMFF §2.3.3). Every field before `color_config`
//! is walked as AV1 §5.5 writes it — timing info, the decoder model, every
//! operating point, the frame-id lengths, the tool flags, the order hint,
//! the screen-content choices — so an encoder that turns one on moves the
//! read with it rather than past it.

use serde::Serialize;

use crate::hdr10::leb128;

/// The OBU types this file names (AV1 §6.2.2).
const OBU_SEQUENCE_HEADER: u8 = 1;
const OBU_TEMPORAL_DELIMITER: u8 = 2;
/// An OBU header's `obu_extension_flag` and `obu_has_size_field` bits.
const OBU_EXTENSION_BIT: u8 = 0x04;
const OBU_HAS_SIZE_BIT: u8 = 0x02;
/// The record's first byte: its marker bit and version 1.
const AV1C_MARKER_VERSION: u8 = 0x81;
/// `color_config`'s values for "the header describes no colour" (AV1 §6.4.2).
const UNSPECIFIED: u8 = 2;

/// The colour a sequence header describes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Av1Color {
    pub primaries: u8,
    pub transfer: u8,
    pub matrix: u8,
    pub full_range: bool,
}

/// An `av1C` record and the fields it was built from.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Av1Config {
    pub record: Vec<u8>,
    pub seq_profile: u8,
    pub seq_level_idx: u8,
    pub seq_tier: u8,
    pub bit_depth: u8,
    pub monochrome: bool,
    pub color: Av1Color,
}

/// One OBU's place in a run: where it starts, its header's length (the
/// header byte, the extension byte, the size field), its type and where it
/// ends.
struct Obu {
    start: usize,
    header: usize,
    kind: u8,
    end: usize,
}

/// The OBU at `start` of `bytes`: `None` when its size field is cut short
/// or its payload runs past the end. One without a size field runs to the
/// end (AV1 §5.3.1).
fn obu_at(bytes: &[u8], start: usize) -> Option<Obu> {
    let first = *bytes.get(start)?;
    let mut header = 1 + usize::from(first & OBU_EXTENSION_BIT != 0);
    if start + header > bytes.len() {
        return None;
    }
    let end = if first & OBU_HAS_SIZE_BIT != 0 {
        let (size, used) = leb128(&bytes[start + header..])?;
        header += used;
        let size = usize::try_from(size).ok()?;
        (start + header).checked_add(size)?
    } else {
        bytes.len()
    };
    if end > bytes.len() {
        return None;
    }
    Some(Obu {
        start,
        header,
        kind: (first >> 3) & 0x0f,
        end,
    })
}

/// An unsigned leb128, the shortest spelling of `value`.
fn leb128_bytes(mut value: usize) -> Vec<u8> {
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

/// A big-endian bit reader over a sequence header's payload, naming the
/// field it was reading when the bytes ran out.
struct Bits<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl Bits<'_> {
    fn f(&mut self, n: u32, field: &str) -> Result<u64, String> {
        let mut value = 0u64;
        for _ in 0..n {
            let Some(byte) = self.bytes.get(self.at / 8) else {
                return Err(format!(
                    "the sequence header ends at bit {}, inside {field}",
                    self.at
                ));
            };
            value = (value << 1) | u64::from((byte >> (7 - self.at % 8)) & 1);
            self.at += 1;
        }
        Ok(value)
    }

    /// One-bit fields read only to be passed over, named in order.
    fn flags(&mut self, fields: &str) -> Result<(), String> {
        for field in fields.split(' ') {
            self.f(1, field)?;
        }
        Ok(())
    }

    fn flag(&mut self, field: &str) -> Result<bool, String> {
        Ok(self.f(1, field)? == 1)
    }

    fn byte(&mut self, n: u32, field: &str) -> Result<u8, String> {
        Ok(self.f(n, field)? as u8)
    }

    /// AV1 §4.10.3: leading zeros, then that many bits; a run of 32 or more
    /// zeros is the maximum value, and reading past the end is an error, so
    /// a payload of zeros cannot loop.
    fn uvlc(&mut self, field: &str) -> Result<(), String> {
        let mut zeros = 0u32;
        while !self.flag(field)? {
            zeros += 1;
        }
        if zeros < 32 {
            self.f(zeros, field)?;
        }
        Ok(())
    }
}

/// AV1 §5.5.1 through `color_config` (§5.5.2): the config with the
/// record's four bytes, the OBU still to follow.
fn parse_sequence_header(payload: &[u8]) -> Result<Av1Config, String> {
    let mut b = Bits {
        bytes: payload,
        at: 0,
    };
    let profile = b.byte(3, "seq_profile")?;
    b.flag("still_picture")?;
    let reduced = b.flag("reduced_still_picture_header")?;
    let (level, tier);
    if reduced {
        level = b.byte(5, "seq_level_idx[0]")?;
        tier = 0;
    } else {
        let mut decoder_model = false;
        let mut buffer_delay_bits = 0;
        if b.flag("timing_info_present_flag")? {
            b.f(32, "num_units_in_display_tick")?;
            b.f(32, "time_scale")?;
            if b.flag("equal_picture_interval")? {
                b.uvlc("num_ticks_per_picture_minus_1")?;
            }
            decoder_model = b.flag("decoder_model_info_present_flag")?;
            if decoder_model {
                buffer_delay_bits = b.f(5, "buffer_delay_length_minus_1")? as u32 + 1;
                b.f(32, "num_units_in_decoding_tick")?;
                b.f(5, "buffer_removal_time_length_minus_1")?;
                b.f(5, "frame_presentation_time_length_minus_1")?;
            }
        }
        let display_delay = b.flag("initial_display_delay_present_flag")?;
        let points = b.f(5, "operating_points_cnt_minus_1")? + 1;
        let mut first = None;
        for _ in 0..points {
            b.f(12, "operating_point_idc")?;
            let idx = b.byte(5, "seq_level_idx")?;
            let point_tier = if idx > 7 { b.byte(1, "seq_tier")? } else { 0 };
            first.get_or_insert((idx, point_tier));
            if decoder_model && b.flag("decoder_model_present_for_this_op")? {
                b.f(buffer_delay_bits, "decoder_buffer_delay")?;
                b.f(buffer_delay_bits, "encoder_buffer_delay")?;
                b.flag("low_delay_mode_flag")?;
            }
            if display_delay && b.flag("initial_display_delay_present_for_this_op")? {
                b.f(4, "initial_display_delay_minus_1")?;
            }
        }
        (level, tier) = first.unwrap_or((0, 0));
    }
    let width_bits = b.f(4, "frame_width_bits_minus_1")? as u32 + 1;
    let height_bits = b.f(4, "frame_height_bits_minus_1")? as u32 + 1;
    b.f(width_bits, "max_frame_width_minus_1")?;
    b.f(height_bits, "max_frame_height_minus_1")?;
    if !reduced && b.flag("frame_id_numbers_present_flag")? {
        b.f(4, "delta_frame_id_length_minus_2")?;
        b.f(3, "additional_frame_id_length_minus_1")?;
    }
    b.flags("use_128x128_superblock enable_filter_intra enable_intra_edge_filter")?;
    if !reduced {
        b.flags("enable_interintra_compound enable_masked_compound")?;
        b.flags("enable_warped_motion enable_dual_filter")?;
        let order_hint = b.flag("enable_order_hint")?;
        if order_hint {
            b.flags("enable_jnt_comp enable_ref_frame_mvs")?;
        }
        let force_screen_content = if b.flag("seq_choose_screen_content_tools")? {
            true
        } else {
            b.flag("seq_force_screen_content_tools")?
        };
        if force_screen_content && !b.flag("seq_choose_integer_mv")? {
            b.flag("seq_force_integer_mv")?;
        }
        if order_hint {
            b.f(3, "order_hint_bits_minus_1")?;
        }
    }
    b.flags("enable_superres enable_cdef enable_restoration")?;
    color_config(&mut b, profile, level, tier)
}

/// AV1 §5.5.2, and the record's fixed bytes (AV1-ISOBMFF §2.3.3).
fn color_config(b: &mut Bits, profile: u8, level: u8, tier: u8) -> Result<Av1Config, String> {
    let high_bitdepth = b.flag("high_bitdepth")?;
    let twelve_bit = profile == 2 && high_bitdepth && b.flag("twelve_bit")?;
    let monochrome = profile != 1 && b.flag("mono_chrome")?;
    let color_description = b.flag("color_description_present_flag")?;
    let (primaries, transfer, matrix) = if color_description {
        (
            b.byte(8, "color_primaries")?,
            b.byte(8, "transfer_characteristics")?,
            b.byte(8, "matrix_coefficients")?,
        )
    } else {
        (UNSPECIFIED, UNSPECIFIED, UNSPECIFIED)
    };
    let mut chroma_position = 0;
    let (full_range, subsampling);
    if monochrome {
        full_range = b.flag("color_range")?;
        subsampling = (true, true);
    } else if (primaries, transfer, matrix) == (1, 13, 0) {
        // BT.709 primaries, sRGB transfer, identity matrix: 4:4:4 full range.
        full_range = true;
        subsampling = (false, false);
    } else {
        full_range = b.flag("color_range")?;
        subsampling = match profile {
            0 => (true, true),
            1 => (false, false),
            _ if twelve_bit => {
                let x = b.flag("subsampling_x")?;
                (x, x && b.flag("subsampling_y")?)
            }
            _ => (true, false),
        };
        if subsampling == (true, true) {
            chroma_position = b.byte(2, "chroma_sample_position")?;
        }
    }
    if !monochrome {
        b.flag("separate_uv_delta_q")?;
    }
    let bit = |on: bool, shift: u8| u8::from(on) << shift;
    let flags = (tier << 7)
        | bit(high_bitdepth, 6)
        | bit(twelve_bit, 5)
        | bit(monochrome, 4)
        | bit(subsampling.0, 3)
        | bit(subsampling.1, 2)
        | (chroma_position & 0x03);
    let color = Av1Color {
        primaries,
        transfer,
        matrix,
        full_range,
    };
    Ok(Av1Config {
        record: vec![
            AV1C_MARKER_VERSION,
            (profile << 5) | (level & 0x1f),
            flags,
            0x00,
        ],
        seq_profile: profile,
        seq_level_idx: level,
        seq_tier: tier,
        bit_depth: [8, 10, 12][usize::from(high_bitdepth) + usize::from(twelve_bit)],
        monochrome,
        color,
    })
}

/// The `av1C` record for the first sequence header OBU in `obus`, an OBU
/// run (AV1-ISOBMFF §2.3.3): its four bytes, then that OBU with a size
/// field. `Err` names what is missing.
pub fn config_record(obus: &[u8]) -> Result<Av1Config, String> {
    let mut at = 0;
    let obu = loop {
        if at >= obus.len() {
            return Err(format!("no sequence header OBU in {} bytes", obus.len()));
        }
        let obu = obu_at(obus, at).ok_or(format!("the OBU at byte {at} runs past the end"))?;
        if obu.kind == OBU_SEQUENCE_HEADER {
            break obu;
        }
        at = obu.end;
    };
    let payload = &obus[obu.start + obu.header..obu.end];
    let mut config = parse_sequence_header(payload)?;
    // The OBU as it came, but always with a size field (AV1-ISOBMFF §2.3.4).
    let first = obus[obu.start];
    config.record.push(first | OBU_HAS_SIZE_BIT);
    if first & OBU_EXTENSION_BIT != 0 {
        config.record.push(obus[obu.start + 1]);
    }
    config.record.extend(leb128_bytes(payload.len()));
    config.record.extend_from_slice(payload);
    Ok(config)
}

/// Removes every temporal delimiter OBU from `bytes` in place (AV1-ISOBMFF
/// §2.4: a sample carries none) and answers the length kept; `None`, with
/// the bytes untouched, when they are not a run of whole OBUs.
pub fn strip_temporal_delimiters(bytes: &mut [u8]) -> Option<usize> {
    let mut kept = Vec::new();
    let mut at = 0;
    while at < bytes.len() {
        let obu = obu_at(bytes, at)?;
        if obu.kind != OBU_TEMPORAL_DELIMITER {
            kept.push(obu.start..obu.end);
        }
        at = obu.end;
    }
    let mut write = 0;
    for range in kept {
        let len = range.len();
        bytes.copy_within(range, write);
        write += len;
    }
    Some(write)
}

/// Makes the `ftyp` box at the start of `head` carry `av01` among its
/// compatible brands (AV1-ISOBMFF §2.1): `Ok(false)` when it already does,
/// `Ok(true)` when its first `mp41` was rewritten `av01` in place (no size
/// or offset moves), and `Err` naming what is missing, the bytes untouched.
pub fn brand_av01(head: &mut [u8]) -> Result<bool, String> {
    if head.len() < 16 || &head[4..8] != b"ftyp" {
        return Err("no ftyp box at byte 0".to_string());
    }
    let size = u32::from_be_bytes([head[0], head[1], head[2], head[3]]) as usize;
    if size < 16 || size > head.len() {
        return Err(format!(
            "the ftyp box's size {size} is not inside the {} bytes given",
            head.len()
        ));
    }
    let brands = 16..size - (size - 16) % 4;
    let compatible = |head: &[u8], brand: &[u8; 4]| {
        brands
            .clone()
            .step_by(4)
            .find(|at| &head[*at..*at + 4] == brand)
    };
    if compatible(head, b"av01").is_some() {
        return Ok(false);
    }
    let at = compatible(head, b"mp41")
        .ok_or("the ftyp box has no mp41 brand to rewrite as av01".to_string())?;
    head[at..at + 4].copy_from_slice(b"av01");
    Ok(true)
}
