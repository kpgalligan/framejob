//! A WebM or Matroska file being imported, read as an INDEX (spec §11
//! #216-R): its first video track and its first audio track, and where
//! each of their frames lies in the file. The app copies those frames,
//! unchanged, into a QuickTime movie; nothing here decodes a frame or
//! touches a sample.
//!
//! This is byte parsing of untrusted input, so every read is bounds-checked
//! and every arithmetic step checked: a header element that cannot be read
//! refuses the file in a sentence naming it, and a damaged or truncated
//! Cluster tail ends the index (`container_blocks.rs`). The file is opened
//! read-only and read through a buffered reader; the only payload bytes read
//! are the first VP9 keyframe's header (its `vpcC`), each Opus packet's
//! first two bytes (its TOC, RFC 6716 §3.1) and each Vorbis packet's first
//! byte (its mode, spec §11 #228-V), all through positioned reads.
//!
//! The EBML header, Segment, Info and Tracks are read by
//! `container_header.rs`, the Cluster walk is `container_blocks.rs`, the
//! codec records `container_codec.rs`, the Vorbis headers and packet
//! counts `container_vorbis.rs`, the times and the space estimate
//! `container_timing.rs`, and the C surface `ffi_container.rs`.

use std::fs::File;
use std::path::Path;

use serde_json::{json, Value};

use crate::container_blocks::{walk, Frame};
use crate::container_codec as codec;
use crate::container_header::{header, Entry, Source};
use crate::container_timing::{self as timing, Timing};
use crate::container_vorbis::Vorbis;
use crate::time::Fps;

/// `rc_container_sample`'s track argument for the video track.
pub const VIDEO: u32 = 0;
/// `rc_container_sample`'s track argument for the audio track.
pub const AUDIO: u32 = 1;

/// One copied frame as the writer needs it: where its bytes are, and its
/// times in the track's described `timescale`. Laid out as the header's
/// `RcContainerSample`.
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct RcContainerSample {
    pub offset: u64,
    pub size: u32,
    /// Audio: the samples in this packet (0 = describe's
    /// `frames_per_packet`). Video: 0.
    pub frames: u32,
    pub pts: i64,
    pub dts: i64,
    pub duration: i64,
    pub sync: bool,
}

// ---- the container ------------------------------------------------------

struct Video {
    codec_id: String,
    fourcc: Option<&'static str>,
    encoded: bool,
    width: u64,
    height: u64,
    atom: Option<(&'static str, Vec<u8>)>,
    vp9_profile: Option<u8>,
    frames: Vec<Frame>,
    ns: Vec<i64>,
    raw: Timing,
    nominal_fps: Option<f64>,
    timing: Timing,
}

struct Audio {
    codec_id: String,
    fourcc: Option<&'static str>,
    encoded: bool,
    rate: i64,
    channels: u64,
    cookie: Vec<u8>,
    per_packet: bool,
    frames: Vec<Frame>,
    counts: Vec<u32>,
    timing: Timing,
}

/// A WebM or Matroska file's first video and first audio track, indexed.
pub struct Container {
    doc_type: String,
    video: Option<Video>,
    audio: Option<Audio>,
}

impl Container {
    /// Reads and indexes the whole file at `path`, read-only.
    pub fn open(path: &Path) -> Result<Container, String> {
        let file = File::open(path).map_err(|e| format!("the file could not be opened ({e})"))?;
        let len = file
            .metadata()
            .map_err(|e| format!("its size is unknown ({e})"))?
            .len();
        let mut src = Source::new(file, len);
        let head = header(&mut src)?;
        let pick = |kind| head.entries.iter().find(|e| e.kind == kind && e.number > 0);
        let (v, a) = (pick(1), pick(2));
        let [video_frames, audio_frames] = match head.first_cluster {
            Some(start) => {
                let wanted = [v.map(|e| e.number), a.map(|e| e.number)];
                walk(&mut src, start, head.end, head.scale, wanted)
            }
            None => [Vec::new(), Vec::new()],
        };
        let video = match v.filter(|_| !video_frames.is_empty()) {
            Some(e) => Some(video(&src, e, video_frames, head.scale)?),
            None => None,
        };
        let audio = a
            .filter(|_| !audio_frames.is_empty())
            .map(|e| audio(&src, e, audio_frames));
        Ok(Container {
            doc_type: head.doc_type,
            video,
            audio,
        })
    }

    /// The JSON `rc_container_describe` answers (the header's keys).
    pub fn describe(&self) -> Value {
        let v = self.video.as_ref();
        let a = self.audio.as_ref();
        let copied = |t: &Timing, sizes: &[Frame]| -> (u64, u64) {
            if t.pts.is_empty() {
                return (0, 0);
            }
            (
                t.pts.len() as u64,
                sizes.iter().map(|f| u64::from(f.size)).sum(),
            )
        };
        let vc = v.map_or((0, 0), |v| copied(&v.timing, &v.frames));
        let ac = a.map_or((0, 0), |a| copied(&a.timing, &a.frames));
        let video = v.map_or(Value::Null, |v| {
            json!({
                "codec_id": v.codec_id, "fourcc": v.fourcc, "encoded": v.encoded,
                "width": v.width, "height": v.height,
                "atom": v.atom.as_ref().map(|(name, _)| *name),
                "atom_hex": v.atom.as_ref().map(|(_, bytes)| codec::hex(bytes)),
                "vp9_profile": v.vp9_profile, "nominal_fps": v.nominal_fps,
                "timescale": v.timing.timescale, "grid": v.timing.grid,
                "samples": vc.0, "bytes": vc.1,
            })
        });
        let audio = a.map_or(Value::Null, |a| {
            json!({
                "codec_id": a.codec_id, "fourcc": a.fourcc, "encoded": a.encoded,
                "sample_rate": a.rate, "channels": a.channels,
                "cookie_hex": codec::hex(&a.cookie),
                "frames_per_packet": if a.per_packet { 0 } else { 1024 },
                "timescale": a.timing.timescale, "samples": ac.0, "bytes": ac.1,
            })
        });
        json!({
            "doc_type": self.doc_type,
            "required_bytes": timing::required_bytes(vc, ac),
            "video": video, "audio": audio,
        })
    }

    /// Snaps the video to `fps`'s grid when it lies on it; true when it did.
    /// Otherwise the raw times stay, and so does their timescale.
    pub fn retime(&mut self, fps: Fps) -> bool {
        let Some(v) = self.video.as_mut().filter(|v| !v.timing.pts.is_empty()) else {
            return false;
        };
        match timing::snapped_video(&v.ns, fps) {
            Some(snapped) => {
                v.timing = snapped;
                true
            }
            None => {
                v.timing = v.raw.clone();
                false
            }
        }
    }

    /// How many samples of `track` are copied (0 for a track that is not).
    pub fn sample_count(&self, track: u32) -> u64 {
        match track {
            VIDEO => self.video.as_ref().map_or(0, |v| v.timing.pts.len() as u64),
            AUDIO => self.audio.as_ref().map_or(0, |a| a.timing.pts.len() as u64),
            _ => 0,
        }
    }

    /// The `index`th copied sample of `track`, in decode order.
    pub fn sample(&self, track: u32, index: u64) -> Option<RcContainerSample> {
        let i = usize::try_from(index).ok()?;
        let (frame, t, frames, sync) = match track {
            VIDEO => {
                let v = self.video.as_ref()?;
                let f = v.frames.get(i).filter(|_| i < v.timing.pts.len())?;
                (f, &v.timing, 0, f.key)
            }
            AUDIO => {
                let a = self.audio.as_ref()?;
                let f = a.frames.get(i).filter(|_| i < a.timing.pts.len())?;
                (
                    f,
                    &a.timing,
                    if a.per_packet { a.counts[i] } else { 0 },
                    true,
                )
            }
            _ => return None,
        };
        Some(RcContainerSample {
            offset: frame.offset,
            size: frame.size,
            frames,
            pts: t.pts[i],
            dts: t.dts[i],
            duration: t.duration[i],
            sync,
        })
    }
}

fn video(src: &Source, e: &Entry, frames: Vec<Frame>, scale: u64) -> Result<Video, String> {
    let fourcc = codec::video_fourcc(&e.codec_id, &e.private);
    let copied = fourcc.is_some() && !e.encoded;
    if copied && e.default_duration.is_none() && frames.iter().any(|f| f.lace > 0) {
        return Err(format!(
            "track {} has laced video Blocks and no DefaultDuration, so its frames have no times",
            e.number
        ));
    }
    let mut atom = codec::private_atom(&e.codec_id).map(|name| (name, e.private.clone()));
    let mut vp9_profile = None;
    // An encoded track is not copied, so its (encrypted or stripped) keyframe
    // is never read: `precheck` refuses it by its own sentence.
    if copied && fourcc == Some("vp09") {
        let key = frames.iter().find(|f| f.key && f.lace == 0);
        let bytes = key.and_then(|f| src.read_at(f.offset, 64.min(f.size as usize)));
        let synth = bytes.and_then(|b| codec::vpcc(&b, &e.colour));
        let (record, profile) = synth.ok_or_else(|| {
            format!(
                "the first VP9 keyframe on track {} could not be read",
                e.number
            )
        })?;
        atom = Some(("vpcC", record));
        vp9_profile = Some(profile);
    }
    let ns = timing::video_ns(&frames, e.default_duration);
    let raw = if copied {
        timing::raw_video(&ns, scale, e.default_duration)
    } else {
        Timing::empty(timing::raw_timescale(scale))
    };
    Ok(Video {
        codec_id: e.codec_id.clone(),
        fourcc,
        encoded: e.encoded,
        width: e.width,
        height: e.height,
        atom,
        vp9_profile,
        nominal_fps: timing::nominal_fps(&ns, e.default_duration),
        frames,
        ns,
        timing: raw.clone(),
        raw,
    })
}

fn audio(src: &Source, e: &Entry, frames: Vec<Frame>) -> Audio {
    let fourcc = codec::audio_fourcc(&e.codec_id, &e.private);
    let opus = fourcc == Some("opus");
    // `audio_fourcc` said `vorb` only for headers that parse.
    let vorbis = match fourcc {
        Some("vorb") => Vorbis::parse(&e.private),
        _ => None,
    };
    // Opus is always timed at 48 kHz, whatever the track's own rate says;
    // Vorbis at its identification header's rate.
    let rate = match (e.rate, &vorbis) {
        (_, Some(v)) => i64::from(v.rate),
        _ if opus => 48_000,
        (r, None) if r.is_finite() && r >= 1.0 => r.round().min(1e7) as i64,
        _ => 8000,
    };
    let channels = vorbis
        .as_ref()
        .map_or(e.channels, |v| u64::from(v.channels));
    let copied = fourcc.is_some() && !e.encoded;
    let counts: Vec<u32> = match (copied, opus, &vorbis) {
        (false, _, _) => Vec::new(),
        (true, true, _) => frames
            .iter()
            .map(|f| codec::opus_samples(&src.read_at(f.offset, 2).unwrap_or_default()))
            .collect(),
        (true, false, Some(v)) => {
            let first = |f: &Frame| {
                src.read_at(f.offset, 1.min(f.size as usize))
                    .and_then(|b| b.first().copied())
            };
            v.counts(&frames.iter().map(first).collect::<Vec<_>>())
        }
        (true, false, None) => vec![1024; frames.len()],
    };
    // Every Vorbis packet moves later by packet 0's count (spec §11
    // #228-V); only a copied track has counts to read it from.
    let lead = match (&vorbis, counts.first()) {
        (Some(_), Some(n)) if copied => i64::from(*n),
        _ => 0,
    };
    let timing = if copied {
        timing::audio(&frames, &counts, e.codec_delay, rate, lead)
    } else {
        Timing::empty(rate)
    };
    let cookie = match fourcc {
        Some("aac ") => codec::esds(&e.private),
        Some(_) => e.private.clone(),
        None => Vec::new(),
    };
    Audio {
        codec_id: e.codec_id.clone(),
        fourcc,
        encoded: e.encoded,
        rate,
        channels,
        cookie,
        per_packet: opus || vorbis.is_some(),
        frames,
        counts,
        timing,
    }
}
