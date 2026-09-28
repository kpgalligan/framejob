# Spec §11 — Decisions made — do not re-litigate

A decision here is binding: it is not re-litigated, and a phase that needs a new one records it
here BEFORE the code (root `CLAUDE.md`). The entries were one chronological list until
2026-09-26; they are now grouped by the work that made them, in their original order within
each file. **Find a decision by its ID in the table below, then read only that file.**

**Adding one:** append it to the file for the road map in progress (a new road map gets a new
file), in the style of its neighbours: a bold one-line decision, an ID if the road map numbers
them, then the reasoning and the risk it accepts. Add its row here in the same change.

| File | Lines | Holds |
|---|---|---|
| [`foundations.md`](foundations.md) | 106 | **Foundations (M1–M3, road map 2).** AVFoundation not ffmpeg, the compositor, one op entry point, overlap and ripple rules, ticks, `async` confinement, media by reference; R2-1. |
| [`recording.md`](recording.md) | 97 | **Screen recording (road map 3).** The recorder: what is in and out, files, grants, pause. |
| [`silence.md`](silence.md) | 49 | **Remove Silences (road map 4).** Silero VAD, its grid and cache, voice mode; S1-23. |
| [`effects-motion.md`](effects-motion.md) | 60 | **Transitions and motion (road map 5).** R5-1..R5-5, E2-27. |
| [`deepening.md`](deepening.md) | 268 | **Deepening (road map 7).** D2-1, D3-1, #21, #22, D4-1..D4-6, D7-1..D7-3: how ops refuse, the op table, the gate, the source window, time envelopes. |
| [`cloud-captions.md`](cloud-captions.md) | 242 | **Cloud captions (road map 6).** R6-1..R6-16: AssemblyAI, keys, deletion, recovery. |
| [`word-captions.md`](word-captions.md) | 123 | **Word captions (road map 8).** W-1..W-11. |
| [`chrome-inspector-keys.md`](chrome-inspector-keys.md) | 306 | **Chrome, the clip inspector and keys (the sharp pass, road map 9, #35).** SH-1, SH-2, CI-1..CI-15, K-1, K-2. |
| [`graphics.md`](graphics.md) | 281 | **Graphics (road map 10).** G-1..G-16. |
| [`dev-tools.md`](dev-tools.md) | 27 | **Dev tools (road map 11).** V-1..V-3: the `REELCUT_DEV_TOOLS` flag and `make dist`, dev tools as ordinary tools, capture by `cacheDisplay`. |
| [`assistant.md`](assistant.md) | 117 | **The Assistant (road map 12).** AI-1..AI-15: the bundled helper, one lane, the catalog at launch, the fourth tab, the window's own project, W-9's reach, withheld and ask-first tools, the key, history, undo, the model, a call mid-gesture, the base-URL override, the tab kept on a selection change, the live context on each message. |

## Every decision

| ID | Decision | File |
|---|---|---|
| — | AVFoundation, not ffmpeg | [`foundations.md`](foundations.md) |
| — | Custom compositor from day one | [`foundations.md`](foundations.md) |
| — | `AVPlayerLayer` under an overlay view | [`foundations.md`](foundations.md) |
| — | One JSON op entry point | [`foundations.md`](foundations.md) |
| — | The plan-string compare | [`foundations.md`](foundations.md) |
| — | Overlap rule | [`foundations.md`](foundations.md) |
| — | Ripple is timeline-wide | [`foundations.md`](foundations.md) |
| — | Freeze frame keeps sync | [`foundations.md`](foundations.md) |
| — | Ducking is by clip extent | [`foundations.md`](foundations.md) |
| — | Speed and pitch | [`foundations.md`](foundations.md) |
| — | Text and shapes are described, not rasterized, in the model | [`foundations.md`](foundations.md) |
| — | Time is 600 000 ticks/s | [`foundations.md`](foundations.md) |
| — | No left panel | [`foundations.md`](foundations.md) |
| — | `async`/`await` is allowed only in `MediaImporter` | [`foundations.md`](foundations.md) |
| — | Transcription reads EXTRACTED audio, not the media file | [`foundations.md`](foundations.md) |
| — | Media is referenced, not copied | [`foundations.md`](foundations.md) |
| R2-1 | One composition audio track per source audio format | [`foundations.md`](foundations.md) |
| — | Screen recording is IN; camera recording and callouts stay OUT | [`recording.md`](recording.md) |
| — | A recording is ordinary media | [`recording.md`](recording.md) |
| — | The file lives in `~/Movies/Reelcut Recordings/` | [`recording.md`](recording.md) |
| — | The canvas takes the recorder's RATE; the media record takes the file's | [`recording.md`](recording.md) |
| — | The panel asks for the grants; the tool never does | [`recording.md`](recording.md) |
| — | A press of Record asks for Screen Recording once, and every later press opens System Settings at the pane | [`recording.md`](recording.md) |
| — | Microphone and system audio are two sources and stay two FILES | [`recording.md`](recording.md) |
| — | Undo of Add Recording leaves the files on disk | [`recording.md`](recording.md) |
| — | A paused recording is a SEQUENCE of files over ONE stream | [`recording.md`](recording.md) |
| — | The recorder panel goes away when a recording starts, for every source, and comes back only with something to say | [`recording.md`](recording.md) |
| — | The silence detector's second signal is a voice-activity model, and the model is Silero VAD v6.2.1 as a Core ML program | [`silence.md`](silence.md) |
| — | Edges come from the model's own 32 ms grid, inward; the level rule is the judge only where no voice is found | [`silence.md`](silence.md) |
| — | The probabilities are a per-media CACHE, never computed at feature time | [`silence.md`](silence.md) |
| — | Voice is the default mode | [`silence.md`](silence.md) |
| — | No network model in the silence path | [`silence.md`](silence.md) |
| S1-23 | A peaks marker certifies a complete selected audio-track decode | [`silence.md`](silence.md) |
| R5-1 | Effects are closed vocabularies, never a runtime | [`effects-motion.md`](effects-motion.md) |
| R5-2 | A transition's sound is a constant-power crossfade, on by default for NEW transitions and absent from old files | [`effects-motion.md`](effects-motion.md) |
| R5-3 | `add_transition` builds the overlap from handles, clamps the duration, and never moves a third clip | [`effects-motion.md`](effects-motion.md) |
| R5-4 | Motion is a presentation term | [`effects-motion.md`](effects-motion.md) |
| R5-5 | Motion is a pure function of clip time | [`effects-motion.md`](effects-motion.md) |
| E2-27 | A zero-duration edge is configured but inactive | [`effects-motion.md`](effects-motion.md) |
| D2-1 | A refused op says why in the CORE's words; a tool still names an argument the caller left out | [`deepening.md`](deepening.md) |
| D3-1 | The core says what an argument IS; the app says what it is FOR | [`deepening.md`](deepening.md) |
| #21 | A call is checked against the schema its tool published, at the door, for every tool | [`deepening.md`](deepening.md) |
| #22 | A media clip's window stays INSIDE its file, on the grid | [`deepening.md`](deepening.md) |
| D4-1 | A clip's content length is ONE function, and the plan obeys it | [`deepening.md`](deepening.md) |
| D4-2 | THE bound takes the pieces, and `start` is one of them | [`deepening.md`](deepening.md) |
| D4-3 | `set_speed` snaps NEAREST and is then held to the bound AT THE NEW RATE | [`deepening.md`](deepening.md) |
| D4-4 | every re-snap of a media clip's duration is one function, and a timed plate is held to its file | [`deepening.md`](deepening.md) |
| D4-5 | a head bound is snapped UP, in one spelling | [`deepening.md`](deepening.md) |
| D4-6 | the reversed mirror is APP arithmetic with ONE home, and the Speed sheet's readout is the core's own answer | [`deepening.md`](deepening.md) |
| D7-1 | Structural times have one admission envelope | [`deepening.md`](deepening.md) |
| D7-2 | Transition searches are bounded while retaining their chosen result | [`deepening.md`](deepening.md) |
| D7-3 | Normalize clip times when crossing a frame grid | [`deepening.md`](deepening.md) |
| R6-1 | The cloud engine is a second engine behind the same command, never a second command | [`cloud-captions.md`](cloud-captions.md) |
| R6-2 | Audio leaves the machine only by name, with the price in front of the person | [`cloud-captions.md`](cloud-captions.md) |
| R6-3 | The transcript is a per-media asset in the package | [`cloud-captions.md`](cloud-captions.md) |
| R6-4 | What was uploaded is deleted by us, immediately, and the fact is recorded | [`cloud-captions.md`](cloud-captions.md) |
| R6-5 | The app never holds an AssemblyAI key of Reelcut's | [`cloud-captions.md`](cloud-captions.md) |
| R6-6 | The protocol boundary is the base URL and the credential | [`cloud-captions.md`](cloud-captions.md) |
| R6-7 | No `async` exception | [`cloud-captions.md`](cloud-captions.md) |
| R6-8 | A fallback to Universal-2 is allowed and REPORTED | [`cloud-captions.md`](cloud-captions.md) |
| R6-9 | A proof-launched app never opens the person's stored key | [`cloud-captions.md`](cloud-captions.md) |
| R6-10 | The caption path clamps a clip's `speed` at BOTH ends, because the reader does not | [`cloud-captions.md`](cloud-captions.md) |
| R6-11 | A media whose remote delete this run could not confirm is not uploaded again in this run | [`cloud-captions.md`](cloud-captions.md) |
| R6-12 | The key and the region are a PERSON's settings, and no tool reads or writes either | [`cloud-captions.md`](cloud-captions.md) |
| R6-13 | The estimate never counts a HELD media as "to upload", and never hides its price | [`cloud-captions.md`](cloud-captions.md) |
| R6-14 | A lost submit reply permits bounded recovery, never another paid submit | [`cloud-captions.md`](cloud-captions.md) |
| R6-15 | A transcript marker identifies audio and the request, not display caches | [`cloud-captions.md`](cloud-captions.md) |
| R6-16 | A current transcript batch may be reused without credentials | [`cloud-captions.md`](cloud-captions.md) |
| W-1 | A word caption is an ordinary text clip holding one PAGE | [`word-captions.md`](word-captions.md) |
| W-2 | `text.words` is one `{start, end}` per whitespace token of `content`, and the core is the one counter | [`word-captions.md`](word-captions.md) |
| W-3 | Word times are clip time, and they move with the content, not with the clip's length | [`word-captions.md`](word-captions.md) |
| W-4 | `word_style` is a closed vocabulary, and the recipe carries a computed answer, never the timings | [`word-captions.md`](word-captions.md) |
| W-5 | `word_style` and `animation` do not compose; `word_style` wins | [`word-captions.md`](word-captions.md) |
| W-6 | `words` is not an animation target, and `paste_attributes` treats it as part of `content` | [`word-captions.md`](word-captions.md) |
| W-7 | Pages are filled to a MEASURED width, in one Swift builder, and the cue builder does not change | [`word-captions.md`](word-captions.md) |
| W-8 | The minimum is macOS 26, and the on-device engine is `SpeechTranscriber` | [`word-captions.md`](word-captions.md) |
| W-9 | No language model chooses words — amended by AI-6 | [`word-captions.md`](word-captions.md) |
| W-10 | `set_text` can patch `case`, `words` and `word_style` | [`word-captions.md`](word-captions.md) |
| W-11 | Karaoke's two lines, the bundled caption faces and the 80 % shrink floor are confirmed | [`word-captions.md`](word-captions.md) |
| SH-1 | `StickerButton` keeps its pill | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| SH-2 | `BlockSliderCell.drawBar` is forked from Rasterize's copy | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-1 | The selected action is the SIXTH piece of view state | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-2 | The editing target is the selected action, not the playhead | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-3 | Pan, mono, compressor, noise reduction, duck and keep-pitch go to the BASE props whatever is selected | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-4 | Mint is the action ink, and nothing else uses it | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-5 | The Clip tab is sub-tabs over a pinned block | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-6 | `◆N` counts KEYS, and the slider knob is the block | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-7 | Every inspector row carries the 14 pt mark gutter, and the label stays 76 | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-8 | A section the selected action keys opens once per selection, and a person's close sticks | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-9 | Reset shows only while a section differs from its default, and with an action selected the same slot reads Clear | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-10 | A person's refusal is shown, in the core's own sentence, at the inspector's foot | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-11 | A band is dragged: its body moves the action, its outer 5 pt resize it, in the timeline's lane and the Clip tab's lane alike | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-12 | The Clip tab's lane carries the clip's transition hatch, fades and motion wedges, and its Curve popup a glyph and the short names | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-13 | The canvas's handles follow the mode | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-14 | `set_action_end.off` keys an optional property OFF at the end | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-15 | Every sub-row carries `mixed`, and the collapse is the one animation | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| K-1 | Space is the transport's unless the first responder is typing or claims it | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| K-2 | In the canvas text editor Return applies, a modified Return is a new line, and Esc asks before dropping a change | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| G-1 | A graphic is a SOURCE, not an effect; R5-1 stands for effects | [`graphics.md`](graphics.md) |
| G-2 | The engine is a separate Rust crate; the core crate keeps its two rules | [`graphics.md`](graphics.md) |
| G-3 | A graphic's source is a FILE in the package, and is not an undo step | [`graphics.md`](graphics.md) |
| G-4 | The core checks props against the schema the OP carries; render time is lenient | [`graphics.md`](graphics.md) |
| G-5 | A graphic is a pure function of its inputs (R5-5 for code) | [`graphics.md`](graphics.md) |
| G-6 | Fonts: the app's bundled faces and the package's, never the system's | [`graphics.md`](graphics.md) |
| G-7 | A graphic draws at its own size, and crosses the FFI as premultiplied BGRA | [`graphics.md`](graphics.md) |
| G-8 | A failing graphic shows its error in preview, answers it to the agent, and stops an export | [`graphics.md`](graphics.md) |
| G-9 | A graphic has its own timeline: `in` and `length`, and `split` pins it | [`graphics.md`](graphics.md) |
| G-10 | Props are not action targets; everything about the LAYER is | [`graphics.md`](graphics.md) |
| G-11 | Plain JavaScript, one ES module, no TypeScript | [`graphics.md`](graphics.md) |
| G-12 | Colours in props are CSS strings | [`graphics.md`](graphics.md) |
| G-13 | The revision is a content hash, and an export pins it | [`graphics.md`](graphics.md) |
| G-14 | `graphics/` is created on the app's first write into it, never at open | [`graphics.md`](graphics.md) |
| G-15 | The Graphic sub-tab: what it shows for several clips, and what a write sends | [`graphics.md`](graphics.md) |
| G-16 | Insert ▸ Graphic: where the clip goes, what the module is called, and what a module that does not compile does | [`graphics.md`](graphics.md) |
| V-1 | Dev tools are compiled only under `REELCUT_DEV_TOOLS`; Distribution ships without them | [`dev-tools.md`](dev-tools.md) |
| V-2 | A dev tool is not an op, but goes through the catalog, gate and parity check like any tool | [`dev-tools.md`](dev-tools.md) |
| V-3 | Screens are captured with `cacheDisplay`, never ScreenCaptureKit | [`dev-tools.md`](dev-tools.md) |
| AI-1 | The assistant is a bundled helper, and the app never calls Anthropic itself | [`assistant.md`](assistant.md) |
| AI-2 | The helper owns no tools; every call goes through `AgentServer.execute` by way of one lane | [`assistant.md`](assistant.md) |
| AI-3 | The catalog and the gate are prepared at launch, not at `start()` | [`assistant.md`](assistant.md) |
| AI-4 | The Assistant is the inspector's fourth tab: Clip, Media, Document, Assistant | [`assistant.md`](assistant.md) |
| AI-5 | The assistant edits its own window's project | [`assistant.md`](assistant.md) |
| AI-6 | W-9 governs automatic styling, not a person's request | [`assistant.md`](assistant.md) |
| AI-7 | What the assistant may not call, and what it must ask about first | [`assistant.md`](assistant.md) |
| AI-8 | The key is the person's own, and is R6-5 and R6-12's key in everything but the vendor | [`assistant.md`](assistant.md) |
| AI-9 | History is append-only, and end-of-turn compaction is the one rewrite | [`assistant.md`](assistant.md) |
| AI-10 | Each tool call the assistant makes is its own undo step | [`assistant.md`](assistant.md) |
| AI-11 | The default model is `claude-opus-5-5` at medium effort | [`assistant.md`](assistant.md) |
| AI-12 | A tool call that arrives during a live gesture waits for mouse-up, then runs | [`assistant.md`](assistant.md) |
| AI-13 | The assistant's one base-URL override is `RC_ASSISTANT_BASE_URL`, and with it set no key file is opened | [`assistant.md`](assistant.md) |
| AI-14 | A selection change that is not a click on a clip leaves the Assistant tab showing; a click still shows Clip | [`assistant.md`](assistant.md) |
| AI-15 | The window's live context rides on each person message; the system prompt is fixed for a session | [`assistant.md`](assistant.md) |
