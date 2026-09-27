# Spec §11 — decisions: Dev tools (road map 11)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **V-1 — Dev tools are compiled only under `REELCUT_DEV_TOOLS`, and the shipping build is
  the Distribution configuration, which does not set it.** Debug and Release set the flag;
  `make app` builds Release, so every proof and agent session has the tools, and the binary
  that is verified is the optimised one rather than a Debug build that only resembles it. A
  compile-time flag rather than a launch flag, because the user does not want the code shipped
  at all, not merely switched off. `make dist` checks that the tools' names are absent from the
  Distribution binary and present in the Release one, and fails otherwise. The agent server
  itself (§7.9) is a product feature and stays in every build; only the dev tools go. Risk
  accepted: the flag-off path is compiled by `make dist` alone, not by `make typecheck`.
- **V-2 — A dev tool is not an op and not a user-visible edit, but it is an ordinary tool.** It
  has no UI path to mirror, so the agent-parity rule asks nothing of it; it goes through the same
  catalog, handler table, argument gate and startup parity check as every product tool, merged
  in from `AgentServer+DevTools.swift` so the frozen `AgentServer.swift` takes wiring only.
- **V-3 — Screens are captured with `cacheDisplay(in:to:)`, never ScreenCaptureKit or
  `screencapture`.** No Screen Recording grant — which an ad-hoc-signed rebuild may lose, and
  which the agent's terminal does not have — so a capture never waits on a person. What that
  path cannot draw (the player layer, Metal) is filled from `render_frame`'s picture and the
  result says so; the capture is a picture of the chrome, and pixel claims about the VIDEO stay
  with `render_frame`.
