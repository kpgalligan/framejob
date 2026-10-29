# Menus and keyboard shortcuts

This page lists every command in Frame Job's menu bar, in menu order, with
its shortcut. After the menus come the keys that work without a menu item,
the mouse and trackpad gestures on the timeline and the preview canvas, and
the context menus you get with a right-click. Each entry says in a few words
what the command does. The page that covers the feature explains it in full.

Symbols: ⌘ Command, ⌥ Option, ⇧ Shift, ⌃ Control, ⌫ Delete, ↩ Return,
⎋ Escape, ← → ↑ ↓ the arrow keys.

## How the keys are shared

- **Single-letter keys** (Space, J, K, L, I, O, M, W, E, T, C, Z, N, `,`, `.`)
  and the arrow keys belong to the editor window. They don't work while you
  are typing in a field, and they don't work while a sheet is open. Some
  menu items also have a single-letter key. The menu doesn't show those
  letters, so this page gives them in the menu tables as "(key)".
- **⌘ shortcuts** are menu shortcuts. A shortcut does nothing when its menu
  item is greyed out.
- **Delete (⌫), ⌘⌫, ⌘↓ and ⌘↑** are switched off while you type in a text
  field. In a field they keep their usual text-editing meaning.
- In a sheet, ↩ presses the default button and ⎋ cancels.
- macOS may add some items of its own to these menus. Those items are not
  listed here.

## Frame Job menu

| Item | Shortcut | What it does |
|---|---|---|
| About Frame Job | | The version and credits panel |
| Check for Updates… | | Asks whether a newer Frame Job has been published, and offers to install it. Only in the copy you download from GitHub; a build from source has no updater ([Settings](settings.md#updates)) |
| Settings… | ⌘, | Opens the Settings window ([Settings](settings.md)) |
| Hide Frame Job | ⌘H | Hides the app |
| Hide Others | ⌥⌘H | Hides every other app |
| Show All | | Shows hidden apps again |
| Quit Frame Job | ⌘Q | Quits |

## File menu

| Item | Shortcut | What it does |
|---|---|---|
| New Project | ⌘N | A new, empty project window |
| New Recording… | ⌥⌘N | Opens the recorder. While a recording runs, the item is called **Stop Recording** and stops it ([Screen recording](screen-recording.md)) |
| Pause Recording | | Pauses the running recording. It is called **Resume Recording** while paused, and is enabled only during a recording |
| Open… | ⌘O | Opens a project or a media file |
| Open Recent ▸ | | Recently opened documents, then **Clear Menu** |
| Close | ⌘W | Closes the window |
| Save | ⌘S | Saves the project |
| Duplicate | ⇧⌘S | Opens a copy of the project as a new, untitled document. Hold ⌥ and the item becomes **Save As…** (⌥⇧⌘S), which writes the project to a new package |
| Rename… | | Renames the project's package |
| Move To… | | Moves the project's package to another folder |
| Revert To ▸ | | Goes back to the last saved version, or browses earlier versions of the package |
| Share | | The macOS Share menu for the project |
| Add Media… | ⇧⌘I | Imports files into the project's Media list ([Projects and media](projects-and-media.md)) |
| Import Captions… | | Reads a caption file onto a caption track ([Captions](captions.md)) |
| Generate Captions… | | Makes captions from speech |
| Export Captions… | | Writes a caption track out as a file |
| Consolidate Media… | | Copies the project's media into the project package |
| Add Font to Graphics… | | Adds a font that graphics can use ([Graphics](graphics.md)) |
| Add Image to Graphics… | | Adds a picture that graphics can use |
| Rename Graphic… | | Renames one of the project's graphics. Greyed when the project has no graphics, or while a nest is open |
| Delete Graphic… | | Deletes a graphic that no clip uses |
| Restore Graphic Version… | | Brings back an earlier version of a graphic |
| Export… | ⌘E | The export sheet ([Export](export.md)) |
| Save Frame… | ⌥⌘E | Saves the frame under the playhead as a PNG, JPEG or HEIC still |

*Agents:* `new_project`, `open_project`, `save_project`, `close_project`,
`import_media`, `import_captions`, `transcribe`, `export_captions`,
`consolidate_media`, `import_graphic_font`, `import_graphic_asset`,
`rename_graphic`, `delete_graphic`, `restore_graphic`, `export`,
`render_frame` (Save Frame…'s writer) and `record_screen`.

### When File items are available

| Item | Enabled when |
|---|---|
| Generate Captions… | Some clip plays sound from a media file forwards, with its audio on |
| Export Captions… | The project has a caption track: a track whose clips are all text clips |
| Consolidate Media… | The project has media |
| Rename Graphic… | The project has graphics and no nest is open |
| Delete Graphic… | The project has graphics |
| Restore Graphic Version… | An earlier version of a graphic is kept |
| Export…, Save Frame… | The project is not empty |

## Edit menu

| Item | Shortcut | What it does |
|---|---|---|
| Undo | ⌘Z | Undoes the last edit. The item names it, for example **Undo Move Clips** or **Undo Ripple Delete** |
| Redo | ⇧⌘Z | Redoes it, named the same way |
| Cut | ⌘X | Cuts the selected clips |
| Copy | ⌘C | Copies the selected clips |
| Paste | ⌘V | Pastes clips at the playhead. Nothing needs to be selected |
| Paste Attributes | ⌥⌘V | Puts the copied clip's look onto the selected clips |
| Paste Graphic Properties | | Puts the copied graphic's properties onto the selected clips that use the same graphic |
| Duplicate | ⌘D | Copies the selected clips and places the copies after them |
| Delete | ⌫ | Removes the selection and leaves a gap. With nothing selected it lifts the in/out range. With an action selected it removes that action |
| Ripple Delete | ⌘⌫ | Removes the selection, or the in/out range when nothing is selected, and closes the gap |
| Insert at Playhead | | Inserts the file selected in the Media tab, pushing later clips along |
| Overwrite at Playhead | | Places that file over whatever is already there |
| Select All | ⌘A | Selects every clip |
| Select After Playhead | ⌥⌘A | Selects every clip that starts at or after the playhead |
| Select All on Track | | Selects every clip on the current track |

Cut and Copy need a selection. Paste needs copied clips on the clipboard.
Paste Attributes needs copied clips and a selection. Paste Graphic
Properties needs copied clips and a selected graphic clip. Insert and
Overwrite at Playhead are enabled only while a file is selected in the Media
tab, and never for a LUT. Select All on Track needs a current track and a
timeline with clips. The *current track* is the track of the
first selected clip. With nothing selected it is the front-most track. See
[Editing](editing.md).

*Agents:* `undo`, `redo`, `paste`, `paste_attributes`, `duplicate`, `delete`,
`lift_range`, `ripple_delete`, `ripple_delete_range`, `insert_clip`,
`overwrite_clip`, `set_selection`.

## Insert menu

| Item | Shortcut | What it does |
|---|---|---|
| Adjustment Clip | | Adds an adjustment clip over the in/out range. Without a range it covers the selected clips' span, and without a selection the whole timeline. Greyed while a nest is open ([Colour grading](color-grading.md)) |
| Graphic… | | Opens the Graphic dialog: the bundled templates by category (and This Project's own graphics), a looping preview, and Insert to add the chosen one at the playhead, From File… to add a `.js` file you choose, or Export… to save the chosen one as a `.fjgraphic` file ([Graphics](graphics.md#adding-a-graphic)) |

*Agents:* `add_adjustment_clip`; `list_graphics` and `insert_graphic`, or
`write_graphic` followed by `add_graphic_clip`.

## Clip menu

| Item | Shortcut | What it does |
|---|---|---|
| Split | ⌘T | Cuts the selected clips at the playhead. With nothing selected, it cuts every clip under the playhead |
| Trim Start to Playhead | W (key) | Trims the selected clips' starts to the playhead |
| Trim End to Playhead | E (key) | Trims their ends to the playhead |
| Freeze Frame | ⇧⌘F | Holds the frame under the playhead as a still clip |
| Detach Audio | ⌥⌘D | Moves a clip's sound onto its own clip ([Audio](audio.md)) |
| Normalize | | Sets the selected clips' loudness |
| Synchronize Audio | | Lines up the selected clips by their sound. Needs two or more clips that play sound |
| Add Action | ⌥⌘K | Adds an action at the playhead ([Motion and transitions](motion-and-transitions.md)) |
| Speed… | | Sets the selected clips' playback rate ([Speed](speed.md)) |
| Speed Ramp… | | Puts a speed ramp preset on one selected media clip |
| Close Gap | | Closes the gap under the playhead on the current track |
| Remove Silences… | | Finds silent stretches and removes them ([Remove Silences and Remove Filler Words](cleanup-tools.md)) |
| Remove Filler Words… | | Finds "um"s and "uh"s and removes them |
| Transition ▸ | | Sets the transition into the clip |
| Motion ▸ | | Sets how the clip enters, leaves and moves |
| Look ▸ | | Puts a look or a LUT on the clip ([Colour grading](color-grading.md)) |
| Add Background ▸ Solid Color | | Puts a colour plate on a new track behind everything ([Canvas and layers](canvas-and-layers.md)) |
| Add Background ▸ Image… | | Puts a picture you choose on a new track behind everything |
| Add Blurred Background | | Puts a blurred copy of the picture on a new track behind everything |
| Rename… | ⇧⌘R | Renames the selected clip in place on the timeline |
| Label ▸ | | Gives the clip a colour label |
| Nest | ⌘G | Wraps the selected clips into one nest clip |
| Un-nest | ⇧⌘G | Breaks a nest clip back into its clips |
| Open Nest | ⌘↓ | Goes inside the selected nest clip |
| Close Nest | ⌘↑ | Comes back out by one level |

### Clip submenus

- **Transition ▸**: Cross Dissolve, Fade Through Black, Fade Through White,
  Push Left, Push Right, Push Up, Push Down, Wipe, Slide, Zoom, Wipe Left,
  Wipe Up, Wipe Down, then **None**. A checkmark shows the selected clip's
  transition. A transition can be picked only on a clip that has room for
  one. **None** works for any selection, so a stored transition can always
  be cleared.
- **Motion ▸ In ▸** and **Motion ▸ Out ▸**: Fade, Zoom In, Zoom Out, Slide
  Left, Slide Right, Slide Up, Slide Down, Spin, Pop, then **None**.
- **Motion ▸ During ▸**: Pulse, Shake, Spin, Bounce, Drift, then **None**.
- In each Motion submenu a checkmark shows the kind every selected clip
  has. An In or Out kind whose length is zero reads **\<Kind\> (inactive)**,
  or **(some inactive)** when only some of the selected clips with that kind
  have zero length.
- **Motion ▸ Preview**: sets the in/out range to the clip, turns Loop on and
  plays it. The range and Loop stay set afterwards.
- **Look ▸**: Warm, Cool, Teal & Orange, Vivid, Faded, Vintage, Dramatic,
  Black & White. Then come the project's `.cube` LUTs, when it has any, and
  then **None**. A checkmark marks a look that every selected clip has. A
  dash marks one that only some of them have.
- **Label ▸**: Red, Orange, Yellow, Green, Blue, Purple (each shown with its
  colour dot), then **None**. A checkmark shows the label the selected clips
  share.

### When Clip items are available

| Item | Enabled when |
|---|---|
| Split | The timeline has any clip |
| Trim Start / End to Playhead, Freeze Frame | A selected clip is under the playhead |
| Detach Audio | Something is selected |
| Normalize | A selected clip plays sound |
| Synchronize Audio | Two or more selected clips play sound |
| Add Action | A selected clip is under the playhead |
| Speed… | The selection includes a clip that plays a media file |
| Speed Ramp… | Exactly one clip is selected and it plays a media file |
| Close Gap | There is a current track and the timeline has clips |
| Remove Silences… | Some clip plays sound |
| Remove Filler Words… | Some clip plays sound from a media file forwards, with its audio on |
| Transition ▸ items | A kind: a selected clip has room for a transition. **None**: something is selected |
| Motion ▸ items | A selected clip shows a picture |
| Look ▸ items | A selected clip shows a picture from a file, or is an adjustment clip |
| Add Background ▸ | Always |
| Add Blurred Background | Exactly one clip is selected and it has a picture size: a video, image, still, shape or graphic clip. Dimmed for a nest, text, adjustment or audio-only clip |
| Rename…, Label ▸ | Something is selected |
| Nest | Something is selected, other than a single nest clip on its own |
| Un-nest | The selection includes a nest clip |
| Open Nest | Exactly one clip is selected and it is a nest clip |
| Close Nest | A nest is open |

Open Nest and Close Nest are also greyed while you are typing in a text
field.

*Agents:* `split`, `trim_start`, `trim_end`, `freeze_frame`, `detach_audio`,
`normalize_clip`, `sync_audio`, `add_action`, `set_speed`, `add_speed_ramp`,
`close_gap`, `detect_silence`, `detect_fillers`, `add_transition` /
`set_transition`, `set_video` (motion and look), `add_background`,
`add_blurred_background`, `set_clip` (name and label), `nest`, `unnest`,
`set_scope` (open and close a nest).

## Track menu

| Item | Shortcut | What it does |
|---|---|---|
| New Track | ⇧⌘N | Adds a track |
| Remove Track | | Removes the current track. If it still holds clips, you are asked first |
| Remove Empty Tracks | | Removes every track that has no clips |
| Hide Video | | Hides the current track's picture |
| Mute Audio | | Mutes the current track's sound |
| Lock Track | | Locks the current track so its clips can't be edited |
| Solo | | Plays only this track's sound. A checkmark shows when it is on |
| Matte ▸ Off · Alpha · Inverted Alpha · Luma · Inverted Luma | | Makes the current track a matte that cuts the track behind it. A checkmark shows the track's mode ([Canvas and layers](canvas-and-layers.md)) |

These items act on the current track. To act on a particular track, use that
track's context menu ([below](#context-menus)).

*Agents:* `add_track`, `remove_track`, `remove_empty_tracks`, `set_track`
(hidden, muted, locked, solo, matte), `move_track`.

## Mark menu

| Item | Shortcut | What it does |
|---|---|---|
| Add Marker | M (key) | Adds a marker at the playhead |
| Set In | I (key) | Sets the in point at the playhead |
| Set Out | O (key) | Sets the out point at the playhead |
| Clear Range | ⌥X | Clears the in/out range |
| Next Marker | | Moves the playhead to the next marker |
| Previous Marker | | Moves it to the previous marker |

The marker items are off while a nest is open. Next and Previous Marker
also need the project to have markers, and Clear Range needs a range to be
set. See [The timeline](timeline.md).

*Agents:* `add_marker`, `set_marker`, `remove_marker`, `set_range` (with no
bounds it clears the range).

## View menu

| Item | Shortcut | What it does |
|---|---|---|
| Zoom In | ⌘+ or ⌘= | Zooms the preview canvas in one step |
| Zoom Out | ⌘- | Zooms it out one step |
| Zoom to Fit | ⌘0 | Fits the canvas to the preview again |
| Fit Timeline | ⇧Z (key) | Zooms the timeline to show the whole project |
| Snapping | N (key) | Turns snapping on or off. A checkmark shows when it is on |
| Safe Areas | | Shows or hides the safe-area guides on the canvas |
| Hide Inspector | ⌥⌘I | Hides the inspector. The item is called **Show Inspector** while it is hidden |
| Assistant | ⌃⌘A | Shows the inspector's Assistant tab and puts the cursor in its message field ([Assistant](assistant.md)) |
| Timeline Track Height ▸ Small · Medium · Large | | Sets the height of the timeline rows |
| Preview Quality ▸ Full · Half · Quarter | | The preview's render size while you play. Export is not affected |
| Preview Window | ⇧⌘P | A second window showing the picture without overlays. Choose it again to close the window |
| Show Ungraded | ⌃⌘U | Shows the preview as if no clip were graded |
| Show Selection | | Shows which pixels the selected adjustment clip's qualifier picks. Needs a selected adjustment clip to turn on |
| Show SDR Version | | Shows an HDR project's SDR version ([HDR and colour management](hdr-and-color.md)) |
| Scopes | ⌃⌘W | Shows the scopes panel beside the preview ([Colour grading](color-grading.md)) |

The canvas zoom steps are Fit, 50 %, 100 % and 200 %. View ▸ Zoom In, Zoom
Out and Zoom to Fit always act on the canvas. Zoom In is greyed at 200 %,
and Zoom Out and Zoom to Fit at Fit. To zoom the timeline, use the timeline
bar's controls or the gestures [below](#timeline-gestures). Show Ungraded,
Show SDR Version and Scopes are always enabled. Snapping, Safe Areas, Hide Inspector,
Timeline Track Height and Preview Quality are remembered between launches.
Show Ungraded, Show Selection, Show SDR Version and Scopes are not
remembered, and they never change an export.

## Window menu

| Item | Shortcut | What it does |
|---|---|---|
| Minimize | ⌘M | Minimizes the window to the Dock |
| Zoom | | Makes the window larger or smaller |
| Export Queue | | Opens the Export Queue window ([Export](export.md)) |
| Bring All to Front | | Brings all Frame Job windows to the front |

The open windows are listed at the end of the menu, as in any Mac app.

## Help menu

| Item | What it does |
|---|---|
| Frame Job Help | The standard macOS help item. The app ships no help book |
| Graphics Reference | Opens the graphics scripting reference in your default Markdown app ([Graphics](graphics.md)) |

*Agents:* `graphic_reference` returns the same reference.

## Keys without a menu item

These keys work in the editor window when you are not typing in a field.
They also work in the Preview Window.

### Playback and moving the playhead

| Key | What it does |
|---|---|
| Space | Play / pause, wherever the focus is in the window. In a text field, Space types a space. A button focused with Full Keyboard Access keeps Space to press itself |
| L | Plays forward. Press it again for 2× and then 4× |
| J | Plays in reverse. Press it again for 2× and then 4× in reverse |
| K | Pauses |
| ← / → | Moves back or forward one frame. With ⇧, ten frames |
| ↑ / ↓ | Moves to the previous or next edit point |
| Home / End | Moves to the start or end of the project |

When the preview canvas has focus, the arrow keys move the selected clips
instead ([below](#preview-canvas-gestures)).

### Editing

| Key | What it does |
|---|---|
| `,` / `.` | Moves the selected clips one frame earlier or later. With ⇧, ten frames |
| T | Adds a text clip at the playhead |
| C | Turns crop mode on or off for the selected clip on the canvas |
| Z | Region mode: drag a rectangle over the selected clip to zoom to it. ⇧ while dragging fills the canvas instead of fitting it. ⎋ or Z again cancels. Needs exactly one selected clip that is visible at the playhead |
| ⇧Z | Fit Timeline |
| N | Snapping on or off |
| M | Add Marker |
| I / O | Set In / Set Out |
| W / E | Trim Start / End to Playhead |
| ⎋ | Deselects the selected action, so the Clip tab shows the clip's own values again |

### Text and fields

| Where | Key | What it does |
|---|---|---|
| Text being edited on the canvas | ↩ | Applies the text and stops editing |
| | ⇧↩, ⌘↩, ⌥↩ or ⌃↩ | Starts a new line |
| | ⎋ | Stops editing. If the text changed, you are asked to choose **Apply**, **Revert** or **Cancel** |
| Rename field on the timeline (clip, track or marker) | ↩, Tab, or a click elsewhere | Saves the new name |
| | ⎋ | Keeps the old name |
| Assistant message field | ↩ | Sends the message |
| | ⇧↩ (or ↩ with any modifier) | Starts a new line |
| | Tab / ⇧Tab | Moves to the next or previous control |
| | ⌘Z / ⇧⌘Z | Undo and redo your typing in the field, not project edits |
| Timecode field in the toolbar | Click, type a time such as `1:23`, `83.5` or `1:23:04`, then ↩ (or click away) | Pauses playback and moves the playhead to that time. A time the app can't read beeps, and the field goes back to the current time |
| Inspector number and text fields | ↩ | Applies the value and leaves the field |
| | Tab, or a click elsewhere | Applies the value |
| | ⎋ | Throws the typing away and keeps the old value |

### Modes that ⎋ leaves

- A canvas drag in progress (move, scale, rotate, crop, line endpoint,
  obscure region): ⎋ puts everything back as it was before you pressed, and
  no undo step is added.
- Crop mode: ⎋ or ↩.
- Region mode (Z, or the Obscure section's **Place on Canvas**). It also
  ends by itself when the selection stops being the clip it was started
  for, or the playhead leaves that clip. Z beeps unless exactly one clip is
  selected and visible at the playhead.
- The key-colour and qualifier eyedroppers. The hint on screen reads "Click
  to pick … · Esc to cancel".
- A selected curve point in the Color tab.

## Timeline gestures

| Gesture | Where | What it does |
|---|---|---|
| Click | Clip | Selects it |
| ⇧-click | Clip | Adds it to the selection, or removes it |
| Click | Empty lane | Deselects everything |
| Drag | Empty lane, or above or below the tracks | Marquee: selects every clip the band touches. Clips on locked tracks are skipped |
| ⇧-drag | Empty lane | Marquee that adds to the selection |
| Double-click | Empty part of a lane | Closes that gap |
| Drag | Clip | Moves the selected clips, in time and to other tracks. Dragging past the top or bottom track puts them on a new track |
| ⌥-drag | Clip | Duplicates the clips and moves the copies |
| ⌥⇧-drag | Clip | Slip: moves the source under the clip while the clip stays in place |
| Drag | Clip edge | Trims that edge |
| ⌥-drag | Clip's end edge | Rate stretch: changes the speed so the clip fills the new length. Works only on a clip that plays a media file. On the start edge, ⌥ trims as usual |
| ⌥⇧-drag | Clip edge | Roll: moves the cut between this clip and the clip touching it. Does nothing where there is no touching clip |
| Drag | Fade handle on a clip | Sets that clip's audio fade-in or fade-out |
| Click | Action band | Selects the clip and that action. The Clip tab then edits the action's end values; ⎋ deselects the action |
| Drag | Action band | Moves the action in time |
| Drag | Edge of an action band | Changes the action's length |
| Double-click | Clip | Renames it in place |
| Double-click | Nest clip | Goes inside the nest. To rename a nest clip, use ⇧⌘R |
| Click or drag | Ruler | Moves the playhead (scrubbing) |
| Drag | Marker | Moves it |
| Double-click | Marker | Renames it |
| Drag | Track header | Moves the track up or down the stack |
| Double-click | Track header | Renames the track |
| ⌥-click | Track header | Selects every clip on that track |
| Click | Header buttons (eye, speaker, lock, headphones) | Hide Video, Mute Audio, Lock Track, Solo |
| Click | Breadcrumb in the corner, while a nest is open | Comes back out by one level |
| Hold ⌘ while dragging | Any drag that snaps | Turns snapping off for that drag, even when you press ⌘ partway through |
| Pinch, or ⌥ / ⌘ with the scroll wheel | Anywhere on the timeline | Zooms around the pointer |
| Scroll | Anywhere on the timeline | Scrolls |

While snapping is on (N), moving, trimming and rolling clips, dragging a
marker and scrubbing the ruler snap to clip edges, markers, the start and
end of the timeline, the playhead and the in/out points, within about 8
points of the pointer. A slip doesn't snap.

Clips on a locked track can't be dragged, trimmed, slipped or rolled. Every
drag is one undo step. See [Editing](editing.md) and [The timeline](timeline.md).

*Agents:* `move_clip`, `trim_start`, `trim_end`, `rate_stretch`, `slip`,
`roll`, `close_gap`, `set_action`, `set_audio` (fades), `move_track`,
`set_playhead`.

## Buttons with no menu item

Most toolbar and timeline-bar buttons repeat a menu item, and their tooltips
give its shortcut. These do something no menu item does, or have their own
controls:

| Button | Where | What it does |
|---|---|---|
| Add Shape | Timeline bar | Opens a menu of **Rectangle**, **Ellipse**, **Line** and **Arrow**. The shape is added at the playhead. This is the only way to add a shape clip |
| Loop | Toolbar, beside the transport buttons | Turns looping on and off. Playback repeats the in/out range when one is set, otherwise the whole timeline |
| − / + (Zoom Out / Zoom In) | Timeline bar | Zooms the timeline out or in |
| Timeline Zoom slider | Timeline bar | Sets the timeline zoom |
| Fit Timeline | Timeline bar | The same as **View ▸ Fit Timeline** (⇧Z) |
| Snap | Timeline bar | The same as **View ▸ Snapping** (N) |
| S / M / L | Timeline bar | Small, Medium and Large tracks: the same as **View ▸ Timeline Track Height** |
| Zoom pop-up (Fit, 50%, 100%, 200%) | Toolbar | Sets the canvas zoom, the same steps as **View ▸ Zoom In / Zoom Out / Zoom to Fit** |
| Safe | Toolbar | The same as **View ▸ Safe Areas** |

*Agents:* `add_shape_clip` (Add Shape's menu).

## Dragging media in

| Drag | Drop on | What it does |
|---|---|---|
| A row from the Media tab | A track | Places the clip at the drop point. A drop that would overlap another clip is refused |
| ⌥ + a Media row | A track | Insert: makes room by pushing later clips along |
| ⇧⌥ + a Media row | A track | Overwrite: replaces what is in the way |
| A Media row | The preview canvas | Places the clip on a new top track at the playhead |
| Files from the Finder | The Media tab | Adds them to the project |
| Files from the Finder | Anywhere else in the window | Opens each one as its own document, the same as dropping it on the Dock icon |
| Files from the Finder | The Welcome window | Opens each one as its own document, the same way |

A LUT row in the Media tab doesn't drag. Apply a LUT with **Clip ▸ Look ▸**
or the Color tab instead.

*Agents:* `add_clip`, `insert_clip`, `overwrite_clip`, `import_media`.

## Preview canvas gestures

| Gesture | What it does |
|---|---|
| Click a clip | Selects it. ⇧-click adds it to the selection or removes it |
| Click empty canvas | Deselects everything and leaves crop mode. With ⇧, keeps the selection |
| Drag a clip | Moves the selected clips. They snap to the canvas centre, edges and thirds and to other layers. ⌘ turns snapping off |
| Drag a corner or side handle | Scales. Video, image, still, graphic and nest clips always scale uniformly. On a shape, ⇧ on a corner handle frees the aspect ratio and a side handle changes only the width or the height. On a text clip, the left and right handles set the wrap width. ⌥ scales around the centre. See [Move, scale and rotate](canvas-and-layers.md#move-scale-and-rotate) |
| Drag the rotation handle | Rotates. ⇧ snaps to 15° steps |
| Drag a crop handle (crop mode) | Crops |
| Drag a line or arrow endpoint | Moves that end of the shape |
| Drag an obscure region's centre grip or one of its eight handles | Moves or resizes that region. ⌥ resizes it around its centre. The grips show only with exactly one unlocked clip selected, outside crop mode. A drag inside the region but away from the grips still moves the clip |
| Double-click a text clip | Edits the text in place |
| Double-click any other clip | Turns on crop mode |
| ← → ↑ ↓ (canvas has focus) | Moves the selected clips 1 pixel. With ⇧, 10 pixels |
| Hold Space and drag | Pans a zoomed canvas that is larger than the preview. A Space tap still plays and pauses |
| Pinch, or ⌥ / ⌘ with the scroll wheel | Steps the canvas zoom |
| Scroll | Pans a canvas that is larger than the preview |

Clips on locked tracks don't move. When an action is selected, a drag or an
arrow-key nudge sets the value at that action's end, not the clip's own
value. See [Canvas and layers](canvas-and-layers.md).

*Agents:* `set_video` (position, scale, rotation, crop), `set_shape`,
`set_text`.

## Color tab controls

In the Color tab's wheels, strips and curves, hold ⌥ while you drag to move
at a tenth of the speed. Double-click a wheel or a strip to reset it. In a
curve, click (or double-click) an empty part of the plot to add a point. To
remove a point, select it and press ⌫, or double-click it. To reset a whole
curve, use its channel strip's **Reset \<channel\>** item
([below](#curves-channel-strip-color-tab)). The
arrow keys nudge the selected point (⇧ for bigger steps). ⇧ while dragging
keeps the point on one axis. Details are on [Colour grading](color-grading.md).

## Context menus

Right-click (or ⌃-click) to open these. A right-click on a clip, the ruler
or the timeline's corner opens no menu.

### Track header or empty lane

The menu is for the track you clicked:

- **Hide Video**, **Mute Audio**, **Lock Track**, **Solo**, each with a
  checkmark showing that track's state
- **Matte ▸** Off · Alpha · Inverted Alpha · Luma · Inverted Luma, with a
  checkmark on the track's mode
- **Remove Track**. You are asked first if the track holds clips. Greyed
  when it is the only track.

Remove Track here is the way to delete an empty track that isn't the
front-most one.

### Media row (Media tab)

- **Insert at Playhead**, **Overwrite at Playhead** (greyed for a LUT)
- **Reveal in Timeline**: selects the clips that use the file and scrolls to
  the first one. Greyed when no clip on the timeline itself uses the file,
  which includes a file no clip uses and one used only inside a nest.
- **Reveal in Finder**, **Relink…**, **Remove**

*Agents:* `insert_clip`, `overwrite_clip`, `relink_media`, `remove_media`.

### Inspector row

Right-click a row's label, slider, checkbox or the space beside them. A text
field or popup keeps its own menu. The menu shows only the items that apply
to that row:

- **Remove from action N**: on a row that the selected action changes
- **Go to action M**: on a row that another action changes
- **Reset to default**, or **Set end value to default** while an action that
  animates the row is selected. Greyed when the row already holds its
  default.

On a row the selected action changes, the ◆ in the row's left gutter turns
into × when you hover over it. Click it to remove that row from the action,
the same as **Remove from action N**.

### Curves channel strip (Color tab)

- **Reset \<channel\>**: resets that curve. Greyed when the curve is already
  flat.

### Recording status item (menu bar)

While a recording runs, its time is shown in the macOS menu bar. Click it
for **Pause Recording** (or **Resume Recording**) and **Stop Recording**.
See [Screen recording](screen-recording.md).
