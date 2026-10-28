//! The write side of EBML for the WebM writer (spec §11 CX-15 (3)): the
//! element IDs it writes, the variable-length sizes, the element encoders and
//! the builders for every level-1 element but the Clusters, which
//! `webm_writer.rs` streams.
//!
//! Every builder answers whole bytes, so `webm_writer.rs` only places them.
//! IDs are written as the Matroska specification spells them (RFC 9559, RFC
//! 8794), marker bits included. A size is the shortest vint that holds it,
//! except where a size is patched later, which is always 8 bytes.

use crate::container_codec::Mastering;

// ---- element IDs -----------------------------------------------------------

pub(crate) const EBML: u32 = 0x1A45_DFA3;
const EBML_VERSION: u32 = 0x4286;
const EBML_READ_VERSION: u32 = 0x42F7;
const EBML_MAX_ID_LENGTH: u32 = 0x42F2;
const EBML_MAX_SIZE_LENGTH: u32 = 0x42F3;
const DOC_TYPE: u32 = 0x4282;
const DOC_TYPE_VERSION: u32 = 0x4287;
const DOC_TYPE_READ_VERSION: u32 = 0x4285;
pub(crate) const SEGMENT: u32 = 0x1853_8067;
pub(crate) const SEEK_HEAD: u32 = 0x114D_9B74;
const SEEK: u32 = 0x4DBB;
const SEEK_ID: u32 = 0x53AB;
const SEEK_POSITION: u32 = 0x53AC;
pub(crate) const VOID: u32 = 0xEC;
pub(crate) const INFO: u32 = 0x1549_A966;
const TIMESTAMP_SCALE: u32 = 0x2A_D7B1;
const DURATION: u32 = 0x4489;
const MUXING_APP: u32 = 0x4D80;
const WRITING_APP: u32 = 0x5741;
pub(crate) const TRACKS: u32 = 0x1654_AE6B;
const TRACK_ENTRY: u32 = 0xAE;
const TRACK_NUMBER: u32 = 0xD7;
const TRACK_UID: u32 = 0x73C5;
const TRACK_TYPE: u32 = 0x83;
const FLAG_LACING: u32 = 0x9C;
const CODEC_ID: u32 = 0x86;
const CODEC_PRIVATE: u32 = 0x63A2;
const DEFAULT_DURATION: u32 = 0x23_E383;
const CODEC_DELAY: u32 = 0x56AA;
const SEEK_PRE_ROLL: u32 = 0x56BB;
const VIDEO: u32 = 0xE0;
const PIXEL_WIDTH: u32 = 0xB0;
const PIXEL_HEIGHT: u32 = 0xBA;
const COLOUR: u32 = 0x55B0;
const MATRIX_COEFFICIENTS: u32 = 0x55B1;
const BITS_PER_CHANNEL: u32 = 0x55B2;
const RANGE: u32 = 0x55B9;
const TRANSFER_CHARACTERISTICS: u32 = 0x55BA;
const PRIMARIES: u32 = 0x55BB;
const MAX_CLL: u32 = 0x55BC;
const MAX_FALL: u32 = 0x55BD;
const MASTERING_METADATA: u32 = 0x55D0;
const PRIMARY_R_X: u32 = 0x55D1;
const PRIMARY_R_Y: u32 = 0x55D2;
const PRIMARY_G_X: u32 = 0x55D3;
const PRIMARY_G_Y: u32 = 0x55D4;
const PRIMARY_B_X: u32 = 0x55D5;
const PRIMARY_B_Y: u32 = 0x55D6;
const WHITE_POINT_X: u32 = 0x55D7;
const WHITE_POINT_Y: u32 = 0x55D8;
const LUMINANCE_MAX: u32 = 0x55D9;
const LUMINANCE_MIN: u32 = 0x55DA;
const AUDIO: u32 = 0xE1;
const SAMPLING_FREQUENCY: u32 = 0xB5;
const CHANNELS: u32 = 0x9F;
pub(crate) const CHAPTERS: u32 = 0x1043_A770;
const EDITION_ENTRY: u32 = 0x45B9;
const EDITION_UID: u32 = 0x45BC;
const CHAPTER_ATOM: u32 = 0xB6;
const CHAPTER_UID: u32 = 0x73C4;
const CHAPTER_TIME_START: u32 = 0x91;
const CHAPTER_TIME_END: u32 = 0x92;
const CHAPTER_DISPLAY: u32 = 0x80;
const CHAP_STRING: u32 = 0x85;
const CHAP_LANGUAGE: u32 = 0x437C;
pub(crate) const CLUSTER: u32 = 0x1F43_B675;
pub(crate) const TIMESTAMP: u32 = 0xE7;
pub(crate) const SIMPLE_BLOCK: u32 = 0xA3;
pub(crate) const BLOCK_GROUP: u32 = 0xA0;
const BLOCK: u32 = 0xA1;
const DISCARD_PADDING: u32 = 0x75A2;
pub(crate) const CUES: u32 = 0x1C53_BB6B;
const CUE_POINT: u32 = 0xBB;
const CUE_TIME: u32 = 0xB3;
const CUE_TRACK_POSITIONS: u32 = 0xB7;
const CUE_TRACK: u32 = 0xF7;
const CUE_CLUSTER_POSITION: u32 = 0xF1;

/// The eight-byte "unknown" size, written where a size is patched later.
pub(crate) const UNKNOWN_SIZE: [u8; 8] = [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];

// ---- encoders --------------------------------------------------------------

/// An element ID's bytes: its big-endian value without leading zero bytes.
pub(crate) fn id(id: u32) -> Vec<u8> {
    let bytes = id.to_be_bytes();
    let first = bytes.iter().position(|b| *b != 0).unwrap_or(3);
    bytes[first..].to_vec()
}

/// A size as the shortest vint that holds it; each length's all-ones value
/// is "unknown", so it is never used for a known size.
pub(crate) fn vint(n: u64) -> Vec<u8> {
    let Some(len) = (1..8usize).find(|len| n < (1u64 << (7 * len)) - 1) else {
        return size8(n).to_vec();
    };
    let mut out = n.to_be_bytes()[8 - len..].to_vec();
    out[0] |= 0x80 >> (len - 1);
    out
}

/// A size as an eight-byte vint, the form a patched size is written in.
/// Sizes past 2^56 − 2 do not occur: a file that large cannot be written.
pub(crate) fn size8(n: u64) -> [u8; 8] {
    let mut out = (n.min((1u64 << 56) - 2)).to_be_bytes();
    out[0] = 0x01;
    out
}

/// An element with `body` as its data.
pub(crate) fn binary(id_value: u32, body: &[u8]) -> Vec<u8> {
    let mut out = id(id_value);
    out.extend(vint(body.len() as u64));
    out.extend_from_slice(body);
    out
}

/// A master element holding `children` in order.
pub(crate) fn master(id_value: u32, children: &[Vec<u8>]) -> Vec<u8> {
    binary(id_value, &children.concat())
}

/// An unsigned integer in the fewest bytes (at least one).
pub(crate) fn uint(id_value: u32, v: u64) -> Vec<u8> {
    let bytes = v.to_be_bytes();
    let first = bytes.iter().position(|b| *b != 0).unwrap_or(7);
    binary(id_value, &bytes[first..])
}

/// A signed integer in the fewest bytes that keep its sign.
pub(crate) fn int(id_value: u32, v: i64) -> Vec<u8> {
    let bytes = v.to_be_bytes();
    // A leading byte is redundant when it is all sign and the next keeps it.
    let sign = |i: usize| (bytes[i] == 0 || bytes[i] == 0xFF) && (bytes[i] ^ bytes[i + 1]) < 0x80;
    let first = (0..7).find(|i| !sign(*i)).unwrap_or(7);
    binary(id_value, &bytes[first..])
}

/// A float as eight bytes, so a value read back is the value written.
pub(crate) fn float(id_value: u32, v: f64) -> Vec<u8> {
    binary(id_value, &v.to_be_bytes())
}

pub(crate) fn string(id_value: u32, s: &str) -> Vec<u8> {
    binary(id_value, s.as_bytes())
}

/// A Void element exactly `total` bytes long (at least 2).
pub(crate) fn void(total: usize) -> Vec<u8> {
    let (head, body) = if total >= 2 && total - 2 < 127 {
        (vec![VOID as u8, 0x80 | (total - 2) as u8], total - 2)
    } else {
        let body = total.saturating_sub(9);
        let mut head = vec![VOID as u8];
        head.extend(size8(body as u64));
        (head, body)
    };
    let mut out = head;
    out.resize(out.len() + body, 0);
    out
}

// ---- builders --------------------------------------------------------------

/// The EBML header: DocType `webm`, DocTypeVersion 4, DocTypeReadVersion 2.
pub(crate) fn ebml_header() -> Vec<u8> {
    master(
        EBML,
        &[
            uint(EBML_VERSION, 1),
            uint(EBML_READ_VERSION, 1),
            uint(EBML_MAX_ID_LENGTH, 4),
            uint(EBML_MAX_SIZE_LENGTH, 8),
            string(DOC_TYPE, "webm"),
            uint(DOC_TYPE_VERSION, 4),
            uint(DOC_TYPE_READ_VERSION, 2),
        ],
    )
}

/// Info: millisecond timestamps, the duration in them, and the app's name.
pub(crate) fn info(duration_ns: u64) -> Vec<u8> {
    master(
        INFO,
        &[
            uint(TIMESTAMP_SCALE, 1_000_000),
            float(DURATION, duration_ns as f64 / 1e6),
            string(MUXING_APP, "Frame Job"),
            string(WRITING_APP, "Frame Job"),
        ],
    )
}

/// The video track's Colour: CICP, range and depth, and on HDR10 the light
/// levels and the mastering display.
pub(crate) struct ColourOut {
    pub matrix: u8,
    pub range: u8,
    pub transfer: u8,
    pub primaries: u8,
    pub bits: u8,
    pub light: Option<(u64, u64)>,
    pub mastering: Option<Mastering>,
}

/// The video TrackEntry (number 1, UID 1).
pub(crate) fn video_entry(
    private: &[u8],
    width: u32,
    height: u32,
    default_duration_ns: u64,
    colour: &ColourOut,
) -> Vec<u8> {
    let mut c = vec![
        uint(MATRIX_COEFFICIENTS, colour.matrix.into()),
        uint(BITS_PER_CHANNEL, colour.bits.into()),
        uint(RANGE, colour.range.into()),
        uint(TRANSFER_CHARACTERISTICS, colour.transfer.into()),
        uint(PRIMARIES, colour.primaries.into()),
    ];
    if let Some((cll, fall)) = colour.light {
        c.push(uint(MAX_CLL, cll));
        c.push(uint(MAX_FALL, fall));
    }
    if let Some(m) = &colour.mastering {
        let fields = [
            float(PRIMARY_R_X, m.red.0),
            float(PRIMARY_R_Y, m.red.1),
            float(PRIMARY_G_X, m.green.0),
            float(PRIMARY_G_Y, m.green.1),
            float(PRIMARY_B_X, m.blue.0),
            float(PRIMARY_B_Y, m.blue.1),
            float(WHITE_POINT_X, m.white.0),
            float(WHITE_POINT_Y, m.white.1),
            float(LUMINANCE_MAX, m.luminance_max),
            float(LUMINANCE_MIN, m.luminance_min),
        ];
        c.push(master(MASTERING_METADATA, &fields));
    }
    let video = master(
        VIDEO,
        &[
            uint(PIXEL_WIDTH, width.into()),
            uint(PIXEL_HEIGHT, height.into()),
            master(COLOUR, &c),
        ],
    );
    master(
        TRACK_ENTRY,
        &[
            uint(TRACK_NUMBER, 1),
            uint(TRACK_UID, 1),
            uint(TRACK_TYPE, 1),
            uint(FLAG_LACING, 0),
            string(CODEC_ID, "V_AV1"),
            binary(CODEC_PRIVATE, private),
            uint(DEFAULT_DURATION, default_duration_ns),
            video,
        ],
    )
}

/// OpusHead version 1 (RFC 7845 §5.1): 48 kHz input, gain 0, family 0.
pub(crate) fn opus_head(channels: u8, pre_skip: u16) -> Vec<u8> {
    let mut out = b"OpusHead".to_vec();
    out.push(1);
    out.push(channels);
    out.extend(pre_skip.to_le_bytes());
    out.extend(48_000u32.to_le_bytes());
    out.extend(0i16.to_le_bytes());
    out.push(0);
    out
}

/// The audio TrackEntry (number 2, UID 2): Opus with its CodecDelay and the
/// 80 ms SeekPreRoll RFC 7845 asks for.
pub(crate) fn audio_entry(channels: u8, pre_skip: u16) -> Vec<u8> {
    let delay_ns = (u64::from(pre_skip) * 1_000_000_000 + 24_000) / 48_000;
    master(
        TRACK_ENTRY,
        &[
            uint(TRACK_NUMBER, 2),
            uint(TRACK_UID, 2),
            uint(TRACK_TYPE, 2),
            uint(FLAG_LACING, 0),
            string(CODEC_ID, "A_OPUS"),
            binary(CODEC_PRIVATE, &opus_head(channels, pre_skip)),
            uint(CODEC_DELAY, delay_ns),
            uint(SEEK_PRE_ROLL, 80_000_000),
            master(
                AUDIO,
                &[
                    float(SAMPLING_FREQUENCY, 48_000.0),
                    uint(CHANNELS, channels.into()),
                ],
            ),
        ],
    )
}

/// One EditionEntry (UID 1) of ChapterAtoms (UID i + 1), times in ns.
pub(crate) fn chapters(list: &[(u64, u64, &str)]) -> Vec<u8> {
    let atoms: Vec<Vec<u8>> = list
        .iter()
        .enumerate()
        .map(|(i, (start, end, name))| {
            master(
                CHAPTER_ATOM,
                &[
                    uint(CHAPTER_UID, i as u64 + 1),
                    uint(CHAPTER_TIME_START, *start),
                    uint(CHAPTER_TIME_END, *end),
                    master(
                        CHAPTER_DISPLAY,
                        &[string(CHAP_STRING, name), string(CHAP_LANGUAGE, "und")],
                    ),
                ],
            )
        })
        .collect();
    let mut edition = vec![uint(EDITION_UID, 1)];
    edition.extend(atoms);
    master(CHAPTERS, &[master(EDITION_ENTRY, &edition)])
}

/// A SeekHead of (element ID, position in the Segment's data) entries. Each
/// SeekID is four bytes and each SeekPosition eight, so its length is fixed
/// by the entry count: 5 + 21 × entries bytes.
pub(crate) fn seek_head(entries: &[(u32, u64)]) -> Vec<u8> {
    let seeks: Vec<Vec<u8>> = entries
        .iter()
        .map(|(target, pos)| {
            master(
                SEEK,
                &[
                    binary(SEEK_ID, &target.to_be_bytes()),
                    binary(SEEK_POSITION, &pos.to_be_bytes()),
                ],
            )
        })
        .collect();
    master(SEEK_HEAD, &seeks)
}

/// Cues of (time in ms, Cluster position in the Segment's data), track 1.
pub(crate) fn cues(points: &[(u64, u64)]) -> Vec<u8> {
    let points: Vec<Vec<u8>> = points
        .iter()
        .map(|(time, pos)| {
            master(
                CUE_POINT,
                &[
                    uint(CUE_TIME, *time),
                    master(
                        CUE_TRACK_POSITIONS,
                        &[uint(CUE_TRACK, 1), uint(CUE_CLUSTER_POSITION, *pos)],
                    ),
                ],
            )
        })
        .collect();
    master(CUES, &points)
}

/// A block's body: the track number, the time relative to its Cluster and
/// the flags, then the frame (no lacing).
pub(crate) fn block_body(track: u32, relative_ms: i16, flags: u8, bytes: &[u8]) -> Vec<u8> {
    let mut out = vint(track.into());
    out.extend(relative_ms.to_be_bytes());
    out.push(flags);
    out.extend_from_slice(bytes);
    out
}

/// A BlockGroup carrying `body` as its Block and a DiscardPadding in ns.
pub(crate) fn block_group(body: &[u8], discard_padding_ns: i64) -> Vec<u8> {
    master(
        BLOCK_GROUP,
        &[
            binary(BLOCK, body),
            int(DISCARD_PADDING, discard_padding_ns),
        ],
    )
}
