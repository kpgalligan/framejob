//! The Vorbis setup header (Vorbis I §4.2.4) walked section by section —
//! codebooks, times, floors, residues, mappings — to its mode table, for
//! each mode's block flag (spec §11 #228-V). Cut out of
//! `container_vorbis.rs` under the size rule, a pure move: the bit reader
//! and the header magic stay there. Every section is skipped, never built:
//! a count sizes no allocation, and every loop reads bits or ends.

use crate::container_vorbis::{ilog, magic, Bits};

/// The setup header (Vorbis I §4.2.4) walked to its mode table: each
/// mode's block flag.
pub(crate) fn setup_modes(packet: &[u8], channels: u8) -> Option<Vec<bool>> {
    let mut b = Bits {
        data: packet,
        at: 0,
    };
    magic(&mut b, 5)?;
    let books = b.read(8)? + 1;
    for _ in 0..books {
        codebook(&mut b)?;
    }
    let times = b.read(6)? + 1;
    for _ in 0..times {
        if b.read(16)? != 0 {
            return None;
        }
    }
    let floors = b.read(6)? + 1;
    for _ in 0..floors {
        match b.read(16)? {
            0 => floor0(&mut b, books)?,
            1 => floor1(&mut b, books)?,
            _ => return None,
        }
    }
    let residues = b.read(6)? + 1;
    for _ in 0..residues {
        if b.read(16)? > 2 {
            return None;
        }
        residue(&mut b, books)?;
    }
    let mappings = b.read(6)? + 1;
    for _ in 0..mappings {
        if b.read(16)? != 0 {
            return None;
        }
        mapping(&mut b, channels, floors, residues)?;
    }
    let modes = b.read(6)? + 1;
    let mut flags = Vec::with_capacity(modes as usize);
    for _ in 0..modes {
        let flag = b.flag()?;
        let window = b.read(16)?;
        let transform = b.read(16)?;
        let mapping = b.read(8)?;
        if window != 0 || transform != 0 || mapping >= mappings {
            return None;
        }
        flags.push(flag);
    }
    if !b.flag()? {
        return None;
    }
    Some(flags)
}

/// A book number that names one of the `books` codebooks.
fn book(b: &mut Bits, books: u32) -> Option<()> {
    (b.read(8)? < books).then_some(())
}

/// One codebook (Vorbis I §3.2.1), skipped: its lengths read and dropped,
/// its lookup values passed over whole.
fn codebook(b: &mut Bits) -> Option<()> {
    if b.read(24)? != 0x56_4342 {
        return None;
    }
    let dimensions = b.read(16)?;
    let entries = b.read(24)?;
    if b.flag()? {
        // Ordered: runs of one length, each run's size in ilog(left) bits,
        // at least one bit while entries are left.
        b.read(5)?;
        let mut current = 0u32;
        while current < entries {
            current = current.checked_add(b.read(ilog(entries - current))?)?;
        }
        if current > entries {
            return None;
        }
    } else {
        let sparse = b.flag()?;
        for _ in 0..entries {
            if !sparse || b.flag()? {
                b.read(5)?;
            }
        }
    }
    let lookup = b.read(4)?;
    match lookup {
        0 => Some(()),
        1 | 2 => {
            if dimensions == 0 {
                return None;
            }
            b.skip(64)?; // minimum and delta values
            let value_bits = u64::from(b.read(4)? + 1);
            b.read(1)?; // sequence_p
            let values = if lookup == 1 {
                lookup1_values(entries, dimensions)
            } else {
                u64::from(entries) * u64::from(dimensions)
            };
            b.skip(values * value_bits)
        }
        _ => None,
    }
}

/// The greatest r with r^dimensions <= entries (Vorbis I §9.2.3), never
/// above `entries`; `dimensions` > 0.
fn lookup1_values(entries: u32, dimensions: u32) -> u64 {
    let entries = u64::from(entries);
    // r^dimensions <= entries, multiplied out until it passes entries.
    let fits = |r: u64| {
        let mut p = 1u64;
        for _ in 0..dimensions {
            p = p.saturating_mul(r);
            if p > entries {
                return false;
            }
        }
        true
    };
    if entries <= 1 {
        return entries;
    }
    let (mut lo, mut hi) = (1u64, entries);
    while lo < hi {
        let mid = lo + (hi - lo).div_ceil(2);
        if fits(mid) {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    lo
}

/// A type 0 floor's header (Vorbis I §6.2.1).
fn floor0(b: &mut Bits, books: u32) -> Option<()> {
    b.skip(8 + 16 + 16 + 6 + 8)?; // order, rate, bark map size, amplitude bits and offset
    let count = b.read(4)? + 1;
    for _ in 0..count {
        book(b, books)?;
    }
    Some(())
}

/// A type 1 floor's header (Vorbis I §7.2.2).
fn floor1(b: &mut Bits, books: u32) -> Option<()> {
    let partitions = b.read(5)? as usize;
    let mut classes = [0u32; 31];
    let mut max_class: Option<u32> = None;
    for class in classes.iter_mut().take(partitions) {
        *class = b.read(4)?;
        max_class = Some(max_class.map_or(*class, |m| m.max(*class)));
    }
    let mut dimensions = [0u32; 16];
    for dims in dimensions
        .iter_mut()
        .take(max_class.map_or(0, |m| m as usize + 1))
    {
        *dims = b.read(3)? + 1;
        let subclasses = b.read(2)?;
        if subclasses != 0 {
            book(b, books)?;
        }
        for _ in 0..(1u32 << subclasses) {
            // Stored as the book plus one; 0 is "no book".
            let sub = b.read(8)?;
            if sub > books {
                return None;
            }
        }
    }
    b.read(2)?; // multiplier
    let rangebits = u64::from(b.read(4)?);
    for class in classes.iter().take(partitions) {
        b.skip(u64::from(dimensions[*class as usize]) * rangebits)?;
    }
    Some(())
}

/// A residue's header (Vorbis I §8.6.1), its type already read.
fn residue(b: &mut Bits, books: u32) -> Option<()> {
    b.skip(24 + 24 + 24)?; // begin, end, partition size
    let classifications = b.read(6)? + 1;
    book(b, books)?;
    let mut cascade = [0u32; 64];
    for c in cascade.iter_mut().take(classifications as usize) {
        let low = b.read(3)?;
        let high = if b.flag()? { b.read(5)? } else { 0 };
        *c = high * 8 + low;
    }
    for c in cascade.iter().take(classifications as usize) {
        for j in 0..8 {
            if c & (1 << j) != 0 {
                book(b, books)?;
            }
        }
    }
    Some(())
}

/// A type 0 mapping's header (Vorbis I §4.2.4.4), its type already read.
fn mapping(b: &mut Bits, channels: u8, floors: u32, residues: u32) -> Option<()> {
    let channels = u32::from(channels);
    let submaps = if b.flag()? { b.read(4)? + 1 } else { 1 };
    if b.flag()? {
        let steps = b.read(8)? + 1;
        let width = ilog(channels.saturating_sub(1));
        for _ in 0..steps {
            let magnitude = b.read(width)?;
            let angle = b.read(width)?;
            if magnitude == angle || magnitude >= channels || angle >= channels {
                return None;
            }
        }
    }
    if b.read(2)? != 0 {
        return None;
    }
    if submaps > 1 {
        for _ in 0..channels {
            if b.read(4)? >= submaps {
                return None;
            }
        }
    }
    for _ in 0..submaps {
        b.read(8)?; // time configuration, unused
        if b.read(8)? >= floors || b.read(8)? >= residues {
            return None;
        }
    }
    Some(())
}
