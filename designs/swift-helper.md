# Road map "swift-helper" — the assistant helper in Swift, on Slaude

**Status: approved 2026-11-12, being built.** Opened 2026-11-11 by issue #599. The owner approved
it on #599 on 2026-11-12 and answered the six questions of §12, which now holds the answers. SA0,
the spike, has landed: its record is in §13, and it wrote SA-1..SA-3 in
`designs/spec/11-decisions/swift-helper.md`. SA1, the package beside the Bun helper, has landed
with SA-4..SA-7 and SA-12; its record is in §13. SA2 is next.

**Source.** The owner, on #599 (2026-11-12): "We're going to replace Bun with the Swift Anthropic
API we wrote. See ~/devel/doctored for background info. That had the same Typescript Anthropic
API, but now uses our new Swift API." And the decision comment (2026-11-13): "#599 Reference
doctored for the design". And the approval (2026-11-12): "For Bun replacement, Slaude changes. I
would like you to push changes to Slaude, not just make them locally. They can be a PR.
Everything else, as recommended".

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
a phase re-reads them at its start. SA0 re-read them at `e0206243` (2026-11-12) and none had
moved: of the files cited by line, only `app/Sources/AssistantPrompt.swift` had changed, below the
line cited. A figure marked **(Doctored)** was measured in Doctored's tree on 2026-11-03 or
2026-11-04; §10 sets the figures SA0 measured here beside them.

Decisions this road map will need are numbered **SA-n**, and its phases **SA0..SA5**. `HS-` is
taken by the host-state rows of `docs/manual-checks.md`, `SH-` by the sharp handoff and `SW-` by
Switch by Speaker; `SA-` appeared nowhere under `designs/spec/` or in the manual checks when it was
chosen.

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
  bytes on every launch and the cached prefix survives a relaunch. Frame Job's `configure` is
  not: SA0 caught two launches' lines, the same once parsed and different in key order at every
  level, and so was the tools-and-system prefix the Bun helper sent from them (§13, SA0 item 8).

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
live and shown to the person, so this road map ports it: the owner's answer 1 (a) (§12), recorded
as SA-3.

| Piece | Today | After |
|---|---|---|
| The price function (P-2) | `agent/src/pricing.ts`, `bun test` on `agent/prices/cases.json` | `Pricing.swift` in the package, the same cases in `swift test` |
| The table and its refresh (P-1, P-5) | `agent/src/priceTable.ts`, `fetch`, `bun test` on `agent/prices/reduce_cases.json` | `PriceTable.swift`, on `URLSession` with the same URL, user-agent, 30 s timeout, feed rule and atomic write; the same cases |
| The bundled table | imported into the Bun binary | compiled into the helper (SwiftPM's `.embedInCode`): the file stays at `agent/prices/anthropic.json`, the target holds a committed relative symlink to it and names that, and the build's stamp digests the table's content (§13, SA0 item 4) |
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
- **Sorted keys from the app.** `configure` is different bytes on every launch today, and so is
  the tools-and-system prefix the Bun helper sends from it (§13, SA0 item 8), so the app's `write`
  gains `.sortedKeys`: one option in `AssistantSession.swift`, the only app-side behaviour change
  in this road map, and a decision (SA-5). Without it the system block's breakpoint cannot be read
  back after a relaunch. The phase that writes SA-5 places the change and proves it with a row of
  two launches and one digest.
- **Platform.** swift-tools 6.0 with `platforms: [.macOS("26.0")]`, the app's floor (`project.yml`
  line 5); Doctored's package says 15. The spelling `.v26` needs PackageDescription 6.2 and is
  refused under 6.0, so the string form is deliberate (§13, SA0 item 1; SA-1).
- **API version `2026-10-21`.** AH-5's five checks, redone against Frame Job's requests in SA0,
  all of which hold (§13, SA0 item 7): no sampling parameters; assistant messages only the API's
  own replies; user messages the typed text (behind the `<framejob_context>` block, AI-15) and
  `tool_result` blocks of text and base64 images (`render_frame`, `render_graphic`); no Admin or
  Analytics call; `GET /v1/models/{id}` for the context meter.
- **Bearer credentials.** The stand-in names `authorization` among its credential headers, and
  SA0 confirmed a Bearer value passes it (§13, SA0 item 6). The relay
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
- The evaluation (`assistant_prompt_eval.py`, E1-E6 and H) is paid, behind `--live --cap`, and
  is one of the three runs of the owner's answer 3, after SA4 has landed and before SA5's close
  (§12, §9 SA5).

## 7. How it fits the tree

```
agent/
  Package.swift            swift-tools 6.0, Swift 6 mode, .macOS("26.0"); Slaude by exact revision
  Package.resolved         committed
  Sources/FrameJobAgentKit/  Doctored's eleven files (Protocol, LineSplitter, Session, Turn,
                           Compaction, Request, History, ContextUsage, ToolResults, ClientFactory,
                           Log) plus Pricing.swift, PriceTable.swift and PriceRefresh.swift, and
                           anthropic.json, the symlink to prices/; each under 400 lines
  Sources/framejob-agent/main.swift   the stdin loop and the one stdout writer
  Tests/                   XCTest; no network, dummy keys
  prices/                  as today
  CLAUDE.md                the package's rules (owed at SA1, applied by the integrator)
tools/agent/build_helper.sh   Doctored's script: scrubbed environment, batches, stamp, strip, sign
tools/agent/agent_test.py     `make agent-test`: the scratch-path guard, then the suite (SA-12)
build/agent-swift/         SwiftPM's scratch path for the release helper (ignored, per worktree)
build/agent-swift-test/    the suite's own debug scratch path (ignored, per worktree; SA-12)
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
  `Anthropic`. SA0 found it has not moved past that revision (its `main` is that revision on
  2026-11-12), and Frame Job pins the same one (§13, SA0 item 10; SA-1).
- **`make`.** A new `make agent-test` (`swift test` on its own scratch path, warnings as errors,
  SA-12) is a line of `make test`. `make typecheck` loses its tsc line and gains nothing: the package is
  checked by its own build and suite, and W-8's four-warning baseline is about `app/Sources`.
  `make app`, `app-debug` and `dist` build the helper in the same Xcode step, through the new
  script.
- **The gate.** `gate.py`'s tools lose `bun --version`; `agent` leaves `typecheck`'s inputs and
  stays in `app`'s; `tools/agent` joins `app`'s.
- **Tree copies.** A proof's tree copy has a real `build/` with only `build/codecs` linked, so
  each proof that builds an app through `tree_copy.py` would compile Slaude from
  nothing where Bun took well under a second. A copy gets the scratch path as a clone
  (`cp -cRp`, as `make_base_copy` already clones `core/target`), with the stamp deciding reuse,
  and never as a link the way `build/codecs` is: a copy never
  changes the encoders' inputs, but a copy that builds a helper mutant changes the helper's on
  purpose, and through a link that mutant would become the tree's product (Doctored's script
  copies the one product path out to strip and sign it after `swift build` has returned and
  released SwiftPM's lock, so a tree build beside it could bundle the copy's helper). A link is
  safe only for a copy whose `agent/` is byte-identical to the tree's, and is not worth a second
  rule. SA3 changes `tree_copy.py`'s copy rule and its T rows with it.
- **A clone serves only while the stamp matches** (§13, SA0 items 3 and 9). When SwiftPM runs on
  a scratch path cloned from another path, every compile fails, because the cloned module cache's
  precompiled headers name the path they were built at; it does not merely recompile. So the
  stamp also records the scratch path's own absolute path, beside its key and not in it, and
  reads it only on a miss: a clone at any path is served while the key matches (item 3's 1.21 s
  step), and a miss on a scratch path whose recorded path is not its own empties it and builds
  cold. The path in the key would make every clone miss and every tree copy build Slaude cold.
  Whether dropping only its module cache would be enough was not measured. The build script takes
  its tree from the caller (`$PROJECT_DIR`), never from its own physical path, because a tree
  copy's `tools` is a symlink to the tree's and Doctored's `$(dirname "$0")/..` would build the
  tree. A tree copy's whole app build, with and without the clone, was not run in SA0 and is
  SA3's.

## 8. The spec §11 decisions each phase will need

Named here, written by the phase that needs each, before its code, in
`designs/spec/11-decisions/swift-helper.md` with their index rows. SA0 wrote SA-1..SA-3 there;
each later one is appended.

| Decision | Phase | What it settles |
|---|---|---|
| SA-1 | SA0 | The helper is a Swift executable from a SwiftPM package in `agent/`, on Slaude by exact revision; the process boundary and the protocol stay. Amends AI-1 (Bun, the Tool Runner, "the one TypeScript in the product", the accepted risk of Bun in every `make app`). |
| SA-2 | SA0 | Its own turn loop, verbatim history, raw-JSON bodies in a pinned order; every `tool_use` answered; a cancel never ends a tool wait. |
| SA-3 | SA0 | Pricing in the Swift helper (the owner's answer 1 (a)). Amends P-2 and P-8 where they say "the SDK". |
| SA-4 | SA1 | The explicit compaction rule and its three changed behaviours (§5). Amends AI-9's and AI-20's pointers to `main.ts`. |
| SA-5 | SA1 | The request: the system block's breakpoint (the owner's answer 6 (a)), the key order, API version `2026-10-21`, Bearer credentials, and sorted keys from the app, which SA0 found are needed (§13, SA0 item 8). Amends AI-13's pointer to `protocol.ts`. |
| SA-6 | SA1 | The protocol: `reset` dropped, `message_done` and `ready` kept. |
| SA-7 | SA1 | **W-8's edge.** async/await and actors are the concurrency model of `agent/` and of nothing else; W-8 and its two files govern `app/Sources`, which gains no `async`. W-8 is not amended, only bounded. |
| SA-8 | SA3 | The build: the script, the scratch path, release in batches, the stamp, the hardened runtime and no entitlements. From SA0 (§13, items 3, 4 and 9): the stamp's key gains the price table's content; the stamp records the scratch path's own path beside the key, not in it, and reads it only on a miss, when a scratch path made elsewhere is emptied (§7: a clone is served at any path while the key matches); the script takes its tree from the caller; and how a helper mutant is built (§9 SA3). Amends D10/D11 and P8's contract. |
| SA-9 | SA3 | B1 measures the built helper's first POST. Amends P-9 (d). |
| SA-10 | SA3 | The Acknowledgements and the publish runner, in the commit that switches the build step (§2: the npm reader reads what that step installs): npm and Bun out, Slaude in, `setup-bun` gone. Amends PUB-10 (its npm and Bun sentences and the LGPL risk line) and PUB-12 (`setup-bun`). |
| SA-11 | SA4 | What the tie to Doctored becomes: the owner's answer 2 (a), Frame Job's package its own, ported once from Doctored at `b524babc`, with no identity rule. Amends AI-15's "`agent/` is one diff with Rasterize" and NM-10. |
| SA-12 | SA1 | `make agent-test`'s own scratch path, `build/agent-swift-test`, emptied before SwiftPM runs when its marker is missing or names another path, because every lane copies `build/` (§13, SA1's record); SA-8's `build/agent-swift` and its rule untouched. Written by SA1, numbered after the four reserved here. |

## 9. Phases

Each phase is its own commit, builds, and passes its own checks. Each has a mutant per decision
it adds. No phase spends money: a phase's own proofs use the stand-in only, and the three paid
proofs of the owner's answer 3 are run by the orchestrator after SA4 has landed and before SA5's
close, whose record holds them (SA5, §12).
A phase that finds Slaude lacking something the port needs follows the owner's answer 4 (§12).

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

It writes SA-1..SA-3. **Proof:** the measurements, each with its command and output (§13).

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
- **How a helper mutant is built** (SA-8). Not by SwiftPM on a clone of the tree's scratch path:
  on a clone used from another path a changed `agent/` cannot be built at all (§13, SA0 item 9).
  SA0's recommendation is one builder beside `tools/proof/swift_build.py` that compiles the
  mutated helper sources against the tree's built Slaude module and links the tree's Slaude
  objects, reading them only, so the tree's product cannot become a mutant's; it needs the tree's
  helper built first. SA0 measured it on Doctored's package, which embeds no resource: with the
  price table compiled in, the source file SwiftPM generates for it (`embedded_resources.swift`)
  must be supplied to the builder, which was not measured. The other shape that works is one
  persistent SwiftPM scratch path for mutants per worktree, built cold once and incremental at a
  fixed path after, at a second scratch path's disk (§10). SA3 chooses between them.
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

- The paid proofs of the owner's answer 3 (§12): all three, serially, in one month, each with its
  flags and its dollars reported, run by the orchestrator, never by a lane, after SA4 has landed
  and before the close below. This phase's record holds each run's flags, dollars and result; a
  failure a run finds is fixed, or filed with the residue, before the close.
- `docs/manual-checks.md`'s AS-1, AS-4, AS-5 and AS-6 are marked for the owner to run again: a
  real conversation, what a turn cost, what a conversation and the month cost, a reply cut short.
- The close: `designs/adr/swift-helper.md`, this file moved to `archive/swift-helper.md` with its
  index row, residue filed as issues.

## 10. Build and publishing cost

SA0 measured these in this tree on 2026-11-12 (§13, SA0 items 2 and 3), beside Doctored's of
2026-11-03 **(Doctored)**, on the same kind of host (12 cores, 96 GB). **None of this tree's figures
is an idle one:** two other lanes built throughout, each figure carries the load averages its run
printed, and the `-j 3` run overlapped an app build in the same worktree. They are costs to plan
with, not thresholds. Memory is the sum of resident sizes over the build's process tree, sampled
four times a second, as Doctored measured it.

| Figure | Doctored, 2026-11-03 (load 20–490) | This tree, 2026-11-12 | Load averages, start → end |
|---|---|---|---|
| Release in batches, cold, 12 jobs: wall | 148 s | 122.4 s | 58.61 31.27 23.88 → 47.86 41.68 29.40 |
| the same: tree peak / largest process | 3.2 GB / 1.78 GB | 3.08 GiB / 1.67 GiB | the same run |
| Release in batches, cold, `-j 3`: wall | 160 s | 391.9 s, beside an app build | 73.73 56.76 38.66 → 101.44 71.05 50.44 |
| the same: tree peak / largest process | 2.1 GB / — | 1.95 GiB / 1.67 GiB | the same run |
| Release, warm, nothing changed: wall (SwiftPM's own line) | (0.6–1.9 s) | 4.1 s (2.93 s) | 106.14 116.85 110.09 → 106.14 116.85 110.09 |
| Release, warm, one helper file edited: wall | — | 4.1 s, 11 files compiled, none of Slaude's | 106.14 116.85 110.09 → 101.17 115.64 109.70 |
| Debug, cold: wall | 60 s, the build | 124.4 s, `swift test` (its build 116.58 s, the 50 tests) | 48.42 42.16 30.24 → 76.34 54.41 36.71 |
| the same: tree peak / largest process | 3.7 GB / 1.20 GB | 3.70 GiB / 1.06 GiB | the same run |
| The helper step in a `make app-debug`, cold | — | 273.36 s of the build's 420.4 s | 63.34 54.66 42.19 → 94.83 79.08 56.81 |
| The step with its stamp matching (digest, copy, strip, sign) | 0.72–0.75 s | 1.21 s and 1.89 s, in a tree copy | 109.74 116.61 83.19 → 110.89 116.73 83.43 |
| The helper, stripped and signed | 35.5 MB | 35,546,496 bytes (78,112,240 before `strip -x`) | — |
| The Bun helper | 57.7 MB | 57,735,840 bytes | — |
| The scratch path on disk: release / debug with the suite | — | 1.8 GB / 2.3 GB | — |

- **A worktree's first app build** compiles Slaude in release, as the table says; later builds
  are skipped by the stamp. Bun took about 0.2 s **(Doctored)**. `make agent-test` compiles it
  once more in debug.
- **Disk.** A worktree that has built the helper and run the suite holds about 4 GB of SwiftPM
  products, a release and a debug build on its scratch path. A tree copy's clone of it is free
  until written to; a persistent scratch path for mutants (§9 SA3) would hold another.
- **Not measured here, so Doctored's figures stand:** the network fetch of Slaude (this Mac's
  SwiftPM cache already held it), and the two below.
  - On the publish runner (`macos-26`, the image `publish.yml` line 44 uses here) SwiftPM built
    Slaude and the helper in 279.5 s with no memory failure, and the archive step took 20 min 2 s
    against 19 min 11 s for the last Bun build **(Doctored)**.
  - Whole-module optimization of Slaude peaks at 10.6 GB in one compiler process, past the
    runner, which is why release compiles in batches **(Doctored)**.
- If a later Slaude outgrows the runner, the levers are the debug configuration and a larger
  runner.

## 11. Accepted risks, carried from Doctored or found here

- **Slaude is young and has one maintainer**, the owner. Its transformation and tests track the
  official Python SDK, and Doctored has shipped on it since 2026-11-04; nobody else uses it.
  Agents change it only through a pull request the owner merges (§12, answer 4).
- **The pin's cadence.** A new API feature or fix reaches the helper only through a commit that
  moves the pin and runs the suite and the gate.
- **A pin on a pull request's branch** (§12, answer 4) is fetchable only while that branch holds
  its commit. A squash merge leaves the commit off Slaude's default branch, so the branch must be
  kept until Frame Job re-pins to the default branch, which the phase that pinned it records as
  owed.
- **The compile**, on every worktree's first build and on the publish runner (§10).
- **Disk:** about 4 GB of SwiftPM products in every worktree that builds the helper and runs the
  suite (§10), with lanes of worktrees on one volume.
- **The first build needs the network**, to fetch Slaude.
- **A second Swift toolchain mode in the tree.** The package is Swift 6 with actors; the app is
  Swift 5 with GCD. SA-7 keeps them apart by directory.

## 12. The owner's answers (2026-11-12)

The owner answered on #599 on 2026-11-12 (the approval quoted at the head of this file): 4 not as
recommended, "Everything else, as recommended". Each question stays as it was asked, with its
options; the answer follows it.

1. **The spend figures.** Doctored dropped pricing when it made this move, because nothing there
   showed it. Frame Job shows two figures (P-7) and keeps a ledger.
   - (a) Keep both, with pricing ported into the Swift helper. **Recommended:** P-2 and P-7 stand,
     the fixtures and the Python cross-check already exist, and the port is two files.
   - (b) Keep both, but price in the app from the helper's `usage`. The helper gets smaller, and
     the app gains the table, its refresh and a network fetch in `app/Sources`.
   - (c) Drop pricing as Doctored did. The tab's Spend row, Settings' month line and the ledger
     go, with P-1, P-2, P-4, P-5, P-7 and P-8; SA1-SA4 lose every pricing item above, and the
     proofs' own budget (P-3, P-6, P-9) is unaffected.
   - **Answered: (a).** Both figures stay, with pricing ported into the Swift helper (SA-3).
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
   - **Answered: (a).** Frame Job's package is its own, ported once from Doctored at `b524babc`,
     with no identity rule (SA-11, in SA4). The two Rasterize issues are the owner's to close.
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
   - **Answered: (a).** All three, serially, in one month, each run's dollars reported. They are
     the orchestrator's, never a lane's, run after SA4 has landed and before SA5's close, whose
     record holds them (§9 SA5); a phase's own proofs use the stand-in only.
4. **Who changes Slaude** when the port needs something it lacks.
   - (a) An agent files the need on `kpgalligan/Slaude`; the owner lands it; the pin moves in its
     own commit here. **Recommended:** it keeps this repository's agents out of another
     repository.
   - (b) Agents may commit to Slaude directly.
   - **Answered: not (a), the recommendation, and not (b) as written.** Agents make the changes
     Slaude needs themselves and push them for the owner to merge:
     - a Slaude change is made only when a measurement shows the pin cannot serve and the fix
       belongs in Slaude;
     - it is a branch pushed to `kpgalligan/Slaude` and a pull request there against its default
       branch: never a push to the default branch, never a merge of the pull request (the owner
       merges), and never a force-push of its branch;
     - Frame Job pins the branch's commit by exact `revision:` meanwhile. A squash merge leaves
       that commit off the default branch, so the pull request asks for its branch to be kept
       until Frame Job re-pins, and "re-pin to Slaude's default branch after the pull request
       merges" is written as owed in the commit message and in the phase's record (§13);
     - the pull request says what Frame Job needs and what was run, with no local path and no bare
       at-sign name in it;
     - the work is done in a fresh clone from GitHub in a scratch folder, never in an existing
       local checkout.

     SA0 needed none of it: the pin lacked nothing it measured (§13, SA0 items 1, 5, 6, 7 and 10).
5. **The build cost** (§10).
   - (a) Accept it. **Recommended:** it is what compiling Slaude costs, once per worktree.
   - (b) Local app builds use SwiftPM's debug configuration (60 s cold against 148 s, for a
     larger and slower helper **(Doctored)**) and only Distribution builds release.
   - **Answered: (a).** The cost is accepted. SA0's figures for this tree are in §10, with one
     cost the question did not show: about 4 GB of SwiftPM products per worktree (§10, §11).
6. **The system block's cache breakpoint** (§5). It lowers what a new conversation costs and
   changes the request.
   - (a) Adopt it with the switch. **Recommended:** Doctored measured the saving live.
   - (b) Switch first with today's request, and adopt it as its own change afterwards, so SA2's
     comparison allows one difference fewer.
   - **Answered: (a).** The breakpoint is adopted with the switch (SA-5), with the app's sorted
     keys that let a relaunch read it (§5).

## 13. Records

Each phase's record goes under its heading here when it lands: what landed, what was measured,
what its review found, what is owed.

### SA0 — record

**What landed** (2026-11-12, on `e0206243`). This record; the status, the owner's answers in §12,
and what the spike changed in §2, §5, §7, §8, §9, §10 and §11; SA-1..SA-3 in
`designs/spec/11-decisions/swift-helper.md`, with a pointer appended to AI-1, P-2 and P-8. No
product code. The spike's package (Doctored's `agent/` at `b524babc`, with a probe target) and its
second build step were a throwaway patch in a worktree, and neither they nor its scripts are in
the tree. No Slaude branch or pull request: the pin lacked nothing measured, so nothing is owed
to re-pin.

**What was measured.** On 12 cores and 96 GB, Xcode 26.2 (17C52), Swift 6.2.3, on 2026-11-12 at
`e0206243`. Two other lanes built throughout, so **no figure here is an idle one**: each carries
the load averages its run printed (one, five and fifteen minutes). Memory is the sum of resident
sizes over the build's process tree, sampled four times a second, with the largest single process
beside it; Xcode's build service is not a child of `xcodebuild`, so no memory figure is given for
a whole app build. "SwiftPM's command" is Doctored's build line, in its scrubbed environment:
`env -i HOME=… PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=… xcrun swift build --package-path agent
--scratch-path <scratch> --configuration release --product doctored-agent -Xswiftc
-no-whole-module-optimization -Xswiftc -enable-batch-mode`, on Doctored's `agent/` at `b524babc`
with its platform line changed. Where the spike's own output went to its terminal only, the build
pass ran the measurement again, marked "re-run", or left the figure out.

1. **Doctored's package against the pin, at the macOS 26 floor.** SwiftPM's command with
   `.macOS(.v26)` under swift-tools 6.0 failed: `error: 'v26' is unavailable`, `note: 'v26' was
   introduced in PackageDescription 6.2`. `swift package dump-package` on four one-target
   manifests (re-run; load 100.14 118.08 110.10): `tools 6.0, .macOS(.v26): REFUSED`;
   `tools 6.0, .macOS("26.0"): accepted, platform 26.0`; tools 6.2 accepted either spelling. With
   `.macOS("26.0")`: `Working copy of https://github.com/kpgalligan/Slaude resolved at
   4c6c2ca435350741796c3d461720a61e7149b378`, `Build of product 'doctored-agent' complete!
   (121.62s)`, the log's only warning the driver's `ignoring -num-threads argument`; and
   `swift test` with Doctored's `DR_AGENT_STRICT=1`: `Executed 50 tests, with 0 failures`. Slaude
   came from this Mac's SwiftPM cache (`Fetched https://github.com/kpgalligan/Slaude from cache
   (0.62s)`), so the network fetch was not measured. **So:** swift-tools 6.0 with
   `platforms: [.macOS("26.0")]` (§5, SA-1).
2. **Build time and peak memory.** A sampler around SwiftPM's command, each cold on an empty
   scratch path, then warm on the 12-job one at the path it was built at:

   | Build | Wall | Tree peak | Largest process | Load averages, start → end |
   |---|---|---|---|---|
   | release, batches, 12 jobs (the default), cold | 122.4 s | 3.08 GiB | 1.67 GiB | 58.61 31.27 23.88 → 47.86 41.68 29.40 |
   | release, batches, `-j 3`, cold, beside item 3's app build | 391.9 s | 1.95 GiB | 1.67 GiB | 73.73 56.76 38.66 → 101.44 71.05 50.44 |
   | debug, `swift test`, cold (`Build complete! (116.58s)`, the 50 tests) | 124.4 s | 3.70 GiB | 1.06 GiB | 48.42 42.16 30.24 → 76.34 54.41 36.71 |
   | release, warm, nothing changed (re-run; SwiftPM's line 2.93 s) | 4.1 s | 0.08 GiB | 0.08 GiB | 106.14 116.85 110.09 → 106.14 116.85 110.09 |
   | release, warm, one helper file edited (re-run; 11 `Compiling` lines, none of Slaude's; SwiftPM 2.89 s) | 4.1 s | 1.49 GiB | 0.15 GiB | 106.14 116.85 110.09 → 101.17 115.64 109.70 |

   The `-j 3` wall time does not compare with Doctored's; its memory does. The release product is
   78,112,240 bytes, and 35,546,496 after `strip -x` and `codesign --force --options runtime
   --sign -`: `flags=0x10002(adhoc,runtime)`, no entitlements (re-read). The Bun helper in this
   tree's Debug and Release bundles is 57,735,840 bytes (re-read). On disk (`du -sh`, re-run):
   1.8 GB for each release scratch path, 2.3 GB for the debug one with the suite. **So:**
   Doctored's build line as it is, release in batches without whole-module optimization at the
   default jobs (§10).
3. **A tree copy's app build with the helper step in it.** The spike worktree's own
   `make app-debug`, its helper step running Bun's build and then Doctored's
   `build_agent_helper.sh` (with this tree's paths) on an empty `build/agent-swift`:
   `exit 0  wall 420.4 s` (load 53.06 55.95 40.78 → 95.81 79.80 57.33), the step
   `helper step total 273.36 s` (load 63.34 54.66 42.19 → 94.83 79.08 56.81). That build left
   914 MB of intermediates, 620 MB of module cache and 195 MB of Debug products (`du -sh`, re-run).
   Then `tools/proof/tree_copy.py`'s `make_copy`, the tree's `build/agent-swift` cloned into the
   copy (`cp -cRp of build/agent-swift: exit 0, 4.41 s`) and the step run there as the copy's
   phase would run it: `SwiftPM skipped`, `digest+check 0.31 s`, `helper step total 1.21 s` (load
   109.74 116.61 83.19), and again 1.89 s (load 110.89 116.73 83.43). Then `touch` on the copy's
   product, so the stamp missed: SwiftPM ran in the copy and failed, `error: PCH was compiled with
   module cache path '…/build/agent-swift/arm64-apple-macosx/release/ModuleCache/2UHWOJU7ZQLJ2',
   but the path is currently '…/copy/build/agent-swift/…'` and `missing required module
   'SwiftShims'`. A clone made without `-p` would not move the product's time: on this volume
   `cp -cR` and `cp -cRp` both kept a file's time (re-run: `1577858460` on the original and both
   copies), and only the `cp -cR` copy's folder took the current time. **Not run:** the copy's
   whole `make app-debug`, with or without the clone, for lack of disk while three lanes built.
   **So:** a clone saves the cold step only while the stamp matches, and on a miss SwiftPM must
   not run on a scratch path made at another path (§7, SA-8).
4. **`.embedInCode` with the table at `agent/prices/anthropic.json`.** Three packages, each with
   the tree's table (3866 bytes) and a target `Kit` that embeds it, and a tool printing the
   embedded bytes against the file: the resource named outside the target
   (`.embedInCode("../../prices/anthropic.json")`), a relative symlink in the target, and a copy
   in it. All three built; the outside one printed `Found unhandled resource at
   …/agent/prices/anthropic.json` on each build, the symlink nothing. One byte was added to the
   table in the first two, which were rebuilt. Their tools, run again (re-run, no compile):
   outside `embedded bytes 3867`, `file bytes 3867 equal true`; symlink the same; copied
   `embedded bytes 3866`, `file bytes 3866 equal true`. The generated accessor is
   `PackageResources.anthropic_json: [UInt8]`. On the symlink layout `find agent/Sources -type f`
   lists `Kit.swift` and `main.swift`, and `find -L` adds `anthropic.json`. **So:** the symlink
   layout, and a stamp that digests the table's content, which Doctored's `find agent/Sources
   -type f` does not reach (§5, SA-3, SA-8). `tree_copy.make_copy` copies `agent/` with
   `shutil.copytree`, which follows the link and writes the same bytes into a copy.
5. **`currentMessageSnapshot` at a cancel.** A probe built as a product of the spike's package
   sent one streamed request through Doctored's `ClientFactory` and `Request` and read it as
   Doctored's turn loop does, against `tools/proof/anthropic_fake.py`, with the app's own captured
   `configure` (122 tools). `"cut": "drop"` is `spend_proof.py` H10's scenario; `"cut": "stall"`,
   closed on its first `content_block_delta`, is H11's; `after-delta` closes an uncut reply on its
   `message_delta`:

   | Mode | Events the probe saw | Thrown | The snapshot's usage |
   |---|---|---|---|
   | drop | `message_start`, `content_block_start`, `content_block_delta`, `content_block_stop` | `StreamEndedEarlyError` | input 100, output 0 |
   | stall | `message_start`, `message_delta`, `content_block_start`, `content_block_delta` | `CancellationError` | input 100, output 10 |
   | after-delta | the drop's four, then `message_delta` | `CancellationError` | input 100, output 10 |
   | full | all six | nothing; `messageComplete` true | input 100, output 10 |

   After a throw the snapshot stays readable with `messageComplete` false, and the two errors are
   distinct types, which is what tells H10's cut (an `error` after the cost) from H11's Stop (no
   `error`). A request failing before `message_start` was not run; Slaude's
   `JSONMessageStream.swift` says the snapshot is `nil` there. The `full` row is a complete reply
   (text, where H12's first reply is a `tool_use`) returned by `getFinalMessage()` with
   `messageComplete` true, which is what prices H12's first reply complete, once. H12 itself, a cancel during the tool wait after that reply with no
   stream in flight (one `cost`, no `partial`, one POST), reads no snapshot and was not run here;
   it is SA1's suite case of a cancel with tools pending. **So:** P-8 ports as written on the
   pin, and its lower bound does not move (SA-3).
6. **The Bearer header.** The same runs, as the stand-in logged them:
   `GET /v1/models/claude-opus-5-5 0 bytes; credential {'authorization': 'Bearer proof-key'};
   anthropic-version 2026-10-21`, `user-agent Anthropic/Swift 2.3.0`, each POST the same at
   398930 bytes, and `stand-in failures: []` in all five modes. **So:** the stand-in needs no
   change, and `assistant_session_proof.credential()` already strips `Bearer `. The relay
   (`tools/proof/assistant_prompt_eval.py` line 376) and `tools/proof/budget_proof.py` (line 438)
   learn it in SA3 (§5).
7. **AH-5's five checks against Frame Job's own request.** The worktree's Debug app, launched by
   `assistant_session_proof.App` against the stand-in with a scratch secret folder, ran a turn
   whose scripted reply calls `render_frame` on a project of one text clip and then answers in
   text: the Bun helper's real traffic. `POST /v1/messages?beta=true 399098 bytes; credential
   header ['x-api-key']; anthropic-version 2023-06-01`, keys `['model', 'max_tokens', 'system',
   'tools', 'messages', 'cache_control', 'output_config', 'thinking', 'fallbacks', 'stream']`,
   `sampling keys present []`, `system is str; tools 123`; the second POST (457461 bytes) carries
   `('assistant', ['tool_use'])` and `tool_result[image:base64:image/png,text]`. Read again from
   the stand-in's log (re-run, no launch): the three requests are the model lookup and the two
   POSTs; no `citations` key in either's messages; the `tool_result` block's keys `['content',
   'tool_use_id', 'type']`. Item 5's Swift body: the same ten keys in the same order,
   `sampling keys []`, `system list of [['cache_control', 'text', 'type']]`, 123 tools. All five
   of §5's checks hold. What differs on the wire, for SA2's allowed differences:
   `anthropic-version` 2023-06-01 → 2026-10-21; `x-api-key` → `authorization: Bearer`; the path
   loses `?beta=true`; `system` is a one-block list carrying `cache_control`; the user-agent is
   `Anthropic/Swift 2.3.0`. **Limit:** the stand-in does not know what API version 2026-10-21
   refuses (owed, below).
8. **`configure`'s bytes across two launches.** A copy of the worktree's Debug bundle whose
   `framejob-agent` is a shim that copies its stdin to a file and pipes it to the real helper; two
   launches against one stand-in, one secret folder and no spend folder: `configure one: 396901
   bytes sha256 2af3d846c5e52075`, `configure two: 396901 bytes sha256 54a156bd00e50130`,
   `byte-identical: False`, `equal once parsed (so any difference is key order): True`, top-level
   key orders `['core_tools', 'type', 'api_key', …]` and `['api_key', 'system', 'api_base', …]`,
   `tool entries whose own key order differs between launches: 101 of 122`, `tool entries whose
   inputSchema bytes differ between launches: 85`, and the tools-and-system prefix of each
   launch's first POST `402397 and 402397 bytes, identical False`. An earlier pair of launches
   printed the same shape (97 of 122, and 95). The two captured lines read again (re-run, no
   launch): `byte-identical: False`, `equal once parsed: True`, `sorted-key serialisations
   identical: True`. **So:** no. `JSONSerialization` writes a dictionary in its per-process hash
   order and the Bun helper passes each schema's order through, so a relaunch cannot read the
   prompt cache the last launch wrote. `AssistantSession.write` takes `.sortedKeys` (§5, SA-5);
   `writeResult` builds its line by hand and is unaffected.
9. **A helper mutant in a clone of the scratch path.** A scratch root shaped as `spend_proof.py`
   makes one (`agent/` copied without `node_modules`, `tools` linked, `build/agent-swift` a
   `cp -cRp` clone of the tree's), the step run in it, and the tree's product digested before and
   after. `agent/` unchanged: `clone (cp -cRp) of the scratch path: exit 0, 6.12 s`, `SwiftPM
   skipped`, `the step took 2.0 s, exit 0`, `tree product unchanged: True` (load 177.80 124.59
   80.47 → 183.66 126.69 81.46). One line of `Turn.swift` changed: `clone: exit 0, 9.53 s`, then
   SwiftPM scheduled Slaude again and every compile failed on the cloned module cache (the log
   holds 298 `PCH was compiled with module cache path` errors): `STOPPED by this script after 9.2
   s: 300 Anthropic files recompiled so far, SwiftPM's counter at [304/381]`, `tree product
   unchanged: True` (load 182.49 127.39 81.98 → 178.26 129.24 83.44). Then the same mutated
   sources by `swiftc` directly, the kit as one module, `main.swift`, one link, against the tree's
   `release/Modules/Anthropic.swiftmodule` and its 2385 `Anthropic.build/*.o`, read only:
   `kit: exit 0, 12.99 s`, `main: exit 0, 0.88 s`, `link: exit 0, 1.39 s`, `the whole mutant
   build: 15.39 s`, a 77847152-byte helper answering `{"type":"ready"}` to the app's `configure`,
   and the tree's product unchanged at 77904736 bytes and sha256 `dabd19c05a175f55` (load 107.51
   116.73 81.59 → 116.10 118.19 82.73). **So:** no: on a clone used from another path SwiftPM
   cannot build a changed `agent/` at all, and an unchanged one is skipped by the stamp, the step
   taking 2.0 s. SA0 recommends the direct build for the proofs' scratch helpers, measured on a
   package that embeds no resource (§9 SA3).
10. **Slaude past the pin.** `gh api
    repos/kpgalligan/Slaude/compare/4c6c2ca435350741796c3d461720a61e7149b378...main`, at the
    spike's start and end and again by the build pass (re-run, 2026-11-12 15:15 UTC):
    `{"ahead_by":0,"behind_by":0,"status":"identical"}`; `main` is
    `4c6c2ca435350741796c3d461720a61e7149b378`, last pushed `2026-11-03T20:51:10Z`; no open pull
    request; its branches `claude/api-implementation-8ix9bn` and `main`. Doctored's
    `agent/Package.swift` at `b524babc` pins the same revision. **So:** it has not moved; Frame Job
    pins `4c6c2ca435350741796c3d461720a61e7149b378` (SA-1), and SA0 opened no Slaude branch or pull
    request.

**What its review found.** The plan's challenge made five objections, all accepted. Four changed
this file before it was written: every figure here is traced to a run's kept output, and where
the spike's had gone to its terminal only the measurement was run again or left out; "a clone
without `-p` misses the stamp", which nothing had measured, was measured and is false (item 3);
the direct mutant build is written as a recommendation measured without an embedded resource,
not as the design (§9 SA3); and two sentences of §7 that still deferred to SA0 were brought up to
date. The fifth changed only the build pass's own checker. The diff read made one should-fix and
three nits, all taken in its fix pass: SA-8's row and the owed list below called the scratch
path's own path one of the stamp's inputs, which, built as written, puts the path in the key, so
every clone at another path misses, is emptied and builds Slaude cold, against item 3's 1.21 s;
both now say the key gains the table's content and the path is recorded beside the key and read
only on a miss, and §7 says why. Item 5 now says what its `full` row shows of H12 and that H12
itself is SA1's. The paid runs are placed after SA4 and before SA5's close, whose record holds
them (§6, §9, §12).

**What is owed.**
- **SA1:** the package at `.macOS("26.0")` with the symlinked table; a suite case for a request
  failing before `message_start`, the snapshot `nil` and no `cost` (P-8's "emits none"); H12 as
  the suite's cancel with tools pending, after a complete `tool_use` reply: one `cost`, no
  `partial`, no second request (item 5); and, with SA-5, `.sortedKeys` in
  `AssistantSession.write` and a row of two launches and one digest.
- **SA3** (SA-8): the table's content in the stamp's key; the scratch path's own path recorded
  beside the key, not in it, and read only on a miss, when a foreign scratch path is emptied (§7);
  whether dropping only its module cache would repair one (not measured, so cold is assumed); the
  mutant builder or the persistent mutant scratch path, and for the builder the generated
  `embedded_resources.swift` (not measured); a tree copy's whole app build, with and without the
  clone, with `tree_copy.py`'s copy rule.
- **The live run, after SA4 and before SA5's close** (§12, answer 3): what API version 2026-10-21
  refuses, which the stand-in cannot say.
- **Not measured, and Doctored's figures stand:** the network fetch of Slaude, whole-module
  optimization and the publish runner (§10). Not owed: any figure here again on an idle host; they
  are costs, not thresholds.

### SA1 — record

**What landed** (2026-11-12, on `943bb2e0`). SA-4..SA-7 and SA-12 in
`designs/spec/11-decisions/swift-helper.md` with their index rows, and pointers appended to AI-9,
AI-13 and AI-20; SA-12's row in §8 and the suite's path in §7. The package in `agent/`, beside the
Bun helper, ported once from Doctored's `agent/` at `b524babc` (the owner's answer 2 (a)):
`Package.swift` (swift-tools 6.0, `.macOS("26.0")`, Slaude at
`4c6c2ca435350741796c3d461720a61e7149b378`, `-warnings-as-errors` under `FJ_AGENT_STRICT=1`),
`Package.resolved`, `Sources/FrameJobAgentKit/` (Doctored's eleven files, then `Pricing.swift`,
`PriceTable.swift` and `PriceRefresh.swift` — the refresh in a third file, as the plan allowed,
to keep the table's file readable at 250 lines — and `anthropic.json`, the committed relative
symlink to `agent/prices/anthropic.json`), `Sources/framejob-agent/main.swift`, and `Tests/` (nine
test files and three support files, 76 tests). What the port adds to Doctored's: `price_cache` and
`price_feed`; the events `message_done`, `prices` and `cost`; the price function, the table, its
refresh and the cache file in `priceTable.ts`'s rules; the partial price from
`currentMessageSnapshot` when a round throws after `message_start`; a turn's prices fixed at
`turn_started`; and #484's sentence. `tools/agent/agent_test.py` is `make agent-test` (the SA-12
guard, then `swift test` with `FJ_AGENT_STRICT=1`), and `make test` runs its selftest and then the
suite. `AssistantSession.write` takes `.sortedKeys` (SA-5), and
`tools/proof/assistant_session_proof.py` gains row KO and the mutant `unsorted-configure`. Nothing
is bundled: the app still ships the Bun helper. **No Slaude change:** the pin lacked nothing the
port needed, so no Slaude branch or pull request was opened and no re-pin is owed.

**What was measured.** On the same 12-core, 96 GB host, Xcode 26.2, Swift 6.2.3, with two other
lanes building throughout: no figure is an idle one, and each carries its load averages (one, five
and fifteen minutes).

1. **Slaude's cold debug build** in this tree, `swift build --build-tests` on a stub package:
   `exit 0 wall 135 s` (load 45.33 32.01 53.86 → 158.17 85.29 72.05), Slaude from this Mac's
   SwiftPM cache. `make agent-test`'s first run in the build worktree, whose scratch path had been
   made by hand: `emptied: no marker`, then the 76 tests, `exit 0 wall 107 s` (load 127.09 135.25
   127.75 → 183.99 148.12 133.30).
2. **The suite.** `Executed 76 tests, with 0 failures` under `FJ_AGENT_STRICT=1`: Doctored's cases
   ported (the codec both ways and the line splitter, the tool-result conversion, the history
   merge, the refusals and error wording, deltas, a multi-tool round with an image, a cancel
   mid-stream, before the headers and with tools pending, `refusal` and `max_tokens`, a final
   reply's unrun calls, 429 and 529 with `retry-after` and three retries, a mid-stream `error`
   event, a stream cut short, `pause_turn`, an unknown tool and thirty rounds, compaction's
   success, wrong stop, empty summary, tool-call ending and limit, settings mid-turn, the request
   body, clearing's edit, the same prefix on every round and in two helpers, byte-identical
   replay, and the process tests over the built executable) and Frame Job's: all 23 of
   `cases.json` within 1e-12, the committed table and the embedded bytes equal to the file's,
   `reduce_cases.json`'s rows and three refusals, priceTable.test.ts's ten refresh cases (a
   dead feed is port 1 on 127.0.0.1), a failed status, and a cache file in the Bun helper's
   indented layout,
   `prices` before `ready` and after it when a refresh settles, `message_done` then `cost` per
   response and none for a summary, H10 (a stream dropped after `message_start`: one partial
   `cost` at input 100, output 0, then the error), H11 (a cancel after `message_delta`: one
   partial `cost` at output 10, no error), a request failing before `message_start` (no `cost`),
   H12 (a cancel during the tool wait after a complete `tool_use` reply: one complete `cost`, one
   POST), a turn keeping its prices through a refresh that settles mid-turn, #484's sentence,
   `reset` ignored with the history kept, and a tool wait held 1 s with no request and across a
   cancel until its answer.
3. **A cloned debug scratch path** (the challenge's objection 2): the warm suite scratch path
   `cp -cRp`-cloned into a second tree in 8 s, with a marker naming the first. `swift test` on it
   unguarded: `exit 1` in 23 s, 2,386 `PCH was compiled with module cache path` lines and
   `missing required module 'SwiftShims'` (load 45.67 115.49 119.49 → 51.91 111.37 117.89). Through
   `agent_test.py --tree`: emptied, built cold, 76 tests passed, `exit 0` in 175 s (load 51.91
   111.37 117.89 → 168.64 141.94 129.31); again, kept, `exit 0` in 8 s. The scratch path was 2.5 GB.
   So the debug suite fails on a clone as the release build did (SA0 item 3), and SA-12's guard
   repairs it at a cold build's cost.
4. **Mutants**, each applied in place, run with `swift test --filter` on the warm scratch path
   without `FJ_AGENT_STRICT` (so a red is a test failure, never a warning), seen red, reverted:
   SA-4 `empty-summary-swapped` (CompactionTests' empty summary), `unrun-calls-unanswered` (a final
   reply's unrun calls), `summary-after-tool-call` (a reply ending in a tool call) and
   `no-484-sentence` (TurnTests' stop-reason sentences); SA-5 `no-system-breakpoint` (the round's
   body); SA-6 `no-message-done` (SpendTests' per-response order) and `reset-clears-history`
   (SessionTests' reset); SA-3 `cancel-not-priced` (H11) and `prices-at-each-cost` (a turn keeps
   its prices); SA-2 `cancel-ends-tool-wait` (the tool wait); and two reds for the price port,
   `stub-price` (cases.json's 23, 14 failing) and `unrounded-per-million` (the reducer's rows).
   All twelve caught. SA-12: `agent_test.py --mutant guard-noop` fails exactly S1 and S2. SA-5's
   app half: `assistant_session_proof.py --mutant unsorted-configure` (item 6). SA-7:
   `make typecheck` 0 errors and its four warnings, and the diff adds no `async`, `await` or
   `actor` under `app/Sources`.
5. **`make gate`.** The first run stopped in `test` at its 900 s bound (`ran past its 900 s
   bound`, 902.5 s, load 344.72 311.40 239.61 at its end), still in `assistant_prompt_proof.py
   --probe`'s 860-source build and before the suite; nothing failed. The second, unchanged:
   `test pass 560s` (the suite's build `Build complete! (28.37s)` on the kept scratch path, 76
   tests) and `app pass 609s`, `gate: PASS 1171s` (load 212.86 293.92 277.17 after `test`, 219.74
   261.56 268.06 at the end). The first `make test` of a lane that copied `build/` adds Slaude's
   cold debug build to that step (item 1), inside the same bound.
6. **SA-5's sorted keys, from the app.** `RC_PROOF_APP=release python3
   tools/proof/assistant_session_proof.py`: `14/14`, KO `launch A's prefix 4049b72362c3d816
   (398849 bytes), launch B's 4049b72362c3d816 (398849 bytes): identical` (KO serialises the
   parsed pair compactly, so its byte count is not SA0 item 8's measure of the raw prefix).
   `--mutant unsorted-configure` (the `.sortedKeys` line deleted in a tree copy, `make app-debug`
   there, `built … in 35 s`, T1's launch A and W's launch B of it): `KO FAIL — launch A's prefix
   cc25d88108d0f8e4 (398849 bytes), launch B's 2f48bd6a24a4fffa (398849 bytes): DIFFERENT; equal
   once parsed True`, `mutant unsorted-configure: caught — KO failed` (load 98.16 219.80 252.05 →
   62.47 195.40 241.62).

**What its review found.** The challenge made four objections, all accepted: the suite has a
scratch path of its own and SA-12's marker governs it alone, so SA-8's clone rule for
`build/agent-swift` stands (1); the clone's failure and the guard's repair were measured in debug
rather than inferred from SA0's release figures (2, item 3 above); KO's mutant runs T1 in a mutant
launch A and then W's launch B of the same app and compares them (3); and the SA-3 mutant that had
nothing to mutate became `cancel-not-priced`, with H12 kept as a plain case (4).

**What is owed.**
- **SA2:** the two-helper drive, with SA-4's three behaviours, SA-5's request and SA-6's listed
  differences as its allowed list; a `cost`'s `dollars` compared as parsed doubles.
- **SA3:** the build script must never use `build/agent-swift-test`; the suite's marker is not the
  stamp's path record (SA-8); `tree_copy.py` copies `agent/` following the symlink, so a copy holds
  the table's bytes.
- **The integrator:** `agent/CLAUDE.md` and the root `CLAUDE.md`'s lines, from the build notes.

### SA2 — record

### SA3 — record

### SA4 — record

### SA5 — record
