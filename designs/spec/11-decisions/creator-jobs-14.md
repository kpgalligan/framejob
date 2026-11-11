# Spec §11 — decisions: Creator jobs, Find's ⌘Return onward (road map "creator-jobs", from 2026-11-12)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs-13.md`](creator-jobs-13.md), so a citation never has
to say which file. This file is new because `creator-jobs-13.md` reached 499 lines, at the spec's
~500-line split rule. It is the series' newest file: each new decision is appended here, before its
code; `creator-jobs.md` says what the road map builds and how its IDs are made (CJ-7).

## Find's ⌘Return, ⌘F on the Media tab, and on-device word ends (#559, #560, #442, 2026-11-12)

Recorded before the code. The owner decided all three on 2026-11-12 ("go with your
recommendations"): #559's and #560's first options, and #442's third.

- **TX-43 — ⌘Return in the Transcript tab's find field selects the current match, as a click on
  its word does.** The match's whole token range becomes the selection (a match inside a word
  selects that word, a phrase every word it touches), told as a person's selection, so TX-31
  widens it and makes its cut the in/out range. The playhead goes to the match's first word, by
  the click's seek (TX-22: playback goes on if it was playing). The transcript's text takes the
  keys, so ⌫ is Delete Words at once (TX-31) and the arrows move from the selection. The bar stays
  open with its marks, its current match and its anchor: the first Esc clears the selection and
  the next closes the bar (TX-37 (e)), and `openedFromText` is not changed, as a click does not
  change it. With no current match (an empty field, or "No matches") it beeps and the field keeps
  the keys. Exactly ⌘ is held, with ⇪ and the keypad and fn flags allowed, so ⌘ with keypad Enter
  does the same; ⌘⇧Return, ⌥Return and ⌃Return are left to AppKit. Never while an input method
  has marked text, never with a sheet attached. Return and ⇧Return still step and select nothing.
  **Where it is decided:** `TextFocus.keptReturn` answers which of the field's three kept Returns
  a key is (`KeptReturn`: next, previous, select), and the editor window asks it at two doors —
  `performKeyEquivalent(with:)`, for ⌘Return only, because `NSApplication` offers a ⌘ key-down to
  the key window's key equivalents and then to the menus before it dispatches the key through
  `sendEvent`; and `sendEvent`, for all three, as before. A key taken at one door is spent there,
  so it is never handled twice; no menu item and no view in the window has ⌘Return as its key
  equivalent. Which door a running app reaches first is not something a script here can watch
  (the probe's window is never key and its app never active), so both take it, and JOB-67 is the
  real key's check. ⌘Return was free in the field: K-4 (3) leaves ⌘ to AppKit and nothing else
  takes it. **No MCP mirror:** the selection, the range and the playhead are view state, which
  `set_range` and `set_playhead` already reach. Amends TX-37 (d) ("to act on a match the person
  clicks its word": ⌘Return does it too) and (e), and K-4 (3)'s exception (the find field keeps
  ⌘Return as well).
- **TX-44 — `transcript_view`'s `find_step` takes `"select"`.** ⌘Return's path (the pane's
  `findSelect()`), once, after `find`; refused while the bar would be closed, as `next` and
  `previous` are. The argument set is unchanged; the refusal of an unknown step names all three.
  Amends TX-38.
- **TX-45 — Edit ▸ Find… (⌘F) gives the keys to the Media tab's search field while that tab
  shows.** One item, one title, "Find…", decided by which tab shows: the Transcript tab opens its
  find bar (TX-37, unchanged); the Media tab makes its Search by name field first responder with
  its whole text selected, and pressed again selects the text again; on the Clip, Document and
  Assistant tabs, and with a sheet attached, the item stays disabled. The Media arm is offered
  only while the field is on screen: the inspector not hidden, the Media tab showing, the project
  holding media (with none the find band is not built, spec §4.3c) and the Media section open. A
  shut section keeps the item disabled rather than opening it, because whether it is shut is the
  person's saved preference; Find never switches tabs either. The field is scrolled into sight in
  the inspector. The hand-back is K-4's, unchanged: Return and a click outside give the keys to
  the content view, Tab as K-4 (2) says, and Esc empties the field (`MediaSearchField`'s own
  rule). **No MCP mirror:** the search is view state, as TX-37's bar is. The selector stays
  `findInTranscript(_:)` and its validator `validateTranscriptAction`: the frozen
  `EditorViewController.swift`'s validator line, `UIMenuTable.swift`, the menu inventory and the
  proof's mutants name them, and a rename buys nothing a comment does not say. The pane is found
  through a static table keyed by the inspector, `TranscriptPane`'s shape, because
  `InspectorViewController.swift` is frozen. Amends TX-37's first sentence ("enabled while the
  window's Transcript tab shows").
- **TX-46 — On-device word ENDS are the recogniser's: a known limit.** TX-19 moves an on-device
  word's start to where its sound begins (TX-15) and leaves its end where the recogniser put it.
  Measured on TX1b's fixtures, a synthetic voice (`word_onset_proof.py` O7, against each phrase's
  last sample over −40 dBFS): ends up to 227.5 ms late (`pause.wav`: dog +227.5, jugs +168.7,
  jump +137.9, vow +36.4 ms) and 315 ms early (`page.wav`, phrase 74, "afternoon."). TX-30 caps a
  word cut at the last deleted word's end plus 1 s, so an early end puts the cap early: deleting
  "afternoon." left 210.8 ms of pause before "Turn" (C1, reported, not scored), the one gap of
  101 past TX-19's acceptance of 0.2 s, by 10.8 ms. A late end lets the cut run that much further
  into the pause, never past the next kept word's start. **Not fixed now (the owner):** the error
  is measured on a synthetic voice only, and the same spike's real-speech rows, S-TH1 and S-RT1,
  are owed. If real speech shows it, the fix is to move ends by the evidence that moved starts
  (the last speech cell's end, refined on the peaks), not to measure the cap from the next word's
  moved start, because the pause token (TX-34) and on-device caption timing read the same ends;
  it needs its own measurement, as the starts did. Until then the site says that an on-device
  word's end is the recogniser's, so a little more or less of a long pause can stay than the
  one-second rule suggests, and JOB-11 is where the owner hears it on S-TH1. No code. Amends
  nothing: TX-19 and TX-30 stand, and their index rows point here.
- **TX-47 — The proof.** `tools/proof/transcript_find_proof.py` with `transcript_find_probe.swift`,
  Find's instrument since TX-39, over the app's own editor window, keys through the window as
  TX-39 says. Probe row **F17**, ⌘Return, each letter's verdict in its detail: (a) offered as
  `NSApplication` offers it, `window.performKeyEquivalent(with:)` answering true — the current
  match selected, the playhead at its first word, the in/out range set, the transcript's text
  first responder, the bar open with the same current match and count; (b) through `sendEvent`
  alone, the same; (c) a phrase, every word selected and the playhead at the first; (d) part of
  a word, the whole word; (e) no match, nothing moved and the field keeping the keys; (f) ⌘⇧Return
  taken at neither door, nothing selected; (g) the first Esc clears the selection and the next
  closes the bar, and after another ⌘Return ⌫ makes one "Delete Words". F4 stays the guard that
  Return and ⇧Return select nothing. Probe row **F18**, ⌘F on the Media tab: (a) the validator
  false on Clip, Document and Assistant and true on Media and Transcript; (b) after a name was
  typed and the keys handed back, the action makes the field's editor first responder with its
  whole text selected, and again from a caret at the end; (c) typing there narrows the list; (d) Return hands the keys to the content
  view and Space then plays; (e) with the Media section shut — set as a volatile argument-domain
  default, so the probe writes no preference — the validator is false and the action beeps
  without moving the keys; (f) the same with the inspector hidden — its container hidden
  directly, not by Hide Inspector, which writes a default; (g) with the field scrolled out of the
  inspector's sight, the action brings it back into sight. App rows: A1 also finds the item
  disabled on the Document tab; **A6** `find_step: "select"`: the answer's selection the current
  match, the view first responder and the field not, the current match unchanged, the playhead
  where a click on the match's first word puts it, the in/out range set where there was none,
  the project unedited, and the step refused with the bar closed; **A7** the item disabled on the Media tab
  of an empty project and run on the Media tab of one with media; Z0 also reads `find_step`'s
  enum as next, previous and select. **Mutants**, one per decision, each read by the letters it
  fails: #559's seven, `command-return-untaken` (F17 a–d, g), `key-equivalent-door-shut`
  (F17 a), `send-event-door-shut` (F17 b), `shifted-command-taken` (F17 f), `select-keeps-keys`
  (F17 a–d, g), `select-no-seek` (F17 a–d, g) and `select-first-word-only` (F17 c); #560's four,
  `media-arm-off` (F18 a), `media-find-unshown` (F18 e, f), `media-find-no-focus` (F18 b, c, g)
  and `media-find-no-scroll` (F18 g). Eleven, over the root rule's ten for one change because two
  issues' decisions share the instrument, which now carries forty-five with TX-39's thirty-four.
  JOB-67 adds a real ⌘Return and a real ⌘F on the Media tab. #442 has no row: its checks are
  `spec_index_proof.py` and `docs_site_proof.py`. Amends TX-39.
