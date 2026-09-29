# Pricing and spend (road map 13)

- **Status:** Built and closed 2026-09-28. P1 the price table and the price function (`79a8b56`); P2 the helper prices every response (`0f0a442`); P3 the proofs' ledger and the monthly budgets (`86162c2`); P4 spend in the UI and the close (uncommitted when this was written). Each phase was one litecode pipeline; P2's review found five nits and P3's three, each fixed in its phase.
- **Original:** `archive/reelcut-roadmap-13.md` (415 lines) is the full record. Sections cited below as "orig §x" refer to it.
- **Spec decisions:** P-1..P-7 in spec §11 (`designs/spec/11-decisions/pricing.md`), which stay binding:
  - P-1: prices come from LiteLLM's table; only AssemblyAI's rate is hand-kept; Anthropic's page is the cross-check.
  - P-2: a call is priced from the response's own `usage` and `model`, per `iterations` entry; unknown is never $0.
  - P-3: budgets are dollars per calendar month per service ($25 Anthropic, $5 AssemblyAI), enforced by the proofs at the worst case.
  - P-4: spend shown in the app is Reelcut's own, and says so.
  - P-5: the spend ledger and the price cache are the person's, in the spend folder; a proof never touches them.
  - P-6: the proofs' ledger is `~/Library/Application Support/Reelcut Proofs/spend.jsonl`; every paid proof request is reserved at its worst case there and refused past the month's budget.
  - P-7: the app shows the conversation's cost on the Assistant tab and the UTC month's, folded from the ledger, in Settings; unpriced and unreadable lines are counted, never $0.
  The helper's prices and the two figures are specified in spec §7.9; the tab's Spend row in §4.3; the files are mapped in §7.4.

## Context

The user asked for three things: a spend budget, a price on every call the assistant and the proofs make, and, eventually, spend in the UI. Their rules: no hand-kept price data where a reliable online source exists, a library if it is reliable, and $25 a month for Anthropic and $5 for AssemblyAI. Before this road map nothing was priced: the assistant's turns and the paid proofs reported tokens, and the proofs' only guard was a per-run cap. No op, model field, FFI export or schema bump was added; Swift only records and shows the helper's dollars, and there is no pricing code in Swift or Rust. (orig §1, §2)

## Decisions

- **LiteLLM's table is the feed; a library was rejected.** `@pydantic/genai-prices` lacked `claude-opus-5-5` and `claude-fable-5-1`; the npm repackagings of LiteLLM add a lag and a dependency for four multiplications. LiteLLM's `claude-opus-5-5` row equalled Anthropic's pricing page exactly. AssemblyAI's Universal-3.5 Pro is absent from every source, so `AssemblyAIRates` stays the one hand-kept rate. (P-1; orig §1)
- **One committed table, written only by `make prices`.** `agent/prices/anthropic.json` holds LiteLLM's 20 Anthropic rows in $/MTok with the LiteLLM commit they came from; `update.py` (stdlib) is its only writer and `make prices` a prerequisite of nothing. `prices_crosscheck.py` compares the rows Reelcut uses against the page, over the network, outside `make test`. (P-1; orig §5 P1)
- **The top-level `usage` is not the whole bill.** It describes only the attempt that returned the message; `usage.iterations` lists every billed attempt (a refused attempt before a fallback, a compaction pass), each at its own model. So a call is priced per iteration when there are any. Fast, priority/batch and US-only usage, a malformed count and a class whose rate a row lacks all answer `unknown`, never the base rate. (P-2; orig §1's correction, §5 P1)
- **Two readers, one fixture.** `agent/src/pricing.ts` (the helper) and `tools/proof/prices.py` (the proofs) answer the same `agent/prices/cases.json`, both in `make test` (`prices_proof.py`), and each made to fail against the other. (P-1, P-2; orig §5 P1)
- **The helper prices every response, at the prices in force when the turn started.** It keeps the bundled table or the spend folder's cache, refreshed at most daily from LiteLLM's raw file (or `-RCPriceFeed`, https or loopback only), and emits `prices` once per `configure` and a `cost` for every response and compaction summary. H9 measured a refresh that settled mid-turn: the turn's two `cost`s stayed bundled and the next turn's were fetched. (P-2, P-5; orig §5 P2)
- **The spend folder is the person's, and a proof never reaches it.** `-RCSpendFolder` (argument domain alone) replaces it; with `RC_ASSISTANT_BASE_URL` set and no `-RCSpendFolder` there is none, nothing is written and the helper prices from its bundled table; with the override the cache goes to the helper only beside `-RCPriceFeed`. Every proof that launches the app checks the person's two files' existence, size and mtime before and after. (P-5; orig §5 P2, P4)
- **The ledger is a whitelist.** One `.sortedKeys` line per `cost` — `time` (UTC), `service`, `model`, a field-by-field `usage`, `dollars`, `unknown`, `rows`, `prices` — appended with one `write` to a 0600 file; never a key or content (S3's banned-token check). (P-5; orig §5 P2)
- **The proofs hold every paid request to the month's budget, fail closed.** `budget.py` is the only writer of the proofs' ledger, outside the repo and outside the spend folder; the read, fold and append run under one `flock`, and the worst case is the dearest rate over every row and tier. A torn line stops every paid proof until a person repairs it. (P-3, P-6; orig §5 P3)
- **The app shows two figures, both its own estimate.** The tab's Spend row is the transcript's sum since the last Clear or ended conversation; Settings' month line is a fold of `spend.jsonl` over the **UTC** month, so the app and P-6 count one month, with "(UTC)" in the title. An unpriced line is counted and said, never $0; an unreadable one is counted; no spend folder says so. (P-4, P-7; orig §5 P4)
- **Settings reads the ledger only when it matters, and off main.** When the window shows and after each line `record` writes while it is visible (`didRecordNotification`), on `AssistantSpendMonth.queue`; an absent ledger answers synchronously, only the latest read is shown, and a read after a recorded line keeps the shown sentence until its fold answers, so the window does not jump twice per response (C3). The harness hands Settings an absent spend folder because its `pinDefaults` wipes `-RCSpendFolder`. (P-5, P-7; orig §5 P4)

## What it built — where it lives now

- The table: `agent/prices/anthropic.json`, `agent/prices/update.py` (199), `agent/prices/cases.json`, `agent/prices/reduce_cases.json`; `make prices`.
- The helper: `agent/src/pricing.ts` (196) with `pricing.test.ts`, `agent/src/priceTable.ts` (247) with `priceTable.test.ts`; the `prices` and `cost` events in `protocol.ts` and `main.ts`.
- The app: `AssistantSpend.swift` (291: the spend folder, `configureFields`, the ledger line and `record`, `toolView`, `AssistantTurnCost` and its line and `figure`), `AssistantSpendMonth.swift` (145: the UTC month, the fold, the sentences), `AssistantTranscript.swift` (the turn's and the conversation's sums), `AssistantContextMeter.swift` (`AssistantConversationCostView`), `AssistantSettingsPane.swift` (the month line); one line each in `AssistantSession.swift` and `EditorViewController+Assistant.swift`.
- The proofs' side: `tools/proof/prices.py` (190), `budget.py` (404), `cloud_live_ledger.py` (428), the relay in `assistant_prompt_eval.py`.
- Proof: `prices_proof.py` (C, K, T, A, R; in `make test`), `prices_crosscheck.py` (X0–X2, network), `spend_proof.py` + `spend_probe.swift` (H1–H9, L0–L2, S1–S5), `budget_proof.py` (in `make test`), `spend_ui_proof.py` + `spend_ui_probe.swift` (M1–M3, C1–C3, U0–U3), each with its mutants. `tools/proof/README.md` has each one's launch line.

## Known limits

- **Every priced response has been the stand-in's**: no response from api.anthropic.com has been priced or recorded; AS-4 and AS-5 in `docs/manual-checks.md` hold the figures against the Anthropic Console with a real key.
- **A response cut short by Stop or an error has no final usage and is not priced** (#162).
- **The month is UTC's**, so near a month's turn Settings' figure differs from the person's local calendar month by up to a day (P-7's accepted risk).
- **Fast, priority/batch and US-only usage is `unknown` in the app** and counted at the dearest standard rates by the proofs (P-2, P-6).

## Open items

- #147 Rasterize takes road map 12 §2's change and this road map's `pricing.ts` / `priceTable.ts`.
- #157 the assistant's live evaluation with a key (`ready-for-human`).
- #162 a response cut short by Stop or an error is not priced.
- #164 reconcile the app's ledger with Anthropic's Admin usage-and-cost API.

## Where to look in the original

- orig §1: the sources checked (genai-prices, LiteLLM, the npm repackagings, the page, the Admin API, AssemblyAI), and the `iterations` correction.
- orig §2: the design as approved; §3 P-1..P-4 as first written; §4 the four phases as planned.
- orig §5 P1: the table's shape, the price function's semantics in order, the hand-checked cases and the mutants.
- orig §5 P2: the helper's refresh and cache, the `prices` / `cost` events, the app's ledger and turn line, H1–H9 / L0–L2 / S1–S5, and the review's five nits.
- orig §5 P3: `budget.py`, the relay's reservation order, the live AssemblyAI ledger, the headroom arithmetic and the review's three nits.
- orig §5 P4: the two figures, the harness and launcher changes that keep Settings off the person's ledger, M1–M3 / C1–C3 / U0–U3 and the mutants.
