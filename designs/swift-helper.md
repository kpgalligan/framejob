# Road map "swift-helper" — the assistant helper in Swift, on Slaude

**Status: designed, not built.** Opened 2026-11-11 by issue #599. No phase has started, no spec
§11 decision is written and no file but this one exists. The owner's questions are at the end
(§12); SA0 does not start until they are answered.

**Source.** The owner, on #599 (2026-11-12): "We're going to replace Bun with the Swift Anthropic
API we wrote. See ~/devel/doctored for background info. That had the same Typescript Anthropic
API, but now uses our new Swift API." And the decision comment (2026-11-13): "#599 Reference
doctored for the design".

**Written from** Doctored's record of the same move, `~/devel/doctored/designs/assistant-helper.md`
(decisions AH-1..AH-7, accepted 2026-11-03, shipped in its v0.4.4), read at Doctored's
`b524babc`, with the two commits that made it: `33af04c1` (the Swift helper in, the Bun helper
out) and `0bb54fc2` (the system block's cache breakpoint and the live acceptance driver). Its
package is `~/devel/doctored/agent/`, its build `~/devel/doctored/scripts/build_agent_helper.sh`.

**Related records.** `designs/adr/roadmap-12-assistant.md` (the helper, the agent lane, withheld
and ask-first tools, the tab and its prompt), `designs/adr/roadmap-13-pricing.md` (the price
table, the spend ledger, the proofs' budgets), spec §7.9b
(`designs/spec/07.9b-agent-lane-assistant.md`), spec §11 AI-1..AI-21
(`designs/spec/11-decisions/assistant.md`), P-1..P-9 (`designs/spec/11-decisions/pricing.md`),
PUB-10..PUB-12 (`designs/spec/11-decisions/publishing.md`), W-8
(`designs/spec/11-decisions/word-captions.md`) and NM-10 (`designs/spec/11-decisions/rename.md`).

Line numbers and counts in this file are `grep -n` and `wc -l` at `e2a918df` (main, 2026-11-11);
a phase re-reads them at its start. A figure marked **(Doctored)** was measured in Doctored's tree
on 2026-11-03 or 2026-11-04 and is not Frame Job's until SA0 measures it here.

Decisions this road map will need are numbered **SA-n**, and its phases **SA0..SA5**. `HS-` is
taken by the host-state rows of `docs/manual-checks.md`, `SH-` by the sharp handoff and `SW-` by
Switch by Speaker; `SA-` appears nowhere under `designs/spec/` or in the manual checks.

## 1. Goal

`Contents/Helpers/framejob-agent` becomes a Swift executable, built from a SwiftPM package in
`agent/` on the owner's Swift client for the Claude API, Slaude (`kpgalligan/Slaude`). Bun,
TypeScript, `node_modules`, the `allow-jit` entitlement and the LGPL notice leave the product and
its build.

**Unchanged for a person:** the Assistant tab, Chat Settings, the ask-first questions, Stop, the
conversation's Spend figure and Settings' month figure, where the key lives.

**Unchanged in code:** the process boundary; the helper's name and place in the bundle; the stdio
protocol, except what §5 lists; the app's `AssistantSession`, `AgentLane`, `AssistantToolTable`,
`AssistantPrompt` and `AssistantSpend` (comments only, §9 SA4); the price fixtures and
`tools/proof/prices.py`; the proofs' ledger and budgets.

## 2. What is true now

### The helper

- `agent/src/main.ts` (428 lines) runs a turn on `@anthropic-ai/sdk` ^0.128.0's
  `client.beta.messages.toolRunner` (line 246): 30 rounds at most, `max_tokens` 32000, three
  betas on every request and a fourth while clearing is on (lines 52-56, 266-268), the clearing
  constants (lines 47-49), compaction through the runner's `compactBeforeNextTurn` (line 319), and
  the three end-of-turn sentences, #484's among them (lines 326-332). `agent/src/protocol.ts`
  (97 lines) is the contract with the app.
- The runner owns the tool round trip. For each `tool_use` it calls the tool's `run`, which emits
  `tool_call` and `tool_request` and waits for the app's `tool_result` (lines 141-152). The
  helper's history is the runner's own copy, taken back in `finally` (line 344).
- **Pricing is live**, unlike Doctored's was. `configure` sets the prices up (lines 88, 93-104);
  every response and every compaction summary emits `cost` (lines 107-116, 293, 300); a response
  cut short is priced once as `partial` from the SDK's in-flight snapshot (lines 282-284,
  334-337; spec §11 P-8). `agent/src/pricing.ts` (196 lines) is the price function.
  `agent/src/priceTable.ts` (247 lines) holds the bundled table (imported from
  `agent/prices/anthropic.json`), the daily refresh from LiteLLM (`REFRESH_AFTER_MS` 86,400,000,
  a 30 s timeout, `user-agent: framejob-agent`), the atomic cache write and `feedProblem`'s
  https-or-loopback rule. Their suites are `agent/src/pricing.test.ts` and
  `agent/src/priceTable.test.ts`, run by `bun test` against `agent/prices/cases.json` and
  `agent/prices/reduce_cases.json`.
- The app sends `price_cache` and `price_feed` in `configure` (`app/Sources/AssistantSpend.swift`
  lines 58-75, merged at `app/Sources/AssistantSession.swift` line 133) and reads `cost` and
  `prices` for the ledger line, the transcript and the tab's figure (`AssistantSpend.swift` lines
  83, 149, 236).
- **Protocol nothing in the app uses.** The app writes only `configure`, `send`, `cancel`,
  `settings` and `tool_result` (`AssistantSession.swift` lines 126, 171, 196, 209, 360); it never
  writes `reset`. No file in `app/Sources` reads `message_done` or `ready`. The proofs do read
  two of them: `tools/proof/spend_proof.py` filters on `message_done` (line 435) and H10's verdict
  ends `"message_done" not in types` (line 520), the clause that says a cut reply was not reported
  as a complete one; `tools/proof/spend_probe.swift` (line 195) and
  `tools/proof/assistant_tab_probe.swift` (line 165) feed the app a `message_done` as a fixture;
  `tools/proof/assistant_helper_proof.py` P3 waits for `ready`.
- The app side is `Process`, pipes and GCD. The helper is
  `Contents/Helpers/framejob-agent` (`AssistantSession.swift` line 121), its environment exactly
  `HOME`, `TMPDIR` and `PATH=/usr/bin:/bin` (line 142), and events are read loosely as
  `[String: Any]`. A helper that keeps the protocol and the file name needs no change there.
- `AssistantSession.write` serialises with `JSONSerialization` and no `.sortedKeys` (lines
  363-368). Doctored's app writes every message with sorted keys, so the same catalog is the same
  bytes on every launch and the cached prefix survives a relaunch. Whether Frame Job's
  `configure` is byte-stable across launches today is not known; SA0 measures it (§9).

### Its build, its notices, its checks

- `agent/build.sh` is the one place bun is found and run: `helper` (the Xcode step "Build Agent
  Helper", `project.yml` line 400), `typecheck` (the last line of `make typecheck`, `Makefile`
  line 187) and `test` (`tools/proof/prices_proof.py` row T, in `make test`). Each fails with
  `error: bun is not installed` rather than skipping.
- The helper is signed `--options runtime` with `agent/entitlements.plist`, exactly
  `com.apple.security.cs.allow-jit`, which Bun's JavaScriptCore needs.
  `tools/proof/dist_check.py` holds both bundles to that (D10/D11, line 230) and
  `tools/proof/published_check.py` the published one (P8, line 179).
- `.github/workflows/publish.yml` installs Bun with `oven-sh/setup-bun` (line 97) at the version
  `acknowledgements.py --print-bun-version` prints (line 90).
- `tools/proof/gate.py` has `bun --version` in the tools' fingerprint (line 82) and `agent` among
  the inputs of `typecheck` and `app` (lines 70, 74). `tools/proof/proof_app.py` walks `agent`
  for staleness (line 41).
- `tools/proof/tree_copy.py` copies `agent/` without `node_modules` into every tree copy, makes
  the copy's `build/` a real directory and links only `build/codecs` to the tree's (its T2 and T6
  rows). Ninety-nine proof scripts name its `make_copy`, `build` or `base` entry points.
- `tools/licenses/acknowledgements.py` (line 199) reads npm packages from `agent/bun.lock`, checks
  `bun --version` against `BUN_LICENSE_VERSION` (lines 162-168, `--strict-bun`), and writes the
  `runtime bun` entry whose note names JavaScriptCore and WebKit as LGPL-2 (line 247), from the
  vendored `tools/licenses/bun/LICENSE.txt`. Sparkle's licence is already read from a resolved
  SwiftPM checkout (lines 48, 216-233), which is the pattern Slaude's will follow. D42/D43 and P25
  expect every npm package and `runtime bun`.
- **The notices depend on the helper's build step.** The npm reader takes each package's
  `package.json` and licence out of `agent/node_modules` and fails on one missing (lines 197-205),
  and the only thing in an app build that makes `agent/node_modules` is the Bun step's
  `bun install`: Write Acknowledgements runs after Build Agent Helper for that reason
  (`project.yml` lines 426-427). A tree copy copies `agent/` without `node_modules`
  (`tools/proof/tree_copy.py` lines 213-214), and the publish runner installs Bun but never runs
  `bun install` itself. So the npm reader cannot outlive the step it reads after: the phase that
  switches the step (SA3) changes the notices with it.
- The built helper is 57,735,840 bytes in the Debug bundle built on 2026-11-09.

### The proofs that touch the helper

- **They build or mutate the TypeScript:** `tools/proof/assistant_helper_proof.py` (P0-P5: the
  wiring, never-skips, signing, `ready`, the configure fields, a type error in `main.ts`);
  `tools/proof/spend_proof.py` (scratch helpers built by `build.sh helper`: `stale_helper` with
  `REFRESH_AFTER_MS = 0`, and `HELPER_MUTANTS` on `main.ts`, lines 735-800);
  `tools/proof/prices_proof.py` (row T and the `ts-disagrees` mutant);
  `tools/proof/assistant_settings_proof.py` (reads `CLEAR_TRIGGER_TOKENS` out of `main.ts`, line
  82); `tools/proof/docs_bugs_c1_proof.py` (a mutant anchored on `main.ts`'s #484 arm, line 152);
  `tools/proof/mutant_anchors.py` (lines 73, 105).
- **It mirrors the helper by hand:** `tools/proof/assistant_lane_probe.swift` (line 457 on), B1's
  measure of the request's fixed part, which spec §11 P-9 (d) accepts "until the helper is Swift
  (#599)".
- **They only run the bundled helper against the stand-in** `tools/proof/anthropic_fake.py`:
  `tools/proof/assistant_session_proof.py`, `tools/proof/assistant_tab_proof.py`,
  `tools/proof/assistant_settings_proof.py`, `tools/proof/assistant_prompt_proof.py`'s S rows,
  `tools/proof/spend_ui_proof.py`, and the rehearsals of
  `tools/proof/assistant_compaction_proof.py` and `tools/proof/assistant_clearing_proof.py`.
- **Credentials on the wire.** The stand-in accepts `x-api-key` or `authorization`
  (`anthropic_fake.py` line 90). The paid proofs' relay refuses anything but `x-api-key`
  (`tools/proof/assistant_prompt_eval.py` line 376), and `tools/proof/budget_proof.py` posts with
  it (line 438). Slaude sends `Authorization: Bearer`.

### The premises of the request, checked

- **Rasterize is Doctored.** `~/devel/rasterize` is a symlink to `~/devel/doctored`, and
  Doctored's `agent/` has no `src/`. The root `CLAUDE.md`'s "byte-identical to
  ~/devel/rasterize/agent/src/" therefore describes nothing that exists, and NM-10's three lines
  and #484's arm "for Rasterize to apply" have no file to land in.
- **W-8 is about `app/Sources`.** Its text names `SpeechEngine.swift` as "the ONE new file allowed
  `async`/`await`" beside `MediaImporter.swift` and ends "nothing else gains `async`"; AI-1 says
  "The Swift side uses `Process`, pipes and GCD, so W-8's `async` confinement holds". A helper in
  its own process and its own package adds no `async` to `app/Sources`. A decision is still
  needed, because W-8 names files and not a directory (SA-7, §8).
- **The app cannot link Slaude.** It builds in Swift 5 mode (`project.yml` line 66), and
  `make typecheck` and every probe compile `app/Sources` with no extra module. That is AH-1's
  reason, and it holds here unchanged.
- #161, #164, #380, #484 and #594 are closed. This road map cites them as history.

## 3. What Doctored did, and what carries over as it is

Doctored's helper was the same TypeScript, so its record answers most of the move.

- **AH-1, the process boundary and the stdio protocol stay.** Kept here for every reason AH-1
  gives: Slaude is async/await throughout; the app is Swift 5 mode with no extra module; a helper
  crash cannot take a document down; the key arrives only on stdin in a scrubbed environment; and
  Slaude's release compile stays out of the app target.
- **AH-2, a SwiftPM package in `agent/`.** swift-tools 6.0, Swift 6 mode; a library target with
  the codec, the tool-result conversion, the history, the request bodies, the turn loop and the
  context arithmetic behind a messages-client seam; an executable target with the stdin loop and
  the one stdout writer; XCTest over Slaude's injectable transport. Slaude pinned by exact
  revision with `Package.resolved` committed. Warnings as errors only in the test run, so a newer
  Xcode on the publish runner cannot fail the archive. Doctored's library is eleven files and
  1,162 lines, its executable 78.
- **AH-3, its own turn loop, not Slaude's tool runner.** Slaude's `BetaStreamingToolRunner` runs
  tools one at a time and rethrows a cancel out of a tool, which can leave a `tool_use` with no
  result and fail the next request. Doctored's loop keeps the TypeScript runner's dispatch (every
  `tool_use` of a response asked for at once, a cancel never ending a tool wait), keeps the
  history as `[RawJSON]` replayed byte for byte, builds each request body as raw JSON in a pinned
  key order, and makes compaction success one explicit rule.
- **AH-5, API version `2026-10-21`** and Bearer credentials, both Slaude's.
- **AH-6, the hardened runtime and no entitlements.** `allow-jit` was for JavaScriptCore alone.
- **AH-7, async/await in `agent/` only.**
- **The build script:** SwiftPM in a scrubbed environment, release compiled in batches without
  whole-module optimization, a content stamp that skips SwiftPM when nothing changed, `strip -x`,
  then the signature.
- **The instruments:** the suite (`make agent-test`), a stdio conformance drive of twelve cases
  against a loopback API (`~/devel/doctored/scripts/verify_agent_helper.py`), and a live
  acceptance run behind explicit spend flags
  (`~/devel/doctored/scripts/live_assistant_acceptance.py`).

## 4. The tool runner and the agent lane

The Tool Runner is the one part of the SDK the helper leans on that Slaude's equivalent cannot
replace (AH-3). The Swift helper writes its own loop, as Doctored's does:

- One streamed request per round. `tool_use` runs the tools and sends the next round; `pause_turn`
  resends; any other stop reason is the turn's final reply; thirty rounds end it.
- For every `tool_use` of a response, at once: `tool_call`, then `tool_request`, then a wait for
  every answer. A `tool_use` naming a tool that was not in `configure` is answered as an error
  without a request.
- A cancel closes the stream in flight and never ends a tool wait. The app answers each pending
  request "Cancelled by the user.", so every `tool_use` in the history keeps its `tool_result`.

**The agent lane takes no change, and this is why.** `AgentLane` (AI-2) serialises calls on the
app side: the session submits each `tool_request` through `AgentLane.submit`, one at a time, in
arrival order. That the helper emits several requests at once is today's behaviour and stays.
AI-5's document pin, AI-10's one undo step per call and AI-12's wait for mouse-up are the lane's
and the session's. AI-16's Stop cancels the running call's token in the app and writes `cancel`
to the helper; the helper's half (stop the stream, send nothing further, keep waiting for
answers) is the rule above.

**Withheld and ask-first tools take no change.** AI-7 and AI-21 are `AssistantToolTable`'s: a
withheld tool is never in `configure`'s catalog, the lane refuses one called anyway, and an
ask-first call is held in the app while "the helper's `tool_request` simply waits, so the helper
is unchanged" (AI-7's words). The Swift helper must keep exactly that: no timeout on a tool wait,
and no next API request while a tool answer is outstanding (the `tool_request`s of one response
still go out together, as above). SA1's suite has a case for a wait of arbitrary length and SA2's
drive a case where the answer arrives after a `cancel`.

## 5. Where Frame Job differs from Doctored

Doctored's record cannot answer these.

### Pricing stays, ported (the price table and the spend ledger, P-1..P-9)

Doctored removed pricing (AH-4) because its app never sent the price messages. Frame Job's is
live and shown to the person, so this road map ports it. Dropping it is the owner's question 1,
not a design choice.

| Piece | Today | After |
|---|---|---|
| The price function (P-2) | `agent/src/pricing.ts`, `bun test` on `agent/prices/cases.json` | `Pricing.swift` in the package, the same cases in `swift test` |
| The table and its refresh (P-1, P-5) | `agent/src/priceTable.ts`, `fetch`, `bun test` on `agent/prices/reduce_cases.json` | `PriceTable.swift`, on `URLSession` with the same URL, user-agent, 30 s timeout, feed rule and atomic write; the same cases |
| The bundled table | imported into the Bun binary | compiled into the helper (SwiftPM's `.embedInCode`), the file staying at `agent/prices/anthropic.json` if SA0 shows a resource outside the target can be embedded, else copied into the target by the build script |
| `prices`, `cost`, `price_cache`, `price_feed` | protocol | kept, the same shapes |
| The partial price (P-8) | the SDK's snapshot of the response in flight | Slaude's `currentMessageSnapshot` on its raw-JSON stream (`Sources/Anthropic/Lib/Streaming/JSONMessageStream.swift` line 127 at the pinned revision), which Doctored does not use |
| A turn's prices fixed at `turn_started` (P-5) | `turnPrices` | the same |
| The spend ledger, the tab's and Settings' figures (P-4, P-7) | `app/Sources/AssistantSpend.swift` | untouched |
| The second reader (P-2's cross-check) | `tools/proof/prices.py`, "`pricing.ts`'s `price` in Python, step for step" | untouched but for its comments; it becomes the Swift function's cross-check |
| `make prices`, `agent/prices/update.py` | the table's only writer | untouched |
| The proofs' ledger and budgets (P-3, P-6, P-9) | `tools/proof/budget.py`, `tools/proof/budget_proof.py` | untouched but for the relay's header (below) |

The port is two files of about 450 lines together in TypeScript. Two things need care, and SA1
has a case for each: `pricing.ts` adds a class's cost in a fixed order in doubles, which
`prices.py` mirrors and the Swift must too; and P-8's lower bound must not move, so a response cut
before `message_delta` is priced from `message_start`'s counts and nothing else.

### Compaction and clearing (#161, #484, AI-9, AI-18, AI-20)

- **What stays:** compaction only at a turn's end, after a final reply, never after a cancel, once
  `used` reaches `auto_compact_tokens`; `null` never compacts; a `settings` message applies from
  the next turn; the events `compaction_started`, `compacted`, `compaction_failed`; the three
  betas; clearing as `context_management` with the fourth beta, at 150,000 / 50,000 / keep 5.
  AI-18's dev knob is the app's and is untouched.
- **What changes, because the runner's implicit compaction becomes AH-3's explicit rule.** Three
  behaviours, each a decision (SA-4) and each with a suite case:
  1. A final reply that ends in `tool_use` blocks (a `max_tokens` cut after a tool call) has each
     block answered at once, unrun, so the next request is valid. Today the runner's history can
     end with an unanswered `tool_use`.
  2. After such a reply no summary request is sent; the helper emits `compaction_started` and
     `compaction_failed` "no summary came back", and the next turn end tries again.
  3. A `compaction` stop whose block has `null` or empty content is a failure ("the summary came
     back empty"), not a swap. Today the history would be swapped for an empty summary.
- **#484's sentence stays.** Doctored ends `model_context_window_exceeded` silently. Frame Job
  emits "The reply was cut off because the conversation filled the model's context window.",
  which the site documents and `tools/proof/docs_bugs_c1_proof.py` holds with a mutant. The Swift
  helper keeps the sentence and the proof's mutant moves to the Swift arm.
- `CLEAR_TRIGGER_TOKENS` moves into the package, and `assistant_settings_proof.py` reads it from
  there.

### The protocol

- **Kept:** every message and event the app or a proof reads, `message_done` included. It costs
  one line per response, and `spend_proof.py`'s H10 needs it to be able to fail. `ready` is kept
  as the acknowledgement P3 waits for.
- **Dropped:** `reset`, which nothing sends (Clear closes the process). If a later phase wants
  `message_done` gone, it names the four sites in §2 in the same change and replaces H10's clause
  with one that can still fail (no non-partial `cost` for the cut reply).
- The helper answers a bad line and ignores an unknown type as Doctored's does. The error
  sentences the tab prints (`API error <status>: …`, "The assistant is busy.", "The assistant
  helper was not configured.") are pinned by the suite against today's wording.

### The request

- **Body.** Today's fields and values (`main.ts` lines 247-270), built as raw JSON in a pinned
  key order, so a conversation's requests are the same bytes in every process.
- **The system block's own cache breakpoint** (Doctored's `0bb54fc2`). Today the only breakpoint
  is the automatic one on the newest block, so a new conversation, and the first request after a
  compaction, writes the tools-and-system prefix again. Doctored measured about 9,700 tokens
  written without it and read with it **(Doctored)**; Frame Job's prefix is larger (the
  rehearsals of 2026-11-11 sent bodies up to 399,360 bytes, P-9). Adopting it changes what a
  person is billed, in their favour, and changes the request's bytes: a decision (SA-5).
- **B1.** The breakpoint and the key order change the bytes `assistant_lane_proof.py`'s B1 and
  the paid proofs' `BODY_BYTES_BOUND` measure. SA3 re-measures B1 from the built helper's real
  first POST, which retires the hand mirror P-9 (d) accepts.
- **Sorted keys from the app.** If SA0 finds `configure`'s catalog is not the same bytes on every
  launch, the app's `write` gains `.sortedKeys`: one option in `AssistantSession.swift`, the only
  app-side behaviour change in this road map, and a decision (SA-5).
- **Platform.** `.macOS(.v26)`, the app's floor (`project.yml` line 5); Doctored's package says
  15.
- **API version `2026-10-21`.** AH-5's five checks, redone against Frame Job's requests in SA0:
  no sampling parameters; assistant messages only the API's own replies; user messages the typed
  text (behind the `<framejob_context>` block, AI-15) and `tool_result` blocks of text and base64
  images (`render_frame`, `render_graphic`); no Admin or Analytics call; `GET /v1/models/{id}`
  for the context meter.
- **Bearer credentials.** The stand-in names `authorization` among its credential headers, and
  SA0 confirms a Bearer value passes it. The relay
  (`assistant_prompt_eval.py` line 376) and `budget_proof.py`'s row learn `Authorization: Bearer`
  in SA3. AI-13's override and AI-8's key path are the app's and do not change.

## 6. The prompt and its proofs

The prompt is the app's: `AssistantPrompt.swift` writes `system`, `search_guide`,
`compaction_instructions` and the core tools into `configure`, and the live context rides on each
message (AI-15). None of it moves.

- `assistant_prompt_proof.py --probe` (F1-F8, M1-M6, in `make test`) compiles the app's texts and
  never runs a helper. Untouched.
- Its S rows read the helper's POSTs at the stand-in: S1 "POST 1's system is `system`, a blank
  line, `search_guide`" must read the text inside the system block once it carries a breakpoint;
  S2's append-only check and S3's compaction instructions hold as they are. SA3 runs them.
- The evaluation (`assistant_prompt_eval.py`, E1-E6 and H) is paid and is SA5's, behind
  `--live --cap`.

## 7. How it fits the tree

```
agent/
  Package.swift            swift-tools 6.0, Swift 6 mode, .macOS(.v26); Slaude by exact revision
  Package.resolved         committed
  Sources/FrameJobAgentKit/  Doctored's eleven files (Protocol, LineSplitter, Session, Turn,
                           Compaction, Request, History, ContextUsage, ToolResults, ClientFactory,
                           Log) plus Pricing.swift and PriceTable.swift; each under 400 lines
  Sources/framejob-agent/main.swift   the stdin loop and the one stdout writer
  Tests/                   XCTest; no network, dummy keys
  prices/                  as today
  CLAUDE.md                the package's rules (owed at SA1, applied by the integrator)
tools/agent/build_helper.sh   Doctored's script: scrubbed environment, batches, stamp, strip, sign
build/agent-swift/         SwiftPM's scratch path (ignored, per worktree)
```

- **Vendored, a package, or copied.** A SwiftPM dependency of `agent/` alone, pinned by exact
  revision, with `Package.resolved` committed, as Doctored has it.
  - *Not vendored.* Slaude is 2,385 Swift source files at the pinned revision, transformed from the
    official Python SDK. In this tree they would sit under `tools/proof/name_residue.py`, the
    size ledger and every `git grep`, for no gain: the pin already fixes the bytes.
  - *Not copied piecemeal.* The client core, the SSE stream and the retries are tested as a
    whole (about 3,800 tests **(Doctored)**), and a copy would leave that behind.
  - *Not linked into the app.* §2's third premise.
  - *The cost.* The first build of a worktree fetches from GitHub, as the encoders' tarballs
    already do (`make codecs`), and compiles Slaude (§10).
- **Slaude's facts** (read from Doctored's checkout at revision
  `4c6c2ca435350741796c3d461720a61e7149b378`): public, Apache-2.0, Foundation only, one target
  `Anthropic`. Whether it has moved past that revision since, and whether Frame Job pins the same
  one, is SA0's.
- **`make`.** A new `make agent-test` (`swift test` on the scratch path, warnings as errors) is a
  line of `make test`. `make typecheck` loses its tsc line and gains nothing: the package is
  checked by its own build and suite, and W-8's four-warning baseline is about `app/Sources`.
  `make app`, `app-debug` and `dist` build the helper in the same Xcode step, through the new
  script.
- **The gate.** `gate.py`'s tools lose `bun --version`; `agent` leaves `typecheck`'s inputs and
  stays in `app`'s; `tools/agent` joins `app`'s.
- **Tree copies.** A proof's tree copy has a real `build/` with only `build/codecs` linked, so
  each proof that builds an app through `tree_copy.py` would compile Slaude from
  nothing where Bun took well under a second. A copy gets the scratch path as a clone (`cp -c`),
  with the stamp deciding reuse, and never as a link the way `build/codecs` is: a copy never
  changes the encoders' inputs, but a copy that builds a helper mutant changes the helper's on
  purpose, and through a link that mutant would become the tree's product (Doctored's script
  copies the one product path out to strip and sign it after `swift build` has returned and
  released SwiftPM's lock, so a tree build beside it could bundle the copy's helper). A link is
  safe only for a copy whose `agent/` is byte-identical to the tree's, and is not worth a second
  rule. SA0 measures a clone's app build; SA3 changes `tree_copy.py`'s copy rule and its T rows
  with it.

## 8. The spec §11 decisions each phase will need

Named here, written by the phase that needs each, before its code. New decisions go in a new
`designs/spec/11-decisions/swift-helper.md` with their index rows.

| Decision | Phase | What it settles |
|---|---|---|
| SA-1 | SA0 | The helper is a Swift executable from a SwiftPM package in `agent/`, on Slaude by exact revision; the process boundary and the protocol stay. Amends AI-1 (Bun, the Tool Runner, "the one TypeScript in the product", the accepted risk of Bun in every `make app`). |
| SA-2 | SA0 | Its own turn loop, verbatim history, raw-JSON bodies in a pinned order; every `tool_use` answered; a cancel never ends a tool wait. |
| SA-3 | SA0 | Pricing in the Swift helper (or what question 1's answer makes of it). Amends P-2 and P-8 where they say "the SDK". |
| SA-4 | SA1 | The explicit compaction rule and its three changed behaviours (§5). Amends AI-9's and AI-20's pointers to `main.ts`. |
| SA-5 | SA1 | The request: the system block's breakpoint, the key order, API version `2026-10-21`, Bearer credentials, and sorted keys from the app if SA0 calls for them. Amends AI-13's pointer to `protocol.ts`. |
| SA-6 | SA1 | The protocol: `reset` dropped, `message_done` and `ready` kept. |
| SA-7 | SA1 | **W-8's edge.** async/await and actors are the concurrency model of `agent/` and of nothing else; W-8 and its two files govern `app/Sources`, which gains no `async`. W-8 is not amended, only bounded. |
| SA-8 | SA3 | The build: the script, the scratch path, release in batches, the stamp, the hardened runtime and no entitlements. Amends D10/D11 and P8's contract. |
| SA-9 | SA3 | B1 measures the built helper's first POST. Amends P-9 (d). |
| SA-10 | SA3 | The Acknowledgements and the publish runner, in the commit that switches the build step (§2: the npm reader reads what that step installs): npm and Bun out, Slaude in, `setup-bun` gone. Amends PUB-10 (its npm and Bun sentences and the LGPL risk line) and PUB-12 (`setup-bun`). |
| SA-11 | SA4 | What the tie to Doctored becomes (question 2). Amends AI-15's "`agent/` is one diff with Rasterize" and NM-10. |

## 9. Phases

Each phase is its own commit, builds, and passes its own checks. Each has a mutant per decision
it adds. No phase spends money except SA5, and only with the flags it names.

### SA0 — the spike (no product code)

Measured in this tree, in a scratch folder, and recorded here before SA1:

1. Doctored's package builds against the pin under this Xcode (Swift 6.2.3) with `.macOS(.v26)`.
2. Cold and warm build time and peak memory here, release in batches and debug.
3. A tree copy's app build with the helper step in it, its scratch path a clone of the tree's
   (§7), against a cold one.
4. `.embedInCode` with the table at `agent/prices/anthropic.json`.
5. What `currentMessageSnapshot` holds at a cancel before and after `message_delta`, against
   P-8's lower bound and `spend_proof.py`'s H10-H12.
6. The Bearer header against `anthropic_fake.py`.
7. AH-5's five checks against Frame Job's own request (§5).
8. Whether `configure`'s bytes are the same across two launches (§2).
9. Whether a helper mutant built in a clone of the scratch path compiles only what it changed
   (SwiftPM's build state records absolute paths, so a clone used from a copy's package path may
   recompile), and that the tree's product is left as it was, since `spend_proof.py` builds
   three scratch helpers.
10. Whether Slaude has moved past the pin, and what the move holds.

It writes SA-1..SA-3. **Proof:** the measurements, each with its command and output.

### SA1 — the package, beside the Bun helper

The library, the executable, the suite, `make agent-test` in `make test`, `agent/CLAUDE.md`.
Nothing is bundled yet: the app still ships the Bun helper.

**Proof:** the suite. Doctored's acceptance list (the codec both ways; the tool-result
conversion; the `send` merge; the refusals; full turns with deltas, a multi-tool round with an
image, a cancel mid-stream and one with tools pending, `refusal` and `max_tokens`, a final
reply's unrun calls, 429/529 with `retry-after`, a mid-stream error, `pause_turn`, compaction
success, failure and an empty summary, settings changed mid-turn; byte-identical replay) plus
Frame Job's: `cases.json`, `reduce_cases.json`, the refresh (due, not due, a refused feed, a
failed fetch, the atomic write), the partial price, a turn keeping its prices through a refresh,
#484's sentence, `message_done`, a tool wait of arbitrary length. One mutant per decision of
SA-4..SA-6.

### SA2 — conformance against the helper it replaces

A stdio drive, `tools/proof/agent_helper_drive.py`, runs **both** helpers (the Bun one and the
Swift one) as the app does, over the same scripted conversations on `anthropic_fake.py`, and
compares the event streams and the request bodies. The differences it allows are an explicit
list, each row naming its SA decision: the system block's breakpoint, the key order, the
credential header, the API version, the three compaction behaviours.

This is the red-then-green Doctored could not have: any other difference fails. It exists only
while both helpers do, so it runs before any deletion. Its cases stay afterwards as the Swift
helper's drive.

### SA3 — the switch

- `project.yml`'s step calls `tools/agent/build_helper.sh`; no entitlements.
- D10/D11 and P8 become "the `runtime` flag and no entitlements", with their mutants in
  `tools/proof/dist_check_mutants.py`.
- `proof_app.py`'s walked inputs and `tree_copy.py`'s copy rule and T rows (§7), with
  `tools/proof/makefile_env_proof.py`'s account of the copy (lines 34-35), whose reason for
  leaving `node_modules` out (the helper's step runs `bun install`) stops being true here.
- The helper-building proofs are repointed: `spend_proof.py`'s `stale_helper` and
  `HELPER_MUTANTS`, `assistant_helper_proof.py`'s rows rewritten for SwiftPM (P1's "never skips"
  becomes "a failed SwiftPM build fails the app build"), `prices_proof.py` row T and its mutant,
  `assistant_settings_proof.py`, `docs_bugs_c1_proof.py`, `mutant_anchors.py`.
- B1 measures the built helper's first POST; the relay and `budget_proof.py` learn Bearer.
- **The notices and the publish runner, with the switch** (SA-10; §2 says why they cannot wait
  for SA4, which would leave every tree copy's and the runner's build failing at Write
  Acknowledgements, and the main tree's bundle with Slaude unlisted and Bun listed):
  - Out: `acknowledgements.py`'s npm reader, `--strict-bun`, `--print-bun-version`,
    `BUN_LICENSE_VERSION`, the Bun entry and the `bun-unchecked` mutant;
    `tools/licenses/acknowledgements_selftest.py`'s npm and Bun rows (N1, N2, B1) and their
    fixtures; `tools/licenses/bun/` with its row and its "Re-vendoring Bun's licence" section in
    `tools/licenses/PROVENANCE.md`; `project.yml`'s `--strict-bun` and its step's comment;
    `dist_check.py`'s `shipped_npm` and its `runtime bun` row; `publish.yml`'s `setup-bun` step,
    the pins step's bun output and their comments, since once the step is switched nothing on the
    runner runs Bun, and the pin they read leaves with the Bun entry.
  - In: Slaude's Apache-2.0 `LICENSE`, read from the resolved checkout as Sparkle's is, under a
    `package slaude <revision>` header (a new kind in `dist_check.py`'s `ACK_HEADER`), with its
    D42/D43/P25 rows and a mutant.
  - **The LGPL notice goes** with the Bun entry: nothing left in the bundle embeds
    JavaScriptCore. #380's review is then moot, and PUB-10's accepted risk is struck by SA-10.
  - The texts that say what the file holds change with it: the site's
    `docs/site/src/content/docs/reference/open-source.mdx` (line 21), `docs/developing.md`'s
    acknowledgements and Bun-pin paragraphs (lines 213-241) and its layout's `tools/licenses/`
    entry (line 109), the `Makefile`'s `make dist` comment (lines 148-149), D42/D43/P25's own
    wording and their rows in `tools/proof/README.md`.
  - Bun stays a build tool until SA4 only for `make typecheck`'s tsc, `gate.py`'s fingerprint
    and SA2's two-helper drive, none of which reads the notices.
- **CLAUDE.md edits owed** to the integrator in this phase, each a line the switch makes untrue:
  the root's `make test` row ("the bun lock's nested keys"), its paragraph naming `make app` and
  `make dist` among what needs bun, its File map's `tools/licenses/` entry; and
  `mcp-proxy/CLAUDE.md` line 11, which compares the proxy's signing with
  `agent/build.sh helper`'s.
- **Proof:** every stand-in assistant proof of §2 run whole, once, on Release; `make dist`; a
  tree copy's app build (`tools/proof/makefile_env_proof.py`) passing Write Acknowledgements with
  no `agent/node_modules` in it.

### SA4 — deletion

- **Deleted:** `agent/src/`, `agent/package.json`, `agent/bun.lock`, `agent/tsconfig.json`,
  `agent/entitlements.plist`, `agent/build.sh`; `.gitignore`'s `node_modules` line; the
  `Makefile`'s tsc line; `gate.py`'s `bun --version`; SA2's two-helper comparison (its cases
  stay). The notices and the publish runner left Bun in SA3.
- **Retired:** `tools/proof/assistant_spike/`, road map 12's A0 spike, with its section of
  `tools/proof/README.md`. It builds a copy around Rasterize's TypeScript `agent/`, runs `bun`
  and reads `bun.lock`, and Rasterize's `agent/` has held only a SwiftPM package since Doctored's
  `33af04c1`, so it cannot pass today either; its record stays in
  `designs/adr/roadmap-12-assistant.md`, and nothing in `make test` or `make gate` runs it.
- **Comments in `app/Sources`** that cite the TypeScript as the contract are repointed (comment
  only, so a frozen file takes them as wiring; no behaviour change):
  `app/Sources/AssistantSession.swift` line 16, `app/Sources/AssistantPrompt.swift` line 4,
  `app/Sources/AssistantConfiguration.swift` lines 34, 43, 153 and 186,
  `app/Sources/AssistantSpend.swift` lines 7 and 58. The same in
  `tools/proof/assistant_prompt_eval.py` (line 40), `tools/proof/prices.py` (lines 5, 30-31, 184)
  and `tools/proof/assistant_lane_probe.swift`.
- **Documents:** spec §7.9b and §8 (`designs/spec/08-repo-layout.md`), `docs/developing.md`'s
  prerequisites and layout (bun as a build tool, `agent/` as Bun), `README.md` line 208 and
  `tools/proof/README.md`. The root `CLAUDE.md`'s remaining lines on bun in Commands, its File
  map's `agent/` entry and its Rasterize-tie lines are listed for the integrator (SA3 owed the
  rest).
- **Proof:** `make gate`; `make dist`; a grep for `bun` across the tree answering only history.

### SA5 — the live run and the close

- The paid proofs question 3 chooses, serially, each with its flags and its dollars reported.
- `docs/manual-checks.md`'s AS-1, AS-4, AS-5 and AS-6 are marked for the owner to run again: a
  real conversation, what a turn cost, what a conversation and the month cost, a reply cut short.
- The close: `designs/adr/swift-helper.md`, this file moved to `archive/swift-helper.md` with its
  index row, residue filed as issues.

## 10. Build and publishing cost

Every figure here is **(Doctored)** until SA0 measures it in this tree.

- A worktree's first app build compiles Slaude in release: 148 s cold, with a 2.1 GB tree peak at
  three jobs and 3.2 GB at twelve. Bun took about 0.2 s. Later builds are skipped by the stamp
  (the phase's no-op is under a second).
- `make agent-test` compiles it once more in debug: 60 s cold, a 3.7 GB tree peak.
- The helper is 35.5 MB stripped where Bun's is 57.7 MB.
- On the publish runner (`macos-26`, the image `publish.yml` line 44 uses here) SwiftPM built
  Slaude and the helper in 279.5 s with no memory failure, and the archive step took 20 min 2 s
  against 19 min 11 s for the last Bun build.
- Whole-module optimization of Slaude peaks at 10.6 GB in one compiler process, past the runner,
  which is why release compiles in batches.
- If a later Slaude outgrows the runner, the levers are the debug configuration and a larger
  runner.

## 11. Accepted risks, carried from Doctored

- **Slaude is young and has one maintainer**, the owner. Its transformation and tests track the
  official Python SDK, and Doctored has shipped on it since 2026-11-04; nobody else uses it.
- **The pin's cadence.** A new API feature or fix reaches the helper only through a commit that
  moves the pin and runs the suite and the gate.
- **The compile**, on every worktree's first build and on the publish runner (§10).
- **The first build needs the network**, to fetch Slaude.
- **A second Swift toolchain mode in the tree.** The package is Swift 6 with actors; the app is
  Swift 5 with GCD. SA-7 keeps them apart by directory.

## 12. Questions for the owner

Each has a recommendation; the phases above are written for the recommended answers.

1. **The spend figures.** Doctored dropped pricing when it made this move, because nothing there
   showed it. Frame Job shows two figures (P-7) and keeps a ledger.
   - (a) Keep both, with pricing ported into the Swift helper. **Recommended:** P-2 and P-7 stand,
     the fixtures and the Python cross-check already exist, and the port is two files.
   - (b) Keep both, but price in the app from the helper's `usage`. The helper gets smaller, and
     the app gains the table, its refresh and a network fetch in `app/Sources`.
   - (c) Drop pricing as Doctored did. The tab's Spend row, Settings' month line and the ledger
     go, with P-1, P-2, P-4, P-5, P-7 and P-8; SA1-SA4 lose every pricing item above, and the
     proofs' own budget (P-3, P-6, P-9) is unaffected.
2. **What the tie to Doctored becomes.** The byte-identical rule has had no counterpart since
   Doctored deleted its TypeScript.
   - (a) Frame Job's package is its own, ported once from Doctored at a named commit, with no
     identity rule. **Recommended:** the two already differ in pricing, #484's sentence, the
     platform and their names, and a shared rule with no checker is the kind that rots.
   - (b) A third repository holding the shared loop, which both apps depend on.
   - (c) A byte-identical rule for the shared files, with a diff check in `make test`.
   - With any answer, the Rasterize-side issues have nothing left to apply and are the owner's to
     close: rasterize#654 is NM-10's three lines (`designs/adr/rename.md` line 84), and
     rasterize#325 is road maps 12 and 13's hand-over of the helper change and of `pricing.ts` /
     `priceTable.ts` (`designs/adr/roadmap-12-assistant.md` line 67,
     `designs/adr/roadmap-13-pricing.md` line 50). #484's arm was never filed there.
3. **The paid acceptance after the switch.** Three live proofs exist: compaction
   (`assistant_compaction_proof.py --live --cap 11.50`), clearing
   (`assistant_clearing_proof.py --live --cap 5`, the run AI-20 says is owed) and the prompt
   evaluation (`assistant_prompt_proof.py --live --cap 32`). Their caps sum to $48.50 against the
   month's $40 (P-9). Each request reserves its own worst case and settles at its real price
   (P-6), and the last full evaluation settled $0.53, so run one after another they fit a month
   that holds little other spend.
   - (a) All three, serially, in one month, each reported. **Recommended:** the switch changes
     every byte the helper sends, which is what these runs test.
   - (b) Compaction and clearing only.
   - (c) None; the stand-in runs and the manual checks carry it.
4. **Who changes Slaude** when the port needs something it lacks.
   - (a) An agent files the need on `kpgalligan/Slaude`; the owner lands it; the pin moves in its
     own commit here. **Recommended:** it keeps this repository's agents out of another
     repository.
   - (b) Agents may commit to Slaude directly.
5. **The build cost** (§10).
   - (a) Accept it. **Recommended:** it is what compiling Slaude costs, once per worktree.
   - (b) Local app builds use SwiftPM's debug configuration (60 s cold against 148 s, for a
     larger and slower helper **(Doctored)**) and only Distribution builds release.
6. **The system block's cache breakpoint** (§5). It lowers what a new conversation costs and
   changes the request.
   - (a) Adopt it with the switch. **Recommended:** Doctored measured the saving live.
   - (b) Switch first with today's request, and adopt it as its own change afterwards, so SA2's
     comparison allows one difference fewer.

## 13. Records

Each phase's record goes under its heading here when it lands: what landed, what was measured,
what its review found, what is owed.

### SA0 — record

### SA1 — record

### SA2 — record

### SA3 — record

### SA4 — record

### SA5 — record
