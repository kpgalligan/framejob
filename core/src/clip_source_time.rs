//! Source time to clip time, the one mapping (road map "creator-jobs" VR2a1,
//! spec §11 VR-20): `speech_in_clip`'s mapping of a forward-file SOURCE
//! tick lifted out whole, so ducking by speech (`audio_duck_speech.rs`) and
//! the framing planner (`reframe.rs`) read a media tick the same way.
//!
//! A media's analyses and speech spans are in ticks of the FORWARD file. A
//! clip's `in` is measured in the stream it plays — the reversed one when
//! `reversed` (`model.rs`'s `Source::Media` doc) — so a tick is reflected
//! over `media.duration` first, then `in` is subtracted, then the read is
//! turned into clip time through the clip's speed map when it is ramped,
//! else divided by its rate. `cursor_zoom_run.rs`'s `clip_time` is not this:
//! it reads past the clip's end on purpose (CU7/CU8).

use crate::model::{Clip, Media, Source};
use crate::source_window::source_read_by;
use crate::speed_map::SpeedMap;
use crate::time::Ticks;

/// Which way a constant-rate division rounds: an edge that starts floors,
/// one that ends ceils, so nothing is shaved off.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Round {
    Down,
    Up,
}

/// The reflected tick: the tick in the stream the clip plays.
fn reflected(media: &Media, reversed: bool, t: Ticks) -> Ticks {
    if reversed {
        media.duration.saturating_sub(t)
    } else {
        t
    }
}

/// The clip tick that plays forward-file source tick `t`: reflected over
/// `media.duration` when the clip is reversed, `in` subtracted (both
/// saturating), then [`SpeedMap::time_at`] when ramped, else divided by the
/// speed and floored (`Down`) or ceiled (`Up`). `None` when the source is
/// not media, or with no map and no positive finite speed. Not clamped to
/// the clip: a caller keeps what it needs.
pub fn clip_time_of_source(clip: &Clip, media: &Media, t: Ticks, round: Round) -> Option<Ticks> {
    let Source::Media { r#in, reversed, .. } = clip.source else {
        return None;
    };
    let map = SpeedMap::of(clip);
    let speed = clip.speed;
    if map.is_none() && !(speed.is_finite() && speed > 0.0) {
        return None;
    }
    let read = reflected(media, reversed, t).saturating_sub(r#in);
    Some(match &map {
        Some(map) => map.time_at(read as f64),
        None if round == Round::Up => (read as f64 / speed).ceil() as Ticks,
        None => (read as f64 / speed).floor() as Ticks,
    })
}

/// Whether forward-file source tick `t` is in the window the clip plays:
/// its reflected tick s′ has `in ≤ s′ < in + source_read_by(clip,
/// clip.duration)`. False for a source that is not media.
pub fn in_played_window(clip: &Clip, media: &Media, t: Ticks) -> bool {
    let Source::Media { r#in, reversed, .. } = clip.source else {
        return false;
    };
    let s = reflected(media, reversed, t);
    let end = r#in.saturating_add(source_read_by(clip, clip.duration));
    r#in <= s && s < end
}
