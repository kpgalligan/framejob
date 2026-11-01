//! The two candidate bodies of a cursor file (CU-S4): a columnar JSON body (integer µs and
//! points × 100) and a binary columnar body (a JSON header with the array lengths, then
//! little-endian i64 arrays, then the image blobs). Both parse to one `Track`, validated.

use serde::{Deserialize, Serialize};

/// Caps a parse refuses beyond (a prototype's, sized well past the worst case).
pub const MAX_MOVES: usize = 120 * 3600 * 4;
pub const MAX_CLICKS: usize = 200_000;
pub const MAX_KEYS: usize = 1_000_000;
pub const MAX_IMAGES: usize = 1024;
pub const MAX_IMAGE_BYTES: usize = 1 << 20;
pub const MAX_IMAGE_CHANGES: usize = 1_000_000;

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Geometry {
    pub t: i64,
    pub display_w: i64,
    pub display_h: i64,
    pub px_per_pt: i64,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Image {
    pub id: i64,
    pub hot_x: i64,
    pub hot_y: i64,
    pub w: i64,
    pub h: i64,
    pub bytes: Vec<u8>,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Moves {
    pub t: Vec<i64>,
    pub x: Vec<i64>,
    pub y: Vec<i64>,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Clicks {
    pub t: Vec<i64>,
    pub button: Vec<i64>,
    pub down: Vec<i64>,
    pub x: Vec<i64>,
    pub y: Vec<i64>,
    pub count: Vec<i64>,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Keys {
    pub t: Vec<i64>,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct ImageChanges {
    pub t: Vec<i64>,
    pub id: Vec<i64>,
}

/// One cursor file's contents, whichever body it came from.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Track {
    pub geometry: Vec<Geometry>,
    pub images: Vec<Image>,
    pub moves: Moves,
    pub clicks: Clicks,
    pub keys: Keys,
    pub image_changes: ImageChanges,
}

// ---- the worst case ---------------------------------------------------------------------

/// The seeded generator (an LCG, seed 1): Knuth's MMIX constants.
pub struct Lcg(u64);

impl Lcg {
    pub fn new(seed: u64) -> Self {
        Lcg(seed)
    }
    pub fn next(&mut self) -> u64 {
        self.0 = self
            .0
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        self.0 >> 33
    }
    pub fn below(&mut self, n: u64) -> u64 {
        self.next() % n.max(1)
    }
}

pub const HOUR_US: i64 = 3_600_000_000;
pub const WIDTH: i64 = 151_200; // 1512 pt × 100
pub const HEIGHT: i64 = 98_200; // 982 pt × 100

/// One hour at 120 Hz (432,000 moves), 3,600 clicks (a down and an up each), 20,000
/// time-only key marks, 40 images of 4,096 opaque bytes, 3,600 image changes, one geometry
/// entry; seeded generation, LCG seed 1.
pub fn worst_case() -> Track {
    let mut rng = Lcg::new(1);
    let mut moves = Moves::default();
    let (mut x, mut y) = (WIDTH / 2, HEIGHT / 2);
    for i in 0..432_000i64 {
        x = (x + rng.below(801) as i64 - 400).clamp(0, WIDTH);
        y = (y + rng.below(801) as i64 - 400).clamp(0, HEIGHT);
        moves.t.push(i * 1_000_000 / 120);
        moves.x.push(x);
        moves.y.push(y);
    }
    let mut clicks = Clicks::default();
    for i in 0..3_600i64 {
        let t = i * 1_000_000 + rng.below(500_000) as i64;
        let k = (t * 120 / 1_000_000) as usize;
        let (cx, cy) = (moves.x[k], moves.y[k]);
        let button = if rng.below(10) == 0 { 1 } else { 0 };
        for (dt, down) in [(0i64, 1i64), (80_000, 0)] {
            clicks.t.push(t + dt);
            clicks.button.push(button);
            clicks.down.push(down);
            clicks.x.push(cx);
            clicks.y.push(cy);
            clicks.count.push(1);
        }
    }
    let mut keys = Keys::default();
    let mut t = 0i64;
    for _ in 0..20_000 {
        t += 1 + rng.below(359_000) as i64;
        keys.t.push(t.min(HOUR_US));
    }
    let images = (0..40i64)
        .map(|id| Image {
            id,
            hot_x: 4,
            hot_y: 4,
            w: 32,
            h: 32,
            bytes: (0..4096).map(|_| rng.below(256) as u8).collect(),
        })
        .collect();
    let mut image_changes = ImageChanges::default();
    for i in 0..3_600i64 {
        image_changes.t.push(i * 1_000_000);
        image_changes.id.push(rng.below(40) as i64);
    }
    Track {
        geometry: vec![Geometry {
            t: 0,
            display_w: WIDTH,
            display_h: HEIGHT,
            px_per_pt: 200,
        }],
        images,
        moves,
        clicks,
        keys,
        image_changes,
    }
}

// ---- validation -------------------------------------------------------------------------

fn non_decreasing(name: &str, t: &[i64]) -> Result<(), String> {
    if t.windows(2).any(|w| w[1] < w[0]) {
        return Err(format!("{name}: times decrease"));
    }
    Ok(())
}

/// Equal column lengths, non-decreasing times, ids in range, the caps.
pub fn validate(track: &Track) -> Result<(), String> {
    let m = &track.moves;
    if m.x.len() != m.t.len() || m.y.len() != m.t.len() {
        return Err("moves: columns differ in length".into());
    }
    let c = &track.clicks;
    let n = c.t.len();
    if [
        c.button.len(),
        c.down.len(),
        c.x.len(),
        c.y.len(),
        c.count.len(),
    ]
    .iter()
    .any(|&l| l != n)
    {
        return Err("clicks: columns differ in length".into());
    }
    let ic = &track.image_changes;
    if ic.id.len() != ic.t.len() {
        return Err("image_changes: columns differ in length".into());
    }
    if m.t.len() > MAX_MOVES
        || n > MAX_CLICKS
        || track.keys.t.len() > MAX_KEYS
        || track.images.len() > MAX_IMAGES
        || ic.t.len() > MAX_IMAGE_CHANGES
    {
        return Err("a column is over its cap".into());
    }
    if track.geometry.is_empty() {
        return Err("no geometry".into());
    }
    non_decreasing("moves", &m.t)?;
    non_decreasing("clicks", &c.t)?;
    non_decreasing("keys", &track.keys.t)?;
    non_decreasing("image_changes", &ic.t)?;
    for (i, image) in track.images.iter().enumerate() {
        if image.id != i as i64 || image.bytes.len() > MAX_IMAGE_BYTES {
            return Err(format!("image {i}: id out of order or over its cap"));
        }
    }
    let count = track.images.len() as i64;
    if ic.id.iter().any(|&id| id < 0 || id >= count) {
        return Err("image_changes: an id out of range".into());
    }
    if c.down.iter().any(|&d| d != 0 && d != 1) {
        return Err("clicks: down is not 0 or 1".into());
    }
    Ok(())
}

// ---- base64 (standard alphabet, padded) -------------------------------------------------

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn b64_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = (b[0] as u32) << 16 | (b[1] as u32) << 8 | b[2] as u32;
        for k in 0..4 {
            if k <= chunk.len() {
                out.push(B64[(n >> (18 - 6 * k) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

pub fn b64_decode(text: &str) -> Result<Vec<u8>, String> {
    let mut lookup = [255u8; 256];
    for (i, &c) in B64.iter().enumerate() {
        lookup[c as usize] = i as u8;
    }
    let bytes = text.as_bytes();
    if !bytes.len().is_multiple_of(4) {
        return Err("base64: length is not a multiple of 4".into());
    }
    let mut out = Vec::with_capacity(bytes.len() / 4 * 3);
    for chunk in bytes.chunks(4) {
        let pad = chunk.iter().rev().take_while(|&&c| c == b'=').count();
        let mut n = 0u32;
        for &c in chunk.iter() {
            let v = if c == b'=' { 0 } else { lookup[c as usize] };
            if v == 255 {
                return Err("base64: a character outside the alphabet".into());
            }
            n = n << 6 | v as u32;
        }
        let three = [(n >> 16) as u8, (n >> 8) as u8, n as u8];
        out.extend_from_slice(&three[..3 - pad.min(2)]);
    }
    Ok(out)
}

// ---- the JSON body ----------------------------------------------------------------------

#[derive(Serialize, Deserialize)]
struct JsonImage {
    id: i64,
    hot_x: i64,
    hot_y: i64,
    w: i64,
    h: i64,
    data: String,
}

#[derive(Serialize, Deserialize)]
struct JsonBody {
    version: i64,
    geometry: Vec<Geometry>,
    images: Vec<JsonImage>,
    moves: Moves,
    clicks: Clicks,
    keys: Keys,
    image_changes: ImageChanges,
}

pub fn to_json(track: &Track) -> Vec<u8> {
    let body = JsonBody {
        version: 1,
        geometry: track.geometry.clone(),
        images: track
            .images
            .iter()
            .map(|i| JsonImage {
                id: i.id,
                hot_x: i.hot_x,
                hot_y: i.hot_y,
                w: i.w,
                h: i.h,
                data: b64_encode(&i.bytes),
            })
            .collect(),
        moves: track.moves.clone(),
        clicks: track.clicks.clone(),
        keys: track.keys.clone(),
        image_changes: track.image_changes.clone(),
    };
    serde_json::to_vec(&body).expect("the JSON body serializes")
}

/// Bytes in memory → a validated track.
pub fn parse_json(bytes: &[u8]) -> Result<Track, String> {
    let body: JsonBody = serde_json::from_slice(bytes).map_err(|e| format!("json: {e}"))?;
    if body.version != 1 {
        return Err(format!("json: version {}", body.version));
    }
    let mut images = Vec::with_capacity(body.images.len());
    for i in body.images {
        images.push(Image {
            id: i.id,
            hot_x: i.hot_x,
            hot_y: i.hot_y,
            w: i.w,
            h: i.h,
            bytes: b64_decode(&i.data)?,
        });
    }
    let track = Track {
        geometry: body.geometry,
        images,
        moves: body.moves,
        clicks: body.clicks,
        keys: body.keys,
        image_changes: body.image_changes,
    };
    validate(&track)?;
    Ok(track)
}

// ---- the binary body --------------------------------------------------------------------

const MAGIC: &[u8; 8] = b"FJCURSB1";

#[derive(Serialize, Deserialize)]
struct BinImage {
    id: i64,
    hot_x: i64,
    hot_y: i64,
    w: i64,
    h: i64,
    len: usize,
}

#[derive(Serialize, Deserialize)]
struct BinHeader {
    version: i64,
    geometry: Vec<Geometry>,
    images: Vec<BinImage>,
    moves: usize,
    clicks: usize,
    keys: usize,
    image_changes: usize,
}

fn columns(track: &Track) -> Vec<&Vec<i64>> {
    let (m, c) = (&track.moves, &track.clicks);
    vec![
        &m.t,
        &m.x,
        &m.y,
        &c.t,
        &c.button,
        &c.down,
        &c.x,
        &c.y,
        &c.count,
        &track.keys.t,
        &track.image_changes.t,
        &track.image_changes.id,
    ]
}

/// MAGIC, the header's length as a little-endian u64, the header (JSON), the twelve i64
/// columns in a fixed order, then the image blobs.
pub fn to_binary(track: &Track) -> Vec<u8> {
    let header = BinHeader {
        version: 1,
        geometry: track.geometry.clone(),
        images: track
            .images
            .iter()
            .map(|i| BinImage {
                id: i.id,
                hot_x: i.hot_x,
                hot_y: i.hot_y,
                w: i.w,
                h: i.h,
                len: i.bytes.len(),
            })
            .collect(),
        moves: track.moves.t.len(),
        clicks: track.clicks.t.len(),
        keys: track.keys.t.len(),
        image_changes: track.image_changes.t.len(),
    };
    let head = serde_json::to_vec(&header).expect("the header serializes");
    let mut out = Vec::new();
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&(head.len() as u64).to_le_bytes());
    out.extend_from_slice(&head);
    for column in columns(track) {
        for v in column {
            out.extend_from_slice(&v.to_le_bytes());
        }
    }
    for image in &track.images {
        out.extend_from_slice(&image.bytes);
    }
    out
}

fn take<'a>(bytes: &'a [u8], at: &mut usize, n: usize) -> Result<&'a [u8], String> {
    let end = at
        .checked_add(n)
        .filter(|&e| e <= bytes.len())
        .ok_or("binary: truncated")?;
    let slice = &bytes[*at..end];
    *at = end;
    Ok(slice)
}

fn column(bytes: &[u8], at: &mut usize, n: usize) -> Result<Vec<i64>, String> {
    let raw = take(bytes, at, n.checked_mul(8).ok_or("binary: overflow")?)?;
    Ok(raw
        .chunks_exact(8)
        .map(|c| i64::from_le_bytes(c.try_into().expect("8 bytes")))
        .collect())
}

/// Bytes in memory → a validated track.
pub fn parse_binary(bytes: &[u8]) -> Result<Track, String> {
    let mut at = 0usize;
    if take(bytes, &mut at, 8)? != MAGIC {
        return Err("binary: not a cursor body".into());
    }
    let len = u64::from_le_bytes(take(bytes, &mut at, 8)?.try_into().expect("8 bytes")) as usize;
    let header: BinHeader =
        serde_json::from_slice(take(bytes, &mut at, len)?).map_err(|e| format!("header: {e}"))?;
    if header.version != 1 {
        return Err(format!("binary: version {}", header.version));
    }
    if header.moves > MAX_MOVES
        || header.clicks > MAX_CLICKS
        || header.keys > MAX_KEYS
        || header.image_changes > MAX_IMAGE_CHANGES
        || header.images.len() > MAX_IMAGES
    {
        return Err("binary: a length is over its cap".into());
    }
    let moves = Moves {
        t: column(bytes, &mut at, header.moves)?,
        x: column(bytes, &mut at, header.moves)?,
        y: column(bytes, &mut at, header.moves)?,
    };
    let n = header.clicks;
    let clicks = Clicks {
        t: column(bytes, &mut at, n)?,
        button: column(bytes, &mut at, n)?,
        down: column(bytes, &mut at, n)?,
        x: column(bytes, &mut at, n)?,
        y: column(bytes, &mut at, n)?,
        count: column(bytes, &mut at, n)?,
    };
    let keys = Keys {
        t: column(bytes, &mut at, header.keys)?,
    };
    let image_changes = ImageChanges {
        t: column(bytes, &mut at, header.image_changes)?,
        id: column(bytes, &mut at, header.image_changes)?,
    };
    let mut images = Vec::with_capacity(header.images.len());
    for i in header.images {
        if i.len > MAX_IMAGE_BYTES {
            return Err("binary: an image is over its cap".into());
        }
        images.push(Image {
            id: i.id,
            hot_x: i.hot_x,
            hot_y: i.hot_y,
            w: i.w,
            h: i.h,
            bytes: take(bytes, &mut at, i.len)?.to_vec(),
        });
    }
    if at != bytes.len() {
        return Err("binary: trailing bytes".into());
    }
    let track = Track {
        geometry: header.geometry,
        images,
        moves,
        clicks,
        keys,
        image_changes,
    };
    validate(&track)?;
    Ok(track)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_round_trips() {
        for n in 0..20usize {
            let bytes: Vec<u8> = (0..n).map(|i| (i * 37 + 11) as u8).collect();
            assert_eq!(b64_decode(&b64_encode(&bytes)).unwrap(), bytes);
        }
    }

    #[test]
    fn both_bodies_round_trip() {
        let mut track = worst_case();
        track.moves.t.truncate(1000);
        track.moves.x.truncate(1000);
        track.moves.y.truncate(1000);
        assert_eq!(parse_json(&to_json(&track)).unwrap(), track);
        assert_eq!(parse_binary(&to_binary(&track)).unwrap(), track);
    }
}
