# Word captions — the social-video style (road map 8)

- **Status:** Built (2026-09-23), phases W0 (spike) to W4b. Landed in one
  commit, `532e115`. Nothing in the phase list is left. The not-built list
  (orig §7) is where the next work starts.
- **Original:** `archive/reelcut-roadmap-8.md` (2971 lines) holds the full
  record. "orig §x" below points into it.
- **Spec decisions:** spec §11 **W-1..W-10** (W-10 as the core's sentence;
  W-9 was copied into §11 on 2026-09-26). This work extends R6-1 and reads R6-2, R6-3, R6-7, R6-12,
  R6-15, R6-16, D7-1, D7-3 and D1 across. W-8 amends two older §11 decisions:
  "`async` only in `MediaImporter`" and "the one-minute ceiling is reported,
  not chunked around".
  - W-1: a word caption is an ordinary text clip holding one PAGE.
  - W-2: `text.words` has one `{start,end}` per whitespace token, and the
    core is the one counter.
  - W-3: word times are clip time. They move with the content and are never
    rescaled.
  - W-4: `word_style` is a closed vocabulary. The recipe carries a computed
    answer, not timings.
  - W-5: when `word_style` and `animation` are both set, `word_style` wins.
  - W-6: `words` is not an action target, and paste treats it as content.
  - W-7: pages are filled to a measured width in one Swift builder.
  - W-8: the minimum is macOS 26, and the on-device engine is
    `SpeechTranscriber`.
  - W-10: `set_text` can patch all three keys, and restyling means
    regenerating.

## Context

Talking-head shorts and reels show speech as large, styled text on one row
near the bottom of the frame, with each word lit as it is said. Reelcut's
captions were subtitles only. `CaptionCues.build` threw away the per-word
timing that both engines already produced, grouping the words into cues of
two lines, 42 characters and 6 s. The ask (2026-09-22) was to generate this
look from either engine, the on-device one or AssemblyAI.

The user's answers shaped the design (orig §6):
- Generate Captions offers a choice of style.
- A page is filled to the width the text will measure when rendered, not to
  a word count. It wraps only when it cannot avoid it.
- Some display fonts are bundled.
- UPPERCASE is a style property.
- Restyling means regenerating.
- macOS 26 is the minimum, so the on-device engine becomes
  `SpeechTranscriber`.

## Decisions

**A word caption is one text clip per PAGE, with its words timed inside it
(W-1).** One clip per word was rejected for four reasons (orig §0):
- It cannot show one row in two styles.
- It hits `RC_MAX_CLIPS` (4096) after about 25 minutes of speech.
- It makes the plan quadratic, because every clip edge is an instruction
  boundary.
- It blinks, because the cue builder leaves a one-frame gap between cues.

A new source kind was also rejected: R6-1 already makes every caption an
ordinary text clip. Outline, backdrop, shadow, motion, the inspector, burn-in
and `.srt` export all come free with a text clip.

**The model grows three text keys, `case`, `words` and `word_style`, in
format version 9 (orig §5a).** All three are serde-defaulted, so no migrate
step is needed. The version still bumps, because an older build would drop
the keys and then save the loss.
- `case` is either `as_written` or `upper`. Swift applies it before layout.
  It is part of the layout key and never changes the token count.
- The pill's `padding` and `radius` are fractions of the font size, so a pill
  tracks the size of its word.

**The token rule is `str::split_whitespace`, and only the COUNT crosses the
seam (W-2; orig §4, §10.1 q4).**
- W0 checked it against a verbatim copy of the renderer's `tokens(of:)` on a
  24-row adversarial corpus (NBSP, ZWSP, CRLF, BOM, ZWJ, CJK, RTL). The count
  agreed in every row.
- One RANGE differs: for `"a \u{0301}b"`, Swift treats the space plus the
  combining mark as one whitespace grapheme. Nothing reads offsets across the
  seam, so this does no harm. A future phase that sends ranges across the
  seam must deal with it first.
- "Alternative B", core-computed UTF-16 ranges in the recipe, was retired.
- A mismatched count is an ERROR (spec §5.5's fourth answer, no undo step)
  in the rule's own sentence. The design said "refusal", but W1b built it as
  an `Err` because spec §6 makes every `set_*` range failure an error.

**Word times are rebased, never rescaled (W-3).**
- `trim_start`, `roll` and `add_transition`'s handle form subtract the delta.
  Actions behave differently: a head trim leaves them in place.
- `split` gives the second half the full list, rebased. It stores `[]` if
  that half's evaluated content has a different token count.
- A negative start is legal and means "already said".
- Times snap to the frame grid, and stay inside D7-1's envelope.
- A duration change never rescales them.
- W0 measured what the engine emits: a 0.06 s grid, ranges that tile, no
  zero-length words, no decreasing starts. So the rebase is plain
  subtraction.

**The recipe carries `word` and `word_pop`, never the timings (W-4; orig
§5b).**
- `word` is how many words have started. `word_pop` is 0..1 over `WORD_POP`
  (72 000 ticks, 0.12 s), and is null at `active_scale` 1.0.
- `words` is stripped from the description.
- `text_hash` folds the two keys in ONLY when `word_style` is set, so an
  unstyled clip's hash is byte-identical with or without `words`.
- `end` is stored but not read. The active word holds until the next start.
  Storing `end` keeps "dim during silence" and a karaoke fill as recipe
  changes rather than schema changes.

**`word_style` beats `animation` without refusing the pair (W-5).** The reveal
keys go null and the Reveal note is greyed. A paste that lands a word style
on an animated title must not fail for a reason nobody can see.

**`words` is not an action target, and paste carries it with `content`
(W-6).** An action end naming `words` is an `Err`. A mismatch that only a
content-switching action can produce degrades instead: `word` goes null and
the page draws static.

**Pages are filled by the renderer's own measurement, in Swift (W-7; orig
§5c).** `CaptionPages` asks `LayerRenderersText.measuredSize` about each
candidate page's real `TextProps`, including the headroom. It does not
estimate.
- Why Swift: only the platform measures text, and measured sizes never enter
  the model.
- Cost, measured: about 17 µs per call, so a whole 10-minute talk pages in
  well under 50 ms. The call is thread-safe under the compositor (orig
  §10.1 q5).
- `CaptionCues` is untouched, and Subtitles output is byte-identical.
- Rules:
  - Page breaks come from speaker changes, gaps ≥ `breakGap`, sentence
    punctuation, `maxLength`, `maxWords` (One Word only) and width.
  - After a width break, one balance move of the last word, if it brings the
    two widths closer.
  - A preference for breaking at a clause mark.
  - A lone over-wide word shrinks in 5 % steps down to 80 %, then wraps at
    the budget width.
  - A page ends at `min(next.start, last.end + hold)`, extended to the next
    page when the gap is under `breakGap`: no blink.

**Pauses come from word gaps of 0.25 s plus sentence punctuation. The
silence detector is not consulted (W-7; orig §5c, §10.9).**
`SpeechTranscriber`'s word ranges TILE the audio: a 1.57 s real silence
showed as a 0.30 s gap, and a 1.13 s one as 0.06 s. So the literature's
0.4 s `breakGap` found nothing, and 0.25 s was chosen. W4a injected road map
4's detector pauses as forced breaks and got the same ten pages, because the
punctuation already broke there.

**Each engine has its own `lead`, applied once in `normalize` and never to
Subtitles (W-7).** On-device is +270 ms: the engine starts words early.
AssemblyAI is −60 ms. Both are W0 q2's signed medians against known onsets.
They are starting points for a person to adjust by eye, not a calibration.

**A page is confined to its job's clip span (W-7; orig §10.9).** Neither
`lead` nor `hold` carries a page past its clip. A word pushed off the end
sits on the clip's last frame. `Transcriber.Job.span` is the one place that
span is spelled.

**A shrunk page is one construction in three places (W-7; orig §10.10
residue).** `CaptionStyle.textProps` is what the pager measures and the
preview draws. `pagePatch`, built from it, is what `place` writes. So the
outline is em × the SHRUNK size everywhere.

**macOS 26 minimum, with `SpeechAnalyzer`/`SpeechTranscriber` replacing
`SFSpeechRecognizer` (W-8; orig §5f, §5g, §10.4, §10.6).**
- `SpeechEngine.swift` is the one new `async` file. Callers use synchronous
  wrappers.
- Deleted: the one-minute ceiling (W0 found none: 99.81 % of a 613 s file
  came back); the TCC grant (none needed, even in a hardened-runtime bundle
  without the usage key); `NSSpeechRecognitionUsageDescription`; and
  `transcribe`'s `truncated` and `note` keys.
- The bump cost three new `AVMutableVideoComposition` deprecation warnings,
  so the typecheck baseline is now 7. `AVVideoComposition.Configuration` was
  not adopted.
- `DictationTranscriber` is not built until some locale needs it.

**Installed-model detection reserves, reads and releases through a
serialising `Gate` actor (orig §10.6).**
- `AssetInventory.status` answers `.installed` only for a RESERVED locale,
  and `assetInstallationRequest` is non-nil even for an installed one. So
  `isInstalled` reserves, reads `status`, then releases.
- The cap is 5 reserved locales, so every path releases what it reserved.
- Release matches by BCP-47 tag, because the framework's own spelling
  differs.
- The caller is answered before its release queues, so one stalled holder
  cannot block an analysis from finishing.
- A download is a person's act. `transcribe` refuses an uninstalled locale
  by name and never downloads (R6-12 read across). The size cannot be named,
  because progress before a download reports 0 units.

**No language model chooses words (W-9).** Every styled word
is styled by its position in time, never by its meaning. Keyword emphasis
and emoji are out.

**Restyling is regenerating (W-10).**
- There is no Words inspector section and no re-page command.
- Generate Captions with "Replace existing captions" replaces the old track
  in one grouped undo step. A track counts as replaceable when:
  - its name is one of `CaptionLayout`'s;
  - it is all text clips;
  - it lies inside the scope;
  - it holds at least one clip (W4b).
- `set_text` can still patch the three keys. That is the agent's door, with
  no promise that the page still fits.
- A content edit that changes the token count sends `words: []`. The page
  then draws static, with a "Not timed — regenerate" footnote.

**Word-style headroom is computed per page, not flat (orig §5d, §10.7, W4a
corrections).**
- Horizontal: `max(0.45 em, peak×pad + (peak−1)×widest/2 − outline + 2 px)`.
  With no pill, the stroke term is ADDED instead: `+ peak×outline/2`.
- Vertical: `max(0.30 em, … (ascent+descent)/2 … + 3 px)`.
- `peak = 1 + (scale−1)×1.1` is the back-out overshoot.
- The pre-spike rule, `max(pad, (scale−1)×line/2)`, was short by more than
  half, and in the wrong axis: the worst overflow is horizontal, at the first
  and last word.
- The box never depends on which word is active.

**Styles are a generation choice, not inspector presets (orig §5h).** They
live in `CaptionStyle`: Subtitles, Highlight, Pill, Karaoke, Build and One
Word. Fonts are named by the PostScript name the registry returns. Four OFL
faces are bundled: Montserrat ExtraBold and Black, Anton, Bebas Neue. Karaoke
is the one style that pages to two lines by design.

**The sheet's preview is drawn by the renderer's own routine (orig §5e,
§10.10).**
- The routine is `LayerRenderers.textBitmap`. The sample page is the first
  page the real pager makes (`CaptionPages.samplePage`).
- It shows two stacked frames: word 1 active, then word 2. Subtitles shows
  one frame.
- It is redrawn only when `PreviewKey` changes.
- The chosen style is remembered under `CaptionStyle.defaultsKey`. It is
  not part of the transcript marker (R6-15).

## What it built — where it lives now

- **Core:**
  - `core/src/model_words.rs`: the vocabulary, `token_count`,
    `rebase_words`.
  - `core/src/recipe_words.rs`: `Words::of`, `WORD_POP`.
  - Hash arm and key emission in `core/src/recipe_text.rs`.
  - Checks in `core/src/props_check.rs`.
  - Rebases in `edit_clip_timing.rs`, `edit_edge.rs`, `edit_transition.rs`
    and `edit_split.rs`.
  - W-6 in `edit_action.rs` and `edit_paste.rs`.
  - Tests in `core/tests/schema_v9.rs` and `core/tests/words.rs`.
- **Picture:**
  - `app/Sources/LayerRenderersWords.swift`: the fourth routine and the
    headroom.
  - `LayerRenderersReveal.swift`: the three reveals, a toll moved out of
    `LayerRenderersText.swift`.
  - `LayerRenderersText.swift`: `layoutKey`, the insets, `textBitmap`.
  - `WordProps.swift`: the Swift vocabulary, `laidContent`, `contentEdit`.
  - `TextProps.swift` and `TextPatch.swift`: toll moves out of
    `ProjectSnapshot.swift` and `ReelCore.swift`.
  - `TextPane.swift`: the UPPERCASE checkbox and the Content footnote.
  - The fonts in `app/Resources/Fonts/`.
- **Generation:**
  - `app/Sources/CaptionStyle.swift`
  - `CaptionPages.swift`
  - `CaptionLayout.swift`: `Cue.words`/`size`/`width`,
    `place(style:replacing:)`, `replaceableTracks`.
  - `Transcriber+Jobs.swift`: `Job.span`.
  - `TranscribeSheetController+Style.swift`
- **Engine:**
  - `app/Sources/SpeechEngine.swift`
  - `Transcriber.swift`, with the SF half deleted.
  - `Transcriber+Languages.swift`
  - `TranscribeSheetController+Download.swift`
- **MCP:** `transcribe` gained `style` and `replace`, and returns per-cue
  `words`/`size`. Code is in `AgentServer+Captions.swift` and
  `AgentCatalog+Captions.swift`. No new `rc_*` export and no new op.
- **Proofs (`tools/proof/`):**
  - `words_core_proof.py`
  - `words_picture_proof.py`, `words_picture_probe.py`,
    `words_picture_chrome.py`
  - `speech_engine_proof.py`, `speech_engine_probe.swift`
  - `word_captions_proof.py`, `word_captions_probe.py`/`.swift`,
    `word_captions_chrome.py`
  - `target_bump_proof.py`, `reveal_toll_proof.py`
  - The spike: `words_spike/`

## Known limits

- **Word-start accuracy is loose.** The engines disagree by a median of
  98–314 ms and a p95 of up to 914 ms, worst 1.22 s. The proof bound is
  median ≤ 350 ms and p95 ≤ 950 ms. It says both engines describe the same
  speech, not that either is accurate. The pre-spike bound (60/150 ms) is
  unreachable (orig §8).
- **Pauses without punctuation may not break a page.** The gap rule sees
  tiled ranges. Detector pauses were measured as adding nothing only on the
  pangram (orig §10.9).
- **The first raster of a face in a process costs about 12 ms**, over the
  8 ms budget. After that, a pop re-raster is 0.5 ms at 1080×1920 and
  1.1–1.3 ms at 4K (orig §10.1 q5).
- **`SourceSans3-Bold`, the Title preset, does not round-trip.** It resolves
  to `SourceSans3-Roman_Bold`, a variable-font instance: the right glyphs
  under another name. `CTFontCreateWithName` never answers nil and falls back
  to Helvetica silently. Whether `SourceSans3-Regular` round-trips was never
  measured.
- **Paste and actions do not protect a page's timings.**
  - Paste stores its payload whole, so a pasted clip with a count mismatch is
    refused at its next `set_text` until `words: []` is sent.
  - `actions.rs` does not restore base `words`: a hand-written action's
    `words` just interpolate.
  - A content-switching action leaves `word` null (W-6).
- **The Download row is unproven against a real download.** The progress
  before a download is indeterminate with 0 units, and `downloadAndInstall()`
  has never been run on the build host.
- **A stalled `AssetInventory` holder turns every later `isInstalled` into
  `.unavailable` until relaunch**, by design of `askBound`.
- **A finished analysis's release can drop a following same-locale
  analysis's reservation**, because it releases by tag. This was accepted,
  and it had no measured effect.
- **With zero installed models, `supportedLanguages()` never caches.** Every
  sheet open re-asks both lists on main, bounded at 10 s each.
- **The no-blink extension is invisible at the default numbers.** `hold`
  (0.5 s) outlasts `breakGap` (0.25 s). It is kept as a rule, and a probe row
  exercises it at hold 0.1 s.
- **A lone word stays alone when the balance step cannot improve it.**
- **`JSONSerialization` drops a leading U+FEFF.** Any corpus shipped through
  JSON has that hole (orig §5b).
- **A named `UserDefaults` suite cannot be removed from inside a process.**
  cfprefsd writes a 42-byte empty plist late. Probes use `MemoryDefaults`
  instead (orig §10.10).

## Open items

- The person checks are tracked in #52:
  - no network;
  - a real model download: its progress, cancel, the popups' lock and the
    model's survival;
  - the Download row looked at;
  - the bundled faces on a Mac without the families;
  - sync by eye per engine;
  - each style on real footage at 9:16 and 16:9;
  - 60 fps with pops;
  - the preview looked at;
  - the Style row seen as a sheet.
- The not-built list (AI emphasis/emoji, a sliding pill, a karaoke in-word
  fill and "dim during silence", restyling in place, WebVTT inline
  timestamps, filler words, per-word confidence styling) is tracked in #96.
- Three choices shipped unconfirmed: Karaoke's two-line exception, the
  initial font set and the 80 % shrink floor. The user confirmed all three
  on 2026-09-28 (spec §11 W-11; #45 closed).
- Spec §7.7's format list still says "measured on macOS 15" and
  was not re-measured at 26. Tracked in #46.
- `AVVideoComposition.Configuration` not adopted (the 3 deprecation warnings
  since the bump). Tracked in #91.
- Stale text and small nits:
  - `ProjectSnapshot.formatVersion = 5` (#84)
  - the "three computed keys" docs in `recipe_text.rs` (closed 2026-09-26:
    accurate, three reveal keys then two word keys)
  - a 128-character doc line in `CaptionLayout.swift` (fixed by 2026-09-26)
- `paste` stores a `words` count mismatch whole (refused at the next
  `set_text`). Tracked with `paste`'s payload in #62.
- Not tracked: `words_core_proof.py` (425) and `word_captions_probe.swift`
  (422) are over 400 lines, but proof instruments are not held to the
  new-file cap (the root `CLAUDE.md`).

## Where to look in the original

- orig §0–§1: the idea. Why one page per clip, why not a new source kind,
  and the decision in one paragraph.
- orig §2: how the reference products (CapCut, VEED, Submagic, Remotion) page
  and highlight, and the engines as documented versus as measured.
- orig §3, §3a: the seven W0 spike questions, and every design section the
  spike rewrote.
- orig §4: W-1..W-10 in full, with the measurements behind W-2, W-3 and W-8.
- orig §5a–§5m: the design. Model, recipe, pager, drawing, sheet, engine,
  the macOS 26 bump, the styles table, the MCP mirror, export, file tolls,
  proof rows and person checks.
- orig §6: the user's answers, verbatim.
- orig §7: not built, and why.
- orig §8: the tunable numbers (budget 0.86, shrink 0.80, maxLength 3 s,
  breakGap 0.25 s, hold 0.5 s, lead ±, WORD_POP, headroom, tolerance) and
  where each came from.
- orig §10.1: the spike's measurements, rows q1–q7.
- orig §10.2–§10.3: spend, and what did not run.
- orig §10.4: W1a, the target bump.
- orig §10.5: W1b, the core.
- orig §10.6: W2, the engine, with its two reviews.
- orig §10.7: W3, the picture (headroom, tolls, mutants).
- orig §10.9: W4a, generation (the pause, lead and span decisions).
- orig §10.10: W4b, the sheet and the residue.
