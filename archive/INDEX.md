# Archive index

`archive/` holds the full historical records: road maps, file histories, surveys. They are
**not read by default**. Each one has a condensed decision record in `designs/adr/`, so read that
first. Come here only when asked, or when an ADR's "Where to look in the original" section points
you at the detail behind a decision.

The documents were moved here verbatim. Paths inside them still say `designs/…`, and any section
number they cite (e.g. "road map 7 §10.1") refers to the archived copy. The same goes for code
comments that cite "road map N §x". The spec they cite as `designs/reelcut-design.md` is now
`designs/spec/`, split by section with the numbers unchanged.

**Every file added here gets a row below, in the same change.**

| Archived original | Condensed record | What it was |
|---|---|---|
| `reelcut-roadmap.md` | `designs/adr/roadmap-01-m1-m3.md` | M1–M3, the spec's own milestones: how each was proved, and the known limits. |
| `reelcut-milestones.md` | `designs/adr/milestones-record.md` | The per-phase status record the root `CLAUDE.md` carried until 2026-09-17, moved out verbatim. It stops at road map 3's R2. |
| `reelcut-roadmap-2.md` | `designs/adr/roadmap-02-ten-phases.md` | Road map 2: ten phases beyond the spec. §0 is the rules every later phase inherited. |
| `reelcut-roadmap-3.md` | `designs/adr/roadmap-03-screen-recording.md` | Road map 3: screen recording (R1) and pause/resume (R2). |
| `reelcut-roadmap-4.md` | `designs/adr/roadmap-04-voice-silence.md` | Road map 4: Remove Silences judged by voice (Silero VAD through Core ML), with the spike's rejected alternatives. |
| `reelcut-roadmap-5.md` | `designs/adr/roadmap-05-transitions-motion.md` | Road map 5: the transitions second pass (E1) and motion presets (E2). |
| `reelcut-roadmap-6.md` | `designs/adr/roadmap-06-cloud-captions.md` | Road map 6: captions from AssemblyAI (C1, built). C2, the relay, was designed and is deferred. |
| `reelcut-roadmap-7.md` | `designs/adr/roadmap-07-deepening.md` | Road map 7, the deepening series: the core as the one validator (D1), an op's three answers (D2), one op table (D3), the source window, handler-forward (retired) and the argument gate. |
| `reelcut-roadmap-8.md` | `designs/adr/roadmap-08-word-captions.md` | Road map 8: word captions in the social-video style (W0–W4b). |
| `reelcut-roadmap-9.md` | `designs/adr/roadmap-09-clip-inspector.md` | Road map 9: the clip inspector redesign (CI-1..CI-15). |
| `reelcut-roadmap-10.md` | `designs/adr/roadmap-10-graphics.md` | Road map 10: motion graphics drawn by code (QuickJS + resvg, the `graphic/` crate). |
| `reelcut-roadmap-11.md` | `designs/adr/roadmap-11-dev-tools.md` | Road map 11: the dev tools (`REELCUT_DEV_TOOLS`, `make dist`, `snapshot_ui`, `perform_menu_item`, `cancel_sheet`, `select_inspector_tab`, `-RCDevAppearance`) and the screen catalog. |
| `reelcut-roadmap-12.md` | `designs/adr/roadmap-12-assistant.md` | Road map 12: the Assistant — a bundled Bun helper on the Anthropic SDK's Tool Runner, one agent lane for every tool call, withheld and ask-first tools, the inspector's Assistant tab and its prompt (AI-1..AI-15). |
| `reelcut-roadmap-13.md` | `designs/adr/roadmap-13-pricing.md` | Road map 13: pricing and spend — LiteLLM's table and one price function in the helper and the proofs, the helper pricing every response, the app's spend ledger, the proofs' ledger and monthly budgets, and the two figures in the UI (P-1..P-7). |
| `reelcut-roadmap-14.md` | `designs/adr/roadmap-14-agent-socket.md` | Road map 14: reaching the agent server — a Unix socket in its own `0700` folder as the only listener, `reelcut-mcp` (the bundled stdio proxy and its catalog snapshot), a tool call never raising a modal question, and Tools ▸ Copy MCP Command (MC-1..MC-6). |
| `build-velocity.md` | `designs/adr/build-velocity.md` | Issue batch B88, build velocity: one cached parallel probe build (`swift_build.py`), the Debug app "Reelcut Debug" and its identity, the refusal to drive a stale app (`proof_app.py`), Debug against Release, and `make gate` (V-4, V-5). |
| `mattes.md` | `designs/adr/mattes.md` | Issue batch B89, the matte track (#240): a track switched to "matte for the track below" in four modes, through nests, dissolves, shadows, reflections and every export, with its chrome (MT-1..MT-7); the spike that chose the compositor's route, and its re-run against the shipped shader. |
| `precision.md` | `designs/adr/precision.md` | Issue batch B94, precision: the compositor in 16-bit float, every video source decoded to `64RGBAHalf`, ProRes 10-bit from deep frames, the `hevc_10bit` row and `hevc` pinned to Main (PR-1..PR-5); the preview-display spike, the memory the owner accepted, and the per-row encoder inputs. |
| `grading.md` | `designs/adr/grading.md` | Road map "grading": colour grading tier 1 — tone at step 4c, Show Ungraded and the luma waveform, adjustment clips, looks and `.cube` LUTs at step 4d (GR-1..GR-9); GR0's route spike, the caps measured against main, the owner's trial and verdict (kept), and format 15's renumbering of the branch's 1015. |
| `grading-2.md` | `designs/adr/grading-2.md` | Road map "grading-2": colour grading tier 2 — the scopes (RGB parade, Rec. 709 vectorscope, histogram) and their counting rule, colour wheels at step 4c.1, curves through a 1,024-texel strip at 4c.2, and qualifiers with Show Selection and Pick from Canvas on adjustment clips (GR-10..GR-14, formats 16–18); the brief's spike, the scopes' time rows, and each phase merged into main alone. |
| `precision-2.md` | `designs/adr/precision-2.md` | Road map "precision-2" (#257): the paths PR-5 left 8-bit — a still deeper than 8 bits drawn at 16-bit float, every reverse written HEVC Main 10 (ProRes 422 at an odd size, its exact size kept) carrying the source's colour labels, and 10-bit `hevc_alpha` and screen recording closed as not wanted (PR-6..PR-8); the brief's measurements, the owner's two PR-4 rulings, and V3 made to discriminate. |
| `svg-motion-components-plan.md` | `designs/adr/svg-motion-plan.md` | The proposal road map 10 reviewed, and what was adopted, amended or rejected. |
| `reelcut-effects-survey.md` | `designs/adr/effects-survey.md` | The effects survey road map 5 came from. E3–E9 are deferred by the user. It also holds the Concat AGPL rule. |
| `reelcut-app-notes.md` | `designs/adr/app-file-history.md` | Why each Swift file in `app/Sources/` is the shape it is: size tolls, measurements, review findings. |
| `reelcut-core-notes.md` | `designs/adr/core-file-history.md` | Why the Rust core's seams fall where they do: every cut, with its line counts. |
| `reelcut-remaining.md` | `designs/adr/remaining-closed.md` | The "what is left" file as of 2026-09-26. Its open items became GitHub issues and the live file was deleted; its closed items and their lessons are in the ADR, its build settings in `designs/adr/rust-build-settings.md`. |
