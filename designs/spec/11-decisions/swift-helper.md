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
