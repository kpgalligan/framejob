# Spec §11 — decisions: Tips

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

These were made with no road map, from the owner's words of 2026-11-14: a tips dialog, a green
Tips button to the right of Export in the editor, an automatic ask on a usage-then-calendar
schedule, and a Settings section that turns the ask and the button off. The owner called the
button an experiment that may be removed.

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
  launch: a launch is also what `framejob-mcp` and every proof make, and a date stamped at launch
  would count use by agents alone. It is elapsed time, not thirty separate days of use, which
  would make an occasional user wait a year. "December" is month 12 of the GREGORIAN calendar in
  the Mac's current time zone (`TipsSchedule.localCalendar()`, built at each evaluation), whatever
  calendar the person's Mac shows, so the same instant can be December in Auckland and November
  in Los Angeles. A December is judged whole so that an ask on 30 June cannot bring the next one
  on 30 December: a last ask after 1 June 00:00 skips that year's December, and one at or before
  it does not. A clock set back before the last ask or the first export makes nothing due. Risk
  accepted: the rule is evaluated only when a counted export completes (TIP-4), so a person who
  exports nothing in December is not asked that year.
- **TIP-4 — Only an export a person confirmed in the export card counts, and only its completion
  evaluates the ask; the agent's `export` never does either.** The card's two commits both sit
  behind its save panel (`ExportSheetCommit.swift`), which no tool and no dev switch answers:
  Export… (`EditorViewController.beginExport`) and Add to Queue (`enqueueExport`). The first hands
  the progress sheet an `onSuccess` it calls once, on a success only; the second follows its job
  by the id `enqueue` answered (`TipsQueueFollower`, `AgentExports`' pattern), so
  `ExportQueueController` is not changed and its jobs carry no origin. The agent's `export`
  enqueues on the same queue and is never followed, and the Assistant tab's `export` is that same
  door. So an instance driven only by an MCP client, the assistant or a proof counts nothing,
  writes no key and is never shown the dialog, which is what keeps `mcp.py`'s `DEFAULTS MOVED`
  guard quiet. A counted export is counted when it succeeds. The ask is evaluated, and recorded,
  at the moment it is shown: for Export…, when the result sheet ends (Close or Show in Finder),
  one main-queue turn later; for a queued job, when it completes. The automatic ask is ordered
  front WITHOUT becoming key, so a Return typed into the editor can never press "Leave a Tip";
  the two buttons' doors make it key. Risks accepted: after Show in Finder the dialog appears
  behind Finder and is found on return; a window closed with its result sheet still attached
  never ends that sheet, so that export is counted and the ask waits for the next one.
- **TIP-5 — The state is four keys of the bundle's defaults domain, written only at a person's
  doors.** `FrameJobTips` (Bool, absent means on) is the toggle, written by Settings' checkbox.
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
- **TIP-7 — The feature has no `-RCDev` switch and no dev tool, and its proof is a probe.**
  `tools/proof/tips_proof.py` builds `tips_probe.swift` over `app/Sources` and hands the schedule
  its clock, calendar and a scratch defaults suite; the two export doors are run for real, on a
  document made in process, with the ask, the window and the queue injected (`TipsDoors`), and the
  window's two order calls are closures so "front, not key" can be read where no probe window is
  ever key. A person pins state with `defaults write` (`docs/manual-checks.md`). So Debug, Release
  and Distribution run the same code. The offscreen harness pins `FrameJobTips` OFF: older chrome
  proofs read the toolbar at fixed points (`sharp_chrome.py`'s `EXPORT_RIGHT`,
  `phase7_chrome.py`'s accent patch) and a button right of Export… would move them; `screens.py`
  pins it ON, the first-run state the catalog shows, and lists the other three keys in
  `NOT_SHOWN`. The proof's live instances launch with `-FrameJobTips YES` or `NO`, so the owner's
  own toggle never decides a row. It holds twelve mutants, two past the usual ten, because the
  feature adds twelve separable decisions (two thresholds, the toggle, the month, the skip, the
  recorded ask, which queue states count, the agent's door, the button's and the pane's halves of
  the toggle, the success wiring and the order call) and dropping one would leave a decision no
  row is seen failing for.
