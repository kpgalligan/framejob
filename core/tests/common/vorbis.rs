//! A Vorbis header and packet WRITER — the independent oracle
//! `container_vorbis.rs` and `container_vorbis_headers.rs` build their
//! tracks with (spec §11 #228-V). It is written from the Vorbis I
//! specification (§2.1.4 bit packing, §4.2 the three headers), never from
//! `core/src/container_vorbis*.rs`: every field is put in its own width, in
//! its own order, so a test's expected value comes from what this file
//! wrote. Each struct writes what it holds even when that breaks the
//! specification, which is how a refusal test spells its damage. The setup
//! header's sections are `vorbis_setup.rs`; the CodecPrivate of a real
//! file, and its three packets, are read back here.

/// Bits packed least significant first into each byte (Vorbis I §2.1.4).
#[derive(Default)]
pub struct Bits {
    bytes: Vec<u8>,
    bits: usize,
}

impl Bits {
    /// The low `n` bits of `value`, its lowest bit first.
    pub fn put(&mut self, value: u64, n: u32) {
        for i in 0..n {
            if self.bits.is_multiple_of(8) {
                self.bytes.push(0);
            }
            let bit = ((value >> i) & 1) as u8;
            let last = self.bytes.len() - 1;
            self.bytes[last] |= bit << (self.bits % 8);
            self.bits += 1;
        }
    }

    pub fn flag(&mut self, on: bool) {
        self.put(u64::from(on), 1);
    }

    /// A header packet's type byte and "vorbis".
    pub fn magic(&mut self, kind: u8) {
        self.put(u64::from(kind), 8);
        for c in b"vorbis" {
            self.put(u64::from(*c), 8);
        }
    }

    pub fn finish(self) -> Vec<u8> {
        self.bytes
    }
}

/// The bits needed to hold `v` (Vorbis I §9.2.1).
pub fn ilog(v: u32) -> u32 {
    let mut n = 0;
    let mut v = v;
    while v > 0 {
        n += 1;
        v >>= 1;
    }
    n
}

/// The identification header's fields (Vorbis I §4.2.2).
#[derive(Clone)]
pub struct Ident {
    pub version: u32,
    pub channels: u32,
    pub rate: u32,
    /// The two block size exponents, short then long.
    pub exps: (u32, u32),
    pub framing: bool,
}

impl Ident {
    pub fn new(channels: u32, rate: u32) -> Ident {
        Ident {
            version: 0,
            channels,
            rate,
            exps: (8, 11),
            framing: true,
        }
    }

    pub fn bytes(&self) -> Vec<u8> {
        let mut b = Bits::default();
        b.magic(1);
        b.put(u64::from(self.version), 32);
        b.put(u64::from(self.channels), 8);
        b.put(u64::from(self.rate), 32);
        b.put(0, 32); // bitrate maximum
        b.put(128_000, 32); // bitrate nominal
        b.put(0, 32); // bitrate minimum
        b.put(u64::from(self.exps.0), 4);
        b.put(u64::from(self.exps.1), 4);
        b.flag(self.framing);
        b.finish()
    }
}

/// A comment header with a vendor string and no comments (§5.2.1).
pub fn comment() -> Vec<u8> {
    let mut b = Bits::default();
    b.magic(3);
    let vendor = b"vorbis.rs";
    b.put(vendor.len() as u64, 32);
    for c in vendor {
        b.put(u64::from(*c), 8);
    }
    b.put(0, 32);
    b.flag(true);
    b.finish()
}

/// Matroska's Vorbis CodecPrivate: 2 (three packets less one), the first
/// two packets' Xiph lacing sizes, then the three packets.
pub fn private(ident: &[u8], comment: &[u8], setup: &[u8]) -> Vec<u8> {
    let mut out = vec![2u8];
    for p in [ident, comment] {
        let mut n = p.len();
        while n >= 255 {
            out.push(255);
            n -= 255;
        }
        out.push(n as u8);
    }
    for p in [ident, comment, setup] {
        out.extend_from_slice(p);
    }
    out
}

/// An audio packet: type bit 0, then `mode` in `mode_bits` bits, then
/// filler to `len` bytes.
pub fn packet(mode: u32, mode_bits: u32, len: usize) -> Vec<u8> {
    let mut b = Bits::default();
    b.put(0, 1);
    b.put(u64::from(mode), mode_bits);
    let mut out = b.finish();
    out.resize(len.max(out.len()), 0x5A);
    out
}

/// The CodecPrivate a real file carries: the `63 A2` element after its
/// `A_VORBIS` CodecID, its size an EBML vint.
pub fn codec_private(file: &[u8]) -> Vec<u8> {
    let id = file.windows(8).position(|w| w == b"A_VORBIS");
    let id = id.expect("an A_VORBIS CodecID");
    let after = file[id..].windows(2).position(|w| w == [0x63, 0xA2]);
    let at = id + after.expect("a CodecPrivate after it") + 2;
    let len = file[at].leading_zeros() as usize + 1;
    let mut size = u64::from(file[at] & (0xFF >> len));
    for b in &file[at + 1..at + len] {
        size = (size << 8) | u64::from(*b);
    }
    file[at + len..at + len + size as usize].to_vec()
}

/// A CodecPrivate's three packets, by its two Xiph lacing sizes.
pub fn packets(private: &[u8]) -> [Vec<u8>; 3] {
    let mut at = 1;
    let mut sizes = [0usize; 2];
    for size in &mut sizes {
        while private[at] == 255 {
            *size += 255;
            at += 1;
        }
        *size += usize::from(private[at]);
        at += 1;
    }
    let comment = at + sizes[0];
    let setup = comment + sizes[1];
    [
        private[at..comment].to_vec(),
        private[comment..setup].to_vec(),
        private[setup..].to_vec(),
    ]
}
