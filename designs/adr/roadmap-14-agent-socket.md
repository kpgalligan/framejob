# Reaching the agent server (road map 14)

- **Status:** Built 2026-10-01 and closed 2026-10-02. Each phase was one litecode pipeline:
  - MC0, the decisions (`b58c458`)
  - MC1, the spike (`ffe5a9f`)
  - MC2, the socket beside TCP (`ba8ed00`)
  - MC3, `framejob-mcp` (`38b9487`)
  - MC4, TCP goes and Copy MCP Command arrives (`20c947d`)
  - MC5, the close (uncommitted when this was written)
- **Original:** `archive/roadmap-14.md` (798 lines) is the full record. It has no section numbers, so it is cited by section name: "orig Record ▸ MC1" is its "Record" section's MC1 entry.
- **Spec decisions:** MC-1..MC-6 in spec §11 (`designs/spec/11-decisions/agent-connection.md`). They stay binding, and where the original's "Decisions" section words them differently, §11's text wins:
  - MC-1: the agent server listens only on a Unix socket, `~/Library/Application Support/Frame Job/Agent/agent.sock`, always, while the app runs. There is no TCP listener and no switch.
  - MC-2: the socket is bound only in its own `0700` `Agent` subfolder. The rules for that folder:
    - The mode-and-owner check is of that folder, not of the support folder.
    - Only the first instance binds. A later instance that can connect leaves the socket alone; one that is refused unlinks the file and binds.
    - The owner unlinks it at quit.
    - A wrong mode is reported, not worked around.
  - MC-3: external clients reach Frame Job through `framejob-mcp`, a Rust stdio server inside the bundle.
  - MC-4: `framejob-mcp` never launches Frame Job to answer `initialize` or `tools/list`. It launches its own bundle with `open -n -g` on a `tools/call` that finds no socket, under a lock beside the socket. A session whose launch timed out launches no other.
  - MC-5: a tool call never raises a modal question, and a click still does. This is decided per call, where the call hands work to the importer.
  - MC-6: `RC_AGENT_SOCKET` overrides the socket path, and every proof sets it. A scratch launch also passes `-ApplePersistenceIgnoreState YES` and logs beside the socket.

## Context

Before this road map, the agent server was streamable HTTP on `127.0.0.1:4817`. It was off until Tools ▸ Allow Agent Connections or `-AgentServerEnabled YES` turned it on, and when 4817 was taken it fell back silently to a port only a log line named. An MCP client lists tools once, when it starts, so a client opened before Frame Job never saw Frame Job's tools.

The TCP endpoint also checked neither `Origin` nor `Content-Type`, so while it was on, a web page could POST a tool call to it. The user chose not to file that as an issue, because this road map removes the listener.

`AgentServerEnabled` had a second meaning: `FFmpegRewrap.canAsk` read it as "nobody is at the keyboard". Because the menu saved the same key, turning agent connections on also turned off the FFmpeg question for the person's own clicks.

Nothing had been published, so nothing migrates. (orig opening, What exists)

## Decisions

- **The socket lives in its own `0700` `Agent` folder.** MC1's S11 measured the support folder at `0755`, and `AppSupport.ensureDirectory` leaves an existing folder's mode alone (#108). A socket required to sit in a `0700` support folder would therefore never bind. A new `Agent` subfolder is made `0700`, and the check is of that folder. (MC-1, MC-2; orig Record ▸ MC1 "The support folder")
- **Connect first, then unlink only a socket that refuses.** `tiny_http` never unlinks a file before binding. Binding over a live socket, a killed instance's leftover or a regular file all fail with EADDRINUSE (S4–S6). So the app connects first: a socket that answers is left alone, and a socket that refuses is a crash's leftover and is unlinked. A file at the path that is not a socket is left alone, and nothing is bound. (MC-2; orig Record ▸ MC1 q4, ▸ MC2 "The non-socket rule")
- **The claim is the file's device and inode.** S7 found that dropping a `tiny_http` 0.12 `Server` unlinks its path unconditionally, which would delete another instance's socket bound at the same path. So `SocketClaim` records the file's device and inode, read with `lstat` after the bind. `shutdown` lets the drop run, and `release` unlinks the file, only while the claim is still current. (MC-2; orig Record ▸ MC1 S7, ▸ MC2)
- **The quit releases without a join.** `rc_agent_socket_release` unlinks the file if it is still this listener's, then abandons the listener without unblocking or joining its thread. A call in flight that waits on main therefore cannot hold up the quit. TCP's quit-join hang went with TCP. (MC-2; orig Record ▸ MC2 deviations)
- **The socket path has a 103-byte budget, and proofs' sockets live under `$TMPDIR`.** Binding at 104 bytes fails. The product path is 73 bytes, and a socket under `tools/proof/work/` reaches exactly 103, so a proof makes its socket in a `mkdtemp` under `$TMPDIR`. `start_socket` refuses a longer path by name. (MC-6; orig Record ▸ MC1 q4)
- **The catalog snapshot is written at build time by an ad-hoc-signed run of the just-linked executable.** Xcode links with `-no_adhoc_codesign`, and arm64 kills an unsigned binary (it exited 137). The "Write Agent Catalog" phase therefore runs `codesign -s - -f` on the executable in place, then runs it with `-RCWriteCatalog`; Xcode's own signing step re-signs the bundle afterwards. In the spike this cost under 1 s of a `make app`. (MC-3, MC-4; orig Record ▸ MC1 q1, ▸ MC3 "The build")
- **Lists are compared as JSON values, not bytes.** The order of keys in the catalog differs between processes (B9). A byte comparison would make the proxy send every session a false `list_changed`, and would make the proof's snapshot check fail. (MC-4; orig Record ▸ MC1 q1, ▸ MC3)
- **The launch lock is held until the poll ends, and sits beside the socket.** If the lock were released straight after `open`, a second proxy's re-check would find nothing answering yet and launch a second instance. Keeping `agent.launch.lock` beside the socket gives a proof's scratch socket a lock of its own. (MC-4; orig Record ▸ MC3 deviations)
- **A session whose launch timed out is stranded.** It launches no other instance, and its later calls answer the timeout sentence. Each session's check and launch are one critical section, after the review found two concurrent calls could both launch. (MC-4; orig Record ▸ MC3 deviations)
- **`tools/list` waits at most 5 s for the app,** then answers from the snapshot. The app serves one request at a time, so another client's long call would otherwise hold the listing up. (MC-4; orig Record ▸ MC3 deviations)
- **The launch is `open -n -g` of the proxy's own bundle.** MC1 measured about 1.1 s cold and 0.5 s warm, never frontmost, and the proxy waits up to 60 s. A scratch launch adds `-ApplePersistenceIgnoreState YES` and a `framejob-launch.log` beside the socket; a launch for the person's own socket adds neither. (MC-4, MC-6; orig Record ▸ MC1 q2, ▸ MC3)
- **MC-5 is decided per call, not per lane.** A process-wide "a call is running" flag would make a person's own MKV import refuse silently while any tool call ran. Instead, `import_media`, `relink_media` and `record_screen` pass `mayAsk: false`, `open_project` runs inside `MediaImporter.withoutAsking`, and every click passes `true`. (MC-5; orig Record ▸ MC4 deviations)
- **TCP and its switch were deleted, and Tools ▸ Copy MCP Command took their place.** MC4 deleted `rc_agent_server_start` / `_stop`, `RC_AGENT_PORT`, `AgentServerEnabled` and Tools ▸ Allow Agent Connections. The new item puts the `claude mcp add --scope user framejob -- '<bundle>/Contents/Helpers/framejob-mcp'` line on the pasteboard, with the path resolved from the running bundle. It is not an edit, so it has no MCP mirror. (MC-1, MC-3; orig Phases ▸ MC4, Record ▸ MC4) After the merge into main, issue batch B74 moved the item into a new MCP section at the top of Settings, which also shows the helper's path, and removed the Tools menu (spec §11 MC-7, #222).

## What it built — where it lives now

- The core:
  - `core/src/agent.rs` (283): `start_socket`, `SocketClaim`, `AgentServer::release` and `shutdown`.
  - `core/src/ffi_agent.rs` (160): `rc_agent_socket_start` / `rc_agent_socket_release`, in one `SOCKET` slot.
  - `core/src/mcp_versions.rs` (22): the supported protocol versions and `negotiate`, shared with the proxy by `#[path]`.
  - `core/tests/agent_socket.rs` (262).
- The proxy: `mcp-proxy/` (`session.rs` 322, `socket.rs` 214, `launch.rs` 142, `bundle.rs` 67, `lib.rs` 48, `main.rs` 7; `tests/stdio.rs` 622). Its rules are in `mcp-proxy/CLAUDE.md` (94).
- The app:
  - `AgentServer+Socket.swift` (194): the plan, MC-2's policy, the bind, the release, `mcpHelperURL` and `mcpCommand`.
  - `AgentCatalogSnapshot.swift` (51): `-RCWriteCatalog`.
  - `PropsDictionaries.swift` (109): MC2's toll from `ReelCore.swift`; main had made the same move as `OpDictionaries.swift` (#190), which the merge into main kept.
  - `AgentServer.swift` (777; frozen, so it took wiring only).
  - `FFmpegRewrap.swift` (761): `assist(_:mayAsk:)`.
  - `MediaImporter+Probe.swift` (238): `mayAsk` and `withoutAsking`.
- The build: `project.yml`'s "Build MCP Proxy" and "Write Agent Catalog" phases.
- The proofs:
  - `tools/proof/mcp.py` (284): HTTP over the socket, and the shared launcher.
  - `agent_socket_proof.py` (788): K1–K13 and the mutants.
  - `mcp_proxy_proof.py` (836): X0–X10, X7b, Z1 and Z2.
  - `pasteboard_keep.swift` (93), deleted by B74: K13 now reads Settings through `snapshot_ui` and never touches the clipboard.
  - `mc1_spike/`: the spike, with its rows in `mc1_spike/README.md`.
  - `dist_check.py` (464) D15–D24: the proxy, its runtime and no entitlements, and the snapshots' version and dev tools.

## Known limits

- **Any process running as the person can drive Frame Job while it runs, and this cannot be turned off.** A client that speaks only HTTP-over-TCP needs the proxy. (MC-1's accepted risk)
- **The assistant's `import_media` of a file AVFoundation refuses no longer asks mid-turn.** It answers with the refusal, which names the setting. (MC-5's accepted risk)
- **Refetching after `list_changed` is unmeasured.** Claude Desktop's behaviour is unknown, and Claude Code's is assumed from its documentation. AC-1 and AC-2 are the owner's checks.
- **A quarantined ad-hoc copy launched by `open` never starts, and shows no dialog** (MC1's L3). A notarized build is not measured.
- **A background launch shows a window without activating the app** (MC1's L5). AC-3 is where a person judges whether that is acceptable.
- **A timed-out launch strands its session:** that session launches nothing until the client restarts it.
- **A quit with a call in flight is not proved.**

## Open items

- #223: proof build copies of `Frame Job.app` stay registered with LaunchServices after their folders are deleted.
- #224: no proof quits Frame Job with an agent call in flight.
- #225: a tree copy's "Build Rust Core" step rebuilds the tree's own `core/target`.
- kpgalligan/rasterize#430: Rasterize takes this transport, if it chooses.
- #214: `clip_catalog_proof.py`'s probe does not compile. #215: `e1_proof.py`'s reference listens on TCP alone. kpgalligan/rasterize#325 is unchanged.
- AC-1..AC-5 are `docs/manual-checks.md` rows, for the owner.

## Where to look in the original

- What exists: the tree before the road map, including the TCP listener, the menu switch, `AgentServerEnabled`'s second meaning and the proofs' ports.
- Decisions: MC-1..MC-6 as MC0 wrote them, with MC1's `Agent`-folder amendment. §11 is the fuller text for MC-4 and MC-6.
- Phases: MC0–MC5 as planned, including MC1's four questions and each phase's planned proof and mutants.
- Record ▸ MC0: the §11 file, the index rows and §7.9c's interim paragraph.
- Record ▸ MC1: q1 (the snapshot, B1–B12), q2 (the launch, L1–L7), q3 (the client, D1 and T1–T3), q4 (the socket, S1–S10), S11 and the §11 amendment, and the side effects.
- Record ▸ MC2: `ReelCore.swift`'s toll, the core and app changes, the deviations (a separate FFI pair, release without join, the interim port rule, the non-socket rule) and the checks and mutants.
- Record ▸ MC3: the versions file, the crate, the snapshot, the build phases, `dist_check.py` D15–D24, the deviations (the lock, the stranded session, the 5 s wait, the scratch launch's extras) and the LaunchServices cleanup of road map 14's own copies.
- Record ▸ MC4: the core, app and proof changes, MC-5 per call, the deviations, the mutants, and every free proof re-run over sockets against its last record.
- Record ▸ MC5: the closing, the LaunchServices figures and the issues filed.
