# The timeline and playback

The editor window shows your project in four areas: the toolbar, the
preview, the inspector and the timeline. This page covers how to move around
the timeline and play the project back: tracks and their switches, the ruler
and playhead, zoom and row heights, selection, snapping, markers, the in/out
range, clip names and labels, and the View menu items for the timeline and
the preview. Editing with gestures (moving, trimming, slipping and so on) is
on [Editing](editing.md).

## The editor window

| Area | Where | What it holds |
|---|---|---|
| Title bar | top | The project name, with canvas size, frame rate and "edited" (while unsaved) as the subtitle, e.g. `1920 × 1080 · 30 fps · edited` |
| Toolbar | under the title bar | Transport, timecode, preview zoom, safe-area guides, **Export…** |
| Preview | middle left | The frame under the playhead, at canvas size, letterboxed |
| Inspector | middle right | The Clip, Media, Document and Assistant tabs |
| Timeline bar | above the timeline | The selection block, clip buttons, Snap, the level meter, zoom, track size (see [below](#the-timeline-bar)) |
| Timeline | bottom | The ruler, track headers and lanes |

Drag the dividers to resize the panes. The inspector can be 280–440 pt wide
(304 pt to start) and the timeline 140 pt up to 60 % of the window (300 pt to
start). The sizes you drag to are remembered. Dragging the inspector divider
to the edge stops at its minimum width; the only way to hide the inspector is
**View ▸ Hide Inspector** (⌥⌘I), which becomes **Show Inspector** while it is
hidden and is also remembered. The window is at least 900 × 620 pt.

### The toolbar

From left to right:

- **Transport**: Go to Start (Home), Previous Edit Point (↑), Play / Pause
  (Space), Next Edit Point (↓), Go to End (End), and **Loop**. Loop is dimmed
  while off.
- **Timecode**: the playhead's time, then `/` and the duration of what the
  timeline shows. Click the time to type one: it takes `HH:MM:SS:FF`,
  `HH:MM:SS.mmm`, `HH:MM:SS`, `MM:SS`, seconds with a decimal (`83.5`) or a
  bare number of seconds. Press Return to jump there, snapped to a frame.
  Text that is not a time beeps and the field goes back to the playhead's
  time.
- **Preview zoom**: a popup with Fit, 50%, 100% and 200%.
- **Safe**: shows the title-safe and action-safe guides (90 % and 80 %
  rectangles) on the preview. Remembered between launches.
- **Export…** (⌘E): see [Export](export.md).

Timecode shows frames by default. The Document tab's **Timecode** popup
(Frames or Milliseconds) changes every readout, the ruler included.

### The timeline bar

From left to right:

- **The selection block**, naming what is selected (see
  [Selecting clips](#selecting-clips)).
- **Eight clip buttons**: Split (⌘T), Trim Start to Playhead (W), Trim End
  to Playhead (E), Ripple Delete (⌘⌫), Add Marker (M), Duplicate (⌘D), Add
  Text (T) and Add Shape. Each button's tooltip names its key. **Add Shape**
  opens a menu of shapes and has no menu-bar item, so this button is the way
  to add one. What the edits do is on [Editing](editing.md); text and shapes
  are on [Canvas and layers](canvas-and-layers.md).
- **Snap**, the snapping checkbox (see [Snapping](#snapping)).
- **The level meter** (see [The level meter](#the-level-meter)).
- **The zoom cluster**: −, the zoom slider, + and Fit (⇔) (see
  [Zooming the timeline](#zooming-the-timeline)).
- **S / M / L**, the track size (see [Row heights](#row-heights)).

## Tracks

There is one kind of track, and it holds any clip: video, audio, a still,
text, a shape, a graphic, a nest or an adjustment clip. Tracks stack: **the
top lane is the front-most**, and the bottom lane is the back.

### Track headers

Each track has a header on the left with its name and four switches:

| Switch | Symbol (off / on) | What it does |
|---|---|---|
| Hide Video | eye / struck-through eye | Takes the track's picture out of the preview and export. Its clips draw dimmed. |
| Mute Audio | speaker / crossed-out speaker | Silences the track's sound. |
| Lock Track | open padlock / closed padlock | Protects the track from edits: its clips can't be dragged or trimmed, a marquee skips them, and ripple, insert and range edits leave them alone. The lane is hatched. |
| Solo | headphones (both) | Silences every other track that is not soloed too. Pictures stay. Mute still wins on a track that is both muted and soloed. |

A lit switch is also highlighted in the accent colour, so you can read a
track's state from the symbol or the highlight. Under a solo, the waveforms
on the silenced tracks draw faded but their speakers stay unlit, because the
speaker shows the track's own setting.

A track with no name shows `Track N`, counting up from the back track.

### Managing tracks

| To | Do this |
|---|---|
| Add a track at the front | **Track ▸ New Track** (⇧⌘N) |
| Rename a track | Double-click its name in the header |
| Reorder | Drag a header up or down. A coral line shows where it will land. |
| Select every clip on a track | ⌥-click its header, or **Edit ▸ Select All on Track** (the current track, below) |
| Remove a track | **Track ▸ Remove Track**, or the header's context menu |
| Drop every empty track | **Track ▸ Remove Empty Tracks** |

Dragging a clip above the top lane or below the bottom lane makes a new track
for it (see [Editing](editing.md)).

**Remove Track** removes an empty track at once. If the track still holds
clips it asks first ("The track still holds 3 clips, which will be removed
with it.") with **Remove** and **Cancel**. The last track can't be removed.
**Remove Empty Tracks** always keeps at least one track.

The **Track** menu works on the *current track*: the first selected clip's
track, or the front-most track when nothing is selected. Besides the commands
above it has **Hide Video**, **Mute Audio**, **Lock Track** and **Solo**,
which flip that track's switches. Only Solo shows a checkmark there. The
**Matte ▸** submenu is described in
[Canvas and layers](canvas-and-layers.md).

### The track context menu

Right-click (or ⌃-click) a header, or an empty part of a lane, to get that
track's menu: **Hide Video**, **Mute Audio**, **Lock Track** and **Solo**,
each checked when on, then **Matte ▸**, then **Remove Track** (disabled on
the last track). Right-clicking a clip opens no menu.

Every switch flip, rename and reorder is one undo step. The names **Edit ▸
Undo** shows for this page's edits are:

| Edit | Undo name |
|---|---|
| Track switches | Hide Track, Mute Track, Lock Track, Solo Track |
| A track's matte | Track Matte |
| Track names and order | Rename Track, Reorder Track |
| Adding and removing tracks | New Track, Remove Track, Remove Empty Tracks |
| Markers | Add Marker, Move Marker, Rename Marker, Chapter Marker, Remove Marker |
| Clip names and labels | Rename Clip, Label Clip |

*Agents:* `add_track` (an `index`, 0 being the back; the front when left
out), `remove_track` (`with_clips` to take its clips too), `move_track`,
`set_track` (`name`, `hidden`, `muted`, `locked`, `solo`, `matte`),
`remove_empty_tracks`.

### Row heights

Pick the track size with the **S / M / L** control at the right end of the
timeline bar, or **View ▸ Timeline Track Height ▸** Small, Medium or Large.
Medium is the default and your choice is remembered.

Each track's height also depends on what it holds:

| Track holds | Small | Medium | Large |
|---|---|---|---|
| Only text and shapes | 30 pt | 44 pt | 58 pt |
| Only clips with sound and no picture | 40 pt | 60 pt | 82 pt |
| Anything else (an empty track included) | 54 pt | 84 pt | 116 pt |

At Small a clip shows little more than its name strip.

## Reading a clip

Each clip is drawn as one rounded block with a thin border, so you can see
where one ends and the next begins.

- **Colour by kind**: video slate, audio green, image or still violet, text
  amber, shape teal (graphics use the same colour), nest grey, adjustment
  rose.
- **Name strip** along the top: a symbol for the kind, then the clip's name.
  A clip with no name of its own shows what it holds: its file, its text, its
  shape or its nest.
- **Label dot**: a labelled clip gets a small dot in its label colour at the
  right end of the name strip. The block's colour still shows its kind.
- **Filmstrip**: thumbnails along the picture part of a video or image clip,
  under a wash of the clip's colour. Each thumbnail is the source frame at
  that point, following speed, reverse and speed ramps.
- **Waveform**: the sound of a clip that has audio, drawn below the
  filmstrip on a clip that has both. Muted, or silenced by another track's
  solo, it draws faded.
- **Fade handles**: small white squares at the top corners of the audio part.
  Drag one inward to fade (see [Audio](audio.md)).
- **Motion marks**: small wedges at the ends of the name strip for an active
  In or Out motion, and a wave glyph for a During motion (see
  [Motion and transitions](motion-and-transitions.md)).
- **Transitions**: the overlap between two clips is hatched, with the
  transition's kind written in it when the word fits.
- **Selected**: a 2 pt coral ring, with trim grips at both ends when the clip
  is wide enough to trim and its track is unlocked.
- **Dimmed**: a clip on a hidden track, or one with both its picture and its
  sound switched off.
- **No filmstrip**: text, shape, graphic, nest and adjustment clips have no
  thumbnails. An adjustment clip is a plain rose block with only its name
  strip and action lane, and its track is sized as a picture track.

Filmstrips and waveforms come from a cache made for each media file after
import, so they fill in a moment after a file is added.

### The action lane

A clip that has actions (keyframed segments) gets an **action lane** right
under its name strip. Each action is a band. At Medium and Large each band
shows its number in time order (and a zoom glyph for a zoom action); at Large
it also lists the properties it changes; at Small the bands are plain bars.
The selected action is solid, its span is washed down the clip, and it is
shaded on the ruler.

Hover a band to highlight it and show its 5 pt grips at both ends (a band
15 pt wide or less has none). The pointer is an open hand over the body and
a resize arrow over a grip.

Click a band to select the clip and that action; the playhead also moves to
the action's end, so the preview shows its end state. Drag a band's body to
move the action, or drag a grip to resize it. After a move or resize the
action stays selected and the playhead goes to its new end. When exactly one
clip is selected, playing or scrubbing into one of its actions' spans
selects that action. Esc leaves it, and ⌫ removes it.
Everything else about actions is on
[Motion and transitions](motion-and-transitions.md).

## The ruler and the playhead

The ruler's ticks adjust to the zoom, from single frames up to minutes.
Labels drop the hours when the timeline is under an hour long. The playhead
is the coral line with a triangle head on the ruler.

- **Click the ruler** to move the playhead there, and **drag** along it to
  scrub. Playback stops while you scrub. The scrub snaps like any other drag
  (see [Snapping](#snapping)).
- The timeline scrolls itself to keep the playhead in view: when the playhead
  leaves the visible part, during playback or after a jump, the view moves
  so the playhead sits about a third of the way in.
- A click in a lane doesn't move the playhead. It starts a marquee selection
  (see [Selecting clips](#selecting-clips)).

## Playback

| Key | What it does |
|---|---|
| Space | Play / pause |
| J | Play backwards; press again for 2×, then 4× |
| K | Pause |
| L | Play forwards; press again for 2×, then 4× |
| ← / → | Back / forward one frame (pauses) |
| ⇧← / ⇧→ | Back / forward ten frames |
| ↑ / ↓ | Previous / next edit point |
| Home / End | Go to the start / end |

**Edit points** are the start and end of the timeline and the start and end
of every clip. ↑ with nothing earlier goes to the start.

J pressed while playing forwards, or L while playing backwards, switches
direction at 1×.

Space plays and pauses wherever the focus is, except while you type in a
text field or when a focused button uses the key itself. On the preview
canvas a quick Space press still plays or pauses (when you let go), while
holding Space and dragging pans the canvas instead. Holding Space down
doesn't toggle playback over and over. Letter keys never
fire while you are typing in a field, and no editor key works while a sheet
is open.

Playback stops at the end of the timeline. An empty timeline has nothing to
play: Play beeps.

### Loop

Turn on **Loop** in the toolbar to loop playback. With an in/out range set it
loops the range; otherwise it loops the whole timeline. Pressing play at or
past the end of the loop starts again from the loop's start. Loop is set per
window and isn't saved.

### What you'll notice after an edit

- A change that only alters how something looks (a property, a colour, text)
  redraws the frame in place without interrupting playback.
- A change to the timeline's structure (a move, a trim, a new clip) rebuilds
  the player in the background. It keeps your place and keeps playing at the
  same rate. While you drag, the rebuild waits until you pause briefly.
- If a rebuild fails, an error is shown and the previous version keeps
  playing.

*Agents:* `set_playhead {t}` moves the playhead and seeks the preview.
`get_project` reports the playhead, selection and in/out range along with the
project. `render_frame` writes the frame at a time as a PNG.

## Zooming the timeline

| Way | How |
|---|---|
| Pinch | On a trackpad, about the pointer |
| ⌥-scroll or ⌘-scroll | Zoom about the pointer |
| Zoom slider | The slider in the timeline bar |
| − / + buttons | Either side of the slider, in steps about the middle of the view |
| Fit Timeline | ⇧Z, the ⇔ button, or **View ▸ Fit Timeline**. Fits the whole timeline in the view and scrolls to the start. |

A window opens at a fixed zoom of about 42 pt per second, not fitted to the
project, so press ⇧Z to see all of a long project. The zoom runs from about a
third of a point per second (hours on screen) to 4,000 pt per second (single
frames wide).

A plain scroll moves the view. **View ▸ Zoom In** (⌘+ or ⌘=), **Zoom Out**
(⌘-) and **Zoom to Fit** (⌘0) zoom the *preview*, not the timeline. They step
through the same stops as the toolbar's zoom popup (see
[Canvas and layers](canvas-and-layers.md)).

## Selecting clips

| To | Do this |
|---|---|
| Select a clip | Click it |
| Add or remove a clip | ⇧-click it |
| Select with a marquee | Drag from any empty space: a gap in a lane, the strip under the ruler, or the space below the last lane. A plain drag replaces the selection; ⇧-drag adds to it. Clips on locked tracks are skipped. |
| Clear the selection | Click empty space |
| Select everything | **Edit ▸ Select All** (⌘A): every clip, on locked tracks too |
| Select everything from the playhead on | **Edit ▸ Select After Playhead** (⌥⌘A): every clip whose start is at or after the playhead, on every track including locked ones. A clip under the playhead isn't included. |
| Select a track's clips | ⌥-click its header, or **Edit ▸ Select All on Track** |

The **selection block** at the left of the timeline bar names what is
selected: one clip's name over its track and kind (`Track 2 · video`), or a
count such as `3 clips` over the track (or `2 tracks`) and the kind (or
`mixed`). With nothing selected it reads "No selection". Selecting clips on
the timeline switches the inspector to its Clip tab.

**Edit ▸ Select All on Track** selects every clip on the current track: the
first selected clip's track, or the front track when nothing is selected. It
beeps when that track is empty. ⌥-clicking a header uses the track you
clicked.

Selection is view state: it is never an undo step and isn't saved.

*Agents:* `set_selection {clips}` (an empty list selects nothing).

## Snapping

Snapping is on by default. While on, a drag (move, trim, roll, marker or
scrub) jumps to a nearby **clip edge**, **marker**, **the playhead**,
**an in/out point**, or **the start or end of the timeline** when it comes within about 8 pt, and a thin guide line
shows what it caught. A drag that doesn't snap still lands on a whole frame.

| To | Do this |
|---|---|
| Turn snapping on or off | N, the **Snap** checkbox in the timeline bar, or **View ▸ Snapping** (checked when on) |
| Skip snapping for one drag | Hold ⌘ while you drag |

The setting is remembered between launches.

## Markers

Markers are flags on the ruler at project time. A **chapter marker** is
drawn as a filled flag and also becomes a chapter in exported movies (see
[Export](export.md)); an ordinary marker is an outline.

| To | Do this |
|---|---|
| Add a marker at the playhead | M, the bookmark button in the timeline bar, or **Mark ▸ Add Marker** |
| Move one | Drag its flag along the ruler (it snaps) |
| Rename one | Double-click its flag, or type in its row in the Document tab |
| Make it a chapter | Tick **Chapter** in its Document-tab row |
| Jump to one | **Mark ▸ Next Marker** / **Previous Marker**, or **Go** in its Document-tab row |
| Remove one | **Delete** in its Document-tab row |

The Document tab's **Markers** section lists every marker in time order with
its time, its name, **Chapter**, **Go** and **Delete**. With none it says
"No markers. Press M to add one."

A new marker is called `Marker N` and is red. Two markers can't share a frame,
so M on a frame that already has a marker beeps, and a drag onto another
marker's frame doesn't move it. **Next Marker** and **Previous Marker** pause
playback and jump; they beep when there is no marker further in that
direction, and are dimmed when the project has no markers.

Markers belong to the whole timeline. While a nest is open the ruler shows no
markers and drags don't snap to them, the three Mark ▸ marker commands are
off (a bare M beeps), and **Go** is disabled (the playhead inside a nest
counts from the nest's own start). The Document tab's Markers list still
shows every marker, and its name field, **Chapter** and **Delete** still
work.

A marker's colour is set only through an agent. The names are the six label
colours (below); any other name draws in the neutral text colour.

*Agents:* `add_marker {at?, name?, chapter?, color?}` (at the playhead when
`at` is left out), `set_marker {marker, time?, name?, chapter?, color?}`,
`remove_marker {marker}`.

## The in/out range

The in/out range is a span of the timeline shaded across the ruler and the
lanes. It sets what Loop plays, what ⌫ lifts and ⌘⌫ ripple-deletes when no
clip is selected (see [Editing](editing.md)), the span a speed ramp preset
covers when it lies inside the clip (see [Speed](speed.md)), what a new
adjustment clip covers (see [Colour grading](color-grading.md)), and what an
export writes when you choose the range.

| Key | Menu | What it does |
|---|---|---|
| I | **Mark ▸ Set In** | Sets the in point at the playhead. With no range yet, the out point goes to the end of the timeline. |
| O | **Mark ▸ Set Out** | Sets the out point at the playhead. With no range yet, the in point goes to the start. |
| ⌥X | **Mark ▸ Clear Range** | Clears the range (available only while one is set) |

Setting an in point after the out point moves the out point to match, and
the other way round. The range is view state (not an undo step, not saved),
and it's cleared whenever you enter or leave a nest.

*Agents:* `set_range {start?, end?}` (no bounds clears it).

## Clip names and labels

**Rename a clip in place**: double-click it on the timeline, or select it
and choose **Clip ▸ Rename…** (⇧⌘R). A field opens over its name strip; the
timeline scrolls it into view first if needed. Return, Tab or a click
elsewhere saves the name as its own undo step; Esc closes the field and keeps
the old name. Saving an empty field or an unchanged name does nothing. To
clear a name back to what the clip shows, use the name field at the top of
the Clip tab. Double-clicking a nest clip opens the nest instead, so rename a
nest with ⇧⌘R or the Clip tab.

The same field renames tracks (double-click the header) and markers
(double-click the flag).

**Label a clip** with **Clip ▸ Label ▸**: Red, Orange, Yellow, Green, Blue,
Purple, or None to remove it. It applies to every selected clip. The menu
checks the label when all the selected clips share it. Labels are for your
own sorting; they don't change how the clip plays or exports.

*Agents:* `set_clip {clips, patch}` with `name` and `label` in the patch (a
null or blank name clears it).

## Finding a file's clips

In the Media tab, right-click a file and choose **Reveal in Timeline**. It
selects every timeline clip that uses the file and scrolls the first one into
view. The item is disabled when the file is used only inside a nest (open the
nest to reach those clips). See [Projects and media](projects-and-media.md).

## Inside a nest

While a nest is open the timeline shows the nest's own tracks and clips from
its own zero, and the corner above the track headers shows the path back, for
example `Timeline › Intro` (hover for the full path). Click it, or press ⌘↑
(**Clip ▸ Close Nest**), to come back out one level. Entering a nest is
covered in [Editing](editing.md).

## The level meter

The two-channel meter in the timeline bar shows the mix while the project
plays and drops to silence when it stops. In a narrow window it gets smaller
and can disappear. It's described on [Audio](audio.md).

## The preview

### Preview Quality

**View ▸ Preview Quality ▸** Full, Half or Quarter draws the preview at a
fraction of the canvas size and scales it back up to fit. It makes heavy
projects play more smoothly. It never changes an export, a saved frame or a
rendered frame. The menu checks the current choice, Full is the default, and
the choice is remembered. The Preview Window (below) shows the same player,
so it draws at the same quality.

### A second preview window

**View ▸ Preview Window** (⇧⌘P) opens the picture in its own window, titled
"<project> — Preview", with no handles or guides drawn over it. Use it to
put the picture on a second display; it can go full screen. It shows the same
player as the main preview, so the two never drift apart. The menu item has a
checkmark while the window is open, and the same key hides it again. The
window remembers where you put it and stays visible when you switch to
another app. While it has the focus, the playback keys and the editor's other
bare keys still work, and so does Undo. It closes with its project window.

### Other View items for the preview

- **View ▸ Safe Areas**: the same title-safe / action-safe guides as the
  toolbar's **Safe** checkbox (checked when on).
- **View ▸ Show Ungraded** (⌃⌘U), **Show Selection** and **Scopes** (⌃⌘W):
  see [Colour grading](color-grading.md).
- **View ▸ Show SDR Version**: see [HDR and colour management](hdr-and-color.md).
- **View ▸ Assistant** (⌃⌘A): see [Assistant](assistant.md).

## What is remembered

| Setting | Remembered between launches |
|---|---|
| Timeline height, inspector width, inspector hidden | Yes |
| Snapping, track size, Safe Areas, Preview Quality | Yes, for every project |
| Preview Window position | Yes |
| Timeline zoom, Loop, playhead, selection, in/out range | No |

## Limits

- Markers live on the main timeline only. Inside a nest the ruler shows
  none, drags don't snap to them, and you can't add one, step to one or jump
  to one; the Document tab can still rename, chapter and delete them.
- Clips on a locked track can be clicked and selected, but not dragged or
  trimmed, and a marquee skips them.
- A marker's colour can only be changed by an agent.
- The timeline zoom has no menu item or keyboard shortcut except ⇧Z (fit).

See [Menus and shortcuts](menus-and-shortcuts.md) for every key in one place.
