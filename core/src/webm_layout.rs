//! The WebM writer's layout (spec §11 CX-15 (3)): `rc_webm_open`'s JSON as
//! [`WebmLayout`], every value checked in a lowercase sentence naming it, and
//! the level-1 elements `webm_writer.rs` writes before the first Cluster —
//! Info, Tracks and Chapters — built through `webm_ebml.rs`. Split out of
//! `webm_writer.rs` so each stays under the 400-line cap for a new module.

use serde::Deserialize;

use crate::container_codec::{light_from_clli, mastering_from_mdcv};
use crate::webm_ebml::{self as ebml, ColourOut};

/// The file's shape, as `rc_webm_open`'s JSON.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WebmLayout {
    pub duration_ns: u64,
    pub video: Option<VideoLayout>,
    pub audio: Option<AudioLayout>,
    #[serde(default)]
    pub chapters: Vec<ChapterLayout>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VideoLayout {
    pub codec_id: String,
    /// The `av1C` record on `V_AV1`; absent on `V_VP9`, whose mapping
    /// makes CodecPrivate optional (spec §11 CX-16 (5)).
    #[serde(default)]
    pub codec_private_hex: Option<String>,
    pub width: u32,
    pub height: u32,
    pub fps: [u32; 2],
    pub colour: ColourLayout,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ColourLayout {
    pub matrix: u8,
    pub range: u8,
    pub transfer: u8,
    pub primaries: u8,
    pub bits_per_channel: u8,
    pub mdcv_hex: Option<String>,
    pub clli_hex: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AudioLayout {
    pub codec_id: String,
    pub channels: u8,
    pub sample_rate: u32,
    pub pre_skip: u16,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ChapterLayout {
    pub start_ns: u64,
    pub end_ns: u64,
    pub name: String,
}

/// Lowercase or uppercase hex as bytes, naming `field` when it is not hex.
fn unhex(field: &str, text: &str) -> Result<Vec<u8>, String> {
    let bad = || format!("{field} \"{text}\" is not hex");
    if !text.len().is_multiple_of(2) {
        return Err(bad());
    }
    (0..text.len())
        .step_by(2)
        .map(|i| {
            text.get(i..i + 2)
                .and_then(|pair| u8::from_str_radix(pair, 16).ok())
                .ok_or_else(bad)
        })
        .collect()
}

/// The video TrackEntry, every value checked first.
fn video_entry(v: &VideoLayout) -> Result<Vec<u8>, String> {
    let private = match (v.codec_id.as_str(), &v.codec_private_hex) {
        ("V_AV1", Some(text)) => {
            let private = unhex("codec_private_hex", text)?;
            if private.is_empty() {
                return Err("the V_AV1 codec_private_hex is empty".to_string());
            }
            Some(private)
        }
        ("V_AV1", None) => return Err("the V_AV1 codec_private_hex is empty".to_string()),
        ("V_VP9", None) => None,
        ("V_VP9", Some(_)) => return Err("a V_VP9 track takes no codec_private_hex".to_string()),
        (other, _) => return Err(format!("video codec_id \"{other}\" is not V_AV1 or V_VP9")),
    };
    if v.width == 0 || v.height == 0 {
        return Err(format!(
            "the video size {} × {} has a side of 0",
            v.width, v.height
        ));
    }
    let [num, den] = v.fps;
    if num == 0 || den == 0 {
        return Err(format!("the video fps [{num}, {den}] is not a rate"));
    }
    let c = &v.colour;
    if c.bits_per_channel != 8 && c.bits_per_channel != 10 {
        return Err(format!(
            "colour bits_per_channel {} is not 8 or 10",
            c.bits_per_channel
        ));
    }
    let mastering = match &c.mdcv_hex {
        Some(text) => {
            let b = unhex("mdcv_hex", text)?;
            let m = mastering_from_mdcv(&b);
            Some(m.ok_or_else(|| format!("mdcv_hex is {} bytes, not 24", b.len()))?)
        }
        None => None,
    };
    let light = match &c.clli_hex {
        Some(text) => {
            let b = unhex("clli_hex", text)?;
            let l = light_from_clli(&b);
            Some(l.ok_or_else(|| format!("clli_hex is {} bytes, not 4", b.len()))?)
        }
        None => None,
    };
    let colour = ColourOut {
        matrix: c.matrix,
        range: c.range,
        transfer: c.transfer,
        primaries: c.primaries,
        bits: c.bits_per_channel,
        light,
        mastering,
    };
    // round(1e9 · den / num) ns, in integers.
    let frame_ns = (1_000_000_000 * u64::from(den) + u64::from(num) / 2) / u64::from(num);
    Ok(ebml::video_entry(
        &v.codec_id,
        private.as_deref(),
        v.width,
        v.height,
        frame_ns,
        &colour,
    ))
}

/// The audio TrackEntry, every value checked first.
fn audio_entry(a: &AudioLayout) -> Result<Vec<u8>, String> {
    if a.codec_id != "A_OPUS" {
        return Err(format!("audio codec_id \"{}\" is not A_OPUS", a.codec_id));
    }
    if a.sample_rate != 48_000 {
        return Err(format!("audio sample_rate {} is not 48000", a.sample_rate));
    }
    if !(1..=2).contains(&a.channels) {
        return Err(format!("audio channels {} is not 1 or 2", a.channels));
    }
    Ok(ebml::audio_entry(a.channels, a.pre_skip))
}

/// The Chapters element, or `None` for none, every chapter checked first.
fn chapters(list: &[ChapterLayout], duration_ns: u64) -> Result<Option<Vec<u8>>, String> {
    for (i, c) in list.iter().enumerate() {
        let n = i + 1;
        if c.end_ns <= c.start_ns {
            return Err(format!(
                "chapter {n} \"{}\" ends at {} ns, not after its start at {} ns",
                c.name, c.end_ns, c.start_ns
            ));
        }
        if c.start_ns >= duration_ns {
            return Err(format!(
                "chapter {n} \"{}\" starts at {} ns, not before the duration {duration_ns} ns",
                c.name, c.start_ns
            ));
        }
    }
    let rows: Vec<(u64, u64, &str)> = list
        .iter()
        .map(|c| (c.start_ns, c.end_ns, c.name.as_str()))
        .collect();
    Ok((!rows.is_empty()).then(|| ebml::chapters(&rows)))
}

/// What `open` writes before the first Cluster, every value checked, and
/// which tracks the layout declares.
pub(crate) struct Header {
    pub(crate) info: Vec<u8>,
    pub(crate) tracks: Vec<u8>,
    pub(crate) chapters: Option<Vec<u8>>,
    pub(crate) video: bool,
    pub(crate) audio: bool,
}

impl WebmLayout {
    /// Reads and checks the layout `text`, answering its header elements.
    pub(crate) fn header(text: &str) -> Result<Header, String> {
        let layout: WebmLayout =
            serde_json::from_str(text).map_err(|e| format!("the layout could not be read: {e}"))?;
        if layout.video.is_none() && layout.audio.is_none() {
            return Err("the layout has no video and no audio track".to_string());
        }
        let mut entries = Vec::new();
        if let Some(v) = &layout.video {
            entries.push(video_entry(v)?);
        }
        if let Some(a) = &layout.audio {
            entries.push(audio_entry(a)?);
        }
        Ok(Header {
            info: ebml::info(layout.duration_ns),
            tracks: ebml::master(ebml::TRACKS, &entries),
            chapters: chapters(&layout.chapters, layout.duration_ns)?,
            video: layout.video.is_some(),
            audio: layout.audio.is_some(),
        })
    }
}
