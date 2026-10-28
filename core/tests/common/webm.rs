//! The WebM writer's test helpers (spec §11 CX-15): an `RcWebm` driven through
//! `rc_webm_*` and freed on drop, the layouts and packets the tests write, and the one
//! full file most of them read back. Shared by `webm_writer.rs` and
//! `webm_writer_refusals.rs`.

use std::ffi::c_char;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicUsize, Ordering};

use serde_json::{json, Value};

use framejob_core::ffi_webm::{
    rc_webm_add_packet, rc_webm_end_track, rc_webm_finish, rc_webm_free, rc_webm_open, RcWebm,
};

use super::ebml_read::Element;
use super::{cstring, take_string};

pub const V: u32 = 1;
pub const A: u32 = 2;
/// An `av1C` record's bytes; the writer carries them opaque.
pub const AV1C: [u8; 10] = [0x81, 0x08, 0x0C, 0x00, 0x0A, 0x0B, 0x00, 0x00, 0x00, 0x2A];
/// HD-5's mastering display and content light level (spec §11 HD-14 (d)).
pub const MDCV: &str = "33c286c41d4c0bb884d03e803d1340420098968000000032";
pub const CLLI: &str = "03e80000";
pub const PRE_SKIP: u16 = 312;
pub const SECOND: i64 = 1_000_000_000;

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// A fresh path in the test's own folder.
pub fn temp_path(name: &str) -> PathBuf {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let dir = std::env::temp_dir().join(format!("framejob-webm-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("temporary folder");
    dir.join(format!(
        "{}-{name}.webm",
        NEXT.fetch_add(1, Ordering::Relaxed)
    ))
}

/// An open `RcWebm`, freed on drop. Shared across threads only by the test
/// that adds from two at once, which the header allows.
pub struct Webm(pub *mut RcWebm);

unsafe impl Send for Webm {}
unsafe impl Sync for Webm {}

impl Drop for Webm {
    fn drop(&mut self) {
        unsafe { rc_webm_free(self.0) };
    }
}

pub fn answer(ok: bool, err: *mut c_char) -> Result<(), String> {
    if ok {
        assert!(err.is_null(), "a true answer writes no err_out");
        Ok(())
    } else {
        Err(take_string(err).expect("a false answer writes err_out"))
    }
}

impl Webm {
    pub fn open(path: &Path, layout: &Value) -> Result<Webm, String> {
        let p = cstring(path.to_str().expect("a UTF-8 path"));
        let l = cstring(&layout.to_string());
        let mut err: *mut c_char = ptr::null_mut();
        let handle = unsafe { rc_webm_open(p.as_ptr(), l.as_ptr(), &mut err) };
        if handle.is_null() {
            return Err(take_string(err).expect("a NULL open writes err_out"));
        }
        assert!(err.is_null());
        Ok(Webm(handle))
    }

    pub fn add(
        &self,
        track: u32,
        pts: i64,
        key: bool,
        discard: i64,
        bytes: &[u8],
    ) -> Result<(), String> {
        let mut err: *mut c_char = ptr::null_mut();
        let ok = unsafe {
            rc_webm_add_packet(
                self.0,
                track,
                pts,
                key,
                discard,
                bytes.as_ptr(),
                bytes.len(),
                &mut err,
            )
        };
        answer(ok, err)
    }

    pub fn end(&self, track: u32) -> Result<(), String> {
        let mut err: *mut c_char = ptr::null_mut();
        let ok = unsafe { rc_webm_end_track(self.0, track, &mut err) };
        answer(ok, err)
    }

    pub fn finish(&self) -> Result<(), String> {
        let mut err: *mut c_char = ptr::null_mut();
        let ok = unsafe { rc_webm_finish(self.0, &mut err) };
        answer(ok, err)
    }
}

pub fn video_layout(fps: [u32; 2], pq: bool) -> Value {
    let mut colour = json!({"matrix": 9, "range": 1, "transfer": 16, "primaries": 9,
                            "bits_per_channel": 10});
    if pq {
        colour["mdcv_hex"] = json!(MDCV);
        colour["clli_hex"] = json!(CLLI);
    }
    json!({"codec_id": "V_AV1", "codec_private_hex": hex(&AV1C), "width": 640, "height": 360,
           "fps": fps, "colour": colour})
}

pub fn audio_layout() -> Value {
    json!({"codec_id": "A_OPUS", "channels": 2, "sample_rate": 48000, "pre_skip": PRE_SKIP})
}

/// The whole two-second layout: video at 30 fps (PQ), Opus, two chapters.
pub fn full_layout() -> Value {
    json!({
        "duration_ns": 2 * SECOND,
        "video": video_layout([30, 1], true),
        "audio": audio_layout(),
        "chapters": [
            {"start_ns": 0, "end_ns": SECOND, "name": "Intro"},
            {"start_ns": SECOND, "end_ns": 2 * SECOND, "name": "Body"}
        ]
    })
}

/// Frame `k`'s bytes: distinct, of varying length.
pub fn frame(k: usize) -> Vec<u8> {
    let mut out = vec![0x12, 0x00, (k & 0xFF) as u8, (k >> 8) as u8];
    out.extend((0..(20 + k % 7)).map(|i| (i * 31 + k) as u8));
    out
}

/// An Opus packet of one 20 ms stereo CELT frame (TOC config 31, code 0).
pub fn opus(k: usize) -> Vec<u8> {
    vec![0xFC, (k & 0xFF) as u8, 0x55, (k >> 8) as u8]
}

/// The video frame's time at `k`, as the app hands it: round(k · 1e9 · den / num).
pub fn frame_ns(k: usize, num: u32, den: u32) -> i64 {
    let scaled = k as i128 * 1_000_000_000 * i128::from(den);
    ((scaled + i128::from(num) / 2) / i128::from(num)) as i64
}

/// Writes the full layout: 60 frames (keys at 0 and 30) first, then 100
/// audio packets, the last with a 5 ms DiscardPadding; ends both, finishes.
pub fn write_full(path: &Path) {
    let w = Webm::open(path, &full_layout()).expect("open");
    for k in 0..60 {
        w.add(V, frame_ns(k, 30, 1), k % 30 == 0, 0, &frame(k))
            .expect("video");
    }
    for k in 0..100 {
        let discard = if k == 99 { 5_000_000 } else { 0 };
        w.add(A, k as i64 * 20_000_000, true, discard, &opus(k))
            .expect("audio");
    }
    w.end(V).expect("end video");
    w.end(A).expect("end audio");
    w.finish().expect("finish");
}

pub fn opus_head() -> Vec<u8> {
    let mut out = b"OpusHead".to_vec();
    out.extend([1, 2]);
    out.extend(PRE_SKIP.to_le_bytes());
    out.extend(48_000u32.to_le_bytes());
    out.extend([0, 0, 0]);
    out
}

pub fn find(e: &Element, id: u32) -> &Element {
    e.child(id)
        .unwrap_or_else(|| panic!("no {id:#x} under {:#x}", e.id))
}
