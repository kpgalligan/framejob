//! `paste` — the clipboard's half of Cut / Copy / Paste (spec §6, table
//! "Clips").
//!
//! Its own module because pasting is a different concern from every other
//! placement op: the material does not come from the project. A `move_clip`
//! or a `duplicate` rearranges clips the project already owns, so the ids,
//! the media and the tracks all exist; a paste arrives as JSON that may have
//! been written by ANOTHER document — a different id space, a different
//! media list, a different frame grid, possibly a different canvas — and has
//! to be made to fit before a single clip lands.
//!
//! ### The payload
//!
//! ```json
//! {"clips": [ …the §5.2 clip objects… ], "media": [ …the §5.2 media rows… ],
//!  "nests": [ …the §5.2 nest objects the clips show… ]}
//! ```
//!
//! It is exactly what `EditorViewController+Clipboard.swift` puts on
//! `NSPasteboard.general` under `com.kgalligan.reelcut.clips`: the clips
//! copied verbatim out of the source document's own `project.json`, plus the
//! media rows those clips name and any nest they show. Four things about it
//! are worth stating before the code:
//!
//! 1. **A payload clip's `track` is a DEPTH, not an id** — 0 is the
//!    front-most track the copy covered, 1 the one behind it, and so on. A
//!    track id from another document means nothing here, and the depth is
//!    the only thing about the source's track stack worth carrying: it is
//!    what makes a two-lane selection paste back onto two lanes.
//! 2. **Ids are re-minted, always.** Clips, actions, any media row the
//!    project does not already have, and every nest — with its tracks, its
//!    clips and their actions — get fresh ids from `next_id`, so a payload
//!    can be pasted repeatedly and into the document it came from.
//! 3. **A nest is COPIED, never matched.** Media is matched by path because
//!    it names a file two documents can share; a nest is content, and two
//!    nests that look alike are no more the same object than two clips are.
//!    So every paste of a nest clip brings its own copy, and editing one
//!    afterwards leaves the other alone.
//! 4. **Unknown keys are ignored**, deliberately: no `deny_unknown_fields`
//!    here. The payload is machine-written, a future build will add keys to
//!    it, and refusing a whole paste over a key this build has not learned
//!    yet would be worse than dropping it — the same reasoning `model.rs`
//!    gives for the project schema itself.
//!
//! ### Making it fit
//!
//! Every project time is re-snapped to THIS document's frame grid
//! ([`Project::snapped`]), because the payload may come from a document at
//! another rate; source times are not, for the same reason `trim_start` and
//! `split` do not snap them — an `in` point is measured on the media's grid,
//! not the canvas's. Media is matched to the existing `media[]` **by path**,
//! which is `add_media`'s one-entry-per-path rule, so pasting between two
//! documents that both reference `/m/talk.mov` reuses the row that is there
//! and pasting into a document that has never seen it brings the row along.
//!
//! Placement obeys the overlap rule like everything else (spec §11), and a
//! clip the rule refuses on its target track goes on a NEW track in front —
//! the same fallback `EditorViewController+AddClips.swift` uses for Add
//! Text, and for the same reason: a paste at a busy playhead should land
//! somewhere visible rather than beep. That fallback is why the only
//! "changes nothing" answer here is an empty clip list.
//!
//! ### Paste Attributes
//!
//! `paste_attributes` reads the same payload and places nothing: it copies
//! the EARLIEST payload clip's property groups onto clips already on the
//! timeline. It lives here rather than in `edit_props.rs` because the
//! material again comes from the clipboard, whose shape is this module's to
//! know. A group is REPLACED whole, never merged — "make this look like
//! that" is the gesture, and a merge would leave the target's shadow under
//! a source that had none. What a target keeps is what makes it the clip it
//! is rather than how it looks: a text clip's `content`; a shape's `kind`,
//! `width`, `height`, `from` and `to`. Video and audio travel whole,
//! transform included — `audio.muted` and `keep_pitch` are properties like
//! opacity, and `keep_pitch` only acts when the speed is not 1, which does
//! not travel: `speed`, `enabled`, the actions, the transition, the name,
//! the label and the source are not properties at all.

use std::collections::HashMap;

use serde::Deserialize;
use serde_json::Value;

use crate::edit_clip::set_gained_transitions;
use crate::export::describe;
use crate::format::MAX_TRACKS;
use crate::model::{Clip, Media, Nest, Project, ShapeProps, Source, TextProps, Track};
use crate::outcome::Outcome;
use crate::patch::Group;
use crate::time::Ticks;

/// One clipboard payload. `media` and `nests` default because most
/// selections name neither; `clips` deliberately does not, so a payload that
/// forgot the key is an error naming it rather than a silent no-op.
#[derive(Debug, Deserialize)]
struct Payload {
    clips: Vec<Clip>,
    #[serde(default)]
    media: Vec<Media>,
    #[serde(default)]
    nests: Vec<Nest>,
}

/// The media a source shows, or `None` for the kinds with no file behind
/// them (spec §5.2).
fn source_media(source: &Source) -> Option<u32> {
    match source {
        Source::Media { media, .. } | Source::Still { media, .. } | Source::Image { media } => {
            Some(*media)
        }
        Source::Text | Source::Shape | Source::Nest { .. } => None,
    }
}

/// The nest a source shows, or `None` for every other kind.
fn source_nest(source: &Source) -> Option<u32> {
    match source {
        Source::Nest { project } => Some(*project),
        _ => None,
    }
}

/// The same source pointing at this project's media and nest ids.
///
/// An id neither map carries is impossible — [`absorb_media`] and
/// [`absorb_nests`] resolve every one the clips name before this runs — but
/// ids are passed through rather than unwrapped, so a future caller that
/// skipped a step gets `validate`'s "refers to unknown media" or "refers to
/// unknown nest" instead of a panic.
fn remap_source(source: &Source, media: &HashMap<u32, u32>, nests: &HashMap<u32, u32>) -> Source {
    let mapped = |id: &u32| media.get(id).copied().unwrap_or(*id);
    match source {
        Source::Media {
            media: id,
            r#in,
            reversed,
        } => Source::Media {
            media: mapped(id),
            r#in: (*r#in).max(0),
            reversed: *reversed,
        },
        Source::Still { media: id, at } => Source::Still {
            media: mapped(id),
            at: (*at).max(0),
        },
        Source::Image { media: id } => Source::Image { media: mapped(id) },
        Source::Nest { project } => Source::Nest {
            project: nests.get(project).copied().unwrap_or(*project),
        },
        other => other.clone(),
    }
}

/// The payload nests the pasted clips show, directly or through one
/// another, in the order they are discovered.
///
/// The traversal is the same shape `validate`'s cycle check uses: an id is
/// queued once, so a payload whose nests point at each other terminates here
/// and is refused later by `validate`, where the message about a cycle
/// already lives.
///
/// `Err` when a clip shows a nest the payload does not carry — a truncated
/// or hand-written payload, whose clip would otherwise become a dangling
/// reference.
fn reachable_nests(payload: &Payload) -> Result<Vec<&Nest>, String> {
    let mut wanted: Vec<u32> = Vec::new();
    for clip in &payload.clips {
        if let Some(id) = source_nest(&clip.source) {
            if !wanted.contains(&id) {
                wanted.push(id);
            }
        }
    }
    let mut found: Vec<&Nest> = Vec::new();
    let mut index = 0;
    while let Some(id) = wanted.get(index).copied() {
        index += 1;
        let Some(nest) = payload.nests.iter().find(|n| n.id == id) else {
            return Err(format!(
                "a pasted clip shows nest {id}, which the payload does not carry"
            ));
        };
        found.push(nest);
        for child in nest.child_nests() {
            if !wanted.contains(&child) {
                wanted.push(child);
            }
        }
    }
    Ok(found)
}

/// Copies every reachable payload nest into the project with fresh ids
/// throughout — the nest, its tracks, its clips and their actions — and
/// returns the payload-id → project-id map.
///
/// Every nest gets its new id BEFORE any is rewritten, so a nest showing
/// another nest is remapped whichever order the two were discovered in.
/// Times inside are re-snapped to this document's frame grid for the same
/// reason the pasted clips' are: the payload may come from a document at
/// another rate, and nothing sub-frame may reach the model.
fn absorb_nests(
    project: &mut Project,
    nests: &[&Nest],
    media: &HashMap<u32, u32>,
) -> HashMap<u32, u32> {
    let mut map: HashMap<u32, u32> = HashMap::new();
    for nest in nests {
        map.insert(nest.id, project.allocate_id());
    }
    for nest in nests {
        let mut copy = (*nest).clone();
        copy.id = map.get(&nest.id).copied().unwrap_or(nest.id);
        let mut tracks: HashMap<u32, u32> = HashMap::new();
        for track in copy.tracks.iter_mut() {
            let id = project.allocate_id();
            tracks.insert(track.id, id);
            track.id = id;
        }
        for clip in copy.clips.iter_mut() {
            clip.id = project.allocate_id();
            for action in clip.actions.iter_mut() {
                action.id = project.allocate_id();
            }
            clip.track = tracks.get(&clip.track).copied().unwrap_or(clip.track);
            clip.source = remap_source(&clip.source, media, &map);
            clip.start = project.snapped(clip.start).max(0);
            // The speed BEFORE the duration: the bound is measured at it.
            if !(clip.speed.is_finite() && clip.speed > 0.0) {
                clip.speed = 1.0;
            }
            clip.duration = project.duration_resnapped(clip);
            resnap_actions(project, clip);
        }
        project.nests.push(copy);
    }
    map
}

/// Resolves every media the pasted clips name onto an entry of this
/// project's `media[]`, appending the ones that are not there, and returns
/// the payload-id → project-id map.
///
/// `clips` is every clip the paste will land — the payload's own AND those
/// inside the nests they show, which reference the payload's `media[]` in
/// the same one id space (spec §5.2) and would otherwise dangle.
///
/// Only media a pasted clip actually SHOWS is brought across. The pasteboard
/// writer only ever puts those there, and a payload row nothing references
/// would arrive as a Media-tab entry the user did not ask for and cannot
/// account for.
///
/// `Err` when a clip names a media the payload does not carry (a truncated
/// or hand-written payload — the clip would otherwise become a dangling
/// reference `validate` refuses) or when a row's path is empty.
fn absorb_media(
    project: &mut Project,
    payload: &Payload,
    clips: &[&Clip],
) -> Result<HashMap<u32, u32>, String> {
    // A `Vec` rather than a set so the ids are resolved — and therefore the
    // new rows are appended and numbered — in the order the clips name them,
    // which makes a paste reproducible.
    let mut wanted: Vec<u32> = Vec::new();
    for clip in clips {
        if let Some(id) = source_media(&clip.source) {
            if !wanted.contains(&id) {
                wanted.push(id);
            }
        }
    }

    let mut map: HashMap<u32, u32> = HashMap::new();
    for id in wanted {
        let Some(entry) = payload.media.iter().find(|m| m.id == id) else {
            return Err(format!(
                "a pasted clip shows media {id}, which the payload does not carry"
            ));
        };
        let path = entry.path.trim().to_string();
        if path.is_empty() {
            return Err("a pasted media path must not be empty".to_string());
        }
        let local = match project.media.iter().find(|m| m.path == path) {
            Some(found) => found.id,
            None => {
                let mut record = entry.clone();
                record.id = project.allocate_id();
                record.path = path;
                // An empty bookmark is not a bookmark — `add_media`'s rule.
                record.bookmark = record.bookmark.filter(|b| !b.trim().is_empty());
                let new_id = record.id;
                project.media.push(record);
                new_id
            }
        };
        map.insert(id, local);
    }
    Ok(map)
}

/// A track with a fresh id, named by the COUNT the way `add_track` names
/// one, so inserting behind the stack does not renumber the tracks above it.
fn new_track(project: &mut Project) -> Track {
    let id = project.allocate_id();
    let name = format!("Track {}", project.tracks.len().saturating_add(1));
    Track {
        id,
        name,
        hidden: false,
        muted: false,
        locked: false,
        solo: false,
    }
}

/// Re-snaps a pasted clip's actions onto this project's frame grid and
/// clamps them inside its (already re-snapped) duration.
///
/// The same two clamps `set_canvas`'s `resnap` applies when the document's
/// rate changes, and for the same reason: yesterday's grid is not today's, a
/// duration that rounds to zero is what `validate` rejects, and an action
/// must still fit the clip it is on.
fn resnap_actions(project: &Project, clip: &mut Clip) {
    let frame = project.frame();
    let last_start = clip.duration.saturating_sub(frame).max(0);
    for action in clip.actions.iter_mut() {
        action.start = project.snapped(action.start).clamp(0, last_start);
        action.duration = project
            .snapped(action.duration)
            .max(frame)
            .min(clip.duration.saturating_sub(action.start))
            .max(1);
    }
}

/// The four groups in the order a default `paste_attributes` visits them —
/// their order on `Clip`, so a range error names the schema's first group.
const GROUPS: [Group; 4] = [Group::Video, Group::Audio, Group::Text, Group::Shape];

/// Whether a clip HAS the group — the model's only notion of what a clip
/// can take, the same one `edit_props.rs`'s patches go by.
fn has_group(clip: &Clip, group: Group) -> bool {
    match group {
        Group::Video => clip.video.is_some(),
        Group::Audio => clip.audio.is_some(),
        Group::Text => clip.text.is_some(),
        Group::Shape => clip.shape.is_some(),
    }
}

/// Replaces `target`'s group with a copy of `source`'s, keeping the fields
/// that make the target the clip it is (module doc). A side that lacks the
/// group leaves the target as it was — the caller has already refused that
/// case by name, so this is only the shape that cannot invent a group.
fn copy_group(target: &mut Clip, source: &Clip, group: Group) {
    match group {
        Group::Video => {
            if let (Some(into), Some(from)) = (target.video.as_mut(), &source.video) {
                *into = from.clone();
            }
        }
        Group::Audio => {
            if let (Some(into), Some(from)) = (target.audio.as_mut(), &source.audio) {
                *into = *from;
            }
        }
        Group::Text => {
            if let (Some(into), Some(from)) = (target.text.as_mut(), &source.text) {
                let content = std::mem::take(&mut into.content);
                *into = TextProps {
                    content,
                    ..from.clone()
                };
            }
        }
        Group::Shape => {
            if let (Some(into), Some(from)) = (target.shape.as_mut(), &source.shape) {
                *into = ShapeProps {
                    kind: into.kind,
                    width: into.width,
                    height: into.height,
                    from: into.from,
                    to: into.to,
                    ..from.clone()
                };
            }
        }
    }
}

/// Parses the payload, naming what was wrong.
fn parse_payload(payload: &Value) -> Result<Payload, String> {
    if !payload.is_object() {
        return Err(format!(
            "a paste payload must be a json object, not {}",
            describe(payload)
        ));
    }
    serde_json::from_value(payload.clone())
        .map_err(|e| format!("paste payload does not match the schema: {e}"))
}

impl Project {
    /// Inserts a clipboard payload's clips with fresh ids, the earliest one
    /// landing exactly at `at` and the rest keeping their offsets from it
    /// (spec §6).
    ///
    /// `track` names where the payload's front-most depth lands and retargets
    /// the rest by the same index delta, the way `move_clip` does; absent, it
    /// is the front-most track, so a paste keeps the copy's own layering.
    /// Tracks missing BEHIND the destination are added; a clip the overlap
    /// rule refuses on its target track goes on a new track in front.
    ///
    /// An identity for an empty clip list — the only answer that changes
    /// nothing, since the fallback track means a placement cannot fail.
    /// `Err` for a malformed payload, an unknown `track`, a clip naming a
    /// media the payload does not carry, or a depth past the track cap.
    pub fn paste(&self, at: Ticks, track: Option<u32>, payload: &Value) -> Result<Outcome, String> {
        let payload = parse_payload(payload)?;
        // An explicit destination is an id from THIS project, so an unknown
        // one is a caller bug and an error — unlike anything in the payload.
        // `tracks.len() - 1` is the front (index 0 is the back, spec §6); a
        // project with no tracks at all leaves it at -1, and the deficit
        // below adds the one every clip then needs.
        let base = match track {
            Some(id) => self.require_track_index(id)? as i64,
            None => self.tracks.len() as i64 - 1,
        };
        if payload.clips.is_empty() {
            return Ok(Outcome::Identity);
        }
        let deepest = payload.clips.iter().map(|c| c.track).max().unwrap_or(0) as i64;
        // Bounded BEFORE anything is allocated: `track` is a depth here, and
        // a payload claiming depth 4 000 000 000 would otherwise ask for four
        // billion tracks before `check_caps` ever saw the result.
        if deepest >= MAX_TRACKS as i64 {
            return Err(format!(
                "a pasted clip is {deepest} tracks deep, past the {MAX_TRACKS}-track limit"
            ));
        }
        let at = self.snapped(at).max(0);

        let mut next = self.clone();
        // The nests first, because their clips name media too: everything
        // that will land is resolved against `media[]` in one pass, and the
        // nests are then copied in with those ids already mapped.
        let nests = reachable_nests(&payload)?;
        let landing: Vec<&Clip> = payload
            .clips
            .iter()
            .chain(nests.iter().flat_map(|n| n.clips.iter()))
            .collect();
        let media = absorb_media(&mut next, &payload, &landing)?;
        let nests = absorb_nests(&mut next, &nests, &media);

        // Tracks missing behind the destination. Inserting at index 0 shifts
        // every existing track up, so the destination index moves with them.
        let deficit = (deepest - base).max(0);
        for _ in 0..deficit {
            let track = new_track(&mut next);
            next.tracks.insert(0, track);
        }
        let base = base + deficit;

        // The earliest clip lands ON `at`, so every other one keeps its own
        // distance from it. Offsets are non-negative by construction, which
        // is what keeps a paste at 0 from folding clips onto each other.
        let earliest = payload.clips.iter().map(|c| c.start).min().unwrap_or(0);

        // Back-most depth first, then time: the order clips are placed in is
        // the order the overlap rule sees them, so it has to be deterministic
        // or the same payload could land two ways.
        let mut ordered: Vec<&Clip> = payload.clips.iter().collect();
        ordered.sort_by_key(|c| (std::cmp::Reverse(c.track), c.start, c.id));

        let mut fallbacks: Vec<u32> = Vec::new();
        let mut touched: Vec<u32> = Vec::new();
        for source in ordered {
            let mut clip = source.clone();
            clip.id = next.allocate_id();
            for action in clip.actions.iter_mut() {
                action.id = next.allocate_id();
            }
            clip.source = remap_source(&source.source, &media, &nests);
            // The payload is trusted about WHAT a clip is and checked about
            // what it would do to the project, so a nonsense rate — which
            // only a hand-written payload can carry — falls back to 1:1
            // rather than reaching the bound below and the composition.
            if !(clip.speed.is_finite() && clip.speed > 0.0) {
                clip.speed = 1.0;
            }
            clip.start = self
                .snapped(at.saturating_add(source.start.saturating_sub(earliest)))
                .max(0);
            // `next` and not `self`: the media this clip names was absorbed
            // into it above, and only a project that HOLDS the media can
            // measure how much window is left (spec §11, D4-4).
            clip.duration = next.duration_resnapped(&clip);
            resnap_actions(self, &mut clip);

            // The target track, then the fallbacks already added, then a new
            // one. A brand-new track holds nothing, so the last arm always
            // succeeds and the loop always terminates.
            let target = next
                .tracks
                .get((base - source.track as i64).max(0) as usize)
                .map(|t| t.id);
            let mut chosen: Option<u32> = None;
            for candidate in target.into_iter().chain(fallbacks.iter().copied()) {
                clip.track = candidate;
                if next
                    .check_overlap_rule(std::slice::from_ref(&clip), candidate, &[])
                    .is_ok()
                {
                    chosen = Some(candidate);
                    break;
                }
            }
            let landed = match chosen {
                Some(id) => id,
                None => {
                    let track = new_track(&mut next);
                    let id = track.id;
                    next.tracks.push(track);
                    fallbacks.push(id);
                    id
                }
            };
            clip.track = landed;
            if !touched.contains(&landed) {
                touched.push(landed);
            }
            next.clips.push(clip);
        }

        set_gained_transitions(&mut next, &touched);
        self.finish(next)
    }

    /// Copies one payload clip's property groups onto every named clip (spec
    /// §6) — Edit ▸ Paste Attributes. The clip is the EARLIEST, then the
    /// front-most (`track` is a depth, 0 = front), then the lower id: Copy
    /// writes a selection in storage — creation — order, not the timeline's,
    /// so the array's first is a clip the user cannot see. Which fields
    /// travel, which a target keeps and why a group is replaced rather than
    /// merged are the module doc's.
    ///
    /// `groups` absent means every group BOTH sides have, silently skipping
    /// the rest: video onto a text clip from a media clip copies the video,
    /// leaves the text alone and drops the audio, which has nowhere to go. A
    /// NAMED group is different — one the source lacks is an `Err` naming
    /// the group, one a target lacks is `Err("clip N has no audio
    /// properties")`, the patches' answer — because a caller who asked for
    /// it would otherwise never learn it did not happen. An empty explicit
    /// list, an identity paste and an empty selection are all identities. The
    /// copied groups then pass the range checks a patch does, so a payload
    /// written by hand cannot smuggle in a value the inspector would refuse.
    pub fn paste_attributes(
        &self,
        clips: &[u32],
        payload: &Value,
        groups: Option<&[Group]>,
    ) -> Result<Outcome, String> {
        let payload = parse_payload(payload)?;
        let earliest = |c: &&Clip| (c.start, c.track, c.id);
        let Some(source) = payload.clips.iter().min_by_key(earliest) else {
            return Err("paste payload has no clips".to_string());
        };
        for group in groups.unwrap_or_default() {
            if !has_group(source, *group) {
                return Err(format!("payload clip has no {} properties", group.name()));
            }
        }
        let ids: Vec<u32> = self.selected_clips(clips)?.iter().map(|c| c.id).collect();

        let mut next = self.clone();
        for id in ids {
            let Some(target) = next.clip_mut(id) else {
                continue;
            };
            let chosen: Vec<Group> = match groups {
                Some(named) => named.to_vec(),
                None => GROUPS
                    .into_iter()
                    .filter(|g| has_group(source, *g) && has_group(target, *g))
                    .collect(),
            };
            for group in chosen {
                if !has_group(target, group) {
                    return Err(format!("clip {id} has no {} properties", group.name()));
                }
                copy_group(target, source, group);
                self.check_group(target, group)?;
            }
        }
        self.finish(next)
    }
}
