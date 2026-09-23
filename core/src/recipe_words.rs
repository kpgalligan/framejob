//! What a timed text page SHOWS at one instant: [`Words`] — how many of its
//! words have started, and how far the newest one's pop has got — the two
//! computed keys `recipe_text.rs`'s `text_source` emits on every text layer
//! as `word` and `word_pop` (spec §7.3; road map 8 §5b).
//!
//! The recipe carries a computed ANSWER, never the timings (spec §11, W-4):
//! `text.words` is stripped from the description the renderer receives, as
//! `text.animation` is, and these two numbers are the whole of what it is
//! told. The renderer derives the rest from `word` — the active word is
//! token `word − 1`, the spoken ones are before it, the upcoming ones from
//! `word` on — with its own tokenizer, and no offset crosses the seam (the
//! two tokenizers agree on the COUNT, which is the only number shared).
//!
//! A new module rather than more of `recipe_text.rs` because that file is a
//! reveal and a burn-in and stood at 510, and because this is a second,
//! independent account of a text layer's content over time: W-5 says the
//! two do not compose, so a styled page is a WHOLE reveal and only this
//! module speaks for it.

use crate::model::TextProps;
use crate::model_words::token_count;
use crate::time::Ticks;

/// How long the active word's pop takes to settle into `active_scale`:
/// 0.12 s (road map 8 §8). Long enough to read as a pop, short enough that
/// a page re-rasterizes for a handful of frames after each word start and
/// then hits the texture cache again.
pub(crate) const WORD_POP: Ticks = 72_000;

/// The two computed word keys of one text layer at one instant.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Words {
    /// How many words have started, 0 to n; `None` when the page is not
    /// word-timed (no `word_style`, empty `words`, or a count mismatch).
    pub(crate) word: Option<usize>,
    /// 0..1 through the active word's pop; `None` before the first word
    /// starts, or when `active_scale` is 1.0 and there is nothing to pop.
    pub(crate) pop: Option<f64>,
}

impl Words {
    /// A layer that is not word-timed: both keys null.
    pub(crate) const NONE: Words = Words {
        word: None,
        pop: None,
    };

    /// The word keys `clip_t` ticks into the clip.
    ///
    /// Total, and it assumes nothing about ORDER. The patch door refuses a
    /// list whose starts decrease, but it is not the only writer: `paste`'s
    /// payload and the file reader store `words` whole
    /// (`edit_props.rs`'s `normalise_and_check_group` doc), so an unsorted
    /// list, or a start of `i64::MIN`, reaches here. `word` is therefore a
    /// COUNT of started words rather than a search, and `pop` subtracts
    /// saturating and clamps to 0..1 — `recipe_text.rs`'s `ramp` is the
    /// precedent. A count mismatch (which only an action switching
    /// `content` can produce, W-6) degrades to [`Words::NONE`]: the page
    /// draws static rather than highlighting the wrong token.
    pub(crate) fn of(text: &TextProps, clip_t: Ticks) -> Words {
        let style = match &text.word_style {
            Some(style) => style,
            None => return Words::NONE,
        };
        if text.words.is_empty() || text.words.len() != token_count(&text.content) {
            return Words::NONE;
        }
        // Equal starts are legal (two engine words snapped to one frame),
        // and both count: the later of them is the active word, which is
        // "the later one wins that frame".
        let word = text.words.iter().filter(|w| w.start <= clip_t).count();
        let pop = if word == 0 || style.active_scale == 1.0 {
            None
        } else {
            let since = clip_t.saturating_sub(text.words[word - 1].start);
            Some((since as f64 / WORD_POP as f64).clamp(0.0, 1.0))
        };
        Words {
            word: Some(word),
            pop,
        }
    }
}
