//! Linked pairs — Detach Audio's picture and sound, kept in step (spec §11
//! AU-90…AU-96).
//!
//! A link is a fact two clips state about each other: `Clip.linked` names
//! the partner, the partner names it back, and both sit in one container
//! (the timeline, or one nest). Everything here is a RULE the placement ops
//! ask, not an op of its own but [`Project::attach_audio`]:
//!
//! - **The closure** ([`Project::with_links`]): the clips an op was given,
//!   then each one's partner. `move_clip`, `split`, `duplicate`, `nest` and
//!   `ripple_delete` act on it; `delete` acts on [`Project::delete_closure`],
//!   which lets a SOUND half named alone go alone (AU-91), so Detach Audio
//!   then Delete stays the way to drop a clip's sound. A partner on a locked
//!   track is never added: locks win over links everywhere.
//! - **Settling** ([`Project::settle_links`]): `finish` clears every link
//!   whose partner is gone from the container or does not name it back, so
//!   an op that removes, nests or replaces half a pair writes no code for it
//!   and can never store a one-sided link; [`Project::check_links`] is the
//!   reader's refusal of one.
//! - **Splits and copies** ([`pair_split_halves`], [`relink_copies`]): a cut
//!   pairs the halves (AU-92), and a copy maps its links through the copy's
//!   old → new ids, clearing one whose partner was not copied (AU-96).
//! - **Edges** ([`Project::carried_edge`]): a trim or roll carries to the
//!   partner whose same edge coincides, unless the caller says `alone`
//!   (AU-93) — the J- and L-cut.
//! - **Rates** ([`Project::linked_rate_refusal`]): a linked clip's speed,
//!   direction and speed-naming actions are refused (AU-94), because the
//!   other half would have to be re-timed identically by a second
//!   implementation of every rate op.

use std::collections::HashMap;

use serde_json::Value;

use crate::edit_clip::clip_end;
use crate::model::{Clip, Curve, Project, Source};
use crate::outcome::Outcome;
use crate::speed_map::end_speed;
use crate::time::Ticks;

/// A linked SOUND half: linked, its picture off — the half Detach Audio
/// made, and the half whose edge a J- or L-cut drags alone.
fn is_linked_sound(clip: &Clip) -> bool {
    clip.linked.is_some() && !clip.enabled.video
}

/// The half of a linked pair that shows the picture: linked, its picture on,
/// its audio off. Read off the clip alone, since a pair inside a nest is out
/// of `Project::clip`'s reach (spec §11 AU-157).
pub(crate) fn is_linked_picture(clip: &Clip) -> bool {
    clip.linked.is_some() && clip.enabled.video && !clip.enabled.audio
}

/// AU-94's sentence: `clip`'s rate may not change while it is linked to
/// `partner`. Written once for `linked_rate_refusal` and `retime_range`
/// (spec §11 CU-90 (b)).
pub(crate) fn linked_rate_sentence(clip: u32, partner: u32) -> String {
    format!(
        "clip {clip} is linked to clip {partner}: Attach Audio before changing its speed or \
         direction"
    )
}

/// Every `(clip, named)` in one container whose link is one-sided: the
/// clip it names is absent, is itself, or does not name it back. Read off
/// the container as it stands, so a mutual pair is never on the list and
/// clearing what is cannot break one.
fn one_sided(clips: &[Clip]) -> Vec<(u32, u32)> {
    if clips.iter().all(|c| c.linked.is_none()) {
        return Vec::new();
    }
    let named: HashMap<u32, Option<u32>> = clips.iter().map(|c| (c.id, c.linked)).collect();
    clips
        .iter()
        .filter_map(|clip| {
            let partner = clip.linked?;
            let back = named.get(&partner).copied().flatten();
            (partner == clip.id || back != Some(clip.id)).then_some((clip.id, partner))
        })
        .collect()
}

fn clear_one_sided(clips: &mut [Clip]) {
    let broken = one_sided(clips);
    for clip in clips.iter_mut() {
        if broken.iter().any(|(id, _)| *id == clip.id) {
            clip.linked = None;
        }
    }
}

/// How long two clips share on the timeline; 0 when they do not meet.
fn shared(a: &Clip, b: &Clip) -> Ticks {
    let start = a.start.max(b.start);
    let end = clip_end(a).min(clip_end(b));
    end.saturating_sub(start).max(0)
}

fn reversed(clip: &Clip) -> bool {
    matches!(clip.source, Source::Media { reversed: true, .. })
}

/// The actions that name a rate, as the rate refusal compares them.
fn speed_actions(clip: &Clip) -> Vec<(Ticks, Ticks, Curve, f64)> {
    clip.actions
        .iter()
        .filter_map(|a| end_speed(a).map(|rate| (a.start, a.duration, a.curve, rate)))
        .collect()
}

/// Every action's span and curve, which Attach Audio holds the two halves
/// to.
fn spans(clip: &Clip) -> Vec<(Ticks, Ticks, Curve)> {
    clip.actions
        .iter()
        .map(|a| (a.start, a.duration, a.curve))
        .collect()
}

fn set_link(project: &mut Project, clip: u32, to: Option<u32>) {
    if let Some(slot) = project.clip_mut(clip) {
        slot.linked = to;
    }
}

/// Pairs the halves a split made (AU-92); `halves` is `(original, second
/// half)` for every clip cut. Both halves of a pair cut: the second halves
/// name each other and the originals keep their link. The partner not cut:
/// it names the half sharing the longer stretch of time with it, the first
/// on a tie, and [`Project::settle_links`] clears the other half's link,
/// which still names the partner.
pub(crate) fn pair_split_halves(project: &mut Project, halves: &[(u32, u32)]) {
    for &(first, second) in halves {
        let Some(partner) = project.clip(first).and_then(|c| c.linked) else {
            continue;
        };
        if let Some(&(_, partner_second)) = halves.iter().find(|(o, _)| *o == partner) {
            set_link(project, second, Some(partner_second));
            continue;
        }
        let Some(other) = project.clip(partner).cloned() else {
            continue;
        };
        let length = |id: u32| project.clip(id).map_or(0, |c| shared(c, &other));
        let keeper = if length(second) > length(first) {
            second
        } else {
            first
        };
        set_link(project, partner, Some(keeper));
        set_link(project, keeper, Some(partner));
    }
}

/// Maps the links of freshly copied clips through the copy's `fresh` ids
/// (old → new); a link whose partner was not copied is cleared (AU-96).
pub(crate) fn relink_copies(clips: &mut [Clip], fresh: &HashMap<u32, u32>) {
    for clip in clips.iter_mut() {
        clip.linked = clip.linked.and_then(|old| fresh.get(&old).copied());
    }
}

impl Project {
    fn unlocked(&self, track: u32) -> bool {
        self.track(track).is_some_and(|t| !t.locked)
    }

    /// The clip `clip` is linked to, when the link is mutual — and so in
    /// the same container, since `Project::clip` searches only this one.
    pub(crate) fn partner(&self, clip: u32) -> Option<&Clip> {
        let named = self.clip(clip)?.linked?;
        if named == clip {
            return None;
        }
        self.clip(named).filter(|c| c.linked == Some(clip))
    }

    /// The named clips in caller order, deduplicated, then each one's
    /// partner on an unlocked track. `Err` on an unknown id, as
    /// `selected_clips` answers.
    pub(crate) fn with_links(&self, clips: &[u32]) -> Result<Vec<u32>, String> {
        self.closure(clips, false)
    }

    /// [`Project::with_links`] for `delete`: a linked SOUND half named
    /// alone adds no partner, so deleting a detached sound keeps its picture
    /// (silent, its link settled away) while deleting a picture takes its
    /// sound (AU-91).
    pub(crate) fn delete_closure(&self, clips: &[u32]) -> Result<Vec<u32>, String> {
        self.closure(clips, true)
    }

    fn closure(&self, clips: &[u32], sound_alone: bool) -> Result<Vec<u32>, String> {
        let named: Vec<&Clip> = self.selected_clips(clips)?;
        let mut out: Vec<u32> = named.iter().map(|c| c.id).collect();
        for clip in named {
            if sound_alone && is_linked_sound(clip) {
                continue;
            }
            if let Some(partner) = self.partner(clip.id) {
                if self.unlocked(partner.track) && !out.contains(&partner.id) {
                    out.push(partner.id);
                }
            }
        }
        Ok(out)
    }

    /// Clears every link that is not mutual inside its own container — the
    /// timeline and each nest apart. `finish` runs it before its identity
    /// comparison, so no op stores a one-sided link and none has to clear
    /// the half it orphaned (AU-96).
    pub(crate) fn settle_links(&mut self) {
        clear_one_sided(&mut self.clips);
        for nest in self.nests.iter_mut() {
            clear_one_sided(&mut nest.clips);
        }
    }

    /// The reader's half of [`Project::settle_links`]: a stored one-sided
    /// link is an `Err`, naming the first clip that holds one.
    pub(crate) fn check_links(&self) -> Result<(), String> {
        let containers = std::iter::once(&self.clips).chain(self.nests.iter().map(|n| &n.clips));
        for clips in containers {
            if let Some((clip, named)) = one_sided(clips).first() {
                return Err(format!(
                    "clip {clip} is linked to clip {named}, which is not linked back"
                ));
            }
        }
        Ok(())
    }

    /// AU-94: a linked clip's speed, direction or speed-naming actions
    /// (start, duration, curve, `end.speed`) may not change. `None` when
    /// `before` is not linked or none of them differ in `after`.
    pub(crate) fn linked_rate_refusal(&self, before: &Clip, after: &Clip) -> Option<String> {
        let partner = before.linked?;
        let same = before.speed == after.speed
            && reversed(before) == reversed(after)
            && speed_actions(before) == speed_actions(after);
        (!same).then(|| linked_rate_sentence(before.id, partner))
    }

    /// An edge edit carried to the partner (AU-93): `edit` applied to
    /// `clip`, then — unless `alone` — the same edit to its partner on an
    /// unlocked track when `carries(clip, partner)` held BEFORE the edit,
    /// each through its own clamps. A refusal from either is the answer.
    pub(crate) fn carried_edge(
        &self,
        clip: u32,
        alone: bool,
        carries: impl Fn(&Clip, &Clip) -> bool,
        edit: impl Fn(&Project, u32) -> Result<Outcome, String>,
    ) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?;
        let partner = match alone {
            true => None,
            false => self
                .partner(clip)
                .filter(|p| self.unlocked(p.track) && carries(target, p))
                .map(|p| p.id),
        };
        let first = edit(self, clip)?;
        let Some(partner) = partner else {
            return Ok(first);
        };
        let (base, moved) = match first {
            Outcome::Refused(why) => return Ok(Outcome::Refused(why)),
            Outcome::Applied(next) => (next, true),
            Outcome::Identity => (self.clone(), false),
        };
        Ok(match edit(&base, partner)? {
            Outcome::Identity if moved => Outcome::Applied(base),
            other => other,
        })
    }

    /// Merges a linked picture and its detached sound back into one clip
    /// (spec §11 AU-95). Either half may be named.
    ///
    /// Refused, each in its own sentence: a clip with no partner; a pair
    /// that is not one half with its audio off and one with it on; and a
    /// pair whose start, duration, source, speed or actions' spans and
    /// curves differ — a J- or L-cut, which has no one clip to become.
    /// Otherwise the picture's audio is switched on and takes the sound's
    /// `audio` group, and each of its actions' `end.audio` the sound's
    /// action at the same index (removed where that one has none); its link
    /// is cleared and the sound clip removed. The sound's track stays, as it
    /// does after any delete.
    pub fn attach_audio(&self, clip: u32) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?;
        let Some(other) = self.partner(clip) else {
            return Ok(Outcome::Refused(format!(
                "clip {clip} is not linked to a detached sound"
            )));
        };
        let (picture, sound) = match (target.enabled.audio, other.enabled.audio) {
            (false, true) => (target, other),
            (true, false) => (other, target),
            _ => {
                return Ok(Outcome::Refused(format!(
                    "clips {clip} and {} are not a picture and its detached sound",
                    other.id
                )))
            }
        };
        let in_step = picture.start == sound.start
            && picture.duration == sound.duration
            && picture.source == sound.source
            && picture.speed == sound.speed
            && spans(picture) == spans(sound);
        if !in_step {
            return Ok(Outcome::Refused(format!(
                "clip {}'s picture and clip {}'s sound do not cover the same time; trim them \
                 to match before Attach Audio",
                picture.id, sound.id
            )));
        }

        let mut merged = picture.clone();
        merged.enabled.audio = true;
        merged.audio = sound.audio;
        merged.linked = None;
        for (action, theirs) in merged.actions.iter_mut().zip(&sound.actions) {
            let audio = theirs.end.get("audio").cloned();
            if let Value::Object(end) = &mut action.end {
                match audio {
                    Some(value) => {
                        end.insert("audio".to_string(), value);
                    }
                    None => {
                        end.shift_remove("audio");
                    }
                }
            }
        }
        let sound_id = sound.id;
        let mut next = self.clone();
        next.clips.retain(|c| c.id != sound_id);
        if let Some(slot) = next.clip_mut(merged.id) {
            *slot = merged;
        }
        self.finish(next)
    }
}
