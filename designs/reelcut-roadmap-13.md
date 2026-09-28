# Road map 13 — pricing and spend

**Status: IN PROGRESS. Proposed and approved 2026-09-28; P1 (the table and the price function) built
2026-09-28, uncommitted, record in §5. P2–P4 not started.**

The user asked three things: to set a spend budget, to price each call the assistant and the proofs
make, and eventually to show spend in the UI. The rules they gave:

- no hand-kept price data, except where no reliable online source exists;
- a library is welcome if it is reliable;
- budgets are $25 a month for Anthropic and $5 a month for AssemblyAI.

§1 is what was measured, §2 the design, §3 the decisions §11 records first, and §4 the phases.

## 1. What was measured (2026-09-28)

**How a call is priced.** Every Messages API response reports `usage`:

- `input_tokens` (uncached input),
- `cache_creation_input_tokens`, with a 5-minute / 1-hour split under `usage.cache_creation`,
- `cache_read_input_tokens`,
- `output_tokens` (thinking counts as output).

The response's `model` field is the model that returned the message, and a refusal fallback
(`fallbacks: "default"`) can change it. Cost is each class times that model's rate for the class.

**Correction (P1, 2026-09-28): the top-level counts are not the whole bill.** They describe only the
attempt that returned the message. When `usage.iterations` is present, it lists every billed attempt,
each with its own counts and (where it differs) its own `model`: a refused attempt before a fallback,
and a compaction pass (refusals-and-fallback.md, "Billing and rate limits"; the SDK's
`BetaUsage.iterations` doc). So a call is priced per `iterations` entry when there are any, each at
its own model, and from the top-level counts only when there are none (spec §11 P-2).

The rates are per model and cannot be derived by a rule of thumb. Anthropic's pricing page
(`https://platform.claude.com/docs/en/about-claude/pricing`, also served as `…/pricing.md`) says a
cache hit is 0.1× input on most models, 0.05× on Claude Opus 5.5 and 0.025× on Claude Fable 5.1.

**Sources checked:**

| Source | Result |
|---|---|
| `@pydantic/genai-prices` (npm, TypeScript) | `claude-opus-5-5` and `claude-fable-5-1` are ABSENT from its `prices/data_slim.json`. Its own issue #703 records `claude-sonnet-5` still carrying a cancelled 2026-09-01 increase. Rejected. |
| LiteLLM's `model_prices_and_context_window.json` (`https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`) | 4,395 entries; three commits to the file on 2026-09-28 alone. `claude-opus-5-5`: input 4.00, cache write 5.00 (5 min) / 8.00 (above 1 h), cache read 0.20, output 20.00 $/MTok, which equals Anthropic's pricing page row for Claude Opus 5.5 exactly. `claude-fable-5-1`: cache read 0.25, matching the page's 0.025×. **Chosen as the feed.** |
| `llm-prices`, `token-costs` (npm) | Repackagings of LiteLLM's data on a weekly or daily lag. No reason to add the lag or the dependency: the arithmetic is four multiplications. |
| Anthropic's pricing page | Official, but a document rather than an API. Used as a cross-check, never as the feed. |
| Anthropic's Admin usage-and-cost API | Billed truth after the fact; needs an admin key. Out of scope (reconciliation, later). |
| AssemblyAI in LiteLLM | Only `assemblyai/best` ($0.12/h) and `assemblyai/nano`. Universal-3.5 Pro, which Reelcut uses, is ABSENT. The app's `AssemblyAIRates` (hand-kept, $0.21/h plus $0.02/h for speakers, dated 2026-09-17, road map 6) stays the only source. It is the one exception to "no hand-kept prices", and the reason is recorded. |

## 2. The design

- **One price table, two readers.**
  - A committed snapshot, `agent/prices/anthropic.json`, holds LiteLLM's Anthropic rows, reduced to the
    fields pricing needs. It also records the LiteLLM commit or date it came from.
  - `make prices` regenerates it from the network. This is the only step that writes the committed file.
  - Two readers use the same table: the helper (TypeScript), and the proofs' ledger and budget guard
    (Python).
- **Pricing lives in the helper** (`agent/src/`, one diff with Rasterize per road map 12 §2; #147
  carries it). The helper already sees every response's `usage` and `model`. A pure
  `price(usage, model, table)` answers dollars or `unknown`, and the helper sends the cost with each
  message's event. Swift only records and displays. There is no pricing code in Swift or Rust.
- **Freshness at runtime.** The helper refreshes the table from LiteLLM at most once a day. The cache
  path is handed to it in `configure`; the app passes a file under Application Support. The helper
  falls back to the cached copy, then to the bundled snapshot. The source actually used (bundled,
  cached with its date, or fetched) is reported, so a stale table is visible, never silent.
- **Unknown is never zero.** A model absent from the table prices as `unknown`. The transcript says so.
  The budget guard counts it at the worst case (the dearest Anthropic row in the table), so spend is
  never under-counted.
- **Ledgers.**
  - The app appends one line per priced response to `~/Library/Application Support/Reelcut/spend.jsonl`:
    time, model, the usage classes and dollars. It never records a key, a header or content.
  - The proofs keep their own persistent ledger, one that survives `rm -rf tools/proof/work`.
  - Both are JSON lines, so a month-to-date total is a fold.
- **Budgets for proofs** ($25/month Anthropic, $5/month AssemblyAI).
  - Before each request, the relay (and the AssemblyAI live proof) refuses when this month's recorded
    spend plus the request's worst case would pass the month's budget.
  - A refused row fails as `budget:`, distinct from a model failure and from the per-run `cap:`.
  - The budgets are the owner's numbers, committed; an agent never raises them.
- **Cross-check.** A network proof row compares the table's rows for the models Reelcut uses against
  Anthropic's `pricing.md`. It runs with the proofs, not in `make test`, and reports a mismatch by name.
- **The UI (a later phase).** Per-conversation cost in the Assistant tab, and month-to-date in
  Settings ▸ Assistant, from the app's ledger. It is labelled as Reelcut's own spend: the Anthropic
  Console is the truth for the account.

## 3. Decisions §11 records before the code

- **P-1 — Prices come from LiteLLM's table.** A committed snapshot is refreshed daily at runtime and by
  `make prices`. Never hand-kept, except AssemblyAI's Universal-3.5 Pro rate, which no online source
  carries (`AssemblyAIRates`). Anthropic's page is the cross-check.
- **P-2 — A call is priced from the response's own `usage` and `model`**, per token class, at that
  model's rates, in the helper — per `usage.iterations` entry when present, each at its own model,
  because the top-level counts describe only the attempt that returned the message and exclude
  compaction (§1's correction). Unknown models price as `unknown`, never $0; so does usage the table
  cannot price (fast, priority/batch, US-only, a malformed count, a class whose rate the row lacks).
  Risk accepted: a declined attempt in an unbilled refusal category is priced (an over-count). The
  binding wording is `designs/spec/11-decisions/pricing.md`.
- **P-3 — Budgets are dollars per calendar month per service** ($25 Anthropic, $5 AssemblyAI). They
  are enforced by the proofs before each request, at the worst case. Tokens are recorded for
  diagnosis and are never the budget.
- **P-4 — Spend shown in the app is Reelcut's own**, from its ledger, and says so.

## 4. Phases

Each phase follows the root `CLAUDE.md` recipe and is built with /litecode.

- **P1 — The table and the price function.**
  - `agent/prices/anthropic.json` and `make prices`.
  - `price()` in `agent/src/`, pure, with a test run from `make test`.
  - A Python reader for the proofs. It shares the table and never re-derives rates.
  - The cross-check row, and the §11 decisions P-1..P-4.
- **P2 — The helper prices every response.**
  - The runtime refresh and cache, with the cache path passed in `configure`.
  - The cost and the table's source carried on the helper's events.
  - The app's `spend.jsonl`, and the transcript line showing a turn's cost.
- **P3 — The proofs' ledger and the monthly budgets.** The relay and the AssemblyAI live proof both
  price through the table (or `AssemblyAIRates`), keep the persistent ledger, and guard at $25 and $5.
- **P4 — Spend in the UI** (later, when the user asks): per-conversation and month-to-date.

## 5. Records

### P1 — the table and the price function (built 2026-09-28, uncommitted)

**What landed.**

- Spec §11 P-1..P-4 in `designs/spec/11-decisions/pricing.md` (written before any code), indexed in
  `11-decisions/README.md`. P-2 carries §1's correction: per `usage.iterations` entry, each at its own
  model.
- `agent/prices/anthropic.json`: LiteLLM's 20 `litellm_provider: "anthropic"` rows at commit
  `b79fc9f1b0249cb533391dd7c941082f0cd6ddb1` (committed 2026-09-28T06:07:45Z), in **USD per million
  tokens** (`round(per_token × 1e6, 6)`): input, output, cache_read, cache_write_5m, cache_write_1h, and
  an `above_200k` tier where LiteLLM has one (the two `claude-sonnet-4-5` rows). A field LiteLLM lacks
  is absent, never 0; batch and search fields are dropped. Written only by `make prices`
  (`agent/prices/update.py`, stdlib only; temp file then `os.replace`; any failure `error: …`, exit 1,
  the file untouched). `make prices` is a prerequisite of nothing.
- `agent/src/pricing.ts`: pure `matchModel()` and `price()`; nothing imports it yet (P2 does).
  `agent/src/pricing.test.ts` (`bun test`) runs every case in `agent/prices/cases.json` and checks the
  committed table's shape. `agent/build.sh test` runs it with a JUnit report in
  `build/agent/bun-test.xml`.
- `tools/proof/prices.py`: the same function in Python for the proofs (P3), step for step.
- `tools/proof/prices_proof.py`, the new last line of `make test` (C × 23, K, T, A; no network), and
  `tools/proof/prices_crosscheck.py` (network, X0–X2), each with its made-to-fail mutants.
  `tools/proof/README.md` has both.

**The semantics** (identical in both readers, checked in this order, the first failure answering):
`usage` not an object or no model id → `unknown usage` / `model`; `speed` other than
standard, `service_tier` other than standard, `inference_geo` other than global → `unknown` with that
cause (fast, batch/priority and the 1.1× US rate are not in the table, and no multiplier is hand-kept);
`iterations` entries (a non-object element → `usage`), each at its own `model` or the response's; each
count absent/null → 0, else a non-negative integer, else `usage`; the 5m/1h split from
`cache_creation` when it is an object, else all of `cache_creation_input_tokens` at the 5-minute rate;
model by exact id, else the id less a trailing `-YYYYMMDD` (`claude-haiku-4-5-20251001` →
`claude-haiku-4-5`), nothing else (`claude-opus-5-5-fast` → `unknown model`); the `above_200k` tier
when input + cache writes + cache reads > 200 000; a class with tokens but no usable rate →
`unknown rate`, never the base rate.

**Measured 2026-09-28** (every command with `ANTHROPIC_API_KEY` and `RC_ASSEMBLYAI_KEY` unset):

- `make typecheck`: 0 errors, the 7 baseline warnings, tsc clean. `make lint` clean. `make app`:
  BUILD SUCCEEDED.
- `make test` exit 0; its last line `prices_proof.py` scored 26/26: all 23 C rows; K (20 rows, 1000
  input tokens on opus = $0.004000); T (bun test, 24 testcases, 0 failing); A (23 cases, both readers
  pass every one, `cases.json` sha256 `ce70456a63f0bf26729ee98bd670c6a2c9416b3aa8ee9ef3cba95ad57c763e1c`).
  Hand-checked answers include opus-mixed $0.3548, long-context (sonnet-4-5 above 200k) $0.9585, its
  edge at exactly 200 000 $0.6, fallback-iterations $0.01946 over [opus, fable], compaction-iteration
  $0.7814.
- Made to fail: `--mutant py-disagrees` FAILed C:opus-cache-read (0.4 for 0.2), C:opus-mixed
  (0.3848), C:fable-cache-read (0.5), C:long-context (0.9945) and A, 21/26, exit 1.
  `--mutant ts-disagrees` FAILed T (failing `case: opus-mixed`) and A (failing in bun
  `['opus-mixed']`), 24/26, exit 1.
- `make prices` rerun: `commit b79fc9f1… 2026-09-28T06:07:45Z`, `rows 20`, `unchanged`; `diff`
  against the copy taken before it was empty. The fetch control (`--api-base http://127.0.0.1:9`):
  `error: … Connection refused`, exit 1, the file's shasum `124dd0346e79852e791c3ffdd11759868fcd6804`
  before and after, no temp file left.
- `prices_crosscheck.py`: 18 page rows parsed; X1 opus and X2 fable equal on all five rates
  (opus 4 / 5 / 8 / 0.2 / 20, fable 10 / 12.5 / 20 / 0.25 / 50 for input / 5m / 1h / cache read /
  output), 3/3. `--mutant table`: X1 FAIL "claude-opus-5-5 cache_read: table 0.21, page 0.2", exit 1.
  `--mutant page`: X2 FAIL "claude-fable-5-1: the page has no 'Claude Fable 5.1' row", exit 1.
- `assistant_helper_proof.py`: P0, P1, P2r, P3, P4, P5 ok, 6/6 (P2d skipped, no `--dist`), so
  `build.sh`'s single guard `exit 1` and the Makefile's one `unexport ANTHROPIC_API_KEY` survived.

**Owed.** Rasterize does not carry `agent/src/pricing.ts` or `pricing.test.ts` (nor the
`agent/prices/` files the test reads) until #147 lands (commented there). No residue issue was filed:
every row above passed and every control failed as stated. P2–P4 as §4 plans them.
