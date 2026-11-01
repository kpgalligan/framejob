//! `set_transition_style` — a transition's curve and whether it crossfades
//! the sound, leaving its kind alone (spec §6, table "Transitions").
//!
//! Cut out of `edit_transition.rs` under the size rule, a pure move (road
//! map "audio" AP11's toll): the op only restyles a stored transition and
//! moves no clip, so it needs none of that module's placement arithmetic.

use crate::edit_adjustment::adjustment_transition;
use crate::model::{Curve, FadeShape, Project, Transition, TransitionKind};
use crate::outcome::Outcome;

impl Project {
    /// Sets the transition's CURVE and whether it crossfades the sound
    /// (spec §6, format version 7), and the crossfade's shape (format 29,
    /// spec §11 AU-115), leaving its kind alone.
    ///
    /// A second op rather than two more arguments on
    /// [`Project::set_transition`], and the reason is the envelope: that op
    /// reads an absent `kind` and an explicit `null` as the same thing — a
    /// CLEAR — so it has no way to spell "leave the curve where it is".
    /// Here no argument is nullable, so an absent key is unambiguous and
    /// means keep.
    ///
    /// It stores on the same terms `set_transition` does: any clip, with or
    /// without an overlap, since a stored transition on a clip with no
    /// overlap is simply undrawn until one exists. With NO stored
    /// transition and at least one key given it mints
    /// (`cross_dissolve`, spec §11 R5-2) and applies the style over it;
    /// with NO key given it is an identity whatever the clip holds
    /// and never mints — asking for no change is not a way to make a
    /// transition. `Err` for an unknown clip.
    pub fn set_transition_style(
        &self,
        clip: u32,
        curve: Option<Curve>,
        audio: Option<bool>,
        audio_shape: Option<FadeShape>,
    ) -> Result<Outcome, String> {
        let target = self.require_clip(clip)?;
        let stored = target.transition_in;
        if curve.is_none() && audio.is_none() && audio_shape.is_none() {
            return Ok(Outcome::Identity);
        }
        if let Some(why) = adjustment_transition(target) {
            return Ok(Outcome::Refused(why));
        }
        let mut next = self.clone();
        if let Some(slot) = next.clip_mut(clip) {
            let mut transition =
                stored.unwrap_or_else(|| Transition::minted(TransitionKind::default()));
            if let Some(curve) = curve {
                transition.curve = curve;
            }
            if let Some(audio) = audio {
                transition.audio = audio;
            }
            if let Some(shape) = audio_shape {
                transition.audio_shape = shape;
            }
            slot.transition_in = Some(transition);
        }
        self.finish(next)
    }
}
