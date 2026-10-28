//! The WebM writer (spec §11 CX-6, CX-15): one file of AV1 video and Opus
//! sound, written from compressed packets the app hands in as opaque bytes.
//! Nothing here encodes or decodes; it decides the container — the header,
//! the timestamps, the interleave, the Clusters and the Cues.
//!
//! **The layout** (CX-15 (3)) is fixed at `open` from a [`WebmLayout`]
//! (`webm_layout.rs`, which checks it and builds its elements): the
//! EBML header (DocType `webm` 4/2), a Segment whose size is patched at
//! `finish`, a Void reserved for the SeekHead `finish` writes over it, Info,
//! Tracks and, when there are any, Chapters. Clusters follow as packets
//! arrive, and Cues close the file. Element bytes are `webm_ebml.rs`'s.
//!
//! **The interleave** (CX-15 (4)): each declared track has a queue, and the
//! earliest head (by its millisecond time, video first among equal times) is
//! written only while every declared track that has not ended has a head,
//! so the file's blocks are in nondecreasing time whatever order two pumps
//! deliver them in. `end_track` releases a track's claim; a layout with one
//! track writes each packet as it arrives. Each call ends with a flush, so
//! what was written is on disk when it returns.
//!
//! **Clusters** start before each video key block, and before a block whose
//! time would pass the 16-bit relative limit (32,767 ms); a Cluster's size is
//! written unknown and patched when the next one starts. Each key-started
//! Cluster is a CuePoint.

use std::collections::VecDeque;
use std::fs::File;
use std::io::{BufWriter, Seek, SeekFrom, Write};
use std::path::Path;

use crate::webm_ebml as ebml;
pub use crate::webm_layout::WebmLayout;

/// The track number of the video track, and `add_packet`'s argument for it.
pub const VIDEO: u32 = 1;
/// The track number of the audio track.
pub const AUDIO: u32 = 2;

/// The bytes reserved after the Segment's header for the SeekHead: four
/// entries take 89 (`ebml::seek_head`), and the rest stays a Void.
const SEEK_RESERVE: usize = 96;
/// The largest time a block may sit after its Cluster's, in ms.
const MAX_RELATIVE_MS: u64 = 32_767;

struct Packet {
    ms: u64,
    key: bool,
    discard_ns: i64,
    bytes: Vec<u8>,
}

#[derive(Default)]
struct Track {
    queue: VecDeque<Packet>,
    last_ns: Option<i64>,
    ended: bool,
}

/// The open Cluster: where its size is to be patched, and its time.
struct Cluster {
    size_at: u64,
    ms: u64,
}

/// One WebM file being written.
pub struct WebmWriter {
    file: Option<BufWriter<File>>,
    pos: u64,
    segment_data: u64,
    level_one: Vec<(u32, u64)>,
    tracks: [Option<Track>; 2],
    cluster: Option<Cluster>,
    cues: Vec<(u64, u64)>,
    failed: bool,
}

impl WebmWriter {
    /// Checks `layout` (JSON), creates the file at `path` and writes
    /// everything up to the first Cluster.
    pub fn open(path: &Path, layout: &str) -> Result<WebmWriter, String> {
        let head = WebmLayout::header(layout)?;
        let file =
            File::create(path).map_err(|e| format!("the file could not be created ({e})"))?;
        let mut w = WebmWriter {
            file: Some(BufWriter::new(file)),
            pos: 0,
            segment_data: 0,
            level_one: Vec::new(),
            tracks: [
                head.video.then(Track::default),
                head.audio.then(Track::default),
            ],
            cluster: None,
            cues: Vec::new(),
            failed: false,
        };
        w.put(&ebml::ebml_header())?;
        w.put(&ebml::id(ebml::SEGMENT))?;
        w.put(&ebml::UNKNOWN_SIZE)?;
        w.segment_data = w.pos;
        w.put(&ebml::void(SEEK_RESERVE))?;
        let level_one = [
            Some((ebml::INFO, head.info)),
            Some((ebml::TRACKS, head.tracks)),
            head.chapters.map(|bytes| (ebml::CHAPTERS, bytes)),
        ];
        for (id, bytes) in level_one.into_iter().flatten() {
            w.level_one.push((id, w.pos - w.segment_data));
            w.put(&bytes)?;
        }
        w.flush()?;
        Ok(w)
    }

    /// Queues one packet of `track` and writes whatever the interleave
    /// allows. `pts_ns` must be at or after 0 and after the track's last.
    pub fn add_packet(
        &mut self,
        track: u32,
        pts_ns: i64,
        key: bool,
        discard_padding_ns: i64,
        bytes: &[u8],
    ) -> Result<(), String> {
        let t = self.track(track)?;
        if pts_ns < 0 {
            return Err(format!("pts {pts_ns} ns on track {track} is negative"));
        }
        if let Some(last) = t.last_ns.filter(|last| pts_ns <= *last) {
            return Err(format!(
                "pts {pts_ns} ns on track {track} is not after its last, {last} ns"
            ));
        }
        t.last_ns = Some(pts_ns);
        // round-half-up(pts_ns / 1e6) ms.
        let ms = (pts_ns as u64).saturating_add(500_000) / 1_000_000;
        t.queue.push_back(Packet {
            ms,
            key,
            discard_ns: discard_padding_ns,
            bytes: bytes.to_vec(),
        });
        self.drain(false)?;
        self.flush()
    }

    /// Ends `track`: no packet follows, and the others no longer wait for it.
    pub fn end_track(&mut self, track: u32) -> Result<(), String> {
        self.track(track)?.ended = true;
        self.drain(false)?;
        self.flush()
    }

    /// Writes every queued packet, the Cues, the SeekHead and the Segment's
    /// size, and closes the file. Nothing may be added after it.
    pub fn finish(&mut self) -> Result<(), String> {
        self.check_open()?;
        for t in self.tracks.iter_mut().flatten() {
            t.ended = true;
        }
        self.drain(true)?;
        self.close_cluster()?;
        let mut seeks = self.level_one.clone();
        if !self.cues.is_empty() {
            seeks.push((ebml::CUES, self.pos - self.segment_data));
            let cues = ebml::cues(&self.cues);
            self.put(&cues)?;
        }
        let mut head = ebml::seek_head(&seeks);
        head.extend(ebml::void(SEEK_RESERVE - head.len()));
        self.patch(self.segment_data, &head)?;
        let size = ebml::size8(self.pos - self.segment_data);
        self.patch(self.segment_data - 8, &size)?;
        self.flush()?;
        self.file = None;
        Ok(())
    }

    // ---- the interleave -----------------------------------------------------

    fn check_open(&self) -> Result<(), String> {
        if self.file.is_none() {
            return Err("the file is finished".to_string());
        }
        if self.failed {
            return Err("the file could not be written earlier".to_string());
        }
        Ok(())
    }

    /// The open track `number`, or the sentence refusing it.
    fn track(&mut self, number: u32) -> Result<&mut Track, String> {
        self.check_open()?;
        let slot = match number {
            VIDEO => self.tracks[0].as_mut(),
            AUDIO => self.tracks[1].as_mut(),
            _ => None,
        };
        let t = slot.ok_or_else(|| format!("track {number} is not in the layout"))?;
        if t.ended {
            return Err(format!("track {number} has ended"));
        }
        Ok(t)
    }

    /// Writes heads while the interleave allows; `all` writes every one.
    fn drain(&mut self, all: bool) -> Result<(), String> {
        loop {
            let waiting = self
                .tracks
                .iter()
                .flatten()
                .any(|t| !t.ended && t.queue.is_empty());
            if waiting && !all {
                return Ok(());
            }
            let next = (0..2)
                .filter_map(|i| {
                    let head = self.tracks[i].as_ref()?.queue.front()?;
                    Some((head.ms, i))
                })
                .min();
            let Some((_, i)) = next else {
                return Ok(());
            };
            let Some(packet) = self.tracks[i].as_mut().and_then(|t| t.queue.pop_front()) else {
                return Ok(());
            };
            self.write_block(i as u32 + 1, &packet)?;
        }
    }

    fn write_block(&mut self, track: u32, p: &Packet) -> Result<(), String> {
        let video_key = track == VIDEO && p.key;
        let fresh = match &self.cluster {
            None => true,
            Some(c) => video_key || p.ms.saturating_sub(c.ms) > MAX_RELATIVE_MS,
        };
        if fresh {
            self.close_cluster()?;
            if video_key {
                self.cues.push((p.ms, self.pos - self.segment_data));
            }
            self.put(&ebml::id(ebml::CLUSTER))?;
            let size_at = self.pos;
            self.put(&ebml::UNKNOWN_SIZE)?;
            self.put(&ebml::uint(ebml::TIMESTAMP, p.ms))?;
            self.cluster = Some(Cluster { size_at, ms: p.ms });
        }
        let base = self.cluster.as_ref().map_or(p.ms, |c| c.ms);
        let relative = i16::try_from(p.ms.saturating_sub(base)).unwrap_or(i16::MAX);
        let element = if p.discard_ns > 0 {
            ebml::block_group(
                &ebml::block_body(track, relative, 0, &p.bytes),
                p.discard_ns,
            )
        } else {
            let flags = if track == AUDIO || p.key { 0x80 } else { 0 };
            ebml::binary(
                ebml::SIMPLE_BLOCK,
                &ebml::block_body(track, relative, flags, &p.bytes),
            )
        };
        self.put(&element)
    }

    fn close_cluster(&mut self) -> Result<(), String> {
        if let Some(c) = self.cluster.take() {
            let size = ebml::size8(self.pos - c.size_at - 8);
            self.patch(c.size_at, &size)?;
        }
        Ok(())
    }

    // ---- the file -----------------------------------------------------------

    fn io<T>(&mut self, result: std::io::Result<T>) -> Result<T, String> {
        result.map_err(|e| {
            self.failed = true;
            format!("the file could not be written ({e})")
        })
    }

    fn put(&mut self, bytes: &[u8]) -> Result<(), String> {
        let Some(file) = self.file.as_mut() else {
            return Err("the file is finished".to_string());
        };
        let written = file.write_all(bytes);
        self.io(written)?;
        self.pos += bytes.len() as u64;
        Ok(())
    }

    /// Overwrites `bytes` at `at`, then returns to the end.
    fn patch(&mut self, at: u64, bytes: &[u8]) -> Result<(), String> {
        let end = self.pos;
        let Some(file) = self.file.as_mut() else {
            return Err("the file is finished".to_string());
        };
        let done = file
            .seek(SeekFrom::Start(at))
            .and_then(|_| file.write_all(bytes))
            .and_then(|_| file.seek(SeekFrom::Start(end)));
        self.io(done).map(|_| ())
    }

    fn flush(&mut self) -> Result<(), String> {
        let Some(file) = self.file.as_mut() else {
            return Ok(());
        };
        let flushed = file.flush();
        self.io(flushed)
    }
}
