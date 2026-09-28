# Spec §11 — decisions: Pricing and spend (road map 13)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is in progress: `designs/reelcut-roadmap-13.md`, whose §3 words
them and whose §1 holds what was measured.

- **P-1 — Prices come from LiteLLM's table.** A committed snapshot
  (`agent/prices/anthropic.json`) is refreshed daily at runtime and by `make prices`. Never
  hand-kept, except AssemblyAI's Universal-3.5 Pro rate, which no online source carries
  (`AssemblyAIRates`). Anthropic's page is the cross-check. `@pydantic/genai-prices` was rejected
  because it lacks the models Reelcut uses (road map 13 §1); the npm repackagings of LiteLLM add a
  lag and a dependency for four multiplications. Risk accepted: LiteLLM is a community table, and
  a wrong row is caught only by the cross-check, which compares the models Reelcut uses.
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
- **P-4 — Spend shown in the app is Reelcut's own**, from its ledger, and says so. The Anthropic
  Console is the truth for the account.
- **P-5 — The spend ledger and the price cache are the person's, and a proof never touches them.**
  Both live in the spend folder, `~/Library/Application Support/Reelcut/` (`spend.jsonl`, one JSON
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
- **P-6 — The proofs' ledger is `~/Library/Application Support/Reelcut Proofs/spend.jsonl`, and
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
  repairs it; the road map 6 and 8 spikes (`cloud_spike/`, `words_spike/`) keep their own ledgers
  and are not held to it (#163).
