//! The word-caption vocabulary (format version 9, road map 8's W1b):
//! [`TextCase`], the [`Word`] timings a caption page carries, and the
//! [`WordStyle`] (with its [`WordMode`] and [`ActivePill`]) that says how
//! the word being spoken is drawn — plus the two small facts every writer
//! of `text.words` shares, [`token_count`] and [`rebase_words`]. Format
//! version 12 (spec §11, W-12) added three looks as KEYS, each off by
//! default: [`ActivePill::glide`], [`WordStyle::active_fill`] and
//! [`WordStyle::pause_dim`].
//!
//! **A word caption is an ordinary text clip holding one PAGE** (spec §11,
//! W-1): `content` is the page, `words` is one `{start, end}` per
//! whitespace token of it, in CLIP time, and `word_style` is how the
//! renderer shows which of them has been said. Nothing here is a measured
//! size or a per-frame answer — `recipe_words.rs` computes the five word
//! keys (`word`, `word_pop`, `word_glide`, `word_fill`, `word_dim`) from
//! these at render time and stores nothing — which is the seam `model_text.rs` states for the text group as a whole, read once
//! more: the model says what the words ARE and when they are said, and only
//! the platform knows where each one lands on the page.
//!
//! **The core is the one counter** (W-2). [`token_count`] is
//! `str::split_whitespace`, the rule road map 8's W0 q4 measured against the
//! renderer's own tokenizer over a corpus written to make them differ, and
//! they agree on the COUNT in every row — the only number `check_text`
//! reads. **Word times move with the content, not with the clip's length**
//! (W-3): [`rebase_words`] is the one subtraction `trim_start`, `roll`,
//! `add_transition`'s handle form and `split`'s second half each make, and
//! nothing rescales them.
//!
//! Re-exported whole by `model_props.rs`, which `model.rs` re-exports whole
//! in turn, so `crate::model::WordStyle` resolves like every other property
//! type; the FIELDS holding these (`TextProps.case`, `.words`,
//! `.word_style`) stay with the text group. The two functions are
//! `pub(crate)`, and a glob re-export cannot widen them, so their callers
//! name `crate::model_words` directly.
//!
//! No enum's declaration ORDER is load-bearing — nothing derives a number
//! from it — so a value may be added at the END (W-4). The JSON spelling of
//! each variant IS persisted, so a rename needs a migration step. The rules
//! are `model.rs`'s: the field names ARE the JSON keys, declaration order IS
//! key order, every struct is `#[serde(default)]` over a [`Default`] that
//! says what an absent key means, and nothing here carries
//! `deny_unknown_fields`.

use serde::{Deserialize, Serialize};

use crate::model::{Color, TextProps};
use crate::time::Ticks;

/// A transform the renderer applies to `content` before layout. It is part
/// of the layout key, because it changes the measured width, and it never
/// changes the token count, so `words` is untouched by it.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TextCase {
    /// The text as it was typed — every text clip before version 9.
    #[default]
    AsWritten,
    Upper,
}

/// When one whitespace token of `content` is said, in CLIP ticks.
///
/// A negative `start` is legal and means "already said": `split` rebases
/// the second half's words by the cut, so a split page is invisible. Two
/// words may share a `start` — the engines' 0.06 s grid snapped to a frame
/// can land two on one — and the later one wins that frame. `end` is what
/// the pager reads the gaps from, and since format version 12 the recipe
/// reads it too: a word fills until its `end` (capped), and a pause is the
/// gap from one word's `end` to the next one's `start` (spec §11, W-13).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct Word {
    pub start: Ticks,
    pub end: Ticks,
}

/// How the words not yet active are shown.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WordMode {
    /// The whole page is drawn; the active word is picked out.
    #[default]
    Highlight,
    /// Words appear as they are said; upcoming ones are hidden.
    Build,
}

/// A rounded plate drawn behind the active word. `padding` and `radius` are
/// FRACTIONS of the text's `size`, so a pill around one word tracks that
/// word's size rather than a fixed pixel count.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct ActivePill {
    pub color: Color,
    pub padding: f64,
    pub radius: f64,
    /// Whether the plate SLIDES from the word before to the active one
    /// rather than jumping (format version 12; spec §11, W-12). It lives on
    /// the pill because without a pill nothing slides.
    pub glide: bool,
}

impl Default for ActivePill {
    /// A saturated purple plate — visibly SOMETHING the moment it is on.
    fn default() -> Self {
        ActivePill {
            color: [0.55, 0.27, 0.93, 1.0],
            padding: 0.2,
            radius: 0.25,
            glide: false,
        }
    }
}

/// How a timed page shows which word is being said (W-4: a closed
/// vocabulary; the recipe carries a computed answer, never the timings).
/// Every colour that is `None` means "the text's own colour".
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct WordStyle {
    pub mode: WordMode,
    pub active_color: Option<Color>,
    /// Where the active word's pop settles, 1.0…1.5. At 1.0 the recipe's
    /// `word_pop` is null and the texture changes only at word boundaries.
    pub active_scale: f64,
    pub active_pill: Option<ActivePill>,
    /// Words already said.
    pub spoken_color: Option<Color>,
    /// Words not yet said (highlight mode).
    pub upcoming_color: Option<Color>,
    /// Whether the active word fills left to right as it is said, from its
    /// `start` to its `end` (format version 12; spec §11, W-12).
    pub active_fill: bool,
    /// How far the page dims in a pause between words, 0 (off) to 1
    /// (invisible): its opacity there is `1 − pause_dim` (format version 12).
    pub pause_dim: f64,
}

impl Default for WordStyle {
    fn default() -> Self {
        WordStyle {
            mode: WordMode::Highlight,
            active_color: None,
            active_scale: 1.0,
            active_pill: None,
            spoken_color: None,
            upcoming_color: None,
            active_fill: false,
            pause_dim: 0.0,
        }
    }
}

impl WordStyle {
    /// Every slot filled with its default.
    ///
    /// Not a value any clip is given: this is what `patch.rs`'s text
    /// template holds so the key walk knows the kind of every member an
    /// optional slot can carry, which a `None` could not tell it.
    pub fn template() -> WordStyle {
        WordStyle {
            mode: WordMode::Highlight,
            active_color: Some([1.0, 1.0, 1.0, 1.0]),
            active_scale: 1.0,
            active_pill: Some(ActivePill::default()),
            spoken_color: Some([1.0, 1.0, 1.0, 1.0]),
            upcoming_color: Some([1.0, 1.0, 1.0, 1.0]),
            active_fill: false,
            pause_dim: 0.0,
        }
    }
}

/// How many words `content` holds — THE token rule (W-2):
/// `str::split_whitespace`, measured against the renderer's tokenizer by
/// road map 8's W0 q4. A non-empty `words` must match it.
pub(crate) fn token_count(content: &str) -> usize {
    content.split_whitespace().count()
}

/// Moves every word `by` ticks EARLIER in clip time — what a clip whose
/// head moved `by` later along its content must do so each word stays on
/// the speech it times (W-3). Saturating, because the file reader stores
/// `words` unchecked and no input may panic.
pub(crate) fn rebase_words(text: &mut TextProps, by: Ticks) {
    for word in &mut text.words {
        word.start = word.start.saturating_sub(by);
        word.end = word.end.saturating_sub(by);
    }
}
