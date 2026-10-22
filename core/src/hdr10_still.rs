//! A PQ still's HDR10 peak (spec §11 HD-20 (b)): a pure reader of the two
//! places a still image carries HDR10 static metadata, from the file's bytes
//! Swift hands it, so import reads a PQ PNG, HEIF or AVIF as it reads a PQ
//! video (`hdr10.rs`, whose arithmetic and choice it shares). Reached through
//! `rc_hdr10_still_peak` (`ffi_hdr10.rs`); what the answer becomes on the
//! media is `media_color.rs`'s.
//!
//! - **PNG** (W3C PNG third edition §11.3.2.7, §11.3.2.8): the chunks before
//!   the first `IDAT`, the first `cLLI` (8 bytes or more; MaxCLL a
//!   big-endian u32 in 0.0001 cd/m², then MaxFALL) and the first `mDCV` (24
//!   bytes or more; ST 2086's order, its maximum luminance a big-endian u32
//!   in 0.0001 cd/m² at bytes 16–19). CRCs are not checked.
//! - **ISOBMFF** (HEIF and AVIF, `ftyp` at bytes 4–8; ISO/IEC 23008-12
//!   §9.3): the first top-level `meta` (a FullBox) gives its `pitm` (the
//!   primary item's id, a u16 at version 0, else a u32) and its `iprp`,
//!   whose `ipco` holds the properties (1-based) and whose `ipma` (a FullBox)
//!   the associations: an entry's item id a u16 at version 0, else a u32; a
//!   u8 `association_count`; each association a u16 when `flags & 1`, else
//!   a u8, its index the low 15 or low 7 bits. Among the primary item's
//!   properties, the first `clli` (4 bytes or more, CTA-861.3's MaxCLL) and
//!   the first `mdcv` (24 bytes or more, ST 2086). A box size of 1 means a
//!   64-bit size follows, 0 that the box runs to its parent's end, and a box
//!   past its parent's end ends the walk. An AV1 item's `av1C` OBUs are not
//!   read.
//!
//! MaxCLL when present and non-zero, else the mastering maximum, else `{}`
//! (`hdr10::choose`); any other file reads `{}`. Every index is
//! bounds-checked: no input panics, a short or malformed file reads nothing.

use crate::hdr10::{choose, mastering_max, max_cll, ten_thousandths};
use crate::model_media_color::PqColor;

/// A PNG file's first eight bytes.
const PNG_SIGNATURE: [u8; 8] = [0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
/// A PNG chunk's length and type, before its data; its CRC, after.
const PNG_CHUNK_HEADER: usize = 8;
const PNG_CHUNK_CRC: usize = 4;
/// The bytes each PNG chunk must hold to be read.
const CLLI_PNG_BYTES: usize = 8;
const MDCV_BYTES: usize = 24;
/// The bytes an ISOBMFF `clli` must hold to be read.
const CLLI_BOX_BYTES: usize = 4;
/// An ISOBMFF box's size and type, and the 64-bit size that follows when the
/// size is 1.
const BOX_HEADER: usize = 8;
const BOX_LARGE_HEADER: usize = 16;
/// A FullBox's version and flags, before its body.
const FULL_BOX_HEADER: usize = 4;

/// The peak of a still image's file: a PNG's `cLLI`/`mDCV`, an ISOBMFF
/// file's primary item's `clli`/`mdcv`, else nothing. `peak` is always
/// `None`: the override is the person's, never the file's.
pub fn still_peak(file: &[u8]) -> PqColor {
    if file.starts_with(&PNG_SIGNATURE) {
        return png_peak(file);
    }
    if file.get(4..8) == Some(b"ftyp".as_slice()) {
        return isobmff_peak(file);
    }
    PqColor::default()
}

/// The first of each reading seen (its value, which may be none).
#[derive(Default)]
struct Readings {
    mastering: Option<Option<u32>>,
    light: Option<Option<u32>>,
}

impl Readings {
    fn answer(self) -> PqColor {
        choose(self.mastering.flatten(), self.light.flatten())
    }
}

/// A big-endian u32 at `at`, if the bytes hold one.
fn be_u32(bytes: &[u8], at: usize) -> Option<u32> {
    let field: [u8; 4] = bytes.get(at..at.checked_add(4)?)?.try_into().ok()?;
    Some(u32::from_be_bytes(field))
}

/// A big-endian u16 at `at`, if the bytes hold one.
fn be_u16(bytes: &[u8], at: usize) -> Option<u16> {
    let field: [u8; 2] = bytes.get(at..at.checked_add(2)?)?.try_into().ok()?;
    Some(u16::from_be_bytes(field))
}

/// A PNG's chunks up to the first `IDAT`: the first `cLLI` and the first
/// `mDCV` long enough to read. A chunk past the end ends the walk.
fn png_peak(file: &[u8]) -> PqColor {
    let mut readings = Readings::default();
    let mut at = PNG_SIGNATURE.len();
    while let (Some(length), Some(kind)) = (
        be_u32(file, at),
        file.get(at + 4..at.saturating_add(PNG_CHUNK_HEADER)),
    ) {
        let start = at + PNG_CHUNK_HEADER;
        let Some(end) = usize::try_from(length)
            .ok()
            .and_then(|length| start.checked_add(length))
        else {
            break;
        };
        let Some(data) = file.get(start..end) else {
            break;
        };
        match kind {
            b"IDAT" => break,
            b"cLLI" if data.len() >= CLLI_PNG_BYTES => {
                readings
                    .light
                    .get_or_insert(be_u32(data, 0).and_then(ten_thousandths));
            }
            b"mDCV" if data.len() >= MDCV_BYTES => {
                readings.mastering.get_or_insert(mastering_max(data));
            }
            _ => {}
        }
        let Some(next) = end.checked_add(PNG_CHUNK_CRC) else {
            break;
        };
        at = next;
    }
    readings.answer()
}

/// The boxes of `bytes`, in order, as (type, body): a size of 1 reads the
/// 64-bit size after the type, 0 runs to the end of `bytes`, and a size
/// shorter than its header or past the end ends the walk.
fn boxes(bytes: &[u8]) -> Vec<(&[u8], &[u8])> {
    let mut out = Vec::new();
    let mut at = 0usize;
    while let (Some(size), Some(kind)) = (
        be_u32(bytes, at),
        bytes.get(at + 4..at.saturating_add(BOX_HEADER)),
    ) {
        let (header, size) = match size {
            0 => (BOX_HEADER, Some(bytes.len() - at)),
            1 => {
                let large = bytes
                    .get(at + BOX_HEADER..at.saturating_add(BOX_LARGE_HEADER))
                    .and_then(|field| <[u8; 8]>::try_from(field).ok())
                    .map(u64::from_be_bytes);
                let Some(large) = large else {
                    break;
                };
                (BOX_LARGE_HEADER, usize::try_from(large).ok())
            }
            size => (BOX_HEADER, usize::try_from(size).ok()),
        };
        let Some(size) = size.filter(|size| *size >= header) else {
            break;
        };
        let Some(end) = at.checked_add(size).filter(|end| *end <= bytes.len()) else {
            break;
        };
        out.push((kind, &bytes[at + header..end]));
        at = end;
    }
    out
}

/// The first box of `kind` among `bytes`' boxes.
fn first<'a>(bytes: &'a [u8], kind: &[u8; 4]) -> Option<&'a [u8]> {
    boxes(bytes)
        .into_iter()
        .find(|(found, _)| *found == kind.as_slice())
        .map(|(_, body)| body)
}

/// A FullBox's version, flags and the bytes after them.
fn full_box(body: &[u8]) -> Option<(u8, u32, &[u8])> {
    let version = *body.first()?;
    let flags = be_u32(body, 0)? & 0x00ff_ffff;
    Some((version, flags, body.get(FULL_BOX_HEADER..)?))
}

/// An ISOBMFF still's primary item's `clli` and `mdcv`.
fn isobmff_peak(file: &[u8]) -> PqColor {
    let read = || -> Option<PqColor> {
        let (_, _, meta) = full_box(first(file, b"meta")?)?;
        let (version, _, pitm) = full_box(first(meta, b"pitm")?)?;
        let primary = if version == 0 {
            u32::from(be_u16(pitm, 0)?)
        } else {
            be_u32(pitm, 0)?
        };
        let iprp = first(meta, b"iprp")?;
        let properties = boxes(first(iprp, b"ipco")?);
        let indices = associations(first(iprp, b"ipma")?, primary)?;
        let mut readings = Readings::default();
        for index in indices {
            let Some((kind, body)) = index.checked_sub(1).and_then(|i| properties.get(i)) else {
                continue;
            };
            match *kind {
                b"clli" if body.len() >= CLLI_BOX_BYTES => {
                    readings.light.get_or_insert(max_cll(body));
                }
                b"mdcv" if body.len() >= MDCV_BYTES => {
                    readings.mastering.get_or_insert(mastering_max(body));
                }
                _ => {}
            }
        }
        Some(readings.answer())
    };
    read().unwrap_or_default()
}

/// The property indices (1-based, 0 none) `ipma` associates with `item`, in
/// its order; `None` when the box is cut short before the item's entry ends
/// or has no entry for it.
fn associations(ipma: &[u8], item: u32) -> Option<Vec<usize>> {
    let (version, flags, body) = full_box(ipma)?;
    let entries = be_u32(body, 0)?;
    let id_bytes = if version == 0 { 2 } else { 4 };
    let wide = flags & 1 != 0;
    let mut at = 4usize;
    for _ in 0..entries {
        let id = if version == 0 {
            u32::from(be_u16(body, at)?)
        } else {
            be_u32(body, at)?
        };
        at += id_bytes;
        let count = usize::from(*body.get(at)?);
        at += 1;
        let mut indices = Vec::with_capacity(count);
        for _ in 0..count {
            let index = if wide {
                let value = be_u16(body, at)?;
                at += 2;
                usize::from(value & 0x7fff)
            } else {
                let value = *body.get(at)?;
                at += 1;
                usize::from(value & 0x7f)
            };
            indices.push(index);
        }
        if id == item {
            return Some(indices);
        }
    }
    None
}
