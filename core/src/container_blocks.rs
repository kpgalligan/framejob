//! The Cluster walk (spec §11 #216-R): every frame of the two tracks
//! `container.rs` picked, as an index entry — where its bytes are, how many,
//! its Block's time, its place in the Block's lace and whether it is a
//! keyframe. It reads element headers, Block headers and lace sizes, and
//! skips every payload unread.
//!
//! A Cluster of unknown size (a live recording's, written before its length
//! was known) ends at the next level-1 element. A SimpleBlock is a keyframe
//! by its flag; a BlockGroup's Block is one when the group holds no
//! ReferenceBlock. Xiph, EBML and fixed lacing are read. A frame of no bytes
//! is not indexed.
//!
//! **A damaged or truncated tail ends the index**: an element header that
//! cannot be read, a Block whose lace does not add up, or a payload running
//! past the end of the file stops the walk, and what was read before it is
//! kept — so a file cut off part-way imports shorter rather than not at all.

use crate::container_header::{read_header, read_vint, Bytes, Source};

/// One frame of a copied track.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Frame {
    pub offset: u64,
    pub size: u32,
    /// Its Block's time in nanoseconds (Cluster time + Block time, scaled).
    pub ns: i64,
    /// Its place in the Block's lace; 0 when the Block is not laced.
    pub lace: u16,
    /// The first frame the index kept from its Block: a zero-byte lace frame
    /// is skipped, so frame 0 of a lace may be missing.
    pub first: bool,
    pub key: bool,
}

const CLUSTER: u32 = 0x1F43_B675;
const TIMESTAMP: u32 = 0xE7;
const SIMPLE_BLOCK: u32 = 0xA3;
const BLOCK_GROUP: u32 = 0xA0;
const BLOCK: u32 = 0xA1;
const REFERENCE_BLOCK: u32 = 0xFB;
const EBML: u32 = 0x1A45_DFA3;
const SEGMENT: u32 = 0x1853_8067;

/// The IDs that may follow a Cluster at the Segment's level, and so end one
/// of unknown size; the EBML header and a Segment end the file's walk.
const LEVEL_ONE: [u32; 10] = [
    0x114D_9B74, // SeekHead
    0x1549_A966, // Info
    0x1654_AE6B, // Tracks
    CLUSTER,
    0x1C53_BB6B, // Cues
    0x1043_A770, // Chapters
    0x1254_C367, // Tags
    0x1941_A469, // Attachments
    EBML,
    SEGMENT,
];

/// More frames than any real file holds (92 hours at 60 fps): the walk stops
/// there rather than let a hostile file size the index.
const MAX_FRAMES: usize = 20_000_000;

/// How a Cluster ended.
enum Step {
    /// Read to its end; the next level-1 element is unread.
    Next,
    /// An unknown-size Cluster ended at this element, whose header is read.
    Header(u32, Option<u64>),
    /// The file ended or could not be read further.
    Stop,
}

/// What one walk is collecting.
struct Walk {
    end: u64,
    scale: i128,
    wanted: [Option<u64>; 2],
    out: [Vec<Frame>; 2],
}

/// Walks from the Cluster at `start` to `end`, indexing the frames of the
/// track numbers in `wanted` (video, audio) into the matching vector.
pub(crate) fn walk(
    src: &mut Source,
    start: u64,
    end: u64,
    scale: u64,
    wanted: [Option<u64>; 2],
) -> [Vec<Frame>; 2] {
    let mut w = Walk {
        end,
        scale: i128::from(scale),
        wanted,
        out: [Vec::new(), Vec::new()],
    };
    if src.seek(start).is_none() {
        return w.out;
    }
    let mut pending = None;
    loop {
        let (id, size) = match pending.take() {
            Some(header) => header,
            None if src.pos >= end => break,
            None => match read_header(src) {
                Some(header) => header,
                None => break,
            },
        };
        if id == CLUSTER {
            match cluster(src, size, &mut w) {
                Step::Next => {}
                Step::Header(id, size) => pending = Some((id, size)),
                Step::Stop => break,
            }
        } else if id == EBML || id == SEGMENT {
            // A second EBML document or Segment is not this file's.
            break;
        } else {
            match size {
                Some(n) if src.skip(n).is_some() => {}
                _ => break,
            }
        }
    }
    w.out
}

fn cluster(src: &mut Source, size: Option<u64>, w: &mut Walk) -> Step {
    let cluster_end = size.map(|n| src.pos.saturating_add(n).min(w.end));
    let mut time: u64 = 0;
    loop {
        let at_end = cluster_end.map_or(src.pos >= w.end, |e| src.pos >= e);
        if at_end {
            return Step::Next;
        }
        let Some((id, size)) = read_header(src) else {
            return Step::Stop;
        };
        if cluster_end.is_none() && LEVEL_ONE.contains(&id) {
            return Step::Header(id, size);
        }
        let Some(size) = size else {
            return Step::Stop;
        };
        let read = match id {
            TIMESTAMP => src.read_uint(size).map(|t| time = t),
            SIMPLE_BLOCK => block(src, size, time, w).map(|parsed| {
                if let Some(b) = parsed {
                    let key = b.flags & 0x80 != 0;
                    b.push(w, key);
                }
            }),
            BLOCK_GROUP => group(src, size, time, w),
            _ => src.skip(size),
        };
        if read.is_none() || w.out.iter().any(|v| v.len() >= MAX_FRAMES) {
            return Step::Stop;
        }
    }
}

fn group(src: &mut Source, size: u64, time: u64, w: &mut Walk) -> Option<()> {
    let end = src.pos.checked_add(size)?;
    let mut parsed = None;
    let mut referenced = false;
    while src.pos < end {
        let (id, size) = read_header(src)?;
        let size = size?;
        match id {
            BLOCK => parsed = block(src, size, time, w)?,
            REFERENCE_BLOCK => {
                referenced = true;
                src.skip(size)?;
            }
            _ => src.skip(size)?,
        }
    }
    if let Some(b) = parsed {
        b.push(w, !referenced);
    }
    Some(())
}

/// A Block of a wanted track, its lace read and its payload skipped.
struct Parsed {
    slot: usize,
    ns: i64,
    flags: u8,
    frames: Vec<(u64, u64)>,
}

impl Parsed {
    fn push(self, w: &mut Walk, key: bool) {
        let mut first = true;
        for (lace, (offset, size)) in self.frames.into_iter().enumerate() {
            let Ok(size) = u32::try_from(size) else {
                continue;
            };
            if size == 0 {
                continue;
            }
            w.out[self.slot].push(Frame {
                offset,
                size,
                ns: self.ns,
                lace: lace as u16,
                first,
                key,
            });
            first = false;
        }
    }
}

/// Reads a Block's header; `Some(None)` for a track nobody wanted, `None`
/// when the Block cannot be read whole.
fn block(src: &mut Source, size: u64, time: u64, w: &Walk) -> Option<Option<Parsed>> {
    let start = src.pos;
    let end = start.checked_add(size).filter(|e| *e <= src.len)?;
    let (track, _, _) = read_vint(src)?;
    let rel = i16::from_be_bytes([src.byte()?, src.byte()?]);
    let flags = src.byte()?;
    let Some(slot) = w.wanted.iter().position(|t| *t == Some(track)) else {
        src.skip(end.checked_sub(src.pos)?)?;
        return Some(None);
    };
    let ns = (i128::from(time) + i128::from(rel)).checked_mul(w.scale)?;
    let ns = i64::try_from(ns).ok()?;
    let sizes = lace_sizes(src, (flags >> 1) & 3, end)?;
    let mut offset = src.pos;
    let mut frames = Vec::with_capacity(sizes.len());
    for size in sizes {
        frames.push((offset, size));
        offset = offset.checked_add(size)?;
    }
    if offset != end {
        return None;
    }
    src.skip(end - src.pos)?;
    Some(Some(Parsed {
        slot,
        ns,
        flags,
        frames,
    }))
}

/// The frame sizes of a Block whose payload ends at `end`, reading its lace
/// header: none (one frame), Xiph (1), fixed (2) or EBML (3).
fn lace_sizes(src: &mut Source, lacing: u8, end: u64) -> Option<Vec<u64>> {
    if lacing == 0 {
        return Some(vec![end.checked_sub(src.pos)?]);
    }
    let count = usize::from(src.byte()?) + 1;
    let mut sizes: Vec<u64> = Vec::with_capacity(count);
    match lacing {
        1 => {
            for _ in 1..count {
                let mut size = 0u64;
                loop {
                    let b = src.byte()?;
                    size += u64::from(b);
                    if b != 255 {
                        break;
                    }
                }
                sizes.push(size);
            }
        }
        3 => {
            let (first, _, _) = read_vint(src)?;
            sizes.push(first);
            for _ in 2..count {
                let (raw, len, _) = read_vint(src)?;
                // A signed lace delta: the value less half its range.
                let bias = (1i128 << (7 * len - 1)) - 1;
                let prev = i128::from(*sizes.last()?);
                sizes.push(u64::try_from(prev + i128::from(raw) - bias).ok()?);
            }
        }
        _ => {
            let total = end.checked_sub(src.pos)?;
            let each = total / count as u64;
            if each * count as u64 != total {
                return None;
            }
            return Some(vec![each; count]);
        }
    }
    let used = sizes.iter().try_fold(0u64, |sum, s| sum.checked_add(*s))?;
    sizes.push(end.checked_sub(src.pos)?.checked_sub(used)?);
    Some(sizes)
}
