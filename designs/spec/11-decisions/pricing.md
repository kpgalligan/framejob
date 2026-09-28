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
