# Spec §11 — Decisions made — do not re-litigate

A decision here is binding: it is not re-litigated, and a phase that needs a new one records it
here BEFORE the code (root `CLAUDE.md`). The entries were one chronological list until
2026-09-26; they are now grouped by the work that made them, in their original order within
each file. **Find a decision by its ID in the table below, then read only that file.**

**Adding one:** append it to the file for the road map in progress (a new road map gets a new
file), in the style of its neighbours: a bold one-line decision, an ID if the road map numbers
them, then the reasoning and the risk it accepts. Add its row here in the same change.
The Lines cell is `wc -l`, and `make test` checks it (`tools/proof/spec_index_proof.py`).

| File | Lines | Holds |
|---|---|---|
| [`foundations.md`](foundations.md) | 111 | **Foundations (M1–M3, road map 2).** AVFoundation not ffmpeg, the compositor, one op entry point, overlap and ripple rules, ticks, `async` confinement, media by reference; R2-1. |
| [`recording.md`](recording.md) | 263 | **Screen recording (road map 3).** The recorder: what is in and out, files, grants, pause, the voice-over, Include Reelcut windows. |
| [`silence.md`](silence.md) | 49 | **Remove Silences (road map 4).** Silero VAD, its grid and cache, voice mode; S1-23. |
| [`effects-motion.md`](effects-motion.md) | 60 | **Transitions and motion (road map 5).** R5-1..R5-5, E2-27. |
| [`deepening.md`](deepening.md) | 1271 | **Deepening (road map 7).** D2-1, D3-1, #21, #22, D4-1..D4-6, D7-1..D7-3, #42, #88, #63, #174, #40, #43, #190, #87, #86, #178, #216, #216-R, #228-P, #228-V, #228-O, #232, #231, #233, #227, #234: how ops refuse, the op table, the gate, the source window, time envelopes, one-delta shifts on the canvas's grid, the non-edits that speak, a relink that re-probes, one frame on the grid, a tool that closes a document, a path one open document holds, a caption name's own extension, a speed of ×0.1–×1000 and the audio ceiling above ×12, a gain change on one audio track slews over 25 ms, a normalised export gained in float and quantised once, the cache passes' save gate's five accepted limits, the supplemental VP9/AV1 decoders and the one-frame import decode, the WebM/Matroska rewrap, its copy's progress window with Cancel, its Vorbis copy, the copy's original, the copy's movie timescale, an agent's `open_project` read off the main thread, the original an ffmpeg conversion records, the ffmpeg step's checked VP9 copy, and one document per path while a person's open is in flight. |
| [`cloud-captions.md`](cloud-captions.md) | 404 | **Cloud captions (road map 6).** R6-1..R6-24: AssemblyAI, keys, deletion, recovery, refusal precedence, a dripping server, a Stop's bound on a DELETE, a refused transcript's failed DELETE reported for the dashboard, cached transcripts not re-checked for the key, speaker colours on Subtitles, server strings checked whole and bounded, a transcript id the key cannot delete holding its media. |
| [`word-captions.md`](word-captions.md) | 406 | **Word captions (road map 8).** W-1..W-17. |
| [`chrome-inspector-keys.md`](chrome-inspector-keys.md) | 418 | **Chrome, the clip inspector and keys (the sharp pass, road map 9, #35).** SH-1..SH-5, CI-1..CI-16, K-1..K-3. |
| [`graphics.md`](graphics.md) | 1845 | **Graphics (road map 10).** G-1..G-35. |
| [`dev-tools.md`](dev-tools.md) | 41 | **Dev tools (road map 11).** V-1..V-3: the `REELCUT_DEV_TOOLS` flag and `make dist`, dev tools as ordinary tools, capture by `cacheDisplay`; V-4, V-5 (build velocity): Debug in the loop and Release for the recorded run, the Debug build as its own app, "Reelcut Debug". |
| [`assistant.md`](assistant.md) | 202 | **The Assistant (road map 12).** AI-1..AI-20: the bundled helper, one lane, the catalog at launch, the fourth tab, the window's own project, W-9's reach, withheld and ask-first tools, the key, history, undo, the model, a call mid-gesture, the base-URL override, the tab kept on a selection change, the live context on each message, Stop reaching a running export or transcribe, the selectable transcript and the multi-line composer, the dev-only compaction threshold a proof lowers, the dot on the Assistant tab's title while a question waits, and the person's chat settings. |
| [`pricing.md`](pricing.md) | 96 | **Pricing and spend (road map 13).** P-1..P-8: LiteLLM's table as the feed, a call priced from its own `usage` and `model` (per iteration), monthly dollar budgets per service, the app's spend as its own, the spend folder (ledger and price cache) that a proof never touches, the proofs' own ledger and how a paid proof request is held to the month's budget in it, and the two figures the app shows (the conversation's on the Assistant tab, the UTC month's in Settings), and a response cut short priced once and marked partial. |
| [`agent-connection.md`](agent-connection.md) | 68 | **Reaching the agent server (road map 14).** MC-1..MC-7: a Unix socket in its own `0700` `Agent` subfolder of the support folder and no TCP listener or switch, who binds it and who unlinks it, the bundled `reelcut-mcp` stdio server and when it launches Reelcut, no modal question from a tool call, the `RC_AGENT_SOCKET` override every proof sets, and Copy MCP Command's home in Settings. |
| [`publishing.md`](publishing.md) | 55 | **Publishing a build (Rasterize's pipeline, 2026-10-04).** PUB-1..PUB-5: GitHub Actions on the `publish` branch, the version and its `VERSION` file, Distribution archived and exported, the check before packing, the notarized DMG. |
| [`mattes.md`](mattes.md) | 175 | **Mattes (#240, road map "mattes").** MT-1..MT-9: a matte as a track relation in a closed vocabulary (`tracks[].matte`, format 14), what a matte cuts and when it cuts nothing, the four modes and where the cut is applied, a matte clip's own properties and the core's override of its blend, shadow and reflection, mattes in nests (the group key, `nest` and `unnest`), and how the compositor draws one (a matte target, one coverage texture at `texture(1)`), and the chrome (Track ▸ Matte, the header tag, the lane, the Clip tab's note), the pool's reuse within a frame and its 30-frame trim, a dissolve or zoom with a nested half drawn as two halves and mixed. |
| [`precision.md`](precision.md) | 114 | **Precision (issue batch B94, road map "precision").** PR-1..PR-5: the 16-bit-float working depth holding encoded values clamped to [0, 1], every video source decoded to `64RGBAHalf`, which exports carry the depth (ProRes deep, a `hevc_10bit` row, `hevc` pinned to Main, `h264` and `hevc_alpha` rounded to 8 bits first), `render_frame`'s depth following its sources, and what stays 8-bit with the frozen references' ±1 rule. |
| [`grading.md`](grading.md) | 425 | **Grading (road map "grading").** GR-1..GR-9: tier 1 of the grading experiment in, kept by the owner's verdict of 2026-10-10, and tiers 2–3 deferred as issues (amends §1), tone's nine keys under `video.color` at step 4c behind `toneEnabled` with exposure and white balance in local linear light and the Color sub-tab (Light, Color), grading on PR-1's float pipeline with encoded blending, the `ungraded` recipe option behind View ▸ Show Ungraded and the luma waveform panel (both view state, preview only), adjustment clips (a kind with no picture that grades what is behind it in its container, by its opacity, inert on a matte track, refused in a nest and in any transition), looks (`video.look`, eight built-ins defined in the core, baked on the GPU into a 33³ lattice and mixed at step 4d), `.cube` LUTs (media of kind `lut`, parsed by the core, applied as a look), and format 15, which reads a file numbered 1015 as 15. |
| [`grading-2.md`](grading-2.md) | 172 | **Grading tier 2 (road map "grading-2").** GR-10: scopes (an RGB parade, a Rec. 709 vectorscope centred on neutral with its 75 % targets and skin line, and an RGB-and-luma histogram) beside the waveform in two stacked slots of its panel, View ▸ Scopes, `render_frame`'s three booleans, the counting rule and a 1.1 ms bound per scope at 4K; GR-11: wheels (`video.wheels`, lift, gamma and gain as a Cartesian push and a master, step 4c.1 after tone and before the look, 128 floats, the Wheels section, format 16); GR-14: each phase merged into main alone with main's format numbers and no verdict phase; GR-12 and GR-13 are recorded before their phases' code. |

## Every decision

| ID | Decision | File |
|---|---|---|
| — | AVFoundation, not ffmpeg — amended by #216-R, amended by #227 | [`foundations.md`](foundations.md) |
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
| — | The recorder panel takes key only from an active Reelcut | [`recording.md`](recording.md) |
| — | A segment whose movie will not probe is left out | [`recording.md`](recording.md) |
| — | A left-out segment's readable microphone lands without its picture | [`recording.md`](recording.md) |
| — | File ▸ Pause Recording | [`recording.md`](recording.md) |
| — | A voice-over is a recording with no picture | [`recording.md`](recording.md) |
| — | Include Reelcut windows | [`recording.md`](recording.md) |
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
| #42 | A shift moves every clip it moves by ONE delta, counted on the canvas's own grid | [`deepening.md`](deepening.md) |
| #88 | A non-edit a rule declined names the rule's value; a clamp that lands where the clip was stays an identity; a list that applied answers applied — amended by #174 | [`deepening.md`](deepening.md) |
| #63 | A relink takes the new file's probe, and a media clip whose window runs past the file's end is held to it | [`deepening.md`](deepening.md) |
| #174 | One frame is the grid's own first frame at every rate, and the handle form counts grid frames | [`deepening.md`](deepening.md) |
| #40 | `close_project` closes a document as File ▸ Close does; `save_project {path}` and `new_project {path}` refuse a path another open document holds — amended by #234 | [`deepening.md`](deepening.md) |
| #43 | `export_captions` replaces only `srt`/`vtt` in a name; any other extension is part of it | [`deepening.md`](deepening.md) |
| #190 | A clip's speed runs ×0.1–×1000; above ×12, in both pitch modes, the plan leaves its audio out; one pitch per plan audio track; `set_speed` fits a duration | [`deepening.md`](deepening.md) |
| #87 | On one composition audio track a gain change with sound on both sides takes up to 25 ms — accepted; a track's first segment is held from time 0 — amended by #217 | [`deepening.md`](deepening.md) |
| #86 | A normalised export reads the mix as float, gains it and quantises once to the unchanged 16-bit encoder format; an un-normalised export keeps the Int16 decode | [`deepening.md`](deepening.md) |
| #178 | The cache passes' save gate has five accepted limits | [`deepening.md`](deepening.md) |
| #216 | Every process opts in to the supplemental VP9 and AV1 decoders; an import of a video track is a one-frame decode, refused only for no decoder or undecodable data, with a sentence naming the codec and no ffmpeg offer | [`deepening.md`](deepening.md) |
| #216-R | A WebM or Matroska file opens by a built-in rewrap: the core indexes it, Swift copies its first video and audio streams unchanged into a `.mov` under `Rewrapped/`, free space checked first, an undecodable codec refused before the copy and an uncopied one falling through to the opt-in ffmpeg step — amended by #228-V, amended by #228-O, amended by #232 | [`deepening.md`](deepening.md) |
| #228-P | A person's WebM or Matroska copy shows a progress window with Cancel after 1 s, never taking the keyboard from a Reelcut window; Cancel deletes the partial copy and adds nothing, with no alert; a tool call's copy shows nothing and answers as before — amended by #231 | [`deepening.md`](deepening.md) |
| #228-V | A WebM or Matroska file's Vorbis sound is copied as `vorb` with its CodecPrivate as the cookie, each packet counted by the overlap rule and every packet placed packet 0's count later; unreadable headers keep #216-R's refusal — amended by #232, amended by #235 | [`deepening.md`](deepening.md) |
| #228-O | A WebM or Matroska copy remembers its original (format version 11): the media is named after it, Reveal in Finder opens it, a relink to a WebM records the new one and any other file clears it, and a copy that is gone (or in the Trash) is copied again on open with no alert — amended by #231, amended by #233 | [`deepening.md`](deepening.md) |
| #232 | A WebM or Matroska copy's movie timescale is the least common multiple of 600 and its tracks' timescales, with a 31-bit guard and two fallbacks; it reaches only a copy written after it — amended by #235 | [`deepening.md`](deepening.md) |
| #231 | An agent's `open_project` reads off the main thread, on the lane's thread inside `withoutAsking`, and answers when the read ends, with no window and no question; other tool calls wait for it — amended by #234, amended by #235 | [`deepening.md`](deepening.md) |
| #233 | A file the opt-in ffmpeg step converts records the file it was made from as the media's `original`, as the built-in copy does; the re-copy on open stays the built-in copy's alone, never ffmpeg | [`deepening.md`](deepening.md) |
| #227 | The opt-in ffmpeg step copies a VP9 Profile 0 or 2 stream into an MP4-format file under the `.mov` digest name, snapped to its frame rate and kept only when every frame of the copy is on that grid; anything else, and any copy that fails, re-encodes as before — amended by issue batch B81 (the wait covers both attempts, one re-encode per file, no second attempt for a plan that copies no VP9) | [`deepening.md`](deepening.md) |
| #234 | While either side's read of a file is in flight, an agent's `open_project` and a person's open of it end as one document at the path, or the agent is refused by name after 30 s; `new_project {path}` and `save_project {path}` refuse a path being opened | [`deepening.md`](deepening.md) |
| R6-1 | The cloud engine is a second engine behind the same command, never a second command | [`cloud-captions.md`](cloud-captions.md) |
| R6-2 | Audio leaves the machine only by name, with the price in front of the person | [`cloud-captions.md`](cloud-captions.md) |
| R6-3 | The transcript is a per-media asset in the package | [`cloud-captions.md`](cloud-captions.md) |
| R6-4 | What was uploaded is deleted by us, immediately, and the fact is recorded | [`cloud-captions.md`](cloud-captions.md) |
| R6-5 | The app never holds an AssemblyAI key of Reelcut's | [`cloud-captions.md`](cloud-captions.md) |
| R6-6 | The protocol boundary is the base URL and the credential | [`cloud-captions.md`](cloud-captions.md) |
| R6-7 | No `async` exception | [`cloud-captions.md`](cloud-captions.md) |
| R6-8 | A fallback to Universal-2 is allowed and REPORTED | [`cloud-captions.md`](cloud-captions.md) |
| R6-9 | A proof-launched app never opens the person's stored key | [`cloud-captions.md`](cloud-captions.md) |
| R6-10 | The caption path clamps a clip's `speed` at BOTH ends, because the reader does not — amended by #41: the reader refuses a speed outside ×0.1–×10 (×0.1–×1000 since #190), and the clamps stay | [`cloud-captions.md`](cloud-captions.md) |
| R6-11 | A media whose remote delete this run could not confirm is not uploaded again in this run | [`cloud-captions.md`](cloud-captions.md) |
| R6-12 | The key and the region are a PERSON's settings, and no tool reads or writes either | [`cloud-captions.md`](cloud-captions.md) |
| R6-13 | The estimate never counts a HELD media as "to upload", and never hides its price | [`cloud-captions.md`](cloud-captions.md) |
| R6-14 | A lost submit reply permits bounded recovery, never another paid submit | [`cloud-captions.md`](cloud-captions.md) |
| R6-15 | A transcript marker identifies audio and the request, not display caches | [`cloud-captions.md`](cloud-captions.md) |
| R6-16 | A current transcript batch may be reused without credentials | [`cloud-captions.md`](cloud-captions.md) |
| R6-17 | `transcribe`'s seven refusals have one precedence, and the answer is the winner's own sentence | [`cloud-captions.md`](cloud-captions.md) |
| R6-18 | A request's only timeout is an idle one; a server that drips holds it for as long as it drips (accepted) | [`cloud-captions.md`](cloud-captions.md) |
| R6-19 | A Stop bounds a DELETE; it never skips one | [`cloud-captions.md`](cloud-captions.md) |
| R6-20 | A transcript refused after it was made, whose DELETE failed, is reported for the dashboard and never retried | [`cloud-captions.md`](cloud-captions.md) |
| R6-21 | A cached transcript is not re-checked for the key when it is read (accepted) | [`cloud-captions.md`](cloud-captions.md) |
| R6-22 | With Speakers on, each speaker's Subtitles cues are their own colour, and nothing else marks them | [`cloud-captions.md`](cloud-captions.md) |
| R6-23 | Every string a server sends is checked for the key whole, and every one the app relays is bounded | [`cloud-captions.md`](cloud-captions.md) |
| R6-24 | A transcript id the person's key cannot delete holds its media for ever (accepted) | [`cloud-captions.md`](cloud-captions.md) |
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
| W-12 | A sliding pill, an in-word fill and a dim in a pause are three keys of `word_style`, not modes; format version 12 | [`word-captions.md`](word-captions.md) |
| W-13 | The recipe's `word_glide`, `word_fill` and `word_dim`: no second index, a word fills in at most 0.6 s, a pause under 0.25 s does not dim | [`word-captions.md`](word-captions.md) |
| W-14 | How the three are drawn: a gliding pill under every word's ink, a hard fill edge, one opacity that leaves the backdrop alone — amended by W-16, W-17 | [`word-captions.md`](word-captions.md) |
| W-15 | The three looks are three remembered checkboxes in the Generate Captions sheet and `transcribe`'s `slide` / `fill` / `dim`: live by style, greyed not hidden, a `true` that would show nothing refused, `false` always accepted | [`word-captions.md`](word-captions.md) |
| W-16 | The dim is the text layer's opacity in the compositor on a page with no backdrop, and one transparency layer in the bitmap on a page with one; the recipe and its hash unchanged — amended by W-17 | [`word-captions.md`](word-captions.md) |
| W-17 | On a timed page with a backdrop the words are drawn first, a dim is one multiply of the bitmap and the backdrop is composited under them; a backdrop's fully covered pixels are written by vImage | [`word-captions.md`](word-captions.md) |
| SH-1 | `StickerButton` keeps its pill — superseded by SH-4 | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| SH-2 | `BlockSliderCell.drawBar` is forked from Rasterize's copy | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-1 | The selected action is the SIXTH piece of view state | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-2 | The editing target is the selected action, not the playhead | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-3 | Pan, mono, compressor, noise reduction, duck and keep-pitch go to the BASE props whatever is selected | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-4 | Mint is the action ink, and nothing else uses it | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-5 | The Clip tab is sub-tabs over a pinned block — amended by GR-2 | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-6 | `◆N` counts KEYS, and the slider knob is the block — amended by GR-2 | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-7 | Every inspector row carries the 14 pt mark gutter, and the label stays 76 | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-8 | A section the selected action keys opens once per selection, and a person's close sticks | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-9 | Reset shows only while a section differs from its default, and with an action selected the same slot reads Clear | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-10 | A person's refusal is shown, in the core's own sentence, at the inspector's foot | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-11 | A band is dragged: its body moves the action, its outer 5 pt resize it, in the timeline's lane and the Clip tab's lane alike | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-12 | The Clip tab's lane carries the clip's transition hatch, fades and motion wedges, and its Curve popup a glyph and the short names | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-13 | The canvas's handles follow the mode | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-14 | `set_action_end.off` keys an optional property OFF at the end | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-15 | Every sub-row carries `mixed`, and the collapse is the one animation — amended by #102: a section header's hover fades too | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| CI-16 | The selected clip's obscure regions are drawn and dragged on the canvas; the layer's own handles outrank them, an armed modal mode's overlay takes every press over them, and Esc cancels any canvas drag | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| K-1 | Space is the transport's unless the first responder is typing or claims it | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| K-2 | In the canvas text editor Return applies, a modified Return is a new line, and Esc asks before dropping a change | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| K-3 | The canvas text editor lays its text out with the renderer's attributes at view scale; an UPPERCASE text is edited as typed | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| SH-3 | An inspector name field is the inspector's value field | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| SH-4 | `StickerButton` is Rasterize's square block, drawn in place | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| SH-5 | Settings' explanations are an info button's AppKit `NSPopover`, which keeps its own rounded bubble | [`chrome-inspector-keys.md`](chrome-inspector-keys.md) |
| G-1 | A graphic is a SOURCE, not an effect; R5-1 stands for effects | [`graphics.md`](graphics.md) |
| G-2 | The engine is a separate Rust crate; the core crate keeps its two rules | [`graphics.md`](graphics.md) |
| G-3 | A graphic's source is a FILE in the package, and is not an undo step — its price amended by G-29 | [`graphics.md`](graphics.md) |
| G-4 | The core checks props against the schema the OP carries; render time is lenient | [`graphics.md`](graphics.md) |
| G-5 | A graphic is a pure function of its inputs (R5-5 for code) | [`graphics.md`](graphics.md) |
| G-6 | Fonts: the app's bundled faces and the package's, never the system's | [`graphics.md`](graphics.md) |
| G-7 | A graphic draws at its own size, and crosses the FFI as premultiplied BGRA | [`graphics.md`](graphics.md) |
| G-8 | A failing graphic shows its error in preview, answers it to the agent, and stops an export | [`graphics.md`](graphics.md) |
| G-9 | A graphic has its own timeline: `in` and `length`, and `split` pins it | [`graphics.md`](graphics.md) |
| G-10 | Props are not action targets; everything about the LAYER is — props superseded by G-34, its paste sentence amended by G-32 | [`graphics.md`](graphics.md) |
| G-11 | Plain JavaScript, one ES module, no TypeScript | [`graphics.md`](graphics.md) |
| G-12 | Colours in props are CSS strings | [`graphics.md`](graphics.md) |
| G-13 | The revision is a content hash, and an export pins it | [`graphics.md`](graphics.md) |
| G-14 | `graphics/` is created on the app's first write into it, never at open | [`graphics.md`](graphics.md) |
| G-15 | The Graphic sub-tab: what it shows for several clips, and what a write sends | [`graphics.md`](graphics.md) |
| G-16 | Insert ▸ Graphic: where the clip goes, what the module is called, and what a module that does not compile does | [`graphics.md`](graphics.md) |
| G-17 | An export's Cancel only sets flags; a reader is cancelled only by the loop that reads it, and a read that never returns is not woken — accepted | [`graphics.md`](graphics.md) |
| G-18 | A graphic's own timeline moves with a transition's head and crosses a frame grid; a graphic with no description is tolerated | [`graphics.md`](graphics.md) |
| G-19 | render_graphic's svg takes no sheet arguments and draws past the length; the library files' watch is capped; the untitled roots are removed | [`graphics.md`](graphics.md) |
| G-20 | Every file source shares G-19 (c)'s limit, modules first; a failed open is a scan warning; render answers at most 8 MiB of SVG; the png sheet draws at most 134,217,728 px; graphic_reference checks a project it is given | [`graphics.md`](graphics.md) |
| G-21 | A thread holds at most 16 graphic engines, least recently used dropped first; a module's top-level warnings are its compile's | [`graphics.md`](graphics.md) |
| G-22 | `measureText` and `textLines` take `xmlSpace`; whitespace-only text measures zero | [`graphics.md`](graphics.md) |
| G-23 | An asset's name is one `asset(name)` can use; a bad one is renamed as it is copied in and skipped by the scan; a font file unchanged on disk is not read again | [`graphics.md`](graphics.md) |
| G-24 | A graphic's warnings show where its other messages do: compile warnings in the module's diagnostics, scan warnings in `get_graphic {}` and the Source section, an export's in its answer, sheet and queue row | [`graphics.md`](graphics.md) |
| G-25 | A colour default is G-12's: refused at compile by the engine and the core, read by the Inspector through `rc_normalise_color` | [`graphics.md`](graphics.md) |
| G-26 | An export rasterizes its graphics ahead on worker threads; the compositor stays the one writer and the texture key decides | [`graphics.md`](graphics.md) |
| G-27 | Deleting a graphic is refused while a clip draws it, naming the clips; the deleted text is kept, not trashed, and a file-less name with kept revisions is a deleted module | [`graphics.md`](graphics.md) |
| G-28 | Renaming a graphic moves the file, its kept revisions and every clip that names it as one undo step; a name in use by a file or by a clip is refused; Undo renames the file back, except onto a deleted name; refused with a nest open | [`graphics.md`](graphics.md) |
| G-29 | The last 10 texts of each module are kept in `graphics/history/` inside the package; `restore_graphic` brings one back and keeps what it replaced; amends G-3's price | [`graphics.md`](graphics.md) |
| G-30 | File ▸ Rename Graphic…, Delete Graphic… and Restore Graphic Version… are one small sheet over the three bodies; a refusal is the body's sentence shown in the sheet, which stays up; no second confirmation; where each opens and when each is greyed | [`graphics.md`](graphics.md) |
| G-31 | The standard library measures a path — `getLength`, `getPointAtLength`, `evolvePath` — in JavaScript: a curve as 64 chords, within 0.01 % on the reference shapes; a draw-on dashed by the longest subpath, padded 0.1 %; the last paths memoised per engine; a path that would answer `Infinity` or NaN is refused, never answered | [`graphics.md`](graphics.md) |
| G-32 | `paste_attributes` takes a fifth group, `graphic`: a clip's props copied whole onto clips drawn by the same module, the target keeping its module, size and timeline; never in the default set (⌥⌘V is unchanged); `skip_missing` skips what cannot take a named group instead of refusing; the copied map is read only when a target takes it; Edit ▸ Paste Graphic Properties is the person's door; amends G-10's paste sentence; (e) amended by G-34: a target key an action on the target names is kept | [`graphics.md`](graphics.md) |
| G-33 | On an export row that needs even pixel dimensions the core resolves and lists the even size the file will have — an odd edge one pixel smaller, the Document row named "Document (even)" — so the sheet and the `export` tool report the file's size and no size of the canvas's own shape is refused for being odd; `hevc_alpha`, "HEVC with Alpha (MOV)", is a tenth row whose frames carry the canvas's alpha; every movie row fills the frame instead of padding it when the miss is within a pixel or the frame is a canvas-shaped size less a pixel (one integer test, shared with the alpha guard), and letterboxes or, on an alpha row, refuses past that; a missing encoder is the preset's own sentence and no file; `RC_FORMAT_VERSION` stays 11; amended by #243: the export sheet 60 pt wider and its footnote on a line of its own above the buttons, so every footnote measured, the default rows and the longest two, is drawn whole; amended by G-35: the two alpha movie rows are written straight and labelled so, and Reelcut reads a video frame's declared alpha mode | [`graphics.md`](graphics.md) |
| G-34 | A graphic's props are action targets: a number and a colour (channel by channel, straight alpha) ramp, a string, boolean or enum switches at the end, an asset is refused; the kind comes from the schema the op carries and is stored in the end's `kinds` (a caller's `kinds` is discarded); a named prop is range-checked, a stored end never re-checked; a prop the clip lacks starts from the schema's current default, written in the same step, and a paste keeps an animated start (amends G-32 (e)); numbers arrive fractional; `RC_FORMAT_VERSION` 13; supersedes G-10's first sentence | [`graphics.md`](graphics.md) |
| G-35 | A video frame is composited as premultiplied only when its buffer's alpha-mode attachment says `PremultipliedAlpha`, an unlabelled one as straight; `prores_4444` and `hevc_alpha` are written straight — each frame un-premultiplied in integers (exact for 8 bits), each transparent pixel within 4 px of a visible one filled with the nearest one's colour, every buffer labelled `StraightAlpha` and `hevc_alpha`'s encoder key straight; `RC_FORMAT_VERSION` unchanged, no migration (the owner's "do both", #242); amends G-33 (d) and (h); amended by PR-3 (`prores_4444` un-premultiplied in float, `hevc_alpha` rounded to 8 bits first) | [`graphics.md`](graphics.md) |
| V-1 | Dev tools are compiled only under `REELCUT_DEV_TOOLS`; Distribution ships without them — amended by V-4 | [`dev-tools.md`](dev-tools.md) |
| V-2 | A dev tool is not an op, but goes through the catalog, gate and parity check like any tool | [`dev-tools.md`](dev-tools.md) |
| V-3 | Screens are captured with `cacheDisplay`, never ScreenCaptureKit | [`dev-tools.md`](dev-tools.md) |
| V-4 | The edit loop and mutant tiers drive a Debug app; the run a phase records, the gate's build and every `release_only` proof are Release | [`dev-tools.md`](dev-tools.md) |
| V-5 | The Debug build is its own app, "Reelcut Debug" (`com.kgalligan.Reelcut.debug`, an Alternate `.reelcut` handler), through Debug-only settings read by `:default=`; `PRODUCT_NAME`, the support folder and its keys stay shared | [`dev-tools.md`](dev-tools.md) |
| AI-1 | The assistant is a bundled helper, and the app never calls Anthropic itself | [`assistant.md`](assistant.md) |
| AI-2 | The helper owns no tools; every call goes through `AgentServer.execute` by way of one lane | [`assistant.md`](assistant.md) |
| AI-3 | The catalog and the gate are prepared at launch, not at `start()` | [`assistant.md`](assistant.md) |
| AI-4 | The Assistant is the inspector's fourth tab: Clip, Media, Document, Assistant | [`assistant.md`](assistant.md) |
| AI-5 | The assistant edits its own window's project | [`assistant.md`](assistant.md) |
| AI-6 | W-9 governs automatic styling, not a person's request | [`assistant.md`](assistant.md) |
| AI-7 | What the assistant may not call, and what it must ask about first — amended by #40 | [`assistant.md`](assistant.md) |
| AI-8 | The key is the person's own, and is R6-5 and R6-12's key in everything but the vendor | [`assistant.md`](assistant.md) |
| AI-9 | History is append-only, and end-of-turn compaction is the one rewrite — amended by AI-20 | [`assistant.md`](assistant.md) |
| AI-10 | Each tool call the assistant makes is its own undo step | [`assistant.md`](assistant.md) |
| AI-11 | The default model is `claude-opus-5-5` at medium effort | [`assistant.md`](assistant.md) |
| AI-12 | A tool call that arrives during a live gesture waits for mouse-up, then runs | [`assistant.md`](assistant.md) |
| AI-13 | The assistant's one base-URL override is `RC_ASSISTANT_BASE_URL`, and with it set no key file is opened | [`assistant.md`](assistant.md) |
| AI-14 | A selection change that is not a click on a clip leaves the Assistant tab showing; a click still shows Clip | [`assistant.md`](assistant.md) |
| AI-15 | The window's live context rides on each person message; the system prompt is fixed for a session | [`assistant.md`](assistant.md) |
| AI-16 | Stop stops a running `export` or on-device `transcribe`; any other running call finishes | [`assistant.md`](assistant.md) |
| AI-17 | The transcript is one selectable text, and the composer is multi-line with K-2's Return | [`assistant.md`](assistant.md) |
| AI-18 | A proof lowers the end-of-turn compaction threshold with the dev-only launch default `-RCDevAssistantAutoCompact <tokens>`; the shipped threshold stays 300 000 — amended by AI-20 | [`assistant.md`](assistant.md) |
| AI-19 | While the window's assistant waits on an ask-first question, the Assistant tab's title wears a dot, whichever tab is showing | [`assistant.md`](assistant.md) |
| AI-20 | The chat settings are the person's, in Settings' Assistant pane, and a change reaches an open conversation without ending it | [`assistant.md`](assistant.md) |
| P-1 | Prices come from LiteLLM's table; only AssemblyAI's rate is hand-kept; Anthropic's page is the cross-check | [`pricing.md`](pricing.md) |
| P-2 | A call is priced from the response's own `usage` and `model`, per `iterations` entry; unknown is never $0 | [`pricing.md`](pricing.md) |
| P-3 | Budgets are dollars per calendar month per service, enforced by the proofs at the worst case | [`pricing.md`](pricing.md) |
| P-4 | Spend shown in the app is Reelcut's own, and says so | [`pricing.md`](pricing.md) |
| P-5 | The spend ledger and the price cache are the person's, in the spend folder; a proof never touches them | [`pricing.md`](pricing.md) |
| P-6 | The proofs' ledger is `~/Library/Application Support/Reelcut Proofs/spend.jsonl`; every paid proof request is reserved at its worst case there and refused past the month's budget | [`pricing.md`](pricing.md) |
| P-7 | The app shows the conversation's cost on the Assistant tab and the UTC month's, folded from the ledger, in Settings; unpriced and unreadable lines are counted, never $0 | [`pricing.md`](pricing.md) |
| P-8 | A response cut short is priced once, from what its stream had reported, and marked partial | [`pricing.md`](pricing.md) |
| MC-1 | The agent server listens only on a Unix socket, `~/Library/Application Support/Reelcut/Agent/agent.sock`, always while the app runs; no TCP listener and no switch | [`agent-connection.md`](agent-connection.md) |
| MC-2 | The socket is bound only in its own `Agent` subfolder of the support folder, made `0700` and checked for mode and owner (the support folder's own mode is not), and only by the first instance; a socket that answers is left alone, a refused one is a leftover and is unlinked | [`agent-connection.md`](agent-connection.md) |
| MC-3 | External MCP clients reach Reelcut through `reelcut-mcp`, a Rust stdio server inside the bundle | [`agent-connection.md`](agent-connection.md) |
| MC-4 | `reelcut-mcp` never launches Reelcut to answer `initialize` or `tools/list`; the first `tools/call` that finds no socket launches its own bundle in the background, one instance between proxies (`agent.launch.lock` beside the socket); a session whose launch timed out launches no other | [`agent-connection.md`](agent-connection.md) |
| MC-5 | A tool call never raises a modal question; a click still does | [`agent-connection.md`](agent-connection.md) |
| MC-6 | `RC_AGENT_SOCKET` overrides the socket path, a proof always sets it, and `reelcut-mcp` honours it and passes it on (with `-ApplePersistenceIgnoreState YES` and a launch log beside the socket); the interim port rule went with `RC_AGENT_PORT` in MC4 | [`agent-connection.md`](agent-connection.md) |
| MC-7 | Copy MCP Command is a button in Settings' MCP section, the window's first, under a visible blurb and the helper's path, enabled exactly while the helper is executable, with no MCP mirror; the Tools menu is gone | [`agent-connection.md`](agent-connection.md) |
| PUB-1 | A build for another person's Mac is made only by GitHub Actions on a push to `publish`: a Developer ID-signed, notarized, stapled DMG on a GitHub Release; local builds stay ad-hoc signed | [`publishing.md`](publishing.md) |
| PUB-2 | The version is `<MAJOR.MINOR>.<run number>`, the build number is the run number, and the base is the `VERSION` file, as in Rasterize | [`publishing.md`](publishing.md) |
| PUB-3 | What is published is the Distribution configuration, archived and then exported with the `developer-id` method | [`publishing.md`](publishing.md) |
| PUB-4 | The exported app is checked by `published_check.py` before it is packed, and a failed row publishes nothing | [`publishing.md`](publishing.md) |
| PUB-5 | The DMG is what is notarized and stapled, with an App Store Connect API key | [`publishing.md`](publishing.md) |
| MT-1 | A matte is a track relation in a closed vocabulary (`none`, `alpha`, `alpha_inverted`, `luma`, `luma_inverted`), set by `set_track {matte}`, drawn by the one compositor; a matte track's clips are never drawn and any clip that draws can be one; `tracks[].matte` written only when not `none`, format 14, no migrate step | [`mattes.md`](mattes.md) |
| MT-2 | A matte cuts the track directly behind it in its own container unless that track is a matte track; with no target it cuts nothing and still draws nothing; where it shows nothing the track behind shows uncut; read per instant, no clip names another; its clips still sound | [`mattes.md`](mattes.md) |
| MT-3 | `alpha`, `alpha_inverted`, Rec. 709 `luma` of the premultiplied colour and `luma_inverted`, in encoded sRGB, multiply the matted layer's coverage at step 7 at its own canvas position — so its shadow and its reflection are cut where they land — and the outgoing half of a dissolve multiplies its partner's cover by the same value; `TrackMatte` is a shader discriminant, append only | [`mattes.md`](mattes.md) |
| MT-4 | A matte clip's placement, crop, colour, filters, motion, actions and transitions shape the matte; its blend mode, drop shadow and reflection do nothing, the core emitting `normal`, `null`, `null` (the recipe's second deliberate override); amends G-10 for a graphic on a matte track | [`mattes.md`](mattes.md) |
| MT-5 | In nests the first matte level walking outward decides where a layer draws, every inner target level cuts it; a matte is keyed by (enclosing nest-clip path, matte track id); `nest` and `unnest` count from the front-most non-matte track and carry a matte only with its target | [`mattes.md`](mattes.md) |
| MT-6 | Each listed matte is drawn into a destination-sized `bgra8Unorm` target before the destination pass, each set of mattes resolved into one `r8Unorm` coverage sampled at `texture(1)`; an unmatted layer binds the 1×1 white placeholder there (MT0's spike); `LayerUniforms` stays 104 floats; amended by PR-1 (`rgba16Float`) | [`mattes.md`](mattes.md) |
| MT-7 | Set by Track ▸ Matte and the track context menu's Matte submenu (Off, Alpha, Inverted Alpha, Luma, Inverted Luma), undo "Track Matte", no toggle or shortcut; the header's tag in the label colour on an accent tint ("Matte · <mode>", dimmed "Matte · nothing behind"), the lane at half opacity with dashed outlines and a bracket to its target, the Clip tab's note, a matte clip the topmost canvas hit | [`mattes.md`](mattes.md) |
| MT-8 | A `cross_dissolve` or `zoom` whose container is a nest, or one of whose clips is a nest clip, is ROUTED: each half drawn with no dissolve weight into its own destination-sized target, then one full-frame pass mixes them (1 − p)·out + p·in, a zoom's halves scaled there about their anchors; the core decides it (the layer's `dissolve`, never its `transition`; `normal`); a matte layer keeps only the dissolves at or inside its first matte level; a timeline pair of non-nest clips keeps MT-3's correction; push, slide, wipe and the fades are not routed; amended by PR-1 (`rgba16Float`) | [`mattes.md`](mattes.md) |
| MT-9 | A frame's mattes are planned first (`MattePlan`): each cut set resolved once its last matte is drawn, a matte's composite given back to the pool once every cut set naming it is resolved; the pool keeps, of each kind, the most any of the renderer's last 30 frames held (a frame is one `render` call) and releases the rest; no cap, a target Metal cannot make fails the frame; amends MT-6's pooling sentence; amended by PR-1 (`rgba16Float`) | [`mattes.md`](mattes.md) |
| PR-1 | The working depth is 16-bit float holding encoded values clamped to [0, 1]: `64RGBAHalf` render-context buffers, `rgba16Float` destination, matte composites, routed dissolve halves, shadow pair and layer, blend, shadow and dissolve pipeline attachments; the coverage stays `r8Unorm` and the placeholder `bgra8Unorm`; the source sample, blend and dissolve `saturate`d; blending in encoded sRGB; the preview shows the same buffers, no EDR or HDR; amends MT-6, MT-8 and MT-9's figures; the measured memory (heavy 4K export +851.7 MB) accepted by the owner | [`precision.md`](precision.md) |
| PR-2 | Every video source decodes to `64RGBAHalf`, wrapped as `rgba16Float`; #216's 32BGRA import check stands; HDR stays tone-mapped (`supportsHDRSourceFrames` false) | [`precision.md`](precision.md) |
| PR-3 | The export reader's frames are `64RGBAHalf`; `prores_422` and `prores_4444` take them as they are; a new `hevc_10bit` row (Main 10, after `hevc_alpha`, even-sized, no alpha, HEVC's tiers); `hevc` pinned to Main; `h264` and `hevc` rounded to 8-bit BGRA first; amends G-35 (c): `prores_4444` un-premultiplied in place in float, `hevc_alpha` rounded to 8-bit premultiplied BGRA then straightened unchanged | [`precision.md`](precision.md) |
| PR-4 | `render_frame`, Save Frame…, GIF and APNG frames are the generator's CGImage: 8-bit when every source is 8-bit, 16-bit float when any is deeper; today's behaviour written down; no `depth` argument; JPEG stays 8-bit | [`precision.md`](precision.md) |
| PR-5 | Graphics, text, shapes, word captions, stills, thumbnails, the reversed-clip intermediate, screen recordings and the `r8` coverage stay 8-bit; HDR/EDR, wide gamut, linear light and the 10-bit rest deferred; a frozen reference compares decoded pixels within ±1, or prints its digest unscored | [`precision.md`](precision.md) |
| GR-1 | The grading experiment: tier 1 (tone, adjustment clips, looks, LUT import, Show Ungraded, one waveform) IN and kept by the owner's verdict; flip and the shape mask out of it; tiers 2 and 3 filed as issues; amends spec §1's non-goal and "scopes", and reverses road map 2 §4's LUT exclusion. Verdict (owner, 2026-10-10): kept, merged into main; tiers 2 and 3 deferred as issues, not out | [`grading.md`](grading.md) |
| GR-2 | Tone: `video.color` gains `exposure` (±3 EV), `temperature`, `tint`, `highlights`, `shadows`, `whites`, `blacks`, `vibrance` (±1) and `fade` (0…1), written only when not 0, applied at step 4c after the obscure regions behind `toneEnabled` (116 floats); exposure and white balance in local linear light, not amending §7.5 or PR-5; the Color sub-tab (Light, Color) for source-pixel clips; amends CI-5 and CI-6 — amended by GR-11 | [`grading.md`](grading.md) |
| GR-3 | Grading runs on PR-1's float pipeline; blending stays encoded (§7.5) | [`grading.md`](grading.md) |
| GR-4 | The `ungraded` recipe option neutralises all thirteen `video.color` keys on every layer; View ▸ Show Ungraded (⌃⌘U) sets it on the window's preview only, with an "Ungraded" tag; never an export, Save Frame, the eyedropper or an un-asked `render_frame`; not persisted — amended by GR-11 | [`grading.md`](grading.md) |
| GR-5 | The luma waveform (View ▸ Waveform, ⌃⌘W): Rec. 709 Y′ of the composited preview frame, 256 × 256, clip marks at levels 255 and 0 over 0.5 % of a column, two readouts, a fixed 248 pt panel beside the preview, a latest-wins tap run only while shown; `render_frame {waveform}` its mirror; no export path; not persisted — amended by GR-10 | [`grading.md`](grading.md) |
| GR-6 | Adjustment clips: `Source::Adjustment` and `add_adjustment_clip`; its colour, point filters and opacity (strength) grade everything drawn behind it in its container, by the eighth pipeline (blending off, reads the destination); inside the matte when matted, inert on a matte track (corrects the road map); refused in a nest, in every transition and overlap, and with blur, sharpen, pixelate or a blend, each in its own sentence; Show Ungraded neutralises it; Insert ▸ Adjustment Clip and the Color/Clip inspector (built); the format stays 1015 (amends GR-9) — amended by GR-11 | [`grading.md`](grading.md) |
| GR-7 | Looks: `video.look {kind, amount}` (amount 0–1, 1 by default, refused outside); eight built-ins — Warm, Cool, Teal & Orange, Vivid, Faded, Vintage, Dramatic, Black & White — defined in the core as Color, Light and split-tone values; baked on the GPU into a 33³ `rgba16Float` lattice (LRU of 8) and mixed at step 4d after tone, at `texture(2)` behind `lookEnabled`, a 2³ identity placeholder otherwise; Show Ungraded and the eyedropper remove it; `amount` animates, `kind` switches at the end; no new op or tool, the format stays 1015; the Look section, its gallery and Clip ▸ Look ▸ — amended by GR-11 | [`grading.md`](grading.md) |
| GR-8 | `.cube` LUTs: a LUT is media of kind `lut` (referenced, relinked, consolidated, never placed as a clip), parsed by the core (3D, sizes 2–65, default domain only, refused by name otherwise), applied as `video.look {kind: "lut", media, amount}` at step 4d to encoded values, trilinear; a missing LUT draws ungraded; Remove clears the looks; Show Ungraded removes it; AVFoundation reads only the `colr` atom and converts no HLG or PQ transfer (T0), log unchecked; no new op or tool, the format stays 1015; [b] the gallery's Imported group and Clip ▸ Look ▸'s LUT items | [`grading.md`](grading.md) |
| GR-9 | The grading branch wrote format 1015 (main's 14 plus a thousand) and refused 15–1014 by name; at the merge 1015 became 15, a file numbered 1015 is read as 15 by one migration step, the base-version constant and the gap refusal are gone, and 16 and above, 1014 included, are newer | [`grading.md`](grading.md) |
| GR-10 | Scopes: an RGB parade, a Rec. 709 vectorscope (256 × 256 bins centred on neutral, the six 75 % targets and the skin line at 123.3° from the matrix) and an R′G′B′Y′ histogram, read from GR-5's frame by its tap; never a global atomic per pixel into a shared counter; each ≤ 1.1 ms of GPU per 4K frame at its worst over five fixtures (replacing #263's bound); two stacked slots with pickers in the 248 pt panel, Waveform over Vectorscope, not persisted, both shrinking to fit a short pane and the bottom hidden below 360 pt (amended in G2-1); View ▸ Scopes (⌃⌘W); `render_frame {parade, vectorscope, histogram}` writing `<path>.<scope>.json`; no export path; amends GR-5 | [`grading-2.md`](grading-2.md) |
| GR-11 | Wheels: `video.wheels {lift, gamma, gain}`, each `{x, y, master}` (−1…1, x² + y² ≤ 1 to 1e-9), written only when not 0, refused not clamped, an action's end clamped onto the rim; step 4c.1 after tone and before the look, in the layer stage and the adjustment pass, lift then gain then gamma on encoded values with Reelcut's strengths (k 1, lift 0.25, gain 0.5, gamma 1), luma-neutral on a grey pixel only; 128 floats behind `wheelsEnabled`; `ungraded` neutralises them; the Wheels section (three discs rotated to the vectorscope's hues, master strips, ⌥ a tenth, no push field); format 16; amends GR-2, GR-4, GR-6, GR-7 | [`grading-2.md`](grading-2.md) |
| GR-14 | Tier 2's working arrangement: each phase gated in the `grading-2` worktree and merged into main alone; main's format numbers (16, 17, 18), renumbered before a merge if main moved; no verdict phase | [`grading-2.md`](grading-2.md) |
