//! The stems an audio export writes beside its mix (spec §11 AU-108): which
//! timeline tracks each file holds and what it is called. Swift writes them
//! (`ExportStems.swift`); this answers only the grouping and the names, so
//! the sheet, the `export` tool and the tests read one list.
//!
//! The rules:
//!
//! - **Heard.** A timeline track is heard when the plan has an audio track
//!   labelled with it (`CompTrack::track`, AU-107 — so a track holding only
//!   pictures, or nothing, is not) and it is not `silenced` among the
//!   timeline's tracks (mute, solo). None heard is refused.
//! - **Grouping.** `tracks`: one stem per heard track. `names`: heard tracks
//!   whose trimmed names match case-insensitively are one stem, named by the
//!   first's spelling; an unnamed track is its own.
//! - **Order.** Timeline order of each stem's first track; a stem's tracks
//!   in timeline order.
//! - **Names.** The trimmed track name, else `Track N` (N = its index + 1,
//!   the header's label), with `/` and `:` replaced by `-`; a name equal
//!   case-insensitively to an earlier stem's gets ` (Track N)` of its first
//!   track, and one still equal to an earlier stem's then gets
//!   ` (Track N, 2)`, ` (Track N, 3)` and on, the first no earlier stem
//!   holds, so no two stems share a file.

use std::collections::BTreeSet;

use serde_json::{Map, Value};

use crate::audio::silenced;
use crate::export_overrides::StemsMode;
use crate::model::Project;

/// One stem: the file's name (without the mix's) and the timeline tracks
/// whose sound it holds.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Stem {
    pub(crate) name: String,
    pub(crate) tracks: Vec<u32>,
}

impl Stem {
    /// `{"name": …, "tracks": [ids]}`, the settings' `stems` entry.
    pub(crate) fn to_json(&self) -> Value {
        let mut out = Map::new();
        out.insert("name".to_string(), Value::from(self.name.clone()));
        let tracks = self.tracks.iter().map(|id| Value::from(*id)).collect();
        out.insert("tracks".to_string(), Value::Array(tracks));
        Value::Object(out)
    }
}

/// A group while it is being gathered: its first track's index and the
/// spelling it is named by.
struct Group {
    first: usize,
    spelling: String,
    tracks: Vec<u32>,
}

impl Project {
    /// The stems `mode` asks for, in order (spec §11 AU-108 (b), (c)), or
    /// the refusal when no track is heard.
    pub(crate) fn export_stems(&self, mode: StemsMode) -> Result<Vec<Stem>, String> {
        let labelled: BTreeSet<u32> = self.assign().audio.iter().map(|t| t.track).collect();
        let mut groups: Vec<Group> = Vec::new();
        for (index, track) in self.tracks.iter().enumerate() {
            if !labelled.contains(&track.id) || silenced(&self.tracks, track) {
                continue;
            }
            let trimmed = track.name.trim();
            let joins = match mode {
                StemsMode::Tracks => None,
                StemsMode::Names if trimmed.is_empty() => None,
                StemsMode::Names => groups
                    .iter_mut()
                    .find(|g| !g.spelling.is_empty() && same(&g.spelling, trimmed)),
            };
            match joins {
                Some(group) => group.tracks.push(track.id),
                None => groups.push(Group {
                    first: index,
                    spelling: trimmed.to_string(),
                    tracks: vec![track.id],
                }),
            }
        }
        if groups.is_empty() {
            return Err("stems: no track is heard, so there is no stem to write".to_string());
        }
        let mut stems: Vec<Stem> = Vec::with_capacity(groups.len());
        for group in groups {
            let label = format!("Track {}", group.first.saturating_add(1));
            let base = if group.spelling.is_empty() {
                label.clone()
            } else {
                group.spelling.replace(['/', ':'], "-")
            };
            let taken = |name: &str| stems.iter().any(|s| same(&s.name, name));
            let mut name = base.clone();
            if taken(&name) {
                name = format!("{base} ({label})");
            }
            let mut count: u32 = 2;
            while taken(&name) {
                name = format!("{base} ({label}, {count})");
                count = count.saturating_add(1);
            }
            stems.push(Stem {
                name,
                tracks: group.tracks,
            });
        }
        Ok(stems)
    }
}

/// Two names the same but for case.
fn same(a: &str, b: &str) -> bool {
    a.to_lowercase() == b.to_lowercase()
}
