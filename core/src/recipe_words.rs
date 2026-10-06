//! What a timed text page SHOWS at one instant: [`Words`] — how many of its
//! words have started, how far the newest one's pop has got, and how far
//! its pill's glide, its fill and the page's dim have got — the five
//! computed keys `recipe_text.rs`'s `text_source` emits on every text layer
//! as `word`, `word_pop`, `word_glide`, `word_fill` and `word_dim` (spec
//! §7.3; road map 8 §5b; spec §11 W-13 for the last three).
//!
//! The recipe carries a computed ANSWER, never the timings (spec §11, W-4):
//! `text.words` is stripped from the description the renderer receives, as
//! `text.animation` is, and these five numbers are the whole of what it is
//! told. The renderer derives the rest from `word` — the active word is
//! token `word − 1`, the spoken ones are before it, the upcoming ones from
//! `word` on, and a gliding pill comes from token `word − 2` — with its own
//! tokenizer, and no offset and no second index crosses the seam (the two
//! tokenizers agree on the COUNT, which is the only number shared).
//!
//! A new module rather than more of `recipe_text.rs` because that file is a
//! reveal and a burn-in and stood at 510, and because this is a second,
//! independent account of a text layer's content over time: W-5 says the
//! two do not compose, so a styled page is a WHOLE reveal and only this
//! module speaks for it.

use serde_json::{Map, Value};

use crate::evaluate::number;
use crate::model::TextProps;
use crate::model_words::token_count;
use crate::recipe_text::ramp;
use crate::time::Ticks;

/// How long the active word's pop takes to settle into `active_scale`:
/// 0.12 s (road map 8 §8). Long enough to read as a pop, short enough that
/// a page re-rasterizes for a handful of frames after each word start and
/// then hits the texture cache again.
pub(crate) const WORD_POP: Ticks = 72_000;

/// How long a pill takes to slide to the active word: 0.2 s, or the time
/// until the next word starts when that is sooner, so the plate has always
/// arrived before it must leave again.
pub(crate) const WORD_GLIDE: Ticks = 120_000;

/// The longest a word takes to fill: 0.6 s (spec §11 W-13, the owner's
/// choice — a chosen number, not a measured one). A word's `end` is not
/// always where it stopped being said: the on-device engine's word ranges
/// tile the audio, so the last word before a pause is stored as lasting
/// through most of the pause (road map 8 measured a 1.57 s silence stored as
/// a 0.30 s gap), and uncapped it would crawl for over a second.
pub(crate) const WORD_FILL_MAX: Ticks = 360_000;

/// How long the page takes to dim at the start of a pause, and to come back
/// before the next word: 0.1 s each way.
pub(crate) const WORD_DIM: Ticks = 60_000;

/// The shortest pause that dims: 0.25 s — the pager's own word gap (W-7).
/// Under it a pause is an ordinary gap between two words of a sentence, and
/// dimming there would flicker.
pub(crate) const WORD_DIM_GAP: Ticks = 150_000;

/// The five computed word keys of one text layer at one instant.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Words {
    /// How many words have started, 0 to n; `None` when the page is not
    /// word-timed (no `word_style`, empty `words`, or a count mismatch).
    pub(crate) word: Option<usize>,
    /// 0..1 through the active word's pop; `None` before the first word
    /// starts, or when `active_scale` is 1.0 and there is nothing to pop.
    pub(crate) pop: Option<f64>,
    /// 0..1 through the pill's slide from token `word − 2` to the active
    /// one; `None` unless `active_pill.glide` is set and a second word has
    /// started — a page's first word has no word to slide from.
    pub(crate) glide: Option<f64>,
    /// 0..1 through the active word's fill, holding 1.0 after; `None`
    /// unless `active_fill` is set and a word has started.
    pub(crate) fill: Option<f64>,
    /// 0..1 into the dim of a pause; `None` unless `pause_dim` is above 0.
    pub(crate) dim: Option<f64>,
}

impl Words {
    /// A layer that is not word-timed: every key null.
    pub(crate) const NONE: Words = Words {
        word: None,
        pop: None,
        glide: None,
        fill: None,
        dim: None,
    };

    /// The word keys `clip_t` ticks into a clip that is `duration` long.
    ///
    /// Total, and it assumes nothing about ORDER. The patch door refuses a
    /// list whose starts decrease, but it is not the only writer: the file
    /// reader stores `words` whole
    /// (`edit_props.rs`'s `normalise_and_check_group` doc), so an unsorted
    /// list, or a start of `i64::MIN`, reaches here. `word` is therefore a
    /// COUNT of started words rather than a search, every other word is
    /// read by `get`, every subtraction saturates and every division is
    /// `recipe_text.rs`'s `ramp`, which answers 0..1 for any two ticks. A
    /// count mismatch (which only an action switching `content` can
    /// produce, W-6) degrades to [`Words::NONE`]: the page draws static
    /// rather than highlighting the wrong token.
    pub(crate) fn of(text: &TextProps, clip_t: Ticks, duration: Ticks) -> Words {
        let style = match &text.word_style {
            Some(style) => style,
            None => return Words::NONE,
        };
        let count = text.words.len();
        if count == 0 || count != token_count(&text.content) {
            return Words::NONE;
        }
        // Equal starts are legal (two engine words snapped to one frame),
        // and both count: the later of them is the active word, which is
        // "the later one wins that frame".
        let word = text.words.iter().filter(|w| w.start <= clip_t).count();
        let active = word.checked_sub(1).and_then(|i| text.words.get(i));
        let next = text.words.get(word);
        let pop = match active {
            Some(active) if style.active_scale != 1.0 => {
                Some(ramp(clip_t.saturating_sub(active.start), WORD_POP))
            }
            _ => None,
        };
        // The glide runs from the active word's start, and is over by the
        // next word's: a word shorter than `WORD_GLIDE` gets a quicker
        // slide rather than a pill that never arrives.
        let glides = style.active_pill.is_some_and(|pill| pill.glide);
        let glide = match active {
            Some(active) if glides && word >= 2 => {
                let over = next.map_or(WORD_GLIDE, |next| {
                    WORD_GLIDE.min(next.start.saturating_sub(active.start))
                });
                Some(ramp(clip_t.saturating_sub(active.start), over))
            }
            _ => None,
        };
        let fill = match active {
            Some(active) if style.active_fill => {
                let spoken = active.end.saturating_sub(active.start);
                Some(ramp(
                    clip_t.saturating_sub(active.start),
                    spoken.min(WORD_FILL_MAX),
                ))
            }
            _ => None,
        };
        let dim = (style.pause_dim > 0.0).then(|| {
            // The pause this instant is in runs from the active word's end
            // — clip time 0 before the first word — to the next word's
            // start — the clip's end after the last.
            let from = active.map_or(0, |active| active.end);
            let until = next.map_or(duration, |next| next.start);
            if clip_t < from || until.saturating_sub(from) < WORD_DIM_GAP {
                return 0.0;
            }
            // A side with no word on it has no ramp: the page opens dim
            // before a late first word, and stays dim after the last.
            let down = active.map_or(1.0, |_| ramp(clip_t.saturating_sub(from), WORD_DIM));
            let up = next.map_or(1.0, |_| ramp(until.saturating_sub(clip_t), WORD_DIM));
            down.min(up)
        });
        Words {
            word: Some(word),
            pop,
            glide,
            fill,
            dim,
        }
    }

    /// Writes the five keys into `map` — a text layer's `source`, and the
    /// object its hash is taken over — in the recipe's order.
    pub(crate) fn insert_into(&self, map: &mut Map<String, Value>) {
        map.insert("word".to_string(), Value::from(self.word));
        let rest = [
            ("word_pop", self.pop),
            ("word_glide", self.glide),
            ("word_fill", self.fill),
            ("word_dim", self.dim),
        ];
        for (key, value) in rest {
            map.insert(key.to_string(), value.map_or(Value::Null, number));
        }
    }
}
