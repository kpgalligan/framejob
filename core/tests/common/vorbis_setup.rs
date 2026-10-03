//! The setup header's sections for `vorbis.rs`'s writer (Vorbis I §3.2.1
//! codebooks, §4.2.4 the setup header, §6.2.1 and §7.2.2 floors, §8.6.1
//! residues), written from the specification and never from
//! `core/src/container_vorbis_setup.rs`. Each struct writes what it holds,
//! even what the specification forbids.

use super::vorbis::{ilog, Bits};

/// How a codebook's codeword lengths are written (§3.2.1).
#[derive(Clone)]
pub enum Lengths {
    /// Ordered: the first length, then each run's entry count.
    Ordered(u32, Vec<u32>),
    /// Sparse: `None` for an unused entry.
    Sparse(Vec<Option<u32>>),
    Dense(Vec<u32>),
}

#[derive(Clone)]
pub struct Codebook {
    pub sync: u32,
    pub dimensions: u32,
    /// The entries field as written: a test may claim more than it lists.
    pub entries: u32,
    pub lengths: Lengths,
    pub lookup: u32,
    pub value_bits: u32,
}

impl Codebook {
    /// A dense two-entry book with no lookup.
    pub fn plain() -> Codebook {
        Codebook {
            sync: 0x56_4342,
            dimensions: 1,
            entries: 2,
            lengths: Lengths::Dense(vec![1, 1]),
            lookup: 0,
            value_bits: 1,
        }
    }

    fn put(&self, b: &mut Bits) {
        b.put(u64::from(self.sync), 24);
        b.put(u64::from(self.dimensions), 16);
        b.put(u64::from(self.entries), 24);
        match &self.lengths {
            Lengths::Ordered(first, runs) => {
                b.flag(true);
                b.put(u64::from(first - 1), 5);
                let mut current = 0;
                for run in runs {
                    b.put(u64::from(*run), ilog(self.entries - current));
                    current += run;
                }
            }
            Lengths::Sparse(lengths) => {
                b.flag(false);
                b.flag(true);
                for length in lengths {
                    b.flag(length.is_some());
                    if let Some(l) = length {
                        b.put(u64::from(l - 1), 5);
                    }
                }
            }
            Lengths::Dense(lengths) => {
                b.flag(false);
                b.flag(false);
                for l in lengths {
                    b.put(u64::from(l - 1), 5);
                }
            }
        }
        b.put(u64::from(self.lookup), 4);
        if self.lookup == 1 || self.lookup == 2 {
            b.put(0x6000_0000, 32); // minimum value
            b.put(0x6010_0000, 32); // delta value
            b.put(u64::from(self.value_bits - 1), 4);
            b.flag(false); // sequence_p
            let values = if self.lookup == 1 {
                lookup1_values(self.entries, self.dimensions)
            } else {
                u64::from(self.entries) * u64::from(self.dimensions)
            };
            for i in 0..values {
                b.put(i, self.value_bits);
            }
        }
    }
}

/// The greatest r whose `dimensions`th power is at most `entries` (§9.2.3),
/// counted up one at a time. With no dimensions there is no greatest r, and
/// a refusal test that writes that book gets no values.
pub fn lookup1_values(entries: u32, dimensions: u32) -> u64 {
    if dimensions == 0 {
        return 0;
    }
    let power = |r: u64| (r as u128).checked_pow(dimensions).unwrap_or(u128::MAX);
    let mut r = 0u64;
    while power(r + 1) <= u128::from(entries) {
        r += 1;
    }
    r
}

/// A floor 1 class (§7.2.2): its dimensions, subclass bits, master book and
/// subclass books (`-1` for none).
#[derive(Clone)]
pub struct Class {
    pub dimensions: u32,
    pub subclasses: u32,
    pub masterbook: u32,
    pub books: Vec<i32>,
}

#[derive(Clone)]
pub enum Floor {
    /// Floor 0 (§6.2.1) with its book list.
    Zero(Vec<u32>),
    /// Floor 1 (§7.2.2): each partition's class, the classes, rangebits.
    One(Vec<u32>, Vec<Class>, u32),
    /// Any other type number, written with nothing after it.
    Other(u32),
}

impl Floor {
    fn put(&self, b: &mut Bits) {
        match self {
            Floor::Zero(books) => {
                b.put(0, 16);
                b.put(16, 8); // order
                b.put(44_100, 16); // rate
                b.put(256, 16); // bark map size
                b.put(6, 6); // amplitude bits
                b.put(40, 8); // amplitude offset
                b.put(books.len() as u64 - 1, 4);
                for book in books {
                    b.put(u64::from(*book), 8);
                }
            }
            Floor::One(partitions, classes, rangebits) => {
                b.put(1, 16);
                b.put(partitions.len() as u64, 5);
                for p in partitions {
                    b.put(u64::from(*p), 4);
                }
                for c in classes {
                    b.put(u64::from(c.dimensions - 1), 3);
                    b.put(u64::from(c.subclasses), 2);
                    if c.subclasses != 0 {
                        b.put(u64::from(c.masterbook), 8);
                    }
                    for book in &c.books {
                        b.put((book + 1) as u64, 8);
                    }
                }
                b.put(1, 2); // multiplier 2
                b.put(u64::from(*rangebits), 4);
                let mut x = 2u64;
                for p in partitions {
                    for _ in 0..classes[*p as usize].dimensions {
                        b.put(x, *rangebits);
                        x += 1;
                    }
                }
            }
            Floor::Other(kind) => b.put(u64::from(*kind), 16),
        }
    }
}

/// A residue (§8.6.1): its type, class book, each classification's cascade
/// (up to 8 bits) and the one book every set cascade bit names.
#[derive(Clone)]
pub struct Residue {
    pub kind: u32,
    pub classbook: u32,
    pub cascades: Vec<u32>,
    pub book: u32,
}

impl Residue {
    pub fn plain(kind: u32) -> Residue {
        Residue {
            kind,
            classbook: 0,
            cascades: vec![1],
            book: 0,
        }
    }

    fn put(&self, b: &mut Bits) {
        b.put(u64::from(self.kind), 16);
        if self.kind > 2 {
            return;
        }
        b.put(0, 24); // begin
        b.put(512, 24); // end
        b.put(31, 24); // partition size 32
        b.put(self.cascades.len() as u64 - 1, 6);
        b.put(u64::from(self.classbook), 8);
        for c in &self.cascades {
            b.put(u64::from(c & 7), 3);
            b.flag(*c > 7);
            if *c > 7 {
                b.put(u64::from(c >> 3), 5);
            }
        }
        for c in &self.cascades {
            for j in 0..8 {
                if c & (1 << j) != 0 {
                    b.put(u64::from(self.book), 8);
                }
            }
        }
    }
}

/// A mapping (§4.2.4.4): type, coupling steps, the reserved field, each
/// channel's submap (`mux`, written only for more than one submap) and
/// each submap's (floor, residue).
#[derive(Clone)]
pub struct Mapping {
    pub kind: u32,
    pub coupling: Vec<(u32, u32)>,
    pub reserved: u32,
    pub mux: Vec<u32>,
    pub submaps: Vec<(u32, u32)>,
}

impl Mapping {
    pub fn plain() -> Mapping {
        Mapping {
            kind: 0,
            coupling: Vec::new(),
            reserved: 0,
            mux: Vec::new(),
            submaps: vec![(0, 0)],
        }
    }

    fn put(&self, b: &mut Bits, channels: u32) {
        b.put(u64::from(self.kind), 16);
        if self.kind != 0 {
            return;
        }
        b.flag(self.submaps.len() > 1);
        if self.submaps.len() > 1 {
            b.put(self.submaps.len() as u64 - 1, 4);
        }
        b.flag(!self.coupling.is_empty());
        if !self.coupling.is_empty() {
            b.put(self.coupling.len() as u64 - 1, 8);
            for (m, a) in &self.coupling {
                b.put(u64::from(*m), ilog(channels - 1));
                b.put(u64::from(*a), ilog(channels - 1));
            }
        }
        b.put(u64::from(self.reserved), 2);
        if self.submaps.len() > 1 {
            for m in &self.mux {
                b.put(u64::from(*m), 4);
            }
        }
        for (floor, residue) in &self.submaps {
            b.put(0, 8);
            b.put(u64::from(*floor), 8);
            b.put(u64::from(*residue), 8);
        }
    }
}

/// A mode (§4.2.4.5): block flag, window, transform, mapping.
#[derive(Clone)]
pub struct Mode {
    pub long: bool,
    pub window: u32,
    pub transform: u32,
    pub mapping: u32,
}

impl Mode {
    pub fn new(long: bool) -> Mode {
        Mode {
            long,
            window: 0,
            transform: 0,
            mapping: 0,
        }
    }
}

/// The setup header's sections (§4.2.4), in the order they are written.
#[derive(Clone)]
pub struct Setup {
    pub codebooks: Vec<Codebook>,
    pub times: Vec<u32>,
    pub floors: Vec<Floor>,
    pub residues: Vec<Residue>,
    pub mappings: Vec<Mapping>,
    pub modes: Vec<Mode>,
    pub framing: bool,
}

impl Setup {
    /// The smallest valid setup: one of each section, a mode per flag.
    pub fn plain(flags: &[bool]) -> Setup {
        Setup {
            codebooks: vec![Codebook::plain()],
            times: vec![0],
            floors: vec![Floor::One(Vec::new(), Vec::new(), 8)],
            residues: vec![Residue::plain(0)],
            mappings: vec![Mapping::plain()],
            modes: flags.iter().map(|f| Mode::new(*f)).collect(),
            framing: true,
        }
    }

    pub fn bytes(&self, channels: u32) -> Vec<u8> {
        let mut b = Bits::default();
        b.magic(5);
        b.put(self.codebooks.len() as u64 - 1, 8);
        for c in &self.codebooks {
            c.put(&mut b);
        }
        b.put(self.times.len() as u64 - 1, 6);
        for t in &self.times {
            b.put(u64::from(*t), 16);
        }
        b.put(self.floors.len() as u64 - 1, 6);
        for f in &self.floors {
            f.put(&mut b);
        }
        b.put(self.residues.len() as u64 - 1, 6);
        for r in &self.residues {
            r.put(&mut b);
        }
        b.put(self.mappings.len() as u64 - 1, 6);
        for m in &self.mappings {
            m.put(&mut b, channels);
        }
        b.put(self.modes.len() as u64 - 1, 6);
        for m in &self.modes {
            b.flag(m.long);
            b.put(u64::from(m.window), 16);
            b.put(u64::from(m.transform), 16);
            b.put(u64::from(m.mapping), 8);
        }
        b.flag(self.framing);
        b.finish()
    }
}
