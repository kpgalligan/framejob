# Road map 14 — Reaching the agent server

**An MCP client should be able to start before Reelcut does.** Today the agent server is
streamable HTTP on `127.0.0.1:4817`, off until Tools ▸ Allow Agent Connections or
`-AgentServerEnabled YES` turns it on. A client lists tools ONCE, when it starts, so a Claude
Code or Claude Desktop session opened before Reelcut has no Reelcut tools, and gets none until
someone reconnects it by hand. When 4817 is taken the app falls back to an ephemeral port that
only an `NSLog` line names, and a client pinned to 4817 then reaches whichever instance holds
it, a proof's included.

The shape, agreed with the user 2026-10-01:

- **The agent server listens on a Unix socket in its own `0700` `Agent` subfolder of the app's
  support folder, always, and nowhere else.** No TCP listener, no menu switch.
- **External clients reach it through `reelcut-mcp`**, a small stdio MCP server in the app
  bundle (`Contents/Helpers/`, beside the assistant's helper). It answers `initialize` and
  `tools/list` itself, from a catalog snapshot built into the bundle, and **launches Reelcut, in
  the background, on the first `tools/call` that finds no socket.**
- **Proofs address their own instance by socket path** (`RC_AGENT_SOCKET`), the way they
  address it by port today.

Nothing has been published and there are no users, so nothing migrates: the TCP listener, the
menu item, `RC_AGENT_PORT` and the `AgentServerEnabled` preference are deleted, not deprecated.

What the change also closes: the TCP endpoint checks neither `Origin` nor `Content-Type`, so
while it is on, a web page in the person's browser can POST a tool call to it as a simple
cross-origin request — it cannot read the answer, but `export`, `save_project` and
`open_project` run. A socket is out of a browser's reach. Not filed as an issue, by the user's
choice: this road map removes the listener.

## What exists

- `core/src/agent.rs` — the generic MCP server, copied from Rasterize: `tiny_http` 0.12 on
  `127.0.0.1`, JSON-RPC, **stateless** (no session ids; GET and DELETE answer 405), one request
  at a time, tools only. `tiny_http` 0.12 has `Server::http_unix(path)` with no feature flag, so
  the socket is the same HTTP on another listener and nothing above the transport changes.
- `rc_agent_server_start(uint16_t port, …)` in the header, `AgentServer.start()` in
  `AgentServer.swift` (frozen at wiring), which tries `RC_AGENT_PORT` or 4817 and then port 0.
- `AppDelegate.applicationDidFinishLaunching` starts the server when the `AgentServerEnabled`
  default is set (the menu persists it; the launch flag puts it in the argument domain);
  `toggleAgentServer` and its validator are the Tools menu's ONLY item
  (`AppDelegate+Menus.swift`).
- `AgentLane.prepareAtLaunch()` builds the catalog, the gate and the parity check in
  `main.swift` BEFORE `NSApplicationMain` (spec §11 AI-3) — the catalog exists before AppKit
  does, which is what makes a build-time snapshot cheap (MC1).
- `AppSupport.ensureDirectory` is the one creator of the support folder, `0700` at each level it
  makes, an existing folder left alone (#108).
- **`AgentServerEnabled` has a second meaning.** `FFmpegRewrap.canAsk` reads it as "an agent is
  driving and nobody is at the keyboard", so `ask` means no. Because the menu persists the same
  key, a person who turned agent connections on has also, unknowingly, turned off the FFmpeg
  question for their own clicks. MC-5 gives the meaning its own home and fixes that.
- `tools/proof/mcp.py` speaks HTTP to a port; about thirty proof scripts launch an instance
  with `RC_AGENT_PORT` and `-AgentServerEnabled YES` (`git grep -c` over `tools/`), and
  `tools/proof/README.md`, root `CLAUDE.md` "Verifying a build", the README's agent section,
  `dist_check.py`'s byte-count comment, the harness's pinned defaults, `DevAssistantLaunch`'s
  `server_running` and the menu inventory (`capture_spike/inventory.json`) all name them.
- The assistant's helper does not use the server's transport (AI-2: one lane, in process), so
  nothing here touches it.

## Decisions (recorded in spec §11 by MC0, before any code)

A new file `designs/spec/11-decisions/agent-connection.md`, with its rows in the index.

- **MC-1 — The agent server listens only on a Unix socket,
  `~/Library/Application Support/Reelcut/Agent/agent.sock`, and always, while the app runs.** No
  TCP listener and no switch. Only processes running as the person can reach a socket in a `0700`
  folder, and those can already read and write everything Reelcut can, so the switch guarded
  nothing a socket leaves open; TCP's only remaining users were the proofs. Risk accepted: any
  process running as the person can drive Reelcut while it runs, with no way to turn that off,
  and a client that speaks only HTTP-over-TCP cannot connect without the stdio helper.
- **MC-2 — The socket is bound only in its own `Agent` subfolder of the support folder, made
  `0700` by `AppSupport.ensureDirectory`; the mode-and-owner check is of that folder, and the
  support folder's own mode is not checked (#108). It is bound only by the first instance.** A
  later instance that can CONNECT to an existing socket leaves it alone and binds none (it logs
  why); one that is REFUSED treats the file as a crash's leftover, unlinks it and binds. The
  owner unlinks it at quit. A folder that is group- or world-accessible is reported and the
  socket is not bound — the folder's mode is the whole access control, so a wrong mode is not
  worked around.
- **MC-3 — External MCP clients reach Reelcut through `reelcut-mcp`, a stdio server inside
  the bundle.** It is the one supported client configuration; `README.md` gives the command.
  A Rust binary (no AppKit, no runtime to install), not the app's own binary run with a flag.
- **MC-4 — `reelcut-mcp` never launches Reelcut to answer `initialize` or `tools/list`.** Opening
  an MCP client must not open a video editor. It answers `tools/list` from the running app when
  there is one and from its bundle's catalog snapshot when there is not, and launches its OWN
  bundle, in the background (`open -n -g`), on the first `tools/call` that finds no socket —
  including after the person quits Reelcut mid-session. Two proxies that both find no socket
  launch one instance between them (a lock in the support folder).
- **MC-5 — A tool call never raises a modal question; a click still does.** "Nobody at the
  keyboard" stops being a launch-wide flag and becomes a property of the call: while the lane is
  running a tool call (`AgentLane`, which already tracks it), `FFmpegRewrap`'s `ask` means no and
  the stored policy decides alone, exactly as under `-AgentServerEnabled YES` today;
  `-RCFFmpegImport always` stays the way a scripted run asks for the conversion. This also
  covers a background-launched instance (MC-4), where an alert would bounce in the Dock with
  the agent's call held behind it, and it removes the persisted-switch wrinkle above. Risk
  accepted: the assistant's `import_media` of a file AVFoundation refuses no longer asks the
  person mid-turn; it answers with the refusal, which names the setting.
- **MC-6 — `RC_AGENT_SOCKET` overrides the socket path, and a proof always sets it.** No proof
  binds or deletes the person's socket, and `reelcut-mcp` honours the same variable, passing it
  to a Reelcut it launches (`open --env`), so a proof can drive the proxy against a scratch
  instance.

## Phases

Each phase is one litecode pipeline, in order; each is provable alone. The IDs are MC0..MC5.

### MC0 — decisions

MC-1..MC-6 into `designs/spec/11-decisions/agent-connection.md` and the index's two tables;
spec §7.9a's closing paragraph ("Default port 4817; env `RC_AGENT_PORT`; launch flag
`-AgentServerEnabled YES`") rewritten to cite them. No code.

### MC1 — spike: the snapshot, the launch and the client

Four questions to answer before MC3 is designed:

1. **Can the build write the catalog snapshot?** A launch argument (`-RCWriteCatalog <path>`)
   handled in `main.swift` straight after `AgentLane.prepareAtLaunch()` writes the prepared
   catalog and exits before `NSApplicationMain`, with no window or Dock icon. Can an Xcode script
   phase run the just-linked binary (linker-signed, not yet signed) and place the file in
   `Contents/Resources` before signing, in Release AND Distribution, and what does it add to
   `make app`? If not, the fallback to measure: the proxy runs its bundle's binary with the same
   argument at runtime when no instance is up, and caches the result per bundle version.
2. **What does a background launch cost and show?** From `open -n -g <bundle>` to the socket
   answering: cold, warm, and on a freshly quarantined copy. Does the Welcome window take focus
   or activate the app? The cold figure sets the proxy's wait (proposed: 60 s, env override).
3. **Does Claude Code refetch on `notifications/tools/list_changed` from a stdio server**, and
   does Claude Desktop? If neither does, a running app newer than the proxy's bundle shows a
   stale list until the client restarts, and that is recorded as a limit, not engineered around.
4. **The socket path's length** under real home folders against macOS's 104-byte `sun_path`,
   and what `tiny_http::Server::http_unix` does with an existing file at the path.

The answers go in this road map's MC1 record and bind MC2 and MC3.

### MC2 — the socket, beside TCP

- `agent.rs` gains a second listener on `Server::http_unix`, served by its own thread through
  the same `handle_request`. Calls still serialise through the lane (AI-2), so two listeners
  change nothing about ordering.
- A separate pair, `rc_agent_socket_start(path, …)` and `rc_agent_socket_release()`, beside
  `rc_agent_server_start` / `_stop`, with a slot of its own: Rust, header, `ReelCore.swift`'s
  `ReelAgentSocket` in lockstep. TCP stays for this phase only, so every existing proof keeps
  running while the socket is proved.
- The app binds the socket at every launch (MC-1), at `AppSupport`'s folder plus
  `Agent/agent.sock` or `RC_AGENT_SOCKET`, under MC-2's rules: ensure the `Agent` folder
  (`AppSupport.ensureDirectory`, `0700`), check its mode and
  owner, try to connect, unlink a refused file, bind, `chmod 0600`, unlink at
  `applicationWillTerminate` only the path this instance bound. A refusal logs one line; it is
  not an alert, since no person asked for anything. **Not** the `Reelcut: ` prefix, which
  stays the parity check's alone.
- Proof, `tools/proof/agent_socket_proof.py`: over a scratch `RC_AGENT_SOCKET`, `tools/list`
  over the socket is byte-identical to `tools/list` over TCP, and an edit made over one is read
  back over the other; a second instance with the same path leaves the first answering and
  binds nothing; after `kill -9` a third instance binds over the leftover file; a `0755` folder
  binds nothing and logs; the socket file is `0600`. Mutants: drop the connect-first check (the
  second instance steals the socket) and drop the mode check (the `0755` row binds).

### MC3 — `reelcut-mcp`

- A new crate, `mcp-proxy/` beside `core/` and `graphic/`, building one binary with `std` and
  `serde_json` only. `make lint`, `make test` and `cargo fmt` cover it; root `CLAUDE.md`'s file
  map gains its row. An Xcode step builds it and puts it in `Contents/Helpers/reelcut-mcp`,
  signed as the assistant's helper is; MC1's answer decides how the snapshot reaches
  `Contents/Resources/agent-catalog.json` (`{version, tools}` — the version is the bundle's).
- **stdio**, newline-delimited JSON-RPC as the MCP stdio transport defines it; stdout carries
  protocol only and everything else goes to stderr. Each request is handled on its own thread
  and answers are written under one lock, so a `ping` is answered during a ten-minute `export`.
- `initialize` and `ping` are answered locally. The supported protocol versions are one file,
  `core/src/mcp_versions.rs`, which `agent.rs` uses and the proxy includes by `#[path]`, so the
  two cannot disagree. Capabilities: `tools` with `listChanged: true`.
- `tools/list`: forwarded when the socket answers, else the snapshot (MC-4). If a live list
  differs from the one this session was last given, the proxy sends
  `notifications/tools/list_changed`.
- `tools/call`: connect; on no socket, take the launch lock (`std::fs::File::lock` on
  `agent.launch.lock` in the support folder), re-check, launch the bundle that contains the
  proxy's own executable with `open -n -g` (plus `--env RC_AGENT_SOCKET=…` when set), release,
  and poll until it answers or MC1's wait runs out. The timeout's error names the bundle it
  launched, the socket it waited on and for how long. **No read timeout on a forwarded call.**
  Anything else is forwarded when the app runs, and `-32601` when it does not.
- `dist_check.py` gains rows: the helper and the snapshot are in the Distribution bundle, and the
  Distribution snapshot names no dev tool while the Release one does.
- Proof, `tools/proof/mcp_proxy_proof.py`, driving the proxy as a client would, over stdin and
  stdout, against a scratch `RC_AGENT_SOCKET`: with no instance, `initialize` and `tools/list`
  answer and no Reelcut process starts; the snapshot's tools are byte-identical to a live
  instance's `tools/list`; a `tools/call get_project` with no instance launches exactly one and
  answers; two proxies calling at once launch one; an instance killed mid-session is relaunched
  by the next call; a `ping` is answered during a long call; stdout holds nothing but JSON-RPC.
  Mutants: launch on `tools/list` (the no-start row fails) and drop the lock (the one-instance
  row fails).
- `docs/manual-checks.md` gains the row only a person can make: Claude Code started with Reelcut
  not running lists Reelcut's tools; the first call opens Reelcut without taking focus from the
  terminal; and, per MC1's third answer, what a newer running app's tools look like.

### MC4 — TCP goes

- `mcp.py` speaks HTTP over a Unix socket (`http.client.HTTPConnection` with an `AF_UNIX`
  `connect`) and takes a path; every proof launches with a scratch `RC_AGENT_SOCKET` and drops
  `RC_AGENT_PORT` and `-AgentServerEnabled YES`. One launcher in `mcp.py` replaces the
  scripts' own, where that is a pure move.
- `agent.rs` loses the TCP listener, and `rc_agent_server_start` / `rc_agent_server_stop` are
  deleted (Rust, header, `AgentServer.swift`'s calls); `rc_agent_socket_start` / `_release` stay.
  `AgentServer` loses `port`, `defaultPort` and `enabledDefaultsKey`; its "is running" becomes
  "bound the socket".
- The interim port rule goes with `RC_AGENT_PORT`: `socketPlan`'s port arm, its `not bound` log
  line, and `agent_socket_proof.py`'s P1 case and K10 row (and the `no-port-rule` mutant). With
  `stop()` goes the TCP quit-join hang: `applicationWillTerminate` joins the TCP serve thread on
  main, which an in-flight call that hops to main can hold.
- Tools ▸ Allow Agent Connections goes, with `toggleAgentServer`, its validator and
  `startAgentServer`'s alert. **Tools ▸ Copy MCP Command takes its place** (agreed 2026-10-01):
  it puts on the general pasteboard the line that registers THIS copy of Reelcut with Claude
  Code — `claude mcp add --scope user reelcut -- '<bundle>/Contents/Helpers/reelcut-mcp'`, the
  path resolved from the running bundle and shell-quoted — so the person never types a path
  into an app bundle. The README gives the same command and Claude Desktop's JSON form. It is
  not an edit, so it has no MCP mirror (spec §7.9). It is the Tools menu's only item, which is
  why the menu is kept for now; where it belongs once the menu has nothing else is owed at
  closing. Spec §9's menus, the menu inventory and its `--check` in `make test` follow.
- MC-5: `FFmpegRewrap.canAsk` reads the lane's "a call is running" instead of the default.
- `tools/proof/README.md`, root `CLAUDE.md` "Verifying a build" (the launch line, the tool list's
  framing, "Launch your own instance on your own port"), the README's agent section (the
  `reelcut-mcp` command for Claude Code and Claude Desktop), spec §7.9a, `dist_check.py`'s
  comment, the harness's pinned defaults and `DevAssistantLaunch`'s `server_running`.
- Proof: `agent_socket_proof.py` gains a row that the instance listens on no TCP port
  (`lsof -a -p <pid> -iTCP -sTCP:LISTEN` is empty; mutant: the TCP listener restored), and a row
  for MC-5 — `import_media` of a file AVFoundation refuses, under the `ask` policy, answers with
  the refusal and raises no alert (mutant: `canAsk` true); and a row for the menu item —
  `perform_menu_item` Tools ▸ Copy MCP Command, then `pbpaste` equals the expected line for the
  instance's own bundle and the path in it is an executable file (mutant: a hard-coded
  `/Applications` path). Then every free proof is run over
  sockets and the scores recorded against their last record; the paid ones are not, unless the
  change reaches what they test.

### MC5 — closing

The ADR (`designs/adr/roadmap-14-agent-socket.md`), the archive move and its `INDEX.md` row,
root `CLAUDE.md`'s table entry for the ADR, and an issue on `kpgalligan/rasterize` offering the
same transport change, since `agent.rs` is Rasterize's copy and now differs from it. The owner
re-points their own client configuration (today a local-scope `reelcut` HTTP entry on 4817) at
the built bundle's `reelcut-mcp`; that is theirs to run — Tools ▸ Copy MCP Command gives it —
after `claude mcp remove reelcut -s local`. Filed as a `low-priority` issue at closing: a home
for Copy MCP Command other than a Tools menu that holds nothing else (the user's call,
2026-10-01: keep it in Tools for now).

## Record

### MC0 — decisions (2026-10-01)

MC-1..MC-6 are spec §11 in `designs/spec/11-decisions/agent-connection.md` (43 lines), each
bullet this document's "Decisions" text re-wrapped, with one edit: MC-5's "the persisted-switch
wrinkle above" names its referent, "(road map 14, "What exists")". Their rows are in
`designs/spec/11-decisions/README.md`: the file's row after `pricing.md`'s, and six rows in
"Every decision" after P-8. Spec §7.9a's closing paragraph now cites MC-1..MC-6 and keeps the
TCP facts true until MC4: the build "also keeps a TCP listener, its only one until MC2 adds the
socket beside it" (default port 4817, `RC_AGENT_PORT`, `-AgentServerEnabled YES`, under which
`FFmpegRewrap`'s `ask` means no for the whole launch). The spec index's counts are current:
`07.9a` at 402 lines ("the port" now "the transport"), `11-decisions/` at 2678 in 14 files (the
old cell's 2628 in 13 plus the new file and the seven index rows). No code. Checked: both greps
for MC rows (`^- **MC-[1-6] — ` in the decision file, `^| MC-[1-6] | …agent-connection.md` in
the index) print 6; the Lines cells equal `wc -l`; §7.9a shows both the MC citation and
`RC_AGENT_PORT`; "Default port 4817" no longer appears under `designs/spec/`; a
whitespace-normalised comparison of the six bullets against this document's text matches, with
the MC-5 edit applied. Owed: nothing from MC0; MC1 is next.

### MC1 — spike: the snapshot, the launch and the client (2026-10-01)

The instrument is `tools/proof/mc1_spike/` (its README has the rows). `python3
tools/proof/mc1_spike/mc1_spike.py` exited 0 with 39 rows: 22 pass, 16 answered and 1 fail
(L4, below). There were no `error` rows and no skips. The B7c, L0 and T3 controls passed. q1–q3's
figures are from that run, and q4's from the `--only q4` run straight after it (exit 0). The
figures are in `tools/proof/work/mc1_spike/answers.json`. **The spike made no model call and no
API request, and spent $0.** Its builds and launches ran while other sessions were building Reelcut
and Rasterize on the same machine, so every timing below was taken under that contention.

**1. The snapshot (q1): yes, if the phase signs first. This binds MC3.**
- Xcode links the app with `-Xlinker -no_adhoc_codesign`, because it signs the bundle later. So at
  script-phase time `$TARGET_BUILD_DIR/$EXECUTABLE_PATH` is not linker-signed: `codesign -dv`
  reports "code object is not signed at all".
- arm64 kills an unsigned exec. The first attempt, which ran the binary as it stood, exited 137 in
  about 15 ms and failed the Release, incremental and Distribution builds.
- The answer (request addendum 4) is a phase that first runs `codesign -s - -f
  "$TARGET_BUILD_DIR/$EXECUTABLE_PATH"` (the executable only, ad hoc, in place) and then runs it
  with `-RCWriteCatalog`. It is not a signed copy in `$DERIVED_FILE_DIR`: a lone executable has no
  bundle, and the snapshot's version comes from `Bundle.main`. Xcode's CodeSign step re-signs the
  bundle afterwards.
- With that phase, in the tree copy:
  - The full `make app` passed in 120.1 s wall, of which the phase took 903 ms (95 ms of it the
    ad-hoc sign) (B2).
  - The incremental `make app` passed in 32.1 s, phase 370 ms, sign 57 ms (B3).
  - The Distribution `xcodebuild` passed in 88.8 s, phase 756 ms, sign 66 ms (B4).
  - Each anchor was found exactly once (B1).
- Both snapshots parse as `{version, tools}` at the bundle's `0.1.0` (B5). Release's has 92 tools
  (240 829 bytes) and Distribution's 86 (232 416 bytes). Release's names all six `devHandlers`
  keys and Distribution's names none (B6).
- `codesign --verify --strict --deep` passes on both bundles (B7). A copy with one byte of the
  snapshot changed fails it: "a sealed resource is missing or invalid" (B7c, control).
  `dist_check.py` gives 14/14 on the two bundles (B8).
- Each product's final signature is Xcode's, not the phase's (B12). Its CDHash differs from the one
  the phase printed. The Info.plist is bound (29 entries), resources are sealed (version 2, 13
  rules, 35 files) and the flags read `adhoc,runtime`, in both Release and Distribution.
- No `Reelcut: ` line appeared in any phase's writer output (B11).
- Release's snapshot `tools` equals a live instance's `tools/list` as JSON values (B9). They are
  **not byte-equal** when compactly re-serialised in their own key order, and are byte-equal with
  sorted keys. The catalog string's object key order differs between processes. B10 shows the same
  between the build's snapshot and four runtime writes.
  - **MC3's proof, and the proxy's own "a live list differs from the one this session was last
    given" test before it sends `notifications/tools/list_changed`, must therefore compare as JSON
    values or with sorted keys**, not as raw bytes, unless MC3 makes the writer emit sorted keys;
    a byte test would send every session a spurious `list_changed`.
- The fallback (the bundle's binary run with `-RCWriteCatalog`) took 0.807 s on a fresh copy and
  0.094, 0.093 and 0.085 s on warm runs. Every run exited 0 with output JSON-equal to the build's
  (B10). It is not needed, because the build-time snapshot works.

**2. The launch (q2): about a second, in the background.** TCP stood in for the socket. Times run
from just before `open -n -g` to the first answered `initialize`, polled every 50 ms.
- Cold, on three fresh `ditto` copies (L1): 1.069, 1.087 and 1.087 s. There was no `purge`, which
  needs root.
- Warm, on one copy (L2): 0.474, 0.518 and 0.533 s, after a 1.059 s priming launch.
- **The wait MC3 adopts is a fixed 60 s with an env override.** L7 passes: 3 × max(L1) = 3.261 s,
  well under 60 s, so MC3's text is unchanged.
- No launch log holds a `Reelcut: ` line (L6, 8 logs). The console was unlocked (H0).
- **Reelcut was never the frontmost app in any of the seven measured launches** (L4's
  `reelcut_ever_frontmost` is empty).
- L4 itself scored **fail**, 6/7. In `cold-…-3` the frontmost app changed from Finder to Brave
  Browser between the answer and +2 s, which is the person at the machine rather than Reelcut. Its
  per-launch pids are in `answers.json`.
- Each launch had one on-screen layer-0 window, 720 × 632, both at the answer and at +2 s
  (L5). **A background launch shows a window without activating the app**; MC3's
  manual check is where a person judges whether that is acceptable.
- A copy with `com.apple.quarantine` set (L3):
  - `spctl --assess --type execute` reported "rejected" (rc 3).
  - `open` returned 0, but no process appeared and nothing answered within 60 s.
  - CoreServicesUIAgent had no on-screen window at the end of the wait. As far as that measures,
    **the quarantined launch left no Gatekeeper dialog**; it simply did not start.
  - This is an ad-hoc-signed, unnotarized build. A notarized Distribution build is not measured.

**3. The client (q3).**
- Claude Code's MCP page, <https://code.claude.com/docs/en/mcp> (D1, fetched 2026-10-01, the
  running client being `2.1.287 (Claude Code)` per C1), says: "Claude Code supports MCP
  list_changed notifications, allowing MCP servers to dynamically update their available tools,
  prompts, and resources without requiring you to disconnect and reconnect. When an MCP server
  sends a list_changed notification, Claude Code automatically refreshes the available
  capabilities from that server."
  - The page also says that, on its v2 runtime, list_changed arrives over a stream the client holds
    open, from servers on the newer protocol revision. That is about HTTP servers; a stdio server's
    notifications share its stdout.
- The stub stdio server behaves as MC3's proxy must. `initialize` advertises `listChanged: true`;
  `tools/list` gives `[probe_wait]`; the `probe_wait` call delivers
  `notifications/tools/list_changed` before its own answer; a second `tools/list` gives both tools;
  and the log holds every inbound message (T1).
  - In `unprompted` mode the notification comes 2.005 s after the first `tools/list` answer (T2).
  - In `silent` mode nothing comes within 8 s (T3, control).
- Whether Claude Code and Claude Desktop actually refetch from a stdio server needs a running
  client with a model. **Owed** as `docs/manual-checks.md` AC-1 (Claude Code) and AC-2 (Claude
  Desktop), the person's own runs against the stub. Until AC-1 answers, MC3 assumes the documented
  refetch for Claude Code and nothing for Claude Desktop.

**4. The socket (q4), and what MC2 must do.**
- **Path length** (S1, S2): binding at 103 bytes succeeds, and at 104 and 105 bytes fails with
  "path must be shorter than SUN_LEN". **103 bytes is the budget.**
  - The product path is 73 bytes on this host. A `/Users/<name>` home fits names up to 43 bytes.
  - `$TMPDIR` plus `reelcut-XXXXXXXX/agent.sock` is 76 bytes.
  - `<worktree>/tools/proof/work/<12 chars>/agent.sock` is exactly 103 bytes on this worktree. **A
    proof's `RC_AGENT_SOCKET` must therefore live under `$TMPDIR` (a `mkdtemp`), not under
    `tools/proof/work/`**, and MC2 should refuse a path over 103 bytes by name.
- A fresh bind's socket file is mode 755 under umask 022 (S3), so MC2's `chmod 0600` is needed.
- Binding over a live server's path (S4), over a SIGKILLed server's leftover file (S5) and over a
  regular file (S6) all fail with "Address already in use (os error 48)". `tiny_http` never unlinks
  first. The leftover's `connect` is refused (ECONNREFUSED), and a regular file is left intact.
  - **So MC2's connect-first-then-unlink-a-refused-file is required.** What MC2 does with a
    non-socket file at the path is for MC2's spec to settle against MC-2, which says only that a
    refused file is unlinked: no row measured a `connect` to a regular file.
- **S7: `tiny_http` 0.12's `Server` `Drop` unlinks its path unconditionally.** Server A was bound,
  its path unlinked, B bound at the same path, and A dropped. A's drop removed B's file, and B was
  then unreachable (NotFound). MC2 must therefore:
  - never drop a second `Server` bound at a path another instance now holds;
  - not rely on `Drop` alone for "unlink only the path this instance bound";
  - keep the listener alive for the app's life and unlink at `applicationWillTerminate` only after
    checking the file is still its own (for example, by inode).
- `server_addr().to_ip()` is `None` for a unix listener (S9). The TCP code's `.to_ip()…port()`
  must not be reused for the socket, since `start` would return an error.
- A POST over the socket is answered `HTTP/1.1 200 OK` (S8). `unblock()` then join returns in
  0.023 ms (S10).

**The support folder (S11), and the §11 amendment.**
- `~/Library/Application Support/Reelcut/` is `0755` on this host, owned by the person, and has no
  `Agent/`. `AppSupport.ensureDirectory` leaves an existing folder's mode alone (#108). MC-2 as
  first worded (bound only in a `0700` folder) would therefore never bind here.
- Per request addendum 1, the socket now lives in its own `Agent` subfolder, which
  `ensureDirectory` makes `0700`, and MC-2's mode-and-owner check is of that folder. The files
  edited:
  - `designs/spec/11-decisions/agent-connection.md`: MC-1's path, now
    `~/Library/Application Support/Reelcut/Agent/agent.sock`, and MC-2's folder. The file is now 45
    lines.
  - `designs/spec/11-decisions/README.md`: the file row (45 lines, "its own `0700` `Agent`
    subfolder of the support folder") and the MC-1 and MC-2 rows.
  - `designs/spec/07.9a-agent-tools.md`: the path and "its own `0700` `Agent` subfolder",
    re-wrapped. It is still 402 lines.
  - `designs/spec/README.md`: `11-decisions/` is now 2680 lines in 14 files.
  - This document: the opening shape bullet, "Decisions" MC-1 and MC-2 (whitespace-normalised
    equal to §11's), and MC2's socket bullet (`Agent/agent.sock`, ensured by `ensureDirectory` at
    `0700`).
  - MC-3..MC-6 are untouched, including MC-4's lock "in the support folder".

**Side effects.**
- The copy's "Build Rust Core" step recompiled the tree's own `core/target` (gitignored), so it was
  not a no-op. Most likely the xcodebuild environment differs from `make rust`'s; this was not
  investigated.
- The first attempt (before addendum 4) ran two `open -n -g` launches of an unsigned copy, which
  never started.
- An empty `/tmp/mc1q4try` is left from a manual trial.
- Nothing was created under `~/Library/Application Support/Reelcut/`, and nothing was registered
  in any Claude configuration. Only pids whose command line holds `tools/proof/work/mc1_spike/`
  were signalled, and Z1 found none left.

**Owed:** AC-1 and AC-2 (the person's). Nothing else from MC1. MC2 is next, carrying S7, S9, the
103-byte budget and the `$TMPDIR` rule for proof sockets; MC3 carries the signing phase, the 60 s
wait and B9's JSON-value comparison.

### MC2 — the socket, beside TCP (2026-10-01)

The app binds the agent server on a Unix socket at every launch, beside the TCP listener, under
MC-1, MC-2 and MC1's findings. Over `ffe5a9f`:

- **The toll first.** `ReelCore.swift` (1353 lines) gave up its `dictionary` extensions to
  `PropsDictionaries.swift` (the 106-line section moved whole; only the section doc's "nothing outside"
  sentence names the new file) before taking the wrapper, and `make typecheck` held its baseline
  over the pure move alone. `app-file-history.md`'s named next cut for it is now the typed patches.
- **Core.** `agent.rs` gains `start_socket` (absolute path, at most 103 bytes, `http_unix`, never
  an unlink first, chmod 0600, then the claim and the serve thread), `SocketClaim` (the device and
  inode `lstat` read after the bind) and `AgentServer::release`. `shutdown` lets `tiny_http`'s
  `Drop` run only while the claim is current and forgets the server otherwise (S7).
  `ffi_agent.rs` gains `rc_agent_socket_start` / `rc_agent_socket_release` in a `SOCKET` slot of
  their own; `host_config` builds the `AgentConfig` for both starts. `core/tests/agent_socket.rs`
  holds 7 tests, and `model_tests.rs`'s null sweep covers both exports.
- **App.** `ReelAgentSocket` in `ReelCore.swift`; `AgentServer+Socket.swift` (188 lines) holds the
  plan, MC-2's policy, the bind, the release and the two log lines (`Reelcut agent socket
  listening at <path>`, `Reelcut agent socket not bound: <reason>`). `AgentServer.swift` (frozen)
  took three wiring edits: the trampoline is internal, `start()` reads `serverVersion`, and the
  header doc names the socket. `applicationDidFinishLaunching` calls `bindSocket()` first, and
  `applicationWillTerminate` calls `unbindSocket()` before `stop()`.

**Deviations from this road map's MC2 text**, each decided in the phase's spec:
- **A separate FFI pair, not a socket argument on `rc_agent_server_start`.** The socket's quit is
  a release without a join (below) while TCP's `stop()` keeps its join, and the Tools menu toggles
  TCP without touching the socket, so each listener has its own slot. The MC2 and MC4 bullets
  above now say so; MC4 deletes the TCP pair.
- **The quit releases without a join.** `rc_agent_socket_release` unlinks the file only while it
  is this listener's (same device and inode), then abandons the listener: its thread is neither
  unblocked nor joined, so a call in flight that waits on main cannot hold the quit, and process
  exit ends it. `AgentServer.shared`, the handler's context, lives for the process.
- **The interim port rule (MC2..MC3).** A launch that sets `RC_AGENT_PORT` and not
  `RC_AGENT_SOCKET` binds no socket and logs why: every proof of the era launches that way, and
  without the rule each would bind the person's socket, against MC-6. It is recorded under spec
  §11 MC-6, and MC4 deletes it with `RC_AGENT_PORT` (its arm, its log line, P1's case and K10).
  Root `CLAUDE.md`'s launch line also gains `RC_AGENT_SOCKET="$(mktemp -d)/agent.sock"`.
- **The non-socket rule.** A file at the path that is not a socket is left alone and nothing is
  bound (`<path> exists and is not a socket; it is left alone`): MC-2 sanctions unlinking only a
  socket that refuses a connection, and MC1 measured no `connect` to a regular file.
- **The TCP `stop()` quit-join hang: removed by MC4.** `stop()` still joins the TCP serve thread
  on main at quit, and a call in flight that hops to main can hold it. This phase does not change
  it and no issue is filed, because MC4 deletes `stop()` with the listener.

**Checked**, every instance my own, no model call and no spend ($0):

| Command | Answer |
|---|---|
| `cd core && cargo fmt --check && cargo test --release --test agent_socket` | clean; 7 passed |
| S7 mutant: `shutdown`'s `is_current` guard removed | `shutting_down_a_listener_whose_file_was_replaced_leaves_the_new_one` FAILED (6 passed, 1 failed) |
| S7 mutant: `release`'s `is_current` check removed | `releasing_a_listener_whose_file_was_replaced_leaves_the_new_one` FAILED (6 passed, 1 failed) |
| `make typecheck` | 0 errors, 4 warnings (the AVFoundation baseline), tsc clean; the same after the toll alone |
| `make lint`; `make test`; `make app` | exit 0; exit 0 (the inventory's `--check` 5/5, its AppDelegate pins found at moved lines); BUILD SUCCEEDED |
| `python3 tools/proof/agent_socket_proof.py --port 4941` | 14/14, exit 0: P1 5 cases; K2 240 631 bytes and 92 tools both ways; K6 and K7 quits in 0.14 s and 0.12 s; K10 `Agent/` and `agent.sock` absent before and after |
| `… --port 4951 --mutant no-connect-first` | K4 FAIL (B listened at A's path, dev/ino changed), caught, exit 0 |
| `… --port 4961 --mutant no-mode-check` | K8 FAIL (E listened in the `0755` folder), caught, exit 0 |
| `… --mutant no-port-rule` | P1 FAIL (`RC_AGENT_PORT` alone planned the default), caught, exit 0; no app launched |

The proof's first run scored K3 FAIL from the proof's own reading (a marker's key is `time`, not
`at`); after that fix it scored 14/14. Nothing was created under `~/Library/Application
Support/Reelcut/`; the scratch folders under `$TMPDIR` are removed at the end of each run.

**Owed:** nothing from MC2. A quit with a call in flight is not proved (out of this phase's
scope). MC3 (`reelcut-mcp`) is next; MC4 owes the interim rule's deletion and the TCP pair's.

### MC3 — `reelcut-mcp` (2026-10-01)

External MCP clients now have their stdio server. Over `ba8ed00`:

- **The versions.** `core/src/mcp_versions.rs` (std only) holds `SUPPORTED_VERSIONS`,
  `LATEST_VERSION` and `negotiate`; `agent.rs` lost its two constants and its `initialize` calls
  `negotiate` — nothing else in Rasterize's copy moved (MC5 files the Rasterize issue). The proxy
  includes the same file by `#[path]`.
- **The crate.** `mcp-proxy/` builds `reelcut-mcp` with `std` and `serde_json` only (`tiny_http`
  0.12 as a dev-dependency, for the tests' stubs), every `src/` file under 400 lines (`session.rs`
  314, `socket.rs` 210, `launch.rs` 142), `#![forbid(unsafe_code)]`, its rules in
  `mcp-proxy/CLAUDE.md`. stdin is read by lines and each request runs on its own thread; stdout is
  written under one lock, protocol only; stderr lines start `reelcut-mcp: `. `initialize` and
  `ping` never touch the socket. `tools/list` is the app's when it answers within 5 s
  (`LIST_READ_TIMEOUT`), else the snapshot's. `tools/call` launches the proxy's own bundle on
  `Absent` (`NotFound` or `ConnectionRefused`). Anything else is forwarded, or `-32601` with no
  app. The reader decodes `Content-Length` and chunked bodies, since `tiny_http` chunks the 240 KB
  list. `list_changed` is sent after a forwarded call when a live list differs, AS A JSON VALUE,
  from the one this session was last given (MC1's B9). `make test`, `make lint`, `make fmt` and
  `make clean` cover the crate; `mcp-proxy/tests/stdio.rs` holds 14 black-box tests over the built
  binary in a fake bundle; only one reaches the launch, and its bundle's executable is a script
  that records its launch and exits without binding.
- **The snapshot.** `app/Sources/AgentCatalogSnapshot.swift` is MC1's hook made product:
  `-RCWriteCatalog <path>`, read from the argument domain only, writes `{version, tools}`
  atomically and exits; a failure is one `reelcut catalog snapshot: …` line and exit 1.
  `main.swift` calls it straight after `AgentLane.prepareAtLaunch()`, at `#if` depth 0 (the lane
  proof's L0 still passes).
- **The build.** `project.yml` gains two post-build phases after "Build Agent Helper". "Build MCP
  Proxy" runs `cargo build --release`, copies the binary into `Contents/Helpers/` and signs it
  `--options runtime` with `agent/build.sh helper`'s identity and timestamp rule and no
  entitlements. "Write Agent Catalog" is MC1's phase minus its timing lines: the executable is
  ad-hoc signed in place, run with `-RCWriteCatalog`, and the phase fails on a non-zero exit or any
  `Reelcut: ` line. `tree_copy.py` needs no change: `project.yml` now spells `mcp-proxy/`, so every
  mutant tree copy links it.
- **The checks.** `dist_check.py` D15–D24 (`TOTAL = 24`): each bundle's proxy is present, has the
  hardened runtime and no entitlements; each snapshot is at the bundle's
  `CFBundleShortVersionString`; Release's names every flag-on `devHandlers` key (the positive
  control) and Distribution's names none. `dist_check_mutants.py`'s skeletons carry
  `Contents/Info.plist`, the proxy and the snapshot for every case, and it adds eight cases
  (20 in all). The phase's proof is `tools/proof/mcp_proxy_proof.py` (X0–X10, X7b, Z1, Z2, and
  two mutants). `docs/manual-checks.md` gains AC-3, with `work/mcp-proxy/ac-mcp.json` as its
  fixture.

**Deviations from this road map's MC3 text**, each decided in the phase's spec:
- **The lock is held until the poll ends**, not released after the launch: released before it, a
  second proxy's re-check finds nothing answering yet and launches a second instance. It is
  `agent.launch.lock` BESIDE THE SOCKET, not in the support folder, so a proof's scratch socket
  has its own lock.
- **A session whose launch timed out launches no other** (the phase's objection 1). Its later
  calls that find no socket answer the stranded sentence, so an instance that never binds is not
  joined by another on every call. The review found that two concurrent calls in one session
  both passed the `stranded` check before either launched, so the second launched again after the
  first timed out; the check and the launch are now one critical section per session
  (`Session.launching`), held by the stdio test
  `concurrent_calls_in_one_session_launch_at_most_once_when_none_answers`, which fails without it
  (both calls answer the timeout sentence).
- **`tools/list` waits at most 5 s for the app** (objection 2). The app serves one request at a
  time, so another client's long call would otherwise hold a listing indefinitely. The snapshot
  answers instead and the next call checks the list.
- **A scratch launch** (`RC_AGENT_SOCKET` set) also passes `-ApplePersistenceIgnoreState YES` and
  writes the instance's stderr to `reelcut-launch.log` beside the socket. A launch for the person's
  own socket passes neither.
- **The snapshot is compared with the live list as JSON values, not bytes** (MC1's B9; X3).
- **Public beyond the spec's interfaces:** `launch::TIMEOUT_OPENING` and
  `launch::timeout_sentence()`, because `ensure_running` answers a `String` and `Session`
  recognises a timeout by the sentence's opening (an `open` failure strands nothing, since
  nothing was launched).
- **`session::dispatch`** is the spec's per-line step (a blank line skipped, `-32700`, a batch
  `-32600`, notifications and responses dropped, a thread per request), public so `run()` calls it.
- **`-32600` for two cases the spec leaves open:** a JSON line that is neither an object nor an
  array answers `a message must be a JSON object` with a null id, and a non-string `method`
  answers `the method must be a string` with the request's id.
- **A live `tools/list` with no `result.tools` array falls back to the snapshot**, the same as a
  failed post.
- **`list_changed` is always sent when the session was given no list yet** (last-given `None`),
  as the spec literally says; that happens only after a `Started` launch in a session that never
  listed.
- **The proof removes its bundle copy** (`work/mcp-proxy/<run>/`) at the end when Z1 finds no
  instance of it alive; a mutant's build tree is replaced by the next run of that mutant.
- **Nothing it launches stays registered with LaunchServices.** `/usr/bin/open` registers the
  bundle it opens, so a deleted copy stayed in LaunchServices' database as a `Reelcut.app` at a
  path that no longer exists (the second review's nit, for the tests' fake bundle). The proof runs
  `lsregister -u` on its copy before removing it, and a `launchable` fixture in
  `mcp-proxy/tests/stdio.rs` does the same on drop; measured, a run of each now adds no
  registration (`lsregister -dump` counted before and after). The registrations road map 14's
  own earlier runs had left — 25 copies under `work/mc1_spike`, `work/mcp-proxy` and
  `work/agent-socket` (MC2's mutant builds, which Xcode registers as it builds) — were
  unregistered and their folders (2.9 GB) deleted by hand. Other proofs' copies are owed at MC5
  as an issue.
- Spec §11 MC-4 and MC-6 (`designs/spec/11-decisions/agent-connection.md`, now 54 lines) record
  the lock's place, the stranded sentence and the scratch launch's two extras. Their index rows and
  the file's Lines cell are updated, and `11-decisions/` is now 2689 lines in 14 files. This
  document's "Decisions" section still words MC-4 and MC-6 as MC0 left them, so §11 is the fuller
  text.

**Checked**, every instance my own, no model call and no spend ($0):

| Command | Answer |
|---|---|
| `cd mcp-proxy && cargo fmt --check && cargo test --release && cargo clippy --all-targets -- -D warnings` | clean; 14 passed (13, then the review's concurrency test); clean |
| `cd core && cargo fmt --check && cargo test --release --test agent_socket` | clean; 7 passed |
| `make typecheck`; `make lint`; `make test` | 0 errors, 4 warnings (the AVFoundation baseline), tsc clean; exit 0; exit 0 (lane 18/18, prompt 14/14, prices 27/27, budget 23/23, inventory 5/5) |
| `make app`; `make dist` | BUILD SUCCEEDED; `dist_check: 24/24` (Release snapshot 92 tools, Distribution 86, both `0.1.0`; D23 6 of 6) |
| `codesign --verify --strict --deep` on the Release app | exit 0 |
| `dist_check_mutants.py` | 20/20 |
| `mcp_proxy_proof.py` | 14/14 in 38 s: X2 answered in 0.49 s; X6 the timeout in 5.08 s, then the stranded sentence at once with no second instance; X7b the snapshot in 5.0 s |
| `--mutant launch-on-list` | X1 FAIL (an instance and a socket after `tools/list`), caught, exit 0 |
| `--mutant no-lock` | X4 FAIL (two instances), caught, exit 0 |
| `agent_socket_proof.py --port 4941` | 14/14 |

No build output and no launch log holds a `Reelcut: ` line. Nothing was created under
`~/Library/Application Support/Reelcut/` (Z2: `Agent/`, `agent.sock` and `agent.launch.lock`
absent before and after), nothing was registered with a Claude client, and the scratch folders
under `$TMPDIR` are removed at the end of each run.

**Owed:** AC-3 (the person's: Claude Code against the built bundle's proxy), with AC-1 and AC-2
from MC1. MC4 is next: TCP goes, `mcp.py` moves to sockets, MC-5, Tools ▸ Copy MCP Command and
the README's agent section (which still names TCP).

### MC4 — TCP goes (2026-10-01)

The socket is the agent server's only listener. Over `38b9487`:

- **Core.** `agent.rs` lost `start` (TCP on 127.0.0.1) and its two imports; its module doc names
  one listener. `ffi_agent.rs` lost `rc_agent_server_start`, `rc_agent_server_stop` and the
  `SERVER` slot; `SOCKET` is the one slot, and `rc_agent_socket_start`'s doc took over the handler
  contract the TCP pair's carried. The header lost both declarations (`RC_FORMAT_VERSION` is
  unchanged). `core/tests/agent_socket.rs` lost the TCP byte-equality test (6 tests), and
  `model_tests.rs`'s null sweep both TCP exports. `AgentServer::shutdown` stays for S7's test.
- **App, the transport.** `AgentServer.swift` (frozen; 825 → 777 lines) lost
  `enabledDefaultsKey`, `defaultPort`, `port`, `start()` and `stop()`; `boundSocketPath`, written
  by `bindSocket` after a bind, is what `isRunning` reads, so `DevAssistantLaunch`'s
  `server_running` means "this launch bound the agent socket". `AgentServer+Socket.swift` lost
  `portOnlyReason` and `socketPlan`'s port arm and gained `mcpHelperURL` (this bundle's own
  `Contents/Helpers/reelcut-mcp`) and `mcpCommand(helperPath:)`. `AppDelegate.swift`'s launch
  only binds and its quit only releases (the TCP quit-join hang is gone with `stop()`);
  `toggleAgentServer`, `startAgentServer` and their validator arm are gone. **Tools ▸ Copy MCP
  Command** (`copyMCPCommand`, enabled exactly while the helper is an executable file, live with
  no document, no MCP mirror) clears the general pasteboard and sets the `claude mcp add --scope
  user reelcut -- '<path>'` line, each `'` in the path written `'\''`. `UIMenuTable.swift` and
  `capture_spike/inventory.json` carry `copyMCPCommand:` as `none` in the old row's place.
- **App, MC-5 carried per call.** "May ask" is decided where a tool call hands work to the
  importer, never read from process-wide state, so a person's own import still asks while a call
  runs: `FFmpegRewrap.assist(_:mayAsk:)` replaces `canAsk` (767 → 761 lines),
  `MediaImporter.probe(url:mayAsk:completion:)` requires the argument (every click path passes
  `true`; `import_media` and `relink_media` pass `false`, and `record_screen` passes `false`
  through `ScreenRecorder.start(…, mayAsk:)`, which `Session` carries to the finished movie's
  probes), and `open_project` runs its synchronous `makeDocument` inside
  `MediaImporter.withoutAsking`, a thread-scoped key `probeBlocking` reads. A tool call's refusal
  of a file an installed ffmpeg could convert names the setting (`neverAsksSentence`).
  `AgentLane.swift` is untouched.
- **The proofs.** `mcp.py` speaks HTTP over the socket (`UnixHTTPConnection`; `MCP(<int>)`
  raises a `TypeError` naming MC4) and is the shared launcher (`scratch_socket`,
  `remove_scratch`, `log_beside`, `wait_listening`, `socket_pid`, `target`, `launch`,
  `Launched`, `LSREGISTER`). Every proof that takes a running instance takes its socket; every
  proof that launches its own does so on a scratch socket; the spikes' launches moved too (none
  was run). `agent_socket_proof.py` retired K2, K10 and `no-port-rule`, and gained K11 (no TCP
  listener), K12 (MC-5's two halves) and K13 (Copy MCP Command, with
  `tools/proof/pasteboard_keep.swift` keeping the person's clipboard byte for byte) and four
  mutants. The `AgentServerEnabled` pins left the harness and the probes.
- **Documents.** Root `CLAUDE.md`'s launch block and its rule (the printed folder named
  literally), the README's agent section (Copy MCP Command, `claude mcp add`, Claude Desktop's
  JSON, the socket's owner-only access), `app/CLAUDE.md`, `core/CLAUDE.md`, spec §7.9a, §7.9b,
  §9 (the Tools menu), §11 MC-5 and MC-6 with their index rows, the spec index's Lines cells,
  `docs/manual-checks.md` (REC-7, REC-8 and HS-2 on a scratch socket; new AC-4 and AC-5),
  `tools/proof/README.md` (`mcp.py`'s paragraph, every how-to-run line and launch block, a note
  that the ports in dated records are what ran then, and an MC4 section) and `dist_check.py`'s
  marker comment.

**MC-5's mechanism sentence**, as spec §11 now words it: "for the import a tool call starts,
decided where the call hands work to the importer (`import_media`, `relink_media`,
`open_project`, `record_screen`), `FFmpegRewrap`'s `ask` means no and the stored policy decides
alone, exactly as under `-AgentServerEnabled YES` before MC4".

**Deviations from this road map's MC4 text**, each decided in the phase's spec:
- **MC-5 is a property of the call, not of the lane.** The text above has `canAsk` read "a call is
  running" from the lane; a process-wide flag would have made a person's own MKV import refuse
  silently while any off-main tool call ran, against MC-5's "a click still does". The callers
  decide instead (above), and K12 gained an `open_project` half.
- **The TCP mutant is a fresh listener**, not the old one restored: `tcp-listener` adds a POSIX
  `socket`/`bind 127.0.0.1:0`/`listen` after the `listening at` line and leaks it.
- **`agent-asks` and `open-asks` replace a `can-ask` mutant**, one per place a call hands work to
  the importer; `fixed-path` is the Copy MCP Command mutant.
- **`mcp.launch` does not pop `RC_AGENT_PORT`** (the spec's interface says it does): the name is
  in the phase's own clean-tree grep's scope, and the app no longer reads the variable, so the pop
  would do nothing.
- **Comments outside the spec's list** were corrected where they named a deleted function:
  `AgentServer.swift`'s and root `CLAUDE.md`'s `start()` (the parity check now runs in
  `prepareCatalog()`), `app/CLAUDE.md`'s gate entry, the trampoline's "both listeners" and
  `AppDelegate`'s "as the agent-server item below is".
- **Proof files outside the spec's list moved with what they call:** `cloud_captions_live.py`
  (`cloud_captions_proof.Instance` lost the port) and `recording_probe.py`'s `recorder.start`
  call (`mayAsk: true`, or the probe would not compile). The
  `AgentServerEnabled` pins in `recording_probe.py` were nine sites, not five, plus one mutant
  sentence; all went.

**Checked**, every instance my own, no model call and no spend (**$0**). `lstat` of
`~/Library/Application Support/Reelcut/Agent/` and `agent.sock`: absent before the first proof and
after the last; `lsregister -dump` holds no registration under `tools/proof/work/agent-socket/`
before or after; no scratch folder left under `$TMPDIR`; no instance of this tree left running.

| Command | Answer |
|---|---|
| `cd core && cargo fmt --check && cargo test --release` | clean; every suite ok (`agent_socket` 6) |
| `make test`; `make lint`; `make typecheck` | exit 0 (lane 18/18, prompt probe 14/14, prices 27/27, budget 23/23, inventory 5/5); exit 0; 0 errors, the 4 baseline warnings, tsc clean |
| `make app`; `make dist` | BUILD SUCCEEDED; `dist_check: 24/24`; no `Reelcut: ` in either log |
| `agent_socket_proof.py` | 15/15, twice (before and after the final `make app`); after the review's fixes, 15/15 again with a non-empty plain-text clipboard, restored (`restored 1 items`) — and K13 driven with its setup made to raise, before the copy and after it: a FAIL each time, never a SKIP, the clipboard untouched in the first and restored in the second |
| `mcp_proxy_proof.py` | 14/14 in 39 s |
| `v2_menu.py --only H`; `capture_spike/inventory.py --check` | 5 pass of 5; 5/5 (AppDelegate's two pins found at moved lines) |
| the two greps of the phase's Verification | nothing |

The mutants (each a `tree_copy` copy built by its own `make app`, every row run, `lsregister -u`
before and after):

| Mutant | Named row | Answer |
|---|---|---|
| `no-connect-first` | K4 | FAIL, caught, exit 0 |
| `no-mode-check` | K8 | FAIL, caught, exit 0 |
| `tcp-listener` | K11 | FAIL (`TCP 127.0.0.1:50225 (LISTEN)`), caught, exit 0 |
| `agent-asks` | K12, the import half | FAIL (a 20 s timeout: the question was up), caught, exit 0 |
| `open-asks` | K12, the open half | FAIL (a 20 s timeout), the import half ok, caught, exit 0 |
| `fixed-path` | K13 | FAIL (the item disabled: no helper at the fixed path), caught, exit 0; again after the review's fixes, over a non-empty clipboard, which K13 restored |

Every free proof this phase edited that drives an app, over sockets (a fresh instance per proof
for the ones that take a running instance), against its last record:

| Proof | MC4 | Last record |
|---|---|---|
| `phase1_proof.py` · `phase2_proof.py` · `phase3_proof.py` | 66/66 · 86/86 · 123/123 | 66/66 (2026-09-20, road map 7) · 86/86 · 123/123 (2026-09-22, road map 8) |
| `phase3_silence_scope.py` | 8/8 | 8/8 (2026-09-30, B22) |
| `phase4_proof.py` · `phase5_proof.py` · `phase6_proof.py` · `phase7_proof.py` | 83/83 · 88/88 · 168/168 · 92/92 | 83/83 (2026-09-24, road map 9) · 88/88 (2026-09-20) · 168/168 (2026-09-24) · 92/92 (2026-09-17) |
| `phase8_proof.py` | 79/79 (its two instances on scratch sockets) | 75/76, the ProRes decode a host skip (2026-09-29, B11) |
| `phase9_proof.py` | 218/218 | 218/218 (2026-10-01, B44) |
| `silence2_proof.py` | 100/100 | 100/100 (2026-09-30, B30) |
| `patch_door_proof.py` · `refusal_proof.py` | 261/261 · 145/145 | 261/261 (2026-09-24) · 116/116 (2026-09-22; rows added since without a record) |
| `clip_catalog_proof.py` | **0/1**: its probe does not compile (`switch must be exhaustive` over `AgentDeclaration.Requirement`, which gained `.filledByTheApp` in road map 10) — not this phase's; nothing reached the app; #214 | 24/24 (2026-09-20, road map 7) |
| `op_catalog_proof.py` · `op_argument_proof.py` | 23/23 · 153/153 (150/153 first, run beside the mutant builds: its graphics-root wait raced another instance's untitled project, as B16 recorded) | 23/23 (2026-09-29, B16) · 153/153 (2026-10-01, B44) |
| `e1_proof.py` | 89/99, exit 1: every measured row ok; the 10 cross-build rows SKIP by name, because the reference tree (`1c3e92e`) listens on TCP alone and cannot answer at a socket; #215 | 99/99 (2026-09-24, road map 9) |
| `e2_proof.py` · `mixed_audio_proof.py` | 75/75 · 13/13 | 75/75 (2026-09-30, B30) · 13/13 (2026-09-21) |
| `peaks_proof.py` | 21/21 (1/3 first: its fixtures are `peaks_probe.py`'s, made next — that probe 79/80, its one FAIL the delayed-AAC row road map 4 also recorded) | 21/21 (road map 4) |
| `relink_proof.py` · `remaining_proof.py` | 22/22 · 80/80 | 22/22 · 80/80 (2026-09-30, B29) |
| `reveal_toll_proof.py` · `target_bump_proof.py` · `video_configuration_proof.py` | capture then compare on this build both times: 6/6 · 3/3 · 2/2 then 7/7 | 6/6 · 3/3 (2026-09-25) · 2/2, 7/7 (2026-09-29, B11), each against a control build |
| `save_project_proof.py` · `close_project_proof.py` | 9 of 9 · 12 of 12 | 9/9 (2026-09-29, B14) · 12/12 (2026-10-01, B44) |
| `speech_engine_proof.py` (with its mutants) | 35/35 | 35/35 (2026-09-23, road map 8); 29/29 `--no-mutants` (2026-09-29) |
| `words_core_proof.py` · `words_picture_proof.py` | 27/27 · 7/7 | 27/27 (2026-09-29, B7) · 7/7 (2026-09-25) |
| `recording_proof.py` | 192/192, the 2 tone rows skipped by name (the output is muted); 191/192 first — the granted instance's parity log was removed with its scratch folder before the row read it, so the folder now goes at the end | 189/189 (2026-10-01, B44); 192/192 (2026-09-30) |
| `v2_snapshot.py` · `v2_menu.py` | 30 of 30 · 28 of 28 | 29 of 29 (2026-09-27, road map 11) · 28 of 28 (2026-09-30) |
| `assistant_session_proof.py` · `assistant_tab_proof.py` · `assistant_settings_proof.py` | 13/13 (W: `not bound` in a `0755` folder, `server_running` false) · 26/26 · 3/3 | 13/13 · 26/26 · 3/3 (2026-10-01, B48) |
| `assistant_compaction_proof.py --rehearse` · `assistant_prompt_proof.py --rehearse` | 8/8, 1 skipped · 25/25, 1 skipped | 8/8, 1 skipped (B48) · 18/18, 8 skipped, run without `--rehearse` (B48) |
| `spend_proof.py` · `spend_ui_proof.py` | 21/21 · 10/10 | 21/21 (2026-09-29, B15) · 10/10 (2026-10-01, B48) |
| `clip_inspector6_proof.py` | 25/25 | 25/25 (2026-10-01, B50) |
| `cloud_captions_proof.py` · `word_captions_proof.py` | 213/213 · 20/20 | 213/213 · 20/20 (2026-10-01) |
| `export_cancel_proof.py` | 7/7 in 548 s | 7/7 (2026-09-29, B13) |
| `extreme_time_proof.py` · `frame_grid_proof.py` | the pass line each, no parity complaint | the same (2026-10-01) |
| `graphics_proof.py` · `graphics_menu_proof.py` · `graphics_inspector_proof.py` | 45/45 · 16/16 · 59/59 | 45/45 (2026-09-30) · 16/16 (2026-09-29, B8) · 59/59 (2026-10-01, B50) |
| `graphics_prefetch_proof.py` · `graphics_store_proof.py` | 7/7 · 9/9 | 7/7 (2026-09-30, #127) · 9/9 (2026-09-25) |
| `screens.py` · `v3_tools.py` | 23 of 23 (22 of 23 first: P2 FAILED on three `static let …Key` literals neither pinned nor in `NOT_SHOWN` — `RC_AGENT_SOCKET` (MC2), `RCWriteCatalog` (MC3), `ReelcutGraphicPrefetchOff` (#127), two of them this road map's; all three are now in `NOT_SHOWN`, each with why no screen shows it) · 8 of 8 | 23 of 23 · 8 of 8 (2026-10-01, B49) |
| `mcp_proxy_proof.py` | 14/14 | 14/14 (2026-10-01, MC3) |

Not run: `graphics_playback_samples.py` (a sample builder with no score, hard-wired to the main
checkout's paths), the spikes, and every `--live` run.

**Owed:** AC-4 (Copy MCP Command's line in Terminal, then `claude mcp list`) and AC-5 (a
person's own import asks while an agent's export runs), with AC-1..AC-3 from MC1 and MC3. Two
proof failures are filed: `clip_catalog_proof.py`'s probe no longer compiles (#214, since road
map 10), and `e1_proof.py` can never exit 0 while its reference build listens on TCP alone
(#215, this phase's). MC5 is next: the ADR, the archive
move, the Rasterize issue, the issue for a later home for Copy MCP Command, and older proofs'
LaunchServices registrations.

### MC5 — closing (2026-10-01)

The road map is closed under root `CLAUDE.md`'s closing rule. Over `20c947d`:

- **The ADR.** `designs/adr/roadmap-14-agent-socket.md` condenses this document, with
  `designs/adr/roadmap-13-pricing.md`'s headings and a "Where to look in the original" section.
- **The move.** This document was `git mv`ed from `designs/` to `archive/roadmap-14.md`
  after this record was appended, and `archive/INDEX.md` gained its row after road map 13's.
- **The pointers.**
  - Root `CLAUDE.md`'s `designs/adr/` row lists `roadmap-14`.
  - `core/CLAUDE.md`'s `agent.rs` entry says the module now differs from Rasterize's and names
    the issue that offers the change.
  - `mcp-proxy/CLAUDE.md` and spec §7.9a now name the ADR in place of this document.
  - Spec §11's `agent-connection.md` header is worded as closed, the way `pricing.md`'s is, and
    its index row drops "in progress".
  - `tools/proof/README.md`, `tools/proof/mc1_spike/README.md` and `mc1_spike.py`'s docstring now
    name `archive/roadmap-14.md`'s MC1 record and the ADR.
- **LaunchServices, measured before filing** (read-only `lsregister -dump`; nothing unregistered):
  - 136 registrations have an identifier containing `reelcut`, 101 of them
    `com.kgalligan.Reelcut`.
  - 54 are at paths that no longer exist, 45 of those under agents' scratchpads. One of the 54 is
    this worktree's `tools/proof/work/graphics-prefetch/mutant`.
  - 82 are at existing paths, 61 of those under a `tools/proof/work/`.
- **Issues filed**, each labelled `ai-drafted` and `low-priority`. No earlier issue matched any of
  them (`gh issue list --state all --search`). The implementer's `gh issue create` was refused by
  the permission check as a write to an outside system; the owner then approved all five, and
  they were filed on 2026-10-02 from the drafted bodies.
  - kpgalligan/rasterize#430: Take Reelcut's agent-server transport: a Unix socket only, no
    TCP, and a stdio proxy (reelcut-mcp).
  - #222: A home for Copy MCP Command other than a Tools menu that holds nothing else.
  - #223: Proof build copies of Reelcut.app stay registered with LaunchServices after their
    folders are deleted.
  - #224: No proof quits Reelcut with an agent call in flight (the socket's
    release-without-join). This is MC2's owed item.
  - #225: A tree copy's "Build Rust Core" step rebuilds the tree's own core/target. This is
    MC1's side effect, which contradicts `tree_copy.py`'s docstring.

  Not refiled: #214, #215, kpgalligan/rasterize#325 and AC-1..AC-5. The TCP endpoint's missing
  `Origin`/`Content-Type` checks are not filed, by the user's choice, since MC4 removed the
  endpoint.
- No code changed, so no build was run. No app was launched, and no model or API call was made
  ($0).

**Owed:**
- AC-1..AC-5 in `docs/manual-checks.md` (the owner's).
- The owner's own client: run `claude mcp remove reelcut -s local`, then the line Tools ▸ Copy
  MCP Command gives. This is theirs to run, not an issue.
