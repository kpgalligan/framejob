//! A test-only EBML WALK — the independent oracle for what the WebM writer
//! (`rc_webm_*`, spec §11 CX-15) puts where #216-R's reader does not look:
//! the SeekHead, Info's Duration, Chapters, Cues, the Segment's size, the
//! Cluster and block order and DiscardPadding. Written from RFC 8794 and RFC
//! 9559, never from `core/src/webm_*.rs`: it parses the whole file into a
//! tree of elements, by a list of master IDs of its own.

/// One element: its ID (marker bits included), where its header starts, where
/// its data starts, how long its data is, and its children when a master.
#[derive(Debug, Clone)]
pub struct Element {
    pub id: u32,
    pub start: usize,
    pub data: usize,
    pub size: usize,
    pub children: Vec<Element>,
}

/// The masters this walk descends into.
const MASTERS: [u32; 22] = [
    0x1A45_DFA3, // EBML
    0x1853_8067, // Segment
    0x114D_9B74, // SeekHead
    0x4DBB,      // Seek
    0x1549_A966, // Info
    0x1654_AE6B, // Tracks
    0xAE,        // TrackEntry
    0xE0,        // Video
    0x55B0,      // Colour
    0x55D0,      // MasteringMetadata
    0xE1,        // Audio
    0x1043_A770, // Chapters
    0x45B9,      // EditionEntry
    0xB6,        // ChapterAtom
    0x80,        // ChapterDisplay
    0x1F43_B675, // Cluster
    0xA0,        // BlockGroup
    0x75A1,      // BlockAdditions
    0xA6,        // BlockMore
    0x1C53_BB6B, // Cues
    0xBB,        // CuePoint
    0xB7,        // CueTrackPositions
];

/// An element ID at `at` (1–4 bytes, the length from the first byte's
/// leading zeros), marker kept; and its length.
fn read_id(bytes: &[u8], at: usize) -> (u32, usize) {
    let first = bytes[at];
    let len = first.leading_zeros() as usize + 1;
    assert!(len <= 4, "an ID of {len} bytes at {at}");
    let id = bytes[at..at + len]
        .iter()
        .fold(0u32, |v, b| (v << 8) | u32::from(*b));
    (id, len)
}

/// A size vint at `at`, marker removed; and its length. The all-ones value
/// ("unknown") is `None`.
pub fn read_size(bytes: &[u8], at: usize) -> (Option<u64>, usize) {
    let first = bytes[at];
    let len = first.leading_zeros() as usize + 1;
    assert!(len <= 8, "a size of {len} bytes at {at}");
    let mut v = u64::from(first) & ((1u64 << (8 - len)) - 1);
    for b in &bytes[at + 1..at + len] {
        v = (v << 8) | u64::from(*b);
    }
    let unknown = v == (1u64 << (7 * len)) - 1;
    ((!unknown).then_some(v), len)
}

/// Every element from `from` to `to`, children parsed for masters. A size
/// that is unknown or runs past `to` fails the test.
pub fn walk(bytes: &[u8], from: usize, to: usize) -> Vec<Element> {
    let mut out = Vec::new();
    let mut at = from;
    while at < to {
        let (id, id_len) = read_id(bytes, at);
        let (size, size_len) = read_size(bytes, at + id_len);
        let size =
            size.unwrap_or_else(|| panic!("element {id:#x} at {at} has an unknown size")) as usize;
        let data = at + id_len + size_len;
        assert!(data + size <= to, "element {id:#x} at {at} runs past {to}");
        let children = if MASTERS.contains(&id) {
            walk(bytes, data, data + size)
        } else {
            Vec::new()
        };
        out.push(Element {
            id,
            start: at,
            data,
            size,
            children,
        });
        at = data + size;
    }
    out
}

impl Element {
    /// The first child with `id`.
    pub fn child(&self, id: u32) -> Option<&Element> {
        self.children.iter().find(|e| e.id == id)
    }

    /// Every child with `id`, in order.
    pub fn all(&self, id: u32) -> Vec<&Element> {
        self.children.iter().filter(|e| e.id == id).collect()
    }

    pub fn body<'a>(&self, bytes: &'a [u8]) -> &'a [u8] {
        &bytes[self.data..self.data + self.size]
    }

    pub fn uint(&self, bytes: &[u8]) -> u64 {
        self.body(bytes)
            .iter()
            .fold(0u64, |v, b| (v << 8) | u64::from(*b))
    }

    pub fn int(&self, bytes: &[u8]) -> i64 {
        let body = self.body(bytes);
        let negative = body.first().is_some_and(|b| b & 0x80 != 0);
        let start: i64 = if negative { -1 } else { 0 };
        body.iter().fold(start, |v, b| (v << 8) | i64::from(*b))
    }

    pub fn float(&self, bytes: &[u8]) -> f64 {
        let body = self.body(bytes);
        match body.len() {
            4 => f64::from(f32::from_be_bytes(body.try_into().expect("4 bytes"))),
            8 => f64::from_be_bytes(body.try_into().expect("8 bytes")),
            n => panic!("a float of {n} bytes"),
        }
    }

    pub fn string(&self, bytes: &[u8]) -> String {
        String::from_utf8(self.body(bytes).to_vec()).expect("a UTF-8 string")
    }
}

/// The file's top level and its Segment, whose children are the level-1
/// elements; the Segment's size must be known.
pub fn segment(bytes: &[u8]) -> (Vec<Element>, Element) {
    let top = walk(bytes, 0, bytes.len());
    let segment = top
        .iter()
        .find(|e| e.id == 0x1853_8067)
        .expect("a Segment")
        .clone();
    (top, segment)
}

/// One block as the file holds it: its track, its absolute time in ms, its
/// flags, its frame's bytes, the DiscardPadding of its group if any, and its
/// group's ReferenceBlock and BlockAdditions (each BlockMore's BlockAddID and
/// BlockAdditional) if any.
#[derive(Debug, Clone)]
pub struct BlockRead {
    pub track: u64,
    pub ms: i64,
    pub flags: u8,
    pub frame: Vec<u8>,
    pub discard: Option<i64>,
    pub cluster_start: usize,
    pub group: bool,
    pub reference: Option<i64>,
    pub additions: Vec<(u64, Vec<u8>)>,
}

/// Every block of every Cluster, in file order.
pub fn blocks(bytes: &[u8], segment: &Element) -> Vec<BlockRead> {
    let mut out = Vec::new();
    for cluster in segment.all(0x1F43_B675) {
        let time = cluster
            .child(0xE7)
            .expect("a Cluster Timestamp")
            .uint(bytes) as i64;
        for e in &cluster.children {
            let (block, discard) = match e.id {
                0xA3 => (e, None),
                0xA0 => (
                    e.child(0xA1).expect("a BlockGroup's Block"),
                    e.child(0x75A2).map(|d| d.int(bytes)),
                ),
                _ => continue,
            };
            let reference = e.child(0xFB).map(|r| r.int(bytes));
            let additions = e
                .child(0x75A1)
                .map(|adds| {
                    adds.all(0xA6)
                        .into_iter()
                        .map(|more| {
                            let id = more.child(0xEE).expect("a BlockAddID").uint(bytes);
                            let body = more.child(0xA5).expect("a BlockAdditional");
                            (id, body.body(bytes).to_vec())
                        })
                        .collect()
                })
                .unwrap_or_default();
            let body = block.body(bytes);
            let (track, len) = read_size(body, 0);
            let rel = i16::from_be_bytes([body[len], body[len + 1]]);
            out.push(BlockRead {
                track: track.expect("a track number"),
                ms: time + i64::from(rel),
                flags: body[len + 2],
                frame: body[len + 3..].to_vec(),
                discard,
                cluster_start: cluster.start,
                group: e.id == 0xA0,
                reference,
                additions,
            });
        }
    }
    out
}
