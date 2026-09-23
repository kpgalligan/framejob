# Reelcut — road map 8: word captions (the social-video style)

**Status: BUILT, 2026-09-23 — every phase of §9 done.** W0, the spike, ran
complete on 2026-09-22: all seven rows of §3 measured on this host, one
sub-row (q3's no-network case) named in §10.3 as not run. W1a moved the
deployment target to macOS 26 as a pure change (§10.4); W1b gave the core
format version 9 — `text.words`, `case`, `word_style` and the recipe's
`word` / `word_pop` (§10.5); W2 moved the on-device engine to
`SpeechTranscriber` with the sheet's Download row (§10.6); W3 drew a timed
page — the fourth text routine, `case`, the bundled faces and the Content
footnote (§10.7); W4a generated word captions headless — `CaptionStyle`,
`CaptionPages`, both engines' hand-off, `place`'s style patch and replace
step, `transcribe`'s `style` and `replace` (§10.9); and W4b gave File ▸
Generate Captions… its Style popup, a preview drawn by the renderer's own
routine and the Replace checkbox with its list, so the sheet commits what
the tool commits, and closed the road map (§10.10). What is not built, and
why, is §7; what only a person can check is
`designs/reelcut-remaining.md` §4.

This document holds the research, the design, and — since W0 — the
measurements.
- Every claim about the code is a scout's reading at `71f3a8d`, given with a
  `file:line`.
- Every claim about a framework or a service was a cited document, not a
  measurement, **until §10.1**. Where §10.1 measured something this document
  had only read about, the section it names has been REWRITTEN rather than
  annotated, and §3a lists every one of them.
- §3 lists the questions only W0 could settle; §10.1 is what it answered.

The baseline the design was written against:
- schema version 8;
- `OP_NAMES` 57;
- the catalog at 77 tools;
- road maps 4–7 landed, and C1 (cloud captions) built;
- deployment target macOS 15.

**The ask (2026-09-22).** Captions are not only overlays for the hearing
impaired. Interview and talking-head videos, especially shorts and reels,
show what the speaker is saying in large, stylized text. The text sits on a
single row towards the bottom of the frame, and usually each word renders
as it is said. Reelcut should generate captions like that, from either the
on-device recogniser or AssemblyAI.

**The user's answers (2026-09-22), which this revision is built on:**

1. **Styles.** Generate Captions offers a choice of style.
2. **Pages fit a measured width.** A page is filled to the measured width of
   the text as it will render, not to a word count. A fixed count sends some
   pages past the frame's edge and leaves others mostly empty.
3. **Wrapping is a fallback.** A page may wrap onto several lines only when a
   wrap cannot be avoided.
4. **Fonts.** Some display fonts are bundled now, and more will come later.
5. **UPPERCASE** is a style property.
6. **Restyling means regenerating.** Changing the style of captions means
   generating them again.
7. **macOS 26 is the minimum.** The on-device engine becomes
   `SpeechTranscriber`: "I think that'll be easier overall."

§6 records the questions and answers verbatim in substance, and every
section below that they changed has been rewritten rather than annotated.

---

## 0. The idea, commented

### What the look actually is

Across the products that ship this look (§2), it comes down to three
independent choices:

1. **The page.** A few words, usually on one line, stay up together and are
   replaced as a unit. "One word at a time" is a page of one.
2. **Which words of the page are visible.** Either the whole page shows as
   soon as it appears ("highlight"), or its words appear as they are spoken
   and the row builds up ("build").
3. **How the word being said differs.** It can take a colour, a rounded pill
   behind it, or a brief scale "pop". Words already said may keep a colour
   (karaoke), and words not yet said may be dimmed.

Around those three sits the dressing: a heavy face, often UPPERCASE, a thick
outline or shadow, and a position in the lower middle of the frame.

### A page is filled to a width, not a count

The user's point is correct, and it is why the page builder is not a word
counter.
- The binding constraint is the **frame's width**, and the width a word
  takes depends on the face, the size, the case and the word itself.
- "3 words" is one line on a 16:9 canvas and overflows a 9:16 one.
- "WHY" and "UNDERSTANDING" are both one word.

So pages are made by **measuring**:
- Words are added to a page while the page, laid out exactly as the renderer
  will lay it out, still fits the width budget.
- The time rules can still close a page earlier: a pause, the end of a
  sentence, a speaker change, a maximum on-screen time.
- A page wraps to a second line only when one word alone cannot fit (§5c).

**The renderer's own measurement is reachable from the builder.**
`LayerRenderersText.measuredSize(for: TextProps)` is static and guarded by
its own lock (`LayerRenderersText.swift:51-69`), and it is the function the
canvas overlay already trusts for the box. The builder asks it about a
candidate page's `TextProps`. That is not an estimate of a render. It is
the render's layout, minus the pixels.

### Reelcut already has most of the parts

Both engines receive per-word timing today:
- **On device:** `SFTranscriptionSegment`s (`Transcriber.swift:397-405`).
- **AssemblyAI:** a `words` array, cached verbatim per media
  (`MediaTranscript.swift:58-67`, spec §11 R6-3).

Both engines map their words through each clip's source window into
timeline ticks. Both then **throw the timing away in one place**,
`CaptionCues.build` (`CaptionLayout.swift:341-473`), which groups words into
cues of at most two lines, 42 characters and 6 s.

The drawing side has matching pieces:
- The text renderer already tokenizes a string into words and draws them one
  at a time, with seams in the whitespace
  (`LayerRenderersText.swift:470-550`, `word_fade`).
- The recipe already re-rasterizes a text layer every frame while it
  animates, keyed by a hash the core computes (`recipe_text.rs:216-246`).

**What is missing** is exactly three things:
- (a) a place in the model for a word's time;
- (b) a core-computed "which word is being said now" in the recipe;
- (c) more than one style inside one text clip.

### Why not one text clip per word

It is the only shape that needs no schema change. The scouts found four
reasons against it:
- **It cannot show the look.** A highlighted word inside a stable row is one
  row with two styles.
- **It hits the clip cap.** `RC_MAX_CLIPS` is 4096 and counts nested clips
  too (`format.rs:141,163-170`). At about 150 words a minute, the cap is
  reached after roughly 25 minutes of speech.
- **It is quadratic in the plan.** Every clip edge is an instruction
  boundary (`evaluate.rs:512-563`).
- **It blinks.** The cue builder forces a one-frame gap between captions
  (`CaptionLayout.swift:454-456`).

### Why not a new source kind

Spec §11's R6-1 says "a caption is an ordinary text clip whichever engine
made it, laid out by the same `CaptionLayout.place`". Outline, backdrop,
shadow, motion, fonts, the inspector, burn-in on export and `.srt` export
all come with a text clip for free.

### The shape: one page, one text clip

A word caption is an ordinary text clip holding one PAGE, with three new
text properties:
- **`words`**: when each word of `content` is spoken, in clip time.
- **`word_style`**: what the page does with that timing, as a closed
  vocabulary.
- **`case`**: UPPERCASE as a rendering property.

The core computes the per-frame answer ("three words have started; the third
began 40 ms ago") into the recipe, and the platform draws it, the way
`reveal` works today. Ten minutes of speech at a typical 3–5 words a page
comes to 300–500 clips, well under the cap.

### Restyling is regenerating

This is the user's answer to §6 question 3, and it is also the design's
largest simplification.
- A page's breaks were measured against one face, size and case. A restyle
  that changes any of those can push a page past the width, so the honest
  way to restyle is to page again.
- The cloud engine re-pages from its cached transcript with no upload and no
  key (R6-16).
- `SpeechTranscriber` re-recognizes far faster than real time (§2).

Regenerating is therefore cheap in both engines. There is no Words section in
the inspector, no Re-flow command, and subtitle-style captions stay exactly
what they are today. The ordinary text inspector still edits a word caption's
font or colour; a person who does that owns the result.

---

## 1. The decision, in one paragraph

A word caption is a text clip whose `text` carries three things:
- **`words`**: one `{start, end}` per whitespace token of `content`, in clip
  ticks.
- **`word_style`**: a closed vocabulary:
  - `mode`, highlight or build;
  - the active word's colour, pill and scale;
  - colours for the words already said and the words not yet said.
- **`case`**: as written, or UPPERCASE.

**The core owns the timing rules:**
- It validates the one-timing-per-token rule.
- It rebases the times when a split or a head trim moves where the clip's
  content starts.
- It never rescales them.
- It snaps them to the frame grid.
- It strips `words` from the recipe's description, and emits two computed
  keys, `word` and `word_pop`.

**Swift draws a fourth text routine** beside the three reveals.

**Generation keeps R6-1's single command.** File ▸ Generate Captions… and
`transcribe` gain a **Style** choice: Subtitles, or one of the word looks,
with a rendered preview. A new Swift builder, `CaptionPages`, fills each page
by the renderer's own `measuredSize` against a width budget. Pages wrap only
when a lone word cannot fit even shrunk. The unchanged `CaptionCues` keeps
making subtitles byte-identical to today.

**The deployment target moves to macOS 26.** The on-device engine becomes
`SpeechTranscriber`, reading the same extracted audio, with one new named
`async` file. That retires `SFSpeechRecognizer`, its one-minute ceiling and
its callback plumbing.

---

## 2. What the reference products and the engines do — read 2026-09-22

This section is a research agent's summary with its sources. Nothing in it
was measured here.

| Look | What's visible | How the active word is shown | Seen in |
|---|---|---|---|
| **Highlight** | the whole page | colour change; Descript also styles past and future words | CapCut "highlight current word", Descript, VEED "Colour Highlight", Remotion Word Highlight |
| **Pill / Box** | the whole page | rounded box behind the active word, sometimes sliding | VEED Box Highlight, Captions.ai "Active Word Background", Remotion Moving Pill (12 px padding, 10 px radius, 5-frame slide) |
| **Pop** | the page, or built word by word | the active word scales up briefly, often recoloured | VEED Impact Pop / Scale In, Remotion Popping Word (1.0→1.03, ≥4 frames), Submagic "Hormozi" |
| **Build** | words appear as spoken; the page clears at a break | the newest word | CapCut short blocks, VEED Reveal / Drop In |
| **One word** | one large word at a time | the word itself, often with a pop | CapCut "one word only", Premiere Pro 26.3 "Single Word" (June 2026), VEED Impact / Stomp |
| **Hormozi / Beast** | 2–5 words, 1–2 lines | pop plus a keyword colour | Submagic templates: Anton / TheBoldFont / Montserrat Black, UPPERCASE, stroke plus shadow, emoji |

Sources for the table:
- captions.ai/help/docs/captions/styles
- help.descript.com …/37469585005197
- capcutguide.com/capcut-word-by-word-captions
- veed.io/tools/add-subtitles/animated-subtitles
- docs.submagic.co/api-reference/templates
- remotion.dev/elements/captions/*
- community.adobe.com, "What's new in Premiere 26.3"

**The products page by count, by time and by width.**
- Captions.ai exposes "words per line" and "lines per page".
- Remotion's `createTikTokStyleCaptions` pages by elapsed time: once a page
  spans `combineTokensWithinMilliseconds` (the examples use 800 and
  1200 ms), the next word opens a new page. It also shrinks text to fit the
  width.
- stable-ts, by default, splits on sentence punctuation, then on a gap over
  0.5 s, then on commas once a segment reaches 50+ characters, and caps a
  segment at 70 characters.
- WhisperX leaves some words (numbers, currency) untimed, so a pager must
  tolerate a word that has no time.

None of these is the user's rule. Measured width with time breaks is
stricter than all of them, and it is what §5c builds.

**AssemblyAI's `words[]`** is `{text, start, end, confidence, speaker,
channel}` in milliseconds.
- Punctuation and casing are attached to the word ("Hi,", "dog.").
- Universal-2's claim: "the vast majority of timestamps accurate to within
  200ms" (assemblyai.com/research/universal-2).
- One third-party measurement found words landing 80–150 ms late (openscreen
  #729).
- Road map 6's q1/q2 measured our own path: word starts identical to the
  millisecond across two uploads, and no drift over an hour.

**Apple, the shipped engine (`SFSpeechRecognizer`) — the reading, then the
measurement.**
- A segment is "an utterance, which is a vocalized word or group of words".
- Timestamps are accurate only on FINAL results (an Apple engineer,
  developer.apple.com/forums/thread/785389).
- A task has a ceiling of about one minute, which the app reports as a
  truncation (`Transcriber.swift:299, 407-414`).
- It needs a TCC grant that an agent-driven app cannot obtain.
- One third-party report says it "silently never starts" on macOS 26
  (github.com/djacobs/transcribe-audio/pull/1).

**W0 q2 measured it on this host, and two of those five are wrong here.** It
starts, and it answers `isFinal` in well under real time. Over the 40 s
`talk.wav` it delivers the file as two results, each with
`speechRecognitionMetadata`, and only the second `isFinal`: that final result
holds the last 27 words of 117, with no error and no partial flag, so the
opening 31 seconds are absent from a result that calls itself final. Read
together, the two results hold the whole file (0.068 word error rate). A
collector that keeps only the final result silently loses the front; whether
the shipped delegate sink does is not measured (§5f). On the two files under
20 s it answered once and was word-perfect or nearly so. It
also ran with `authorizationStatus()` at `notDetermined`, inside an
ad-hoc-signed hardened-runtime bundle with no usage-description key. §10.1's
q2 has the texts and the counts.

**Apple, the new engine (`SpeechTranscriber`, macOS 26+) — the reading, then
the measurement.**
- `SpeechAnalyzer` runs `SpeechTranscriber` modules over audio, including a
  file.
- With the `.audioTimeRange` attribute option, each run of the result's
  `AttributedString` carries a `CMTimeRange`. WWDC25 session 277 uses this
  to highlight words as they are spoken, and third parties report one run
  per word.
- `.transcriptionConfidence` gives a confidence per run.
- It is built for long-form audio. One measurement ran it at 40–55× real
  time (the same PR).
- Its models are system assets installed through `AssetInventory`, shared
  between apps. `supportedLocales` is the authority on languages; about ten
  languages were supported at launch.
- `DictationTranscriber` is the in-framework fallback for locales or
  hardware `SpeechTranscriber` does not cover, with the same `.audioTimeRange`.
- Both are `async`-only.

**W0 q1 and q3 measured it.** One run per word is exactly what arrives, over
three files and 1 895 words: every run is one whitespace token, punctuation is
attached to its word, nothing is zero-length, and every run but the first
carries a LEADING SPACE that a caller has to trim. It ran the 10 s pangram at
151× real time, the 40 s talk at 694× and a 613 s file at 103×, with no
ceiling — the last result ends 1.1 s from the end of the ten-minute file. Its
word times land on a 0.06 s grid and the ranges TILE: each word's end is the
next word's start, so silence inside a phrase belongs to the words either
side of it rather than to a gap between them. That last fact is what rewrote
§5c and §8. Thirty locales are supported on this host and nine installed, all
English; `DictationTranscriber` was not needed for any row.

---

## 3. W0 — the spike: questions only a run can answer

W0 comes before any product code, as C0 and S0 did. Each question below is a
row with a named instrument, and its answer rewrites the section it names.
The target bump (§5g) is W0's LAST row as well as W1's first step: the spike
builds its probes against macOS 26 in a scratch copy of `project.yml`, so
nothing in the tree moves until W1.

| # | Question | Instrument | What it decides |
|---|---|---|---|
| q1 | `SpeechTranscriber` over the extracted 16 kHz WAV (`Transcriber+Extract.swift`). Is each `.audioTimeRange` run exactly one word? Does punctuation attach to the word or stand alone? Do runs ever span a pause? Are there zero-length ranges? How fast does it run on the 45 s talking head and on a 10-minute file, and is there any length ceiling? Does it need the speech-recognition TCC grant, or none, when the app is agent-driven? | A swiftc probe (macOS 26 target) with one `async` main over `SpeechAnalyzer(inputAudioFile:)`, dumping runs and timings | §5f's engine; how far the truncation machinery and the TCC check can be deleted; the word splitter in §5c |
| q2 | Is it significantly better than what ships? Compare word error against the known script of the `say` fixture, word-start agreement with AssemblyAI's cached words on the same audio (median and 95th-percentile delta), and speed, all against `SFSpeechRecognizer` on the same files. | The q1 probe plus the existing engine's raw segments; a Python diff over the three outputs | the record for the user's "if significantly better"; the decision is already made (§6 question 5), so this is evidence, not a gate |
| q3 | `AssetInventory` on this machine: which locales are installed or downloadable, what `assetInstallationRequest(supporting:)` / `downloadAndInstall()` report as progress, and what happens with no network. | The same probe | §5f's language table and the sheet's download row |
| q4 | Does Rust's `split_whitespace` agree with the renderer's `tokens(of:)` (`LayerRenderersText.swift:470-484`, Swift `Character.isWhitespace` over UTF-16) on a corpus? The corpus covers NBSP, U+2009, U+200B, ideographic space, CRLF, a combining mark after a space, emoji ZWJ sequences, CJK with no spaces, and RTL. | A probe tokenizing the corpus both ways; the counts and ranges diffed | W-2's "the core counts tokens". Any disagreement becomes a named token rule, or alternative B of §5b. |
| q5 | Can the active word be recoloured, pilled and scaled inside the FIXED layout box (`LayerRenderersText.swift:23-27`)? What headroom does a 1.15 scale and a 0.2 em pill need? What does one re-raster cost at 1080×1920 and 3840×2160? Is `measuredSize` safe and fast when called 1,000 times from the transcription queue while the compositor renders? | A throwaway routine in the offscreen harness; a timing loop; a two-thread stress over `measuredSize` | §5d's headroom rule; whether a pop fits §7.5's 8 ms budget; §5c's cost per page |
| q6 | Which bundled faces (§5a, fonts) register and resolve by PostScript name through the app bundle? Does `NSFontManager.availableMembers` list their weights (`TextPane.swift:465-513`)? Does the export's burn-in resolve them? | A probe over the fonts folder; one `render_frame` and one export with each face | the preset rows' font names |
| q7 | What does the macOS 26 bump cost? Measure the typecheck warning count (baseline 4) and any API now marked unavailable. Check the harness and probe build lines at `-target arm64-apple-macos26.0`, and `make app` at 26.0. | `make typecheck` and `make app` against a scratch `project.yml` / `Makefile` | §5g's list; the new warning baseline the root `CLAUDE.md` states |

Any row that finds the plan wrong rewrites this document before W1, as C0's
§3a did.

**All seven ran on 2026-09-22. §10.1 is the record, row by row; §3a lists what
each one changed, and the instruments are `tools/proof/words_spike/` with
their own README.** Nothing below this line in §3 is a prediction any more:
read the section a row names, which has been rewritten, and §10.1 for the
numbers behind it.

### 3a. What W0 changed in this document

| Section | Before W0 | Now | Row |
|---|---|---|---|
| Status header | designed, not built | spiked, not built; W0 complete | all |
| §2, the engines | `SpeechTranscriber` at 40–55× real time; `SFSpeechRecognizer` "silently never starts" on macOS 26 | 103–694× measured (the first full run's q1); `SFSpeechRecognizer` starts, and delivers a 40 s file as two results whose FINAL one holds only the tail — a final-only collector loses the front silently | q1, q2 |
| §4 W-2 | "`str::split_whitespace`, unless W0 q4 says otherwise" | CONFIRMED for the COUNT over 24 rows; one range disagreement named, which the count never sees | q4 |
| §4 W-3 | word times are clip time, snapped to the frame grid | unchanged, plus what the engine actually emits: a 0.06 s grid, ranges that TILE with no gaps, no zero-length and no decrease | q1 |
| §4 W-8 | the ceiling goes "if W0 q1 finds none" | no ceiling at ten minutes, no TCC grant needed at all; the deletion rests on those two | q1, q2 |
| §5a, fonts | four proposed faces | the four fetched, their sha256, version and PostScript names; `SourceSans3-Bold` does NOT round-trip | q5, q6 |
| §5b, alternative B | "only if W0 q4 finds the two tokenizers disagree" | RETIRED: the counts agree everywhere | q4 |
| §5c, normalization | step 2 splits a word with internal whitespace | that case never arises; a LEADING SPACE on every run but the first does, and trimming is load-bearing | q1 |
| §5c, `breakGap` | the gap since the previous word's END | REWRITTEN: on-device word ranges tile the audio, so a 1.57 s silence reads as a 0.30 s gap | q1 |
| §5d, headroom | `max(pill padding, (scale − 1) × line height / 2)` | REWRITTEN: horizontally per widest word, floored at 0.45 em (0.43 em measured on one page, where that rule gives 0.20 em); 0.30 em vertically | q5 |
| §5f, the TCC check | deleted "if q1 finds no TCC grant is needed" | deleted: `authorizationStatus()` stays `notDetermined` through every run, bare and bundled | q1 |
| §5f, the language table | `supportedLocales` / `installedLocales` | the measured lists, plus: constructing a transcriber RESERVES a locale, cap 5 | q3 |
| §5f, the Download row | drives `assetInstallationRequest` and shows its progress | REWRITTEN: the request is non-nil for an INSTALLED locale too, and the progress before a download is indeterminate with zero units | q3 |
| §5g | five pins, and "whatever W0 q7 measured" | measured: 0 errors, 7 warnings, three new, all one API; 37 proof files pin the old triple | q7 |
| §5h, face names | "Montserrat Black", "Anton", "Bebas Neue" | the PostScript names the registry publishes | q6 |
| §8, `breakGap` | 0.4 s | REWRITTEN with the measurement that makes 0.4 s unreachable | q1 |
| §8, `lead` | 0 ms, "set by eye" | per-engine, from a measured bias: on-device 270 ms EARLY, AssemblyAI 62 ms late | q2 |
| §8, agreement tolerance | median ≤ 60 ms, p95 ≤ 150 ms | REWRITTEN from the measurement; the old bound is not reachable | q2 |
| §8 | — | a new headroom row, from q5 | q5 |
| §10 | "Nothing yet." | §10.1 the record, §10.2 spend and deletion, §10.3 what did not run | all |

---

## 4. Decisions for spec §11 — recorded before W1's first line

### W-1 — A word caption is an ordinary text clip holding one PAGE

The page's words are timed inside it. It is not one clip per word, and not a
new source kind. R6-1 stands and is extended: File ▸ Generate Captions… and
`transcribe` remain the one way captions are made from speech, and the style
is a popup and an argument, never a second command.

### W-2 — `text.words` is one `{start, end}` per whitespace token of `content`, and the core is the one counter

- The core refuses a non-empty `words` that does not match `content`'s token
  count. It is an error (§5.5's fourth answer), no undo step, in the rule's
  own sentence ("this text is timed word by word: 4 timings for 5 words").
  (Corrected by W1b from "§5.5's third arm": spec §6 makes every `set_*`
  range failure an error; §10.5 records it.)
- It never pads or drops timings.
- An empty `words` means untimed.
- An edit to the content field that changes the count sends `words: []` in
  the same patch, so the page draws static and says so (§5e).
- **The token rule is `str::split_whitespace`.** W0 q4 measured it against a
  verbatim copy of the renderer's own `tokens(of:)`
  (`LayerRenderersText.swift:470-484`) over a 24-row corpus written to make
  them differ: NBSP, U+2009, U+200B, U+3000, U+1680, U+202F, U+2007, U+0085,
  U+2028, U+2029, the vertical tab and form feed, CRLF, a BOM, a combining
  mark after a space, an emoji ZWJ family, CJK without spaces, and Arabic and
  Hebrew with them. **The two agree on the COUNT in every row**, which is the
  only thing the core's check reads, so the rule stands as written and no
  named exception is needed.
- They disagree about one RANGE, and it is recorded rather than legislated: in
  `"a \u{0301}b"` Swift's `Character.isWhitespace` sees the space and the
  combining acute as ONE grapheme cluster and gives the second token as `b`,
  where Rust's per-`char` rule gives it as `\u{0301}b`. Two tokens either way.
  The core counts; the renderer places; neither reads the other's offsets
  (§5b), so the disagreement has nowhere to do harm — and a phase that ever
  DOES send ranges across the seam has to read this paragraph first.

### W-3 — Word times are clip time, and they move with the content, not with the clip's length

- **`split`** gives the second half the full `words`, rebased by the cut. A
  negative start is legal and means "already said", so a split is invisible.
  A second half whose evaluated content has a different token count stores
  `words: []` instead — a half is a clip the door must accept again.
- **`trim_start`** rebases them by the trim's delta. This is **unlike
  actions**, which a head trim leaves in place
  (`edit_clip_timing.rs:62-83`). A word is anchored to speech that stays
  where it is on the timeline.
- **Nothing rescales them.** A duration change that rescales actions
  (`edit_clip_timing.rs:23-29`) leaves the words alone.
- **They are snapped to the frame grid** like every tick a patch carries
  (spec §6), including under D7-3's normalization. When two words snap to one
  frame, the later one wins that frame.
- **They stay inside D7-1's envelope.**

**What the engine actually hands the model** (W0 q1, 1 895 runs over three
files). None of this changes the decision; all of it is what the checks in
§5a will meet:
- Word times arrive on a **0.06 s grid** — every start and end measured was a
  multiple of 60 ms. At 30 fps that is 1.8 frames, so snapping moves a word
  by up to half a frame and two DIFFERENT words never snap together.
- The ranges **tile**: each word's end is the next word's start exactly,
  within a result. So `start > end` and "starts that decrease" never fire on
  engine output, and the only gaps in the timeline are between results.
- **No zero-length range** appeared in any of the three files.
- The caption mapping therefore receives a monotone, non-overlapping list —
  which is what makes the rebase in `split` and `trim_start` a subtraction and
  nothing more.

### W-4 — `word_style` is a closed vocabulary, and the recipe carries a computed answer, never the timings

- `words` is stripped from the recipe's description, as `animation` is
  (`recipe_text.rs:271-281`).
- Two computed keys are emitted on every text layer, following the precedent
  of the three `reveal` keys:
  - `word`: how many words have started, or null;
  - `word_pop`: 0..1, or null.
- The text hash folds these keys in only when `word_style` is set. An
  unstyled clip's hash is therefore byte-identical whether or not it carries
  `words`.
- A value may be added to the vocabulary at the end, and never renamed.

### W-5 — `word_style` and `animation` do not compose; `word_style` wins

- The recipe emits the reveal keys as null when `word_style` is set, and the
  Reveal section of the inspector is greyed with this sentence.
- The combination is not refused: a paste landing a `word_style` on an
  animated title must not fail for a reason nobody can see.
- Whole-layer `video.motion` still composes with it.

### W-6 — `words` is not an action target, and `paste_attributes` treats it as part of `content`

- An action end patch naming `words` is an error (§5.5's fourth answer), no
  undo step, by name: `text.words is not an animation target`. (Corrected by
  W1b from "refused"; §10.5 records it.)
- `paste_attributes` copies text "but content" (`edit.rs:125`), and `words`
  goes with content.
- A count mismatch that only an action switching `content` can produce
  degrades in the recipe: `word` becomes null and the page draws static.

### W-7 — Pages are filled to a MEASURED width, in one Swift builder, and the cue builder does not change

- `CaptionPages` fills each page greedily by `LayerRenderersText.measuredSize`
  of the page as it will be placed: its face, size, case, tracking, outline
  and word-style headroom, all on one line. It fills against a budget that is
  a fraction of the canvas width (§8).
- The time rules can close a page early.
- A page wraps only when a lone word cannot fit even after shrinking to §8's
  floor.
- The builder is Swift because only the platform measures text (spec §11:
  "Measured text sizes live in a Swift cache, never in the model").
- `CaptionCues` keeps its five rules and remains "the ONLY place they live"
  (`CaptionLayout.swift:318-321`). Subtitle-style output is byte-identical to
  today, and carries no `words`.

### W-8 — The minimum is macOS 26, and the on-device engine is `SpeechTranscriber`

This amends two spec §11 decisions:
- **"`async`/`await` is allowed only in `MediaImporter`."** The spec's own
  words foresaw this: `SpeechAnalyzer` "would earn the argument again — but
  only when the deployment target moves, and then as one more named file,
  never as a general licence". The file is `SpeechEngine.swift`, and nothing
  else gains `async`.
- **"Transcription reads EXTRACTED audio … the one-minute ceiling is
  REPORTED, not chunked around."** The engine still reads the extracted
  audio. **The ceiling GOES: W0 q1 found none.** A 613.7 s file gave 172
  results and 1 755 words, the last of them ending at 612.6 s — 99.81 % of the
  file — in 5.9 s of analysis. There is nothing left for the truncation
  machinery (`Transcriber.swift:299, 407-414`) to report, and it is deleted
  with the rest of the `SFSpeechRecognizer` half.

**What W0 q2 says about the old engine's results is narrower.** Over the 40 s
`talk.wav` it delivered TWO results, both carrying
`speechRecognitionMetadata`: a first, not `isFinal`, of 87 segments, and a
final one of 26 holding the last 27 of 117 words. Accumulated, the two read at
a 0.068 word error rate; the final result alone reads at 0.77, silently. So a
collector that keeps only the final result loses three quarters of a
forty-second clip without saying so. Whether the shipped `TaskSink`
(`Transcriber.swift`), which keeps the LAST `didFinishRecognition` result, is
such a collector was NOT measured — the probe reads the result handler, not
the delegate. The deletion rests on the ceiling and the grant above, not on
this.

**No speech-recognition grant is needed.** `SFSpeechRecognizer
.authorizationStatus()` read `notDetermined` before and after every
`SpeechTranscriber` run in q1, as a bare Mach-O and inside an ad-hoc-signed
hardened-runtime bundle carrying NO `NSSpeechRecognitionUsageDescription`, and
every one of those runs returned a full transcript. `requestAuthorization` was
never called. The authorization check in `Transcriber.swift` therefore goes
with the rest of that half — and so, for the on-device engine, does the reason
`project.yml`'s usage-description key exists (§5f).

`DictationTranscriber` is used only where `SpeechTranscriber` has no model for
the chosen locale; W0 q1–q3 did not need it on this host, so nothing about it
is built until a locale asks. `SFSpeechRecognizer` is deleted rather than kept
as a third path.

### W-9 — No language model chooses words

Keyword emphasis and emoji are left out (§7). Every styled word is styled by
its position in time, never by its meaning.

### W-10 — Restyling is regenerating

- No inspector section edits `word_style`.
- There is no re-page command.
- A caption track is restyled by running Generate Captions again with
  another style. The sheet's "Replace the existing word captions" choice
  (§5e) makes that one step.
- `set_text` can still patch any of the three keys, because deepening D1 makes
  every declared key patchable. That is the agent's door, and it is not a
  promise that a hand-restyled page still fits.

---

## 5. The design

### 5a. The model — format version 9

New module `core/src/model_words.rs`, under the 400-line cap, re-exported
through `model_props.rs` the way `model_text.rs` is:

```jsonc
"text": {
  "content": "so here's the thing",
  // … every v8 key, unchanged …
  "case": "as_written",            // NEW: "as_written" | "upper"
  "words": [                        // NEW: [] = untimed; else one per token
    {"start": 0,      "end": 108000},
    {"start": 120000, "end": 276000},
    {"start": 288000, "end": 348000},
    {"start": 360000, "end": 618000}
  ],
  "word_style": null | {            // NEW
    "mode": "highlight",            // "highlight" | "build"
    "active_color": [1, 0.85, 0, 1] | null,   // null = the text's own color
    "active_scale": 1.0,            // 1.0 … 1.5; where the pop settles
    "active_pill": null | {"color": [...], "padding": 0.18, "radius": 0.25},
    "spoken_color": null | [...],   // words already said (karaoke)
    "upcoming_color": null | [...]  // words not yet said (highlight mode)
  }
}
```

**`case`** is a transform Swift applies before layout.
- It is part of the layout key, because it changes the measured width.
- It never changes the token count.
- Titles get it too, through the ordinary inspector's Style section. That is
  one checkbox in `TextPane.swift`, and not a Words section.

**`active_pill`**'s `padding` and `radius` are fractions of the font size.
A pill around one word should track that word's size.

**`active_scale`** is where the active word settles.
- The core's `word_pop` drives a back-out overshoot into it over a fixed
  `WORD_POP` (§8), reusing `motion.rs`'s pop curve.
- At `active_scale` 1.0, `word_pop` is null and the texture changes only at
  word boundaries.

**The format bump.** All three keys are serde-defaulted, so the bump needs no
migrate step. It still bumps both `format.rs:135` and the header, because an
older build would drop the keys and save the loss. The bump adds:
- `core/tests/schema_v9.rs`;
- a walk forward of the "one past the current" fixtures in `schema_v3.rs`,
  `model_tests.rs` and `tools/proof/phase9_proof.py`.

**`check_text`** (`props_check.rs`) refuses:
- a `words` count that does not match `content`'s token count (W-2);
- `start > end`;
- starts that decrease;
- times outside D7-1's envelope;
- `active_scale` outside 1.0…1.5;
- a negative pill padding or radius.

**Fonts.** A first set of OFL display faces goes in
`app/Resources/Fonts/`, each with its licence file beside the ones already
there. **W0 q6 fetched them, checked the licences, registered them and
photographed them; all four resolve, and they are named here by the
PostScript name the registry publishes** (§10.1's q6 has the URLs, the
sha256s and the sizes):

| File | PostScript name | Family | `name` version |
|---|---|---|---|
| `Montserrat-ExtraBold.ttf` | `Montserrat-ExtraBold` | Montserrat | Version 9.000; ttfautohint (v1.8.4.7-5d5b) |
| `Montserrat-Black.ttf` | `Montserrat-Black` | Montserrat | Version 9.000; ttfautohint (v1.8.4.7-5d5b) |
| `Anton-Regular.ttf` | `Anton-Regular` | Anton | Version 2.116; ttfautohint (v1.8.3) |
| `BebasNeue-Regular.ttf` | `BebasNeue-Regular` | Bebas Neue | Version 2.000 |

Each licence file carries "SIL Open Font License, Version 1.1" verbatim, so
all four may be redistributed in this tree; the three `OFL-<Family>.txt` files
follow the naming already in `app/Resources/Fonts/`.

Source Sans 3 stays the default face. The set covers the three heavy
silhouettes §2's products use: geometric, condensed, and all-caps display.
More are added later in the same folder and need no code.

**A face is named by the string that round-trips, and W0 found one in the
tree that does not.** `CTFontCreateWithName` never answers nil
(`LayerRenderersText.swift:124`), so a name it cannot match comes back as
Helvetica with no diagnostic. q5 asked for the Title preset's own face,
`SourceSans3-Bold` (`TextPane.swift:446`), and got back a font whose
`CTFontCopyPostScriptName` is **`SourceSans3-Roman_Bold`** — the right family
and the right weight under another name, because `SourceSans3.ttf` is a
VARIABLE font and that is what its named instance is called. It is not the
fallback (the control name `NoSuchFont-Black` resolves to Helvetica, and the
measured widths differ), so nothing renders wrongly today. But it means a
`font` string cannot be assumed to be the name the registry will give back,
and W3 checks each of §5h's faces the way q5 does: ask, then compare
`CTFontCopyPostScriptName` to what was asked, and to what an invented name
resolves to.

### 5b. The recipe — `core/src/recipe_words.rs` (new)

`text_source` (`recipe_text.rs:268-311`) calls `Words::of(&text, clip_t)`
beside `Reveal::of`. It computes two keys:
- **`word`**: the count of words whose `start ≤ clip_t`, from 0 to n. It is
  null with no `word_style`, with empty `words`, or on a W-6 mismatch.
- **`word_pop`**: `min(1, (clip_t − start[word−1]) / WORD_POP)`. It is null
  when `word` is null or 0, or when `active_scale` is 1.0.

The renderer derives the rest from `word`:
- the active word is token `word − 1`;
- spoken words are the tokens before it;
- upcoming words are the tokens from `word` on, which build mode hides.

`end` is not consulted. The active word holds until the next word starts, and
a real pause is a page break (§5c). `end` is stored because the pager needs
gaps, and so that a later "dim during silence" is a recipe change, not a
schema change.

**The hash.** When `word_style` is set, `text_hash` keys the description,
the reveal, and `word` / `word_pop`. Otherwise it keys exactly what it keys
today. A page therefore re-rasterizes for `WORD_POP` after each word start,
then hits the cache. The 64-entry LRU (`LayerRenderers.swift:40`) serves a
scrub back across a page from cache.

**Alternative B is RETIRED.** It would have had the recipe carry each token's
UTF-16 range, computed by the core, and it existed only for the case where the
two tokenizers disagree. W0 q4 measured them over 24 rows and they agree on
the token COUNT in every one (§4's W-2), which is the only number that crosses
the seam. The recipe carries `word` and `word_pop` and no offsets, and the
renderer keeps placing tokens with its own `tokens(of:)`.

q4 also turned up a fact about the INSTRUMENT that a later phase should not
re-discover: `JSONSerialization` DROPS a leading U+FEFF from a decoded string,
so the Swift half of that one corpus row received seven UTF-16 units where
Rust and Python received eight. The spike records that as a transport
difference and not a tokenizer difference, because the two halves did not see
the same string; anything that ships a corpus through JSON has the same hole.

**`recipe.rs`** (582) does not grow.

### 5c. Making pages — `app/Sources/CaptionPages.swift` (new)

```swift
enum CaptionPages {
    struct Rules { widthBudget, shrinkFloor, maxLength, breakGap,
                   breakAfterSentence, breakAfterClause, hold, lead,
                   maxWords /* nil for every style but One Word */ }
    static func build(from words: [CaptionCues.Word], frame: Ticks,
                      look: CaptionStyle, canvas: CGSize,
                      clip: Int) -> [CaptionLayout.Cue]   // cues WITH words
}
```

**Normalization, once** — and step 1 is the load-bearing one, which W0 q1 is
why:
1. **Trim each word and drop the empties.** Every `SpeechTranscriber` run but
   the very first arrives with a LEADING SPACE (1 754 of 1 755 runs over the
   ten-minute file). Untrimmed, `" quick"` is still one `split_whitespace`
   token, so the core's count would pass — and the page's measured width, its
   `CTLine` offsets and every seam in §5d would all be off by a space.
2. **A word with internal whitespace never arrived**, over 1 895 runs of three
   files: every run was exactly one whitespace token. The splitting step stays
   as a one-line guard because the cloud engine is a different source, but it
   is not a case the on-device engine produces and it is not where the effort
   goes.
3. Shift every time by `lead` (§8), which is now PER ENGINE and not zero.

**The width test.** The budget is `widthBudget × canvas.width` (§8).
- A candidate page is the style's `TextProps`: its face, size, case,
  tracking, outline and `word_style`, whose headroom enters the inset (§5d),
  with `width: nil` so the page lays out on one line, and the candidate words
  as `content`.
- It fits when `LayerRenderersText.measuredSize(for:)` is at most the budget.
  This is the same function and the same cache the renderer and the canvas
  overlay use.
- The measured width includes the outline and the pop/pill headroom, so a
  page that fits the test is a page whose ink fits the frame.

**The pager, in word order:**
1. Close the current page before a word when any of these holds:
   - the speaker changes (the cue builder's rule,
     `CaptionLayout.swift:415-422`);
   - the gap since the previous word's end is at least `breakGap` — **which on
     the on-device engine is almost never true, and §8 says what to do about
     it**;
   - the previous word ends a sentence (`.?!…`);
   - adding the word would pass `maxLength`, measured to the word's end;
   - the page already holds `maxWords`, which only One Word sets;
   - **the page with the word added no longer fits the budget.**
2. After a break made ONLY by width, **balance the pair**. If moving the
   closed page's last word onto the new page would leave both fitting, and
   would bring their measured widths closer, move it. This runs once, not
   recursively. It is what stops a sentence ending on a one-word orphan page
   while keeping every page within the budget.
3. Where the previous word ends a clause (`,;:`), prefer a break there:
   - A width break that lands within two words after a clause mark moves
     back to the mark, if the page before the mark is at least half the
     budget.
   - Reading groups follow the sentence's own pauses when the width allows
     it.

**A lone word that does not fit** gets two steps, in order:
1. The page's `size` shrinks, in 5% steps, until it fits or reaches
   `shrinkFloor` of the style's size (§8). This is what Remotion's caption
   elements do.
2. Still over: the page gets `width = budget`, and CoreText wraps it. That
   splits within the word only if the word is wider than the budget at the
   floor, which at these sizes means a URL or a compound.

Multi-word pages never wrap. The width test guarantees it.

**Page timing:**
- A page starts at its first word's start.
- It ends at `min(nextPage.start, lastWord.end + hold)`.
- When the gap to the next page is under `breakGap`, the end extends to the
  next page's start, so the row never blinks. That is `CaptionCues`'
  one-frame gap deliberately NOT applied, and the builder's first paragraph
  says so.

**The words ride in the cue.** `CaptionLayout.Cue` gains `words: [Word]?`,
which is nil from the importer and from `CaptionCues`. `place` writes them in
clip time into the `text` patch it already builds. Along with them it writes:
- the style's `word_style`, `case`, face and size;
- any shrunk size;
- the placement.

**The engines' hand-off.** Both engines call `CaptionPages.build` or
`CaptionCues.build` according to the style, at the two places the words are
dropped today:
- `CloudTranscriber.swift:295-306`;
- the new on-device engine's equivalent of `Transcriber.swift:397-405`
  (§5f).

`Transcriber.Outcome` does not grow, because the words ride inside the cues.

**The gap a pause leaves, MEASURED (W0 q1) — this is the rule's real
problem.** `SpeechTranscriber`'s word ranges TILE the audio: each word's end
is the next word's start, so a silence inside a phrase is swallowed by the
words either side of it rather than left as a gap between them. Over the
pangram fixture, whose two `[[slnc]]` silences measure 1.57 s and 1.13 s from
the WAV itself:

| Truth pause | Its length | The gap `breakGap` would see | Lost |
|---|---|---|---|
| 2.72–4.29 s | 1.57 s | **0.30 s** | 1.27 s |
| 6.68–7.81 s | 1.13 s | **0.06 s** | 1.07 s |

The word before the first pause (`dog.`, 2.34–2.88 s) runs 0.16 s into it and
the word after (`Pack`) starts at 3.18 s, 1.11 s BEFORE the pause ends; at the
second pause `jugs.` runs 0.16 s in and `How` starts 0.91 s before its end.
Across the whole 10.4 s pangram the
largest gap between any two words is 0.30 s, and across the 40.1 s talk it is
0.36 s — **so §8's `breakGap` of 0.4 s would find not one break in either
file.** Only the 0.8 s of DIGITAL silence stitched between the copies of
`ten.wav` produced gaps over 0.4 s (10 of them, the largest 0.96 s).

Three things follow, and W4 owns them:
- `breakGap` cannot be read off word ENDS at 0.4 s. §8 gives it a measured
  default instead.
- Sentence punctuation is the reliable break on this engine — it is attached
  to its word (`dog.`, `2026.`, `works.`) and arrived on every sentence in
  q1's three files.
- A pause the LISTENER hears is in the audio, not in the timings. The
  detector road map 4 built (`SilenceDetector`, `MediaSpeech`) already knows
  where the silences are, and a pager that wants real pauses asks it rather
  than differencing word ends. That is a W4 decision, not a W0 one, and it is
  recorded here so W4 does not re-measure it.

**Cost, MEASURED (W0 q5).** The builder measures once per candidate, about 1.3
calls per word with the balance step; a 10-minute talking head makes about
2 000 calls. A thousand `LayerRenderersText.measuredSize` calls over 841
DISTINCT candidate pages took **16.6 ms on a cold cache** and 13.9 ms warm —
about 17 µs a call — so the whole pager costs well under a twentieth of a
second. Run on a second thread while the compositor rendered 200 frames
through the same lock, every one of the thousand answers was identical to the
single-threaded pass. The size cache empties wholesale past `cacheLimit * 4`
= 256 entries (`LayerRenderersText.swift:62`), which those 841 keys do three
times; nothing about the answers changed across a flush.

### 5d. Drawing — a fourth text routine

**The toll comes first.** `LayerRenderersText.swift` is at 577, so its
three reveal routines move to `LayerRenderersReveal.swift` as a pure move,
landed and gated alone. The new routine goes in `LayerRenderersWords.swift`,
under 400 lines.

**The routine:**
1. Lay out the full text once, exactly as today, with `case` applied first.
   The box never depends on which word is active.
2. Draw the tokens in one base pass:
   - build mode skips upcoming tokens;
   - highlight mode draws them in `upcoming_color`, when set;
   - spoken tokens take `spoken_color`, when set.
3. Draw the active token last:
   - its pill first: a rounded rect from `CTLineGetOffsetForStringIndex` plus
     the line's ascent and descent, grown by `padding × size`;
   - then the token, clip-drawn at the existing whitespace midpoints
     (`LayerRenderersText.swift:546-550`) through a second cached layout in
     `active_color`;
   - scaled about its own centre by
     `1 + (active_scale − 1) × popCurve(word_pop)`.
4. Composite fill and outline once per token through `drawFaded`'s
   transparency layer (`:378-387`).

**Headroom — REWRITTEN from W0 q5's measurement.** The rule this section
carried before the spike was
`max(pill padding, (active_scale − 1) × line height / 2)`, which at a 0.2 em
pill and a 1.15 pop gives **0.20 em**. q5 drew the routine above for every
active word of "THIS IS HOW IT LOOKS" at both canvases and measured the ink
that landed outside `measuredSize`'s box:

| Canvas | Face | Size | Worst overflow (l / r / t / b, px) | Worst, in em | As a fraction of the line |
|---|---|---|---|---|---|
| 1080×1920 | `SourceSans3-Roman_Bold` | 81 px | 25 / 31 / 20 / 22 | **0.383** | 0.269 |
| 1080×1920 | `Montserrat-Black` | 81 px | 27 / 35 / 18 / 21 | **0.432** | 0.355 |
| 3840×2160 | `SourceSans3-Roman_Bold` | 162 px | 50 / 61 / 41 / 43 | **0.377** | 0.264 |
| 3840×2160 | `Montserrat-Black` | 162 px | 54 / 70 / 38 / 40 | **0.432** | 0.355 |

The old rule is short by more than a factor of two, and it is short in the
wrong DIRECTION: the worst overflow is horizontal, at the first and last word
of the page, where the pop scales the pill about the ACTIVE WORD's own pill
centre (`tools/proof/words_spike/text_probe.swift`, the `raster` routine), so
the overflow grows with that word's width. So:

- **`textInset` grows horizontally by about `active_scale × padding +
  (active_scale − 1) × (widest word's width / 2)`**, less the outline's own
  inset, where `padding` and the word width are in em. The pager already has
  every word's width, so it computes this per page from the page's widest
  word. **0.45 em is a MEASURED bound for the measured page only** — words of
  at most five letters ("THIS IS HOW IT LOOKS"), `active_scale` 1.15,
  `padding` 0.2 — and is NOT a flat bound: an eleven-letter word, or One
  Word's pop of 1.2 (§5h), overflows past it by the formula. §8 carries 0.45 em
  as a floor a person may change, not as the rule.
- Vertically 0.30 em is enough (the worst measured was 0.27 of a line, 0.22 em
  of the size) — **for that page at 1.15 only. W3 corrected it to a FLOOR**
  under the horizontal rule's shape, with the line's ascent + descent in
  place of the widest word: at `active_scale` 1.5 the scaled pill needs
  more (§10.7).
- It stays inside `measuredSize`, so the pager's width test pays for it and
  the canvas handles show the room a pop needs.
- The box does NOT depend on which word is active: q5 measured the same box
  at every value of `word` for every face and canvas.

**Decoding.** `RecipeSourceRef.text` and `RecipeReveal` gain the two keys.
`ProjectSnapshot.swift` is on the ledger at 2516, so the decoding goes in a
new `ProjectSnapshot+Words.swift`, with one call line in the over-cap file.
`case` is decoded with the text description, one field.

**Cost of one re-raster, MEASURED (W0 q5).** Twenty
`LayerRenderers.text(_:hash:reveal:)` calls with distinct hashes, so every one
missed the texture cache:

| Canvas | Face | Median | Worst | First (cold) |
|---|---|---|---|---|
| 1080×1920 | `SourceSans3-Roman_Bold` | 0.56 ms | 11.92 ms | 11.92 ms |
| 1080×1920 | `Montserrat-Black` | 0.54 ms | 2.49 ms | 2.49 ms |
| 3840×2160 | `SourceSans3-Roman_Bold` | 1.11 ms | 1.21 ms | 1.21 ms |
| 3840×2160 | `Montserrat-Black` | 1.31 ms | 1.51 ms | 1.51 ms |

**A pop fits §7.5's 8 ms budget in steady state with room to spare** — half a
millisecond at 1080×1920 and a little over one at 4K, against a 16.7 ms frame
— and the ONE call that does not is the FIRST raster of a face in a process,
which paid 11.9 ms while CoreText brought the font in. That cost is per face
per process, not per word, and it lands on whatever frame first shows a
caption. A run of 200 renders at stepping reveal amounts on a second thread
averaged 0.70 ms while the pager measured a thousand pages on the first.

**Export and `render_frame`** read the same recipe through the same
compositor (`CompositionBuilder.swift:137`) and need nothing.

### 5e. The sheet: choosing a style

File ▸ Generate Captions… gains a **Style** row:
- **A popup** listing Subtitles, then the word styles (§5h's table).
- **A preview beside it**: a sample page ("This is how it looks", in sentence
  case so each style's own `case` shows — capitals for the four UPPER styles,
  as written for Subtitles and Karaoke — or the selection's first few words
  when a cached transcript already has them),
  drawn by the renderer's own routine at the current canvas aspect. It shows
  two frames, with the second word active in each mode. W4b read "two
  frames" as the page twice, stacked, the FIRST word active and then the
  SECOND, and Subtitles, which has no word to make active, as one frame
  (§10.10). The preview is a
  `CGImage` from the same `LayerRenderersText` code path the compositor
  uploads. **W0 q5 drew exactly that, off-Metal, into a
  `LayerRenderers.bitmap` and read its pixels back** — base pass, pill, active
  token scaled about its own centre — so the preview is reachable. It is not a
  photograph and not a mock. (q5 needed `MTLCreateSystemDefaultDevice` only
  for the `text(_:hash:reveal:)` timing loop, not for the drawing.)
- **A "Replace existing captions" checkbox**, enabled when the scope already
  holds a track this command made. Checked, the new track replaces the old
  one in the same grouped edit, one undo step. This is the whole restyle
  flow (W-10).
- **Remembered choices.** The style is remembered like the engine, under one
  defaults key. It is a display choice, so it is not part of R6-15's
  transcript marker: a cached transcript stays a cache hit whatever style is
  picked.

There is no words-per-page control. The width does that job (§0).

`TranscribeSheetController.swift` is at 540, so the row, the preview and the
checkbox live in `TranscribeSheetController+Style.swift`, following the
`+Cloud` / `+Commit` pattern. Only the grid's registration grows in the
capped file.

**How the replace step finds "a track this command made".**
- The track's name is one of `CaptionLayout`'s names ("Captions",
  "Captions 2", …).
- Every clip on the track is a text clip.
- The track holds no clip outside the scope.

The sheet lists what it will replace before the button, and nothing is
replaced that the sheet did not name.

**Editing a word caption's text** in the ordinary Content field:
- It keeps the timings when the token count is unchanged, which covers a
  typo.
- Otherwise it sends `words: []` in the same patch. The page draws static,
  and the Content section's footnote reads "Not timed — regenerate to time
  it again".

That footnote is the only word-caption chrome in the inspector (W-10).

### 5f. The on-device engine — `SpeechTranscriber`

**New file `SpeechEngine.swift`**, the one named `async` file W-8 allows.
- It takes the SAME jobs as today: `Transcriber+Jobs.swift`'s per-clip
  source windows, extracted by `Transcriber+Extract.swift` to 16 kHz mono
  WAV.
- It runs `SpeechAnalyzer` with a `SpeechTranscriber(locale:,
  transcriptionOptions: [], reportingOptions: [], attributeOptions:
  [.audioTimeRange])` over each file.
- It reads the finalized results only.
- It maps each run's `audioTimeRange` through the existing `Self.project`
  (`Transcriber.swift:452-455`) into timeline ticks.

**The boundary with the rest of the app** is a completion handler on the
serial queue that R6-7 already names. The sheet, the tool and the
cancellation token never see `async`: one `Task` inside the file bridges to
a callback. Cancellation reaches `SpeechAnalyzer` through `Task.cancel()`.

**What it replaces — and W0 q1 settled both conditionals:**
- `Transcriber.swift`'s `SFSpeechRecognizer` half: the task sink, **the
  truncation machinery (no ceiling: 99.81 % of a 613.7 s file came back), and
  the authorization check (no grant: `authorizationStatus()` read
  `notDetermined` before and after every successful run, bare and inside a
  hardened-runtime bundle with no usage-description key).**
- `Transcriber+Languages.swift`'s list, which becomes
  `SpeechTranscriber.supportedLocales` and `installedLocales`. On this host
  that is **30 supported** — `fr_FR fr_CH fr_CA fr_BE ko_KR pt_BR pt_PT
  de_AT de_CH de_DE it_IT it_CH zh_CN zh_TW es_CL es_ES es_US es_MX en_ZA
  en_CA en_SG en_IN en_NZ en_GB en_AU en_US en_IE yue_CN zh_HK ja_JP` — and
  **9 installed**, every one of them English. The list is asked for, never
  written down: W2 reads both properties and neither is a constant.

**`project.yml`'s `NSSpeechRecognitionUsageDescription` outlives the engine
that needed it.** The key exists because `SFSpeechRecognizer.h` says an app
lacking it CRASHES on `requestAuthorization` (`project.yml:61-70`), and W2
calls neither. Whether it is removed is W2's call and it is not free —
removing a usage-description string is a user-visible change to what the app
declares — but nothing after W2 reads it.

**A language whose model is not installed** gets a **Download** row in the
sheet. W0 q3 measured what that row can honestly say, and it is less than this
section assumed:
- **`AssetInventory.status(forModules:)` is the test**, and it answered
  `installed` for `en_US` and `supported` for `fr_FR`.
- **`assetInstallationRequest(supporting:)` is NOT nil for an installed
  locale.** It answered a non-nil request for `en_US` as well as for `fr_FR`,
  so "the request is nil" cannot mean "the model is here". Only `status` can.
- **The progress before a download says nothing.** The request's `Progress`
  for the uninstalled `fr_FR` reported `totalUnitCount` 0,
  `fractionCompleted` 0, `isIndeterminate` true, kind `NSProgressKindFile`.
  So the sheet's row cannot show a size or a percentage until
  `downloadAndInstall()` is running, and the MCP `transcribe`'s refusal
  **cannot name the size to download** — it names the locale and says a
  person has to install it. W0 never called `downloadAndInstall`: a download
  is a person's decision (the same argument as R6-12) and it would have
  changed host state the spike is only allowed to measure.
- **Constructing a `SpeechTranscriber` RESERVES its locale.**
  `AssetInventory.reservedLocales` was empty before the row and held
  `fr_FR` and `en_US` after it, against a `maximumReservedLocales` of **5**.
  W2 therefore releases what it reserves, or a person who transcribes in six
  languages meets a cap nobody told them about.

**`Transcriber.swift` (583) shrinks rather than pays a toll.** The engine is
new code in a new file, and the old half is deleted in the same phase. The
record gives the before and after `wc -l`.

**What survives:**
- the job list;
- the extractor;
- the `Outcome` shape;
- the cue hand-off;
- the engine popup: "On this Mac" / "AssemblyAI", one popup as before.

R6-2's "never remembered" still applies to the tool's `engine` argument.

### 5g. The macOS 26 bump

The bump is its own step, first in W1, landed and gated alone as a pure
change. It touches every place the target is pinned:
- `project.yml:5, 49, 57`: the deployment target, `MACOSX_DEPLOYMENT_TARGET`
  and `LSMinimumSystemVersion`;
- `Makefile:40`: the typecheck `-target`;
- `tools/proof/harness/build.sh:50`: the harness `-target`;
- the README's system requirements;
- spec §7.10 and wherever the spec says macOS 15.

**W0 q7 made exactly those five edits in a 25 MB rsync copy of the tree and
built it.** The copy at 15.0 reproduced the tree's own baseline first — 0
errors and 4 warnings — so what follows is the bump's cost and not the copy's:

| | At 15.0 (the control) | At 26.0 |
|---|---|---|
| `make typecheck` | 0 errors, **4 warnings**, 43.8 s | 0 errors, **7 warnings**, 43.9 s |
| `make app` | — | rc 0, **68.4 s**, the binary written |
| `harness/build.sh --force` | — | rc 0, **63.6 s**; one `harness welcome` render, rc 0 |

**The three new warnings are one API, deprecated at 26.0, in three files:**

```
Playback.swift:332          'AVMutableVideoComposition' was deprecated in macOS 26.0:
ExporterWriter.swift:676      Use AVVideoComposition.Configuration instead
CompositionBuilder.swift:131
```

No warning went away, and nothing became unavailable: zero errors at 26.0.
**The root `CLAUDE.md`'s typecheck baseline becomes "0 errors and 7
warnings"** — the four AVFoundation deprecations it already names plus these
three — and W1a is the phase that re-states it there, because this document
holds no rules. The replacement, `AVVideoComposition.Configuration`, is not
taken in W1a: the bump lands and is gated alone, and app/CLAUDE.md's
`CompositionBuilder` entry is where that work would be decided.

**W1a's other list.** `git grep -l arm64-apple-macos15.0 -- tools/proof`
answers **41 files** on this tree, **37 of them besides the READMEs** — every
probe and proof that compiles against `app/Sources` pins the triple itself
(`peaks_probe.py:111`, `cloud_spike/local_rows.py:23`, `e1_chrome.py:675` and
34 more). They are not part of the product build and the bump does not break
them, but a probe still built at 15.0 against sources that now need 26.0 will
stop compiling the moment W2 lands, so W1a walks that list.

### 5h. The styles

The rows live in `CaptionStyle.swift` (new). The Text inspector's four
`TextPreset.all` rows (`TextPane.swift:435-459`) stay as they are. A caption
style is a generation choice, not an inspector preset.

- `size` is a fraction of `min(W, H)`. For vertical video this is the height
  a line needs; the width is the pager's job.
- `y` is a fraction of H, measured to the box's centre.

**The `font` column is the PostScript name, verbatim**, because that is what
`TextProps.font` carries and what `CTFontCreateWithName` is asked for. W0 q6
measured every one of these four round-tripping through
`CTFontCopyPostScriptName` (§5a). `SourceSans3-Bold`, the Title preset's
face, is a name in the tree that W0 measured NOT round-tripping (it resolves to
`SourceSans3-Roman_Bold`, §10.1 q5), and §5a says what W3 does about it. The
Caption preset's `SourceSans3-Regular` was not asked for by any run, so
whether it round-trips is not measured.

| Style | Face (`font`), case | Colours | Active word | Page | y |
|---|---|---|---|---|---|
| **Subtitles** | today's Caption preset (`SourceSans3-Regular`) | — | — | `CaptionCues` | +0.38·H |
| **Highlight** | `Montserrat-Black`, UPPER | white, black outline 0.08 em | yellow `[1, .85, 0]`, pop 1.12 | width | +0.25·H |
| **Pill** | `Montserrat-ExtraBold`, UPPER | white | white on a violet pill, no pop | width | +0.25·H |
| **Karaoke** | `Montserrat-ExtraBold`, as written | upcoming white 0.55α; spoken and active yellow | colour only | width, up to 2 lines* | +0.28·H |
| **Build** | `Anton-Regular`, UPPER | white, black outline | yellow, pop 1.15, build mode | width | +0.25·H |
| **One Word** | `BebasNeue-Regular`, UPPER, size ×1.6 | white, black outline | pop 1.2 | `maxWords` 1 | +0.18·H |

**One number in this table is already known to be tight.** At the 0.075 size,
on a 1080×1920 canvas, "THIS IS HOW IT LOOKS" measures **1 003 px** in
`Montserrat-Black` and **805 px** in Source Sans 3 Bold (W0 q5), against §8's
budget of 0.86 × 1080 = **929 px**. So five words of that page in the
Highlight style do not fit a vertical frame and the pager closes it at four —
which is W-7 working, not a fault, and it is the first concrete evidence that
the width test is doing something a word count would not.

\*Karaoke is the one style that pages to TWO lines by design: a longer phrase
reads as a sung line. Its width test runs per line. Multi-line pages are
deliberate here and nowhere else. If the user wants Karaoke on one line
too, this footnote and one rule in §5c go.

### 5i. The MCP mirror

**`transcribe`** gains one argument:
- `style`: `"subtitles"` by default, so today's calls are unchanged. Its
  other values are `"highlight"`, `"pill"`, `"karaoke"`, `"build"` and
  `"one_word"`.

**`replace`** (bool) is the sheet's checkbox, and is refused by name without
a word style. It answers `replaced: [track ids]`.

**Each cue in the result** gains `words: [{start, end, text}]` in timeline
ticks, plus `size` when a lone word shrank. The catalog sentence "Cues are at
most two lines of 42 characters and at most 6 s"
(`AgentCatalog+Captions.swift:90-92`) gains the page rules beside it.

**The catalog stays at 77 tools.** There is no re-flow tool (W-10).
`set_text` needs no new tool: the three keys are patchable the moment
`model.rs` declares them (`edit_props.rs:17-19`), and its prose gains one
sentence per key. `ReelOps.swift`'s typed `TextPatch`
(`ReelCore.swift:1151-1164`, on the ledger) gains `case` in an extension
file; nothing app-side writes `words` or `word_style` except `place`.

**Spec mirrors:**
- §5.2 gets the three keys.
- §6 gets `set_text`'s refusal and the `split` / `trim_start` rebase.
- §7.3 gets the two computed keys and the hash rule.
- §4 gets the sheet's Style row, preview and replace checkbox.
- §7.10 gets the engine file and the target.
- §11 gets W-1…W-10.

### 5j. Export and import

- `.srt` export writes one entry per clip (`CaptionExporter.swift:189-197`),
  so a word track exports one entry per page. These are short, readable
  subtitles, and correct as they stand.
- WebVTT's inline timestamps (`Hello <00:00:01.200>world`) are §7.
- Import is unchanged.

### 5k. Files, tolls, seams

| File | Lines now | What happens |
|---|---|---|
| `project.yml` · `Makefile` · `harness/build.sh` | — | §5g, first, alone |
| `LayerRenderersText.swift` | 577 | TOLL: the reveal routines move to `LayerRenderersReveal.swift`, alone |
| `Transcriber.swift` | 583 | shrinks: its `SFSpeechRecognizer` half is deleted when `SpeechEngine.swift` lands |
| `Transcriber+Languages.swift` | 172 | rewritten over `supportedLocales` / `AssetInventory` |
| `ProjectSnapshot.swift` | 2516 (ledger) | one call line; decode in `ProjectSnapshot+Words.swift` |
| `ReelCore.swift` | 1542 (ledger) | `TextPatch.case` in an extension file; no new `rc_*` |
| `TranscribeSheetController.swift` | 540 | the row lives in `+Style.swift`; only the grid registration grows |
| `TextPane.swift` | 513 | the UPPERCASE checkbox and the Content footnote, about 20 lines |
| `CaptionLayout.swift` | 473 | `Cue.words`; `place` writes the style's patch; about 30 lines |
| `recipe.rs` · `actions.rs` · `MediaTranscript.swift` | 582 · 592 · 399 | untouched; W-6's refusal goes in `edit_action.rs` (359) |
| `recipe_text.rs` | 510 | about 15 lines: the call and the hash arm |
| `edit_split.rs` · `edit_clip_timing.rs` · `frame_grid.rs` | 195 · — · — | W-3, a few lines each |
| new: `model_words.rs`, `recipe_words.rs`, `SpeechEngine.swift`, `CaptionPages.swift`, `CaptionStyle.swift`, `LayerRenderersWords.swift`, `TranscribeSheetController+Style.swift`, `core/tests/{schema_v9,words}.rs`, `tools/proof/word_captions_proof.py` | — | each under 400 |

**No new FFI export, and the op table is unchanged (57).**

**The seam between lanes** goes into the tree first:
`core/tests/fixtures/words_v9.json`, which holds §5a's shape and §5b's recipe
keys.

### 5l. The proof — `tools/proof/word_captions_proof.py` and a pager probe

Every row is one of three things:
- a placement read back through `get_project`;
- a byte comparison of two `render_frame` PNGs;
- a recipe key read back;
- or, for the pager's arithmetic only, a **probe** compiled from
  `app/Sources` over the harness's `swiftc` line (the root `CLAUDE.md`'s
  rule for app arithmetic no script can reach).

**Model**
- A mismatch is refused with W-2's sentence, and the undo stack does not
  move.
- A `split` mid-page renders byte-identically on both sides of the cut.
- `trim_start` rebases the times, and a duration change does not rescale
  them.
- `paste_attributes` copies `word_style` and not `words`.
- An action naming `words` is refused.

**Recipe**
- `word` steps exactly at each snapped start.
- `word_pop` reaches 1 and stays there.
- An unstyled clip's hash is identical with and without `words`, checked
  against a v8 fixture.

**Picture**
- Two frames inside one word's hold, after its pop, are byte-identical.
- The frames either side of a word start differ.
- Build mode shows no ink before the first word.
- A styled page's box is the same at every value of `word`.

**Pager (the probe)**, over a fixed word list, a 1080×1920 and a 1920×1080
canvas, and every style:
- Every multi-word page measures at most the budget.
- Every page closed ONLY by width would pass the budget with its next word,
  so pages are maximal.
- No page is a lone word unless the next break was forced, or the word
  alone is at least half the budget.
- A lone over-wide word shrinks before it wraps.
- No page other than a Karaoke page, or a wrapped lone word, has two lines.
- Page N's end equals page N+1's start wherever the gap is under
  `breakGap`.
- The same word list pages differently on the two canvases, and the
  vertical canvas's pages are never wider than its budget.

**Width, the picture's side**
- A `render_frame` of every page of a generated track leaves no ink outside
  the budget's columns.
- This is the user's complaint, read off pixels.

**Generation**
- `transcribe {style:"highlight", place:false}` over a cached cloud fixture
  gives words with the pages' shape.
- Subtitle style still gives the pinned cue texts and times of
  `cloud_captions_probe.py`.
- `replace: true` replaces exactly the named track in one undo step.

**On-device**
- `transcribe {engine:"apple", style:"highlight"}` over the `say` fixture:
  word count, and word-start agreement with the fixture's known timing
  within §8's tolerance.
- A locale with no installed model is refused by name.

**Mutants**, each a tree copy with one text asserted to occur once:
- the hash arm dropped;
- the trim rebase dropped;
- the count check dropped;
- the pager's width test replaced by a 3-word count;
- the balance step dropped;
- the no-blink extension dropped.

Each must fail at least one row.

### 5m. What only a person at the machine can check

- Whether the highlight feels in sync with the voice. `lead` (§8) exists for
  that, and W0 q2 gave it a measured starting point per engine (+270 ms on
  device, −60 ms in the cloud) rather than the zero it had.
- Each style against real footage, on 9:16 and 16:9.
- Playback at 60 fps with a pop on every word.
- The model download on a Mac that has never had one. W0 q3 measured
  everything up to the download and never called `downloadAndInstall`, and
  what it found is that the progress BEFORE a download carries no size and no
  fraction — so what the Download row can show while one runs is unknown.
- What `AssetInventory` does with no network (W0 q3's one sub-row that did
  not run, §10.3).
- Whether the four bundled faces resolve on a Mac that does NOT already have
  Montserrat, Anton and Bebas Neue in `/Library/Fonts`. This one does, so
  W0 q6's pictures prove the faces DRAW and differ, not that the bundle is
  what supplied them.

Each of these has a bullet in `designs/reelcut-remaining.md` §4.

---

## 6. The user's answers, 2026-09-22

1. **Display face:** "bundle some. We'll add more later." → §5a's fonts.
2. **UPPERCASE:** "Style property." → `case`.
3. **Edits and restyling:** "If easier, restyling anything would require
   generating the captions again." → W-10. The inspector has no Words
   section, there is no Re-flow command, and a content edit that changes
   the count drops the timings.
4. **Sizing:** "The size is limited by the width … rather than a word count
   we'll need to attempt to fit words based off a width estimate … If a word
   wrap cannot be avoided, we can render a section of text on multiple
   lines, but ideally we avoid that." → W-7 and §5c. Pages are filled by the
   renderer's own measurement, not an estimate. A lone word shrinks, then
   wraps as a last resort.
5. **Target:** "macos 26 as the minimum is fine. I think that'll be easier
   overall." → W-8, §5f and §5g.

**Still open, for the user to say if they want otherwise:**
- Karaoke's two-line exception (§5h).
- The initial font set (§5a).
- The shrink floor, 80% (§8).

---

## 7. Not built, and why

- **AI keyword emphasis and emoji insertion** (W-9).
- **A sliding pill.** The pill jumps between words. A slide needs a second
  index in the recipe, and can come later as a mode value.
- **A karaoke fill within a word**, and **"dim during silence"**. Both need
  `end` in the recipe. `end` is stored, so either is a recipe change, not a
  schema change.
- **Restyling or re-paging in place** (W-10). Regenerating is the path. If
  the on-device engine turns out slow enough to matter, a per-media on-device
  transcript cache in R6-3's shape is the cure, not a re-page command.
- **WebVTT inline timestamps on export.**
- **Filler words** (`disfluencies: true`). That is a request change, and so a
  cache change under R6-15.
- **Per-word confidence styling.**

---

## 8. Numbers a person may want to change before the build

A row marked **MEASURED** came out of W0 and §10.1 has the run behind it; the
rest are still choices.

| Name | Default | Where from |
|---|---|---|
| `widthBudget` | 0.86 of the canvas width | leaves about 7% a side for platform chrome and overscan |
| `shrinkFloor` | 0.80 of the style's size | Remotion shrinks to fit; below 80% a page reads as a different style |
| `maxLength` | 3.0 s on screen | a readability ceiling; with width-fitting, time is the fallback, not the driver |
| `breakGap` | **0.25 s** | **MEASURED (q1).** The old 0.4 s came from stable-ts and Remotion, and it finds NOTHING on this engine: the largest gap between two word ranges is 0.30 s over a 10.4 s file with two real pauses in it, and 0.36 s over 40.1 s of continuous speech. 0.25 s catches the 0.30 s one and nothing inside a phrase. A pager that wants the pauses a LISTENER hears asks `SilenceDetector`, not the word ends (§5c) |
| `hold` | 0.5 s after the last word | synthesis of §2 |
| clause preference | back to a `,;:` within 2 words, page ≥ half the budget | §5c |
| `lead`, on-device | **+270 ms** | **MEASURED (q2).** `SpeechTranscriber` starts a word 270 ms EARLY against `isolated.wav`'s onset-corrected known start (signed median −270.4 ms, absolute median 271.6 ms, p95 441.9, max 504.8, over 21 matched words). Positive `lead` moves the highlight later |
| `lead`, AssemblyAI | **−60 ms** | **MEASURED (q2).** AssemblyAI runs 62 ms LATE against the same starts (signed median +61.8 ms, absolute median 61.8 ms, p95 273.0, max 313.1, 22 matched) — which is §2's cited 80–150 ms late, smaller. Both numbers are a starting point for §5m's "by eye", not a calibration |
| `WORD_POP` | 0.12 s | Remotion: at least 4 frames |
| word-style headroom | **horizontally `active_scale × padding + (active_scale − 1) × widest word / 2`, floored at 0.45 em; 0.30 em vertically — a FLOOR since W3 (§10.7), under the same shape with the line's ascent + descent** | **MEASURED (q5), for one page only.** On "THIS IS HOW IT LOOKS" (no word longer than five letters) at `active_scale` 1.15 and pill `padding` 0.2 the worst ink overflow measured was 0.432 em horizontally and 0.27 of a line vertically. The pop scales about the active word's pill centre, so a longer word or a 1.2 pop overflows more; 0.45 em is not a bound for them. §5d's pre-spike rule gave 0.20 em and was short by more than half |
| engine agreement tolerance | **median ≤ 350 ms, p95 ≤ 950 ms** | **MEASURED (q2).** The pre-spike bound was median ≤ 60 ms and p95 ≤ 150 ms, and no pair of engines came near it. `SpeechTranscriber` against AssemblyAI on matched tokens: median 98 / 168 / 314 ms and p95 914 / 610 / 500 ms over the three fixtures, worst 1 220 ms. This is a PROOF bound — "the two engines are describing the same speech" — and it is not a claim that either is accurate to a third of a second |
| style sizes | 0.075 · min(W, H); One Word ×1.6 | §5h, and see its note: five words of Highlight do not fit 1080 px wide |

---

## 9. The build's shape

Each phase is a separate `/litecode` pipeline with its own reader review, as
road map 6 was built. W1 alone bumps the format.

**Every phase below is DONE** (W0 2026-09-22 through W4b 2026-09-23; §10.1
to §10.10 the records).

- **W0 — the spike** (§3): seven rows, no product code. **RUN COMPLETE
  2026-09-22**, recorded in §10.1, with §3a listing every section it changed
  and `tools/proof/words_spike/` holding the instruments.
- **W1 — the target and the core** — **DONE: W1a §10.4, W1b §10.5:**
  - first the macOS 26 bump (§5g), landed and gated alone — **W1a**, which
    q7 has already measured end to end and which also re-states the root
    `CLAUDE.md`'s typecheck baseline (0 errors, 7 warnings) and walks the 37
    files under `tools/proof/` that pin `arm64-apple-macos15.0`;
  - then format v9: `model_words.rs`, the checks, the W-3 rebase, W-6,
    `recipe_words.rs` and the hash arm — **W1b, LANDED 2026-09-22, §10.5
    its record**;
  - tests: `schema_v9.rs` and `words.rs`;
  - spec §5.2 / §6 / §7.3 / §11;
  - proved by `make test` and by §5l's model and recipe rows
    (`tools/proof/words_core_proof.py`).
- **W2 — the on-device engine** — **DONE, §10.6:**
  - `SpeechEngine.swift`, the language and download rows, and the deletion
    of the `SFSpeechRecognizer` half;
  - proved by the on-device rows, with subtitle output unchanged in shape.
  - It is independent of W1's schema and may run beside W3.
- **W3 — the picture** — **DONE, §10.7:**
  - the `LayerRenderersText` toll first, alone;
  - then the decoding, the fourth routine, `case`, the fonts and the Content
    footnote;
  - proved by the picture rows and the offscreen harness at each value of
    `word`.
- **W4 — generation** — **DONE: W4a §10.9 (headless generation), W4b §10.10
  (the sheet's Style row, preview and Replace):**
  - `CaptionStyle`, `CaptionPages` with its probe, `Cue.words`, the two
    hand-offs, the sheet's Style row with its preview and the replace step,
    and `transcribe`'s `style` and `replace`;
  - proved by the pager, width and generation rows, and the full proof
    re-run against the final binary.

---

## 10. Record

### 10.1. W0 — the spike, run on 2026-09-22

Seven rows, all `run`, exit 0, every reservation closed. The instruments are
`tools/proof/words_spike/` and its README says how to run them again; every
number below was printed by a run and is in the CURRENT
`tools/proof/work/words_spike/answers.json`, which two runs wrote: the full
re-run after the first review wrote q1, q2, q3, q6 and q7 (the file's
`carriedForward` block names them), and a `--only q4,q5` run after it
rewrote q4 and q5. That `--only` run left the file's `fixtures` block empty
(a known artifact of `--only`), so the fixture numbers below are from
`tools/proof/work/words_spike/fixtures/fixtures.json`.

**The host.** macOS 26.5.1 (build 25F80) on an Apple M2 Max; Xcode 26.2 (build
17C52); Apple Swift 6.2.3; rustc 1.92.0; ffmpeg 8.0; Python 3.14.5.
`speech_probe.swift` was built `xcrun swiftc -O -parse-as-library -target
arm64-apple-macos26.0`; `text_probe.swift` was compiled AS `main.swift` over
every file in `app/Sources` but the app's own, module `Reelcut`, at
`-target arm64-apple-macos15.0` against `libreelcut_core.a`; `tokens.rs` with
`rustc -O`. The fixtures are `say`'s renderings, measured on this host:
`pangram.wav` 10.389 s with truth pauses at 2.72–4.29 and 6.68–7.81 s
(identical to road map 4's, to the millisecond), `talk.wav` 40.117 s of 116
synthetic words, `ten.wav` 613.748 s of `talk.wav` repeated 0.8 s apart, and
`isolated.wav` 18.759 s of the pangram's 23 words said one at a time. **`say`
publishes no word timing**, so `isolated.wav`'s known starts are its
concatenation offsets plus the onset measured in each lone rendering (the
−40 dBFS / 10 ms bucket rule, median leading silence 0.050 s), and it is an
approximation of speech rather than speech.

**Re-running a row rewrites its entry in `answers.json`, and numbers move
between runs.** Wall times move, and so does every rate read off one: the
first full run printed q1 real-time factors of 151.4×, 694.2× and 103.3×
where the re-run printed 136.0×, 680.7× and 107.3×. Counts move too: the
first full run collected 47 results before q1's cancel and the re-run 46,
and AssemblyAI's word error on `talk.wav` was 0.0427 in the first full run
and 0.0342 in the re-run. §2, §3a (its "103–694×" is the first full run's
q1), §5d, §5g and §8 still quote the FIRST full run's figures; this
section quotes the current file.

---

#### q1 — `SpeechTranscriber` over the extracted 16 kHz WAV

**Measured.**

| File | Audio | Analysis | Real time | Results | Runs |
|---|---|---|---|---|---|
| `pangram.wav` | 10.389 s | 0.076 s | **136×** | 3 | 23 |
| `talk.wav` | 40.117 s | 0.059 s | **681×** | 11 | 117 |
| `ten.wav` | 613.748 s | 5.719 s | **107×** | 172 | 1 755 |

- **Every run is exactly one whitespace token**, in all three files.
- **Punctuation is attached to its word** and never standalone: 3, 20 and 300
  runs ended in punctuation (`dog.`, `jugs.`, `2026.`, `project,`), and zero
  runs were punctuation alone.
- **Every run but the first carries a leading space**: 22 of 23, 116 of 117,
  1 754 of 1 755.
- **No zero-length or negative range**, anywhere.
- **Times land on a 0.06 s grid**, and ranges TILE: each word's end is the
  next word's start. The smallest gap between two words is 0.000 s in all
  three files; the largest is 0.30 s (pangram), 0.36 s (talk) and 0.96 s
  (`ten.wav`, where 0.8 s of digital silence separates the copies — 10 gaps
  over 0.4 s).
- **A pause is absorbed, not left.** Against the truth pauses: the 1.57 s
  silence shows as a 0.30 s inter-word gap (the word before it, `dog.`, runs
  0.16 s into the pause, and the word after, `Pack`, starts 1.11 s before the
  pause's end); the 1.13 s silence shows as 0.06 s (`jugs.` runs 0.16 s in,
  `How` starts 0.91 s before its end).
- **No ceiling.** On the 613.7 s file the last result ends at 612.6 s —
  99.81 % covered.
- **No TCC grant.** `SFSpeechRecognizer.authorizationStatus()` read
  `notDetermined` before and after every run. The same probe inside an
  ad-hoc-signed hardened-runtime bundle (`flags=0x10002(adhoc,runtime)`) with
  NO `NSSpeechRecognitionUsageDescription` returned all 23 runs and the same
  status. `requestAuthorization` was never called.
- **Cancel.** `cancelAndFinishNow()` 2 000 ms into `ten.wav` returned in
  2.14 s with 46 results and 468 words already collected.

**Verdict.** §5f **CHANGED**: both conditionals it carried are settled — the
truncation machinery and the authorization check are deleted. §4's W-8
**CONFIRMED** and strengthened. §5c **CHANGED**: the normalization's trim is
load-bearing (the leading space), the internal-whitespace split never fires,
and `breakGap` cannot be read off word ends. §8's `breakGap` **CHANGED** from
0.4 s to 0.25 s, with the reason written into the row.

---

#### q2 — is it significantly better than what ships?

Three files, three engines. `ten.wav` was NOT uploaded.

| File | Engine | WER vs the script | Words | Real time |
|---|---|---|---|---|
| `pangram.wav` (10.4 s) | `SpeechTranscriber` | 0.043 | 23 | 118× |
| | `SFSpeechRecognizer` | **0.000** | 23 | 22× |
| | AssemblyAI `universal-3-5-pro` | 0.043 | 23 | 3.7× |
| `talk.wav` (40.1 s) | `SpeechTranscriber` | 0.043 | 117 | 695× |
| | `SFSpeechRecognizer` | **0.769** | **27** | 21× |
| | AssemblyAI | 0.034 | 117 | 9.7× |
| `isolated.wav` (18.8 s) | `SpeechTranscriber` | 0.130 | 24 | 264× |
| | `SFSpeechRecognizer` | 0.130 | 22 | 26× |
| | AssemblyAI | 0.130 | 25 | 6.7× |

- **`SFSpeechRecognizer`'s FINAL result holds only the tail of a 40 s file.**
  The table's row is the final result alone: 26 segments holding the last 27
  of 117 words — "So we renamed it now we call it a reward…" — with no error
  and no truncation flag. A re-run of the probe that records EVERY callback
  (after the review) shows the file arrives as two results, both carrying
  `speechRecognitionMetadata`: the first, not `isFinal`, 87 segments from "So
  here's the thing about editing video…"; the second, `isFinal`, the 26.
  Accumulated, the 113 segments score a **0.068** word error rate (`2026` heard
  as four digits, two numerals, `weights`, one deletion). So the loss is a
  final-only COLLECTOR's, not the engine's; whether the shipped `TaskSink`
  collects that way is not measured. It ran with `authorizationStatus()` at
  `notDetermined`, inside a bundle with no usage key, in 1.81 s (1.90 s on the
  re-run). It did not "never start".
- **Almost every word error on the two clean files is a NUMERAL.** Both
  `SpeechTranscriber` and AssemblyAI wrote `5` for "five", `40` for "forty",
  `90` for "ninety", `3` for "three", `2` for "two". `SpeechTranscriber` also
  heard "weights" for "waits". On `isolated.wav` — words said one at a time,
  which is not speech — `SpeechTranscriber` heard "back" for "pack" and "uh"
  for "the" and inserted an "uh"; AssemblyAI wrote `5` for "five" and
  inserted two "uh"s.
- **Word-start agreement, `SpeechTranscriber` against AssemblyAI**, on
  matched tokens, absolute:

  | File | Matched | Median | p95 | Max | Signed median |
  |---|---|---|---|---|---|
  | `pangram.wav` | 23 | 98 ms | 914 ms | 1 220 ms | −97 ms |
  | `talk.wav` | 115 | 171 ms | 610 ms | 991 ms | −171 ms |
  | `isolated.wav` | 22 | 314 ms | 500 ms | 591 ms | −317 ms |

  The sign is consistent: **`SpeechTranscriber` starts a word earlier than
  AssemblyAI does**, which is the tiling of §10.1's q1 seen from outside.
- **Both against `isolated.wav`'s known start** (onset-corrected, with the raw
  concatenation-offset delta beside it so the synthesizer's own 0.050 s of
  leading silence stays visible):

  | Engine | Matched | Corrected median | p95 | Signed median | Raw-offset signed median |
  |---|---|---|---|---|---|
  | `SpeechTranscriber` | 21 | 271.6 ms | 441.9 ms | **−270.4 ms** | −200.7 ms |
  | AssemblyAI | 22 | 61.8 ms | 273.0 ms | **+61.8 ms** | +127.7 ms |

**Verdict.** §8's tolerance row **CHANGED** — the pre-spike bound of median
≤ 60 ms and p95 ≤ 150 ms is not reachable by any pair of engines here — and
§8 gains two `lead` rows, one per engine, from the signed medians. §2's two
engine paragraphs **CHANGED**. The user's "if significantly better" is
answered: on word error the new engine matches the cloud within a numeral or
two and matches the old engine on short files; on a forty-second file the old
engine's final result alone holds a quarter of the words (all of them only when
both of its results are read), and it is thirty times slower than the new one.

---

#### q3 — `AssetInventory` on this machine

**Measured.**
- **30 supported locales**, listed in §5f; **9 installed**, every one English
  (`en_AU en_CA en_GB en_IE en_IN en_NZ en_SG en_US en_ZA`).
- `AssetInventory.status(forModules:)` answered **`installed`** for `en_US`
  and **`supported`** for `fr_FR`, the first supported locale not installed.
- **`assetInstallationRequest(supporting:)` was non-nil for BOTH** — for the
  installed `en_US` as well as the missing `fr_FR`. Nil-ness is not a test for
  "the model is here".
- The request's `Progress` for `fr_FR`, read **before any download**:
  `totalUnitCount` 0, `fractionCompleted` 0, `isIndeterminate` true, kind
  `NSProgressKindFile`.
- **Constructing a `SpeechTranscriber` reserves its locale.**
  `reservedLocales` was `[]` before the row and `["en_US", "fr_FR"]` after it;
  `maximumReservedLocales` is **5**.
- `downloadAndInstall()` was never called.
- The **no-network case did not run** (§10.3).

**Verdict.** §5f's language table and Download row **CHANGED**: `status` is
the test, the progress before a download carries no size and no fraction, the
MCP refusal cannot name a download size, and W2 must release the locales it
reserves.

---

#### q4 — `split_whitespace` against the renderer's `tokens(of:)`

**Measured.** A 24-row corpus; the Swift side is a copy of
`LayerRenderersText.swift:470-484` asserted CHARACTER FOR CHARACTER against
the tree's before the row is believed (the control held: 15 lines, equal).

- **The token COUNT agrees in all 24 rows.**
- **One RANGE disagreement**, `combining_after_space`: for `"a \u{0301}b"`
  Swift gives `[0,1]` and `[3,4]` (the space and the combining acute are one
  grapheme cluster, and the cluster is whitespace), Rust gives `[0,1]` and
  `[2,4]` (`\u{0301}` is not whitespace and joins `b`). Two tokens either way.
- **One TRANSPORT difference**, `bom_feff`: Swift received 7 UTF-16 units
  where Rust and Python received 8, because `JSONSerialization` drops a
  leading U+FEFF. Not a tokenizer difference — the two halves did not see the
  same string — and recorded as such.
- Everything else agrees exactly, including NBSP, U+2009, U+2007, U+200B,
  U+202F, U+1680, U+3000, U+0085, U+2028, U+2029, the vertical tab, the form
  feed, CRLF, an emoji ZWJ family, CJK with no spaces, and Arabic and Hebrew
  with them.

**Verdict.** W-2 **CONFIRMED**: `str::split_whitespace` stands, with no named
exception. §5b's alternative B **RETIRED**.

---

#### q5 — the pop, the pill, the cost and the lock

**Measured.** Page "THIS IS HOW IT LOOKS", size 0.075 · min(W, H), outline
0.08 em, pill padding 0.2 em, active scale 1.15.

| Canvas | Requested face | Resolved | Box | Line | Worst overflow | In em | Render: median / worst / first |
|---|---|---|---|---|---|---|---|
| 1080×1920 | `SourceSans3-Bold` | `SourceSans3-Roman_Bold` | 805 × 129 | 115.3 px | 25 / 31 / 20 / 22 px | 0.383 | 0.54 / 11.63 / 11.63 ms |
| 1080×1920 | `Montserrat-Black` | `Montserrat-Black` | 1003 × 112 | 98.7 px | 27 / 35 / 18 / 21 px | 0.432 | 0.53 / 2.89 / 2.89 ms |
| 3840×2160 | `SourceSans3-Bold` | `SourceSans3-Roman_Bold` | 1609 × 257 | 230.7 px | 50 / 61 / 41 / 43 px | 0.377 | 1.10 / 1.38 / 1.38 ms |
| 3840×2160 | `Montserrat-Black` | `Montserrat-Black` | 2006 × 224 | 197.5 px | 54 / 70 / 38 / 40 px | 0.432 | 1.21 / 1.46 / 1.46 ms |

(overflow is left / right / top / bottom; the render column is 20 calls with
distinct hashes, so every one missed the texture cache.)

- **The box is the same at every value of the active word**, for every face
  and canvas.
- **Neither face is the system fallback.** The control name
  `NoSuchFont-Black` resolves to `Helvetica`; both measured faces resolve to
  their own family and measure differently from the control.
- **`SourceSans3-Bold` does not round-trip.** It resolves to the Source Sans 3
  family, weight Bold, under the PostScript name
  `SourceSans3-Roman_Bold` — a variable font's named instance. Recorded as a
  measurement, not a failure: it is the right glyphs, and it is why §5a now
  tells W3 to check both the round-trip and the fallback.
- **The two-thread stress held.** 1 000 `measuredSize` calls over 841 distinct
  candidate pages on one thread while 200 frames rendered through the same
  lock on another: **every answer identical** to the single-threaded pass.
  1 000 calls took 16.7 ms on a cold cache and 13.9 ms warm; the 200 renders
  took 141.7 ms (0.71 ms each). The 841 keys cross
  `cacheLimit * 4` = 256 three times, and nothing changed across a flush.

**Verdict.** §5d's headroom rule **CHANGED** — it was short by more than half
— and §8 gains a headroom row. §7.5's 8 ms budget **CONFIRMED** for steady
state, with the first raster of a face in a process named as the one call that
does not fit it. §5c's cost **CONFIRMED**: the whole pager for a ten-minute
talk is tens of milliseconds. §5a and §5h **CHANGED** to name faces by the
string that round-trips.

---

#### q6 — the bundled faces, registered, resolved and photographed

**Fetched**, each URL written out in `tools/proof/words_spike/text_rows.py`,
each answering HTTP 200:

| File | Bytes | sha256 (first 16) |
|---|---|---|
| `Montserrat-ExtraBold.ttf` | 455 468 | `d3ac6a843d3ba6d5` |
| `Montserrat-Black.ttf` | 462 844 | `ea67b37f8776eebe` |
| `Anton-Regular.ttf` | 170 812 | `a4ba3a92350ebb03` |
| `BebasNeue-Regular.ttf` | 61 400 | `08e4623805102d81` |
| `OFL-Montserrat.txt` | 4 400 | `8b7141c03fa4f8d4` |
| `OFL-Anton.txt` | 4 484 | `ee67e6ee22790b79` |
| `OFL-BebasNeue.txt` | 4 337 | `72082f6cb4d04be2` |

The Montserrat licence came from the repository ROOT
(`…/JulietaUla/Montserrat/master/OFL.txt`); `fonts/ttf/OFL.txt` is a 404. All
three licence files contain "SIL Open Font License, Version 1.1", so the four
faces are kept.

**Registered** `.process`-scope and read back: all four give the PostScript
name and family of §5a's table, `NSFont(name:)` resolves each,
`NSFontManager.availableFontFamilies` lists each family, and
`availableMembers(ofFontFamily:)` lists 18 members for Montserrat and one each
for Anton and Bebas Neue. Measured widths for the test page — 989, 1 003, 648
and 532 px — all differ from the control name's 912 px.

**Photographed** through a scratch app built at macOS 26 (q7's copy, with the
four TTFs in its own `app/Resources/Fonts` before `make app`), on port 4831,
`grep "Reelcut: "` empty before and after: a 1080×1920 project, one text clip
per face plus the CONTROL name, `render_frame` at 1 s and one `h264` export
decoded to a frame with ffmpeg.

| Face | PNG bytes | PNG sha256 | Export bytes | Frame sha256 |
|---|---|---|---|---|
| `Montserrat-ExtraBold` | 53 693 | `dd36e438e0ca` | 54 685 | `4ad955b62e60` |
| `Montserrat-Black` | 53 346 | `018b4b3db9a9` | 54 244 | `8a4639ffe228` |
| `Anton-Regular` | 50 688 | `2529290dd45e` | 51 306 | `98dc91f76602` |
| `BebasNeue-Regular` | 50 048 | `a6fea8b33786` | 42 897 | `99eab61d3439` |
| CONTROL `NoSuchFont-Black` | 54 013 | `6fe7aa4d94fb` | 59 508 | `dddd4809dc1d` |

Every face's PNG differs byte-wise from the control's and from every other
face's, and so does every decoded export frame. **The export's burn-in
resolves the faces.**

`export`'s schema does NOT enumerate its presets, so the list was asked for by
sending a name no preset has: `h264, hevc, prores_422, prores_4444, audio_m4a,
audio_wav, audio_aiff, gif, apng`. The tool also CORRECTS the extension — a
path ending `.mov` came back as `.mp4` for `h264` — so a caller reads the path
the tool answers with.

**Verdict.** §5a's font set **CONFIRMED** and §5h's face names **CHANGED** to
the measured PostScript names. **One host-state caveat, recorded in
`designs/reelcut-remaining.md` §4**: Montserrat, Anton and Bebas Neue are also
installed in `/Library/Fonts` on this Mac, so a face resolving in the app does
not by itself prove the BUNDLE is what resolved it. The registry half of the
row reads the same four faces out of the spike's own directory, which is what
the bundle would do.

---

#### q7 — what the macOS 26 bump costs

**Measured** in a 25 MB rsync copy of the tree
(`--exclude .git build tools/proof/work core/target`), with five edits and
nothing else:

```
project.yml:5    macOS: "15.0"                      → "26.0"
project.yml:49   MACOSX_DEPLOYMENT_TARGET: "15.0"   → "26.0"
project.yml:57   LSMinimumSystemVersion: "15.0"     → "26.0"
Makefile:40                  -target arm64-apple-macos15.0 → …26.0
tools/proof/harness/build.sh:50  -target arm64-apple-macos15.0 → …26.0
```

| | Control, at 15.0 | At 26.0 |
|---|---|---|
| `make typecheck` | 0 errors, 4 warnings, 45.5 s | 0 errors, **7 warnings**, 48.7 s |
| `env -u RC_ASSEMBLYAI_KEY make app` | — | **rc 0, 81.4 s**, binary written |
| `harness/build.sh --force` | — | **rc 0, 67.5 s** |
| one `harness welcome` render | — | rc 0, 1.0 s, a PNG written |

The control reproduced the tree's own baseline exactly, so the three extra
warnings are the bump's. They are one API in three files, and nothing went
away:

```
Playback.swift:332, ExporterWriter.swift:676, CompositionBuilder.swift:131
  'AVMutableVideoComposition' was deprecated in macOS 26.0:
  Use AVVideoComposition.Configuration instead
```

`git grep -l arm64-apple-macos15.0 -- tools/proof` answers **41 files**, **37
besides the READMEs** (the four README hits include the paragraph this spike
added to `tools/proof/README.md`).

**Verdict.** §5g **CONFIRMED** and filled in. **The root `CLAUDE.md`'s
typecheck baseline becomes "0 errors and 7 warnings"**, and W1a is the phase
that writes it there — this document holds no rules and does not edit that
file. W1a also walks the 37 proof files.

### 10.2. Spend and deletion

Only q2 spent anything. Fifteen paid calls across five runs of the row — the
same three synthetic fixtures each time — 355.0 s of billed audio,
**$0.0207** of the $2.00 budget in `tools/proof/work/words_spike/ledger.json`.

| Uploaded | Billed | Bytes | Outcome |
|---|---|---|---|
| `pangram.wav` ×5 | 11.0 s each | 336 532 | deleted (HTTP 200) |
| `talk.wav` ×5 | 41.0 s each | 1 287 826 | deleted (HTTP 200) |
| `isolated.wav` ×5 | 19.0 s each | 600 336 | deleted (HTTP 200) |

Every transcript created was DELETEd and every DELETE answered 200. No
reservation is open and none is `unresolved`. `ten.wav` was never uploaded.
Nothing but three of the four synthetic fixtures (`pangram.wav`,
`talk.wav`, `isolated.wav`) ever left this machine.
`--leakcheck` over the spike's directory, its work directory, this document,
`tools/proof/README.md`, `designs/reelcut-remaining.md` and the pipeline's
handoff directory printed `leakcheck: 16 secrets, 6 roots` and then `clean` —
the key plus the fifteen upload URLs the ledger recorded, none of which appears
anywhere but that ledger.

### 10.3. Not run

One SUB-row, named here and in `designs/reelcut-remaining.md` §4:

- **q3's no-network case.** `AssetInventory`'s behaviour with no network was
  NOT measured, because measuring it means changing this host's network state
  and the spike is only allowed to read host state. What the Download row does
  when the network is gone is a person's check.

One instrument residue, from the W0 residue pipeline's review (a nit, not
fixed): `speech_rows._cloud_call` records `outcome: "deleted"` whatever
the DELETE answered, so `q2_verdict` would score `run` for a transcript whose
DELETE returned a 500. The ledger shows all fifteen DELETEs answered 200, so
no recorded answer is affected; a re-run that depends on the gate should
also require the delete status. `tools/proof/words_spike/q2_gate.py` proves
the gate on recorded data (8/8, no paid call).

Every other row and sub-row ran. Nothing was skipped for a missing key: 
`RC_ASSEMBLYAI_KEY` was present, so q2 ran in full, and the on-device grant
turned out not to be needed, so q2's `SFSpeechRecognizer` half ran too.

### 10.4. W1a — the macOS 26 bump, landed 2026-09-22

The deployment target moved from macOS 15.0 to 26.0 at every pin: the five
build pins W0 q7 measured (`project.yml`'s `deploymentTarget`,
`MACOSX_DEPLOYMENT_TARGET` and `LSMinimumSystemVersion`, the `Makefile`'s
typecheck `-target`, `tools/proof/harness/build.sh`'s `-target`), the other
39 tracked files under `tools/proof/` that pinned `arm64-apple-macos15.0`, the
README's system requirements, and spec lines 20 and 2666. Nothing under
`app/Sources`, `app/Resources` or `core/` was edited; there is no format
bump and no `async`. `project.yml`'s `MTL_LANGUAGE_REVISION:
UseDeploymentTarget` was left as it was, which is why the shader recompiled
and why (f) exists. Every number below is what a run printed on this host,
Xcode's SDK 26.2; seconds are the wall clock of a bounded wrapper around the
command.

**(a) The CONTROL at 15.0, before any edit.** `make typecheck`: **0 errors,
4 warnings**, 42.8 s — the four root `CLAUDE.md` names
(`Exporter.swift:595`, `CompositionBuilder.swift:368`, `:401`, `:446`).
`env -u RC_ASSEMBLYAI_KEY make app`: **rc 0**, 4.6 s — xcodebuild found the
product on disk current against today's sources and only relinked (one `Ld`
step, no `SwiftCompile`, no `CompileMetalFile`), so the control's
`default.metallib` is the one its dependency check accepts for the current
`Compositor.metal` at 15.0. `LSMinimumSystemVersion` **15.0**; `otool -l`
`LC_BUILD_VERSION` `minos 15.0`, `sdk 26.2`. `default.metallib`: sha256
`f37bcef77b282bcd8b8b14835d2e4cad91f3435a5fc43e10677bb6a388ba7eaf`,
**81 884 bytes**.

**(b) `make typecheck` at 26.0: 0 errors, 7 warnings, 40.7 s.** Every
warning, as printed:

```
app/Sources/Playback.swift:332:47: warning: 'AVMutableVideoComposition' was deprecated in macOS 26.0: Use AVVideoComposition.Configuration instead
app/Sources/ExporterWriter.swift:676:59: warning: 'AVMutableVideoComposition' was deprecated in macOS 26.0: Use AVVideoComposition.Configuration instead
app/Sources/Exporter.swift:595:31: warning: 'copyCGImage(at:actualTime:)' was deprecated in macOS 15.0: Use generateCGImageAsynchronouslyForTime:completionHandler: instead
app/Sources/CompositionBuilder.swift:131:32: warning: 'AVMutableVideoComposition' was deprecated in macOS 26.0: Use AVVideoComposition.Configuration instead
app/Sources/CompositionBuilder.swift:368:15: warning: 'tracks(withMediaType:)' was deprecated in macOS 13.0: Use loadTracks(withMediaType:) instead
app/Sources/CompositionBuilder.swift:401:15: warning: 'timeRange' was deprecated in macOS 13.0: Use load(.timeRange) instead
app/Sources/CompositionBuilder.swift:446:62: warning: 'preferredTransform' was deprecated in macOS 13.0: Use load(.preferredTransform) instead
```

(each line ends `[#DeprecatedDeclaration]`). The three new ones are W0's
three exactly, at the same lines: `Playback.swift:332`,
`ExporterWriter.swift:676`, `CompositionBuilder.swift:131`. No difference
from W0. They are ACCEPTED (§5g); `AVVideoComposition.Configuration` was not
taken with the bump.

**(c) `env -u RC_ASSEMBLYAI_KEY make app` at 26.0: rc 0, 52.6 s** (W0's copy
measured 68.4 s; this run's build directory was warm). The binary's
`LSMinimumSystemVersion` **26.0**; `LC_BUILD_VERSION` `minos 26.0`,
`sdk 26.2`. `default.metallib`: sha256
`3a182095ad80b59d83f951f663c750399f725e4f0987a44f019d044dba96e5d9`,
**81 916 bytes** — against the control's `f37bcef7…`, 81 884 bytes: the
library changed, as `MTL_LANGUAGE_REVISION: UseDeploymentTarget` said it
would (the compile line is `metal -c -target air64-apple-macos26.0`). The
xcodebuild log's Swift warnings are the same seven. It also prints one Metal
warning, `Compositor.metal:23:14: unused variable 'kTransitionNone'
[-Wunused-const-variable]`; that one is NOT new — the same `metal -c` line
run by hand at `-target air64-apple-macos15.0` prints it too — and it is
outside `make typecheck`'s count.

**(d) `tools/proof/harness/build.sh --force`: rc 0, 62.4 s** (the script
printed "built … in 62 s"), 0 errors, the same seven Swift warnings.

**(e) `git grep -l arm64-apple-macos15.0 -- tools/proof`: 41 before, 1
after.** The remaining hit is `tools/proof/README.md:4463`, W0's record
sentence describing the line `text_probe.swift` was compiled with — a
record, not a build line. `rg -l` (which also sees the untracked
`words_spike/`) answers that file plus `words_spike/text_rows.py`,
`words_spike/scratch_rows.py` and `words_spike/README.md`, left by design
(l). The 40 files moved are `harness/build.sh` (a build pin, above), 36
other scripts and spike sources — with it, the 37 non-README files W0
counted — and the three spike READMEs (`cloud_spike`, `effects_spike`,
`silence_spike`); `reference_build.py`'s `SWIFT_TARGET` is among them (i).

**(f) The render comparison — the gate for the recompiled shader.** The
new `tools/proof/target_bump_proof.py` writes one package by hand
(format 8; canvas 640×360 at 30 fps; `A.mov` as media 20; a media clip, a
text clip and a shape clip, all spanning ticks 0–3 000 000) and renders
ticks 0, 900 000 and 1 500 000. **Deviation from the phase's spec:** the
spec put the text and shape clips on one track, fully overlapping; the
core's overlap rule (`transition.rs` `check_overlap_rule`) allows a
same-track overlap of at most half the shorter clip, and such an overlap is
a transition, so the package puts each kind on its own track (three tracks)
to have all three drawn plainly at every tick. `capture` on the CONTROL
build (port 4841, log grep empty): `t0.png` 49 126 bytes
`9536e383d74e1d3c9cf9f0ee343ac59c869ec52463dc815d8cbe9b8cb7d17cca`,
`t900000.png` 47 124 bytes
`f38c67bdbcb4ed0322588fe14a9655263c32e66cc5aa10b9cfd8a1d0b8640cc5`,
`t1500000.png` 47 579 bytes
`57c86febf366865788f5ea79dd601729e0e67cbb485718eb72f2822c05db8e4c`.
`compare` on a fresh 26.0 instance (port 4842, log grep empty): **3/3**, the
same three frames byte for byte. Made to fail on purpose: a copy of the
capture with one byte of `t900000.png` flipped, compared on a third fresh
26.0 instance (port 4843, log grep empty), scored **2/3, exit 1**, naming
both PNGs, sizes and hashes; the copy was deleted.

**(g) `op_catalog_proof.py`: 23/23** on a fresh 26.0 instance (port 4844,
log grep empty before and after), its probe cache deleted first:
"op-catalog probe: … (built in 64.6 s)".

**(h) `phase9_chrome.py`: 62/62**, its probe cache deleted first: "corner
probe: … (built in 62.9 s)".

**(i) The historical instruments, at `SWIFT_TARGET = "arm64-apple-macos26.0"`.**
`phase5_chrome.py`: **81/81**, 93.7 s — "reference: built 3187c5d7 in 48 s";
its harness line read "up to date", which is the (d) build.
`recording_probe.py --only welcome`: **29/29**, 125.3 s — "recording probe:
… (built in 63.4 s from …/app/Sources)", "reference: built c1dce5f0 in
56 s". **Decision: 26.0 kept.** Both old trees compiled at 26.0 with their
own core and header and scored as before, so the spec's fallback (restoring
15.0 in `reference_build.py`) was not needed.

**(j) `make test`: rc 0**, 51 suites, 786 passed, 0 failed. **`make lint`:
rc 0.** `cargo fmt --check` in `core/`: rc 0, no output. No Rust changed.

**(k) The app-side availability audit.** `app/Sources` has **no
`#available`** and no version-gated `@available`: 91 `@available` matches,
90 of them `@available(*, unavailable)` on `init?(coder:)`, and the 91st a
doc comment (`ScreenRecorder+Delegates.swift:28`, "nothing here needs an
`@available`"). The new minimum makes no gate dead. Two comments name
macOS 15 as a measured fact — `AgentServer+RecordingResult.swift:247` (the
recorder's arm timeout and macOS 15's periodic prompt) and
`FrameWriter.swift:77` (`CGImageDestinationCopyTypeIdentifiers()` on
macOS 15) — and are left: they say what was measured.

**(l) Residue.**
- `tools/proof/words_spike/text_rows.py:87` compiles `app/Sources` at
  `arm64-apple-macos15.0` (`words_spike/README.md:45` describes that line;
  `scratch_rows.py:39` names 15.0 as the OLD triple it moves in its rsync
  copy). It was not run here; it will stop building when W2 lands
  `SpeechTranscriber` code in `app/Sources`. That is W2's to move.
- Spec §7.7's format list (spec line 2185) was measured on macOS 15 and was
  not re-measured on 26.
- `tools/proof/work/e1-reference`'s archived `build.sh` (commit `1c3e92e`)
  pins 15.0 outside the tree; `e1_chrome.py` builds its reference from it.
- Every other probe binary cached in `tools/proof/work/` on source mtimes
  (`b6probe`, `bcprobe`, `clip-catalog-probe`, …) was built at 15.0 and stays
  so until its sources change or it is deleted; only `cornerprobe`,
  `op-catalog-probe` and `recordingprobe` were cleared and rebuilt here.
- The root `CLAUDE.md` typecheck baseline sentence ("0 errors and 4
  warnings … Any fifth warning is new") is owed by hand: it becomes 0 errors
  and 7 warnings, naming the three above.

### 10.5. W1b — the core, landed 2026-09-22

**What landed.** Format version 9 (`core/src/format.rs` and
`core/include/reelcut_core.h`): `text.case`, `text.words` and
`text.word_style`, closing the text object in that order, all
serde-defaulted, no migration step. Spec §11 gained W-1 to W-6 and W-10's
`set_text` sentence after S1-23, and D7-1's last sentence the `text.words`
clause; spec §5.2, §6 (`trim_start`, `roll`, `split`, `paste_attributes`,
`set_*`, `add_transition`, `set_action_end`), §7.3 and §7.10 mirror them, as
do `edit.rs`'s seven rows. The op table is unchanged at 57 ops: the new keys
are patch keys, and `Kind::Object` has no properties, so the parity check and
the argument gate see nothing new.

- `model_words.rs` (new, 170): the vocabulary, `token_count`
  (`split_whitespace`) and `rebase_words` (saturating).
- `check_text` (`props_check.rs`): the count rule, D7-1's envelope per word
  time (`ticks_in_envelope`), `end ≥ start`, non-decreasing starts (equal
  starts and negative starts legal), `active_scale` 1.0–1.5
  (`WORD_SCALE_MIN`/`MAX`), the three colours and the pill's colour, and a
  non-negative pill padding and radius. Every one is an `Err`.
- `patch.rs`: the text template carries one `Word` and
  `WordStyle::template()`; `COMPLETE_ENTRIES` gains `("words", ["start",
  "end"])`.
- `snap_animation` snaps every word time too, so its four callers (`set_text`,
  `add_text_clip`, `paste_attributes`, `frame_grid.rs`'s D7-3 re-snap) cover
  words with no new call site. `frame_grid.rs` was not edited.
- W-3: `rebase_words` at `trim_start` (by the delta), `roll` (by the move) and
  `add_transition`'s handle form (by −head); `split_clip` rebases the second
  half by the cut, or stores `words: []` when its evaluated content's token
  count differs; the first half is untouched.
- W-6: `set_action_end` refuses a `text` object naming `words`, a `null`
  included, as an `Err`; `paste_attributes`' `copy_group` keeps the target's
  `words` with its `content`.
- `recipe_words.rs` (new, 83): `Words::of` and `WORD_POP` (72 000 ticks).
  `text_source` emits `word` and `word_pop` on every text layer (the burn-in
  included, both null), gives a styled page `Reveal::WHOLE` (W-5), strips
  `words` from the description and keeps `word_style` only when set and
  `case` only when not `as_written`; `text_hash` folds the two keys in only
  when `word_style` is set. `recipe.rs` did not grow.

**Line counts, `wc -l` before → after** (before measured at the start of the
run, on tree `4cbdaaaa`):

| File | Before → after |
|---|---|
| `core/src/model_words.rs` | new → 170 |
| `core/src/recipe_words.rs` | new → 83 |
| `core/src/lib.rs` | 90 → 92 |
| `core/src/model_props.rs` | 445 → 454 |
| `core/src/model_text.rs` | 252 → 267 |
| `core/src/props_check.rs` | 396 → 474 |
| `core/src/patch.rs` | 414 → 427 |
| `core/src/edit_props.rs` | 376 → 388 |
| `core/src/edit_clip_timing.rs` | 170 → 177 |
| `core/src/edit_edge.rs` | 197 → 203 |
| `core/src/edit_transition.rs` | 524 → 530 |
| `core/src/edit_split.rs` | 195 → 218 |
| `core/src/edit_action.rs` | 359 → 369 |
| `core/src/edit_paste.rs` | 572 → 575 |
| `core/src/recipe_text.rs` | 510 → 552 |
| `core/src/recipe.rs` | 582 → 582 |
| `core/src/actions.rs` | 592 → 592 |
| `core/src/frame_grid.rs` | 40 → 40 |
| `core/src/format.rs` | 343 → 366 |
| `core/src/edit.rs` | 840 → 840 (seven rows lengthened in place) |
| `core/include/reelcut_core.h` | 361 → 370 |
| `core/tests/schema_v9.rs` | new → 399 |
| `core/tests/words.rs` | new → 399 |
| `core/tests/schema_v3.rs` | 256 → 256 |
| `core/tests/model_tests.rs` | 2138 → 2138 |
| `core/tests/commit_placement.rs` | 346 → 347 |
| `core/tests/common/commit_placement.rs` | 138 → 139 |
| `core/tests/schema_v5.rs` | 442 → 441 |
| `core/tests/recipe.rs` | 618 → 621 |
| `core/tests/schema_v2.rs`, `schema_v4.rs`, `schema_v6.rs`, `schema_v7.rs`, `schema_v8.rs`, `time_bounds.rs` | unchanged (1312, 452, 696, 359, 618, 209) — one expected version each |
| `tools/proof/words_core_proof.py` | new → 425 |
| `tools/proof/phase9_proof.py` | 1809 → 1809 |
| `tools/proof/phase2_proof.py` | 687 → 687 |
| `tools/proof/phase3_proof.py` | 1460 → 1460 |
| `tools/proof/phase4_proof.py` | 1191 → 1193 |
| `tools/proof/e2_proof.py` | 1186 → 1190 |
| `designs/reelcut-design.md` | 3655 → 3764 |
| `designs/reelcut-core-notes.md` | 1027 → 1077 |
| `tools/proof/README.md` | 4515 → 4553 |

No touched source file crossed 600. `recipe_text.rs` grew by 42 where the
design estimated about 15 — the two computed keys, the description rule and
their comments — and now has 48 lines of room.

**Scores.** `cargo fmt --check` in `core/`: exit 0. `make test`: exit 0,
53 suites, **816 passed, 0 failed** (786 before; `schema_v9.rs` 14 and
`words.rs` 16). `make lint`: exit 0. `make typecheck`: exit 0, 0 errors,
**7 warnings**, the W1a baseline. `env -u RC_ASSEMBLYAI_KEY make app`:
BUILD SUCCEEDED. `words_core_proof.py` on a fresh instance (port 4851,
`grep "Reelcut: "` empty before and after): **27/27**. Its three mutants,
each in a copied `core/` with a once-only anchor and a 900 s ceiling, each
exit 0 with the named test FAILED: `hash-arm`
(`words::a_styled_page_hashes_a_word_apart_differently`), `trim-rebase`
(`words::trim_start_rebases_the_words_by_its_delta`), `count-check`
(`schema_v9::a_count_mismatch_is_an_error_in_the_rules_own_words`).
The byte comparison of two `render_frame` PNGs a word apart is a CONTROL:
nothing draws `word` until W3. The recipe's `word` / `word_pop` are not
reachable over MCP (no tool returns a recipe), so the recipe rows are proved
in `core/tests/words.rs` through the FFI, including `Words::of` on the
unsorted `[0, 600000, 100000]` list (`word` 2, `word_pop` inside 0..1) and an
`i64::MIN` start (`word_pop` 1.0).

Existing proofs against the new binary, each on its own fresh instance,
killed by PID, `grep "Reelcut: "` empty before and after:
`phase2_proof.py` **86/86** (4852); `phase3_proof.py` **123/123** (4853);
`phase4_proof.py` **84/84** (4854); `phase9_proof.py` **217/217** (4856 —
the first run, 4855, scored 208/216 on eight rows that asserted "stamped 8",
walked forward below); `e2_proof.py` **69/69** (4857);
`patch_door_proof.py` (which runs `patch_door_patches.py` and
`patch_door_args.py`) **261/261** (4858); `refusal_proof.py` **116/116**
(4859); `op_argument_proof.py` **133/133** (4860); `target_bump_proof.py
compare` against W1a's capture (a copy of `tools/proof/work/target-bump`)
**3/3** (4861). `cloud_captions_probe.py` (no instance): **732/733** — the
one FAIL is row 18, "`project.yml` changed in the Speech usage string and
NOWHERE else", which diffs `project.yml` against HEAD and now sees W1a's
three macOS 26 lines. W1b did not touch `project.yml`; the row is W1a's
residue, recorded here and owed to whichever phase next edits that probe.

**Corrections to this document.** §4's W-2 and W-6 said "refuses … as spec
§5.5's third arm". Spec §6 makes every `set_*` range failure an **error**
(`check_blend` is the precedent), and so is `set_action_end`'s
`video.motion` refusal, so W1b built both as `Err` — §5.5's fourth answer,
no undo step — and §4's bullets and spec §11's W-2 and W-6 say so.
`Outcome::Identity`'s doc list is untouched. W-3's `split` bullet gained the
drop-to-`[]` clause (the objection that a split after a content-switching
action would leave a half the door refuses forever).

**Walk-forwards beyond the named fixtures.** The bump moved every assertion
that the writer stamps the CURRENT version: `schema_v2.rs`, `schema_v3.rs`,
`schema_v4.rs`, `schema_v5.rs`, `schema_v6.rs`, `schema_v7.rs`,
`schema_v8.rs` and `time_bounds.rs` (8 → 9), `model_tests.rs`'s two
new-project literals, its round-trip fixture and its every-prior-version
loop (now 1–9), `tests/common/commit_placement.rs`'s `text_props` (the three
new keys), `schema_v5.rs`'s module doc (its "animation is the LAST key"
bullet), `phase9_proof.py`'s versions loop (1–9, stamped 9),
`phase4_proof.py`'s "animation is the LAST key" check (now: followed by
exactly `case`, `words`, `word_style`), and `e2_proof.py`'s save check (a
`CURRENT_VERSION = 9` beside E2's own `VERSION = 8`, which its hand-written
version-8 fixtures keep).

**Known limits.**
- `paste`'s payload is stored whole (road map 5 §12, R2·2), so a pasted clip
  carrying a count mismatch is refused at its next `set_text` until the
  caller sends `words: []`; `split` clears it on the second half only.
  Nothing here changes `paste`.
- `actions.rs` does not restore base `words` over an end patch: the door now
  refuses one, but a hand-written or pasted action's `words` merely
  interpolate ticks (`lerp_number` keeps integers integral), and the recipe
  then reads whatever list the evaluation reached.
- A finished action that switches `content` over a timed page leaves `word`
  null (the page draws static) until the clip is split or its words are
  re-sent — W-6's degradation, by design.

**Residue.**
- `app/Sources/ProjectSnapshot.swift`'s `formatVersion = 5` (line 1890) was
  already stale and stays; no Swift decodes `case`, `words`, `word_style`,
  `word` or `word_pop` yet (W2–W4). Swift decodes leniently, so the app
  builds and runs unchanged.
- `core/CLAUDE.md` needs module-map entries for `model_words.rs` and
  `recipe_words.rs`, and its format rule's "versions 3 through 8 have none"
  becomes "3 through 9"; subagents do not edit `CLAUDE.md` files, so the text
  is owed by hand.
- `cloud_captions_probe.py` row 18, above.

#### W1b's review — three nits, recorded rather than fixed

The pipeline's review passed with no blocker and no should-fix. Its three
nits stand in the tree, for whichever phase next touches the file:

- `tools/proof/words_core_proof.py` is 425 lines, over the 400 a new file is
  held to; not trimmed.
- `core/src/recipe_text.rs`'s `text_source` doc (about line 271) and module
  doc still say "the three computed keys"; a text layer now carries five —
  the three reveal keys and `word` / `word_pop` from `recipe_words.rs`.
- `core/tests/words.rs`'s `a_rate_change_resnaps_the_words_under_d7_3`
  changes the CANVAS frame rate (`set_canvas fps`), not a clip's rate; the
  name misleads.

The orchestrator applied the proposed `core/CLAUDE.md` text by hand after
the review: map entries for `model_words.rs` and `recipe_words.rs`, and the
Format-changes rule's "versions 3 through 9 have none".

### 10.6. W2 — the on-device engine, landed 2026-09-22

**What landed.** `SpeechAnalyzer` + `SpeechTranscriber` replace
`SFSpeechRecognizer` behind the unchanged `Transcriber.Job → Outcome →
CaptionCues.build` path, over the same extracted 16 kHz mono WAVs (spec §11
W-8, recorded first, with dated amendments in place to the `MediaImporter`
`async` decision and the extracted-audio/ceiling decision). Subtitle output
is unchanged in shape; nothing of W3/W4 was touched.

- `SpeechEngine.swift` (new) is the ONE file under `app/Sources` that
  imports Speech or says `async` for it: `transcribe` (synchronous, refuses
  main, a `Task.detached` analysis signalling a semaphore waited for in
  0.1 s slices, bounded at `max(120, seconds × 4)`), the three bounded asks
  (`supportedLocales`, `installedLocales`, `isInstalled`; `askBound` 10 s),
  `download` (main-queue progress and completion), and `Handle`, what
  `CancelToken` now holds instead of an `SFSpeechRecognitionTask`.
- `Transcriber.swift`: the whole `SFSpeechRecognizer` half deleted —
  `TaskSink`, the delivery `OperationQueue`, the grant (`canAsk`,
  `requestAuthorization`, `authorizationStatus` and the rest), the ceiling
  (`truncationSlack`, `Truncation`, `Outcome.truncations`) and
  `TranscribeError.notAuthorized`; `noOnDeviceModel` renamed `notInstalled`.
  `transcribe` guards `isAvailable`, then `isInstalled` for the one chosen
  locale (nil → `.unavailable`, false → `.notInstalled`).
- `Transcriber+Languages.swift`: both lists asked of the engine, in BCP-47;
  `Language.installed`; `forgetLanguages()`; `defaultLanguage(in:)`
  rewritten over `identifier(.bcp47)`, preferring an installed row.
- The sheet: every supported locale in the popup, a missing model titled
  "— not installed", Generate live only for an installed language, and the
  Download row (`TranscribeSheetController+Download.swift`, grid row 1,
  `cloudRows` → `[3, 4, 5]`). No grant branch.
- `transcribe`: no grant tier; the refusal order is the caller's mistakes
  (scope, `engine`, cloud-only arguments, spelling), then the installed model,
  then the run. **`truncated` and the apple `note` are GONE for both engines**
  — a key that can never be true teaches a caller to read for a ceiling that
  no longer exists. The argument set is unchanged, so the gate and the five
  parity parts see nothing new; the catalog's prose was rewritten (no grant,
  no ceiling, models per Mac, never downloads).
- `project.yml`: `NSSpeechRecognitionUsageDescription` and its comment
  REMOVED (no code path asks for the grant; W0 q1 ran the engine in a
  hardened-runtime bundle without the key); the microphone comment's aside
  about how speech reads a file reworded.

**Two measurements W2 made that correct W0 q3** (this host, 2026-09-22,
bare Mach-O test programs, never a download):
- **`status(forModules:)` is `.installed` only for a RESERVED locale.** For
  `en-US` — in `installedLocales` — it answered `.supported` with nothing
  reserved, `.installed` after `AssetInventory.reserve(locale:)`, and
  `.supported` again after the release. Constructing a `SpeechTranscriber`
  reserved nothing (`reservedLocales` stayed `[]`), a full analysis of the
  pangram (23 runs) reserved nothing, and reserving the uninstalled `fr-FR`
  left its status `.supported` — no download. Why W0 q3 read `installed` is
  not settled; W0's own probe (`speech_probe assets en_US`), re-run today,
  printed `reserved` `["fr_FR", "en_US"]` and `status_installed`
  `installed`, so the locale WAS reserved when that row asked. So
  `SpeechEngine.isInstalled` RESERVES, reads, and releases a reservation it
  made; the first build (status without a reservation) refused `en-US` as not
  installed on the first MCP call.
- **`release(reservedLocale: fr-FR)` answered `false` while `fr_FR` was
  reserved.** The release matches the framework's own spelling, so
  `SpeechEngine`'s release also walks `reservedLocales` and releases every
  entry with the same BCP-47 tag. P2 reads `reservedLocales` empty after the
  probe's runs.

**Line counts, `wc -l` before → after** (before read off tree `c8c87624`):

| File | Before → after |
|---|---|
| `app/Sources/SpeechEngine.swift` | new → 358 (392 after the review's fix pass, 399 after the second review's) |
| `app/Sources/Transcriber.swift` | 583 → 340 |
| `app/Sources/Transcriber+Languages.swift` | 172 → 176 (179 after the fix pass) |
| `app/Sources/Transcriber+Extract.swift` | 305 → 305 (comment only) |
| `app/Sources/TranscribeSheetController.swift` | 540 → 514 |
| `app/Sources/TranscribeSheetController+Download.swift` | new → 163 (165 after the fix pass) |
| `app/Sources/TranscribeSheetController+Cloud.swift` | 334 → 337 |
| `app/Sources/TranscribeSheetController+Commit.swift` | 205 → 189 |
| `app/Sources/AgentServer+Captions.swift` | 439 → 401 |
| `app/Sources/AgentServer+CloudCaptions.swift` | 279 → 279 (comment only) |
| `app/Sources/AgentCatalog+Captions.swift` | 221 → 216 |
| `app/Sources/CloudTranscriber.swift` | 325 → 323 |
| `app/Sources/AssemblyAIClient.swift` | 397 → 398 (comment only) |
| `app/Sources/RecorderPanelController+Recording.swift` | 382 → 383 (comment only) |
| `app/Sources/ScreenRecorder.swift` | 399 → 399 (comment only) |
| `app/Sources/RecordingSetup.swift` | 300 → 301 (comment only) |
| `project.yml` | 151 → 142 |
| `tools/proof/speech_engine_proof.py` | new → 364 (371 after the second review's pass) |
| `tools/proof/speech_engine_probe.swift` | new → 362 (400 after the second review's pass) |
| `tools/proof/phase4_proof.py` | 1193 → 1184 |
| `tools/proof/cloud_captions_proof.py` | 2100 → 2103 |
| `tools/proof/cloud_captions_probe.py` | 6515 → 6538 |

**Scores, each printed by a run on 2026-09-22.**
- `cargo fmt --check` clean; `make test` 53 suites, 816 passed, 0 failed;
  `make lint` clean (no Rust changed).
- `make typecheck`: 0 errors, **7 warnings, the baseline's seven** —
  `Playback.swift:332`, `ExporterWriter.swift:676`, `Exporter.swift:595`,
  `CompositionBuilder.swift:131, 368, 401, 446`. None moved: no file W2
  touched holds one.
- `env -u RC_ASSEMBLYAI_KEY make app` rc 0; `harness/build.sh --force` built.
- `speech_engine_proof.py 4871` (fresh instance): **31/31, 0 skipped** — 13
  MCP rows (pangram 22 of 23 words; `ten.wav` 604.2 s WHOLE in 8.7 s, 108
  cues, the first at 0.00 s and the last ending at 603.18 s, every cue within
  the four rules; silence the exact sentence; `zz-ZZ` a misspelling; `fr-FR`
  refused as not installed in 0.00 s, identically twice; no undo step), the
  probe built and 12/12 probe rows (P1 cancel at 300 ms answered `.cancelled`
  0.02 s after the cancel — at progress 0.000, i.e. during the extract — and
  P1 mid-analysis at progress 0.023 answered `.cancelled` 0.02 s after; P7
  1 242 runs, the last ending at 603.2 s; P4 `.notInstalled("French (France)")`
  in 0.51 s), and 4/4 mutants.
- `phase4_proof.py 4872` (fresh instance): **83/83**; 4a rewritten —
  `speech.mov` transcribes ("the quick brown fox jumps over the lazy dog.
  pack my box with 5 dozen liquor jugs."), placed as one undo step, the two
  language tiers.
- `cloud_captions_proof.py --port-base 4873`: **167/167** (row 8's accepted
  answers now the on-device engine's own; row 9 unchanged and still true).
  The spec's `cloud_captions_proof.py 4873` form does not parse — the script
  takes `--port-base`.
- `cloud_captions_probe.py`: **733/733**. Row 18 now expects exactly what a
  run printed: W1a's three macOS 26 lines, the deleted usage-description
  block (eight lines), and the microphone comment's two reworded lines.
- `phase4_chrome.py`: **59/59** (the harness compiles `SpeechEngine.swift`).
- `grep "Reelcut: "` over `/tmp/reelcut-4871.log` … `-4875.log` printed
  nothing.

**Mutants** (tree copies under `tools/proof/work/speech_engine/mutants/`,
once-only anchors, the probe rebuilt from each; each exited with its named
row FAILED):

| Mutant | Named row | What it answered |
|---|---|---|
| `keep-last-result-only` | P7 ten minutes | 6 runs over 604.2 s (P6 failed too: 6 of 23 words) |
| `drop-the-trim` | P6 pangram | 1 of 23 words, 22 runs with whitespace at an end (`" quick"`) |
| `skip-installed-check` | P4 not installed | `fr-FR` reached the engine: `.failed("… Audio format is not supported")` |
| `raw-compare-default` | P3 default | `en-AU` over both lists where the host's tag is `en-US` |
| `cancel-live-before-progress` (second review's pass) | P5 awaiting progress | the only row failed |
| `release-before-signal` (second review's pass) | P8 gate stalled | no answer, 0 pangram words, in 60.01 s with the gate held for 90 s; the only row failed |

**The review, and the fix pass.** A reader review found three should-fix
defects and three nits, all dealt with in one pass the same day:
- `isInstalled` reserves, reads `status` and releases, but any other
  path's release (an analysis winding down after a cancel, a concurrent
  sheet and tool, a second `isInstalled` that found the locale held) could
  drop that reservation between the reserve and the read, and an installed
  model would then be refused `.notInstalled`. FIXED: `SpeechEngine`'s
  private `Gate` actor runs `isInstalled`'s reserve → status → release, and
  every `release`, one at a time, first come first served, with `held` read
  inside it (an actor alone interleaves at each `await`, so it waits on a
  continuation queue). Not separately proved: no row races two walks.
- `supportedLanguages()` cached a list read against an EMPTY installed set
  — what the installed ask expiring past `askBound` looks like — so every
  row would read "— not installed" for the session. FIXED: that list is not
  cached. Not separately proved: no row makes the ask expire. On a Mac
  with zero installed models `supportedLanguages()` never caches, so every
  sheet open re-asks both lists on main, each bounded at `askBound`.
- The Download row's Cancel was live before the request's `Progress` had
  arrived, and a Cancel then did nothing. FIXED: Cancel is disabled until
  `downloadProgress` is set. P5 still passes (it sets a `Progress` by hand);
  the window itself is part of the person's download check.
- Nits: a downloaded model's survival, and a second request after
  reopening the sheet mid-download, are now person's checks in
  `designs/reelcut-remaining.md` §4; the Download row's KVO
  `DispatchQueue.main.async` hop is named in the proposed `app/CLAUDE.md`
  seam text.

After the pass, every command above was run again: `cargo fmt --check`,
`make test` (53 suites, 816 passed, 0 failed), `make lint`, `make
typecheck` (0 errors, the same 7 warnings), `env -u RC_ASSEMBLYAI_KEY make
app`, `harness/build.sh --force`; `speech_engine_proof.py 4871` **31/31**
(12/12 probe rows, 4/4 mutants), `phase4_proof.py 4872` **83/83**,
`cloud_captions_proof.py --port-base 4873` **167/167**,
`cloud_captions_probe.py` **733/733**, `phase4_chrome.py` **59/59**, and
`grep "Reelcut: "` over the five logs printed nothing.

**The second review, and this pass.** A second reader review found one
should-fix and three nits, closed in one pass on 2026-09-22:
- **Liveness.** `analyse` released its locale BEFORE it finished the sink,
  and `download` released before its completion landed, and every release
  queues at the gate. A stalled holder — an `isInstalled` whose reserve or
  status stopped answering keeps the gate after its `askBound` expiry —
  therefore held every later caller: an analysis finished but could not
  signal, so `transcribe` answered `.timedOut` at its bound, and a
  download's completion never landed. FIXED: `analyse` now calls
  `sink.finish(failure)` and then `await release(locale)`, and `download`
  runs its completion on main and then releases; each doc comment says the
  caller is answered before the task waits its turn at the gate. PROVED on
  the analysis side by the probe's new last row, P8 gate stalled: a
  detached task holds `SpeechEngine.gate` for 90 s and `SpeechEngine.transcribe`
  over the pangram answered 23 runs, 22 pangram words, in 0.21 s; the
  mutant `release-before-signal` (the old order) answered nothing in
  60.01 s. `gate` and `Gate` are now internal so the probe can hold them;
  nothing in the app outside `SpeechEngine.swift` reads them. The download
  side is the same two-line shape and is NOT separately proved: it would
  call `downloadAndInstall()`, which is never called on this host (§10.1 q3).
- **What REMAINS of it.** A stalled holder still turns every later
  `isInstalled` into nil — `.unavailable` — until relaunch, by design of
  `askBound`: the question waits its turn at the gate and expires. Recorded,
  not fixed.
- **The overlap the reorder opens.** A finished analysis's `release` now
  queues at the gate AFTER its caller is unblocked, so it can land during
  the caller's next same-locale analysis, and `releaseNow` releases every
  reserved locale with that BCP-47 tag — that analysis's reservation too.
  The cancel and timeout paths could already do this (`transcribe`'s
  comment: the detached task "releases its locale on its own"); the success
  path could not. Accepted, not mitigated: no change to `releaseNow`, no
  per-analysis reservation tracking. Its effect on a running analysis is
  UNMEASURED beyond one number: the probe's P6 → P7 back-to-back en-US pair
  is the one place on this host where it occurs, and P7 after this pass
  printed 1 242 runs over 604.2 s, the last ending at 603.2 s — the same as
  the W2 run's P7.
- **P5's missing step** (nit): P5 awaiting progress sets `downloading` to
  fr-FR and `downloadProgress` to nil and reads the button "Cancel",
  enabled false. The mutant `cancel-live-before-progress` (Cancel enabled
  unconditionally) fails it.
- **`supportedLanguages()` with no installed model** (nit): the sentence is
  in the fix-pass bullet above. No code change.
- **The gate's rule** (nit): `Gate`'s doc comment now says never to call
  `release` or `gate.run` from inside `gate.run` — `releaseNow` is the
  in-gate form.

Every command was run again after this pass: `cargo fmt --check` clean,
`make test` 53 suites, 816 passed, 0 failed, `make lint` clean, `make
typecheck` 0 errors and the same 7 warnings, `env -u RC_ASSEMBLYAI_KEY make
app` rc 0, `harness/build.sh --force` built; `speech_engine_proof.py 4881`
(fresh instance) **35/35, 0 skipped** — 13 MCP rows (pangram 22 of 23
words; `ten.wav` 604.2 s WHOLE in 6.7 s, 108 cues, the first at 0.00 s and
the last ending at 603.18 s; `fr-FR` refused as not installed in 0.00 s,
identically twice), the probe built, 14/14 probe rows (P1 cancel answered
0.02 s after the cancel at progress 0.000, P1 mid-analysis at 0.023
answered 0.02 s later, P4 in 0.51 s, P7 as above, P8 as above), the exit
row, and 6/6 mutants — `keep-last-result-only` and `drop-the-trim` now fail
P8 too, which reads the pangram's words; `phase4_proof.py 4882` **83/83**;
`cloud_captions_proof.py --port-base 4883` **167/167**;
`cloud_captions_probe.py` **733/733**; `phase4_chrome.py` **59/59**; and
`grep "Reelcut: "` over `/tmp/reelcut-4881.log` … `-4885.log` printed
nothing. `wc -l`: `SpeechEngine.swift` 399, `speech_engine_probe.swift`
400, `speech_engine_proof.py` 371.

**What is owed.**
- A person's checks, in `designs/reelcut-remaining.md` §4: a real download
  from the Download row, the row LOOKED AT, `Progress.cancel()` during a
  download, the popups' lock seen mid-download (and a second request after
  reopening the sheet mid-download), that a downloaded model survives the
  release `download` makes (still installed, and transcribing, after a
  relaunch and later), and the no-network case.
- `app/CLAUDE.md`'s map entries (`SpeechEngine.swift`, the `Transcriber`
  family, `TranscribeSheetController` +`Download`), its Hygiene `async`
  clause and its `DispatchQueue` seam list (the recogniser's
  `OperationQueue` goes), and the root `CLAUDE.md`'s "async is confined to
  `MediaImporter.swift`" sentence: exact text proposed in the pipeline's
  handoff, applied by hand.
- Two proof COMMENTS still describe the old grant and were outside W2's file
  list: `tools/proof/harness/main.swift` (the `cues` mode's paragraph, about
  line 106) and `tools/proof/phase4_chrome.py` (section 8's header, about
  line 633). Both say `SFSpeechRecognizer` produces no words without a grant.

#### The W2 residue's review — one nit, recorded rather than fixed

Its review passed with one nit: probe row P8 cancels its 90 s stall and the
probe exits at once, so the release P8's own analysis queued behind the stall
may never run before exit, and no row checks whether that leaves `en-US`
reserved for the next run's P2. A bounded drain of the gate after
`stall.cancel()` would close it; the probe is at its 400-line cap. The
orchestrator applied W2's proposed `app/CLAUDE.md` text by hand (the
`SpeechEngine.swift` map entry with the gate's rule, the rewritten
`Transcriber` family entry, the `CloudTranscriber` entry without
`truncations`, the Hygiene `async` clause and the `DispatchQueue` seam list)
and the root `CLAUDE.md`'s typecheck sentence.

### 10.7. W3 — the picture, landed 2026-09-22

The app decodes format version 9's `case` / `words` / `word_style` and the
recipe's `word` / `word_pop`, and draws a timed page — a base pass, the
active word's pill and the active word popped about the pill's centre —
inside a box that already holds the pop's headroom in both axes. Three size
tolls landed first as pure moves, gated alone; the four W0 faces are
bundled; the inspector gained §5e's two items; `set_text`'s prose names the
three keys.

**The tolls, gated alone** (`wc -l` before → after). The three reveal
routines and what only they read out of `LayerRenderersText.swift` into
`LayerRenderersReveal.swift`: **577 → 408**, new file **186**. The text
group (`TextAnimationKind`, `OutlineProps`, `BackdropProps`,
`TextAnimation`, `TextProps`) and `RecipeReveal` out of
`ProjectSnapshot.swift` into `TextProps.swift`: **2516 → 2289**, new
**241**. `TextPatch` out of `ReelCore.swift` into `TextPatch.swift`: **1542
→ 1440**, new **113**. Verbatim text with doc comments; `typewriter`,
`wordFade`, `lineRise`, `TextLine`, `TextLayout`, `drawLaidLine`,
`drawFaded`, `tokens(of:)`, `midpoint` and `attributedString` widened from
`private` (an extension's `private` reaches only its file). The gate, on a
tree with nothing of the feature in it: `make typecheck` 0 errors / 7
warnings (the baseline recorded on the unchanged tree), `make app` rc 0,
`reveal_toll_proof.py compare` **6/6** against six frames captured on the
UNCHANGED build (a static title, a typewriter, a word_fade, an outlined
word_fade, a two-line line_rise over a backdrop; the capture's six PNGs all
distinct), `target_bump_proof.py compare` **3/3**, `words_core_proof.py`
**27/27** with its CONTROL still identical, `phase4_proof.py` **83/83**.

**The feature** (`wc -l` after): `WordProps.swift` **215** (new — the
vocabulary mirroring `model_words.rs`, `laidContent`, `tokenCount`,
`isUntimedPage`, `recolored`, `TextPatch.contentEdit` and
`InspectorBinding.contentOps` / `ops(textContent:)`);
`LayerRenderersWords.swift` **247** (new — `wordHeadroom`, `wordMetrics`,
`backOut`, `drawWords`); `LayerRenderersText.swift` 408 → **440**
(`laidContent` at the attributed string and the two reveal calls,
`layoutKey`, `textInsets`, the words arm FIRST in `drawText`,
`renderTextBitmap` + `upload`); `TextProps.swift` 241 → **274**;
`TextPatch.swift` 113 → **133**; `ProjectSnapshot.swift` 2289 → **2293**
(`RecipeSourceRef`: four lines, the only growth); `TextPane.swift` 513 →
**530**; `AgentCatalog+Clips.swift` 792 → **799** (`wordsClause`, prose
that cannot move purely). `app/Resources/Fonts/` gained the seven W0 files
byte for byte (sha256 prefixes d3ac6a843d3ba6d5, ea67b37f8776eebe,
a4ba3a92350ebb03, 08e4623805102d81, 8b7141c03fa4f8d4, ee67e6ee22790b79,
72082f6cb4d04be2); `project.yml` already registered the folder and
`ATSApplicationFontsPath: Fonts`, and was not edited. No `rc_*` export, no
core change, the op table unchanged, the catalog still 77.

**The headroom rule, as built.** `.zero` with no style, or at
`active_scale` 1 and no pill. Else, with `peak = 1 + (active_scale − 1) ×
1.1` (the peak of `back_out`), `pad = padding × size` and one `CTLine` per
token of `laidContent`: width `max(0.45 em, peak × pad + (peak − 1) ×
widest / 2 − outline + 2 px)`, height `max(0.30 em, peak × pad + (peak −
1) × (ascent + descent) / 2 − outline + 3 px)` (3 px since the review,
below). **This corrects §5d's and
§8's "vertically 0.30 em is enough" to a FLOOR**: at `active_scale` 1.5 and
the default pill the formula gives 48.78 px at 81 px (≈0.60 em, P7 after
the review's fix) and the
flat 0.30 em overflowed by 29 px (mutant `flat-vertical`, below). **The
`+ 2 px` is a deviation from this phase's spec**, found by its own probe row
P2: the spec's formula exactly, with no edge, left the scaled pill **2 px**
past the TOP of the box on both Montserrat faces at 1080×1920 and 1.5 —
`makeLayout`'s two points of frame slack centre the text rect a point
nearer the top inset, and the pill's antialiased edge takes a row more. It
is one named constant, `wordHeadroomEdgePx` — HORIZONTAL only since the
review, the vertical taking `wordHeadroomVerticalEdgePx` — and P7 checks
the formula with it. An unstyled text has zero headroom, so its insets,
`layoutKey` and pixels are what they were (`reveal_toll_proof.py` 6/6 and
`target_bump_proof.py` 3/3 after the feature too). A pop or pill style
keeps its headroom whether or not `words` is set: an UNTIMED pop-style page
has the styled box, not its unstyled twin's.

**Scores, final tree.** `cargo fmt --check` clean; `make test` **53
suites, 816 passed, 0 failed**; `make lint` clean; `make typecheck` **0
errors, 7 warnings** (the baseline's); `env -u RC_ASSEMBLYAI_KEY make app`
rc 0. On fresh instances, each on port 4871 and killed by PID, `grep
"Reelcut: "` empty before each: `reveal_toll_proof.py compare` **6/6**,
`target_bump_proof.py compare` **3/3**, `words_picture_proof.py` **7/7**,
`words_core_proof.py` **27/27** (its row inverted: two frames a word apart
now DIFFER), `phase2_proof.py` **86/86**, `phase3_proof.py` **123/123**,
`phase4_proof.py` **83/83**, `phase9_proof.py` **217/217**, `e2_proof.py`
**69/69**, `patch_door_proof.py` **261/261**, `op_argument_proof.py`
**133/133**. `words_picture_probe.py` **11/11** (the build, the answer, P1–P9:
32 pages, every bitmap `measuredSize` at every word and pop; no ink outside
any; the four faces resolved to `app/Resources/Fonts/*.ttf` with the pinned
sha256 although this host's `/Library/Fonts` copies are different files; P4
red ink at word 1 x 12–392 against the LAID midpoint 410.6 and "STRASSE"
391.96 wide, at word 2 from 431; P9 red ink 824 px at pop 0 and 1237 px at
pop 1). Then, after the harness build, `words_picture_chrome.py` **5/5**,
`phase2_chrome.py` **26/26**, `phase3_chrome.py` **33/33**.
`tools/proof/words_spike/text_probe.swift` still type-checks over
`app/Sources`.

**Mutants**, each built from a tree COPY of `app/Sources` with an anchor
asserted to occur once, each exit 0 with a row FAILED: `ignore-word` (P3,
P4, P9; 153 s), `drop-headroom` (P2 worst 162 px, P9; 135 s), `skip-case`
(P4; 138 s), `keep-words` (P6; 147 s), `clip-then-scale` (P9; 148 s),
`flat-vertical` (P2 worst 29 px, P7; 145 s).

**The review, and its fixes** (one pass, 2026-09-23). One should-fix and
three nits, all fixed.
- *should-fix* — the `+ 2 px` edge was calibrated on `valign` middle only.
  At "bottom" `makeLayout`'s frame starts at the inset and is two points
  taller than the text; CoreText fills it from its top, so the first line
  reaches two points into the top inset (the slack is below the last line,
  not above the text — W4a corrected this sentence's mechanism), and P1/P2
  never set `valign`. Fixed: the vertical term takes its own
  constant, `wordHeadroomVerticalEdgePx = 3` (the horizontal stays 2), and
  P1/P2 loop `valign` middle, top and bottom — **96 pages**, not 32. A
  CONTROL with the vertical edge put back to 2 fails P2 by **1 px** at the
  top of the box (worst 1 px); the four spilling pages the scorer prints
  are all Anton-Regular at `active_scale` **1.15** with `valign` bottom,
  both canvases, one line and wrapped (318 s). With 3, P2's worst is 0 px
  on all 96. `flat-vertical`'s anchor names the new constant.
- *nit* — `LayerRenderersText.swift`'s header still said the file held "the
  three reveal routines" and that nothing else crossed: reworded to name
  `drawText`'s dispatch to `LayerRenderersReveal` and `LayerRenderersWords`
  and the members W3 widened.
- *nit* — base-colour tokens went through the opaque-then-fade path, so at
  a `color` alpha below 1 a timed page faded the outline with the fill,
  unlike the static page. The base pass now draws from the layout AS LAID
  at alpha 1 (fill at its own alpha, stroke at the outline's); the three
  style colours keep opaque-then-fade.
- *nit* — `renderText` uploaded at a second `measuredSize(for:)` lookup
  while the bitmap was allocated at `layout.size`; it uploads at the
  context's own width and height now (the same integers: `measure` rounds
  up, `bitmap` rounds).

`wc -l` after the fixes: `LayerRenderersText.swift` 440 → **444**,
`LayerRenderersWords.swift` 247 → **255**, `words_picture_probe.swift` 278
→ **281**, `words_picture_probe.py` 256 → **256**. Re-run after them:
`make typecheck` **0 errors, 7 warnings**; `env -u RC_ASSEMBLYAI_KEY make
app` rc 0; on fresh instances on port 4873, each killed by PID and `grep
"Reelcut: "` empty before each: `reveal_toll_proof.py compare` **6/6**,
`target_bump_proof.py compare` **3/3**, `words_picture_proof.py` **7/7**,
`words_core_proof.py` **27/27**, `phase4_proof.py` **83/83**.
`words_picture_probe.py` **11/11** (96 pages, P2 worst 0 px; 304 s). Every
mutant exit 0 with a row FAILED: `ignore-word` (P3, P4, P9; 315 s),
`drop-headroom` (P2 worst 162 px, P9; 254 s), `skip-case` (P4; 292 s), `keep-words`
(P6; 316 s), `clip-then-scale` (P9; 315 s), `flat-vertical` (P2 worst
30 px, P7; 308 s) — four at a time, which is why they took twice the
serial run's time. Then `words_picture_chrome.py` **5/5**. Not re-run,
because no fix touched the core or their paths: `make test`, `make lint`,
`phase2/3/9_proof.py`, `e2_proof.py`, `patch_door_proof.py`,
`op_argument_proof.py`, `phase2/3_chrome.py`.

**Found, and left.**
- The Animation section's note is ONE line (`InspectorSection`), and at the
  inspector's 304 pt "Word style and animation do not compose; the word
  style wins." is cut to "…the word style w…" — seen in
  `work/chrome-words/untimed.png`. The sentence is W-5's and was not
  shortened here.
- Twice, during step 1's gate, the first request of `phase4_proof.py`
  against a just-bound instance was refused (`Connection refused`, 0/0)
  while other scripts launched the same way connected; later fresh
  instances connected every time and the gate's run passed 83/83. Not
  explained.
- `ProjectSnapshot.swift`'s stale `formatVersion = 5`, `recipe_text.rs`'s
  "three computed keys" doc and `words_core_proof.py`'s 425 lines are
  untouched (out of this phase).

**What is owed.**
- `app/CLAUDE.md`'s map entries for the five new files and the changed
  `ProjectSnapshot.swift`, `ReelCore.swift`, `LayerRenderers*` and
  `TextPane.swift` entries: exact text proposed in the pipeline's handoff,
  applied by hand.
- A person's checks, in `designs/reelcut-remaining.md` §4: the look on real
  footage, 60 fps with a pop on every word, and the app BUNDLE supplying
  the faces on a Mac without the families.
- W4: `CaptionStyle`, `CaptionPages`, the sheet's Style row and
  `transcribe`'s `style` — nothing on the app side writes `word_style` yet.

#### W4a's corrections to this record (2026-09-23)

W3's second review left three nits (the pipeline's `07-review-2.md`), and
W4a paid them first.
- `wordHeadroomEdgePx`'s doc and this record said "in both axes"; the
  constant is HORIZONTAL only since the review. Reworded in both places, and
  the 1.5 / default-pill formula's number is post-fix P7's **48.78 px
  (≈ 0.60 em)**, not 47.8 px (0.59 em).
- The valign-bottom mechanism was misstated: `makeLayout`'s frame starts at
  the inset and is two points TALLER than the text, and CoreText fills it
  from its top, so the first line reaches two points into the top inset —
  the slack is below the last line, not above the text. Reworded in
  `LayerRenderersWords.swift` and in the review paragraph above; the
  conclusion (3 px vertically) stands.
- **Nit 3 was a real spill, and it is fixed.** P1/P2 had measured pops only
  WITH the default pill. W4a added (`active_scale` 1.5, NO pill) for the four
  faces and each §5h word style's own face, case, outline, scale and pill
  (through `CaptionStyle`) to the loop — **204 pages**, from 96. On the tree
  as W3 left it P2 FAILED: worst **11 px**, on the RIGHT edge, one-line pages
  at 1080×1920 and 1.5 with no pill — Montserrat-Black 11 px, Montserrat-
  ExtraBold 10 px, each at `valign` middle, top and bottom (the scorer prints
  the first four spilling pages; whether any §5h style page spilled as well
  was not printed). The review's estimate of about 5 px was short by half.
  The fix is the one it named: with no pill the width term is `(peak − 1) ×
  widest / 2 + peak × outline / 2 + edge` — the popped stroke ADDED, where
  the pill's term keeps its `− outline`. Re-run: `words_picture_probe.py`
  **11/11**, P2 worst **0 px** over all 204 pages, P7 unchanged (it measures
  the pill), 575 s wall — its bound raised from 600 s to 1500 s for the
  larger loop; the six mutants in §10.9.

### 10.9. W4a — generation, landed 2026-09-23

Both engines page a run's words into width-measured, word-timed pages in one
of five styles, each page confined to its job's clip, and
`CaptionLayout.place` writes them as ordinary text clips carrying `words`
(clip time), `word_style` and `case`; `transcribe` gained `style` and
`replace`. Subtitles are byte-identical, and the Generate Captions sheet
still passes Subtitles and no replace — its chrome is W4b's. No `rc_*`
export, no core change, the op table unchanged (57), the catalog still 77.

**What landed** (`wc -l` before → after). New: `CaptionStyle.swift` **145**
(§5h's table as `enum CaptionStyle`, its measuring `TextProps` and base
`TextPatch`, `defaultsKey` declared for W4b and read by nothing);
`CaptionPages.swift` **335** (normalisation, `lead(for:)`, the pager,
balance, clause preference, shrink-then-wrap, page timing, the
`cues(...)` dispatch). Grown: `CaptionLayout.swift` 473 → **556** (`Cue`'s
`words`/`size`/`width`, `place`'s `style:`/`replacing:`, `Plan.replaced`,
`replaceableTracks`, `trackName(excluding:)`; `CaptionCues` untouched);
`TextPatch.swift` 133 → **140**; `WordProps.swift` 215 → **231**
(`ActivePill.dictionary`, `WordStyle.dictionary` — all six keys, `NSNull`
for a nil slot); `Transcriber+Jobs.swift` 178 → **187** (`Job.span`);
`Transcriber.swift` 340 → **344**; `CloudTranscriber.swift` 323 → **328**;
`TranscribeSheetController.swift` 514 → **526** (the two stored flags and
`pagesRequest`); `+Cloud` 337 → **337**; `+Commit` 189 → **194**;
`AgentServer+Captions.swift` 401 → **456**; `AgentServer+CloudCaptions.swift`
279 → **279**; `AgentCatalog+Captions.swift` 216 → **253**;
`LayerRenderersWords.swift` 255 → **265** (the three nits, §10.7's
corrections). Proofs: `word_captions_probe.swift` **387** and
`word_captions_support.swift` **185** (split so neither passes the new-file
cap), `word_captions_probe.py` **222**, `word_captions_proof.py` **391**
(new); `words_picture_probe.swift` 281 → **309**, `words_picture_probe.py`
256 → **259**; and three instruments the new signatures reached —
`speech_engine_probe.swift` 400 → **402** and `cloud_captions_probe.py`
6537 → **6538** (each `Transcriber`/`CloudTranscriber` call passes
`pages:` for Subtitles), `phase4_proof.py` 1184 → **1184** (its pinned
argument set of `transcribe` gains `style` and `replace`).

**The three decisions** (spec §11 W-7 carries one sentence each).
- **Pauses are word gaps of 0.25 s plus sentence punctuation**;
  `SilenceDetector` / `MediaSpeech` are NOT consulted. Measured by the
  probe's P10 on this host: `SpeechEngine` over the `say` pangram gave 23
  words; the gaps it left at the two real pauses are **0.24 s** (`dog. |
  Pack`) and **0.06 s** (`jugs. | How`) — both UNDER `breakGap`, so the gap
  rule finds neither (W0 q1's own run read 0.30 s at the first) — and the
  largest gap anywhere is 0.24 s.
  Both breaks come from the punctuation: (a) paged by gap and punctuation
  gives `The quick | brown fox | jumps over | the lazy dog. | Pack my box |
  with 5 dozen | liquor jugs. | How vexingly | quick daft | zebras jump.`
  (Highlight, 1080×1920), and (b) with road map 4's detector pauses
  [2.72–4.29, 6.68–7.81] injected as forced breaks gives the SAME ten
  pages. So (b) adds no break (a) lacks and nothing is owed; a recording
  whose pauses carry no punctuation is where the question would reopen
  (`designs/reelcut-remaining.md` §5).
- **`lead` lives in `CaptionPages.lead(for:)`** — `apple` +162 000 ticks
  (+270 ms), `assemblyai` −36 000 (−60 ms), W0 q2's medians — applied once in
  `normalize` and never in `CaptionCues`, so Subtitles never shift.
- **A page is confined to its job's span.** `normalize` clamps every word
  after `lead` — start into `[lower, upper − frame]`, end into `[start,
  upper]` — and the last page ends at `min(last.end + hold, upper)`; a word
  pushed off the end sits on the clip's LAST FRAME because the core snaps to
  the NEAREST frame (`core/src/time.rs`). `Job.span` is the one spelling.
  Proved by P11 and by G8 (below).

**Found while building, and recorded rather than redesigned.**
- **The no-blink extension is invisible under §8's own numbers.** `hold`
  (0.5 s) outlasts `breakGap` (0.25 s), so wherever the gap is under
  `breakGap`, `min(next.start, last.end + hold)` already reaches the next
  page. The rule is kept as §5c writes it; P6 runs twice — the standard
  rules and a hold of 0.1 s under the list's 0.12 s gaps — and only the
  second is what `drop-no-blink` fails.
- **A lone word the balance step cannot improve stays alone.** At
  Highlight on 1080×1920 one sentence ends on a one-word page after a width
  break because moving the word before it across would not bring the pair's
  widths closer (§5c's test). P3 is therefore "no lone word unless its break
  was forced, NO BALANCE MOVE IMPROVES IT, or it is ≥ half the budget" — the
  spec's "unless forced" read as the rules plus the balance step's own
  test; one such page in the final run's 250 lone-word pages.
- Karaoke's width for the balance step and the clause minimum is its WIDEST
  line; its two-line exception stands (it never breaks the width guarantee:
  every line is measured, P1).
- `replaceableTracks` follows §5e's three rules literally, so an EMPTY track
  named "Captions" qualifies (every clip of it vacuously overlaps).
- Spec §11 had no W-7 entry to "gain three sentences"; the entry was
  written whole, with the three.

**Scores, final tree.** `cargo fmt --check` clean; `make test` **53
suites, 816 passed, 0 failed**; `make lint` clean; `make typecheck` **0
errors, 7 warnings** (the baseline's); `env -u RC_ASSEMBLYAI_KEY make app`
BUILD SUCCEEDED. `word_captions_probe.py` **14/14** (71 s): 117 fixed words;
pages vertical / horizontal — Highlight 49 / 28, Pill 48 / 27, Karaoke
22 / 18, Build 32 / 19, One Word 117 / 117; fullest line 0.999 of the
budget; 120 width breaks, 37 balanced, 35 at a clause mark; 2 lone words
shrunk and 8 wrapped; 24 two-line
Karaoke pages; 934 abutting pairs; T = 11 200 000 for P11. Its five mutants,
each exit 0 with its NAMED row failed: `width-count` (P1, P2, P4, P7; 68 s),
`drop-balance` (P3 — "off-camera and | waits.", "So we renamed | it."; 68 s),
`drop-no-blink` (P6, at hold 0.1 s; 68 s), `drop-lead` (P8, P11; 67 s),
`drop-span` (P11 — A's last page 10 842 000…11 610 000 past T; 67 s).
`words_picture_probe.py` **11/11** (§10.7), and its six mutants:
each exit 0 with a row FAILED, run one at a time: `ignore-word` (P3, P4, P9;
590 s), `drop-headroom` (P2 worst 162 px, P9; 457 s), `skip-case` (P4;
540 s), `keep-words` (P6; 566 s), `clip-then-scale` (P9; 561 s),
`flat-vertical` (P2 worst 30 px, P7; 559 s).
On fresh instances, each killed by PID and `grep "Reelcut: "` empty:
`word_captions_proof.py 4891` **18/18** (G1 7 pages, G2 differing columns
per page between 198 and 871 of 1080 against [76, 1004], G6 23 pages, G8 cut
at 1 560 000 with 4 pages, no `trimmed`, no `skipped`); `phase4_proof.py`
**83/83**; `words_picture_proof.py` **7/7**; `words_core_proof.py`
**27/27**; `cloud_captions_proof.py --port-base 4895` **167/167**;
`speech_engine_proof.py` **35/35** (its six mutants caught);
`cloud_captions_probe.py` **733/733**. Then, after
`harness/build.sh --force` (64 s): `phase4_chrome.py` **59/59**,
`words_picture_chrome.py` **5/5**. No instance refused its first
request: each script waited for the log's bound-port line first.

**What is owed.**
- `app/CLAUDE.md`'s entries for `CaptionStyle.swift` and
  `CaptionPages.swift` and the changed `CaptionLayout`, `WordProps`,
  `TextPatch`, `Transcriber` and `LayerRenderersWords` entries: exact text
  proposed in the pipeline's handoff, applied by hand.
- **W4b**: the sheet's Style row, preview and Replace checkbox, over the
  stored `style` / `replaceExisting` and `CaptionStyle.defaultsKey`.
- A person's checks, `designs/reelcut-remaining.md` §4: sync by eye per
  engine, each style on real footage at 9:16 and 16:9, 60 fps with
  generated pages.

### 10.10. W4b — the sheet, and the close

File ▸ Generate Captions… gained §5e's chrome: a **Style** popup (Subtitles,
then the five word styles, in `CaptionStyle.allCases` order, opening on the
style last chosen), a **preview** under it drawn by the renderer's own
routine, and a **Replace existing captions** checkbox that lists the tracks
it will replace. The sheet's `style`, `replaceExisting` and `pagesRequest`
are now computed off those controls, so `begin`, `beginCloud` and `finish`
— unchanged callers — commit what `transcribe {style, replace}` commits:
Replace is live only for a word style and only over tracks
`CaptionLayout.replaceableTracks` names, the tool's two rules. The style is
remembered under `CaptionStyle.defaultsKey`, read by the popup and written
by `styleChanged`, never by the tool, and it is not part of any transcript's
marker (R6-15). No `rc_*` export, no core change; the op table is 57 and
the catalog 77.

**W4a's four review nits, first** (gated alone: `make typecheck` 0 errors /
7 warnings, `word_captions_probe.py` 15/15, both new mutants caught).
1. `replaceableTracks` requires at least one clip on the track: an EMPTY
   "Captions"/"Captions N" track no longer qualifies, is not removed and is
   not listed. `word_captions_proof.py`'s G4 adds an empty "Captions 2" before
   the `pill` + `replace` run: `replaced` is the old track alone and the
   empty one survives, empty (a new row, 18 → 19).
2. `fixed_words` shifts every token from the sixth unpunctuated mid-sentence
   one ("editing | video") 0.3 s later, a 0.42 s gap; **P12** asserts no page
   of any style or canvas holds both of its words (gap measured 252 000
   ticks). Mutant `drop-gap` (the `>= rules.breakGap` disjunct removed)
   fails P12 alone.
3. P2 exempts a `,;:` page only where `clauseMark`'s conditions held — the
   page at least `clauseMinimum` of the budget, and it plus m ≤
   `clauseWindow` next words laying where m + 1 did not — and requires at
   least one such page. **As first written it did not catch its own
   mutant**: with `clauseMark` disabled, two comma-ended pages still met the
   test, because the BALANCE step had made them (a width break moved one
   word across, leaving the comma last). So a page one balance move explains
   is not counted as a clause break; it falls to the maximality check, which
   accepts it as balanced. Final: 138 width breaks, 47 balanced, 13 at a
   clause mark. Mutant `drop-clause` (`clauseMark` never fires) fails P2
   with 0 at a clause mark.
4. G5's `place` refusal is matched on "when place is true", which "replace"
   does not contain.

**What landed** (`wc -l` before → after). `TranscribeSheetController.swift`
526 → **526** (the three members moved out; four stored views,
`sampleWordsCache`, three grid rows and `refreshStyleRow()` in `refresh()`'s
`defer` in); `TranscribeSheetController+Style.swift` **239** (new);
`CaptionPages.swift` 335 → **349** (`samplePage`); `LayerRenderersText.swift`
444 → **451** (`static func textBitmap`, the instance method forwarding);
`CaptionLayout.swift` 556 → **557**; `Theme.swift` 201 → **205**
(`DS.captionPreviewPlate`); `CaptionStyle.swift` 145 → **145** (the
`defaultsKey` comment, which said nothing read it). Proofs:
`harness/main.swift` 953 → **1052** (the `transcribe` target and
`MemoryDefaults`); `word_captions_chrome.py` **281** and
`word_captions_sheet_probe.swift` **388** plus `word_captions_sheet_support.swift`
**233** (new; the probe was 400 at W4b, before the residue's move); `word_captions_probe.py`
222 → **247**; `word_captions_probe.swift` 387 → **422** — past the 400 a
NEW file is held to, which this W4a file was written under: P12 and P2's
clause test are 35 lines, and moving them into `word_captions_support.swift`
would have touched a file outside this pipeline's list;
`word_captions_proof.py` 391 → **402**.

**Readings and decisions.**
- **"Two frames, with the second word active in each mode"** (§5e) was read
  as the sample page drawn twice and stacked — the FIRST word active, then
  the SECOND (`RecipeReveal(word: 1, wordPop: 1)` and `word: min(2, n)`),
  each `LayerRenderers.textBitmap` scaled into a 258 × 36 pt slot over the
  plate — and Subtitles, which has no word to make active, as one frame
  (`.whole`). One Word's page is one token, so its two frames are alike.
- **The sample is sentence case**, "This is how it looks", so each style's
  own `case` shows in the preview as `transcribe` commits it — capitals for
  Highlight, Pill, Build and One Word, as written for Subtitles and Karaoke.
- **The preview's page is a real page**: `CaptionPages.samplePage` is the
  first page `cues(...)` makes, balance step included. §5h's measured note
  still holds — at 1080 wide the width closes Highlight's sample at four
  tokens (751 px for four, 1 076 px for five, against 928) — but the balance
  step then moves the fourth across, "THIS IS HOW | IT LOOKS", so the first
  page holds **three**, not the four the spec's probe row expected; the row
  asserts both facts. On 1920 × 1080 all five fit.
- **The preview's words** are the scope's first clip's cached transcript,
  up to twelve, else the fixed sample; the ANSWER is cached per clip, a miss
  included, because `refresh` runs per keystroke and `MediaTranscript.read`
  is a disk read hit or miss.
- **The preview sits UNDER the popup**, in the controls column (258 × 80 pt),
  not beside it: the column is 258 pt wide.

**Found while building, and recorded rather than redesigned.**
- **A named `UserDefaults` suite removed with
  `removePersistentDomain(forName:)` still leaves
  `~/Library/Preferences/<suite>.plist` behind.** Measured with a standalone
  program: remove, `CFPreferencesAppSynchronize`, `synchronize()` and a
  `FileManager` delete inside the process all "work", and a 42-byte EMPTY
  plist appears several seconds after the process has exited — cfprefsd
  writes the emptied domain late, so no removal inside the process can win.
  The harness's `transcribe` target and the sheet probe therefore never make
  a named suite: both hand the sheet `MemoryDefaults`, a `UserDefaults`
  subclass that keeps its values in memory (the sheet reads
  `string(forKey:)`, writes `set(_:forKey:)` and, on a keyed cloud start,
  reads the ARGUMENT domain through
  `volatileDomain(forName: UserDefaults.argumentDomain)`, which
  `MemoryDefaults` answers empty). After the
  chrome script and its seven mutants, `ls ~/Library/Preferences | grep -c
  "reelcut.harness.transcribe\|wordsheet-"` printed **0**.
- **`cloud_captions_probe.py` has been leaving its suites behind for the
  same reason**: `~/Library/Preferences` held **1 619**
  `cloudprobe-*.plist` files after this pipeline's run of it (1 588 before
  it; 1 387 of them the empty 42-byte kind, by `find ~/Library/Preferences
  -maxdepth 1 -name 'cloudprobe-*.plist' -size 42c | wc -l`). Its `dropSuite` is the pattern
  above. Not fixed here — the file is outside this pipeline — and owed below.
  The 1 619 files were deleted by hand on 2026-09-23 at the user's request
  (`find … -name 'cloudprobe-*.plist' -delete`, then 0 left); the probe
  itself still writes them.
- **`finish` ends a clean run in `dismiss(self)`**, which raises for a
  controller nobody presented; the probe's S5 presents the sheet from a host
  with a no-op `NSViewControllerPresentationAnimator`, so the commit is
  driven through the real exit.
- The harness's `transcribe` target is the first photograph of the Generate
  Captions card at all: `settings`' header sentence that it was
  "photographed nowhere" is corrected.

**Scores, final tree.** `cargo fmt --check` clean; `make test` **53
suites, 816 passed, 0 failed**; `make lint` clean; `make typecheck` **0
errors, 7 warnings** (the baseline's); `env -u RC_ASSEMBLYAI_KEY make app`
BUILD SUCCEEDED. `word_captions_probe.py` **15/15** (67 s): 117 fixed words;
pages vertical / horizontal — Highlight 50 / 29, Pill 49 / 28, Karaoke
22 / 18, Build 32 / 19, One Word 117 / 117; fullest line 0.999 of the
budget; 138 width breaks, 47 balanced, 13 at a clause mark; 252 lone-word
pages, 3 a balance move cannot improve; 2 shrunk, 8 wrapped; 24 two-line
Karaoke pages; 922 abutting pairs; P11's T moved with the list to
**11 380 000** (word 58, raw 11 220 000…11 328 000); P12's gap "editing |
video", 252 000 ticks; P10 unchanged (23 words, the same ten pages both
ways). Its seven mutants, each exit 0 with its NAMED row failed:
`drop-gap` (P12), `drop-clause` (P2), `width-count` (P1, P2, P4, P7),
`drop-balance` (P3), `drop-no-blink` (P6), `drop-lead` (P8, P11),
`drop-span` (P11), 66–68 s each. `words_picture_probe.py` **11/11**.
On fresh instances, each killed by PID with `grep "Reelcut: "` empty
first: `word_captions_proof.py 4931` **19/19** (G1 7 pages, G2 columns per
page between 198 and 871 of 1080 against [76, 1004], G6 23 pages, G8 cut at
1 560 000 with 4 pages); `words_core_proof.py` **27/27**;
`words_picture_proof.py` **7/7**; `phase4_proof.py` **83/83**;
`speech_engine_proof.py` **35/35** (14/14 probe rows, its six mutants
caught); `cloud_captions_proof.py --port-base 4940` **167/167**;
`cloud_captions_probe.py` **733/733**. Then, after
`harness/build.sh --force` (72 s): `word_captions_chrome.py` **31/31**
(the W4b residue's run, 80 s, after its own 65 s
rebuild; 27/27 in 85 s before S8 and S9) — CONTROL byte-identical (98 939
bytes twice), six distinct PNGs per
appearance, every style light ≠ dark, Highlight 9:16 ≠ 16:9, Replace with a
track ≠ without; the probe's S1–S9 (S2's six previews 7 305 to 28 885
bytes, all distinct; S3's label `Replaces “Captions” (1 caption).`; S5 two
cues, one "Captions" track, undo restoring the old one) — and its seven
mutants, each exit 0 with its NAMED row failed: `commit-wider-outline`
(S8 ×2), `preview-base-size` (S8 ×2), `preview-redraws` (S9) — the
residue's three — `preview-ignores-style`
(S2 ×2, S6), `replace-without-track` (S3 ×3, S7), `style-not-remembered`
(S4), `replace-empty-track` (S3's empty-track row); `phase4_chrome.py`
**59/59**; `words_picture_chrome.py` **5/5**; and the preferences count 0.

**What is owed.**
- `app/CLAUDE.md`'s entries for `TranscribeSheetController` (+`Style`),
  `CaptionPages` (`samplePage`), `LayerRenderersText` (`textBitmap`),
  `CaptionLayout` (at least one clip) and `CaptionStyle` (`defaultsKey` now
  read), and root `CLAUDE.md`'s road map 8 row: exact text proposed in the
  pipeline's handoff, applied by hand.
- `cloud_captions_probe.py`'s suites (above): its `dropSuite` cannot win
  against cfprefsd; `MemoryDefaults` is the shape that does.
- A person's checks, `designs/reelcut-remaining.md` §4: the sheet's preview
  LOOKED AT, and the Style row seen in the app as a sheet — beside W4a's
  and W3's, which stand.
- Next work on word captions starts at §7's not-built list
  (`designs/reelcut-remaining.md` §5).

**W4b residue, 2026-09-23.** The review's six nits and the orchestrator's
addendum, closed in one pipeline; no core change (op table 57, catalog 77).
In the review's order:
1. **A shrunk page is ONE page in three places.** The review found the
   preview drew a shrunk page's outline at em × its own size while `place`
   committed em × the BASE size; the addendum found the pager measured it the
   preview's way. Resolved in the addendum's direction — the commit follows
   the pager, not the preview the commit: `CaptionStyle.textProps` is the one
   construction the pager measures and the sheet previews, and
   `CaptionStyle.pagePatch(content:size:width:words:)`, built from it, is what
   `place` writes (`basePatch(canvas:)` is deleted). An unshrunk page's ops are
   unchanged, key for key; a shrunk page's `outline.width` is now em ×
   `cue.size`. `previewProps`'s code is untouched. Probe row S8 measures it:
   "Straightforward", the first word of an eight-word ladder to shrink without
   wrapping, pages at 68.85 of 81.0; its preview props, its committed props
   less `words` and `textProps` at 68.85 are equal, the committed outline is
   5.508 (0.08 × 68.85), and it measures 895 px and draws a 895 px bitmap
   against a 928 px budget where the same text at 81.0 measures 1052 px
   (yesterday's commit, the outline at 0.08 × 81, measured 898 px). A word
   wrapped at the floor, 64.8 with `width` 928.8, holds the same three-way
   equality with outline 5.184, and Subtitles' preview props equal its
   committed props whole. Spec §11 W-7 gains the sentence.
2. **`loosen-clause`**, a mutant of `word_captions_probe.py` that loosens
   `clauseMark`'s two limits at once (`measure(head) >= 0`, `lowest = 0`):
   P2 fails with non-empty slack — 144 width breaks, 47 balanced, 12 at a
   clause mark, and four Karaoke pages such as "you open a project," + "you"
   that still fit.
3. **`MemoryDefaults` answers every keyed call from memory, the argument
   domain empty, and every domain write traps** — the same text in
   `harness/main.swift` and the new `word_captions_sheet_support.swift`. The
   sheet reaches THREE calls, not two: `string(forKey:)`, `set(_:forKey:)`
   and, on a keyed cloud start, `volatileDomain(forName:
   UserDefaults.argumentDomain)` through `AssemblyAIConfiguration`, which it
   answers `[:]` rather than trapping; `register`, the suite calls, the
   persistent- and volatile-domain writes and `synchronize` trap with
   `fatalError`, a crash and so a scored failure.
4. **The 1 387** is now printed with its command, before and after this run:
   `find ~/Library/Preferences -maxdepth 1 -name 'cloudprobe-*.plist' -size
   42c | wc -l` → 1387, beside `ls ~/Library/Preferences | grep -c
   '^cloudprobe-'` → 1619.
5. **The preview is redrawn on a key change only**: `PreviewKey` (the style,
   the first job's clip, the canvas) is stored on the sheet and
   `refreshStyleRow` redraws when it differs. Row S9: the preview's image is
   the same object across five `refresh()`es and a Vocabulary keystroke, and
   a new one on Pill and again on Highlight.
6. **The `ReelcutCaptionStyle` pin is kept, as DEFENSIVE**: `pinDefaults`'
   own rule pins a key ordinary use writes, and no render reads it —
   `transcribe` hands the card `MemoryDefaults` and no other mode builds the
   card. Its comment and the harness header now say so.

Sizes (`wc -l`, before → after): `CaptionStyle.swift` 145 → 152,
`CaptionLayout.swift` 557 → 555, `TranscribeSheetController+Style.swift`
239 → 252, `TranscribeSheetController.swift` 526 → 529;
`word_captions_sheet_probe.swift` 400 → 388 with
`word_captions_sheet_support.swift` 233 (new: a move of the probe's
fixture, builders and byte readers, then `MemoryDefaults` grown, and S8's
four readers, which is what keeps the probe under its cap),
`word_captions_chrome.py` 281 → 300, `word_captions_probe.py` 247 → 254,
`harness/main.swift` 1052 → 1116.

Scores: `make typecheck` 0 errors, 7 warnings; `env -u RC_ASSEMBLYAI_KEY
make app` BUILD SUCCEEDED; `word_captions_probe.py` **15/15** (66 s), P2
still "138 width breaks, 47 balanced, 13 at a clause mark", and its eight
mutants each exit 0 with the named row failed (`loosen-clause` P2,
`drop-gap` P12, `drop-clause` P2, `width-count` P1 P2 P4 P7,
`drop-balance` P3, `drop-no-blink` P6, `drop-lead` P8 P11, `drop-span`
P11; 66–68 s each). On fresh instances, killed by PID, `grep "Reelcut: "`
empty: `word_captions_proof.py 4871` **19/19**, `phase4_proof.py` on 4872
**83/83**. After `harness/build.sh --force` (65 s):
`word_captions_chrome.py` **31/31** (80 s) and its seven mutants, each
exit 0 with the named row failed, 66 s each; `phase4_chrome.py` **59/59**.
`ls ~/Library/Preferences | wc -l` printed 2454 before the run and 2454
fifteen seconds after the last script, and `grep -c
"reelcut.harness.transcribe\|wordsheet-"` printed 0.

#### The W4b residue's review — three nits, recorded rather than fixed

It passed with no blocker and no should-fix. Standing in the tree:
`CaptionLayout.swift`'s rewritten doc line near 223 runs to 128 characters
where the block wraps near 80; this paragraph's probe sentence above still
says "seven mutants" for a run the residue took to eight; and the sheet's
preview plate resolves `DS.captionPreviewPlate` at draw time while
`PreviewKey` carries no appearance, so switching light/dark with the sheet
open leaves the plate stale until the style, the first clip or the canvas
changes (before the residue any keystroke redrew it). The last is a
person-visible nit; the cure is the effective appearance's name in
`PreviewKey`.
