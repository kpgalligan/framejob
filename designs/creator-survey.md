# Creator survey: what would make Frame Job a leading creator editor

## Summary

This survey is dated 1 November 2026. It asks what would make Frame Job a leading editor for content creators. It draws on five inputs:

- an inventory of the tree;
- four research sweeps (creator tools, pro editors, screen and tutorial tools, creator demand);
- three strategists' proposals;
- the candidates merged from those proposals;
- adversarial checks of each candidate against the code, Apple's frameworks and the market.

Frame Job is already ahead of most creator tools on finishing: its audio chain, colour and HDR, codecs, and an MCP surface that covers the whole editor. It loses creators earlier, at the jobs that now define a creator editor:

- cutting a talk by its transcript;
- polishing a screen recording from the cursor;
- turning a horizontal edit into vertical shorts;
- finding the clips worth posting;
- switching podcast angles by speaker;
- cutting the presenter out of the background.

Agent access no longer sets a tool apart, because most AI-forward editors gained an MCP server in 2026. No rival combines what Frame Job has: a full editor whose every edit is a pure, undoable op, analysis that runs on the creator's Mac, and AI on the creator's own key with no credits.

The recommendation is to ship those creator jobs as on-device commands whose results land as ordinary edits on the timeline, in the order below. The rest is either table stakes to pick up later or not worth chasing.

## What Frame Job has

Frame Job is a native macOS editor for Apple Silicon, macOS 26 or later. It is a Swift/AppKit app over a Rust core, Apache-2.0, with no account and no backend. As of 1 November 2026 it has the following.

- **Editing.** One kind of track. Move, trim, slip, roll, rate-stretch, split, lift, ripple delete, insert and overwrite. Nests. Picture and sound linked for J- and L-cuts. Markers with a chapter flag. A second preview window. Every edit is one undo step through one mutation point, and a refused edit says why in the rule's own sentence.
- **Picture.** Transform, crop, blend modes, chroma key, spotlight, obscure regions, text with reveals, shapes with gradients, blurred backgrounds, and matte tracks that let any clip cut the track behind it. Actions animate almost every property, including speed, which is how speed ramps work. 13 transitions, and Zoom to Region for screencasts.
- **Audio.**
  - A per-clip chain: voice isolation, EQ, hum and noise reduction, gate, a phrase-level leveller, de-esser, compressor and true-peak limiter.
  - Enhance Voice, Match Audio, Normalize to LUFS, Duck by Speech, and Synchronize Audio with drift correction.
  - Track compressor and limiter, a live loudness meter, stems, and a −1 dBTP master on every export.
- **Clean-up.** Remove Silences (on-device Silero VAD), Remove Filler Words (AssemblyAI word timings; cloud-only), and `get_transcript`. The Assistant cuts false starts when asked.
- **Captions.** On-device or AssemblyAI transcription. Subtitles plus five word-by-word styles and three looks. SRT and WebVTT export; SRT import.
- **Colour and HDR.**
  - Grading: wheels, curves, hue curves, looks, .cube LUTs, adjustment clips with qualifiers, and four scopes.
  - Log footage: Apple Log (detected on import), S-Log3, V-Log and Canon log.
  - HDR: HLG projects with HLG, HDR10 and SDR deliverables, on a 16-bit float compositor.
- **Graphics.** Sandboxed JavaScript modules that return SVG per frame, 23 bundled templates, shareable `.fjgraphic` packages, and agents that write new graphics.
- **Recording.** A display or a window through ScreenCaptureKit, with system audio, a separate microphone file, click rings, pause and resume, a camera beside the screen (bottom-right), and voice-over.
- **Export.** H.264, HEVC (10-bit and with alpha), AV1 and VP9 through bundled encoders, ProRes, audio formats and stems, GIF, APNG and stills. An Export Queue, embedded chapters, and loudness targets of −14 and −16 LUFS.
- **Agents.** 106 product tools over a local socket (one per edit, plus app-state tools), the bundled `framejob-mcp` helper, and `render_frame` so an agent can look at its work. An in-app Assistant runs on the creator's own Anthropic key and shows its spend.

### Checked absent or partial

| Feature | Status | Evidence |
|---|---|---|
| A transcript view where deleting words cuts the video | Absent | Cutting by transcript works only through the Assistant or MCP (`get_transcript` + `ripple_delete_ranges`). |
| Cursor, click and key events from recordings | Absent | `RecordingSetup.swift` sets `showsCursor` and `showMouseClicks`, so the pointer is burned into the picture and no events are stored. |
| Auto-reframe, subject tracking | Absent | `set_canvas` fits or letterboxes. There is no Vision import in `app/Sources`. A spec §1 non-goal. |
| Finding clips in long recordings | Absent | Nothing in the code or the guide. |
| Speaker-based angle switching, multicam | Absent | A spec §1 non-goal. Only the first audio track of a file is read (`CompositionBuilder.firstTrack`, `core/src/container.rs`). |
| Background removal without a green screen | Absent | Issue #124 is iceboxed. The recorded camera is fixed bottom-right (spec §11 CAM-10). |
| Placing part of a file, a source viewer | Absent | `add_clip`, `insert_clip` and `overwrite_clip` take only track, media and position. |
| Proxies | Absent | Playback at 60 fps is checked on a 1080p movie (`docs/manual-checks.md` PB-2), and a few 4K rows exist. There is no multi-stream 4K or multi-hour figure. |
| Saved text and caption styles, brand kit, project templates | Absent | Four hard-coded text presets (`TextPane.swift`). Word-style colours can be set only by an agent. |
| Platform presets, safe-zone overlays, chapter-list text, thumbnail preset | Partial | Loudness targets and a vertical canvas preset exist. Named platforms, overlays and chapter text do not. |
| Translation, soft subtitle tracks, WebVTT import | Absent | |
| Stock media, direct upload, collaboration, cloud sync | Absent | |
| Eye contact, text-to-speech, beat detection, stabilisation, motion blur, optical-flow retiming | Absent | Several are spec §1 non-goals; beat detection is candidate #415. |

The in-app tutorials (TU0–TU3) are on an unmerged branch, and the owner's trial (TU4) is still owed.

### Where it is already ahead

- The whole editor is exposed as MCP tools printed from the core's own op table. Every agent edit is an undo step shown live, and `render_frame` lets an agent check its work.
- Its audio chain is deeper than any creator tool surveyed: a leveller, de-esser, true-peak master, LUFS targets, stems, Synchronize Audio with drift correction, and Duck by Speech.
- Colour management and HDR deliverables (HLG, HDR10, an SDR version) and log support. Creator tools lack these.
- Codec breadth: AV1 and VP9 with bundled encoders, VP9 and HEVC with alpha, ProRes 4444, and WebM and MKV import without re-encoding.
- A programmable motion-graphics engine whose templates agents can write.
- Open source with bring-your-own key and on-device processing first: no credits, no subscription, no upload of footage.

## The market in late 2026

Status words follow the vendor's own: shipped; beta (including open beta, public beta and research preview); announced. Where a claim rests on third-party coverage or on a vendor's own marketing, the text says so. Source tags such as [C1] refer to the Sources section.

### Creator tools

| Tool | What leads it (status) | Price or position | Sources |
|---|---|---|---|
| CapCut | EditPilot natural-language assistant on desktop (shipped). Smart Search, Auto Cutout, Remove Filler Words, Script to Video (shipped). Agentic first-draft mode and CapCut in ChatGPT (announced, pilot). Auto Reframe moved to Pro in April 2026 (shipped). | Free core. Annual Pro reported at $179.99, up from about $77; prices vary by region. | [C1] [C2] [C3] [C4] [C5] |
| Descript | Underlord agent with a model picker, a review pass after each turn, and plans stated in plain language (shipped). Editing by transcript, Studio Sound, Eye Contact, Green Screen, Clips (shipped). Smoothed jump cuts billed in AI credits (shipped). 18 caption presets and 15 text animations (shipped). API (beta) and MCP (shipped). | Per seat, metered by media minutes plus AI credits with no rollover. | [C6] [C7] [D7] |
| Riverside | Producer, Editor, Clipper and Marketer agents that start work unprompted but "nothing goes out without your sign-off" (shipped, rolling out). Magic Clips from the edited version. In-person multi-camera recording. MCP on Grow and above. "Smooth cuts" appears on its updates page, but one verifier could not find the feature. | Free plan, then subscriptions with AI credits. | [C8] [C9] |
| OpusClip | ClipAnything multimodal clip finding (shipped). ReframeAnything subject tracking (shipped, Pro). Virality score, scheduler, brand templates (shipped). AI Producer (open beta). Hosted MCP with 37 tools (shipped). | Free; Starter $15 and Pro $29 a month. Claims 16M+ users in its media kit. | [C10] [C11] [C12] [C13] |
| Submagic | One-click Auto Edit; custom caption, word and emoji animations; a B-roll library; MCP; publishing with analytics to six platforms (all shipped). | Credits per video. | [C14] |
| Captions (company now Mirage) | AI Edit by prompt, eye contact, AI twins, translation (shipped). Raised $75M in March 2026. | Freemium mobile app. | [C15] [C16] |
| VEED | OpenEdit: a coding agent writes HTML and CSS, rendered locally on Apple-silicon macOS 26 (beta). MCP and a ChatGPT app (shipped). Lipsync 2.0 (shipped). | Freemium with per-seat credits. OpenEdit's pipeline is Apache-2.0; its renderer is closed. | [C17] [C18] |
| Kapwing | Kai agent shows a plan and its credit cost for approval, and checks its own output (shipped). Moment finding from what is seen and heard (shipped). MCP 1.0 and 1.1 (shipped, October 2026). | Freemium with AI credits. | [C19] [C20] [C21] |
| Canva | Canva AI 2.0, conversational and agentic (research preview). | Pro and Teams subscriptions. | [C22] |
| Instagram Edits | Free, no watermark. An assistant that reads the creator's own Reels metrics (shipped, US rollout). Desktop version (announced). | Free. | [C23] [C24] |
| YouTube Create and Studio | Conversational editor for Shorts (announced, early 2027). Auto-dubbing for all creators in 27 languages (shipped; lip sync is a pilot). Video A/B tests and three thumbnails per video (announced). | Free. | [C25] [C26] [C27] [C29] |
| Premiere on iPhone | Free 4K export with no watermark, auto captions, background removal, publishing to YouTube Shorts (shipped). | Free; Firefly credits cost extra. | [C30] |
| Rough-cut hand-off tools | Gling: bad takes, silences, fillers, titles and chapters, export to Final Cut Pro, Resolve and Premiere. Eddie AI: syncs up to 6 cameras and cuts to the speaker. Selects: multicam sync and MCP (vendor claim). All shipped. | Subscriptions or credits. | [C31] [C32] [C33] |
| Video as code | HeyGen HyperFrames (Apache-2.0, with agent skills) and Remotion's Claude Code plugin (shipped). | Free or source-available. | [C34] [C35] |

What changed in 2026:

- **Agentic editing became the front door.** The pattern that won is to plan, show the cost, get approval, apply, check the result, then hand back the timeline. Descript runs a review pass and states its plans [C6]. Kapwing shows a plan with its credit cost [C19] [C20]. Riverside asks for sign-off [C8]. YouTube's editor "edits with you, not for you" [C25].
- **MCP became expected.** Descript, VEED, Submagic, OpusClip, Riverside and Kapwing all expose MCP servers [C6] [C18] [C14] [C13] [C9] [C21].
- **Repurposing became one product:** find clips, reframe, caption, add B-roll, publish, measure [C12] [C9] [C14].
- **Captions became a design system.** Descript has 18 presets and 15 animations [C6]. Kapwing has 12 presets with line length that follows the aspect ratio [C19]. Submagic has custom word and emoji animations [C14].
- **Editors resell other vendors' generative models**, billed in credits [C6] [C19] [C18] [C9].
- **Platforms give capable editors away.** Edits [C23], Premiere on iPhone [C30], YouTube dubbing in 27 languages [C26] [C27], and Instagram's lip-synced translation, free in 14 languages [C28].
- **Prices rose.** CapCut's annual Pro [C5], and Auto Reframe moved behind Pro [C4].

### Pro editors

| Tool | What it added for creators (status) | Price or position | Sources |
|---|---|---|---|
| Premiere (desktop 26.x) | Object Mask, on-device (shipped). Single-Word Captions without a karaoke highlight (shipped). Paper Edit, listed in 26.5 (one verifier found only a request for it, so treat it as disputed). Generative Media Tool with Firefly and partner models (shipped; Soundscape and Music in beta). Enhance Audio, Separate Crosstalk and Dynamic Auto Ducking (public beta). AI Assistant (public beta from 23 June 2026, with daily and weekly credit caps). Caption translation into 27 languages (shipped 2025). Auto Reframe Sequence (long-standing). | Creative Cloud subscription. | [P1] [P2] [P3] [P4] [P5] [P7] [P21] |
| Adobe for creativity connector | A hosted MCP server in Claude across Adobe apps (shipped). Reviewers say it does not drive the desktop Premiere timeline. | Adobe account. | [P6] |
| DaVinci Resolve 20, 21, 21.1 | IntelliScript, Animated Subtitles, Multicam SmartSwitch, AI Audio Assistant, Detect Music Beats and Music Editor (shipped 2025, mostly Studio). IntelliSearch, Speech Generator, CineFocus and face tools (shipped, Studio). A built-in MCP server for Claude, Claude Code and Codex (shipped September 2026, Studio only; Python scripting moved to Studio). A review calls the learning curve steep and the hardware demands heavy. | Free; Studio $295 once. | [P8] [P9] [P10] [P11] [P12] |
| Final Cut Pro 12.x | Transcript Search, Visual Search, Beat Detection (12.0, shipped). Generate Captions (US English), Auto Mask, Match Color, Edit Detection (12.3, shipped). MotionVFX content built in (announced for November 2026). | $299.99 once, or Apple Creator Studio at $12.99 a month. | [P13] [P14] [P15] [P18] |
| Final Cut Pro for iPad | Live Multicam from up to four iPhones; Montage Maker with Auto Crop (shipped). | Creator Studio subscription. | [P16] [P17] |
| Apple Creator Studio | AI assistants and MCP added to Keynote, Pages and Numbers, but not Final Cut Pro (announced, November 2026). | $12.99 a month. | [P19] |
| LumaFusion | Multicam Studio add-on and AI Person Keyer (shipped). | $29.99 once, plus add-ons. | [P20] |

What changed: within about a year, the three major editors all shipped search of the creator's own footage [P1] [P13] [P9], one-click subject masks [P2] [P14] [P8], word captions [P8] [P3] [P14] and beat detection [P13] [P8]. Resolve has automatic multicam [P8]. Agent access is partial everywhere. Resolve's MCP needs Studio [P10] [P11]. Adobe's connector does not drive the desktop timeline [P6]. Apple left Final Cut Pro out of its MCP update [P19]. Premiere's assistant is capped by credits [P7]. Pricing is split between subscriptions with credits and one-time licences [P18] [P12].

### Screen and tutorial tools

| Tool | What leads it (status) | Price or position | Sources |
|---|---|---|---|
| Screen Studio 4 | Auto zoom aimed at recorded clicks. Cursor smoothing, resizing, hiding when idle, click effects. Editing by transcript with filler and pause removal (4.0, shipped). Camera cutout (beta), layouts, face tracking, LUTs (4.0). Privacy masking (4.1, shipped). MCP server (announced, in progress). | About $29 a month, subscription only. The lifetime licence was withdrawn in October 2025. | [S1] [S2] [S3] [S4] [S5] [S6] [S7] |
| Camtasia | SmartFocus auto zoom and pan (shipped). Cursor smoothing, on Camtasia's own recordings only. | Subscription only since February 2025. | [S8] [S9] [D19] |
| ScreenFlow | Last feature release August 2025. No auto zoom, AI captions or transcript editing. | Effectively in maintenance. | [S10] |
| Tella | Auto zoom presets and keystroke overlays (shipped, October 2026). Camera cutout, LUTs, eye contact. API and MCP. Tella Agent (public beta). Direct publishing to seven platforms. | Cloud, credits for the agent. | [S11] [S12] |
| Loom | Native Mac rebuild (shipped, October 2026). Record for agent (open beta). Atlassian MCP that manages recordings but does not edit them. Transcript trim and filler removal on Business + AI. | Per seat. | [S13] [S14] [S15] |
| Cap | Auto zoom with spring motion and motion blur. Cursor capture. Camera background removal (0.6). A keyboard-press overlay track. A CLI and MCP that record, export and share but do not edit the timeline (shipped). Its changelog lists a word-level transcript editor; a verifier could find only an open pull request. | Free personal use, $58 lifetime desktop licence. | [S16] [S17] |
| FocuSee | Typing-triggered zoom and cursor enhancement (shipped). | Annual or lifetime licence. | [S18] |
| Prequel | Pointer stored as data, not burned in (v0.0.26). Typing-aware zoom, 14 layouts, camera cutout, a notch teleprompter, a CLI and a Claude Code skill (shipped). | $39 lifetime. | [S19] [S20] [S21] |
| ScreenKite | 83 local agent editing tools that plan first and apply on a second call (vendor claim). | One-time licence. | [S22] |
| OpenScreen | A free, MIT-licensed Screen Studio alternative with about 40k GitHub stars. Archived after v1.5.0. | Free. | [S23] |
| Arcade | A describe-to-video agent on Claude models that checks its own output (shipped). | Subscription. | [S24] |

What changed:

- **The category rests on cursor data.** The pointer and click events are captured apart from the frames [S2] [S3] [S19] [S16].
- **Auto zoom grew** typing triggers, spring motion and lenses [S18] [S19] [S16] [S4].
- **Presenter-camera cutout, layouts and face tracking** shipped across the leaders in September and October 2026 [S6] [S16] [S11] [S19] [S13].
- **Every recorder now has an agent surface**, but most only manage recordings [S16] [S14]. Tella's agent edits the timeline in public beta [S12]. ScreenKite claims 83 editing tools [S22].
- **Subscription pricing drew a backlash** [S7] [D19], and free or lifetime alternatives grew [S23] [S17] [S21].

### What creators ask for

- **Editing is the biggest time sink.** One vendor classified 27,555 comments on 44 creator-education channels. Editing and production was the largest category, at 21.4% of actionable comments, ahead of monetisation at 15.6% [D1]. This is one vendor's analysis, not a survey.
- **Most work alone, and repurposing is wanted.** In Adobe Express's survey of 384 US video creators (December 2025), 86% work solo. The most-wanted new AI features were auto-repurposing (19%), instant platform-specific edits (14%) and help while filming (14%) [D2].
- **AI use is near-universal, but cost and training worry them.** In Adobe's 2025 Creators' Toolkit (more than 16,000 creators, 8 countries), 86% use generative AI. High cost is the top barrier, at 38%, and 69% worry their content will train AI without permission [D3].
- **They want control over agents.** In Adobe's 2026 report, 85% say the final decision must stay with the creator. Among creators who want more agent independence, 44% want to review, edit or undo at any point, and 37% want to see what the agent is doing and why. 57% say AI output usually needs moderate or extensive editing [D4]. Epidemic Sound found 94% use AI and 89% feel pressure to [D5].
- **Video podcasts are big and the picture edit is still manual.**
  - YouTube reports over 1 billion monthly podcast users [D10]. Spotify says more than 500 million users have streamed a video podcast [D11]. Edison found 57% of Americans 12+ have both listened to and watched a podcast [D12].
  - Automatic angle switching has long-open Premiere idea threads [D13] and is sold as AutoPod for about $29 a month [D14].
  - Descript users ask for multicam export to Final Cut Pro and Premiere (181 votes) [D6].
- **Descript frustrations.** The top requests are regenerating speech in more languages (753 votes), an iOS/iPadOS app (417), transcription in more languages (400) and strip silence (192) [D6]. Reviewers report slow scrubbing and long exports [D8]. Plans moved to media minutes plus AI credits with no rollover [D7].
- **Captions.** Premiere's animated-caption request has about 416 votes, and users round-trip to CapCut [D15]. A verifier counted about 380. Either way, the request is for animated word captions, which Frame Job already has.
- **Auto-cutters are distrusted.** Riverside Magic Clips is faulted for cutting where a thought ends rather than where the energy peaks [D16]. Gling sometimes cuts good takes [D17].
- **What makes creators switch tools:**
  - price rises and forced subscriptions [C5] [D19] [S7];
  - content-licence scares [D18];
  - stability regressions [D20];
  - metered AI credits [P7] [D7].
- **Platform rules a tool can check.**
  - YouTube chapters start at 00:00, need at least three, and each must be at least 10 s [D21].
  - Apple Podcasts asks for about −16 LKFS with a true peak at or below −1 dBFS [D22].
  - Spotify video podcasts want H.264, 16:9 and Rec.709 with stereo AAC, and HDR is tone-mapped to SDR [D23].
  - No platform publishes safe-zone figures, and third-party figures conflict [D24].
  - YouTube requires disclosure of realistic synthetic content but exempts colour fixes, background blur, captions and audio repair [D25].
- **Platforms build the simple cases themselves.** YouTube's own clips tool suggests moments only in 10 countries and 7 languages [D9]. Twitch is building vertical streaming (beta) and Auto Clips with captions (waitlist) [D26].

## The bets

The bets are ranked by how many creators each reaches, how often they would use it, and how far it puts Frame Job ahead rather than level, discounted by effort and risk.

Every bet has the same shape. Analysis that Frame Job already caches, or that macOS provides on the device, feeds a planner. The planner writes edits the core already knows how to make. Each result is therefore an ordinary undo step on a real timeline, and each command becomes an MCP tool that the Assistant and outside agents can run with no new agent work.

Effort is build effort (S, M, L, XL), never lines of code.

| Rank | Bet | Effort | Serves |
|---|---|---|---|
| 1 | Transcript tab | L | Everyone who records themselves talking |
| 2 | Screen recordings with the cursor as data | L | Screencasts, tutorials, courses, product demos |
| 3 | Make Vertical Version | M (copy), L (linked versions) | Everyone who posts shorts |
| 4 | Find Clips | M on top of 3 | Podcasters, long-form YouTubers, streamers |
| 5 | Switch by Speaker, and every audio track | M | Video podcasts and interviews |
| 6 | Camera cutout and layouts | L | Screencasters, talking heads, streamers |

Bets 1 and 2 remove the two points where talking creators and the home segment give up. Bets 3 and 4 complete the long-to-short loop. Bet 5 takes the podcast format on the strength of the audio chain. Bet 6 closes the presenter-camera gap.

### 1. Transcript tab: cut by deleting words, with retakes found for review

**Pitch.** A Transcript tab shows the timeline's words in timeline order. The word being spoken is highlighted during playback, and clicking a word moves the playhead to it. The creator selects a sentence and presses Delete, and that span ripples out of the video as one undo step. Cut words stay greyed in place and can be restored.

A review pass strikes through long pauses and, where an AssemblyAI transcript exists, filler words. After the §11 decision below, it also strikes earlier takes of each repeated line and false starts. One click removes everything struck, as one undo step. Words inside a nest or a transition overlap show as not editable, with the reason.

**Why it puts Frame Job ahead.** On its own this brings Frame Job level. Editing by transcript ships in:

- Descript [C7], Screen Studio 4 [S4] and Tella [S11];
- Loom, on its Business + AI plan [S15];
- Prequel [S20] and Gling [C31].

Adobe lists Paper Edit in Premiere 26.5 [P4], though one verifier disputed it. Cap's changelog lists a word-level editor [S16] that a verifier could not confirm shipped.

Frame Job pulls ahead on terms and on depth:

- **Cost.** The on-device transcript costs nothing per minute. Descript meters media minutes and AI credits [D7] and draws complaints about speed [D8].
- **No model needed for retakes.** They are found by a deterministic comparison of neighbouring sentences, with no key.
- **Depth.** Every cut is an ordinary ripple edit in a full editor, with the audio chain, grading and graphics behind it, so restoring a cut is exact.
- **Agents for free.** The same word-to-timeline mapping already serves agents: `get_transcript` answers in timeline ticks, and `ripple_delete_ranges` is one undo step. "Drop the first take of every repeated line" therefore works the same by click or by chat.

Editing is the largest topic in one vendor's analysis of creator comments [D1].

**Builds on.** `DeviceTranscriptCache.swift` and `MediaTranscript.swift` (words cached per media in source ticks); AssemblyAI transcripts; `get_transcript` (`AgentServer+Transcript.swift`); `rc_project_source_map` (`speed_map.rs`, spec §11 SR-20) through speed, ramps and reverse; `ripple_delete_ranges` (`core/src/edit_time.rs`); `detect_fillers` and its lock, nest and transition rules.

**Effort.** L, as a short road map: the view with seek; delete as ranges; greyed, restorable words; the retake pass after its decision.

**Risks and what comes first.**
- Spec §11 TR-3 says a false start is never offered without a conversation. AI-6 and W-9 say no pipeline picks words to cut by meaning. A deterministic retake pass is such a pipeline, so it needs an amending §11 decision before code. Pauses and fillers already sit within TR-3 and TR-4.
- Restore is not one existing op. It is `insert_time` plus `trim_end` into the left clip's handle, grouped, or `add_clip` with a source range (next tier).
- On-device transcription kept 1 of 8 fillers in the owner's test (TR-7), so filler strike-through needs an AssemblyAI key.
- `MAX_CLIPS` (4,096) counts every clip, nested ones included, and each text cut splits every unlocked track. About 1,000 cuts over four tracks reaches the cap.
- The first fill of a whole-timeline view runs the recogniser at a few seconds per minute of speech. After that it is cached.
- A multi-hour transcript in one text view, kept in step with edits made elsewhere, needs care. The new pane needs a planned file split under the 600-line cap.

The companion item Punch in on cuts (next tier, S) hides the jump cuts this bet leaves.

### 2. Screen recordings with the cursor as data

**Pitch.** The recorder stops burning the pointer and click rings into the picture. Beside the movie it saves the cursor's path and image and every click. If the creator opts in, it also saves the shortcuts pressed. When the recording lands:

- zoom actions already sit on the action lane at each click and each burst of typing;
- the cursor is its own layer, which can be made bigger, restyled, smoothed or hidden when idle, and gets click ripples;
- each shortcut appears as a Keyboard keys overlay;
- long typing stretches can be sped up.

All of it is ordinary actions, clips and graphics that the creator can drag or delete. Recordings made before this ships, and imported screen videos, behave as today.

**Why it puts Frame Job ahead.** The polished-screencast category rests on cursor data:

- Screen Studio zooms where clicks happened [S2] and edits the cursor after recording [S3];
- Prequel stores the pointer as data [S19];
- Cap [S16], FocuSee [S18], Tella [S11] and Camtasia [S8] [S9] do the same.

Frame Job's recorder stores none of it, so Frame Job loses its own home segment to a recorder that costs about $29 a month [S7]. This bet brings Frame Job level on polish. It pulls ahead because those recorders are shallow editors and Frame Job is a full one. Its auto zooms are actions on a real timeline, next to grading, the audio chain, captions and graphics, and an agent can re-plan them ("zoom only on the clicks in the settings pane").

Being free is not unique by itself. OpenScreen is a free, MIT-licensed Screen Studio alternative with about 40,000 stars, archived after v1.5.0 [S23], and Cap sells a $58 lifetime licence [S17].

**Builds on.** `RecordingSetup.swift`, which sets `showsCursor` and `showMouseClicks` today; `add_zoom_action` (`core/src/edit_zoom.rs`); `add_speed_ramp`; the Keyboard keys graphic template; the recorder panel's grants; `recipe_layer.rs`; `MediaConsolidator` and relink.

**Effort.** L.

**Risks and what comes first.**
- Spec §11 (`recording.md`) decides three things this bet reverses: the cursor and click ring are taken as drawn and nothing is reconstructed; callouts stay out; a recording is ordinary media, with no source kind and no schema bump. The owner amends §11 first, as CAM-1 did for the camera.
- Shortcuts need the Input Monitoring grant, which `RecorderStatusItem.swift` deliberately avoids today. Key capture should be opt-in and record only modifier shortcuts by default. It must never record secure fields, and it must show plainly when it is on.
- The cursor must follow the screen clip's own transform and zoom actions. It has to be drawn as part of that clip's layer, or the two have to be nested with the zooms on the nest. A sprite on another track would drift.
- `NSCursor.currentSystem` is marked deprecated in macOS 27.0 in Apple's availability metadata, so a replacement is needed.
- The sidecar cannot be regenerated, so Consolidate and Relink must carry it.
- Timing can anchor on the screen's first-frame time, which the camera spike measured within 0.5 ms. Issue #370 is a microphone-offset problem and is not inherited.
- Motion blur on zooms needs sub-frame sampling and is out of scope.
- Code from AGPL-licensed recorders is not carried over, the same rule as for Concat.

### 3. Make Vertical Version

**Pitch.** File ▸ Make Vertical Version… writes a 9:16 or 1:1 version of a finished 16:9 edit. Each clip fills the frame and follows the face, person or salient region that Vision found on the Mac. It does this with ordinary eased x, y and scale actions the creator can nudge. In a screen recording made after bet 2, it follows the cursor instead. Captions re-lay for the short side, and graphics re-layout from the canvas size. A shot that cannot be cropped gets Add Blurred Background.

**Why it puts Frame Job ahead.** Subject-tracking reframe is table stakes. OpusClip [C11], CapCut [C4], Premiere [P21], Final Cut Pro for iPad [P17], Riverside [C9], Kapwing [C20] and Screen Studio [S1] all ship it, and auto-repurposing is the most-wanted creator AI feature in one survey [D2]. Frame Job pulls ahead on terms. CapCut moved Auto Reframe behind Pro in April 2026 [C4]. Here it is free and local, and the result is editable pan actions rather than a render. If the owner chooses linked versions (one cut, with a framing per shape), Frame Job is ahead of every rival, because their vertical copies drift from the master.

**Builds on.** `fill_scale` (`edit_fit.rs`); Add Blurred Background (`edit_background.rs`); word captions sized to the shorter side (`CaptionStyle.swift`); graphics that read `ctx.canvas`; actions (`edit_action.rs`); nests (`edit_nest.rs`); `set_canvas` (`edit_canvas.rs`); File ▸ Duplicate; the E9 Vision spike in `tools/proof/effects_spike/`.

**Effort.** M as a regenerated copy. L for linked versions, which need a canvas per version, framing overrides per clip and a format bump.

**Risks and what comes first.**
- Spec §1 lists auto-reframe as a non-goal, so a §11 decision must lift it first. The reason given there, heavy pixel work outside the one-pass compositor, no longer applies: the analysis runs offline and its output is actions.
- No two actions on one clip may overlap, of any kind. A clip that already carries an action (a zoom, a grade, a ramp) needs a wrapping nest, and a nest's canvas freezes at the size it was nested at.
- `set_canvas` does not rescale action end states. A screencast's existing zoom actions keep their 16:9 targets, and the planner must rewrite them.
- `MediaCacheLane` is a width-2 lane for audio decodes, so video analysis needs its own lane, cache kind and ledger rows.
- The planner should use face, human and saliency rectangles with tracking, not masks: the E9 spike found that foreground masks flicker on video.
- Two people in frame, a speaker leaving the frame, and shot changes inside one flattened clip each need a rule.

### 4. Find Clips

**Pitch.** Clip ▸ Find Clips…, run on an episode, a VOD or a finished edit, lists 10 to 30 candidates of 20 to 60 seconds. Each candidate shows:

- in and out points snapped to sentence ends;
- its length;
- a one-line reason, such as "laughter after the punchline";
- a preview.

There is no virality score. Make Short turns the checked candidates into vertical projects through bet 3. Each short is word-captioned, has fillers removed where a cloud transcript exists, and is queued for export.

**Why it puts Frame Job ahead.** Long-to-short is what OpusClip [C10] [C12], Riverside [C9], Submagic [C14] and Kapwing [C20] sell, all metered by credits. YouTube's own free tool covers only 10 countries and 7 languages [D9]. Frame Job pulls ahead in three ways:

- **Local signals.** Laughter, applause and cheering from Sound Analysis, the 10 ms loudness, speech spans and sentence ends are all measured on the Mac.
- **The creator's own key.** Ranking runs on the creator's Claude key, with no per-minute credits.
- **Real timelines.** Each candidate opens as an editable timeline.

A stated reason for each moment, rather than a score, answers the documented complaint that clippers cut in the wrong place [D16].

**Builds on.** `get_transcript` (timeline ticks); `ClipLoudness.swift` and the per-media loudness cache; `media_speech.rs`; `detect_fillers` and `ripple_delete_ranges`; caption Restyle with Replace; the Export Queue; the Assistant helper (`agent/`) and its price table; `set_range`.

**Effort.** M on top of bet 3. Without bet 3 it produces horizontal clips only.

**Risks and what comes first.**
- Ranking quality is the whole product.
- On-device FoundationModels has a 4,096-token context and needs Apple Intelligence turned on. It is a chunked, weaker fallback, not an equal path.
- Speaker labels exist only on AssemblyAI transcripts requested with speakers.
- No op copies a timeline range into a new project: `new_project` takes a path, and Duplicate copies everything. One is needed.
- Sound Analysis (`SNClassifySoundRequest` `.version1`, 303 labels on macOS 26.5.1, laughter, applause and cheering among them) is noisy on game audio and music beds.
- Long transcripts cost tokens, so show an estimate range before running.

### 5. Switch by Speaker, and read every audio track of a file

**Pitch.** The creator brings two to four cameras and a mic per person, lines them up with Synchronize Audio, and chooses Clip ▸ Switch by Speaker…. Frame Job cuts to whoever is talking, judging each mic's speech spans against that mic's own noise floor. It uses the wide shot during crosstalk and holds a minimum shot length. The whole switch is one undo step, and every cut is an ordinary split the creator can roll or re-pick. OBS multitrack files and multichannel recorder files import every audio track, not only the first.

**Why it puts Frame Job ahead.** Automatic switching is sold as AutoPod for about $29 a month [D14], as Resolve SmartSwitch in Studio [P8], and inside hand-off or metered tools such as Eddie [C32] and Descript. Premiere users have asked for it for years [D13], and video podcasts are the fastest-growing creator format [D10] [D11] [D12]. Frame Job already owns the hard audio half: drift-corrected sync, cached speech spans, the loudness cache, Match Audio, Enhance Voice, the leveller, a −16 LUFS target and stems. Adding the picture half makes it a free podcast editor. An agent can also re-run the switch with new rules, such as "cut to wide whenever both laugh".

**Builds on.** `AudioSync*.swift` (alignment as `move_clip` and `set_speed`); `SileroVAD.swift` and `media_speech.rs`; `audio_duck_speech.rs`; `ClipLoudness.swift`; `set_enabled` (a clip with its picture disabled is not decoded, per `nest.rs` `shows_video`); `ProjectDocument.performGroupedEdit`; `core/src/container.rs` and every `CompositionBuilder.firstTrack` audio caller.

**Effort.** M for speaker switching on stacked tracks plus every audio track. L for a multicam clip with an angle grid and live overrides.

**Risks and what comes first.**
- Spec §1 lists multicam as a non-goal, so a §11 decision must lift it, either narrowly (stacked tracks) or fully.
- Reading every audio track touches every `firstTrack(.audio)` caller: the builder, Silence, the isolation, ramp, voice and reverse renderers, and the transcription extract. It needs a format bump.
- Splitting linked picture and sound halves of three angles every 8 s for two hours gives about 5,400 clips, which is over the 4,096 cap. The switch should cut picture only and keep the mics whole.
- Mic bleed can mislead the switch, and one-mic shows need Vision mouth activity instead.
- Transitions decode both angles. Decoding three or four 4K angles has not been measured (see the next tier).
- Zoom and Riverside already deliver one file per participant, so the multitrack fix chiefly serves OBS and multichannel WAV.

### 6. Camera cutout and layouts

**Pitch.** The creator ticks Remove Background on a camera clip. Vision segments the person on the Mac, rendered in the background the way Reverse is. A Layout pop-up switches the camera at the playhead, with an animated move, between:

- corner bubble (circle or rounded);
- side by side;
- stacked for vertical;
- camera full;
- screen only.

"Hide camera while silent" fades the camera out during pauses. Text Behind Subject follows from cutout: a title sits between the person and their background.

**Why it puts Frame Job ahead.** This is mostly catch-up. Screen Studio 4 (cutout in beta) [S6], Cap 0.6 [S16], Tella [S11], Prequel [S19] and Loom [S13] shipped camera cutout or layouts in September and October 2026. Final Cut Pro [P14], Premiere [P2] and Resolve [P8] ship one-click subject masks. Frame Job's recorded camera is fixed in the bottom-right corner. It pulls ahead only in combination: layouts are actions any agent can write, the camera gets Frame Job's grading and LUT engine, and with bet 2 the whole screencast polish lives inside a full editor.

**Builds on.** Issue #124 and its E9 Vision spike; `ReverseRenderer`, `ReverseCache`, `BackgroundRender` and `MediaCacheLedger`; matte tracks (`recipe_matte.rs`); actions over transform, crop, corner radius and shadow; Add Background; the speech spans of the microphone media.

**Effort.** L.

**Risks and what comes first.**
- Edge quality on hair is a risk. Balanced person masks are 512×384 and likely need a refinement pass. Accurate masks run at 1.7× realtime and take 1.7 GiB per minute.
- Non-person masks flicker on video, so non-person cutout is for stills only.
- A mask on a Luma matte track has no link to the camera clip and drifts on trims, splits and speed changes. A per-layer mask with a format bump is the sound design.
- Issue #124's `texture(2)` binding is stale: looks now hold texture 2 and curves texture 3.
- The camera clip has no sound of its own, so hide-while-silent reads the microphone's spans through the microphone clip.
- Spec §1's ML non-goal, and issue #124's proposed decision D5, must enter §11 first.
- The 8-decoder budget is a warning, not a refusal. HLG projects need the mask in the right working space.

### The next tier

- **Proposals: play an agent's multi-step edit before it lands (M; Recipes later, also M).** Only Frame Job can do this cheaply. Handles are immutable. The export pin already renders a project that is not the current one. `performGroupedEdit` already makes one undo step from many. An agent's turn becomes a side chain the creator plays and compares A/B with the current cut, then accepts as one named step or rejects. This answers the 44% who want to review or undo and the 37% who want to see what the agent does [D4]. It amends spec §11 AI-10, which accepted ten Undos for a ten-call turn. It matters most once bets 1 and 4 produce agent-driven batches. Recipes come after Proposals and need three things: tool allow-lists enforced by the gate, because a shared recipe is a prompt-injection path; cost shown as an estimate range, because `pricing.ts` prices a run after it happens; and prompts served from `mcp-proxy`, because `core/src/agent.rs` is generic code.
- **Punch in on cuts (S).** Alternates scale between about 100% and 112% across cuts within one take, centred on the face, with `set_video` x, y and scale as one grouped step. It is free and exact, and needs no disclosure. Ship it right after bet 1's first phase.
- **Source ranges, skimming, In and Out, favourite ranges (M).** `add_clip`, `insert_clip` and `overwrite_clip` gain a source range, and `opTool` prints it into the MCP tools automatically. This is the precondition for placing a found moment and for a clean restore in bet 1. Add proxies only after a measurement shows a shortfall, under a recorded decision on a playback-only builder input.
- **Caption styles, brand kit and project templates (M).** Colour controls are safe under spec §11 W-10. Size and font changes need re-paging or a W-10 amendment. Per-word emphasis and emoji need a `model_words.rs` field and a format bump under W-2 and W-3. Whether emoji render correctly in HLG projects is unverified.
- **Publish polish slice (S).** A copyable 00:00 chapter list from chapter markers, checked against YouTube's rule [D21]; approximate platform safe-zone overlays [D24]; named platform export targets. Skip AI titles and thumbnails, which YouTube Studio is adding itself [C29].
- **Measure multi-stream 4K and multi-hour playback (S).** Bet 5 and any claim to lead depend on it. It is a measurement, not performance work.
- **`search_media` over cached transcripts (S).** The useful slice of a footage index. Build the Vision and Sound Analysis analysis inside bets 3, 4 and 6.
- **Merge the in-app tutorials after TU4 (S).** Creators arriving from CapCut need onboarding. The merge needs TutorialTargets rows for the audio road map.
- **Optical-flow slow motion, spike first (S, then M).** `VTFrameProcessor` accepts only 64RGBAHalf on this Mac, and its handling of HDR encodings is untested. Interpolated smooth cuts across a jump cut stay a spike, not a commitment.
- **WebVTT import (S); translated captions later (M).** A later phase of a caption road map, not a bet.

## Not worth chasing

| Item | Reason |
|---|---|
| Generative media: AI B-roll and video, avatars, voice clones, lip-synced dubbing | Nothing on the device can do it, so it means brokering credit-metered vendor APIs, the model Frame Job competes against. It carries disclosure risk [D25]. YouTube [C26] and Instagram [C28] now dub and translate for free. |
| Direct upload, scheduling, hosted share links, platform analytics | An open-source app with no backend cannot keep OAuth client secrets. A shared quota would cap all users together, and posting APIs need audits. Share links need a server. Bring-your-own storage is the only later form that fits. |
| Stock libraries; a template marketplace | These need licensing, curation and a backend. One developer cannot match CapCut's volume [C1] or MotionVFX inside Final Cut Pro [P15]. Agent-written graphics and `.fjgraphic` packages are the counter. |
| Eye-contact correction, face retouching | Apple has no public API for these on recorded video. They would need cloud or custom generative face models, with likeness risk and a per-frame cost the one-pass compositor cannot absorb. |
| Cloud sync, collaboration, mobile or iPad apps, Windows | Each needs a backend or a second platform. |
| Remote guest recording, live multi-camera capture | This is Riverside's moat [C9] and needs WebRTC servers. Import the per-guest files instead, and switch between them with bet 5. |
| A virality score | Creators distrust scored clips [D16]. A stated reason per moment is honest and controllable. |
| A standalone on-device footage index | The major editors shipped footage search within a year [P1] [P13] [P9]. Vision gives only fixed labels, so free-text search needs a bundled model whose licence is unverified. Build slices inside bets 3, 4 and 6, plus `search_media`. |
| Script to cut: a listening teleprompter that assembles takes | Teleprompters are common [S19] [S16]. Script-first recording suits a minority. `SpeechEngine.swift` is file-based today. The valuable kernel, retake removal, belongs in bet 1. |
| Translated captions and soft subtitle tracks as a bet | Platforms translate themselves [C26] [C28]. ADA Title II needs same-language captions, which Frame Job already makes. Platforms take the sidecar SRT and VTT files Frame Job already writes. |
| A publish kit as a headline | YouTube Studio is adding AI titles and title and thumbnail tests [C29]. The on-device model's context cannot hold a long transcript, and Frame Job already meets the loudness targets. Only the S slice is worth doing. |
| More MCP surface or a second agent mode as the headline | MCP became expected in 2026 [C6] [C13] [C21] [P10]. Every creator job shipped as ops becomes an agent tool anyway. |
| Stabilisation, for now | Phones stabilise in camera, and stabilisation mainly serves handheld vlogs. It is feasible later as a cached render. |
| Live-compositor motion blur | It needs several sub-frame passes, which breaks the one-pass compositor. |
| A plugin system | It contradicts the closed effect vocabulary (spec §11 R5-1, G-1) that preview and export parity and the proof suite rest on. |
| Pro finishing as headline features (Dolby Vision, synthetic depth of field) | Resolve and Final Cut Pro own these [P9]. Frame Job's colour and HDR already lead every creator tool. |
| Analytics-driven idea features | The platforms hold the data [C23] [C29]. |

## Decisions for the owner

1. **Lead segment.** Recommendation: creators who record themselves talking, meaning talking-head YouTube and screen tutorials (bets 1, 2 and 6). Then repurposing to shorts (bets 3 and 4), then video podcasts (bet 5).
2. **Which spec §1 non-goals to lift, and how far.**
   - Auto-reframe: needed for bet 3.
   - Multicam: narrowly, as speaker switching on stacked tracks, or fully, as a multicam clip with an angle grid (bet 5).
   - ML and heavy pixel work: needed for camera cutout (issue #124's D5, bet 6).
   - Optical-flow retiming and motion blur: stay out until a spike.
   - A plugin system: stays out.
3. **Which spec §11 decisions to amend before code.**
   - TR-3, AI-6 and W-9, so that a deterministic retake pass may strike words (bet 1).
   - `recording.md`: cursor as data, callouts, a source kind and a schema bump (bet 2).
   - AI-10, for Proposals.
   - W-10, for inspector caption styling.
4. **Shortcut capture.** Whether the recorder may ask for the Input Monitoring grant, with capture opt-in and limited to modifier shortcuts by default.
5. **Vertical versions.** A regenerated copy (M), or linked versions in one project, where one cut has a framing per shape (L, with a format bump).
6. **Language models.** Claude on the creator's key only, or Apple FoundationModels as a no-key fallback. FoundationModels needs Apple Intelligence on and has a context of about 4k tokens.
7. **Cloud.** Confirm that bring-your-own key stays the only cloud model. Then either accept that filler detection stays AssemblyAI-only (TR-7), or fund an on-device filler pass.
8. **Performance.** Allow one measurement of multi-stream 4K and multi-hour playback now, despite the features-first order, before bet 5 and before any claim to lead. Add proxies only if the measurement falls short.
9. **Real use.** Cut at least one real video per lead segment in Frame Job before or alongside the first bet, so the bets are tested against real work.
10. **Positioning.** Whether to present Frame Job to creators as free, open, on-device and credit-free. That position answers the most common switching triggers: price rises [C5] [S7] [D19], metered credits [D7] [P7] and content-licence scares [D18].

## Sources

The "What Frame Job has" section cites repository paths only and has no external sources. The bets and Not worth chasing sections cite the tags below; no source is first cited there. Dates are each page's as-of date as recorded by the research sweeps.

### The market: creator tools

- [C1] CapCut EditPilot. https://www.capcut.com/tools/edit-pilot (as of 2026-10-27)
- [C2] CapCut newsroom, CapCut World LA. https://www.capcut.com/newsroom/capcut-world-la (2026-10-27)
- [C3] CapCut desktop AI tools. https://www.capcut.com/tools/desktop-ai-power (page undated; read 2026-11-01)
- [C4] CapCut help, Auto Reframe moved to Pro. https://www.capcut.com/help/why-do-i-have-to-pay-for-auto-reframe (2026-04-03)
- [C5] Newsweek, CapCut subscription price. https://newsweek.com/app-used-millions-nearly-doubles-subscription-price-overnight-11535999 (February 2026; read 2026-11-01)
- [C6] Descript changelog. https://descript.canny.io/changelog (2026-10-12)
- [C7] Descript homepage. https://www.descript.com/ (2026-11-01)
- [C8] Riverside, first team of AI agents. https://riverside.com/blog/first-team-of-ai-agents-built-for-video (2026-10-26)
- [C9] Riverside product updates. https://riverside.com/university/product-updates (2026-10-28)
- [C10] OpusClip pricing. https://www.opus.pro/pricing (2026-11-01)
- [C11] OpusClip homepage. https://www.opus.pro/ (2026-11-01)
- [C12] OpusClip media kit. https://media.opus.pro/ (2026-10-30)
- [C13] OpusClip MCP agent setup. https://help.opus.pro/api-reference/agent-setup (page undated; read 2026-11-01)
- [C14] Submagic changelog. https://submagic.canny.io/changelog (2026-06-08)
- [C15] Captions homepage. https://www.captions.ai/ (2026-11-01)
- [C16] TechCrunch, Mirage raises $75M. https://techcrunch.com/2026/03/24/mirage-raises-75m-to-continue-building-models-for-its-ai-video-editing-app-captions/ (2026-03-24)
- [C17] VEED newsroom, OpenEdit. https://www.veed.io/newsroom/openedit-by-veed (2026-08-19)
- [C18] VEED changelog. https://changelog.veed.io/ (2026-07-14)
- [C19] Kapwing release notes, August 2026. https://www.kapwing.com/help/release-notes-august-2026-2/ (2026-08)
- [C20] Kapwing release notes, March 2026. https://www.kapwing.com/help/release-notes-march-2026/ (2026-03)
- [C21] Kapwing MCP release notes. https://www.kapwing.com/help/release-notes-kapwing-mcp/ (2026-10-27)
- [C22] Canva Create 2026, Canva AI 2.0. https://www.canva.com/newsroom/news/canva-create-2026-ai/ (2026-04)
- [C23] TechCrunch, Instagram's AI video assistant. https://techcrunch.com/2026/09/30/instagram-rolls-out-an-ai-video-assistant-for-creators/ (2026-09-30)
- [C24] TechCrunch, Edits assistant and desktop version. https://techcrunch.com/2026/06/11/metas-edits-app-is-getting-an-ai-assistant-and-a-desktop-version/ (2026-06-11)
- [C25] TechCrunch, YouTube's conversational editor. https://techcrunch.com/2026/09/23/youtubes-conversational-video-editing-tool-lets-creators-make-edits-in-natural-language/ (2026-09-23)
- [C26] YouTube blog, auto-dubbing and Expressive Speech. https://blog.youtube/news-and-events/youtube-auto-dubbing-expressive-speech/ (2026-02-04)
- [C27] WinBuzzer, auto-dubbing for all creators in 27 languages. https://winbuzzer.com/2026/02/05/youtube-ai-auto-dubbing-all-creators-27-languages-xcxwbn/ (2026-02-05)
- [C28] Metricool, Meta AI translations. https://metricool.com/meta-ai-translations/ (2026-07-14)
- [C29] Social Media Today, YouTube at Made on YouTube 2026. https://www.socialmediatoday.com/news/youtube-presents-new-ai-and-engagement-features-at-made-on-2026/831216/ (2026-09-23)
- [C30] Adobe Premiere mobile app. https://www.adobe.com/products/premiere/app.html (2026-11-01)
- [C31] Gling homepage. https://www.gling.ai/ (2026-11-01)
- [C32] Eddie AI help, multicam podcasts. https://help.heyeddie.ai/en/articles/10548843-multicam-podcasts-the-correct-angle-chosen-for-the-correct-speaker (2026-11-01)
- [C33] Cutback, Selects comparison (vendor). https://cutback.video/blog/hyperframes-vs-remotion-vs-selects (2026-10-17)
- [C34] HeyGen HyperFrames repository. https://github.com/heygen-com/hyperframes (2026-11-01)
- [C35] Remotion Claude Code plugin. https://www.remotion.dev/docs/ai/claude-code-plugin (2026-11-01)

### The market: pro editors

- [P1] Adobe news, AI innovation in Premiere (Media Intelligence, Caption Translation, Generative Extend). https://news.adobe.com/news/2025/04/new-ai-innovation-in-industry (2025-04-02)
- [P2] PetaPixel, Premiere 26 with one-click object tracking. https://petapixel.com/2026/01/20/rebranded-adobe-premiere-26-arrives-with-one-click-object-tracking (2026-01-20)
- [P3] Adobe community, what's new in Premiere 26.3. https://community.adobe.com/announcements-727/what-s-new-in-adobe-premiere-26-3-june-2026-1628369 (2026-06-17)
- [P4] Adobe community, what's new in Premiere 26.5. https://community.adobe.com/announcements-727/what-s-new-in-adobe-premiere-26-5-september-2026-1641187 (2026-09-10)
- [P5] Adobe blog, generating in the timeline (IBC 2026). https://blog.adobe.com/en/publish/2026/09/08/generate-create-directly-in-your-timeline-with-new-ai-powered-innovations-in-premiere-after-effects (2026-09-08)
- [P6] Adobe blog, Adobe for creativity connector. https://blog.adobe.com/en/publish/2026/04/28/adobe-for-creativity-connector (2026-04-28)
- [P7] Adobe community, AI Assistant in Premiere public beta. https://community.adobe.com/announcements-727/meet-your-new-assistant-editor-ai-assistant-in-premiere-pro-is-now-in-public-beta-1629317 (2026-06-23)
- [P8] Blackmagic Design, DaVinci Resolve 20 release. https://www.blackmagicdesign.com/media/partial/release/20250404-02 (2025-04-04; final 2025-05-27)
- [P9] Newsshooter, DaVinci Resolve 21 announced. https://www.newsshooter.com/2026/04/13/blackmagic-design-announces-davinci-resolve-21-major-update-adds-new-photo-page/ (2026-04-13)
- [P10] Blackmagic Design, DaVinci Resolve 21.1 release. https://www.blackmagicdesign.com/media/partial/release/20260908-03 (2026-09-08)
- [P11] CineD, DaVinci Resolve 21.1 with MCP. https://www.cined.com/davinci-resolve-21-1-released-ai-assistant-integration-via-mcp-individual-hdr-trims-and-python-scripting-moves-to-studio/ (2026-09-08)
- [P12] Videomaker, DaVinci Resolve 21 review. https://www.videomaker.com/reviews/software/davinci-resolve-21-review-blackmagic-turns-its-editor-into-a-full-creative-hub/ (October 2026)
- [P13] Apple support, Final Cut Pro release notes. https://support.apple.com/en-us/102825 (2026-09-29)
- [P14] CineD, Final Cut Pro 12.3 (Generate Captions, Edit Detection, Auto Mask). https://www.cined.com/apple-creator-studio-update-adds-generate-captions-edit-detection-and-auto-mask-to-final-cut-pro/ (2026-06-30)
- [P15] Newsshooter, MotionVFX built into Final Cut Pro. https://www.newsshooter.com/2026/10/27/apple-creator-studio-brings-built-in-motionvfx-content-to-final-cut-pro/ (2026-10-27)
- [P16] Apple support, Final Cut Pro for iPad release notes. https://support.apple.com/en-gw/102731 (2026-06-30)
- [P17] Apple, Final Cut Pro for iPad guide, Montage Maker. https://support.apple.com/guide/final-cut-pro-ipad/dev00a725416/ipados (2026-06-30)
- [P18] Apple Creator Studio. https://www.apple.com/creator-studio (2026-01-28)
- [P19] MacStories, Creator Studio adds AI assistants and MCP. https://macstories.net/news/apple-creator-studio-to-add-motionvfx-ai-assistants-and-mcp-support-in-november/ (2026-10-27)
- [P20] LumaFusion, App Store listing. https://apps.apple.com/us/app/lumafusion/id1062022008 (2026-11-01)
- [P21] Adobe help, Auto Reframe overview (fetch refused; content seen in search results). https://helpx.adobe.com/premiere/desktop/add-video-effects/commonly-used-effects/auto-reframe-overview.html (2026)

### The market: screen and tutorial tools

- [S1] Screen Studio homepage. https://screen.studio (2026-11-01)
- [S2] Screen Studio guide, auto zoom. https://www.screen.studio/guide/auto-zoom (2026-11-01)
- [S3] Screen Studio guide, cursor. https://www.screen.studio/guide/cursor (2026-11-01)
- [S4] Screen Studio 4. https://screen.studio/4 (2026-10-02)
- [S5] Screen Studio roadmap. https://screen.studio/roadmap (2026-11-01)
- [S6] AlternativeTo, Screen Studio 4.0. https://alternativeto.net/news/2026/10/screen-studio-4-0-adds-transcript-editing-a-camera-cutout-tool-and-more-mouse-effects/ (2026-10-02)
- [S7] AlternativeTo, Screen Studio removes non-subscription licences. https://alternativeto.net/news/2025/10/screen-studio-has-removed-their-non-subscription-licensing-options-for-new-customers/ (2025-10)
- [S8] TechSmith, Camtasia Mac 2026 version history. https://support.techsmith.com/hc/en-us/articles/41263167862285-Camtasia-Mac-2026-Version-History (2026-09-10)
- [S9] TechSmith, Camtasia cursor smoothing. https://www.techsmith.com/learn/tutorials/camtasia/cursor-smoothing/ (2026-10-06)
- [S10] Telestream, ScreenFlow versions. https://www.telestream.net/screenflow/versions.htm (2026-02-12)
- [S11] Tella changelog. https://www.tella.com/docs/changelog (2026-10-30)
- [S12] Creators Toolbox, Tella Agent, Motion and Auto Capture. https://creatorstoolbox.com/blog/tella-agent-motion-auto-capture (2026-10-30)
- [S13] Atlassian, all-new Loom for Mac. https://www.atlassian.com/blog/loom/all-new-loom-for-mac (2026-10-07)
- [S14] Atlassian, Loom record for agents. https://www.atlassian.com/blog/loom/record-for-agents (2026-10-22)
- [S15] Atlassian support, Loom filler words and silences. https://support.atlassian.com/loom/docs/remove-filler-words-and-silences-from-your-video/ (2026-11-01)
- [S16] Cap desktop changelog. https://cap.so/changelog/desktop (2026-10-28)
- [S17] Cap pricing. https://cap.so/pricing (2026-11-01)
- [S18] FocuSee changelog. https://focusee-voice.imobie.com/en/changelog (2026-08-27)
- [S19] Prequel changelog. https://prequel.sh/changelog (2026-10-30)
- [S20] Prequel homepage. https://prequel.sh/ (2026-10-30)
- [S21] Prequel pricing. https://prequel.sh/pricing (2026-11-01)
- [S22] ScreenKite blog, local agent editing (vendor). https://www.screenkite.com/blog/loom-record-for-agent-alternative-local-2026 (2026-10-19)
- [S23] OpenScreen repository. https://github.com/siddharthvaddem/openscreen (2026-06-06)
- [S24] Arcade changelog. https://www.arcade.software/changelog (2026-10-20)

### The market: what creators ask for

- [D1] OverseerOS, what YouTube creators struggle with (vendor analysis). https://www.overseeros.com/blog/what-youtube-creators-struggle-with-most (2026-08)
- [D2] Adobe Express, AI video tools survey. https://www.adobe.com/express/learn/blog/ai-video-tools (published 2026-03-25; fielded December 2025)
- [D3] Adobe, inaugural Creators' Toolkit report (PDF). https://news.adobe.com/news/downloads/pdfs/2025/10/10282025-inauguraladobecreatorstoolkitreport.pdf (2025-10-28)
- [D4] Adobe, Creators' Toolkit report 2026. https://news.adobe.com/news/2026/06/creators-toolkit-report-2026 (2026-06-16)
- [D5] Epidemic Sound, Future creator economy report 2026. https://www.epidemicsound.com/de/data-trends/sound-of-creativity-reports/future-creator-economy-report-2026/ (2026)
- [D6] Descript feature requests, sorted by votes. https://feedback.descript.com/feature-requests?sort=top (2026-11-01)
- [D7] Descript help, legacy plan sunset. https://help.descript.com/billing-payments-plans/legacy-sunset.md (from 2025-11-17; read 2026-11-01)
- [D8] CheckThat, Descript reviews (aggregator). https://checkthat.ai/brands/descript/reviews (2026-07-07)
- [D9] YouTube help, clips and Shorts from long videos. https://support.google.com/youtube/answer/15824265 (2026-11-01)
- [D10] YouTube blog, 1 billion monthly podcast users. https://blog.youtube/news-and-events/1-billion-monthly-podcast-users/ (2025)
- [D11] Spotify newsroom, investor day podcast updates. https://newsroom.spotify.com/2026-05-21/investor-day-podcast-features-updates/ (2026-05-21)
- [D12] Tubefilter, Edison Infinite Dial video podcast report. https://www.tubefilter.com/2026/03/20/edison-research-infinite-dial-video-podcast-report/ (2026-03-20)
- [D13] Adobe community idea, multicam switching by speaker. https://community.adobe.com/t5/premiere-pro-ideas/multicam-automatically-with-cams-based-on-who-is-speaking/idi-p/13651747 (open; read 2026-11-01)
- [D14] AutoEdit AI, two-person podcast editing in Premiere (AutoPod price). https://autoeditai.net/blog/edit-two-person-video-podcast-automatically-premiere-pro (2026)
- [D15] Adobe community, animated caption options request. https://community.adobe.com/feature-requests-730/request-for-enhanced-animated-caption-options-and-ai-features-in-premiere-pro-1327436/index4.html (October 2026)
- [D16] BlitzCut, Riverside Magic Clips review (competitor's blog). https://blitzcutai.com/blog/riverside-magic-clips-review-2026 (2026)
- [D17] Unite.AI, Gling review. https://www.unite.ai/gling-ai-review (2026)
- [D18] CapCut, about the terms of service. https://www.capcut.com/resource/about-capcut-terms-of-service (2025-06-24)
- [D19] TechSmith support, Camtasia moves to subscription. https://support.techsmith.com/hc/en-us/articles/27009223314701 (2025-02-12)
- [D20] Adobe community, Premiere 2026 stability on Mac Studio M3 Ultra. https://community.adobe.com/questions-729/premiere-pro-2026-severe-stability-issues-on-mac-studio-m3-ultra-1548629 (2026)
- [D21] YouTube help, video chapters. https://support.google.com/youtube/answer/9884579 (2026-11-01)
- [D22] Apple Podcasts, audio requirements. https://podcasters.apple.com/support/audio-requirements (2026-11-01)
- [D23] Spotify for Creators, video specs. https://support.spotify.com/us/podcasters/article/video-specs/ (2026-11-01)
- [D24] AdaptlyPost, social media safe zones 2026 (third-party figures). https://adaptlypost.com/blog/social-media-safe-zones-2026-complete-guide (2026)
- [D25] YouTube help, disclosing altered or synthetic content. https://support.google.com/youtube/answer/14328491 (2026-11-01)
- [D26] Twitch blog, TwitchCon Rotterdam 2026 announcements. https://blog.twitch.tv/en/2026/05/30/everything-we-announced-at-twitchcon-rotterdam-2026/ (2026-05-30)
