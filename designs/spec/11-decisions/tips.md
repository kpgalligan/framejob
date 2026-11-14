# Spec §11 — decisions: Tips

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

These were made with no road map, from the owner's words of 2026-11-14: a tips dialog, a green
Tips button to the right of Export in the editor, an automatic ask on a usage-then-calendar
schedule, and a Settings section that turns the ask and the button off. The owner called the
button an experiment that may be removed. The same day, having seen it built, the owner overruled
one part: "Exports over the MCP count. That user is getting value from the app, and getting
something that other video apps don't really offer. Assuming the dialog doesn't prevent further
MCP calls, the dialog should open." TIP-3, TIP-4, TIP-5 and TIP-7 are amended in place for it,
each saying what changed, and TIP-8 is new.

- **TIP-1 — A tip is voluntary, nothing in Frame Job is gated on one, and the app holds no payment
  code: the dialog says who a tip funds and opens one web page.** The statement is plain: Frame
  Job is made by one developer, it is free to use and its source is open, a tip helps pay for the
  time to keep working on it, and nothing is locked without one. "Leave a Tip" opens
  `https://boppallewyn.com/frame-job/tips/` in the person's browser, and that address is ONE
  constant (`TipsLink.url`, `Tips.swift`), so moving the page is a one-line change. The page is
  the owner's to make. Frame Job never learns whether anyone tipped, so there is no "thank you"
  state and nothing to restore. Risk accepted: until the page exists the button opens a missing
  page.
- **TIP-2 — The dialog is its own small window titled "Tips", not a sheet and not an app-modal
  alert, and it has three doors: the editor's Tips button, Settings' Tips button and the automatic
  ask.** A sheet needs a host window and two of the doors have no document (Settings, and Settings
  opened from the Welcome window); an app-modal alert would stop every window and would sit in
  front of an MCP client's calls. A window that is modal to nothing cannot make anything wait. It
  is the Settings window's mould (`TipsWindowController`): one instance, not released when closed,
  no frame autosave name (so it writes no `NSWindow Frame` key), built from the sheets' own pieces
  (`makeSheetView`, `makeButtonRow`) so it reads as one of them, Escape on "Not Now" and Return on
  "Leave a Tip". It is left out of the Window menu: a two-button dialog is not a place to come
  back to, and both buttons reopen it. There is no menu item for it, and no MCP mirror, because
  showing it is not an edit (spec §7.9).
- **TIP-3 — The automatic ask is due by usage first and the calendar after: never while the
  toggle is off; first once at least 5 exports are counted AND at least 30 × 24 hours have passed
  since the first counted export; after an ask, only in a December, and a December is skipped
  whole when its 1 December 00:00 is less than six calendar months after the last ask.** The rule
  is one pure function, `TipsSchedule.isDue(_:now:calendar:)`, over the stored state, the moment
  and a calendar. "30 days of use" counts from the first counted export and not from the first
  launch: a launch is also what every proof makes, and a copy that was opened and never exported
  from has not been used (amended 2026-11-14 with TIP-4: this read "a date stamped at launch
  would count use by agents alone", and an agent's export is use now). It is elapsed time, not
  thirty separate days of use, which would make an occasional user wait a year. "December" is month 12 of the GREGORIAN calendar in
  the Mac's current time zone (`TipsSchedule.localCalendar()`, built at each evaluation), whatever
  calendar the person's Mac shows, so the same instant can be December in Auckland and November
  in Los Angeles. A December is judged whole so that an ask on 30 June cannot bring the next one
  on 30 December: a last ask after 1 June 00:00 skips that year's December, and one at or before
  it does not. A clock set back before the last ask or the first export makes nothing due. Risk
  accepted: the rule is evaluated only when a counted export completes (TIP-4), so a person who
  exports nothing in December is not asked that year.
- **TIP-4 — Every export that completes in a person's instance (TIP-8) counts, whoever started
  it, and its completion evaluates the ask: the export card's two commits, an MCP client's
  `export` and the Assistant's `export` (amended 2026-11-14, the owner: "Exports over the MCP
  count").** Before the amendment only an export a person confirmed in the export card counted,
  the agent's `export` was never followed, and an instance driven only by an agent was never
  shown the dialog; the owner overruled that because a person whose agent exports for them is
  using Frame Job, and in a way other editors do not offer. The card's two commits are Export…
  (`EditorViewController.beginExport`), which hands the progress sheet an `onSuccess` it calls
  once, on a success only, and Add to Queue (`enqueueExport`), which follows its job by the id
  `enqueue` answered (`TipsQueueFollower`, `AgentExports`' pattern). The agent's `export`
  (`AgentServer.exportProject`) enqueues on the same queue and follows its job through the same
  `TipsDoors.follow(queueJob:)`, and the Assistant tab's `export` is that same handler, so there
  is one line for both callers, `ExportQueueController` is not changed and its jobs carry no
  origin. A counted export is counted when it succeeds; a cancel, a failure and a call the tool
  refused count nothing. The ask is evaluated, and recorded, at the moment it is shown: for
  Export…, when the result sheet ends (Close or Show in Finder), one main-queue turn later; for a
  queued job, a person's or an agent's, when it completes. The automatic ask is ordered front
  WITHOUT becoming key, so a Return typed into the editor can never press "Leave a Tip"; the two
  buttons' doors make it key. **It never makes a tool call wait:** the window is modal to nothing
  (TIP-2) and a queued job's ask runs from the queue's own notification, outside every call and
  outside the agent lane's lock, so `export_status`, the next `export` and every other tool
  answer as they did. What keeps a proof's exports from counting is not the door any more but
  the instance (TIP-8). Risks accepted: after Show in Finder the dialog appears behind Finder and
  is found on return; a window closed with its result sheet still attached never ends that
  sheet, so that export is counted and the ask waits for the next one; Frame Job is usually in
  the background when an agent's export ends, so the dialog waits there without bringing Frame
  Job forward, and when the person comes back it may be the window that becomes key, where
  Return is "Leave a Tip"; a client that exports in a loop is asked once, at the export that
  made it due.
- **TIP-5 — The state is four keys of the bundle's defaults domain, and no export in a scratch
  instance writes one (TIP-8): an export writes only when it succeeds in a person's instance,
  whoever started it, and the dialog's and Settings' own controls write wherever a person
  presses them (amended 2026-11-14 with TIP-4: this read "written only at a person's
  doors").** Only the two export doors ask TIP-8's rule; "Leave a Tip" and Settings' checkbox
  do not, being presses no tool can make. `FrameJobTips` (Bool, absent means on) is the toggle, written by Settings' checkbox.
  `FrameJobTipsExports` (Int) and `FrameJobTipsFirstExport` (a date, stamped once) are written
  when a counted export succeeds, and counting goes on while the toggle is off, so turning it back
  on behaves sensibly. `FrameJobTipsLastAsked` (a date) is written when the automatic ask is shown
  and when "Leave a Tip" is pressed from any door: someone who has just visited the page is not
  asked again that December. Opening the dialog by hand and choosing "Not Now", or closing it,
  writes nothing. Dates are stored as dates, so `defaults write … -date` sets one. No project
  format changes. Risk accepted: the state is per Mac and per build identity, so a Debug build
  and a reinstall on another Mac each start again.
- **TIP-6 — The editor's Tips button is an `AccentButton` filled with `DS.tips` (`#2E7D32`), right
  of Export…, and Settings ▸ Tips holds the toggle that removes it.** The owner asked for green.
  The fill is a fixed leaf green, the same in both appearances as the recorder's coral Record
  button is, with the white `DS.onAccent` label at 5.1:1. It is deliberately not `DS.action` and
  not `DS.forest`: CI-4 keeps mint for the action ink and nothing else, and forest (`#1F8564`) is
  within 10/255 of the action ink's light value (`#1E8F6E`), so a forest button would read as an
  action in the light appearance. `DS.tips` sits about 40° of hue from both action values, so
  CI-4 stands unamended. How it looks is a row in `docs/manual-checks.md`. The button is 12 pt
  after Export… with no rule between them, has no symbol, and is `TipsToolbarButton`, a view that
  hides itself while the toggle is off and follows `TipsSettings.didChangeNotification`, so the
  frozen editor file holds nothing for it: removing the experiment is deleting that file and one
  line of `buildToolbar`. Settings' fifth and last pane, "Tips", is a bare heading, one visible
  sentence (under SH-5's and `settings_layout_probe` L5's 200 characters, so it needs no ⓘ), the
  checkbox "Show the Tips button and the yearly reminder" (on by default) and a "Tips" button.
  Unticking stops the automatic ask and removes the button from every open editor at once; the
  pane's own button is never hidden or disabled and shows the dialog whatever the toggle says. It
  is a person's setting: no tool reads or writes it (R6-12, MC-7).
- **TIP-7 — The feature has one `-RCDev` switch, `-RCDevTipsSuite <name>`, and no dev tool; its
  proof is a probe and, for what only the running app can show, four instances over MCP
  (amended 2026-11-14 with TIP-4: this read "no `-RCDev` switch", and the mutants were twelve).**
  `tools/proof/tips_proof.py` builds `tips_probe.swift` over `app/Sources` and hands the schedule
  its clock, calendar and a scratch defaults store; the export doors are run for real, on a
  document made in process, with the ask, the window, the queue and the instance rule injected
  (`TipsDoors`), the agent's among them through `AgentServer.exportProject(_:tips:)`, and the
  window's two order calls are closures so "front, not key" can be read where no probe window is
  ever key. A person pins state with `defaults write` (`docs/manual-checks.md`). **The switch**
  exists because a counted agent export on the running app, with the window really ordered and
  the next call really answered, cannot be seen without writing some defaults domain, and it
  must not be the bundle's: under `-RCDevTipsSuite <name>` (a build with the dev tools only, so
  never Distribution) the three counting keys are read and written in the named suite and the
  instance counts whatever its socket (TIP-8). One switch does both on purpose, so counting can
  never be turned on in a proof's instance while the state is still the bundle's. The name must
  start with `framejob.`, the prefix `proof_defaults.py` owns and removes; any other name, or a
  suite that cannot be made, is named on stderr and ignored whole, and the instance stays as
  TIP-8 judged it. It has no `dist_check.py` row: it widens nothing a person could reach, and
  the seam's own needle (D1–D5) is what proves dev code is out of Distribution. The offscreen
  harness pins `FrameJobTips` OFF: older chrome proofs read the toolbar at fixed points
  (`sharp_chrome.py`'s `EXPORT_RIGHT`, `phase7_chrome.py`'s accent patch) and a button right of
  Export… would move them; `screens.py` pins it ON, the first-run state the catalog shows, and
  lists the other three keys and the switch in `NOT_SHOWN`. The proof's live instances launch
  with `-FrameJobTips YES` or `NO`, so the owner's own toggle never decides a row. It holds
  nineteen mutants, nine past the usual ten, because the feature holds nineteen separable
  decisions and dropping one would leave a decision no row is seen failing for: the first
  eleven of the original twelve (two thresholds, the toggle, the month, the skip, the recorded
  ask, which queue states count, the button's and the pane's halves of the toggle, the success
  wiring and the order call; the twelfth, "the agent's door follows", guarded the decision TIP-4
  reversed and is gone), and eight for the amendment: the agent's door following its job, the
  two conditions of TIP-8, the process's own environment being what is judged, the rule being
  the doors' default, each of the two doors asking it, and the ask running no modal session. A
  mutant is a probe rebuild and never runs a row against the app, so none can write a real
  domain.
- **TIP-8 — A scratch instance counts nothing and asks nothing, from any door: an instance is a
  person's only when it runs from an app bundle and `RC_AGENT_SOCKET` is unset or empty.** The
  reason TIP-4 first excluded the agent's door still stands for the proofs: they export over MCP
  constantly and share the bundle's defaults domain, the owner's real one for a Release proof
  (#238), so they must not count, must not move the owner's Tips state, must not trip `mcp.py`'s
  `DEFAULTS MOVED` guard and must not put a Tips window into a capture. The rule is one pure
  function, `TipsInstance.counts(environment:bundleIdentifier:)`, read once for the process
  (`TipsInstance.isPersons`) and asked by both of `TipsDoors`' doors before anything is followed,
  counted or asked, so it is a rule about the instance and not about who started the export.
  **The socket variable** is the mark of a proof's instance because it cannot be forgotten: MC-6
  keeps every proof off the person's socket, so an instance a proof can reach is one it gave
  `RC_AGENT_SOCKET` (`mcp.launch` sets it on every launch, and every proof that starts the app
  itself does), and the helper already calls that a scratch instance and launches it differently
  (`mcp-proxy/src/launch.rs`). Empty reads as unset, as `AgentServer.socketPlan` reads it.
  Nothing a person does sets it by accident: Copy MCP Command writes no environment, and the
  helper passes the variable to the app only when its own environment holds it, which the site
  documents as testing a second copy. **The bundle** is the mark of a probe or the harness,
  which run the app's code in a bare executable with no bundle identifier and so count nothing
  even when they reach a door in process (`assistant_lane_probe.swift` submits `export`). It is a
  product rule and not a `-RCDev` switch: Distribution judges itself the same way, where it
  means a test copy on its own socket is not counted. A relocated home (`CFFIXED_USER_HOME`) is
  deliberately NOT a condition: macOS sets it in sandboxed processes, `open` hands an app its
  caller's environment, so a person whose MCP client is sandboxed would silently never be
  counted, and no proof needs it, since every proof launch of a real bundle that sets the home
  sets the socket too. The loud backstop is unchanged: a proof instance that did count would
  write `FrameJobTipsExports`, and `mcp.py`'s guard ends that script with status 3. Risks
  accepted: a person who runs their everyday copy with `RC_AGENT_SOCKET` set is never counted or
  asked, not even for an Export… of their own in that copy; a probe built as a bundle with an
  identifier of its own would count into its own domain, never the app's, if it ever ran a door.
