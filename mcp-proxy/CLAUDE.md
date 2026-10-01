# mcp-proxy/CLAUDE.md — the stdio MCP proxy's rules

Applies to everything under `mcp-proxy/`, the crate that builds
`reelcut-mcp`: the stdio MCP server bundled as
`Reelcut.app/Contents/Helpers/reelcut-mcp`, which external MCP clients start
(road map 14's MC3, spec §11 MC-3, MC-4, MC-6; the record is
`designs/reelcut-roadmap-14.md`). Build commands are the root `CLAUDE.md`'s:
`make test` and `make lint` run this crate after the core and the graphics
engine; `project.yml`'s "Build MCP Proxy" phase builds it, copies the binary
into `Contents/Helpers/` and signs it `--options runtime` with no
entitlements, as `agent/build.sh helper` signs the assistant's helper.

## Module map

- `lib.rs` — `#![forbid(unsafe_code)]`, the module declarations, and `run()`:
  the stdin loop (one `Session`, one `Output`; each line to
  `session::dispatch`; stdin's end exits at once without waiting for a call
  in flight). It also includes `core/src/mcp_versions.rs` by `#[path]` as
  `mcp_versions`, so the proxy and the app negotiate from ONE list.
- `main.rs` — `fn main() { reelcut_mcp::run() }` and nothing else.
- `session.rs` — `dispatch` (a blank line skipped; unparsable `-32700` and a
  batch `-32600`, both with a null id; a notification or a response dropped
  and never forwarded; every request on its own thread), `Output` (stdout
  behind one `Mutex`: one message, one line, flushed) and `Session` (one
  `Mutex` over the tools last given, `check_due` and `stranded`). What is
  answered where: `initialize` and `ping` here, never touching the socket;
  `tools/list` from the app within `LIST_READ_TIMEOUT`, else the snapshot,
  and it never launches (MC-4); `tools/call` launches its own bundle on
  `Absent`; anything else forwarded when the app answers, else `-32601`. A
  proxy-side failure of a call is a CallToolResult with `isError: true`.
  The `list_changed` check compares `serde_json::Value`s, never bytes (MC1's
  B9). A launch that timed out STRANDS the session: its later `Absent` calls
  answer the stranded sentence and launch nothing. The `stranded` check and
  the launch are one critical section per session (`Session.launching`), so
  concurrent calls that found no socket launch at most once between them.
- `socket.rs` — `socket_path` (`RC_AGENT_SOCKET` when not empty, else
  `$HOME/Library/Application Support/Reelcut/Agent/agent.sock`), `is_scratch`,
  `reach` (`Answers`; `Absent` for `NotFound` or `ConnectionRefused`;
  `Unreachable` otherwise), and `post`: one `POST /mcp HTTP/1.1` with
  `Connection: close`, its body read by `Content-Length` or CHUNKED —
  `tiny_http` 0.12 chunks any body of 32 768 bytes or more, and a
  `tools/list` is about 240 KB.
- `launch.rs` — `ensure_running`: the socket's folder made if missing
  (`0700`), `agent.launch.lock` beside the socket taken with `File::lock`,
  the re-check, `/usr/bin/open` with `open_arguments` (pure: `-n -g`, and for
  a scratch socket `--env RC_AGENT_SOCKET=…`, `--stderr <folder>/reelcut-launch.log`
  and `--args -ApplePersistenceIgnoreState YES`), and the 50 ms poll until the
  socket answers or `launch_wait()` (`RC_MCP_LAUNCH_WAIT`, else 60 s) runs out
  with `timeout_sentence`.
- `bundle.rs` — `own_bundle` (the canonicalised executable must be
  `<X>.app/Contents/Helpers/<name>`) and `read_snapshot`
  (`Contents/Resources/agent-catalog.json`, `{version: string, tools:
  array}`), which the build's "Write Agent Catalog" phase writes
  (`app/Sources/AgentCatalogSnapshot.swift`).

## Rules

- **stdout is protocol only.** Every other word goes to stderr, each line
  starting `reelcut-mcp: `; never `Reelcut: `, which is the app's parity
  check's prefix and which every proof reads as a complaint.
- **`initialize`, `ping` and `tools/list` never launch Reelcut** (MC-4);
  `mcp_proxy_proof.py`'s X1 and its `launch-on-list` mutant hold it.
- **The launch lock is held until the poll ends.** Released before it, a
  second proxy's re-check would find nothing answering yet and launch a
  second instance; X4 and the `no-lock` mutant hold it. The lock statement
  and `tools_list`'s `let answers = …` line are each ONE anchor a mutant
  replaces: keep each exactly once in `src/`.
- **No read timeout on a forwarded call**: an `export` may take minutes.
  Only the session's `tools/list` passes `LIST_READ_TIMEOUT`, because the app
  serves one request at a time and another client's long call would hold it.
- **A proxy launches only its OWN bundle**, so a copy of Reelcut launches
  itself; outside a bundle a call answers the sentence naming the executable.
- `#![forbid(unsafe_code)]` stays in `lib.rs` and `main.rs`; every `src/`
  file stays under 400 lines.
- Tests are black-box in `tests/stdio.rs`, through the built binary copied
  into a fake bundle with a snapshot and a scratch `RC_AGENT_SOCKET`; a stub
  is `tiny_http`'s `Server::http_unix`. **Only a `Fixture::launchable` fake
  bundle may reach `ensure_running`**: its executable is a script that
  records its launch and exits without binding, so `/usr/bin/open` starts
  nothing that lasts, and its `Drop` runs `lsregister -u` on the fake bundle
  before removing it, because `open` registered it with LaunchServices. Any other `tools/call` from a fake bundle is made only
  while a stub answers. Every stdout line of every proxy must parse as
  JSON-RPC 2.0. The launch of the real app is proved against the built app
  by `tools/proof/mcp_proxy_proof.py`, never here.

## Dependencies, and why each

- `serde_json` 1 (no features): the JSON-RPC. Its `Map` sorts keys, which is
  harmless: every comparison is of values, and a forwarded answer is
  re-serialised as one line.
- Dev: `tiny_http` 0.12, the app's own transport (`core/src/agent.rs`), for
  the tests' stub servers, so a stub chunks exactly as the app does.
- `std` for everything else: the socket, the lock (`File::lock`, Rust 1.89),
  `open`, the threads. No async runtime.
