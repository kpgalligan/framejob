# The MC1 spike — road map 14 (2026-10-01)

Four questions `designs/reelcut-roadmap-14.md` asks before MC2 (the socket) and
MC3 (`reelcut-mcp`) are built, and the instrument that measures them. **The
answers are not here**: they are in that document's "MC1 — spike" record,
which also lists what they changed in MC2's and MC3's text and in spec §11.
What is here is how to run it again.

- **q1 — the snapshot.** Can an Xcode script phase run the just-linked binary
  with `-RCWriteCatalog <path>` and put `Contents/Resources/agent-catalog.json`
  (`{version, tools}`) in the bundle before it is signed, in Release and
  Distribution, and what does it add to `make app`? And the fallback's cost:
  the built binary run with the same argument at runtime. Xcode links with
  `-Xlinker -no_adhoc_codesign`, so the just-linked binary is unsigned and
  arm64 kills it at exec (exit 137); the phase therefore ad-hoc signs the
  executable alone, in place (`codesign -s - -f`), before running it, and
  B12 checks that Xcode's CodeSign step still gives the product its own
  signature.
- **q2 — the launch.** From `open -n -g <bundle>` to the server answering
  `initialize`: cold, warm and on a quarantined copy; whether the frontmost
  app changes; which Reelcut windows are on screen. TCP stands in for the
  socket (MC2 is not built; both start in `applicationDidFinishLaunching`).
- **q3 — the client.** Whether Claude Code refetches on
  `notifications/tools/list_changed`, answered from its own MCP docs page
  (quoted), plus a stdio stub server (`stub_mcp.py`) that sends the
  notification, driven by the runner itself. **No model call**: what only a
  running client can confirm is `docs/manual-checks.md` AC-1 (Claude Code)
  and AC-2 (Claude Desktop), whose fixture is the stub.
- **q4 — the socket.** The socket path's length against macOS's 104-byte
  `sun_path`, and what `tiny_http` 0.12's `Server::http_unix` does with an
  existing file at the path, a killed server's file, a regular file, a file
  replaced under a live server, a POST, `server_addr().to_ip()` and
  `unblock()`; and the mode of the person's support folder (read only).

```sh
python3 tools/proof/mc1_spike/mc1_spike.py                 # q4, q1, q2, q3, then Z1
python3 tools/proof/mc1_spike/mc1_spike.py --only q4       # a subset; the other rows carry forward
python3 tools/proof/mc1_spike/mc1_spike.py --only q1,q2    # the builds and the launches
```

Needs `cargo` (and tiny_http 0.12.0 and serde_json in the cargo cache: the
crate builds `--offline`), `swiftc`, `xcodegen`, `bun`, `xcodebuild`, a built
core (`core/target/release/libreelcut_core.a`), and for D1 the network. q1
builds the app twice in Release and once in Distribution in
`work/mc1_spike/tree` (a `tree_copy.py` copy, which alone gets
`CatalogWriterHook.swift`, the `mc1WriteCatalogIfAsked()` line in
`main.swift` and the `MC1 Spike Write Agent Catalog` phase in `project.yml`);
q2 needs q1's Release product and launches about nine instances of it, each
by `open -n -g` from a path under `work/mc1_spike/`, each stopped by SIGTERM
(SIGKILL after 10 s), and only a pid whose command line holds
`tools/proof/work/mc1_spike/` is ever signalled. A full run takes a few
minutes plus the builds.

Rules it keeps: every child runs in its own process group under a wall-clock
bound (`graphics_spike/bounded.py`; the stub's interactive session has its own
bound and `killpg`), without `ANTHROPIC_API_KEY`, `CLAUDECODE` or
`CLAUDE_CODE_ENTRYPOINT`; no `claude -p`, no `claude mcp`, no API request;
nothing is created under `~/Library/Application Support/Reelcut/`, and
nothing is registered in a Claude Code or Claude Desktop configuration.

It writes `work/mc1_spike/answers.json` (`{date, run, carried, rows: {<id>:
{status, value, detail}}}`), prints one line per row and a digest, and exits
0 when no row is `error`. A status is `answered` (a measurement), `pass` or
`fail` (a check), `skip` (naming its host condition, `host: …`) or `error`
(the instrument could not run).

## The instruments

| File | What it is |
|---|---|
| `mc1_spike.py` | the runner: the rows, `--only`, carry-forward, `answers.json`, the digest, the exit |
| `CatalogWriterHook.swift` | `mc1WriteCatalogIfAsked()`: with `-RCWriteCatalog <path>`, writes `{"version":<CFBundleShortVersionString>,"tools":<AgentServer.shared.preparedCatalog>}` and `exit(0)`; nil catalog or a failed write, one stderr line and `exit(1)`. Copied into the tree copy only |
| `windows_probe.swift` | `windows_probe <pid>`: one JSON line, `on_console`, `locked`, `front_pid` and the pid's windows' layer, on-screen flag and bounds (no titles, so no Screen Recording grant); compiled into `work/mc1_spike/` |
| `stub_mcp.py` | the stdio MCP stub: `--mode during-call\|unprompted\|silent --log <jsonl>`; tools v1 `[probe_wait]`, v2 `[probe_wait, probe_new]`; logs every inbound message (and each notification it sends) with a monotonic stamp |
| `socket_probe/` | the scratch crate (own `[workspace]`, `tiny_http` 0.12.0, `serde_json`): `socket_probe <scratch-dir>` prints S2–S10 as one JSON object; `socket_probe --hold <path>` binds and blocks (S5's fixture) |

## The rows

| ID | Question | What it measures | Kind |
|---|---|---|---|
| S1 | q4 | byte lengths: the product path on this host, the longest `/Users/<name>` that fits 103 bytes, `$TMPDIR` + `reelcut-XXXXXXXX/agent.sock`, `<worktree>/tools/proof/work/<12 chars>/agent.sock` | answered |
| S2 | q4 | bind at 103-, 104- and 105-byte paths: result and error | answered |
| S3 | q4 | a fresh bind; the socket file's mode under the umask | answered |
| S4 | q4 | bind over a live server's path | answered |
| S5 | q4 | bind over a `--hold` child killed with SIGKILL; `connect` to the left file | answered |
| S6 | q4 | bind over a regular file; the file left intact | answered |
| S7 | q4 | A bound, its path unlinked, B bound there, A dropped: B's file and reach | answered |
| S8 | q4 | an HTTP/1.1 POST over the socket is answered | pass/fail |
| S9 | q4 | `server_addr().to_ip()` for a unix listener | answered |
| S10 | q4 | `unblock()` then join returns | pass/fail |
| S11 | q4 | mode and owner of `~/Library/Application Support/Reelcut/`, whether `Agent/` exists (read only) | answered |
| B1 | q1 | each anchor (`main.swift`, `project.yml`) found exactly once | pass/fail |
| B2–B4 | q1 | full `make app`, incremental `make app`, the Distribution `xcodebuild`: success, wall s, the phase's ms and its ad-hoc sign's ms | pass/fail |
| B5 | q1 | each bundle's snapshot parses as `{version, tools}` at the bundle's version | pass/fail |
| B6 | q1 | Release's snapshot names all six `devHandlers` keys, Distribution's none | pass/fail |
| B7 | q1 | `codesign --verify --strict --deep` on both bundles | pass/fail |
| B7c | q1 | CONTROL: one byte of a copied bundle's snapshot changed fails it | pass/fail |
| B8 | q1 | `dist_check.py` on the copy's two bundles | pass/fail |
| B9 | q1 | the Release snapshot's `tools` against a live `tools/list` (q2's first warm instance), as JSON and compactly re-serialised | pass/fail |
| B10 | q1 | the fallback: the binary with `-RCWriteCatalog` on a fresh copy and three warm runs; exit 0, equal to the build's | pass/fail |
| B11 | q1 | no `Reelcut: ` line in any phase's writer output | pass/fail |
| B12 | q1 | each product's final signature is Xcode's, not the phase's: another CDHash than the phase printed, Info.plist bound, resources sealed, `runtime` in the flags | pass/fail |
| H0 | q2 | console state | answered |
| L0 | q2 | CONTROL: polling a port nothing listens on expires at 2 s | pass/fail |
| L1 | q2 | cold launch ×3, each a fresh `ditto` copy at a new path (no `purge`: it needs root) | answered |
| L2 | q2 | warm launch ×3 on one copy, after an unscored priming launch | answered |
| L3 | q2 | a quarantined copy: `spctl` verdict, a process, an answer within 60 s, CoreServicesUIAgent's on-screen windows | answered |
| L4 | q2 | the frontmost app's pid unchanged at the answer and at +2 s | pass/fail |
| L5 | q2 | Reelcut's on-screen windows at the answer and at +2 s | answered |
| L6 | q2 | no `Reelcut: ` line in any launch's log | pass/fail |
| L7 | q2 | 3 × max(L1) ≤ 60 s | pass/fail |
| C1 | q3 | `claude --version` (skip `host: claude not on PATH`) | answered |
| D1 | q3 | the sentences of `https://code.claude.com/docs/en/mcp` naming `list_changed` (skip `host: no network`) | answered/fail |
| T1 | q3 | stub `during-call`: `listChanged`, `[probe_wait]`, the notification before the call's answer, both tools after, every inbound message logged | pass/fail |
| T2 | q3 | stub `unprompted`: the notification 2 ± 0.5 s after the first `tools/list` answer | pass/fail |
| T3 | q3 | CONTROL: stub `silent`: no notification within 8 s | pass/fail |
| Z1 | — | `pgrep -f tools/proof/work/mc1_spike` prints nothing | pass/fail |

q3 also writes `work/mc1_spike/q3/ac-mcp.json`, the scratch MCP
configuration AC-1 passes to `claude --mcp-config … --strict-mcp-config`;
the stub it names logs to `work/mc1_spike/q3/ac-stub.jsonl`.
