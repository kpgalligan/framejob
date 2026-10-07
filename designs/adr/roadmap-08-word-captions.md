# Word captions — the social-video style (road map 8)

- **Status:** Built (2026-09-23), phases W0 (spike) to W4b. Landed in one
  commit, `532e115`. Nothing in the phase list is left. The not-built list
  (orig §7) is where the next work starts. Issue batch B86 (2026-10-05, #96)
  builds three of its looks: phase 1, recorded below, put them in the model,
  the recipe and the picture (spec §11 W-12..W-14); phase 2 put them in the
  sheet and `transcribe` (W-15) and closed the list.
- **Original:** `archive/reelcut-roadmap-8.md` (2971 lines) holds the full
  record. "orig §x" below points into it.
- **Spec decisions:** spec §11 **W-1..W-10**, and W-12..W-15 for issue batch
  B86's three looks (W-10 as the core's sentence;
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

**Issue batch B86 phase 1 (2026-10-05, #96): three looks from the not-built
list are keys of `word_style` (W-12, W-13, W-14).** The owner asked for a
sliding pill, an in-word fill and a dim in a pause, and chose every point
below.
- They are three KEYS, not modes: `active_pill.glide`, `active_fill` and
  `pause_dim` (0–1), each off by default. `mode` stays `highlight | build`,
  and the three combine with each other and with both. Format version 12, no
  migrate step; an older build refuses the file.
- The recipe carries three more computed answers, `word_glide`, `word_fill`
  and `word_dim`, and still no timing and no second index (W-4): the pill
  comes from token `word − 2`, which the renderer can count for itself.
- The glide takes 0.2 s, easing out, or the time to the next word when that
  is sooner. The pill appears on a page's first word; it never flies in from
  the page before.
- **A word takes at most 0.6 s to fill** (the owner's choice 4 (a)), because
  an on-device word's `end` is stretched over the silence after it. Known
  limits has both engines' behaviour.
- A pause dims only from 0.25 s, over 0.1 s each way; the depth is the key's
  value. **The dim is built as specified** (the owner's choice 7 (a)) though
  the pager ends a page at the same 0.25 s: Known limits says what that
  makes of it on generated captions.
- A gliding pill is drawn UNDER every word's ink, in every frame of its
  page; the fill's edge is hard, on a device pixel; the dim is one opacity
  over words and pill, and the backdrop never dims. With all three off the
  drawing calls are the ones road map 8 shipped, in their order.
- Phase 1 made them reachable through `set_text` only. The Generate Captions
  sheet's three checkboxes, `transcribe`'s booleans and the close-out of the
  not-built list are phase 2.

**Issue batch B86 phase 2 (2026-10-05, #96): the sheet and `transcribe`
(W-15).** The owner chose all four points as the spec built them.
- Three checkboxes under Style, one per line, no heading: "Slide the pill",
  "Fill words as spoken", "Dim in pauses". Each is off until ticked and is
  remembered under its own key, written by a CLICK and never by Generate,
  and never read by the tool. An older build's defaults hold none of the
  keys, so its remembered style opens with all three off.
- What is live when is derived from the style's own `word_style`, never a
  table: Slide with a pill (Pill); Fill where `build` or the active and
  upcoming colours differ (Highlight, Karaoke, Build); Dim with every word
  style. A box that is not live is greyed and KEEPS its tick (the owner's
  choice 2); it commits nothing while greyed.
- Dim writes `pause_dim` 0.5. While On this Mac and a word style are
  chosen, a two-line note under the boxes says on-device words rarely carry
  a pause (the owner's choice 3); the card is about two lines taller while
  it shows (34 pt in the offscreen probe).
- `transcribe` takes `slide`, `fill`, `dim`: a `true` that would show
  nothing (a style it is not live with, or `place: false`) is refused by
  name; an explicit `false` is always accepted (the owner's choice 4 (b)) —
  where `replace` and the cloud-only arguments refuse on presence. A placed
  run given any of them answers `looks`.
- The preview draws a ticked fill half done and a ticked pill half-way
  through its slide; the dim is not previewed.

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
- **Issue batch B86 phase 1 (2026-10-05, #96; spec §11 W-12..W-14):**
  - Core: `ActivePill.glide`, `WordStyle.active_fill` and
    `WordStyle.pause_dim` in `model_words.rs`; `pause_dim`'s range in
    `props_check.rs`; format version 12 in `format.rs` and the header;
    `recipe_words.rs`'s `Words::of(text, clip_t, duration)` with `word_glide`,
    `word_fill`, `word_dim`, the constants `WORD_GLIDE`, `WORD_FILL_MAX`,
    `WORD_DIM`, `WORD_DIM_GAP`, and `insert_into`, which `recipe_text.rs`
    calls for the source and the hash. Tests: `core/tests/word_looks.rs`
    (22), `core/tests/schema_v12.rs` (10).
  - Picture: `LayerRenderersWords.swift`'s `drawWords` takes `glide`, `fill`
    and `dim`; `WordProps.swift` and `TextProps.swift` mirror the keys.
    Two pure moves went first, each gated alone: `RecipeReveal` reads and
    writes its own sibling keys (out of `ProjectSnapshot.swift`), and
    `set_text`'s word clause is `AgentServer.textWordsClause` (out of
    `AgentCatalog+Clips.swift`).
  - MCP: `set_text`'s patch description teaches the three keys. No op, no
    `rc_*` export, no tool.
  - Proofs: `word_looks_proof.py` (an existing project's frames held to the
    bytes of the build before B86, `word_looks_baseline.json`, which
    `--record-baseline` refuses to write from a tree with uncommitted
    sources; the glide, the fill and the dim read off `render_frame` PNGs;
    six mutants) and `words_picture_probe.py`'s P2 sweep, P10, and P11–P16,
    the looks' geometry read off `textBitmap` (seven mutants).
  - **What a look costs, as P10 printed it** (2026-10-05, one host, judged
    in High Power on battery — `pmset -g` `powermode 2`, Low Power Mode off,
    thermal state nominal before the rasters and after; an unoptimised probe
    build, word 3, the median of 20 rasters-and-uploads on a cache miss,
    every page one line). The Highlight preset's page: at 1080×1920 pop
    1.215 ms, fill 1.187 ms, fill with dim 2.435 ms, glide 1.200 ms; at
    3840×2160 pop 2.439 ms, fill 2.449 ms, fill with dim 7.174 ms, glide
    2.514 ms. The page One Word generates, one word in the largest type a
    preset ships, fill with dim: 1.553 ms and 4.982 ms. The budgets are 4 ms
    and 8 ms, not raised, and **the two pages P10 scores are inside them**:
    Highlight's six words on one line and One Word's one-word page. No run
    timed a dim on Pill's, Karaoke's or Build's page in a judged power
    state; Karaoke's is the one preset page of two lines. It
    also prints, unscored, a hand-made page — the same six words on one line
    at One Word's size — which read 3.100 ms and 9.529 ms, over the budget
    at 3840×2160; Known limits has it. (The run that printed these scored
    that line and failed on it; the scoring was put right the same day, and
    a run under it passed, 7.382 ms and 4.915 ms on the two scored dims at
    3840×2160, beside another session's `make test`.) An
    earlier run that day in Low Power Mode read higher — Highlight's fill
    with dim 3.067 ms and 9.268 ms, the hand-made line 3.951 ms and 12.043 ms
    (that pair beside a running build) — and P10 now reads the power state
    and does not judge a run taken in Low Power Mode or above a nominal
    thermal state: it fails it by name.
  - Owed to phase 2: the sheet's three checkboxes and their remembered
    defaults, `transcribe`'s `slide` / `fill` / `dim`, the preview, the
    README, `docs/manual-checks.md` and the not-built list's close-out; and,
    once the sheet's Dim reaches every word style, a P10 case for a Karaoke
    page laid on two lines as its pager lays it, which nothing here timed.
    (Phase 2 did all of it. The Karaoke case was built on 2026-10-05 in Low
    Power Mode and first timed in a judged power state on 2026-10-06: "What
    Karaoke's two-line page costs", in the phase 2 record below.)
- **Issue batch B86 phase 2 (2026-10-05, #96; spec §11 W-15):**
  - App: `CaptionLooks.swift` (the value, the live rule, `styleList`, the
    keys, `CaptionStyle.wordStyle(_:)`); `CaptionStyle.textProps` /
    `pagePatch` and `CaptionLayout.place` take `looks:`;
    `TranscribeSheetController+Looks.swift` (the row, `looks`,
    `lookChanged`, `refreshLooksRow`, the note); `+Style` (`PreviewKey`'s
    looks, `previewReveals`), `+Commit`; `AgentServer+Captions.swift`'s
    `captionLooks` and `AgentCatalog+Captions.swift`'s three properties. No
    core, FFI, op or format change.
  - Proofs, as their runs printed them on 2026-10-06 (one host, on AC power,
    `pmset -g` `powermode 0` every time it was read; `tools/proof/README.md`'s
    "Issue batch B86 phase 2" has every row):
    - `word_captions_sheet_probe.swift` S10–S16 through
      `word_captions_chrome.py`: 49/49 with three new photographs. Nine
      mutants, each `MUTANT PASS`: `fill-live-everywhere`, `note-unbounded`,
      `note-any-engine`, `looks-not-remembered`, `greyed-box-counts`,
      `commit-drops-looks`, `rebuild-drops-preset`, `preview-ignores-looks`
      and the re-anchored `preview-base-size`. `note-unbounded` survived the
      day before, when S11 read the note only in a hosted window; S11 now
      also reads it on a sheet just built, before any layout, where the
      note's `preferredMaxLayoutWidth` is what makes its intrinsic size
      257.5 × 30.0 pt and not 335.5 × 15.0 pt. The line stays.
    - `word_looks_sheet_proof.py`: 9/9 on a scratch home, the stand-in's
      words. Four mutants, each `MUTANT PASS`: `looks-not-placed` (T1, T2 and
      T3 all failed), `refusals-dropped`, `tool-reads-remembered`,
      `note-never-shown`.
    - `word_looks_proof.py`, phase 1's rows on this build: 15/15, B1
      `moved: []`.
    - `words_picture_probe.py`: P17, the pill's height between two lines of
      different metrics, passes (the two pills 259 and 287 px tall, the
      plate 273 px half-way) and its mutant `plate-height-jumps` is
      `MUTANT PASS`. The whole probe, its first full run under the final
      scoring: 18/19 — P1–P9 and P11–P17 hold and P10 fails, on the median
      below.
    - `screens.py` launches under a scratch home of its own: 26 pass of 26,
      both looks, and screen 16's footnote reads "saved in ~/Movies/Reelcut
      Recordings" under it. `v3_tools.py`, the launch's other caller: 8 of 8.
    - `cloud_captions_probe.py --mutant speaker-colour-word-styles` (its
      anchor quotes `place`'s `pagePatch` call): exit 1, SP2 failed on all
      five word styles. The unmutated probe: 863/865 with SP2 passing; its
      two failures (SP3, SP4·off) are the baseline build under "Owed" (#246).
    - `make typecheck` 0 errors and 4 warnings, tsc silent; `make lint`
      clean; `make app` `BUILD SUCCEEDED`; `make test` whole, exit 0 (`core`
      1,064 passed, `graphic` 125, `mcp-proxy`'s `stdio` suite 14/14 with no
      timeout, and its seven proof steps).
  - **What Karaoke's two-line page costs, as P10 printed it** (2026-10-06,
    one host, two runs of `--only P10`, each judged: on AC power, `pmset -g`
    `powermode 0` before and after, Low Power Mode off and thermal state
    nominal before the rasters and after; an unoptimised probe build, the
    median of 20 rasters-and-uploads on a cache miss; none of the pass's own
    jobs beside them, the Mac in use by other sessions). The page is the one
    Karaoke's pager makes of a run of words with no pause: two lines at its
    own wrap width, its last word half filled, half-way into its dim. At
    1080×1920 (8 words, box 806×197) it read 1.241 ms and 1.237 ms. **At
    3840×2160 (15 words, box 3037×396) it read 8.384 ms and 8.210 ms, over
    the 8 ms budget, and P10 FAILED both runs on that one median**; the
    control run at budget 0 read 8.358 ms and the whole probe's run 8.441 ms.
    Every other scored median was
    inside: at 3840×2160 Highlight's fill with dim 7.684 ms and 7.567 ms,
    One Word's page 5.147 ms and 5.214 ms, a fill 2.772 ms and 2.781 ms, a
    glide 2.787 ms and 2.936 ms. The budget was not raised, and the draw and
    the scoring were not changed. As on the hand-made line (Known limits), it
    is the dim that costs — one transparency layer over the whole text box
    (W-14) — and it is paid on a ramp's frames only. What these readings do
    not settle: in the same four runs Highlight's line read 7.567–7.760 ms,
    where phase 1's four judged runs, on battery at `powermode 2`, read
    7.147–7.382 ms; whether Karaoke's page is inside 8 ms under phase 1's
    conditions was not measured.
  - **Owed after this phase:**
    - **The owner's decision on that median**: a cheaper draw for the dim
      (#245) or Karaoke's two-line page at 3840×2160 recorded as a known
      limit beside the hand-made line. Until then `python3
      tools/proof/words_picture_probe.py --only P10` fails by name on an
      unthrottled host.
    - The person checks CAP-6 (the sheet) and CAP-7 (the three looks on real
      speech, with each engine) in `docs/manual-checks.md`.
    - `word_captions_proof.py` and `cloud_captions_proof.py` were not run:
      each launches outside a scratch home, which this batch's limits did
      not allow. `word_looks_sheet_proof.py`'s T1–T5 cover `place` and the
      handler on a scratch home.
    - `cloud_captions_probe.py`'s two baseline builds no longer build
      against today's core, a rot older than this phase (its SP3 and SP4·off
      fail and row W's three rows are skipped by name on any run):
      the probe's source names a Settings member B46's tree does not have,
      and B46's and the WAV baseline's `AgentServer.swift` call the TCP
      exports road map 14 deleted. Each baseline needs its own tree's core
      and header, as the meter and welcome comparisons build theirs; not
      done in this phase, and tracked in #246.

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
- **On a hand-made page of large type a dim's ramp costs more than a
  frame's budget at 3840×2160** (B86 phase 1; `words_picture_probe.py` P10
  prints it and does not score it). In phase 1 P10 scored two pages in the presets'
  own styles — Highlight's line and One Word's one-word page — and judged in
  High Power each was inside its budget: a fill with a dim took a median of
  7.174 ms and 4.982 ms at 3840×2160 against 8 ms (2.435 ms and 1.553 ms at
  1080×1920 against 4 ms). A hand-made page of large type — six words on
  one line at One Word's size, 0.12 × min(w, h) where Highlight's is 0.075,
  which no preset makes and `set_text` can write — read 9.529 ms at
  3840×2160 on a dim's ramp frames against the 8 ms budget (2026-10-05, High
  Power, on battery, thermal state nominal; 3.100 ms at 1080×1920). The
  reason the dim costs this is the one transparency layer over the whole
  text box (W-14): it costs by the box. **Those two pages are one line with
  `width: nil`**, where a generated page is cut to its style's width, so
  Highlight's scored line is wider than any its pager makes. Phase 2 added
  a third scored page, Karaoke's two lines as its pager cuts them, which
  read over the 8 ms budget at 3840×2160: an open decision, not a limit
  recorded here ("Owed after this phase", above). The cost is
  paid on the frames of a ramp only — 0.1 s down and 0.1 s up per pause;
  the plateau between is one cached texture — and a fill or a glide alone
  costs what the shipped pop costs (about 1.2 ms and 2.5 ms). An earlier
  run that day in Low Power Mode read 9.268 ms on Highlight's line and
  12.043 ms on the hand-made one at 3840×2160; P10 does not judge such a
  run. Not fixed.
- **A fill follows a word's stored `end`, and the two engines store
  different ends** (issue batch B86 phase 1, spec §11 W-13). AssemblyAI's
  `end` is where the word was heard to end, so the fill keeps time with the
  voice and then stays full. The on-device engine's word ranges tile the
  audio (the 1.57 s silence stored as a 0.30 s gap, the 1.13 s one as
  0.06 s, above), so the last word before a pause is stored as lasting
  through most of it. A word therefore takes at most 0.6 s to fill
  (`WORD_FILL_MAX`, the owner's choice, a chosen number and not a measured
  one), which stops that crawl; its cost is that a word really spoken for
  longer than 0.6 s, with either engine, finishes its fill early.
- **On generated captions the dim is a page's tail, not a pause in
  mid-page** (B86 phase 1, W-13). Only a pause of 0.25 s or more dims, and
  the pager already ENDS a page at a 0.25 s pause (W-7) and takes it down at
  most 0.5 s later. So with AssemblyAI words a page that is followed by a
  pause fades for its last 0.25–0.5 s; with on-device words mostly nothing
  happens, because the stretched `end` leaves gaps under 0.25 s (0.06 s for
  the 1.13 s silence; the 1.57 s one left 0.30 s, so that page's last 0.3 s
  dims). The dim behaves as W-13 describes — down, then back before the next
  word — on a page timed by hand or by an agent. Trimming on-device word
  ends against the silence detector is not built.
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
- The not-built list (orig §7), closed by issue batch B86 (2026-10-05):
  - a sliding pill, a karaoke in-word fill and "dim during silence": BUILT
    (B86, spec §11 W-12..W-15);
  - restyling in place: STRUCK by the owner, 2026-10-05 — regenerating is
    not slow for them, and W-10 stands;
  - WebVTT inline timestamps: STRUCK by the owner, 2026-10-05 — no player
    they use shows them;
  - filler words: tracked in #92;
  - per-word confidence styling: tracked in #241;
  - AI emphasis and emoji: ruled out by W-9 (as amended by AI-6).
- Three choices shipped unconfirmed: Karaoke's two-line exception, the
  initial font set and the 80 % shrink floor. The user confirmed all three
  on 2026-09-28 (spec §11 W-11; #45 closed).
- Spec §7.7's format list still says "measured on macOS 15" and
  was not re-measured at 26. Tracked in #46.
- Stale text and small nits:
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
