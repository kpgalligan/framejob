# Spec §11 — decisions: The assistant helper in Swift (road map "swift-helper")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map is in progress at `designs/swift-helper.md` (#599): the assistant helper becomes a
Swift executable on Slaude, the owner's Swift client for the Claude API, in place of the
Bun-compiled TypeScript. Its §8 names the SA- decisions and the phase that writes each; its §13
holds what each phase measured, SA0's spike first. SA-1..SA-3 are SA0's, decided 2026-11-12 after
the owner approved the road map and answered its §12 on #599. SA-4 on are appended here by the
phases §8 names, each before its code. Each entry binds the code from the phase that builds it:
until SA3's switch lands, the shipped helper is the one AI-1, P-2 and P-8 describe. SA-11 and
SA-13 are SA4's, the deletion of the Bun helper.

- **SA-1 — The assistant helper is a Swift executable built from a SwiftPM package in `agent/`,
  on Slaude pinned by exact revision; the process boundary and the stdio protocol stay.** It is
  still `Contents/Helpers/framejob-agent`, same name and place, and the app still talks to it
  over stdin and stdout with `Process`, pipes and GCD. The package is swift-tools 6.0 in Swift 6
  mode with `platforms: [.macOS("26.0")]`, the app's floor, in the string form on purpose: the
  spelling `.v26` needs PackageDescription 6.2 and is refused under 6.0 (road map §13, SA0 item
  1), so it is not to be "fixed". Slaude is `https://github.com/kpgalligan/Slaude` at revision
  `4c6c2ca435350741796c3d461720a61e7149b378`, the revision Doctored ships and Slaude's `main` on
  2026-11-12 (SA0 item 10), a dependency of `agent/` alone with `Package.resolved` committed:
  never vendored, never copied piecemeal, never linked into the app, which builds in Swift 5 mode
  with no extra module. Slaude changes only as the owner's answer 4 (road map §12) says: a branch
  and a pull request on Slaude's repository, the owner merging, Frame Job pinning the branch's
  commit until it re-pins. Why: the owner on #599, "We're going to replace Bun with the Swift
  Anthropic API we wrote"; Doctored made the same move (its AH-1, AH-2), and SA0 built its package
  against the pin under this Xcode with its suite passing (SA0 item 1). **Amends AI-1**: its
  "Bun-compiled from `agent/` on the Anthropic TypeScript SDK's Tool Runner", "the one TypeScript
  in the product" and its accepted risk "Bun in every `make app`" hold until SA3's switch, and
  then this entry replaces them. Risk accepted: Slaude's compile on every worktree's first build
  and on the publish runner, at the cost road map §10 measures; about 4 GB of SwiftPM products in
  every worktree that builds the helper and runs its suite (road map §10); the first build needs
  the network; Slaude is young and has one maintainer.
- **SA-2 — The helper runs its own turn loop, not Slaude's tool runner.** One streamed request
  per round: `tool_use` runs the tools and sends the next round, `pause_turn` resends, any other
  stop reason is the turn's final reply, and thirty rounds end the turn. Every `tool_use` of a
  response is asked of the app at once (`tool_call`, then `tool_request`), and every one is
  answered before the next request, so the history never holds a `tool_use` without its
  `tool_result`. A cancel closes the stream in flight and never ends a tool wait; there is no
  timeout on a tool wait, and no next request while an answer is outstanding, which is what lets
  AI-7's ask-first hold sit in the app with the helper unchanged. The history is kept as raw JSON
  and replayed byte for byte, and each request body is raw JSON in a pinned key order. Why:
  Slaude's runner runs tools one at a time and rethrows a cancel out of a tool, which can leave a
  `tool_use` with no result and fail the next request (Doctored's AH-3); Doctored's loop, built
  unchanged at the macOS 26 floor, passed its suite and sent Frame Job's ten body keys in today's
  order (SA0 items 1 and 7). The agent lane and the session are the app's, so AI-2, AI-5, AI-10,
  AI-12 and AI-16 are not amended. Risk accepted: the loop is Frame Job's to keep, with no SDK
  runner beneath it.
- **SA-3 — Pricing stays, in the Swift helper.** The owner's answer 1 (a) (road map §12): the
  conversation's Spend figure and Settings' month figure stay. The price function and the table
  with its daily refresh are ported into the package and answer the same fixtures
  (`agent/prices/cases.json`, `agent/prices/reduce_cases.json`); `prices`, `cost`, `price_cache`
  and `price_feed` keep their shapes; `tools/proof/prices.py` stays the second reader. The bundled
  table is compiled in with SwiftPM's `.embedInCode` through a committed relative symlink in the
  target to `agent/prices/anthropic.json`, which stays where `make prices` writes it, and the
  build's stamp digests the table's content, which a digest of the files under `agent/Sources`
  without following links does not reach (SA0 item 4). A response cut short is priced from
  Slaude's `currentMessageSnapshot`: when a round throws and the snapshot is not `nil`, once, as
  `partial`; a reply that returned from `getFinalMessage()` is priced complete and never again
  (`spend_proof.py`'s H12). SA0 found the snapshot holds what P-8 and H10 and H11 want: input 100
  and output 0 for a cut before `message_delta`, input 100 and output 10 after it (SA0 item 5).
  **Amends P-2 and P-8** where they name the SDK: P-2's pricing "in the helper" is the Swift
  helper's, and its "the SDK's `BetaUsage.iterations` doc" stays only as the source for what
  `iterations` means, read the same way from the response's raw JSON; P-8's "the SDK's
  accumulating snapshot … until `finalMessage` resolves" becomes Slaude's `currentMessageSnapshot`
  until `getFinalMessage()` returns, and its lower bound does not move. P-1, P-3..P-7 and P-9 are
  not amended. Risk accepted: P-8's, unchanged; and a price-table edit now needs a helper rebuild,
  which the stamp's digest of the table is there to force.
- **SA-4 — Compaction is one explicit rule, and three of the runner's behaviours change with it**
  (SA1, road map §5 "Compaction and clearing"). What stays: compaction only at a turn's end, after
  its final reply, never between tool calls and never after a cancel, once the context reaches
  `auto_compact_tokens` (`null` never compacts), the threshold read when the turn ends and
  clearing and its beta fixed when it starts, as AI-20 has it; one summary request, the round's
  body without `context_management` and with `compaction {type: summarize, instructions}`; the events
  `compaction_started`, `compacted` and `compaction_failed`; and the three end-of-turn sentences,
  #484's "The reply was cut off because the conversation filled the model's context window." among
  them, which Doctored's helper drops and Frame Job keeps. Success needs both the `compaction` stop
  reason and a `compaction` block whose `content` is a non-empty string; the history is then the
  summary response as it came. What changes from the TypeScript runner's implicit compaction: (a) a
  final reply that ends in `tool_use` blocks (a `max_tokens` cut after a tool call) has each block
  answered at once, unrun, as an error result "Not run: the reply stopped with <reason> before this
  call could run.", so the next request is valid, where the runner's history could end with an
  unanswered `tool_use`; (b) after such a reply no summary is requested: `compaction_started`, then
  `compaction_failed` "no summary came back", and the next turn end tries again; (c) a `compaction`
  stop whose block holds `null` or an empty string is `compaction_failed` "the summary came back
  empty", never a swap, where the runner would have swapped the history for an empty summary. Why:
  SA-2's loop has no runner to compact implicitly, and Doctored's rule (its AH-3) is the one its
  suite already holds; the three changes each remove a request the API refuses or a conversation
  lost for nothing. **Amends AI-9 and AI-20** where they point at `agent/src/main.ts` for the rule
  and `CLEAR_TRIGGER_TOKENS`: from SA3's switch these are the package's `Compaction.swift`,
  `Turn.swift` and `Request.clearTriggerTokens`. Risk accepted: SA2's two-helper drive allows these
  three differences by name, and nothing else. SA2 measured (`tools/proof/agent_helper_drive.py`,
  road map §13): (b) is no difference, since the 0.128.0 runner already skips the summary after
  such a reply and both helpers send nothing and say "no summary came back"; (c) differs in events
  only, since that runner keeps the history when the block is empty and only `main.ts`'s report
  says `compacted`; and "success needs both" makes a fourth difference, allowed by name under
  this entry: a summary holding a non-empty `compaction` block that stopped with another reason
  replaces the TypeScript runner's history with that block, though `main.ts` reports
  `compaction_failed`, where the Swift helper keeps the conversation.
- **SA-5 — The request: today's body in a pinned key order, the system block's own cache
  breakpoint, API version `2026-10-21`, Bearer credentials, and sorted keys from the app** (SA1,
  road map §5 "The request"; the owner's answer 6 (a)). The body is raw JSON with today's keys in
  `main.ts`'s order — `model`, `max_tokens`, `system`, `tools`, `messages`, `cache_control`,
  `output_config`, `thinking`, `fallbacks`, then `context_management` while clearing is on, then
  `stream`, and for the summary `compaction` last — and today's values; no sampling parameter. The
  tool list (tool search first, then the catalog in the app's order, each schema in its own key
  order, all but the core tools deferred) and `system` are built once per `configure` and sent as
  the same bytes on every round and in every process. `system` is a list of one text block, the
  app's system prompt, a blank line and the search guide, carrying `cache_control {type:
  ephemeral}`, so a new conversation and the first request after a compaction read the
  tools-and-system prefix from the cache instead of writing it again; the top-level automatic
  breakpoint still covers the history. The API version is Slaude's `2026-10-21` and the credential
  `Authorization: Bearer <key>`, and the path carries no `?beta=true` (SA0 items 6 and 7). The app
  writes every helper message with `.sortedKeys` (`AssistantSession.write`), so the same catalog is
  the same `configure` bytes on every launch, and the helper's prefix with it: SA0 item 8 measured
  two launches' `configure` lines equal once parsed and different in key order at every level, and
  the Bun helper's prefixes from them different (402,397 bytes each, not identical). `writeResult`
  splices a tool's result as the dispatcher returned it and is unchanged. Why: a cached prefix is
  only read back when its bytes repeat, which neither a per-launch hash order nor a breakpoint the
  growing history moves can give; Doctored measured about 9,700 tokens written without the
  breakpoint and read with it (its `0bb54fc2`). **Amends AI-13** where it cites the shared
  `protocol.ts`: from SA3's switch `api_base` is read by the package's `Protocol.swift` the same
  way. Risk accepted: the bytes `assistant_lane_proof.py`'s B1 and the paid proofs'
  `BODY_BYTES_BOUND` measure change (SA3 re-measures B1, SA-9); the sorted keys also change the
  order inside each tool's schema in what the Bun helper sends until the switch, an order that was
  a per-launch hash order and that nothing could depend on; sizes do not move.
- **SA-6 — The protocol keeps every message and event the app or a proof reads, `message_done` and
  `ready` included, and drops `reset`** (SA1, road map §5 "The protocol"). `reset`, which nothing
  in `app/Sources` writes (Clear closes the process), is ignored like any unknown type: no event,
  the history kept. `ready` answers `configure`; `prices` comes before it when no refresh is due,
  else after it, when the refresh settles. Per response of a turn's rounds the order is
  `message_done`, `cost`, `context_usage`, then any `tool_results_cleared`; a summary response
  emits `cost` and then `compacted` or `compaction_failed`, and no `message_done`; a response cut
  short emits one `cost` with `partial: true` before any `error`. The shapes are `protocol.ts`'s,
  `type` first and the fields in its order, `partial` present only when true and a field the
  response lacked absent. These differences from the TypeScript are deliberate and are SA2's
  allowed list, each named there: `configure` is validated when it arrives ("Bad message from the
  app: configure needs a string api_key"), and a line that is JSON but not an object is answered
  with an error; the text after "Bad message from the app: " is Swift's parser's; a refresh
  settling after a later `configure` is dropped (the app sends one `configure` per process);
  `fetched_at` is read as ISO 8601 with or without fractional seconds (JavaScript's `Date.parse` is
  laxer, and anything else means a refresh is due, as an unparseable date does today); the feed's
  URL is read by Foundation's `URLComponents` and must have a host, where the TypeScript reads it
  with WHATWG's `new URL`, so a URL only one of them accepts is refused by the other in the same
  sentence; an API error reads `API error <status>: <message>` with Slaude's message and status,
  so an `error` event mid-stream carries its type's status (529 for `overloaded_error`) where the
  TypeScript gives every such event none, and one with no status (a failed connection, an `error`
  event of a type Slaude does not map, a stream cut short) reads `API error: <message>`, where the
  TypeScript writes `API error : <message>`, or for a stream cut short its SDK's message alone; and
  the cache file holds the same table written compact, where the TypeScript indents it, each
  helper reading the other's file. A `cost`'s `dollars` is the same double written in Swift's
  shortest spelling (`1e-07` where JavaScript writes `1e-7`), so SA2 and every reader compares
  parsed values. Why: `message_done` costs one line per response and `spend_proof.py`'s H10 needs
  it to be able to fail; `ready` is what `assistant_helper_proof.py` P3 waits for; `reset` has no
  sender. A later phase that drops `message_done` names the four sites of road map §2 in the same
  change and gives H10 a clause that can still fail. Risk accepted: a client that sends `reset`
  hears nothing back.
- **SA-7 — `async`/`await` and actors are the concurrency model of `agent/` and of nothing else; W-8
  is bounded, not amended** (SA1). W-8 and its two files (`MediaImporter.swift`,
  `SpeechEngine.swift`) govern `app/Sources`, which gains no `async`, and `make typecheck` keeps its
  baseline. The package is Swift 6 with actors (`AgentSession`), in its own process and its own
  build, and links nothing of the app's. Why: W-8 names files, not a directory, and the helper's
  model is Slaude's (AI-1's reason, Doctored's AH-7). Risk accepted: two concurrency models in one
  tree, kept apart by directory.
- **SA-12 — `make agent-test` runs the suite on a scratch path of its own, `build/agent-swift-test`,
  and empties it before SwiftPM runs whenever its marker is missing or names another path** (SA1,
  numbered after the SA-8..SA-11 road map §8 reserves; objections 1 and 2 of the phase's challenge).
  `tools/agent/agent_test.py` keeps `.framejob-scratch-path` inside the scratch path, holding its
  own absolute path; a scratch path without one, or with one naming another path, is emptied and
  marked, and then `swift test --package-path agent --scratch-path build/agent-swift-test` runs
  with `FJ_AGENT_STRICT=1`. `build/agent-swift`, the app build's release scratch path, is SA-8's and
  is never touched by the suite: SA-8's own rule (a clone served at any path while its stamp
  matches, the recorded path read only on a miss) is unchanged. Why: every lane worktree starts by
  CoW-copying the integration worktree's `build/`, and SwiftPM cannot build on a scratch path made
  at another path (SA0 items 3 and 9, in release); SA1 measured the same of the debug suite (road
  map §13, SA1's record): a `cp -cRp` clone of a warm suite scratch path, used from another tree,
  failed in 23 s with 2,386 "PCH was compiled with module cache path" errors, and through the guard
  it was emptied, built cold and passed its 76 tests in 175 s, and passed again in 8 s. The suite
  has no stamp to serve a clone from, so its marker is read on every run. Risk accepted: a worktree that copied `build/` builds Slaude cold once in debug
  (about two minutes, the cost the owner's answer 5 accepted), and the suite's scratch path is a
  second one per worktree beside SA3's (about 2.3 GB, road map §10).
- **SA-8 — The app build makes the helper with `tools/agent/build_helper.sh`: SwiftPM in release,
  in batches, on `build/agent-swift`, skipped by a content stamp that serves a clone at any path,
  the tree taken from the caller, the product stripped and signed with the hardened runtime and
  no entitlements; a helper mutant is built by the same script on one persistent mutant tree**
  (SA3, road map §7, §9 SA3, §10). Project.yml's "Build Agent Helper" step is the one line
  `/bin/bash "$PROJECT_DIR/tools/agent/build_helper.sh"` with the bundle's
  `Contents/Helpers/framejob-agent` as its argument. The script takes its tree from
  `$PROJECT_DIR`, refusing to run when it is unset, and never from its own path, because a tree
  copy's `tools` is a link to the tree's. It runs `swift build --product framejob-agent` in the
  release configuration, without whole-module optimization and in batches, on
  `<tree>/build/agent-swift`, under `env -i` with only `HOME`, `TMPDIR`,
  `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and, when set, `DEVELOPER_DIR`, so no key, no
  `FJ_AGENT_STRICT` and none of Xcode's build settings reach SwiftPM. It has no configuration
  knob (the owner's answer 5 (a)) and never touches the suite's scratch path (SA-12). A stamp
  inside the scratch path holds a key and the product's size and time, and SwiftPM is skipped
  while all three match. The key digests the script, the toolchain, `agent/Package.swift`,
  `agent/Package.resolved` and every file under `agent/Sources` read through links, so the price
  table's content is in it (SA-3), and a tree and its copy agree where the copy holds the
  table's bytes as a regular file. The scratch path's own absolute path is a second file beside
  the stamp, `.framejob-helper-path`, never part of the key and read only on a miss: a miss on a
  scratch path whose record is missing or names another path empties it and builds Slaude cold,
  because SwiftPM cannot build on a scratch path made at another path (SA0 items 3 and 9). So a
  clone is served at any path while its key matches, and a tree copy
  (`tools/proof/tree_copy.py`) receives the tree's scratch path as a `cp -cRp` clone, never as a
  link: a copy that builds a mutant changes the helper on purpose, and through a link it would
  become the tree's product. Whether dropping only the module cache would repair a foreign
  scratch path was not measured and is not needed: SA0 item 9 saw SwiftPM schedule all of Slaude
  again on a moved one, so the best case is the cold build. A dependency edited in place
  (`agent/Packages`) or local runs SwiftPM every time with no stamp, as Doctored's script has it.
  The destination is removed before SwiftPM runs, so a failed build fails the step with no
  helper at the destination and no stamp. The product is copied out, its linker signature
  removed, `strip -x`ed and signed `--options runtime` with no entitlements, ad hoc or with
  Xcode's identity and a secure timestamp. **A helper mutant**, a proof's scratch helper, is
  built by this script on one persistent tree per worktree, `build/agent-swift-mutant/`, under a
  lock: its own `agent/`, brought to the tree's file by file by content (only a file that
  differs is written) before the mutant's edits are applied, and its own `build/agent-swift`,
  cold once and incremental after (`tools/proof/agent_helper_build.py`). Never by SwiftPM on a
  clone of the tree's scratch path, which cannot build a changed `agent/` (SA0 item 9), and not by
  the direct `swiftc` builder SA0 recommended, which was never measured with the embedded table
  and would compile a mutant differently from the product. **Amends PUB-4 and the contract of
  `dist_check.py`'s D10/D11 and `published_check.py`'s P8** (spec §7.9b): the helper holds the
  `runtime` flag and no entitlements, where `allow-jit` was JavaScriptCore's (Doctored's AH-6).
  Why: Doctored's script, measured in this tree by SA0 (its 122.4 s cold build, its 1.21 s step on
  a served clone, its PCH failure on a moved scratch path), with the three rules SA0 found it
  lacks: the table's content in the key, the path record beside the key, the tree from the
  caller. `tools/proof/agent_build_proof.py` holds the script's rules over toy packages in
  `make test`, each rule with a mutant. Risk accepted: a worktree's first app build compiles
  Slaude (SA0's 122–392 s) and needs the network; a cloned scratch path that misses builds cold;
  a worktree that builds helper mutants holds a second release scratch path (about 1.8 GB) and
  builds it cold once; `make test` builds the release helper (SA-9).
- **SA-9 — `assistant_lane_proof.py`'s B1 measures the first POST of the release helper SA-8's
  script builds, configured as the app configures it** (SA3, road map §5 "The request"). The probe
  writes the `configure` the app writes — the assistant catalog through
  `AssistantToolTable.assistantCatalog`, `AssistantPrompt`'s system prompt, search guide, core
  tools and compaction instructions, the dummy `proof-key`, tool-result clearing on, sorted keys,
  no spend fields — and B1 starts the helper on it against the stand-in, sends one short message,
  and reads the first POST's bytes from the stand-in's log. That POST's `tools` must be the
  catalog plus tool search and its system text the prompt, a blank line and the guide; then its
  bytes plus `CONVERSATION_BYTES_BOUND` must fit `BODY_BYTES_BOUND`. The hand mirror of the wire
  shape (`requestBytes` in `assistant_lane_probe.swift`) is deleted. **Amends P-9 (d)**: its "B1's
  measure mirrors the helper's wire shape by hand until the helper is Swift (#599)" is struck; the
  measure is the helper's own bytes, envelope and one short message included, and
  `CONVERSATION_BYTES_BOUND` stays the room for the rest of a conversation. Why: SA-5 changed the
  bytes (the system block's breakpoint, the key order), and a mirror can drift from the helper it
  mirrors where the helper's own POST cannot. Risk accepted: `make test` builds the release helper,
  seconds while its stamp matches and SA0's cold build in a worktree that has none; no spend
  fields are sent, so the helper B1 starts makes no price request and writes nothing.
- **SA-10 — The acknowledgements list Slaude and no longer read npm or Bun, and the publish runner
  installs no Bun, in the commit that switches the build step** (SA3, road map §2, §9 SA3).
  `tools/licenses/acknowledgements.py` reads neither `agent/bun.lock` nor `agent/node_modules`,
  checks no `bun --version`, and has no `--strict-bun` or `--print-bun-version`; the `runtime bun`
  entry, `BUN_LICENSE_VERSION` and `tools/licenses/bun/` are gone, and with them the LGPL notice,
  since nothing left in the bundle embeds JavaScriptCore (#380's review is moot). Slaude is the
  entry `== package slaude <revision> ==`, read as Sparkle's is: the revision from the
  `workspace-state.json` of the scratch path the caller names (`--agent-scratch`, which
  project.yml's "Write Acknowledgements" passes as `$PROJECT_DIR/build/agent-swift`, else the
  tree's), and the texts from its resolved checkout. They are Slaude's `LICENSE` (Apache-2.0) and,
  because Slaude's sources are transformed from Anthropic's Python SDK and its README says the
  vendored SDK keeps its own licences, that SDK's `LICENSE` and `LICENSE-MIT`; the two files of the
  SDK's vendored `httpx_aiohttp`, a Python transport of which nothing ships, are listed as excluded
  in `NESTED`, and a licence file a later pin adds fails the build until it is listed. A missing
  state or checkout fails the build naming the path. `dist_check.py`'s D42/D43 and
  `published_check.py`'s P25 want `package slaude` at `agent/Package.resolved`'s revision, read
  with their own reader, and refuse a header of any kind the file no longer holds (`npm`,
  `runtime`). The publish workflow loses `oven-sh/setup-bun` and the pins step's Bun output: once
  the step is switched nothing on the runner runs Bun. **Amends PUB-10** (its npm and Bun
  sentences, and its accepted risk of Bun's LGPL notice by link, are struck) **and PUB-12**
  (`setup-bun`). Bun stays a build tool until SA4 only for `make typecheck`'s tsc, `gate.py`'s
  fingerprint and SA2's two-helper drive, none of which reads the notices. Why: the npm reader read
  `agent/node_modules`, which only the Bun step's `bun install` made; a tree copy has none of its
  own and the runner never ran it, so the old notices could not outlive the old step, and the
  bundle would have listed Bun and not Slaude (road map §2). Risk accepted: the step reads
  SwiftPM's checkout, so it runs after Build Agent Helper; a base copy of a commit before SA3
  (`tree_copy.make_base_copy`), which passes no `--agent-scratch`, reads the tree's scratch path,
  so the tree's helper must have been built; and a real publish is the first run of SwiftPM on the
  runner (road map §10).
- **SA-11 — The helper's package is Frame Job's own, ported once from Doctored at `b524babc`, with
  no identity rule; the Bun helper, its TypeScript and its build are deleted, and Bun and
  TypeScript are no build tool of this tree** (SA4, the owner's answer 2 (a), road map §12). No
  file of `agent/` is kept equal to another repository's, and nothing checks it against
  Doctored's or Rasterize's: a change either makes reaches this tree only as a Frame Job phase that
  decides it. Deleted: `agent/src/` (the TypeScript helper and its `bun test` files),
  `agent/package.json`, `agent/bun.lock`, `agent/tsconfig.json`, `agent/entitlements.plist` and
  `agent/build.sh`, with `.gitignore`'s `/agent/node_modules/`. `make typecheck` is the `swiftc`
  check of `app/Sources` alone (W-8's four warnings, SA-7); `gate.py`'s tool fingerprint holds no
  `bun --version`, and `agent` leaves the `typecheck` step's inputs and stays in `app`'s. SA2's
  two-helper comparison goes with the Bun helper, and its cases stay as the Swift helper's drive,
  held to recordings (SA-13). Road map 12's A0 spike, `tools/proof/assistant_spike/`, is retired:
  it builds a copy around Rasterize's TypeScript `agent/`, which has held a SwiftPM package since
  Doctored's `33af04c1`, so it could not pass, and nothing in `make test` or `make gate` ran it;
  its record stays in `designs/adr/roadmap-12-assistant.md`. kpgalligan/rasterize#654 (NM-10's
  three lines) and kpgalligan/rasterize#325 (road maps 12 and 13's hand-over of the helper and of
  its price code) have nothing left to apply and are the owner's to close. **Amends AI-15** (its
  "`agent/` is one diff with Rasterize (#147)" is struck; the rest stands: `configure` is the
  helper's only system channel, and a prompt that changed per turn would still break AI-9's
  unchanged prefix) **and NM-10** (struck whole: there is no shared `agent/src`, and nothing is
  recorded for Rasterize to apply). Why: the owner's answer 2 (a), "the two already differ in
  pricing, #484's sentence, the platform and their names, and a shared rule with no checker is the
  kind that rots"; and after SA3's switch nothing built from the TypeScript ships, so keeping it
  only typechecked a dead helper and kept Bun on every machine that builds. Risk accepted: a fix
  Doctored makes to the loop both share reaches Frame Job only when a phase here ports it, and
  nothing in this tree says when one is made.
- **SA-13 — The drive holds the Swift helper to its recordings: every event and every request,
  key order included** (SA4; the challenge of SA4's plan). `tools/proof/agent_helper_drive.py` (in
  `make test`) runs the release helper over its cases on the stand-in as SA2 did, and holds each
  run to `tools/proof/agent_helper_recorded/<case>.json`: the event stream, every request (method,
  path, headers, body and its byte count) and, for a case that writes the price cache, its table
  and its bytes, compared by SA2's comparison (parsed JSON with each object's key order at every
  level, numbers by value). The case's own `expect` (event types, POST and request counts, the
  stand-in's failures, feed GETs) is checked first, as before. A recording holds the run as the
  helper made it, except where one of three comparison rules, applied the same way to the run and
  to the recording, puts a placeholder: a clock reading (a fetched or cached table's `as_of`, the
  cache file's `fetched_at`) must be an instant inside the run and is then `<clock>`; the cache
  file's `source` must be the URL of the drive's own price feed, whose port is chosen per run, and
  is then `<feed>`; and seven headers set by the host or the toolchain, not by the helper, are
  held by presence only — `host` (the stand-in's port), `accept-language`, `accept-encoding`,
  `connection`, `x-stainless-arch`, `x-stainless-os` and `x-stainless-runtime-version` — the
  headers compared as a set, in no order, and every other header by value. Nothing else has a
  rule: the words after "Bad message from the app: " for a line that is not JSON are Slaude's own
  parser's ("key must be a string at line 1 column 2"), not Foundation's, so they are held by
  value like every other event. A field found to vary between runs or hosts joins a rule by name,
  with its reason, in an entry here; a rule is never widened to a pattern. **The bridge:** the
  recordings were written by `--record` from the Swift side of a run of SA2's two-helper drive
  that passed whole, before the Bun side was deleted, so each holds a stream equal to the Bun
  helper's but for SA2's sixteen allowed differences, and SA-6's "SA2's allowed differences" are
  from SA4 the history of how the recordings were reached. **`--record`** rewrites the recordings of every case or of
  `--cases`; it refuses, writing nothing and exiting 2, with `--mutant` or when any case it ran
  fails a check other than its recording (its `expect`, an exit other than 0, a stderr line without
  `framejob-agent: `), and it prints each case as `new`, `same` or `changed` with the paths that
  changed. `make test` never passes it. A case with no recording fails, and a recording with no
  case fails the run's `recordings` row. `prices-cached` starts on the cache file the Swift helper
  wrote in `prices-fetched`, where it started on the other helper's; reading a cache in the Bun
  helper's indented layout, which a person's spend folder may hold, stays held by the suite's
  `PriceTableTests`. **Re-recording without a new decision** is for two changes only, each of which
  the printed paths show: `make prices` refreshing `agent/prices/anthropic.json` (only `cost`'s
  `dollars` and the bundled table's `as_of` move), and a re-pin of Slaude (only the client's own
  `user-agent` and the `x-stainless-*` headers held by value, and its parser's words in
  `bad-lines`, move), which lands with the re-pin's own record. Any other change to a recording is a change to what the
  helper sends or says: it lands with its own SA- entry in the same commit, the recordings' diff
  showing it, and a failure is never re-recorded to make it pass. Why: SA2's comparison with the
  Bun helper held every byte of both streams, while a case's `expect` holds only types and counts,
  and five of the drive's eight mutants change only a request body; a recording keeps what SA2
  held once the helper it compared with is gone. Risk accepted: a Slaude re-pin or a toolchain
  that changes a request legitimately fails `make test` until re-recorded; `x-stainless-timeout:
  NOT_GIVEN` (#614) is now held by value and no longer compared with the TypeScript SDK's header.
