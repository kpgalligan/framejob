# The Assistant — an AI agent in the editor (road map 12)

- **Status:** Built and closed 2026-09-28. A0 the spike 2026-09-27 (`4f8d4ce`); A1 the lane (`08ab2ee`), the helper and its build (`68ccc20`) and the session (`5a88a57`) 2026-09-27; A2 the Assistant tab 2026-09-27 (`dae833a`); A3 the prompt 2026-09-27 (`172cf0c`, committed 2026-09-28); A4 `dist_check.py`'s helper rows and the close 2026-09-28 (uncommitted when this was written). Each phase was one litecode pipeline; A2's and A3's reader reviews each found one fix, landed in their commits.
- **Original:** `archive/reelcut-roadmap-12.md` (1022 lines) is the full record. Sections cited below as "orig §x" refer to it.
- **Spec decisions:** AI-1..AI-16 in spec §11 (`designs/spec/11-decisions/assistant.md`), which stay binding:
  - AI-1: the assistant is a bundled helper, and the app never calls Anthropic itself.
  - AI-2: the helper owns no tools; every call goes through `AgentServer.execute` by way of one lane.
  - AI-3: the catalog and the gate are prepared at launch, not at `start()`.
  - AI-4: the Assistant is the inspector's fourth tab: Clip, Media, Document, Assistant.
  - AI-5: the assistant edits its own window's project.
  - AI-6: W-9 governs automatic styling, not a person's request.
  - AI-7: what the assistant may not call, and what it must ask about first.
  - AI-8: the key is the person's own, and is R6-5 and R6-12's key in everything but the vendor.
  - AI-9: history is append-only, and end-of-turn compaction is the one rewrite.
  - AI-10: each tool call the assistant makes is its own undo step.
  - AI-11: the default model is `claude-opus-5-5` at medium effort.
  - AI-12: a tool call that arrives during a live gesture waits for mouse-up, then runs.
  - AI-13: the one base-URL override is `RC_ASSISTANT_BASE_URL`, and with it set no key file is opened.
  - AI-14: a selection change that is not a click on a clip leaves the Assistant tab showing; a click still shows Clip.
  - AI-15: the window's live context rides on each person message; the system prompt is fixed for a session.
  - AI-16: Stop stops a running `export` or on-device `transcribe`; any other running call finishes.
  The helper, the lane, the session, the prompt and the tab are specified in spec §7.9; the files are mapped in §7.4.

## Context

The user asked for an AI agent in the editor, "designed in the same way that the agent for `~/devel/rasterize` is". Rasterize had just shipped one: a Bun helper on the Anthropic TypeScript SDK's Tool Runner that owns no tools and asks the app to run each one over JSON lines on stdio, a Swift session that launches it with an empty environment and hands it the key on stdin, append-only history with end-of-turn compaction, and a panel. Reelcut already had every tool, as MCP tools. What it did not have: a dispatcher that could take a second caller (the MCP server is single-request, and eight tools run off main), a gate filled without the server, a way to pin a call to one window's project, a place in the chrome (the sharp handoff forbade an "assistant panel"), and a rule for tools that record the screen, spend money or write files where the model chose. A0 measured the unknowns before any code; A1 built the plumbing with no UI, A2 the tab, A3 the prompt, A4 the build check. No op, model field, FFI export or schema bump was added. (orig §1–§5)

## Decisions

- **The helper is taken whole, and is one diff with Rasterize's.** `agent/src/` is Rasterize's except for three domain constants moved into `configure` (`core_tools`, `search_guide`, `compaction_instructions`); `package.json` and `bun.lock` differ only in the name. With `rasterize-agent` renamed, `bun install --frozen-lockfile` passed, so the lock needs no regeneration (B2). Rasterize has not taken the change: the write into its tree was refused as a shared resource, and until #147 lands it is one diff behind. (AI-1; orig §2, §7 B, §8 part 2)
- **The helper is signed with the hardened runtime and exactly `allow-jit`, in both bundles, and `make dist` checks it.** `agent/build.sh helper`, `project.yml`'s last post-build step, copies it to `Contents/Helpers/reelcut-agent` and signs it before Xcode signs the app; no bun fails the build. The helper is 57719424 bytes, `flags=0x10002(adhoc,runtime)`, entitlements exactly `{com.apple.security.cs.allow-jit: true}` (H1); re-signed with no entitlements it exits −5 with "Ran out of executable memory" (H6), so the entitlement is necessary. `dist_check.py` D6–D13 hold each bundle's helper to that contract (present, `runtime` in the flags, entitlements exact, no dev-tools marker), and `dist_check_mutants.py` makes each row fail on purpose, 11/11 cases. (AI-1; orig §7 H, §8 part 2, §11)
- **Tool search, with four core tools.** The assistant's catalog is 84 tools and 219188 bytes, an estimated 54797–87675 tokens, entirely over the 10000 at which Anthropic's guidance turns to tool search (C3); none of Rasterize's core tools exists here, so A0's helper deferred all 85. Reelcut's core set is `get_project`, `render_frame`, `undo` and `redo`, loaded up front; every other tool is found by BM25 search, guided by A3's fourteen topics. (orig §7 C, §5 A1, §10)
- **One lane for every tool call, never locked on main.** `AgentLane` holds one `NSLock` around every call from the MCP trampoline and the assistant session, so `callScope` and `callDocument` stay race-free; the eight `offMainTools` run in place and every other tool on main. L2: 20 concurrent calls, 10 `serve` and 10 `submit` to two documents, 0 errors, every marker on its own document. (AI-2; orig §3a, §3b, §8 part 1)
- **The catalog and the gate are prepared at launch.** `prepareCatalog()` runs from `main.swift` before `NSApplicationMain`, so an assistant call with arguments works in a launch without `-AgentServerEnabled` (L0, L1; the session proof's W). Without it, the gate refused "add_marker does not take at and name" (M1), and the no-prepare mutant failed W. (AI-3; orig §3c, §8 parts 1 and 3)
- **A call is pinned to its window's document.** `callDocument` is checked first by `targetDocument`; a `project` naming another open project is refused by name, and a closed one is "no longer open" (L3). (AI-5; orig §3d, §8 part 1)
- **AI-7's table is one file, and ask-first happens before the lock.** `AssistantToolTable.swift` withholds the dev tools, `record_screen` and cloud `transcribe`, and puts `export`, `export_captions`, `save_project` and `consolidate_media` to the session's hook before the lane's lock, naming the path and saying REPLACES when a file is there — because A0 measured that `export` replaces an existing file without asking (E2). L5 11/11; the session proof's D, E and S rows (Deny writes nothing, Allow writes, Stop writes nothing). An MCP caller is never asked. (AI-7; orig §3f, §7 E, §8 parts 1 and 3)
- **A call mid-gesture waits for mouse-up.** A0 measured the loss: an agent edit between two drag ticks answered ok and was gone after the next tick, and Undo restored a mid-drag frame (D2, #144). Every main hop is `onMainWhenIdle`, retrying every 20 ms while any document is live-editing; L7 (`serve`) and L8 (`submit`) land the marker after mouse-up as its own undo step, and #144 was closed on them. (AI-12; orig §7 D, §8 part 1)
- **The helper gets an empty environment and the key on stdin.** Exactly `HOME`, `TMPDIR` and `PATH=/usr/bin:/bin`; the key is in `configure` and nowhere else. `proof-key` appeared in none of 25 MCP answers nor the log (K1); with no `-RCSecretFolder` no key file is opened and no helper starts (K2); the no-server launch W worked end to end. The Makefile `unexport`s `ANTHROPIC_API_KEY` beside `RC_ASSEMBLYAI_KEY` (`makefile_env_proof.py`). (AI-8, AI-13; orig §3i, §8 parts 2 and 3)
- **The pane holds views only, built once.** `AssistantPane` builds its one `AssistantView` in `init`, never in `makeSections()`; the session, the transcript's storage and the pending question live on the window's controller, so a rebuild keeps the composer's text and a floating window would be a new host (#160). (AI-4; orig §3e, §3h, §9)
- **The tab stays up through the assistant's own selection changes.** Its calls change the selection mid-turn; only a click on a clip shows Clip (the tab probe's P5). (AI-14; orig §9)
- **The prompt's facts are interpolated or checked, and the live context rides on the message.** The system prompt, search guide and compaction instructions are Swift literals whose backticked names, timescale, id kinds, topics and ask-first rows are held to the code by `make test` (F1–F7, each checker made to fail, M1–M4). The playhead, selection and open nest go in a `<reelcut_context>` block on each person message (S2), so the system prompt stays byte-stable for the cache and `agent/` stays one diff. (AI-15; orig §10)
- **Stop reaches a running export or transcribe through a per-call token (issue batch B15, #149).** The session makes an `AgentCallCancel` per call and passes it to `AgentLane.submit`; Stop cancels it, the lane answers a call already cancelled when it takes the lock "Cancelled by the user." without running it (L13), and while a call runs `AgentLane.callCancel` is its token, which `export` links to `Exporter.cancel()` (flags only, G-17) and the on-device `transcribe` to its `Transcriber.CancelToken`. The session proof's SX (a 240 s text clip's export, allowed with `stop_after: 2`) and ST (a ten-minute WAV's transcribe) answer the tool's own cancelled sentence within 5 s of the Stop, each made to fail by its mutant. Every other running call still finishes. (AI-16)
- **The spend cap is an upper bound.** `assistant_prompt_eval.py --live` prices at the priciest model `fallbacks: "default"` can bill: the worst POST $2.67, the floor $14.11, `SUGGESTED_CAP` $15; `--live` needs an explicit `--cap`. No spend was made; the live run is #157. (orig §10)

## What it built — where it lives now

- The helper: `agent/src/main.ts` (378), `agent/src/protocol.ts` (79), `agent/build.sh` (49), `agent/entitlements.plist` (11), `package.json`, `bun.lock`, `tsconfig.json`; `project.yml`'s "Build Agent Helper"; `make typecheck`'s last line.
- The lane and table: `AgentLane.swift` (224), `AssistantToolTable.swift` (130); wiring in the frozen `AgentServer.swift`, `main.swift`.
- The session: `AssistantSession.swift` (400), `AssistantConfiguration.swift` (132), `AssistantPrompt.swift` (163), `AssistantLiveContext.swift` (54), `EditorViewController+Assistant.swift` (150).
- The tab: `InspectorTab.swift` (73), `AssistantPane.swift` (45), `AssistantView.swift` (299), `AssistantTranscriptView.swift` (121), `AssistantTranscript.swift` (183), `AssistantContextMeter.swift` (105), `AssistantSettingsPane.swift` (207); View ▸ Assistant ⌃⌘A.
- Dev only: `AgentServer+Assistant.swift` (312: `assistant_send`, `assistant_answer`), `DevAssistantLaunch.swift` (175), rows in `AgentServer+DevTools.swift` (105).
- Proof: `assistant_spike/` (32 rows, B/H/C/F/T/E/D/L); `anthropic_fake.py` (285, the stand-in); `assistant_lane_proof.py` + `assistant_lane_probe.swift` (12 rows, in `make test`); `assistant_helper_proof.py` (P0–P5, two mutants); `assistant_session_proof.py` (11 rows); `assistant_tab_proof.py` + `assistant_tab_probe.swift` (16 rows); `assistant_prompt_proof.py` + `assistant_prompt_probe.swift` (F1–F7, M1–M4 in `make test`; S0–S3; E1–E6, H, K) and `assistant_prompt_eval.py` (696); `dist_check.py` (D1–D13) and `dist_check_mutants.py` (11 cases). `tools/proof/README.md` has each one's launch line.

## Known limits

- **Every turn has been against the stand-in**: nothing has reached api.anthropic.com, so whether a real model does the six asks right is unmeasured (#157), and end-of-turn compaction on the real API has never run (#161).
- **Ad-hoc signing only**: no Developer ID, notarization or quarantine; the app itself carries `get-task-allow` (#145).
- **`assistant_helper_proof.py` P1 skips** on a host with bun at a fixed path (`/opt/homebrew/bin`, `/usr/local/bin`), because `build.sh`'s own `PATH` finds it there.
- **The mid-drag row is reachable in a probe only**: no MCP tool begins a gesture; L8 measures `submit`, the session's one door.
- **F1 checks that a backticked token names something real**, not that the sentence around it is true.
- **A gesture held down holds the lane**, and every other caller with it (AI-12's accepted risk).

## Open items

- #145 the Distribution app is signed with `get-task-allow` beside `audio-input`.
- #147 Rasterize takes §2's change (one diff).
- #151 Chat Settings are not offered.
- #152 a question asked while the tab is hidden draws no attention.
- #153 the transcript cannot be selected across entries.
- #154 the composer is single-line.
- #157 the live evaluation with a key (`ready-for-human`).
- #159 the person check: the tab with a real key (`ready-for-human`).
- #160 candidate: the Assistant in a floating window.
- #161 end-of-turn compaction against the real API.

## Where to look in the original

- orig §1–§3: what Rasterize built, what carries over, and the nine things Reelcut needed that Rasterize did not (3a–3i).
- orig §4: the decisions as first written (AI-1..AI-11); §5 the phases as planned and as A0 changed them; §6 the user's four answers.
- orig §7 A0 record: rows B (the copy, the builds), H (signatures, `ready`, H6's entitlement), C (catalog size, the tool-search choice), F and T (the stand-in, a scripted turn), E (`export` replaces), D (the lost mid-drag edit), and the limits.
- orig §8 A1 record: part 1 the lane (L0–L9, C1, M1), part 2 the helper and its build (P0–P5, the mutants, the Rasterize outcome), part 3 the session (A0, T1–T2, R, D, E, S, X, K1, W, K2).
- orig §9 A2 record: the tab, Settings, the menu, the dev tools' `pane`, the tab proof's rows, screens 02 and 11b.
- orig §10 A3 record: the prompt, the drift rule, S/E/H/K, the spend arithmetic.
- orig §11 A4 record: D6–D13, the mutant cases, the corrected review lines, the issues filed at the close.
