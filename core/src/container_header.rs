//! The EBML side of a WebM or Matroska file being imported (spec §11
//! #216-R): the variable-length integers, element headers and element bodies
//! every read is made of, the file read forward through a buffer (`Source`)
//! with its position kept so no read passes its end, and the header that
//! comes before the first Cluster — the EBML header and its DocType, the
//! Segment (an unknown size allowed: a live browser recording writes one),
//! Info's TimestampScale and every TrackEntry in Tracks.
//!
//! A header element that cannot be read refuses the file in a lowercase
//! sentence naming it; the Cluster walk that follows is
//! `container_blocks.rs`, and `container.rs` picks the tracks. Cut out of
//! `container.rs` under the 400-line cap for a new file.

use std::fs::File;
use std::io::{BufReader, Read, Seek, SeekFrom};
use std::os::unix::fs::FileExt;

use crate::container_codec::{Colour, Mastering};

const EBML: u32 = 0x1A45_DFA3;
const DOC_TYPE: u32 = 0x4282;
const SEGMENT: u32 = 0x1853_8067;
const INFO: u32 = 0x1549_A966;
const TIMESTAMP_SCALE: u32 = 0x2A_D7B1;
const TRACKS: u32 = 0x1654_AE6B;
const TRACK_ENTRY: u32 = 0xAE;
const CLUSTER: u32 = 0x1F43_B675;

/// A header element larger than this is not a header a muxer wrote.
const MAX_HEADER: u64 = 16 << 20;
/// The largest CodecPrivate read (spec §11 #216-R): a real one is a few
/// hundred bytes.
const MAX_PRIVATE: usize = 1 << 20;

// ---- reading ------------------------------------------------------------

/// Something EBML's variable-length integers can be read out of.
pub(crate) trait Bytes {
    fn byte(&mut self) -> Option<u8>;
}

/// A variable-length integer: its value without the length marker, its
/// length in bytes, and whether every value bit is set (an unknown size).
pub(crate) fn read_vint(src: &mut impl Bytes) -> Option<(u64, usize, bool)> {
    let first = src.byte()?;
    let len = first.leading_zeros() as usize + 1;
    if len > 8 {
        return None;
    }
    let mask = if len == 8 { 0 } else { 0xFFu8 >> len };
    let mut value = u64::from(first & mask);
    let mut all_ones = first & mask == mask;
    for _ in 1..len {
        let b = src.byte()?;
        all_ones &= b == 0xFF;
        value = (value << 8) | u64::from(b);
    }
    Some((value, len, all_ones))
}

/// An element ID, its length marker kept, as the spec writes IDs.
pub(crate) fn read_id(src: &mut impl Bytes) -> Option<u32> {
    let first = src.byte()?;
    let len = first.leading_zeros() as usize + 1;
    if len > 4 {
        return None;
    }
    let mut id = u32::from(first);
    for _ in 1..len {
        id = (id << 8) | u32::from(src.byte()?);
    }
    Some(id)
}

/// An element header: its ID and its size, `None` for an unknown size.
pub(crate) fn read_header(src: &mut impl Bytes) -> Option<(u32, Option<u64>)> {
    let id = read_id(src)?;
    let (size, _, unknown) = read_vint(src)?;
    Some((id, if unknown { None } else { Some(size) }))
}

/// The file, read forward through a buffer, with its position kept so a
/// read can never pass its end.
pub(crate) struct Source {
    reader: BufReader<File>,
    pub(crate) pos: u64,
    pub(crate) len: u64,
}

impl Bytes for Source {
    fn byte(&mut self) -> Option<u8> {
        let mut b = [0u8];
        if self.pos >= self.len || self.reader.read_exact(&mut b).is_err() {
            return None;
        }
        self.pos += 1;
        Some(b[0])
    }
}

impl Source {
    /// `file`, `len` bytes long, read from its start.
    pub(crate) fn new(file: File, len: u64) -> Source {
        Source {
            reader: BufReader::with_capacity(1 << 16, file),
            pos: 0,
            len,
        }
    }

    pub(crate) fn skip(&mut self, n: u64) -> Option<()> {
        let to = self.pos.checked_add(n).filter(|to| *to <= self.len)?;
        self.reader.seek_relative(i64::try_from(n).ok()?).ok()?;
        self.pos = to;
        Some(())
    }

    pub(crate) fn seek(&mut self, to: u64) -> Option<()> {
        self.reader.seek(SeekFrom::Start(to)).ok()?;
        self.pos = to;
        Some(())
    }

    fn read(&mut self, n: u64) -> Option<Vec<u8>> {
        self.pos.checked_add(n).filter(|to| *to <= self.len)?;
        let mut out = vec![0u8; usize::try_from(n).ok()?];
        self.reader.read_exact(&mut out).ok()?;
        self.pos += n;
        Some(out)
    }

    /// A big-endian unsigned integer element body of `n` bytes.
    pub(crate) fn read_uint(&mut self, n: u64) -> Option<u64> {
        Some(uint(&self.read(n).filter(|_| n <= 8)?))
    }

    /// Up to `n` bytes at `at`, without moving the forward position.
    pub(crate) fn read_at(&self, at: u64, n: usize) -> Option<Vec<u8>> {
        let n = n.min(usize::try_from(self.len.checked_sub(at)?).ok()?);
        let mut out = vec![0u8; n];
        self.reader.get_ref().read_exact_at(&mut out, at).ok()?;
        Some(out)
    }
}

/// An in-memory element body, read the same way.
struct Cursor<'a> {
    data: &'a [u8],
    pos: usize,
}

impl Bytes for Cursor<'_> {
    fn byte(&mut self) -> Option<u8> {
        let b = *self.data.get(self.pos)?;
        self.pos += 1;
        Some(b)
    }
}

/// The children of an in-memory master element, as (ID, body).
fn children<'a>(data: &'a [u8], what: &str) -> Result<Vec<(u32, &'a [u8])>, String> {
    let mut c = Cursor { data, pos: 0 };
    let mut out = Vec::new();
    while c.pos < data.len() {
        let malformed = || format!("its {what} element is malformed");
        let (id, size) = read_header(&mut c).ok_or_else(malformed)?;
        let size = size
            .and_then(|s| usize::try_from(s).ok())
            .ok_or_else(malformed)?;
        let end = c.pos.checked_add(size).filter(|e| *e <= data.len());
        let end = end.ok_or_else(malformed)?;
        out.push((id, &data[c.pos..end]));
        c.pos = end;
    }
    Ok(out)
}

fn uint(body: &[u8]) -> u64 {
    body.iter().take(8).fold(0, |v, b| (v << 8) | u64::from(*b))
}

fn float(body: &[u8]) -> f64 {
    match body.len() {
        4 => f64::from(f32::from_be_bytes([body[0], body[1], body[2], body[3]])),
        8 => f64::from_be_bytes(body.try_into().unwrap_or([0; 8])),
        _ => 0.0,
    }
}

fn text(body: &[u8]) -> String {
    let end = body.iter().position(|b| *b == 0).unwrap_or(body.len());
    String::from_utf8_lossy(&body[..end]).into_owned()
}

// ---- the header ---------------------------------------------------------

/// One TrackEntry, as much of it as the copy needs.
#[derive(Default)]
pub(crate) struct Entry {
    pub(crate) number: u64,
    pub(crate) kind: u64,
    pub(crate) codec_id: String,
    pub(crate) private: Vec<u8>,
    pub(crate) default_duration: Option<u64>,
    pub(crate) codec_delay: u64,
    pub(crate) encoded: bool,
    pub(crate) width: u64,
    pub(crate) height: u64,
    pub(crate) colour: Colour,
    pub(crate) rate: f64,
    pub(crate) channels: u64,
}

fn entry(body: &[u8]) -> Result<Entry, String> {
    let mut e = Entry {
        rate: 8000.0,
        channels: 1,
        ..Entry::default()
    };
    for (id, b) in children(body, "TrackEntry")? {
        match id {
            0xD7 => e.number = uint(b),
            0x83 => e.kind = uint(b),
            0x86 => e.codec_id = text(b),
            0x63A2 => e.private = b.to_vec(),
            0x23_E383 => e.default_duration = Some(uint(b)).filter(|d| *d > 0),
            0x56AA => e.codec_delay = uint(b),
            0x6D80 => e.encoded = true,
            0xE0 => video_settings(&mut e, b)?,
            0xE1 => {
                for (id, b) in children(b, "Audio")? {
                    match id {
                        0xB5 => e.rate = float(b),
                        0x9F => e.channels = uint(b),
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }
    if e.private.len() > MAX_PRIVATE {
        let (n, size) = (e.number, e.private.len());
        return Err(format!(
            "track {n}'s CodecPrivate is {size} bytes, over the 1 MiB limit"
        ));
    }
    Ok(e)
}

fn video_settings(e: &mut Entry, body: &[u8]) -> Result<(), String> {
    for (id, b) in children(body, "Video")? {
        match id {
            0xB0 => e.width = uint(b),
            0xBA => e.height = uint(b),
            0x55B0 => {
                for (id, b) in children(b, "Colour")? {
                    let v = u8::try_from(uint(b)).ok();
                    match id {
                        0x55B1 => e.colour.matrix = v,
                        0x55B9 => e.colour.range = v,
                        0x55BA => e.colour.transfer = v,
                        0x55BB => e.colour.primaries = v,
                        0x55BC => e.colour.max_cll = Some(uint(b)),
                        0x55BD => e.colour.max_fall = Some(uint(b)),
                        0x55D0 => e.colour.mastering = mastering(b),
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }
    Ok(())
}

/// A MasteringMetadata element's floats (RFC 9559; spec §11 HD-18 (a)), an
/// absent child 0; `None` when its children cannot be read, so a damaged one
/// is ignored, never a refusal.
fn mastering(body: &[u8]) -> Option<Mastering> {
    let mut m = Mastering::default();
    for (id, b) in children(body, "MasteringMetadata").ok()? {
        let v = float(b);
        match id {
            0x55D1 => m.red.0 = v,
            0x55D2 => m.red.1 = v,
            0x55D3 => m.green.0 = v,
            0x55D4 => m.green.1 = v,
            0x55D5 => m.blue.0 = v,
            0x55D6 => m.blue.1 = v,
            0x55D7 => m.white.0 = v,
            0x55D8 => m.white.1 = v,
            0x55D9 => m.luminance_max = v,
            0x55DA => m.luminance_min = v,
            _ => {}
        }
    }
    Some(m)
}

/// What `open` read before the first Cluster.
pub(crate) struct Header {
    pub(crate) doc_type: String,
    pub(crate) scale: u64,
    pub(crate) entries: Vec<Entry>,
    pub(crate) first_cluster: Option<u64>,
    pub(crate) end: u64,
}

pub(crate) fn header(src: &mut Source) -> Result<Header, String> {
    let not_ebml = || "it does not begin with an EBML header".to_string();
    let (id, size) = read_header(src).ok_or_else(not_ebml)?;
    let size = size
        .filter(|s| id == EBML && *s <= 4096)
        .ok_or_else(not_ebml)?;
    let body = src.read(size).ok_or_else(not_ebml)?;
    let doc = children(&body, "EBML header")?;
    let doc_type = doc
        .iter()
        .find(|(id, _)| *id == DOC_TYPE)
        .map(|(_, b)| text(b));
    let doc_type = doc_type.unwrap_or_else(|| "matroska".to_string());
    if doc_type != "webm" && doc_type != "matroska" {
        return Err(format!("its DocType is “{doc_type}”, not webm or matroska"));
    }
    let end = loop {
        let (id, size) = read_header(src).ok_or("it has no Segment")?;
        if id == SEGMENT {
            break size
                .and_then(|s| src.pos.checked_add(s))
                .map_or(src.len, |e| e.min(src.len));
        }
        src.skip(size.ok_or("it has no Segment")?)
            .ok_or("it has no Segment")?;
    };
    let mut head = Header {
        doc_type,
        scale: 1_000_000,
        entries: Vec::new(),
        first_cluster: None,
        end,
    };
    let mut tracks = false;
    while src.pos < end {
        let start = src.pos;
        let Some((id, size)) = read_header(src) else {
            break;
        };
        if id == CLUSTER {
            head.first_cluster = Some(start);
            break;
        }
        let Some(size) = size else {
            return Err(format!(
                "its element {id:X} before the first Cluster has no size"
            ));
        };
        match id {
            INFO | TRACKS => {
                let name = if id == INFO { "Info" } else { "Tracks" };
                if size > MAX_HEADER {
                    return Err(format!("its {name} element is {size} bytes, over 16 MiB"));
                }
                let body = src
                    .read(size)
                    .ok_or(format!("its {name} element is cut short"))?;
                let found = children(&body, name)?;
                if id == INFO {
                    let scale = found.iter().find(|(id, _)| *id == TIMESTAMP_SCALE);
                    head.scale = scale.map_or(1_000_000, |(_, b)| uint(b));
                    if head.scale == 0 {
                        return Err("its TimestampScale is 0".to_string());
                    }
                } else {
                    tracks = true;
                    for (_, b) in found.iter().filter(|(id, _)| *id == TRACK_ENTRY) {
                        head.entries.push(entry(b)?);
                    }
                }
            }
            _ if src.skip(size).is_none() => break,
            _ => {}
        }
    }
    if !tracks {
        return Err("it has no Tracks element before its first Cluster".to_string());
    }
    Ok(head)
}
