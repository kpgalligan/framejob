# Spec §11 — decisions: The assistant helper in Swift (road map "swift-helper")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map is in progress at `designs/swift-helper.md` (#599): the assistant helper becomes a
Swift executable on Slaude, the owner's Swift client for the Claude API, in place of the
Bun-compiled TypeScript. Its §8 names the SA- decisions and the phase that writes each; its §13
holds what each phase measured, SA0's spike first. SA-1..SA-3 are SA0's, decided 2026-11-12 after
the owner approved the road map and answered its §12 on #599. SA-4 on are appended here by the
phases §8 names, each before its code. Each entry binds the code from the phase that builds it:
until SA3's switch lands, the shipped helper is the one AI-1, P-2 and P-8 describe.

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
  `auto_compact_tokens` (`null` never compacts); one summary request, the round's body without
  `context_management` and with `compaction {type: summarize, instructions}`; the events
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
  three differences by name, and nothing else.
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
  sentence; and the cache file holds the same table
  written compact, where the TypeScript indents it, each helper reading the other's file. A
  `cost`'s `dollars` is the same double written in Swift's shortest spelling (`1e-07` where
  JavaScript writes `1e-7`), so SA2 and every reader compares parsed values. Why: `message_done`
  costs one line per response and `spend_proof.py`'s H10 needs it to be able to fail; `ready` is
  what `assistant_helper_proof.py` P3 waits for; `reset` has no sender. A later phase that drops
  `message_done` names the four sites of road map §2 in the same change and gives H10 a clause that
  can still fail. Risk accepted: a client that sends `reset` hears nothing back.
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
