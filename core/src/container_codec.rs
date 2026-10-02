//! What a WebM or Matroska track's codec becomes in a QuickTime movie (spec
//! §11 #216-R): its four-character code, and the setup record the writer's
//! format description carries.
//!
//! - **Video.** `V_VP9` is `vp09` with a `vpcC` built here from the first
//!   keyframe's uncompressed header and the track's Colour element, because
//!   ffmpeg writes no VP9 CodecPrivate (measured) and the decoder needs one.
//!   `V_AV1`, `V_MPEG4/ISO/AVC` and `V_MPEGH/ISO/HEVC` are `av01`, `avc1` and
//!   `hvc1`, their CodecPrivate already being the `av1C`, `avcC` and `hvcC`
//!   record. `V_VP8` is `vp08`, named so the app can refuse it in #216's
//!   sentence. Anything else is not copied.
//! - **Audio.** `A_OPUS` is `opus` with OpusHead verbatim as its cookie.
//!   `A_AAC` is `aac ` with an ES_Descriptor around the AudioSpecificConfig:
//!   a bare AudioSpecificConfig wrote a movie with NO audio track and no
//!   error (measured). `A_AAC/MPEG4/*`, with no CodecPrivate, and every
//!   other codec are not copied — the app names them and the opt-in ffmpeg
//!   step may take them.
//! - **Opus packet lengths** come from the TOC byte (RFC 6716 §3.1), because
//!   a 60 ms packet timed at a fixed 960 samples mistimes the track
//!   (measured).

/// The Colour element's four values the `vpcC` record carries.
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct Colour {
    pub matrix: Option<u8>,
    pub range: Option<u8>,
    pub transfer: Option<u8>,
    pub primaries: Option<u8>,
}

/// A video codec's four-character code, or `None` when it is not copied.
/// The three whose CodecPrivate IS their record need one.
pub(crate) fn video_fourcc(codec_id: &str, private: &[u8]) -> Option<&'static str> {
    match codec_id {
        "V_VP9" => Some("vp09"),
        "V_VP8" => Some("vp08"),
        "V_AV1" if !private.is_empty() => Some("av01"),
        "V_MPEG4/ISO/AVC" if !private.is_empty() => Some("avc1"),
        "V_MPEGH/ISO/HEVC" if !private.is_empty() => Some("hvc1"),
        _ => None,
    }
}

/// The atom a codec's CodecPrivate is carried as, verbatim.
pub(crate) fn private_atom(codec_id: &str) -> Option<&'static str> {
    match codec_id {
        "V_AV1" => Some("av1C"),
        "V_MPEG4/ISO/AVC" => Some("avcC"),
        "V_MPEGH/ISO/HEVC" => Some("hvcC"),
        _ => None,
    }
}

/// An audio codec's four-character code, or `None` when it is not copied.
pub(crate) fn audio_fourcc(codec_id: &str, private: &[u8]) -> Option<&'static str> {
    match codec_id {
        "A_OPUS" if private.starts_with(b"OpusHead") => Some("opus"),
        "A_AAC" if !private.is_empty() => Some("aac "),
        _ => None,
    }
}

/// Reads bits most significant first.
struct Bits<'a> {
    data: &'a [u8],
    at: usize,
}

impl Bits<'_> {
    fn read(&mut self, n: usize) -> Option<u32> {
        let mut v = 0u32;
        for _ in 0..n {
            let byte = *self.data.get(self.at / 8)?;
            v = (v << 1) | u32::from((byte >> (7 - self.at % 8)) & 1);
            self.at += 1;
        }
        Some(v)
    }
}

/// A `vpcC` record (version 1) from a VP9 keyframe's uncompressed header
/// (VP9 bitstream spec §6.2) and the track's Colour element, with the
/// profile it read. `None` when `frame` is not a keyframe's header.
///
/// Level is 0 (unspecified). The colour space maps to the matrix
/// coefficients ISO/IEC 23091-2 numbers; the Colour element, when present,
/// overrides it and supplies the primaries and transfer, else 2
/// (unspecified). Chroma is 1 (4:2:0, co-sited) for 4:2:0, 2 for 4:2:2 and
/// 3 for 4:4:4 — the 8-bit Profile 0 and 10-bit Profile 2 records this
/// writes decode (measured); Profile 1 still does not, which the app's
/// pre-check refuses first.
pub(crate) fn vpcc(frame: &[u8], colour: &Colour) -> Option<(Vec<u8>, u8)> {
    let mut b = Bits { data: frame, at: 0 };
    if b.read(2)? != 2 {
        return None;
    }
    let low = b.read(1)?;
    let profile = (b.read(1)? << 1) | low;
    if profile == 3 {
        b.read(1)?;
    }
    let show_existing = b.read(1)?;
    let frame_type = b.read(1)?;
    if show_existing == 1 || frame_type != 0 {
        return None;
    }
    b.read(2)?; // show_frame, error_resilient_mode
    if b.read(24)? != 0x49_8342 {
        return None;
    }
    let depth: u8 = match profile {
        0 | 1 => 8,
        _ if b.read(1)? == 1 => 12,
        _ => 10,
    };
    let space = b.read(3)?;
    let (full, sub_x, sub_y) = if space != 7 {
        let full = b.read(1)?;
        if profile == 1 || profile == 3 {
            (full, b.read(1)?, b.read(1)?)
        } else {
            (full, 1, 1)
        }
    } else {
        (1, 0, 0)
    };
    let chroma: u8 = match (sub_x, sub_y) {
        (1, 1) => 1,
        (1, _) => 2,
        _ => 3,
    };
    let matrix = match space {
        1 | 3 => 6, // BT.601, SMPTE 170M
        2 => 1,     // BT.709
        4 => 7,     // SMPTE 240M
        5 => 9,     // BT.2020 non-constant
        7 => 0,     // RGB
        _ => 2,     // unspecified
    };
    let full = match colour.range {
        Some(2) => 1,
        Some(1) => 0,
        _ => full as u8,
    };
    let record = vec![
        1,
        0,
        0,
        0,
        profile as u8,
        0,
        (depth << 4) | (chroma << 1) | full,
        colour.primaries.unwrap_or(2),
        colour.transfer.unwrap_or(2),
        colour.matrix.unwrap_or(matrix),
        0,
        0,
    ];
    Some((record, profile as u8))
}

/// An MPEG-4 descriptor: its tag, its length (one byte under 128, else the
/// four-byte form) and its body.
fn descriptor(tag: u8, body: &[u8]) -> Vec<u8> {
    let len = body.len() as u32;
    let mut out = vec![tag];
    if len < 128 {
        out.push(len as u8);
    } else {
        for shift in [21, 14, 7] {
            out.push(0x80 | ((len >> shift) & 0x7F) as u8);
        }
        out.push((len & 0x7F) as u8);
    }
    out.extend_from_slice(body);
    out
}

/// The ES_Descriptor an AAC format description's cookie must be: ES_ID 1,
/// a DecoderConfigDescriptor (MPEG-4 audio, an audio stream) holding the
/// AudioSpecificConfig, and the predefined SLConfig.
pub(crate) fn esds(asc: &[u8]) -> Vec<u8> {
    let mut config = vec![0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    config.extend(descriptor(0x05, asc));
    let mut es = vec![0, 1, 0];
    es.extend(descriptor(0x04, &config));
    es.extend(descriptor(0x06, &[0x02]));
    descriptor(0x03, &es)
}

/// The 48 kHz samples in one Opus packet, from its TOC byte and, for code
/// 3, its frame count byte (RFC 6716 §3.1). A packet too short to say is
/// one 20 ms frame, Opus's usual.
pub(crate) fn opus_samples(packet: &[u8]) -> u32 {
    let Some(&toc) = packet.first() else {
        return 960;
    };
    let config = toc >> 3;
    let frame: u32 = match config {
        0..=11 => [480, 960, 1920, 2880][usize::from(config % 4)],
        12..=15 => [480, 960][usize::from(config % 2)],
        _ => [120, 240, 480, 960][usize::from(config % 4)],
    };
    let count = match toc & 3 {
        0 => 1,
        1 | 2 => 2,
        _ => packet.get(1).map_or(1, |m| u32::from(m & 0x3F).max(1)),
    };
    // A packet holds at most 120 ms (§3.2.5).
    (frame * count).min(5760)
}

/// Lowercase hex, two digits a byte.
pub(crate) fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
