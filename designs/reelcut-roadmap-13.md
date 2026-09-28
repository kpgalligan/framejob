# Road map 13 — pricing and spend

**Status: IN PROGRESS. Proposed and approved 2026-09-28; P1 (the table and the price function) built
2026-09-28 and committed 79a8b56; P2 (the helper prices every response) built 2026-09-28,
uncommitted. Records in §5. P3–P4 not started.**

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

### P1 — the table and the price function (built 2026-09-28, committed 79a8b56)

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

### P2 — the helper prices every response (built 2026-09-28, uncommitted)

**What landed.**

- Spec §11 **P-5** in `designs/spec/11-decisions/pricing.md` (written before any code), indexed in
  `11-decisions/README.md`: the spend ledger and the price cache are the person's, in the spend
  folder (`~/Library/Application Support/Reelcut/`, or `-RCSpendFolder`); none with
  `RC_ASSISTANT_BASE_URL` set and no `-RCSpendFolder`; with the override the cache is passed only
  beside `-RCPriceFeed`; a feed must be https or loopback http; a turn is priced at the prices in
  force at its `turn_started`.
- The helper (`agent/src/`): `priceTable.ts` — the bundled table (a JSON import, `tsconfig`'s
  `resolveJsonModule`), `parseTable`, `reduceLiteLLM` (`update.py`'s `reduce_table` step for step,
  with the feed and `fetched_at` in place of a commit), `feedProblem`, `initialPrices` (a synchronous
  cache read; a refresh is due when the cache is absent, unreadable, invalid, 24 h old or more, in
  the future or unparseable) and `refreshPrices` (never rejects; on success the cache is written
  `mkdir -p`, `<cache>.tmp-<pid>`, `rename`, as its last step; on failure `current` is kept with the
  problem and nothing is written). `protocol.ts` — `PriceSource`, `price_cache` / `price_feed`, the
  `prices` and `cost` events. `main.ts` — `configure` sets up the prices (`prices` before `ready`
  when no refresh is due, else in the refresh's own continuation, which also puts it in force);
  `runTurn` takes the prices once beside `turn_started`; `emitCost` after every `message_done` and
  before `reportCompaction`. `pricing.ts`'s `PriceTable` type: `litellm_commit` /
  `litellm_commit_date` optional, `fetched_at?`. `priceTable.test.ts` (12 `reduce:` / `refresh:`
  tests, `Bun.serve` on 127.0.0.1 only) and `agent/prices/reduce_cases.json`.
- The app: `AssistantSpend.swift` (269 lines) — `folder()`, `configureFields()`, `ledgerLine` (the
  listed keys only, `usage` whitelisted), `record` (creates the folder, `O_APPEND|O_CREAT` 0600, one
  `write`), `toolView` and `AssistantTurnCost` (the sum, `amount`, `day` in the local zone, the
  line). `AssistantSession.swift` line 134 merges `configureFields()` (still 400 lines).
  `EditorViewController+Assistant.swift`: `session.onEvent =` stays one line, now
  `assistantEventHandler(spendFolder: AssistantSpend.folder())`, which feeds the transcript and
  records each `cost`, a ledger failure being at most one note per session. `AssistantTranscript`
  sums the turn's `cost`s and appends the line as `.meta` on `turn_finished`; `clear()` and
  `endConversation` reset it. `AgentServer+Assistant.swift` and `DevAssistantLaunch.swift` map their
  `events` through `AssistantSpend.toolView` (no line added).
- Proofs: `prices_proof.py` row R (and `--mutant reduce-disagrees`); `spend_proof.py` (H1–H9, L0–L2,
  S1–S5) with `spend_probe.swift`; `assistant_tab_proof.py`'s L2 now expects the exact bundled cost
  line. Docs: spec §7.9's session paragraph, `docs/manual-checks.md` AS-4, `app/CLAUDE.md`, the root
  `CLAUDE.md`, `README.md`, `tools/proof/README.md`.

**Measured 2026-09-28** (every command with `ANTHROPIC_API_KEY` and `RC_ASSEMBLYAI_KEY` unset):

- `make typecheck`: 0 errors, the 7 baseline warnings, tsc clean. `make lint` clean. `make test`
  exit 0, `prices_proof.py` 27/27 (bun test 36 testcases, 0 failing; R: 5 LiteLLM entries reduce
  to 4 rows). `make app`: BUILD SUCCEEDED.
- `spend_proof.py` 17/17: H1 bundled as of 2026-09-28T06:07:45Z with "no price cache is
  configured", 2 POSTs and 2 costs of $0.0006; H2 one GET, the cache written, the reply $0.001
  (fetched); H3 cached before `ready`, 0 GETs; H4 cached with "fetching http://127.0.0.1:…: Unable
  to connect…", the cache unchanged; H5 "… was rejected: no claude-fable-5-1 row", no cache; H6
  "the price feed http://example.invalid/ is neither https nor a loopback http URL"; H7 2 POSTs, 2
  costs, order `message_done, cost, cost, compaction_failed`; H8 unknown, cause `model`; H9 the
  first turn's two costs bundled with the GET held and released between them, the next turn's
  fetched at $0.001; L1 3 ledger lines for 3 costs, no stranger key, no text, the last entry
  `Cost: $0.0020 · Reelcut's estimate at LiteLLM prices (fetched 2026-09-28)`; L2 bundled with the
  problem, 0 feed GETs, the person's two files absent before and after; S1–S5 ok.
- Made to fail: `prices_proof.py --mutant reduce-disagrees` R FAIL, 26/27, exit 1; `spend_proof.py
  --mutant stale-refresh` H3 FAIL (no `prices` before `ready`, 1 GET), 1/2, exit 1;
  `--mutant unknown-as-zero` S1 FAIL (`Cost: $0.0000 · …` for an unknown), 4/5, exit 1.
- `assistant_tab_proof.py` 16/16 (L2 ends with `Cost: $0.0012 · … (bundled table of 2026-09-28;
  not refreshed: no price cache is configured)`); `assistant_helper_proof.py` 6/6;
  `assistant_session_proof.py` 11/11. No launch log held a `Reelcut: ` line.

**The review's five nits, fixed (2026-09-28, at the owner's ask).** Two change wording P2's spec
prescribed. (1) A turn with an unknown response whose priced part rounds to $0 no longer reads
`unknown (…) · at least $0.0000`; it reads `unknown (…) · the priced part under $0.0001`
(`AssistantTurnCost.pricedPart`); a larger priced part still reads ` · at least $%.4f`. (2) A
`fetched` table whose cache write failed no longer reads `fetched <day>; not refreshed: the price
cache could not be written: …`, which contradicted itself; for `fetched` the problem follows a bare
`; `, and `bundled` / `cached` keep `; not refreshed: <problem>`. `spend_probe.swift`'s S1 gained a
check for each. (3) `priceTable.test.ts`'s "a fresh cache is in force with no GET" never called
`refreshPrices`, so its GET count was vacuous; it is now "a fresh cache is in force and no refresh
is due", with no feed served (spend_proof's H3 carries the no-GET claim). (4) `prices_proof.py`
imports `update` inside R's `try`, so an unimportable `update.py` scores R FAIL instead of killing
the proof. (5) `AssistantSpend.swift`'s doc comment now says the spend folder is created by
`record` or by the helper's cache write, whichever comes first. Re-run after the fixes: typecheck
0 errors and the 7 baseline warnings, tsc clean; lint clean; `make test` exit 0, prices_proof 27/27
(bun test 36 testcases); `make app` BUILD SUCCEEDED; `--mutant reduce-disagrees` R FAIL, 26/27,
exit 1; spend_proof 17/17, `--mutant stale-refresh` H3 FAIL exit 1, `--mutant unknown-as-zero` S1
FAIL exit 1; tab 16/16, helper 6/6, session 11/11; no `Reelcut: ` line.

**Owed.** A response cut short by Stop or an error has no final usage and is not priced (#162).
Rasterize carries none of P2's `agent/src` change until #147 lands (commented there). AS-4 in
`docs/manual-checks.md` (a real key: bundled, then fetched, then cached; the ledger against the
Console) is the owner's. P3–P4 as §4 plans them.
