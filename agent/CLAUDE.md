# agent/CLAUDE.md — the assistant helper's rules

Applies to everything under `agent/`. The shipped helper is the SwiftPM package here
(`Package.swift`, `Sources/`, `Tests/`; spec §11 SA-1..SA-13, in
`designs/spec/11-decisions/swift-helper.md`), the agent loop of
`Contents/Helpers/framejob-agent`, started once per window's conversation by
`AssistantSession`: every app build makes its release product with
`tools/agent/build_helper.sh` (SA-8). Nothing else lives here: the Bun helper and its
TypeScript were deleted in road map "swift-helper" (`designs/swift-helper.md`, #599) SA4
(SA-11). The package was ported once from Doctored's helper at that repository's `b524babc`
(the owner's answer 2 (a)) and has no identity rule with it or with Rasterize. `make
agent-test` runs its suite through `tools/agent/agent_test.py`, and
`tools/proof/agent_helper_drive.py` (in `make test`) runs the release helper over scripted
conversations on the stand-in API and fails any difference from its recordings in
`tools/proof/agent_helper_recorded/` (SA-13).

## Module map

One line per file; each file's doc comments hold its detail.

- `Package.swift` — swift-tools 6.0, Swift 6 mode, `.macOS("26.0")` in the string form on purpose
  (`.v26` needs PackageDescription 6.2, SA-1); Slaude by exact revision; `-warnings-as-errors` on
  the three targets under `FJ_AGENT_STRICT=1` (`make agent-test`); the kit embeds `anthropic.json`.
- `Package.resolved` — committed beside it.
- `Sources/framejob-agent/main.swift` — the stdin reader thread and line loop, the one stdout
  writer, Slaude's diagnostics routed to `Log`, exit 0 at stdin EOF.
- `Sources/FrameJobAgentKit/Protocol.swift` — `HostMessage` (app → helper), `HelperEvent`
  (helper → app, `message_done`, `prices` and `cost` among them), `Configure` (with
  `price_cache`, `price_feed`), `EventSink`.
- `LineSplitter.swift` — the LF-only line framing.
- `Session.swift` — `AgentSession`, the actor: configure (the prices, `ready`, the refresh),
  send, cancel, settings, tool answers, error wording.
- `Turn.swift` — the turn loop: one streamed request per round, `message_done` and `cost` per
  response, the partial price, the tool round trip, the end-of-turn sentences (#484's among them).
- `Compaction.swift` — the end-of-turn summary request, its price and its events (SA-4).
- `Request.swift` — the request bodies and betas, built once per configure (SA-5).
- `History.swift` — the verbatim, append-only history and the `pushUserText` merge.
- `ContextUsage.swift` — the context-meter arithmetic and cleared tool results.
- `ToolResults.swift` — MCP CallToolResult → tool_result blocks and the tab's summary.
- `ClientFactory.swift` — the Slaude client per configure, behind the `MessagesAPI` seam.
- `Pricing.swift` — `PriceTable`, `Price` and `Pricing.price`, the same steps in the same order
  as `tools/proof/prices.py` (spec §11 P-2, SA-3).
- `PriceTable.swift` — `PriceSource`, `LoadedPrices`, `PriceOptions` and `PriceTables`: the parse,
  the LiteLLM reducer, the feed rule, the bundled table, the prices at configure.
- `PriceRefresh.swift` — the daily refresh on URLSession and the cache's write.
- `anthropic.json` — a relative symlink to `prices/anthropic.json`; never a copy.
- `Log.swift` — stderr diagnostics.
- `Tests/FrameJobAgentKitTests/` — XCTest; `Support/` holds the scripted transport, the SSE
  builders and the 127.0.0.1 loopback server.
- `prices/` — `anthropic.json` (written only by `make prices`), and `cases.json` and
  `reduce_cases.json`, which the helper's price code and `tools/proof/prices.py` answer.

## Rules

- **stdout is protocol only**: one `HelperEvent` per line, written only by `StdoutWriter`.
  Diagnostics go to stderr through `Log`, every line starting `framejob-agent: `.
- **The protocol is the app's contract.** `AssistantSession` and `AssistantSpend` read events
  loosely, so a renamed type or field fails silently there; change one only with its app side and
  spec §11 (SA-6). The sentences the tab shows (the refusals, `API error <status>: …`,
  `API error: …`, the three end-of-turn sentences) are pinned by tests.
- **A change to what the helper sends or says is a decision first.** A change that makes its
  events, requests or wording differ from the recordings fails
  `tools/proof/agent_helper_drive.py`; it lands with its spec §11 SA- entry and the recordings
  rewritten by `--record` in the same commit, whose diff shows the change. Only two re-records
  need no new entry (SA-13): a `make prices` refresh (only `dollars` and the bundled table's
  `as_of` move) and a Slaude re-pin (only the client's own headers and its parser's words).
  Never re-record to make a failure pass.
- **History is verbatim and append-only**: `[RawJSON]` exactly as received, replayed byte for
  byte. Never route it through typed models, `JSONValue` or sorted keys. The only rewrites are the
  compaction swap at turn end and the `pushUserText` merge into an unanswered user message.
- **Every tool_use gets a tool_result** in the next user message, or the API refuses every later
  request: run or answered (a cancel's "Cancelled by the user.", an unknown tool, a final reply's
  unrun call), never left open (SA-2, SA-4).
- **A cancel never ends a tool wait, and a tool wait has no timeout** (SA-2, AI-7): every
  tool_request of a response goes out at once and every answer is awaited.
- **A turn prices at the table it started with**; a response cut short is priced once, partial,
  before any error, from `currentMessageSnapshot`, and one that failed before `message_start` is
  not priced (SA-3, P-5, P-8).
- **A turn keeps the clearing and betas it started with, and reads the compaction limit when it
  ends** (AI-20): `compactIfDue` reads the session's `settings`, never `turn.settings`, so a
  `settings` message's threshold applies at the end of the turn in flight and its clearing from
  the next turn.
- **The client comes from `configure` only**: explicit key and base URL, `environment: [:]`,
  `maxRetries` 3. The helper reads no environment variable or profile; its only file is the price
  cache `configure` names.
- **Slaude is the only dependency**, pinned by exact revision; it changes only through a pull
  request on Slaude's repository that the owner merges, with the branch's commit pinned meanwhile
  (SA-1, the road map's §12 answer 4). A bump edits the revision, re-resolves and commits
  `Package.resolved`.
- **async/await and actors are this package's concurrency model and nothing else's** (SA-7);
  `app/Sources` keeps W-8.
- Every file stays under 400 lines.
- **Tests use no network and no real key**: dummy keys, Slaude's `MockTransport` through
  `ClientFactory`, and the 127.0.0.1 `LoopbackServer`. The suite runs on `build/agent-swift-test`
  through `make agent-test`, whose guard empties a scratch path made at another path (SA-12);
  never on `build/agent-swift`, the app build's (SA-8).
- **The suite reads its price fixtures from `prices/`**, through `PriceFiles`, unless
  `FJ_AGENT_PRICES` names a whole copy of that folder (`tools/proof/prices_proof.py`'s
  `swift-disagrees` mutant); the helper itself reads no environment variable.
- **A proof's helper is built by `tools/agent/build_helper.sh`**: the tree's through
  `tools/proof/agent_helper_build.release`, a mutant through `agent_helper_build.mutant` on
  `build/agent-swift-mutant/`; never by editing this folder in place (SA-8).
