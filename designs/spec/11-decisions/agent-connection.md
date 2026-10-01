# Spec §11 — decisions: Reaching the agent server (road map 14)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is in progress: `designs/reelcut-roadmap-14.md`, whose
"Decisions" section words them and whose "What exists" section holds the tree they change.

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
- **MC-3 — External MCP clients reach Reelcut through `reelcut-mcp`, a stdio server inside the
  bundle.** It is the one supported client configuration; `README.md` gives the command. A Rust
  binary (no AppKit, no runtime to install), not the app's own binary run with a flag.
- **MC-4 — `reelcut-mcp` never launches Reelcut to answer `initialize` or `tools/list`.**
  Opening an MCP client must not open a video editor. It answers `tools/list` from the running
  app when there is one and from its bundle's catalog snapshot when there is not, and launches
  its OWN bundle, in the background (`open -n -g`), on the first `tools/call` that finds no
  socket — including after the person quits Reelcut mid-session. Two proxies that both find no
  socket launch one instance between them (a lock in the support folder).
- **MC-5 — A tool call never raises a modal question; a click still does.** "Nobody at the
  keyboard" stops being a launch-wide flag and becomes a property of the call: while the lane is
  running a tool call (`AgentLane`, which already tracks it), `FFmpegRewrap`'s `ask` means no
  and the stored policy decides alone, exactly as under `-AgentServerEnabled YES` today;
  `-RCFFmpegImport always` stays the way a scripted run asks for the conversion. This also
  covers a background-launched instance (MC-4), where an alert would bounce in the Dock with the
  agent's call held behind it, and it removes the persisted-switch wrinkle (road map 14, "What
  exists"). Risk accepted: the assistant's `import_media` of a file AVFoundation refuses no
  longer asks the person mid-turn; it answers with the refusal, which names the setting.
- **MC-6 — `RC_AGENT_SOCKET` overrides the socket path, and a proof always sets it.** No proof
  binds or deletes the person's socket, and `reelcut-mcp` honours the same variable, passing it
  to a Reelcut it launches (`open --env`), so a proof can drive the proxy against a scratch
  instance. Until MC4, a launch that sets `RC_AGENT_PORT` and not `RC_AGENT_SOCKET` binds no
  socket, because every proof of the era sets `RC_AGENT_PORT` and would otherwise bind the
  person's; MC4 deletes this rule with `RC_AGENT_PORT`.
