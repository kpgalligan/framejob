# Spec §11 — decisions: Pricing and spend (road map 13)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed: its condensed record is `designs/adr/roadmap-13-pricing.md`,
and the original, `archive/roadmap-13.md`, words them in §3 and holds what was measured in §1
and §5.

- **P-1 — Prices come from LiteLLM's table.** A committed snapshot
  (`agent/prices/anthropic.json`) is refreshed daily at runtime and by `make prices`. Never
  hand-kept, except AssemblyAI's Universal-3.5 Pro rate, which no online source carries
  (`AssemblyAIRates`). Anthropic's page is the cross-check. `@pydantic/genai-prices` was rejected
  because it lacks the models Frame Job uses (road map 13 §1); the npm repackagings of LiteLLM add a
  lag and a dependency for four multiplications. Risk accepted: LiteLLM is a community table, and
  a wrong row is caught only by the cross-check, which compares the models Frame Job uses.
- **P-2 — A call is priced from the response's own `usage` and `model`, per token class, at that
  model's rates, in the helper — per `usage.iterations` entry when present, each at its own
  model, because the top-level counts describe only the attempt that returned the message and
  exclude compaction** (refusals-and-fallback.md, "Billing and rate limits"; the SDK's
  `BetaUsage.iterations` doc). Unknown models price as `unknown`, never $0; so does usage the
  table cannot price (a fast, priority/batch or US-only request, a malformed count, a class
  whose rate the row lacks). Risk accepted: a declined
  attempt in an unbilled refusal category is priced (an over-count); fast, priority/batch and
  US-only answer `unknown`.
- **P-3 — Budgets are dollars per calendar month per service** ($25 Anthropic, $5 AssemblyAI).
  They are enforced by the proofs before each request, at the worst case. Tokens are recorded for
  diagnosis and are never the budget. The budgets are the owner's numbers, committed; an agent
  never raises them.
- **P-4 — Spend shown in the app is Frame Job's own**, from its ledger, and says so. The Anthropic
  Console is the truth for the account.
- **P-5 — The spend ledger and the price cache are the person's, and a proof never touches them.**
  Both live in the spend folder, `~/Library/Application Support/Frame Job/` (`spend.jsonl`, one JSON
  line per priced response; `anthropic-prices.json`, the helper's daily copy of LiteLLM's table).
  `-RCSpendFolder <path>` replaces the folder, read from the argument domain alone (R6-9 (c)). With
  `RC_ASSISTANT_BASE_URL` set and no `-RCSpendFolder` there is NO spend folder: no ledger line is
  written, no cache is kept, and the helper prices from its bundled table and says so. The refresh
  fetches LiteLLM's raw `main` file; `-RCPriceFeed <url>` (argument domain) replaces it, and with
  the base URL set the cache is handed to the helper only together with `-RCPriceFeed`, so a proof
  never reaches LiteLLM. The helper refuses a feed that is neither https nor http to 127.0.0.1,
  localhost or ::1. A turn is priced with the prices in force at its `turn_started`; a refresh that
  settles mid-turn applies from the next turn. Risk accepted: two sessions opened at once may both
  fetch.
  **Amended by NM-4** (rename R0): the spend folder `~/Library/Application Support/Reelcut/` is now
  `~/Library/Application Support/Frame Job/`.
- **P-6 — The proofs' ledger is `~/Library/Application Support/Frame Job Proofs/spend.jsonl`, and
  every paid proof request is held to the month's budget in it before it is sent.** It is outside
  the repo, so it survives `rm -rf tools/proof/work` and a fresh clone and is shared by every
  worktree, and outside P-5's spend folder, which is the person's. `tools/proof/budget.py` is its
  only writer: one JSON line per event (`reserve`, `settle`, `refused`; `format` 1, `at` in UTC,
  `service`, `kind`, `id`), appended in one write to a file created 0600 in a folder created 0700,
  never a key, a header, a body or a text. The month is the UTC calendar month. A month's total for
  a service is a fold: a `reserve` made in the month counts its largest `settle`, or its `worst`
  while it has none; a `settle` with no `reserve` counts its own dollars in its own month; a
  `refused` counts nothing. The read, the fold and the append happen under one exclusive `flock` on
  the file, and a request is refused (`budget: …`) when the month's total plus its worst case would
  pass P-3's budget. It fails closed: a line that does not parse, or a ledger that cannot be read or
  written, refuses every paid request until a person repairs it. The worst case is the dearest the
  request can bill: for Anthropic, the relay's measure of the body and `max_tokens` at each token
  class's dearest rate over every row and `above_200k` tier of the price table; for AssemblyAI, the
  planned seconds at `AssemblyAIRates`' two rates added (speakers included). A reply is settled at
  the table's price; usage the table cannot price (an unknown model, a mode it has no rate for)
  settles at those dearest rates, and a reply whose usage cannot be read settles at its
  reservation. Only a keyed live run writes this ledger: rehearsals and verifications use scratch
  ledgers of their own. The budgets are constants in `budget.py`, pinned by `budget_proof.py`.
  Risk accepted: fast, priority and US-only usage is counted at the dearest standard rates (the
  helper requests none of them); a torn or hand-broken line stops every paid proof until a person
  repairs it. A keyed run of either road map 6 or 8 spike (`cloud_spike/`, `words_spike/`) reserves
  here too, through `cloud_live_ledger.spike_ledger`, beside its own $2.00 ledger (#163).
  **Amended by NM-4 and NM-7** (rename R0):
  `~/Library/Application Support/Reelcut Proofs/spend.jsonl` is now
  `~/Library/Application Support/Frame Job Proofs/spend.jsonl`; while
  `~/Library/Application Support/Reelcut Proofs/` exists, `budget.py` refuses every paid request in
  a sentence naming the guarded `mv` to the new name, and it refuses before it creates or writes
  anything under `Frame Job Proofs/` (no folder, no ledger, no `refused` event), so the month's
  total is never restarted at $0 and the owner's `mv` never nests.
- **P-7 — The app shows two figures: what the current conversation has cost, on the Assistant
  tab, and what the UTC calendar month has cost, in Settings ▸ Assistant; both say they are
  Frame Job's own estimate (P-4).** The conversation figure is the transcript's sum of the `cost`
  events since its last Clear or ended conversation (a key or model change): kept in memory, it
  carries across a helper restart and is shown with no spend folder. The month figure is a fold of
  the spend folder's `spend.jsonl` over the **UTC** calendar month, because the ledger's `time` is
  UTC and P-6's budget month is UTC, so the app and the proofs count one month; its title says
  "(UTC)". The ledger is read only when Settings shows and after each line recorded while it is
  visible, and a read after a recorded line keeps the figure shown until its fold answers, so the
  window does not jump twice per response. An absent ledger answers at once on main; a present one
  is folded on one serial queue and only the latest read is shown. A line that could not be priced
  is counted and said, never added as $0 (P-2); a line that cannot be read is counted and said; a
  launch with no spend folder (P-5) says it keeps no ledger. Risk accepted: near the turn of a
  month the UTC month differs from the person's local calendar month by up to a day.
  **Amended by NM-5** (rename R0): "Reelcut's own estimate" is now "Frame Job's own estimate"
  (Settings' month note, "Frame Job's own estimate at LiteLLM prices, from its spend ledger.").
- **P-8 — A response cut short is priced once, from what its stream had reported, and marked
  partial.** The helper holds the SDK's accumulating snapshot of the response in flight
  (`message_start`'s counts and model, and each `message_delta`'s counts) until `finalMessage`
  resolves. A turn that throws — Stop, a network error, an API error mid-stream — with one held
  emits one `cost` with `partial: true`, at the turn's prices, before any `error`; a request that
  failed before `message_start` emits none. A response is never priced both complete and partial.
  The ledger line gains `"partial": true`; the turn line and the tab's Spend figure read "at
  least"; Settings' month fold sums a partial line's dollars like any priced line, unflagged.
  Where the tab's full figure does not fit its row, it reads "≥" for "at least" and "<" for
  "under", still ending "· Frame Job's estimate" (issue batch B47, #203). Before this, a response
  cut short was not priced at all (#162). Risk accepted: the figure is a lower bound — the API
  sends its one `message_delta` after the last content block, so a response cut short mid-stream
  is priced from `message_start`'s counts, its input and cache tokens, and in practice none of its
  streamed output; how the API bills an aborted stream is manual check AS-6's; the month line does
  not say that a line was partial.
  **Amended by NM-5** (rename R0): "· Reelcut's estimate" is now "· Frame Job's estimate".
