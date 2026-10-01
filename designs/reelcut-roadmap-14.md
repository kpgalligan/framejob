# Road map 14 — Reaching the agent server

**An MCP client should be able to start before Reelcut does.** Today the agent server is
streamable HTTP on `127.0.0.1:4817`, off until Tools ▸ Allow Agent Connections or
`-AgentServerEnabled YES` turns it on. A client lists tools ONCE, when it starts, so a Claude
Code or Claude Desktop session opened before Reelcut has no Reelcut tools, and gets none until
someone reconnects it by hand. When 4817 is taken the app falls back to an ephemeral port that
only an `NSLog` line names, and a client pinned to 4817 then reaches whichever instance holds
it, a proof's included.

The shape, agreed with the user 2026-10-01:

- **The agent server listens on a Unix socket in the app's `0700` support folder, always, and
  nowhere else.** No TCP listener, no menu switch.
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
  `~/Library/Application Support/Reelcut/agent.sock`, and always, while the app runs.** No TCP
  listener and no switch. Only processes running as the person can reach a socket in a `0700`
  folder, and those can already read and write everything Reelcut can, so the switch guarded
  nothing a socket leaves open; TCP's only remaining users were the proofs. Risk accepted: any
  process running as the person can drive Reelcut while it runs, with no way to turn that off,
  and a client that speaks only HTTP-over-TCP cannot connect without the stdio helper.
- **MC-2 — The socket is bound only in a folder that is `0700` and owned by the person, and
  only by the first instance.** A later instance that can CONNECT to an existing socket leaves
  it alone and binds none (it logs why); one that is REFUSED treats the file as a crash's
  leftover, unlinks it and binds. The owner unlinks it at quit. A folder that is group- or
  world-accessible is reported and the socket is not bound — the folder's mode is the whole
  access control, so a wrong mode is not worked around.
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
- `rc_agent_server_start` takes a socket path (NULL for none) beside the port: Rust, header,
  `ReelCore.swift` in lockstep. TCP stays for this phase only, so every existing proof keeps
  running while the socket is proved.
- The app binds the socket at every launch (MC-1), at `AppSupport`'s folder plus
  `agent.sock` or `RC_AGENT_SOCKET`, under MC-2's rules: ensure the folder, check its mode and
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
- `agent.rs` loses the TCP listener and `rc_agent_server_start` loses the port (Rust, header,
  `ReelCore.swift`). `AgentServer` loses `port`, `defaultPort` and `enabledDefaultsKey`; its
  "is running" becomes "bound the socket".
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

Nothing has landed.
