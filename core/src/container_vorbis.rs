//! A Vorbis track's three headers, read as far as the copy needs them (spec
//! §11 #228-V): the rate, the channels and the two block sizes from the
//! identification header, and each mode's block flag from the setup header,
//! which is walked section by section (Vorbis I §4.2.4) to reach its mode
//! table (`container_vorbis_setup.rs`). Nothing is decoded and no codebook
//! is built.
//!
//! The headers are untrusted bytes, so every read is a bounds-checked
//! `Option`, no count a header claims sizes an allocation, and every loop
//! consumes bits or ends: a claim the packet has no bits for runs out and
//! answers `None`, which the app refuses in #216-R's sentence.
//!
//! **Each packet's sample count** is the overlap rule, n = prev/4 + cur/4,
//! where a packet's block size is its mode's (Vorbis I §4.3.1). Packet 0,
//! which decodes to nothing, counts bs0/4 + its own/4 — ffmpeg's convention,
//! and never 0, because the movie writer refuses a later append after a
//! 0-frame packet (measured). A packet whose mode cannot be read counts as a
//! short block.

use crate::container_vorbis_setup::setup_modes;

/// What the copy needs from a Vorbis track's three headers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Vorbis {
    /// The identification header's channels, at least 1.
    pub channels: u8,
    /// The identification header's rate, 1..=10_000_000 (the TrackEntry's
    /// cap, `container.rs`).
    pub rate: u32,
    /// The short and long block sizes, 2^6..=2^13, `[0] <= [1]`.
    pub blocksizes: [u32; 2],
    /// One per mode, 1..=64 modes: true for a long block.
    pub block_flags: Vec<bool>,
}

/// The highest rate read, as the TrackEntry's rate is capped.
const MAX_RATE: u32 = 10_000_000;

/// Reads bits least significant first (Vorbis I §2.1.4).
pub(crate) struct Bits<'a> {
    pub data: &'a [u8],
    pub at: u64,
}

impl Bits<'_> {
    fn remaining(&self) -> u64 {
        (self.data.len() as u64 * 8).saturating_sub(self.at)
    }

    /// `n` bits, `n <= 32`, the first read the value's lowest.
    pub(crate) fn read(&mut self, n: u32) -> Option<u32> {
        if u64::from(n) > self.remaining() {
            return None;
        }
        let mut v = 0u32;
        for i in 0..n {
            let byte = self.data[(self.at / 8) as usize];
            v |= u32::from((byte >> (self.at % 8)) & 1) << i;
            self.at += 1;
        }
        Some(v)
    }

    pub(crate) fn flag(&mut self) -> Option<bool> {
        Some(self.read(1)? == 1)
    }

    /// Skips `n` bits when the packet holds them.
    pub(crate) fn skip(&mut self, n: u64) -> Option<()> {
        if n > self.remaining() {
            return None;
        }
        self.at += n;
        Some(())
    }
}

/// The bits needed to hold `v` (Vorbis I §9.2.1): ilog(0) = 0, ilog(1) = 1,
/// ilog(4) = 3.
pub(crate) fn ilog(v: u32) -> u32 {
    32 - v.leading_zeros()
}

/// A header packet's type byte and "vorbis".
pub(crate) fn magic(b: &mut Bits, kind: u32) -> Option<()> {
    if b.read(8)? != kind {
        return None;
    }
    for &c in b"vorbis" {
        if b.read(8)? != u32::from(c) {
            return None;
        }
    }
    Some(())
}

/// Matroska's CodecPrivate for Vorbis: the packet count less one (2), two
/// Xiph lacing sizes, then the three packets, the third the rest.
fn split(private: &[u8]) -> Option<[&[u8]; 3]> {
    if *private.first()? != 2 {
        return None;
    }
    let mut at = 1usize;
    let mut sizes = [0usize; 2];
    for size in &mut sizes {
        loop {
            let byte = *private.get(at)?;
            at += 1;
            *size = size.checked_add(usize::from(byte))?;
            if byte < 255 {
                break;
            }
        }
    }
    let first_end = at.checked_add(sizes[0])?;
    let second_end = first_end.checked_add(sizes[1])?;
    let ident = private.get(at..first_end)?;
    let comment = private.get(first_end..second_end)?;
    let setup = private.get(second_end..)?;
    Some([ident, comment, setup])
}

impl Vorbis {
    /// The three headers in a Matroska CodecPrivate, or `None` when any of
    /// them cannot be read.
    pub(crate) fn parse(private: &[u8]) -> Option<Vorbis> {
        let [ident, comment, setup] = split(private)?;
        let mut v = identification(ident)?;
        magic(
            &mut Bits {
                data: comment,
                at: 0,
            },
            3,
        )?;
        v.block_flags = setup_modes(setup, v.channels)?;
        Some(v)
    }

    /// Each packet's samples, from its first byte (`None` = empty or
    /// unread): n_0 = bs0/4 + b_0/4, n_k = b_{k−1}/4 + b_k/4. Never 0.
    pub(crate) fn counts(&self, first_bytes: &[Option<u8>]) -> Vec<u32> {
        let mut prev = self.blocksizes[0];
        first_bytes
            .iter()
            .map(|byte| {
                let size = self.blocksize(*byte);
                let n = prev / 4 + size / 4;
                prev = size;
                n
            })
            .collect()
    }

    /// A packet's block size from its first byte: bit 0 must be 0 (an
    /// audio packet), then the mode number in ilog(modes − 1) bits.
    /// Anything unreadable is a short block.
    fn blocksize(&self, first: Option<u8>) -> u32 {
        let short = self.blocksizes[0];
        let Some(byte) = first else {
            return short;
        };
        let data = [byte];
        let mut b = Bits { data: &data, at: 0 };
        if b.read(1) != Some(0) {
            return short;
        }
        let modes = self.block_flags.len() as u32;
        let mode = b.read(ilog(modes.saturating_sub(1)));
        match mode.and_then(|m| self.block_flags.get(m as usize)) {
            Some(true) => self.blocksizes[1],
            _ => short,
        }
    }
}

/// The identification header (Vorbis I §4.2.2); `block_flags` left empty.
fn identification(packet: &[u8]) -> Option<Vorbis> {
    let mut b = Bits {
        data: packet,
        at: 0,
    };
    magic(&mut b, 1)?;
    if b.read(32)? != 0 {
        return None;
    }
    let channels = b.read(8)? as u8;
    let rate = b.read(32)?;
    b.skip(96)?; // bitrate maximum, nominal and minimum
    let exps = [b.read(4)?, b.read(4)?];
    let framing = b.flag()?;
    let fits = |e: &u32| (6..=13).contains(e);
    if channels == 0
        || !(1..=MAX_RATE).contains(&rate)
        || !exps.iter().all(fits)
        || exps[0] > exps[1]
        || !framing
    {
        return None;
    }
    Some(Vorbis {
        channels,
        rate,
        blocksizes: [1 << exps[0], 1 << exps[1]],
        block_flags: Vec::new(),
    })
}
