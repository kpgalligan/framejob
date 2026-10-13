//! An EBML / Matroska WRITER — the independent oracle `container.rs` and
//! `container_timing.rs` build their files with (spec §11 #216-R). It is
//! written from the Matroska and EBML specifications (RFC 8794, RFC 9559),
//! never from `core/src/container*.rs`: every element here is spelled out
//! byte by byte, so a test's expected value comes from what this file wrote
//! and not from what the reader happens to do.
//!
//! It also holds the FFI read-back the two files share (`Opened`), so the
//! pointer dance over `rc_container_*` is written once.

use std::ffi::c_char;
use std::path::PathBuf;
use std::ptr;
use std::sync::atomic::{AtomicUsize, Ordering};

use serde_json::Value;

use framejob_core::container::RcContainerSample;
use framejob_core::ffi_container::{
    rc_container_describe, rc_container_free, rc_container_open, rc_container_retime,
    rc_container_sample, rc_container_sample_count,
};

use super::{cstring, take_string};

// ---- elements --------------------------------------------------------------

/// An element ID's bytes: the ID as the spec writes it, marker included.
pub fn id_bytes(id: u32) -> Vec<u8> {
    let bytes = id.to_be_bytes();
    let first = bytes.iter().position(|b| *b != 0).unwrap_or(3);
    bytes[first..].to_vec()
}

/// A size as the shortest variable-length integer that holds it (the
/// all-ones value of each length is reserved for "unknown").
pub fn vint(n: u64) -> Vec<u8> {
    for len in 1..=8u32 {
        if n < (1u64 << (7 * len)) - 1 {
            let mut out = Vec::new();
            for i in (0..len).rev() {
                out.push((n >> (8 * i)) as u8);
            }
            out[0] |= 0x80 >> (len - 1);
            return out;
        }
    }
    panic!("size {n} does not fit a vint");
}

/// The eight-byte unknown size.
pub fn unknown() -> Vec<u8> {
    vec![0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
}

pub fn element(id: u32, body: &[u8]) -> Vec<u8> {
    let mut out = id_bytes(id);
    out.extend(vint(body.len() as u64));
    out.extend_from_slice(body);
    out
}

pub fn master(id: u32, children: &[Vec<u8>]) -> Vec<u8> {
    element(id, &children.concat())
}

pub fn master_unknown(id: u32, children: &[Vec<u8>]) -> Vec<u8> {
    let mut out = id_bytes(id);
    out.extend(unknown());
    out.extend(children.concat());
    out
}

pub fn uint(id: u32, v: u64) -> Vec<u8> {
    let bytes = v.to_be_bytes();
    let first = bytes.iter().position(|b| *b != 0).unwrap_or(7);
    element(id, &bytes[first..])
}

pub fn float(id: u32, v: f64) -> Vec<u8> {
    element(id, &v.to_be_bytes())
}

pub fn string(id: u32, s: &str) -> Vec<u8> {
    element(id, s.as_bytes())
}

// ---- the file ----------------------------------------------------------------

pub const SEGMENT: u32 = 0x1853_8067;
pub const CLUSTER: u32 = 0x1F43_B675;
pub const CUES: u32 = 0x1C53_BB6B;

pub fn ebml_header(doc_type: &str) -> Vec<u8> {
    master(
        0x1A45_DFA3,
        &[
            uint(0x4286, 1),
            uint(0x42F7, 1),
            uint(0x42F2, 4),
            uint(0x42F3, 8),
            string(0x4282, doc_type),
            uint(0x4287, 4),
            uint(0x4285, 2),
        ],
    )
}

pub fn info(timestamp_scale: u64) -> Vec<u8> {
    master(
        0x1549_A966,
        &[uint(0x2A_D7B1, timestamp_scale), string(0x4D80, "ebml.rs")],
    )
}

/// One TrackEntry. `kind` 1 is video, 2 audio, 0x11 subtitles.
#[derive(Clone, Default)]
pub struct Track {
    pub number: u64,
    pub kind: u64,
    pub codec_id: String,
    pub private: Vec<u8>,
    pub default_duration: Option<u64>,
    pub codec_delay: Option<u64>,
    pub encoded: bool,
    pub width: u64,
    pub height: u64,
    /// (matrix, range, transfer, primaries) as a Colour element.
    pub colour: Option<(u64, u64, u64, u64)>,
    pub rate: f64,
    pub channels: u64,
}

impl Track {
    pub fn video(number: u64, codec_id: &str) -> Track {
        Track {
            number,
            kind: 1,
            codec_id: codec_id.to_string(),
            width: 640,
            height: 360,
            ..Track::default()
        }
    }

    pub fn audio(number: u64, codec_id: &str, rate: f64) -> Track {
        Track {
            number,
            kind: 2,
            codec_id: codec_id.to_string(),
            rate,
            channels: 2,
            ..Track::default()
        }
    }

    pub fn entry(&self) -> Vec<u8> {
        let mut c = vec![
            uint(0xD7, self.number),
            uint(0x73C5, self.number),
            uint(0x83, self.kind),
            string(0x86, &self.codec_id),
        ];
        if !self.private.is_empty() {
            c.push(element(0x63A2, &self.private));
        }
        if let Some(d) = self.default_duration {
            c.push(uint(0x23_E383, d));
        }
        if let Some(d) = self.codec_delay {
            c.push(uint(0x56AA, d));
        }
        if self.encoded {
            let encoding = master(
                0x6240,
                &[uint(0x5032, 1), master(0x5034, &[uint(0x4254, 0)])],
            );
            c.push(master(0x6D80, &[encoding]));
        }
        if self.kind == 1 {
            let mut v = vec![uint(0xB0, self.width), uint(0xBA, self.height)];
            if let Some((m, r, t, p)) = self.colour {
                v.push(master(
                    0x55B0,
                    &[
                        uint(0x55B1, m),
                        uint(0x55B9, r),
                        uint(0x55BA, t),
                        uint(0x55BB, p),
                    ],
                ));
            }
            c.push(master(0xE0, &v));
        }
        if self.kind == 2 {
            c.push(master(
                0xE1,
                &[float(0xB5, self.rate), uint(0x9F, self.channels)],
            ));
        }
        master(0xAE, &c)
    }
}

pub fn tracks(list: &[Track]) -> Vec<u8> {
    let entries: Vec<Vec<u8>> = list.iter().map(Track::entry).collect();
    master(0x1654_AE6B, &entries)
}

/// How a Block's frames are laced.
#[derive(Clone, Copy, PartialEq)]
pub enum Lacing {
    None,
    Xiph,
    Fixed,
    Ebml,
}

/// A signed EBML lace delta: the value plus half the range of its length.
fn signed_vint(delta: i64) -> Vec<u8> {
    for len in 1..=8u32 {
        let bias = (1i64 << (7 * len - 1)) - 1;
        if delta > -bias && delta < bias {
            let raw = (delta + bias) as u64;
            let mut out = Vec::new();
            for i in (0..len).rev() {
                out.push((raw >> (8 * i)) as u8);
            }
            out[0] |= 0x80 >> (len - 1);
            return out;
        }
    }
    panic!("delta {delta} does not fit");
}

/// A Block's body: track, relative time, flags, lace and the frames.
pub fn block_body(track: u64, rel: i16, flags: u8, lacing: Lacing, frames: &[Vec<u8>]) -> Vec<u8> {
    let mut out = vint(track);
    out.extend(rel.to_be_bytes());
    let bits = match lacing {
        Lacing::None => 0,
        Lacing::Xiph => 1,
        Lacing::Fixed => 2,
        Lacing::Ebml => 3,
    };
    out.push(flags | (bits << 1));
    if lacing != Lacing::None {
        out.push((frames.len() - 1) as u8);
    }
    match lacing {
        Lacing::Xiph => {
            for f in &frames[..frames.len() - 1] {
                let mut n = f.len();
                while n >= 255 {
                    out.push(255);
                    n -= 255;
                }
                out.push(n as u8);
            }
        }
        Lacing::Ebml => {
            out.extend(vint(frames[0].len() as u64));
            for w in frames[..frames.len() - 1].windows(2) {
                out.extend(signed_vint(w[1].len() as i64 - w[0].len() as i64));
            }
        }
        Lacing::Fixed | Lacing::None => {}
    }
    for f in frames {
        out.extend_from_slice(f);
    }
    out
}

pub fn simple_block(
    track: u64,
    rel: i16,
    key: bool,
    lacing: Lacing,
    frames: &[Vec<u8>],
) -> Vec<u8> {
    element(
        0xA3,
        &block_body(track, rel, if key { 0x80 } else { 0 }, lacing, frames),
    )
}

/// A BlockGroup; `reference` adds a ReferenceBlock, which makes it a
/// non-keyframe.
pub fn block_group(track: u64, rel: i16, reference: bool, frames: &[Vec<u8>]) -> Vec<u8> {
    let lacing = if frames.len() > 1 {
        Lacing::Xiph
    } else {
        Lacing::None
    };
    let mut c = vec![element(0xA1, &block_body(track, rel, 0, lacing, frames))];
    if reference {
        c.push(element(0xFB, &[0xFF]));
    }
    c.push(uint(0x9B, 1));
    master(0xA0, &c)
}

pub fn cluster(timestamp: u64, blocks: &[Vec<u8>]) -> Vec<u8> {
    let mut c = vec![uint(0xE7, timestamp)];
    c.extend_from_slice(blocks);
    master(CLUSTER, &c)
}

pub fn cluster_unknown(timestamp: u64, blocks: &[Vec<u8>]) -> Vec<u8> {
    let mut c = vec![uint(0xE7, timestamp)];
    c.extend_from_slice(blocks);
    master_unknown(CLUSTER, &c)
}

/// A whole file: the EBML header and one Segment holding `children`.
pub fn file(doc_type: &str, children: &[Vec<u8>], unknown_segment: bool) -> Vec<u8> {
    let mut out = ebml_header(doc_type);
    if unknown_segment {
        out.extend(master_unknown(SEGMENT, children));
    } else {
        out.extend(master(SEGMENT, children));
    }
    out
}

/// A payload whose every byte says which frame it is, so a read-back at
/// the wrong offset is caught.
pub fn payload(tag: u8, len: usize) -> Vec<u8> {
    (0..len).map(|i| tag.wrapping_add((i % 7) as u8)).collect()
}

// ---- codec bytes ---------------------------------------------------------------

/// Bits written most significant first.
#[derive(Default)]
pub struct BitWriter {
    bytes: Vec<u8>,
    bits: usize,
}

impl BitWriter {
    pub fn put(&mut self, value: u32, n: usize) {
        for i in (0..n).rev() {
            if self.bits.is_multiple_of(8) {
                self.bytes.push(0);
            }
            let bit = ((value >> i) & 1) as u8;
            let last = self.bytes.len() - 1;
            self.bytes[last] |= bit << (7 - self.bits % 8);
            self.bits += 1;
        }
    }

    pub fn finish(mut self, pad_to: usize) -> Vec<u8> {
        self.bytes.resize(pad_to.max(self.bytes.len()), 0x55);
        self.bytes
    }
}

/// A VP9 keyframe's uncompressed header (VP9 bitstream spec §6.2) as far
/// as its colour config, padded with stand-in bytes.
pub fn vp9_keyframe(
    profile: u32,
    twelve_bit: bool,
    space: u32,
    full: u32,
    sub: (u32, u32),
) -> Vec<u8> {
    let mut w = BitWriter::default();
    w.put(2, 2); // frame_marker
    w.put(profile & 1, 1);
    w.put(profile >> 1, 1);
    if profile == 3 {
        w.put(0, 1);
    }
    w.put(0, 1); // show_existing_frame
    w.put(0, 1); // frame_type: KEY_FRAME
    w.put(1, 1); // show_frame
    w.put(0, 1); // error_resilient_mode
    w.put(0x49_8342, 24);
    if profile >= 2 {
        w.put(u32::from(twelve_bit), 1);
    }
    w.put(space, 3);
    if space != 7 {
        w.put(full, 1);
        if profile == 1 || profile == 3 {
            w.put(sub.0, 1);
            w.put(sub.1, 1);
            w.put(0, 1);
        }
    } else if profile == 1 || profile == 3 {
        w.put(0, 1);
    }
    w.finish(40)
}

/// An Opus packet: its TOC byte (config, stereo 0, code), the frame-count
/// byte for code 3, then filler.
pub fn opus_packet(config: u8, code: u8, count: u8, len: usize) -> Vec<u8> {
    let mut out = vec![(config << 3) | code];
    if code == 3 {
        out.push(count & 0x3F);
    }
    out.resize(len.max(out.len()), 0xA5);
    out
}

pub fn opus_head() -> Vec<u8> {
    let mut h = b"OpusHead".to_vec();
    h.extend([1, 2, 0x38, 0x01, 0x80, 0xBB, 0, 0, 0, 0, 0]);
    h
}

// ---- reading it back -------------------------------------------------------------

/// Writes `bytes` to a fresh file in the test's own temporary folder,
/// numbered so tests running in parallel never share one.
pub fn write_temp(name: &str, bytes: &[u8]) -> PathBuf {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let dir = std::env::temp_dir().join(format!("framejob-container-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("temporary folder");
    let path = dir.join(format!("{}-{name}", NEXT.fetch_add(1, Ordering::Relaxed)));
    std::fs::write(&path, bytes).expect("temporary file");
    path
}

/// An open `RcContainer`, freed on drop.
pub struct Opened(*mut framejob_core::container::Container);

impl Drop for Opened {
    fn drop(&mut self) {
        unsafe { rc_container_free(self.0) };
    }
}

/// `rc_container_open` on `bytes` written to a file named `name`.
pub fn open(name: &str, bytes: &[u8]) -> Result<Opened, String> {
    let path = write_temp(name, bytes);
    let c = cstring(path.to_str().expect("a UTF-8 temporary path"));
    let mut err: *mut c_char = ptr::null_mut();
    let handle = unsafe { rc_container_open(c.as_ptr(), &mut err) };
    let _ = std::fs::remove_file(&path);
    if handle.is_null() {
        return Err(take_string(err).expect("a NULL open writes err_out"));
    }
    assert!(err.is_null(), "a successful open writes no err_out");
    Ok(Opened(handle))
}

impl Opened {
    pub fn describe(&self) -> Value {
        let json = take_string(unsafe { rc_container_describe(self.0) }).expect("describe");
        serde_json::from_str(&json).expect("describe answers JSON")
    }

    pub fn retime(&mut self, num: i64, den: i64) -> bool {
        unsafe { rc_container_retime(self.0, num, den) }
    }

    pub fn samples(&self, track: u32) -> Vec<RcContainerSample> {
        let n = unsafe { rc_container_sample_count(self.0, track) };
        let mut out = Vec::new();
        for i in 0..n {
            let mut s = RcContainerSample::default();
            assert!(unsafe { rc_container_sample(self.0, track, i, &mut s) });
            out.push(s);
        }
        let mut past = RcContainerSample::default();
        assert!(!unsafe { rc_container_sample(self.0, track, n, &mut past) });
        out
    }
}
