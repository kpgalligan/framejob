# Spec §11 — decisions: Word captions (road map 8)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **W-1 — A word caption is an ordinary text clip holding one PAGE.** Its
  words are timed inside it (`text.words`, format version 9); it is not one
  clip per word and not a new source kind. R6-1 stands and is extended:
  File ▸ Generate Captions… and `transcribe` remain the one way captions are
  made from speech, and a style is a popup and an argument, never a second
  command.
- **W-2 — `text.words` is one `{start, end}` per whitespace token of
  `content`, and the core is the one counter.** The token rule is
  `str::split_whitespace` (road map 8's W0 q4 measured it against the
  renderer's tokenizer: the COUNT agrees in every row). A non-empty `words`
  whose length differs is an **error** (§5.5's fourth answer, no undo step)
  in the rule's own words — `this text is timed word by word: 4 timings for
  5 words` — and the core never pads or drops a timing. An empty `words` is
  untimed. A content edit that changes the count sends `words: []` in the
  same patch.
- **W-3 — Word times are clip time, and they move with the content, not
  with the clip's length.** `split` gives the second half every word,
  rebased by the cut — a negative start is legal and means "already said",
  so a split is invisible — and leaves the first half's alone; a second half
  whose evaluated content has a different token count (a finished action
  switched it) stores `words: []` instead, because a half is a clip the door
  must accept again. `trim_start` rebases them by its delta, unlike actions,
  which a head trim leaves in place: a word is anchored to speech that stays
  where it is on the timeline. `roll` and `add_transition`'s handle form
  rebase them the same way. Nothing rescales them. They are snapped to the
  frame grid like every tick a patch carries, D7-3's normalization included,
  after the range check; two words may snap to one frame, and the later one
  wins it. They stay inside D7-1's envelope; starts never decrease and an
  `end` is never before its `start`.
- **W-4 — `word_style` is a closed vocabulary, and the recipe carries a
  computed answer, never the timings.** `words` is stripped from the
  recipe's description, as `animation` is. Two computed keys ride on every
  text layer: `word`, how many words have started, or null; `word_pop`,
  0..1, or null (§7.3). The text hash folds them in only when `word_style`
  is set, so an unstyled clip's hash is byte-identical whether or not it
  carries `words`. A value may be added to the vocabulary at the end, and
  never renamed.
- **W-5 — `word_style` and `animation` do not compose; `word_style` wins.**
  The recipe emits a whole reveal — `reveal` 1.0, the phase and kind null —
  when `word_style` is set. The combination is not refused: a paste landing
  a `word_style` on an animated title must not fail for a reason nobody can
  see. Whole-layer `video.motion` still composes with it.
- **W-6 — `words` is not an animation target, and `paste_attributes`
  treats it as part of `content`.** An action end patch naming `text.words`,
  a `null` included, is an **error** (§5.5's fourth answer, no undo step):
  `text.words is not an animation target`. `paste_attributes` copies text
  "but content", and the target's `words` stay with its content. A count
  mismatch that only an action switching `content` (or a hand-written file,
  which is stored whole) can produce degrades in the recipe: `word` becomes
  null and the page draws static.
- **W-7 — Pages are filled to a MEASURED width, in one Swift builder, and
  the cue builder does not change** (road map 8 §4 W-7, §5c; built by W4a,
  §10.9). `CaptionPages` fills each page greedily by
  `LayerRenderers.measuredSize` of the page as it will be placed — face,
  size, case, outline and word-style headroom — against 0.86 of the canvas
  width; a page wraps only when a lone word does not fit even at 80 % of its
  size, and Karaoke pages to two lines by design. `CaptionCues` keeps its
  five rules and Subtitles output is byte-identical. **Pauses are word gaps
  of 0.25 s or more plus sentence punctuation**: `SilenceDetector` and
  `MediaSpeech` are not consulted, because the pager is pure and
  `Transcriber.transcribe` has no cache directory to ask (W4a measured the
  pangram's two pauses breaking by punctuation alone). **Each engine's
  `lead` lives in `CaptionPages.lead(for:)`** — on-device +270 ms,
  AssemblyAI −60 ms — applied once in its normalisation and never in
  `CaptionCues`. **A page is confined to its job's span** `[start, start +
  duration)` (`Transcriber.Job.span`): `lead` and `hold` never carry a page
  past its clip, a word pushed off the end sits on the clip's last frame
  (`upper − frame`, since the core snaps to the nearest frame), and the last
  page ends by the bound, so pages of abutting clips abut at most and
  `place`'s trim pass never fires on a transcript. A shrunk page's outline
  is em × its SHRUNK size: `CaptionStyle.textProps` is the one construction
  the pager measures and the sheet previews, and `pagePatch`, built from it,
  is what `place` writes — so the committed page is the measured one (W4b
  residue, §10.10).
- **W-8 — The minimum is macOS 26, and the on-device engine is
  `SpeechTranscriber`** (road map 8 §4 W-8, §5f; built by W2, §10.6).
  `SpeechAnalyzer` + `SpeechTranscriber` replace `SFSpeechRecognizer`
  behind the unchanged `Transcriber.Job → Outcome → CaptionCues.build`
  path, over the SAME extracted 16 kHz mono WAVs. `SpeechEngine.swift` is
  the ONE new file allowed `async`/`await` (the amendment to the
  `MediaImporter` decision below), its only callers reach it through
  synchronous wrappers, and nothing else gains `async`. The one-minute
  ceiling and the TCC grant are DELETED on W0 q1's measurement: 99.81 % of
  a 613.7 s file came back in one analysis, and `authorizationStatus()`
  read `notDetermined` before and after every run. So `transcribe` loses
  its grant tier and its `truncated`/`note` keys under `apple` (a key that
  can never be true teaches a caller to read for a ceiling that no longer
  exists), and `project.yml`'s `NSSpeechRecognitionUsageDescription` is
  REMOVED: no code path asks for the grant any more, and W0 q1 ran the
  engine inside a hardened-runtime bundle without the key. The locale
  lists are ASKED for (`supportedLocales`, `installedLocales`), never
  written down, and `AssetInventory.status(forModules:)` is the only
  installed test. Every path that constructs a transcriber releases the
  locale it reserved (W0 q3: a cap of 5). **A download is a person's act,
  never a tool's** — R6-12's argument read across: the sheet's Download
  row drives `assetInstallationRequest(supporting:)` and
  `downloadAndInstall()`, while `transcribe` refuses an uninstalled locale
  by name ("a person has to install it") and never downloads. Closing the
  sheet mid-download lets the download run on in the framework.
  `DictationTranscriber` is not built until a locale asks for it.
- **W-9 — No language model chooses words.** Keyword emphasis and emoji
  insertion are left out: every styled word is styled by its position in
  time, never by its meaning (road map 8 §4 W-9).
  **Amended 2026-09-27, by AI-6 (road map 12): W-9 governs automatic
  styling, not a person's request.** No PIPELINE picks words by meaning.
  The assistant writes a caption's text or style only because the person
  asked it to in the conversation, and each such edit is an ordinary undo
  step.
- **W-10 (the core's sentence) — `set_text` can patch `case`, `words` and
  `word_style`,** because deepening D1 makes every declared key patchable.
  That is the agent's door, and it is not a promise that a hand-restyled
  page still fits: restyling is regenerating (road map 8 §4 W-10).
- **W-11 — Three style choices are confirmed as shipped** (the user,
  2026-09-28, closing #45): Karaoke is the one style that pages to two
  lines (every other style is one row); the caption faces bundled are
  Montserrat ExtraBold and Black, Anton and Bebas Neue (OFL, in
  `app/Resources/Fonts/`); and a page that does not fit shrinks no further
  than 80 % of its size (`CaptionPages.Rules.shrinkFloor`).
- **W-12 — A sliding pill, an in-word fill and a dim in a pause are three
  KEYS of `word_style`, not modes** (issue batch B86, #96; the owner,
  2026-10-05). `active_pill.glide` (a boolean, on the pill because without
  a pill nothing slides), `active_fill` (a boolean) and `pause_dim` (0 to 1:
  the page's opacity in a pause is `1 − pause_dim`). Each defaults to off,
  so a page written before them draws exactly as it did. W-4 is kept and
  not stretched: `mode` stays `highlight | build`, and the three compose
  with each other and with both modes, which three more modes could not
  say. They are appended in declaration order — `glide` after `radius`,
  `active_fill` and `pause_dim` after `upcoming_color` — and never renamed.
  **Format version 12**, with no migrate step, since each carries a serde
  default; the bump is what makes an older build refuse the file ("project
  format version 12 is newer than this build understands (version 11);
  update Reelcut to open it") rather than open it, drop the three keys on
  read and write the loss back on the next save. `pause_dim` outside 0–1
  is refused at the patch door in the rule's own words
  (`text.word_style.pause_dim must be between 0 and 1, not 2`); the two
  booleans are refused only by kind. `set_text` is the door (W-10 stands:
  nothing in the inspector writes `word_style`).
- **W-13 — The recipe carries three more computed answers, `word_glide`,
  `word_fill` and `word_dim`, and still no timing** (W-4). They ride on
  every text layer's `source` after `word_pop`, each 0..1 or null, all null
  when `word` is null, and the text hash folds all five word keys for a
  styled page and none for an unstyled one. With `w` = `word`, `n` the
  number of words, `s[i]` / `e[i]` word i's start and end (0-based) and `t`
  the clip time:
  - `word_glide` — null unless `active_pill.glide` and `w ≥ 2`. Else
    `ramp(t − s[w−1], over)`, where `over` is `min(WORD_GLIDE, s[w] −
    s[w−1])` while a next word exists (`w < n`) and `WORD_GLIDE` on the
    last. The pill comes FROM token `w − 2`, the one before the active
    token; **no second index is carried**, because the renderer can derive
    it from `word`. So the pill APPEARS on a page's first word and never
    flies in from the page before.
  - `word_fill` — null unless `active_fill` and `w ≥ 1`. Else `ramp(t −
    s[w−1], min(e[w−1] − s[w−1], WORD_FILL_MAX))`, holding 1.0 after.
    **A word takes at most `WORD_FILL_MAX`, 0.6 s, to fill** (the owner's
    choice, a chosen number, not a measured one): an on-device word's `end`
    is stretched over the silence after it — the engine's word ranges tile
    the audio; road map 8 measured a 1.57 s silence stored as a 0.30 s gap
    and a 1.13 s one as 0.06 s — so uncapped, the last word before a pause
    would crawl for over a second. The cost is accepted: a word really
    spoken for longer than 0.6 s, with either engine, finishes its fill
    early.
  - `word_dim` — null unless `pause_dim > 0`. 0.0 inside a word, and in
    any pause shorter than `WORD_DIM_GAP`, 0.25 s, so ordinary gaps between
    words do not flicker. Else, for the pause `[a, b)`: `min(ramp(t − a,
    WORD_DIM), ramp(b − t, WORD_DIM))`, where `a = e[w−1]` — with no
    down-ramp when `w = 0`, where the pause runs from clip time 0 — and
    `b = s[w]` — with no up-ramp when `w = n`, where the pause runs to the
    clip's `duration`. The value is how far INTO the dim the page is; the
    renderer multiplies it by `pause_dim`.
  `WORD_GLIDE` is 0.2 s, `WORD_DIM` 0.1 s each way; all four constants are
  `recipe_words.rs`'s, and nothing persists them. Every division is
  `recipe_text.rs`'s `ramp`, every subtraction saturates and every word is
  read by `get`, because the file reader stores `words` unchecked: an
  unsorted list or a start of `i64::MIN` answers a number in 0..1 and never
  panics. **What W-7 makes of the dim on generated captions is accepted and
  said in the sheet** (the owner's choice): the pager already ends a page at
  a 0.25 s pause and takes it down at most 0.5 s later, so there the dim is
  a page fading for its last 0.25–0.5 s, on AssemblyAI words; on-device
  words rarely carry a pause that long. It dims and comes back in mid-page
  on a page timed by hand or by an agent. W-7 is not changed.
- **W-14 — How the three are drawn** (`LayerRenderersWords.swift`). With
  `glide` not set and `word_fill` and `word_dim` null, a page draws by the
  calls it drew by before, in their order: an existing project's frames
  are byte-identical (`word_looks_proof.py` B1). **A gliding pill lies
  UNDER every word's ink**: when `active_pill.glide` is true the plate is
  filled before the base pass in every frame of the page, gliding or
  settled, so the word it is leaving is never covered and the drawing order
  does not flip when a glide ends. Its rect is the linear interpolation of
  token `w − 2`'s pill rect and the active token's at `easeOut(word_glide)`
  (`1 − (1 − u)³`) when each of the two lies on one line, and the active
  token's settled pill otherwise (a token that wraps over two lines). It is
  scaled about its own centre by the pop's scale; the active token still
  pops about its settled pill's centre. **The fill's edge is hard**, at
  `left + word_fill × (right − left)` over the active token's glyph range,
  snapped to a whole device pixel: the active colour left of it, the
  upcoming colour right of it in `highlight`, nothing right of it in
  `build`; a token on two lines fills each piece by the same fraction. At
  1 the edge is the token's own clip bound, so a full word is drawn whole
  (an outline's stroke reaches past the glyph range). It runs left to right
  in every script. **The dim is one opacity over the
  words and the pill together** (`1 − word_dim × pause_dim`, in one
  transparency layer); **the backdrop never dims**, for the reason it never
  fades with a reveal. None of the three moves a glyph or the box, so
  `layoutKey`, `frameKey` and the headroom are unchanged. All three recipe
  values and `pause_dim` are clamped to 0…1 where they are drawn, because
  `set_action_end` is lenient and text is not clamped.
  **Amended 2026-10-07, by W-16 (#245): "in one transparency layer" now
  holds only for a page with a backdrop.** On a page with none the dim is
  the text layer's opacity in the compositor and the bitmap holds none of
  it. What is seen is unchanged: one opacity over the words and the pill
  together, and a backdrop that never dims.
- **W-15 — The three looks are three checkboxes in the Generate Captions
  sheet and three booleans on `transcribe`, off unless asked for** (issue
  batch B86 phase 2, #96; the owner, 2026-10-05). Under the Style pop-up
  and above the preview, one per line with no heading: "Slide the pill",
  "Fill words as spoken", "Dim in pauses". Each is off by default and
  REMEMBERED under its own key in the sheet's defaults
  (`ReelcutCaptionSlide`, `ReelcutCaptionFill`, `ReelcutCaptionDim`; an
  absent key is off, so a build that remembered only a style opens with
  all three off), read when the row is built and written by a CLICK —
  never by Generate — and never read or written by a tool (R6-2 read
  across, as for the engine and the style). The six presets are not
  changed: a look is added to the preset's `word_style` when the page is
  placed, and with none asked for the placed page is the one it was.
  - **What is live when** is derived from the style's own `word_style`,
    never a table: Slide ⇔ the style has an `active_pill`; Fill ⇔ its
    `mode` is `build`, or its active and upcoming colours differ; Dim ⇔ it
    is a word style. Today:

    | look | key written | live with |
    |---|---|---|
    | Slide the pill (`slide`) | `active_pill.glide: true` | pill |
    | Fill words as spoken (`fill`) | `active_fill: true` | highlight, karaoke, build |
    | Dim in pauses (`dim`) | `pause_dim: 0.5` | highlight, pill, karaoke, build, one_word |

    On Pill and One Word a fill would show nothing (one colour on both
    sides of its edge), and with Subtitles nothing is live.
  - **A box that is not live is greyed, not hidden, and keeps its tick**:
    tick Slide on Pill, choose Karaoke, and the box is disabled and still
    ticked; back on Pill it is on again. While greyed it writes no default
    and commits nothing — the sheet's looks are each box ENABLED and on.
  - **Dim writes `pause_dim` 0.5, and the sheet has no depth or speed
    control.** While On this Mac is the engine and a word style is chosen —
    ticked or not — one note under the box reads "On-device words rarely
    carry a pause; this shows mostly with AssemblyAI." (W-13's last
    paragraph is why.) It is hidden with AssemblyAI and with Subtitles. At
    the sheet's small-note size it wraps to two lines, so the card is about
    two lines taller while it shows, as it is while the AssemblyAI rows
    show.
  - **`transcribe` takes `slide`, `fill` and `dim`**, booleans, each false
    by default and never what the sheet last chose. A `true` that would
    show nothing is the caller's own mistake and is refused by name, after
    the refusals of `replace` and before the scope, the style first and
    then `place`: `<name> only applies with style <the styles it is live
    with> — not <style>.` and `<name> only applies when place is true: with
    place false nothing is placed, so nothing is styled.` **An explicit
    `false` is always accepted.** That is a second rule inside one tool,
    on purpose: `replace`, `speakers`, `vocabulary` and `refresh` are
    refused whenever they are PRESENT where they cannot apply, `false`
    included, while these three are refused only when `true`. The first
    rule exists so a dropped request is never mistaken for one that was
    carried out; a `false` asks for nothing, and with three switches whose
    styles differ, refusing on presence would mostly refuse calls that
    asked for exactly what they would have got. Each description says
    which rule it follows. A placed run in which any of the three was
    given answers `looks`, the names that were on, in the order slide,
    fill, dim. The style list in each description and each refusal comes
    from one accessor over the live rule, never typed.
  - **The looks are no part of the measurement.** `CaptionPages.Request`
    does not carry them and the pager's measured page is the looks-free
    one: none of the three moves a glyph or the box (W-14), so the
    committed page is still the measured page.
  - **The preview's two frames show the fill half done and the pill
    half-way through its slide**; the dim is not previewed, and ticking it
    redraws nothing.
  - **Restyling is still regenerating** (W-10): the boxes and the booleans
    act when captions are generated, `CaptionLayout.place` stays the one
    app-side writer of `word_style`, and nothing in the inspector turns a
    look on or off for a page already placed (`set_text` is the agent's
    door, W-12).
- **W-16 — The dim is the text layer's opacity in the compositor when the
  page has no backdrop, and one transparency layer in the bitmap when it
  has one** (issue batch B86 phase 3, #245; the owner, 2026-10-07: build
  the cheaper draw rather than record Karaoke's page as a limit). It
  supersedes W-14's "in one transparency layer" for a page with no
  backdrop and changes nothing else of W-14. The layer cost by the text
  box's area on every frame of a ramp: judged on 2026-10-06 at 3840×2160,
  a fill with a dim read 7.57–7.76 ms on Highlight's line where the fill
  alone read 2.77–2.78 ms, and 8.21–8.44 ms on Karaoke's two-line page,
  over the 8 ms budget.
  - **One rule, in one place** (`LayerRenderers.wordDim(of:reveal:)`). The
    amount is `word_dim × pause_dim`, each clamped to 0…1
    (`LayerRenderers.dimAmount`), and 0 on a page that is not timed and
    styled. It is the LAYER's when `text.backdrop` is null and the
    BITMAP's otherwise. `drawText` hands `drawWords` a dim only in the
    second case; `RecipeLayer.drawnOpacity` is `opacity × (1 − amount)` in
    the first and `opacity` itself, the same bits, in every other, and the
    compositor reads it wherever it read `opacity`.
  - **No backdrop: the bitmap is the undimmed page's, byte for byte**, so
    a dim adds nothing to a raster. The compositor multiplies the finished
    bitmap's alpha by the layer's opacity once, after every colour stage,
    and the layer's shadow and reflection are drawn from the same number —
    exactly what a clip's own opacity or fade is. The words and the pill
    are both in that bitmap and nothing else is, so they still fade
    together (W-14).
  - **A backdrop: W-14's draw, unchanged** — the words and the pill in one
    transparency layer above the backdrop, which never dims. The
    compositor cannot do this one: the backdrop is in the same bitmap and
    would dim with them. Such a page still pays the layer by its box on a
    ramp's frames. No caption style writes a backdrop, so the Generate
    Captions sheet and `transcribe` never make such a page; the
    inspector's Backdrop switch, its Lower Third and Caption presets, and
    `set_text` do. A cheaper draw for it — the words and the pill first,
    one `destinationIn` multiply, the backdrop under them — was designed
    in this phase and not built: it was to be kept only at or under 5.0 ms
    at 3840×2160 and 2.5 ms at 1080×1920, and Karaoke's two-line page
    under the default backdrop read 6.359 ms and 6.341 ms at 3840×2160
    with NO dim (1.033 ms and 0.993 ms at 1080×1920; judged twice on
    2026-10-07), so no draw of the dim could meet it. With the dim that
    page read 11.289 ms and 11.227 ms, and 1.734 ms and 1.718 ms.
    `designs/adr/roadmap-08-word-captions.md`'s Known limits has it.
  - **The recipe and its hash are unchanged** (W-13): `word_dim` still
    rides on the source and still folds into the hash, so each frame of a
    ramp has its own cache key and none can be handed another's texture. A
    ramp's frames therefore still rasterize, at the undimmed page's cost.
    Leaving `word_dim` out of the hash would let them share one texture
    and would put this entry's backdrop rule in the core as well as in the
    renderer: not done.
  - **What may move, and what may not.** With `word_dim` 0 or null a frame
    is byte-identical to what it was (`word_looks_proof.py` B1, D2). A
    DIMMED frame of a page with no backdrop is not the layer's to the
    byte: the layer rounded the dimmed colour into the 8-bit bitmap, and
    the compositor multiplies in floating point. D1 and D3 hold it to the
    same picture. Preview, `render_frame` and both export passes draw a
    layer from the same uniforms, so an exported frame is the previewed
    one. A dimmed frame is as repeatable as any layer drawn below full
    opacity: it is the one multiply a clip's own opacity takes
    (`Compositor.metal`, step 9).
