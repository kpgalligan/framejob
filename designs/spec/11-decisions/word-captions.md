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
  mismatch that only an action switching `content` (or a paste payload or a
  hand-written file, which are stored whole) can produce degrades in the
  recipe: `word` becomes null and the page draws static.
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
