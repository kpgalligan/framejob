//! `nest` and `unnest` — grouping (spec §6, table "Clips").
//!
//! The two halves of one idea: a selection of clips becomes ONE clip on the
//! timeline showing a [`Nest`], and a nest clip becomes the clips again.
//! Their own module because grouping is a different concern from placement
//! — no other op changes which CONTAINER a clip lives in — and because the
//! pair only makes sense read together.
//!
//! ### They are inverses, up to ids
//!
//! `nest` then `unnest` gives back the clips it took: same sources, same
//! relative times, same props, same actions, same stacking. The ids differ,
//! exactly as they do across `split` then a re-join, because `unnest` mints
//! fresh ones — it has to, since a second clip may still show the same nest
//! and the clips inside it cannot be in two places at once.
//!
//! Two asymmetries are deliberate, and both come from the schema:
//!
//! - **A trimmed nest clip gives everything back.** `Source::Nest` has no in
//!   point (spec §5.2), so `unnest` is the inverse of `nest`, not of the
//!   trim that followed it: content the nest clip's edges were hiding
//!   reappears rather than being destroyed. Nothing is lost, and the user
//!   can trim again.
//! - **A clip the overlap rule refuses on the way out goes on a new track in
//!   front**, the fallback `paste` and Add Text already use (spec §6): a
//!   round trip lands on the tracks it came from because the nest clip's own
//!   span is free once it is removed, and only a nest that has since been
//!   moved next to other material needs the fallback. Refusing the whole op
//!   would leave the user with a group they cannot open.
//!
//! ### What `nest` decides
//!
//! The nest clip lands on the FRONT-most track the selection occupied, which
//! is where the selection's front-most layer already was, and runs from the
//! earliest start to the latest end. The nest's own canvas is frozen at the
//! project's current size, so a later `set_canvas` cannot silently re-lay
//! out what is inside it ([`Nest`]). Its tracks are fresh — new ids, the
//! source tracks' names and their `hidden`/`muted`/`locked`/`solo` flags —
//! because the timeline's tracks stay on the timeline, holding whatever was
//! not selected.

use crate::edit_clip::{clip_end, set_gained_transitions};
use crate::model::{AudioProps, Clip, Enabled, Nest, Project, Source, Track, VideoProps};

/// A track with a fresh id, copying `from`'s name and its hidden / muted /
/// locked / solo state.
///
/// The state is copied and not cleared: a selection taken off a muted track
/// must go on sounding the way it did, and the mute now lives on the nest's
/// own track where the user can find it. Solo copies for the same reason —
/// what played before nesting plays after — even though a solo is judged
/// per container, so inside the nest it is now judged among the nest's own
/// tracks.
fn nested_track(project: &mut Project, from: &Track) -> Track {
    Track {
        id: project.allocate_id(),
        name: from.name.clone(),
        hidden: from.hidden,
        muted: from.muted,
        locked: from.locked,
        solo: from.solo,
    }
}

/// A track for a clip coming OUT of a nest, named by the count the way
/// `add_track` names one.
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

impl Project {
    /// Collapses `clips` into one nest clip (spec §6).
    ///
    /// The clips keep their relative times — the earliest starts at 0 inside
    /// the nest — their relative track order, their props and their actions;
    /// the nest clip covers exactly the span they covered, on the front-most
    /// track any of them was on.
    ///
    /// Refuses (`None`) on an empty selection, on a selection of one clip
    /// that is already a nest (grouping a group alone changes nothing a user
    /// can see), and when the nest clip would break the overlap rule against
    /// whatever was NOT selected. `Err` on an unknown clip id or a selection
    /// that would put the project past the track cap.
    pub fn nest_clips(&self, clips: &[u32], name: Option<&str>) -> Result<Option<Project>, String> {
        let selected: Vec<Clip> = self
            .selected_clips(clips)?
            .into_iter()
            .cloned()
            .collect::<Vec<_>>();
        if selected.is_empty() {
            return Ok(None);
        }
        if selected.len() == 1 && matches!(selected[0].source, Source::Nest { .. }) {
            return Ok(None);
        }

        let earliest = selected.iter().map(|c| c.start).min().unwrap_or(0);
        let latest = selected.iter().map(clip_end).max().unwrap_or(0);
        if latest <= earliest {
            return Ok(None);
        }

        // The source tracks, back-most first, so the nest's own stack keeps
        // the order the timeline had. `track_index` is the stack position;
        // a clip on a track that is not in `tracks` cannot exist (`validate`
        // refuses it) and is skipped rather than defended against twice.
        let mut sources: Vec<(usize, u32)> = Vec::new();
        for clip in &selected {
            if let Some(index) = self.track_index(clip.track) {
                if !sources.iter().any(|(_, id)| *id == clip.track) {
                    sources.push((index, clip.track));
                }
            }
        }
        sources.sort_unstable();
        // The front-most source track is where the nest clip goes. The
        // nest's own tracks count toward `MAX_TRACKS` like any other
        // (`format::check_caps`), so a selection that would overrun the cap
        // is caught by `finish` rather than counted twice here.
        let Some((_, front_track)) = sources.last().copied() else {
            return Ok(None);
        };

        let mut next = self.clone();
        let nest_id = next.allocate_id();
        let mut tracks: Vec<Track> = Vec::with_capacity(sources.len());
        let mut mapping: Vec<(u32, u32)> = Vec::with_capacity(sources.len());
        for (_, id) in &sources {
            let Some(source) = self.track(*id) else {
                continue;
            };
            let track = nested_track(&mut next, source);
            mapping.push((*id, track.id));
            tracks.push(track);
        }

        // The clips move WHOLE — ids, actions, transitions and all — so
        // nothing about them has to be re-minted or re-checked. Only their
        // container changes.
        let mut inside: Vec<Clip> = Vec::with_capacity(selected.len());
        for clip in &selected {
            let Some((_, track)) = mapping.iter().find(|(from, _)| *from == clip.track) else {
                continue;
            };
            let mut moved = clip.clone();
            moved.track = *track;
            moved.start = clip.start.saturating_sub(earliest);
            inside.push(moved);
        }
        // Any sound inside means the nest clip needs a volume of its own to
        // scale it by; a nest of text and shapes gets no audio group, so the
        // inspector shows no Audio tab for something that cannot make a
        // sound.
        let audible = inside.iter().any(|c| c.audio.is_some());

        next.clips
            .retain(|c| !selected.iter().any(|s| s.id == c.id));
        next.nests.push(Nest {
            id: nest_id,
            name: match name.map(str::trim).filter(|n| !n.is_empty()) {
                Some(given) => given.to_string(),
                None => format!("Nest {}", next.nests.len().saturating_add(1)),
            },
            width: next.canvas.width,
            height: next.canvas.height,
            tracks,
            clips: inside,
        });

        let clip_id = next.allocate_id();
        next.clips.push(Clip {
            id: clip_id,
            track: front_track,
            start: earliest,
            duration: latest.saturating_sub(earliest),
            source: Source::Nest { project: nest_id },
            enabled: Enabled::default(),
            speed: 1.0,
            video: Some(VideoProps::default()),
            audio: audible.then(AudioProps::default),
            text: None,
            shape: None,
            actions: Vec::new(),
            // A transition INTO the selection belonged to a clip that is now
            // inside the group, so the nest clip gets the default cross
            // dissolve over whatever overlap it inherits — the same rule
            // every other op uses for a clip that gains one.
            transition_in: None,
            name: None,
            label: None,
        });

        if next.check_overlap_rule(&[], front_track, &[]).is_err() {
            return Ok(None);
        }
        set_gained_transitions(&mut next, &[front_track]);
        self.finish(next)
    }

    /// Puts a nest clip's contents back on the timeline and removes the clip
    /// (spec §6) — the inverse of [`Project::nest_clips`].
    ///
    /// Each clip returns at `clip.start + its own start`, with fresh ids, on
    /// the track counted back from the nest clip's own: the nest's
    /// front-most track lands where the nest clip was, the one behind it a
    /// track further back, and tracks missing behind are added. A clip the
    /// overlap rule refuses goes on a new track in front.
    ///
    /// The nest itself is dropped when nothing else shows it; a second clip
    /// showing it keeps it, which is why the returned clips are copies.
    /// `Err` when `clip` is not a nest clip.
    pub fn unnest_clip(&self, clip: u32) -> Result<Option<Project>, String> {
        let target = self.require_clip(clip)?.clone();
        let Source::Nest { project } = target.source else {
            return Err(format!("clip {clip} is not a nest clip"));
        };
        // `validate` refuses a clip pointing at a nest that is not there, so
        // this is a corrupt project rather than a caller's mistake — an
        // error either way, naming both ids.
        let nest = self
            .nest(project)
            .ok_or_else(|| format!("clip {clip} shows unknown nest {project}"))?
            .clone();

        let base = self.require_track_index(target.track)? as i64;
        let depth = |track: u32| -> i64 {
            // 0 for the nest's FRONT-most track, counting backwards.
            match nest.tracks.iter().position(|t| t.id == track) {
                Some(index) => (nest.tracks.len() as i64 - 1) - index as i64,
                None => 0,
            }
        };
        // Bounded by the track cap the project was read under, so the
        // deficit loop below can ask for at most `MAX_TRACKS` tracks and
        // `finish` refuses the result if that is too many.
        let deepest = nest.tracks.len().saturating_sub(1) as i64;

        let mut next = self.clone();
        next.clips.retain(|c| c.id != clip);

        // Tracks missing behind the destination, exactly as `paste` adds
        // them: inserting at index 0 shifts every existing track up, so the
        // destination index moves with them.
        let deficit = (deepest - base).max(0);
        for _ in 0..deficit {
            let track = new_track(&mut next);
            next.tracks.insert(0, track);
        }
        let base = base + deficit;

        // Back-most first, then time: the order clips are placed in is the
        // order the overlap rule sees them, so it has to be deterministic or
        // one nest could open two ways.
        let mut ordered: Vec<&Clip> = nest.clips.iter().collect();
        ordered.sort_by_key(|c| (std::cmp::Reverse(depth(c.track)), c.start, c.id));

        let mut fallbacks: Vec<u32> = Vec::new();
        let mut touched: Vec<u32> = Vec::new();
        for source in ordered {
            let mut moved = source.clone();
            moved.id = next.allocate_id();
            for action in moved.actions.iter_mut() {
                action.id = next.allocate_id();
            }
            // Already on this document's frame grid — the nest was made from
            // clips that were — and snapped anyway, because a hand-written
            // nest need not have been.
            moved.start = next
                .snapped(target.start.saturating_add(source.start))
                .max(0);
            moved.duration = next.snapped(source.duration).max(next.frame());

            let wanted = next
                .tracks
                .get((base - depth(source.track)).max(0) as usize)
                .map(|t| t.id);
            let mut chosen: Option<u32> = None;
            for candidate in wanted.into_iter().chain(fallbacks.iter().copied()) {
                moved.track = candidate;
                if next
                    .check_overlap_rule(std::slice::from_ref(&moved), candidate, &[])
                    .is_ok()
                {
                    chosen = Some(candidate);
                    break;
                }
            }
            // A brand-new track holds nothing, so the last arm always
            // succeeds and the loop always terminates.
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
            moved.track = landed;
            if !touched.contains(&landed) {
                touched.push(landed);
            }
            next.clips.push(moved);
        }

        if !next.nest_is_shown(project) {
            next.nests.retain(|n| n.id != project);
        }
        set_gained_transitions(&mut next, &touched);
        self.finish(next)
    }
}
