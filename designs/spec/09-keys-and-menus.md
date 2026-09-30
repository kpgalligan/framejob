# 9. Keyboard map and menus

| Keys | Action |
|---|---|
| Space | Play / pause — from any focus but a field being typed into (§11 K-1) |
| J / K / L | Reverse / pause / forward; L again for 2×, 4× |
| ← / → | Previous / next frame (⇧: 10 frames) |
| ↑ / ↓ | Previous / next edit point |
| Home / End | Start / end |
| ⌘T | Split at playhead |
| W / E | Trim start / end to playhead |
| ⌫ | Delete the selection, leaving a gap — or LIFT the in/out range when nothing is selected. With an action selected (§11 CI-1) it removes THAT action instead |
| esc | Leave the selected action (§11 CI-1) — the Clip tab's fields go back to the clip's base props. With no action selected the key is not consumed |
| ↩ (canvas text editor) | Apply the text and leave the editor; ⇧↩, ⌘↩, ⌥↩ or ⌃↩ insert a new line (§11 K-2) |
| esc (canvas text editor) | Leave an unchanged edit; with the text changed, ask Cancel / Revert / Apply (§11 K-2) |
| esc (timeline rename field) | Close the field and keep the old name; no undo step. Return, Tab or a click elsewhere commits, as its own undo step even when that click also edits |
| esc (canvas drag) | Cancel the drag in progress — move, scale, rotate, crop, endpoint or region grip: the project goes back to the press's state, with no undo step (§11 CI-16) |
| ⌘⌫ | Ripple delete (selection, or the in/out range) |
| ⇧⌘F | Freeze frame |
| ⌥⌘D | Detach audio |
| ⌥⌘K | Add action at playhead |
| M | Add marker |
| I / O / ⌥X | Set in / set out / clear range |
| N | Toggle snapping |
| T | Add text clip at playhead |
| C | Crop mode on the selected clip |
| Z | Region mode on the canvas — drag a rectangle over the selected clip to zoom to it (⇧ fills instead of fits), Esc cancels. Z again disarms it, and so does moving the selection: one key in and out, because a modal overlay that has lost focus can no longer be dismissed by Esc |
| ⇧Z | Fit timeline |
| ⌘= / ⌘- / ⌘0 | Zoom in / out / fit (canvas, or timeline when focused) |
| ⇧⌘N | New track |
| ⇧⌘I | Add media… |
| ⌘G / ⇧⌘G | Nest / un-nest (M3) |
| ⌘↓ / ⌘↑ | Open / close nest (road map 2's phase 9) — go inside the selected nest clip, and come back OUT one level. Two items rather than one toggle, unlike ⇧⌘P: in and out are different distances, since a stack can be eight deep, so a single checkmarked row could not say what it would do |
| ⇧⌘R | Rename the selected clip — an inline field over its name strip |
| ⌥⌘V | Paste Attributes — the copied clip's look onto the selection |
| ⌘E | Export… |
| ⌥⌘E | Save Frame… — the frame under the playhead as a PNG, JPEG or HEIC still (road map 2's phase 7a). Export…'s still-image sibling, under the same letter |
| ⌥⌘N | New Recording… — the recorder panel (road map 3). The same item reads Stop Recording while one runs, paused included, and stops it; a nil-target action on `AppDelegate`, so it resolves with no document open, as New Project does. Pause Recording and Resume Recording are the status item's rows (R2) and File ▸ Pause Recording, directly under this item, retitled Resume Recording while paused, with no key (#98) |
| ⌘, | Settings… — Reelcut ▸ Settings…, the app's one window for something PERSISTED beyond view state (road map 6 §5d): two panes, "Transcription", holding the AssemblyAI key, the region and a Verify button, and under it "Assistant" (road map 12 A2), holding the Anthropic key and the model (§11 AI-8, AI-11) with no Verify. macOS's own place for the item and its own key; the nudge pair below is the BARE `,` and `.`, so nothing is displaced. A nil-target selector on `AppDelegate`, so it resolves with no document open, as New Project does |
| ⌥⌘I | Toggle inspector |
| ⌃⌘A | View ▸ Assistant — show the inspector, pick its Assistant tab and focus the composer (road map 12 A2, §11 AI-4). ⌘A is Select All and ⌥⌘A Deselect All; ⌃⌘A was free. Not a toggle: pressed on the Assistant tab it only refocuses the composer |
| ⇧⌘P | Preview Window — a second window showing the same picture as the canvas, with no overlay (road map 2's phase 8b). A TOGGLE: the item carries a checkmark and the key both opens the window and puts it away |
| `,` / `.` (⇧ ×10) | Nudge the selection one frame |
| ⌥-drag clip | Duplicate |
| ⌥⇧-drag clip | Slip — the source under a fixed clip |
| ⌥-drag clip edge | Rate stretch |
| ⌥⇧-drag clip edge | Roll — the hard cut that edge sits on |
| Double-click an empty lane span | Close that gap |
| Double-click a clip | Rename it in place — EXCEPT a nest clip, which opens (road map 2's phase 9); rename it with ⇧⌘R, Clip ▸ Rename… or the Clip tab's header field |
| Click the breadcrumb | Come out one level, while a nest is open — the corner over the track headers, which is inert otherwise |
| ⌥-drop / ⇧⌥-drop from the Media tab | Insert / overwrite at the drop |
| ⌥-click a track header | Select every clip on that track |
| ⌘-drag | Suppress snapping |

**Proposed, not yet bound** — the keys `archive/reelcut-roadmap-2.md` asks
for, kept here so a phase that binds one checks this table for a conflict
first and then promotes its row into the one above. A row here is a claim on
a key, nothing more.

| Keys | Action | Phase |
|---|---|---|
| — | Nothing. Phase 9 took the ⌘↓ / ⌘↑ this table claimed for it, for Clip ▸ Open Nest and Clip ▸ Close Nest, and the row has been promoted into the bound table above. Carrying a modifier does NOT keep either off the first responder — every main-menu key equivalent is offered the key-down before the window dispatches it, and what a modifier changes is only WHICH field-editor binding it displaces (here `moveToBeginningOfDocument:` / `moveToEndOfDocument:`). So the pair is validated DEAD while text is being edited, the Delete pair's precedent — otherwise ⌘↑ in an inline rename would leave the nest and discard the open field | — |

Menus: Reelcut (About Reelcut, Settings… ⌘, — road map 6 §5d's window, in a
separator group of its own between About and Hide, which is where macOS puts
one; a WINDOW and not a sheet, because the key and the region belong to the
person rather than to a document and the item has to work with no document
open, Hide Reelcut, Hide Others, Show All, Quit Reelcut),
File (New Project, New Recording… (road map 3 — directly under New
Project with no separator, because both make a document out of nothing),
Pause Recording (#98 — under New Recording…, live only while a recording
runs, retitled Resume Recording while paused, no key), Open…, Open Recent, Close, Save, Save As…,
Add Media…, Import Captions… (M3), Generate Captions… and Export
Captions… (road map 2's phase 4 — the three caption items sit
together, in the order a caption track comes into being and leaves again,
and none of them takes a key equivalent), Consolidate Media… (M3),
Export…, Save Frame… (road map 2's phase 7a — the frame under the playhead
written as a PNG, JPEG or HEIC still, at ⌥⌘E because it is Export…'s
still-image sibling and belongs under the same letter; the format is chosen
in the save panel's own accessory view rather than in a sheet, and the panel
says which of the three keeps the canvas's alpha, because phase 7b makes a
transparent canvas reachable and JPEG cannot carry one — it flattens onto
black. One writer serves the menu item and `render_frame` alike
(`FrameWriter.swift`), which is what makes the two produce the same bytes for
one frame rather than merely being meant to)),
Edit (Undo, Redo, Cut, Copy, Paste, Paste Attributes, Duplicate, Delete,
Ripple Delete, Insert at Playhead, Overwrite at Playhead, Select All,
Select After Playhead, Select All on Track), Clip (Split, Trim Start, Trim
End, Freeze Frame, Detach Audio, Normalize (road map 2's phase 5, beside
Detach Audio because those two are the menu's only sound commands; no key
equivalent, and it duplicates the Audio section's button deliberately —
a command reachable from a pane alone can be lost), Add Action, Speed…,
Close Gap, Remove
Silences…, Transition ▸, Motion ▸ (In ▸ / Out ▸ / During ▸, each the kinds
and None; no key equivalent), Add Background ▸ (Solid Color · Image… — road map
2's phase 6c, a submenu rather than one dialog because the two are
different commands: the colour takes no dialog at all and is re-coloured
afterwards in the Shape section's Fill row, which is also how a
full-canvas gradient is reached, while the image needs a file chooser) and
Add Blurred Background, in a group of their own since neither edits the
selection — both put a clip on a new back-most track — and neither takes a
key equivalent, Rename…, Label ▸ (the six colours and None),
Nest, Un-nest, Open Nest ⌘↓, Close Nest ⌘↑ — road map 2's phase 9, in the
grouping group because going inside a nest is the third thing you do with
one), Track (New Track,
Remove Track, Remove Empty Tracks, Hide/Mute/Lock/Solo), Mark (Add Marker,
Set In, Set Out, Clear Range, Next/Previous Marker), View (Zoom, Fit,
Snapping, Safe Areas, Inspector, Assistant ⌃⌘A (road map 12 A2: the
Assistant tab, shown and focused), Timeline Track Height, and — road map 2's
phase 8, in a group of their own after a separator because both are about the
PREVIEW rather than about the editor's panes — Preview Quality ▸ (Full · Half ·
Quarter, a tagged submenu with a checkmark for the current row and no key
equivalents: it scales the render size of the PLAYER's video composition alone,
always at the canvas's exact aspect ratio, and export and `render_frame` are
unreachable from it) and Preview Window ⇧⌘P (a second `AVPlayerLayer` on the
same player in an `NSPanel` — a panel because a titled window would become MAIN
and every ⌘-item whose action lives on the editor would stop resolving while
the preview was focused; its window sets `isExcludedFromWindowsMenu` for the
export queue's reason and autosaves its frame, which the queue's deliberately
does not, so it stays on the display it was put on)), Window (Minimize,
Zoom, Export Queue — road map 2's phase 7e, the export sheet's Add to Queue
button's other end, with no key equivalent because §9's "proposed, not yet
bound" table claims no row for it and every bare letter belongs to the
editor's own `keyDown`; the queue's window sets
`isExcludedFromWindowsMenu`, since this menu is `NSApp.windowsMenu` and
AppKit would otherwise list it a second time under its own title — Bring All
to Front), Help (Reelcut Help, Graphics Reference — road map 10's G5b: the
bundled `GraphicsAPI.md` opened in the person's own app, live while the
bundle holds it, with no document needed).
Road map 10's G5b adds **Insert**, right after Edit, holding **Graphic ▸**:
one item per bundled template (the six of `graphic/tests/graphics/`, copied
into the app's `GraphicTemplates/`, titled from the file stem —
`lower-third.js` is Lower Third — never by compiling it), a separator and
From File…; and File gains **Add Font to Graphics…** and **Add Image to
Graphics…** right after Consolidate Media…. None of the ten items takes a
key equivalent, for the caption items' reason; §11 G-16 has the rules.
All menu items are nil-target selectors validated in
`validateUserInterfaceItem`.
