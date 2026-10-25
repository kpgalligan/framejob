# Editing clips

This page covers the edits you make to clips and to time on the timeline: putting clips on it, moving and trimming them, cutting, deleting and closing gaps, copying and pasting, and grouping clips into nests. Each edit is one undo step, and a gesture counts as one edit however long the drag lasts. When the project's rules won't allow an edit, the app beeps, changes nothing and tells you why.

Changing a clip's speed, freezing a frame and reversing a clip are covered in [Speed](speed.md). Transitions are covered in [Motion and transitions](motion-and-transitions.md). Selecting, zooming, scrubbing and the track headers are covered in [Timeline](timeline.md).

## What an edit acts on

Most commands act on the **selection**, the clips outlined in coral on the timeline. Some also use the **playhead**, the **in/out range**, or the **current track**:

- **The selection.** Click a clip to select it. ⇧-click adds a clip or takes it out. Drag from empty space to select by marquee. ⌘A (**Edit ▸ Select All**), ⌥⌘A (**Edit ▸ Select After Playhead**, every clip that starts at or after the playhead) and **Edit ▸ Select All on Track** also select. ⌥-clicking a track header selects every clip on that track. See [Timeline](timeline.md).
- **The playhead.** Split, trim to playhead, freeze frame, paste, insert and overwrite all work at the playhead.
- **The in/out range.** I sets the in point, O sets the out point and ⌥X clears both (**Mark ▸ Set In / Set Out / Clear Range**). With nothing selected, Delete and Ripple Delete act on the range instead.
- **The current track** is the track of the first selected clip, or the front-most track when nothing is selected. Close Gap, Select All on Track, and Insert / Overwrite at Playhead use it.

Clips on a **locked** track can't be dragged, trimmed, slipped or rolled. A marquee skips them, and the edits that shift everything later in time leave them where they are. See [Limits](#limits).

*Agents:* `set_selection`, `set_playhead` and `set_range` set the same view state. They are not edits and make no undo step.

## Adding clips from the Media tab

Drag a file's row from the Media tab onto a track. What the drop does depends on the modifier keys you hold **when you release**:

| Drop | What it does | Undo name |
|---|---|---|
| No modifier | Places the whole file as a clip at the drop point. Nothing else moves. The drop is refused if the clip would overlap its neighbours in a way the overlap rule forbids. | Add Clip |
| ⌥ | **Insert.** Splits the clip under the drop point on that track, pushes everything on every unlocked track later by the file's length, then places the file in the gap. Only the destination track is cut. Clips on other tracks that span the drop point stay where they are, uncut; only clips that start at or after it move later. | Insert |
| ⇧⌥ | **Overwrite.** Clears the file's length from the drop point on that track alone, cutting at both ends and removing what lies between, then places the file. Nothing moves and no other track is touched. | Overwrite |

Dropping a row on the **preview canvas** adds the file at the playhead on a new track at the front.

The same two placements also work without dragging. Select a row in the Media tab, then choose **Edit ▸ Insert at Playhead** or **Edit ▸ Overwrite at Playhead**. They place the file on the current track at the playhead. Neither has a shortcut. Right-clicking a row gives you the same two items for that file. Both are greyed out when no media row is selected, and for a `.cube` LUT, which is applied as a look rather than placed (see [Colour grading](color-grading.md)).

A new clip covers the whole file, rounded down to whole frames so it never runs past the end of the file. Footage larger than the canvas is fitted when the project's fit-new-clips setting is on. Importing files is covered in [Projects and media](projects-and-media.md).

*Agents:* `add_clip`, `insert_clip` and `overwrite_clip` take `track`, `media` and `at`.

## Moving clips

Drag a clip's body to move it in time. Drag it up or down to move it to another track. If several clips are selected, dragging any one of them moves them all and keeps their timing and track offsets. Starts stop at zero.

- **Onto a new track:** drop above the top lane to make a new front track, or below the bottom lane to make a new back track.
- **Duplicate while dragging:** hold ⌥ when you press. Copies are dragged and the originals stay put (undo name "Duplicate Clips").
- **Refused drops spring back.** If the drop breaks the overlap rule (see [Limits](#limits)), the clip animates back to where it was and nothing changes. While you drag, positions the project refuses are skipped, and the clip stays at the last allowed position.
- **Overlaps make transitions.** A clip dropped so it overlaps the clip before it on the same track gets a Cross Dissolve over the overlap, unless it already has a transition. Clips never push each other out of the way. Other edits do the same; see [Overlaps make transitions](#overlaps-make-transitions).

The whole drag is one undo step, "Move Clips".

### Nudging

`,` and `.` move the selection one frame earlier or later. With ⇧ they move it ten frames. A nudge is an ordinary move, so the overlap rule can refuse it (undo name "Nudge Clips").

*Agents:* `move_clip` takes `clips` and a `delta` in ticks. The optional `track` is the destination track for the first clip; the others keep their track offsets from it. Leave it out to stay on the current tracks.

## Trimming

Drag either edge of a clip to trim it. The edge is the outer 7 points of the clip: the pointer becomes a left-right resize cursor there, and the selected clip shows trim grips. A clip too narrow on screen (under about 21 points) has no edges, so zoom in to trim it. Clips on locked tracks show no resize cursor.

- A **start trim** moves the clip's start and its in point together, so the frame under the edge stays put and the rest of the clip stays where it is on the timeline.
- An **end trim** moves the clip's end.
- A clip always keeps at least one frame. A media clip's trim stops at the start and end of its file. Stills, text, shapes and graphics have no file length, so they trim freely.
- The whole drag is one undo step, "Trim Clip".

To trim to the playhead, press **W** (**Clip ▸ Trim Start to Playhead**) or **E** (**Clip ▸ Trim End to Playhead**), or click the matching buttons in the timeline bar. They trim each selected clip that the playhead is inside. If the playhead isn't inside any selected clip, the menu items are greyed out and the keys beep. W undoes as "Trim Start" and E as "Trim End", one step for all the clips they trim.

### Rate stretch

Hold ⌥ while you drag a media clip's **end** edge to stretch it instead. The clip's speed changes so that the same content fills the new length (undo name "Rate Stretch"). ⌥ on the start edge does an ordinary trim. If a stretch would take the clip above the speed where its sound is dropped, the app asks first. Speeds and their limits are covered in [Speed](speed.md).

*Agents:* `trim_start` and `trim_end` take `clip` and `to`. `rate_stretch` takes `clip` and `to_end`.

## Slip and roll

Both keep something fixed on purpose.

| Gesture | What it does | Undo name |
|---|---|---|
| ⌥⇧-drag a clip's body | **Slip.** The clip stays where it is on the timeline, at the same length, and the footage slides underneath it. You choose which part of the file it shows. It stops when the clip reaches either end of the file. A still slips the frame it holds. | Slip |
| ⌥⇧-drag a clip's edge | **Roll.** Moves a cut between two clips that touch. One clip gets longer and the other gets shorter by the same amount, and nothing else moves. Each clip keeps at least one frame and can't extend past its own file. | Roll |

A slip doesn't snap, because the timeline's snap points mean nothing inside the footage. It still moves in whole frames. A roll snaps like a trim.

A roll needs two clips that touch exactly. The start edge rolls the cut with the clip before, and the end edge rolls the cut with the clip after. Where there is a gap or an overlap (a transition) at that edge, there is no cut to roll and the drag does nothing. A slip on a clip with nothing to slip, such as text, a shape or a nest, is an error.

*Agents:* `slip` takes `clip` and `delta`. `roll` takes `clip` (the clip to the right of the cut) and `to`. A roll is refused with "no clip on track … ends where clip … begins" when the clips don't touch.

## Splitting

**Clip ▸ Split** (⌘T, or the scissors button in the timeline bar) cuts at the playhead:

- With clips selected, it cuts each selected clip the playhead is strictly inside.
- With nothing selected, it cuts every clip under the playhead on every unlocked track.

The second piece carries on playing the footage from where the first stopped. Animation actions stay with the piece they fall in, and an action that spans the cut becomes two. Caption word timings stay on their words.

*Agents:* `split` takes `at` (the playhead when left out) and optional `clips`. Without `clips` it cuts every unlocked clip at that time.

## Deleting

The two delete keys pair up. Each acts on the selection, or on the in/out range when nothing is selected. The difference is whether the hole closes.

| Command | Selection | In/out range, nothing selected |
|---|---|---|
| **Edit ▸ Delete** (⌫) | **Delete:** removes the clips and leaves gaps. | **Lift:** cuts every unlocked clip at both ends of the range and removes what lies between. Nothing moves, markers included. |
| **Edit ▸ Ripple Delete** (⌘⌫, or the timeline bar's button) | **Ripple Delete:** removes the clips, then closes each hole they leave. Everything later on every unlocked track moves left by the hole's length. | **Ripple Delete:** cuts every unlocked clip at both ends of the range, removes what lies between, and closes the hole. |

- Each hole closes with one shift of everything after it, so clips that touched before still touch. A clip past several holes moves by their combined length. Clips on other tracks that span the hole stay where they are. **Markers don't move** in a ripple delete.
- With an animation action selected, ⌫ removes that action instead of its clip. See [Motion and transitions](motion-and-transitions.md).
- Both items are greyed out while you are typing in a text field, so ⌫ and ⌘⌫ still edit text there. They are also greyed out when nothing is selected and no range is set.
- **Clip ▸ Remove Silences…** and **Clip ▸ Remove Filler Words…** each make many ripple cuts as a single undo step. See [Remove Silences and Remove Filler Words](cleanup-tools.md).

*Agents:* `delete` and `ripple_delete` take `clips`. `lift_range` and `ripple_delete_range` take `from` and `to`; a reversed pair means the same range. `ripple_delete_ranges` takes a list of `[from, to]` pairs. It merges pairs that touch or overlap, then cuts them all as one edit.

## Closing gaps and inserting time

**Double-click an empty stretch of a lane** to close that gap. Everything after the gap, on every unlocked track, moves left by the gap's length. **Clip ▸ Close Gap** does the same for the gap under the playhead on the current track. A gap before the first clip of a track closes back to zero. Undo name: "Close Gap".

A gap closes completely or not at all. The edit is refused when:

- the point you chose is on a clip, not in a gap;
- no clip follows the gap;
- the track is locked;
- closing it would push clips on another track into an overlap the overlap rule forbids.

**Inserting time** opens empty room instead. Every clip on an unlocked track that starts at or after a point moves later by a length, and so does every marker at or after it. Clips that span the point stay put, so nothing is cut (split first if you want the room inside a clip). No menu item or gesture does this on its own. ⌥-drop insert and Freeze Frame both use it as part of their edit, and agents can call it directly.

To open room by hand, press ⌥⌘A (**Edit ▸ Select After Playhead**) and drag the selected clips later, or nudge them with ⇧. (period). Unlike Insert Time, this also moves selected clips on locked tracks, and it leaves markers where they are.

*Agents:* `close_gap` takes `track` and `at`. `insert_time` takes `at` and `length`.

## Duplicating

**Edit ▸ Duplicate** (⌘D, or the timeline bar's button) puts a copy of each selected clip on the same track, starting right after the selection's span. A selection of several clips keeps its internal timing. The duplicate is refused if the copies would break the overlap rule. To place copies somewhere else, ⌥-drag instead (see [Moving clips](#moving-clips)).

*Agents:* `duplicate` takes `clips`.

## Copy, cut and paste

| Command | Shortcut | What it does |
|---|---|---|
| **Edit ▸ Copy** | ⌘C | Puts the selected clips on the clipboard, with the media files they show. Pasted into a text editor, they arrive as a one-line summary such as "Frame Job — 2 clips, 00:00:01:00 to 00:00:04:00". |
| **Edit ▸ Cut** | ⌘X | Copies, then deletes the selection and leaves gaps, as ⌫ does. One undo step. |
| **Edit ▸ Paste** | ⌘V | Pastes the clipboard's clips at the playhead, then selects them. |
| **Edit ▸ Paste Attributes** | ⌥⌘V | Copies the copied clip's look onto every selected clip. |
| **Edit ▸ Paste Graphic Properties** | — | Copies a copied graphic's properties onto the selected clips drawn by the same graphic. See [Graphics](graphics.md). |

Cut and Copy are greyed out with nothing selected. Paste is greyed out unless Frame Job clips are on the clipboard; it never pastes another app's text or files. Paste Attributes also needs a selection, and Paste Graphic Properties a selected graphic clip.

**Paste** keeps the copied arrangement. The earliest clip lands at the playhead and the others keep their distance from it. The copied front-most lane goes onto the front track, the lanes behind it onto the tracks behind, and tracks are added at the back if there aren't enough. A pasted clip that would break the overlap rule goes on a new track at the front, so a paste is never refused for lack of room. You can paste into another project. Media is matched by file path and added to the project when it isn't there yet. Pasted clips get new identities and are snapped to the project's frame rate.

**Paste Attributes** takes the look of the copied clip that starts earliest, then replaces each matching group on every selected clip with it. A group is only copied when both clips have it:

| Group | What travels | What the target keeps |
|---|---|---|
| Video | Everything: position, scale, rotation, crop, opacity, effects, grade | — |
| Audio | Everything: volume, pan, fades, effects | — |
| Text | Font, size, colours, layout, animation | Its own words and their timings |
| Shape | Fill, stroke, gradient and the rest of the style | Its kind, size and end points |

The target keeps its place, length, speed, animation actions, transition, name, label, and which halves (picture and sound) are switched on. If nothing would change, it beeps.

*Agents:* `paste` takes `at` (the playhead when left out) and a `payload` shaped like what Copy writes, `{"clips": […], "media": […]}`. A payload clip's `track` is its depth from the front, 0 being the front-most lane. The optional `track` argument is the track id where depth 0 lands (default: the front track); deeper lanes follow behind it, and tracks are added as needed. `paste_attributes` takes `clips`, the same `payload`, and optional `groups` and `skip_missing`.

## Splitting picture from sound

**Clip ▸ Detach Audio** (⌥⌘D) switches off each selected clip's sound and adds an audio-only copy of it on the track below, at the same time, with the same footage and speed. If the clip is on the back track, a new track is added behind it. Undo name: "Detach Audio".

Each clip that can't be detached is refused with a reason: "clip … has no audio to detach: it is not a media clip", "…: media … has no audio track", or "…: its audio is switched off".

A clip's picture and sound can each be switched on or off. The app's only control for this is Detach Audio. Agents can set either half directly.

*Agents:* `detach_audio` takes `clip`. `set_enabled` takes `clip` and `video` and/or `audio` (true or false). Leave one out to keep its value.

## Nests

A nest collapses several clips into one clip that stands for the group. From then on, the group moves, trims, fades and transforms as one thing.

### Making and opening up a nest

**Clip ▸ Nest** (⌘G) groups the selected clips:

- The new nest clip goes on the front-most track the selection used. It runs from the earliest start to the latest end and is selected afterwards.
- Inside the nest, the clips keep their properties, actions and transitions, their timing relative to each other, and their stacking order.
- The nest's own canvas is fixed at the project's size at the moment you nest. Changing the project size later doesn't re-lay out what's inside. To change a nest's size, un-nest it (⇧⌘G), change the project size if you need to, and nest again (⌘G). Opening the nest lets you edit its contents but not its size.
- It's named "Nest 1", "Nest 2", and so on. Double-clicking a nest clip opens it, so rename a nest clip with ⇧⌘R (**Clip ▸ Rename…**) or the Clip tab's name field.
- Greyed out with nothing selected, and when the only selected clip is already a nest clip. Refused when the nest clip would break the overlap rule, and when the selection holds an adjustment clip, which can't go inside a nest.

**Clip ▸ Un-nest** (⇧⌘G) opens every selected nest clip back out, in one undo step, and selects what came out:

- The clips return to the timeline at the nest clip's start plus their own times, on tracks counted back from the nest clip's track. Missing tracks are added.
- A clip that would break the overlap rule goes on a new front track instead of being lost.
- A nest clip trimmed shorter than its contents still gives everything back. Trimming a nest hides content but doesn't cut it.
- Un-nesting discards the nest clip's own transform, opacity, fades and volume. To change the contents and keep those, open the nest and edit inside it (below).

### Editing inside a nest

You can edit a nest's contents in place instead of un-nesting:

- **Go in:** double-click a nest clip, or select one nest clip and choose **Clip ▸ Open Nest** (⌘↓).
- **Come out one level:** **Clip ▸ Close Nest** (⌘↑).
- **Breadcrumb:** while a nest is open, the corner above the track headers shows a path such as "Timeline › Intro". It shows the last two levels, and hovering it shows the full path. Clicking it goes out one level, like ⌘↑.

Nests can contain nests, up to eight levels deep.

Open Nest needs exactly one nest clip selected, and Close Nest is greyed out at the top level. Both are greyed out while you are typing in a field.

### Shared and independent copies

Split, Duplicate (⌘D) and ⌥-drag copies of a nest clip share one nest. Editing inside any of them changes them all, and the nest is only removed once no clip shows it. Copy and Paste make an independent copy, so editing a pasted nest leaves the original alone.

Inside, the timeline shows the nest's own tracks and clips from the nest's own zero. The canvas shows the nest at its fixed size, without the nest clip's position or scale, so you edit the group on its own terms. The playhead is mapped in and out, so the frame under it doesn't change.

When you go in, the selection is cleared. When you come out, the nest clip is selected again. Going in and coming out aren't edits: there is no undo step, and the project isn't marked as changed. The in/out range is cleared both ways, because a range means one thing inside a nest and another on the timeline.

Every clip edit on this page works inside a nest, and each one is still one undo step on the project's single undo history. Some things belong to the whole project rather than to a nest:

- **Markers.** Add Marker and Next / Previous Marker are greyed out inside a nest. A nest has no markers of its own.
- **Media and project settings.** Adding, relinking or removing media and changing the Document tab still work with a nest open. They change the whole project.
- **Adjustment clips.** **Insert ▸ Adjustment Clip** is greyed out inside a nest.

Some limits count the whole project even while you edit inside a nest: up to 4,096 clips and 64 tracks, and the eight-level nesting depth. An edit that is fine inside the nest can still be refused when the whole project would go over one of them.

*Agents:* `nest` takes `clips` and an optional `name`. `unnest` takes `clip`. Every edit tool takes an optional `scope`, a nest id, which applies the edit inside that nest using the nest's own ids and times. Nine edits are an error with a scope: the three marker edits, `set_canvas`, `add_media`, `relink_media`, `remove_media`, `set_media_color` and `add_adjustment_clip`. `set_scope` opens a nest in the window itself, so that `get_project` and `render_frame` show its contents. It is view state, not an undo step.

## Removing empty tracks

**Track ▸ Remove Empty Tracks** removes every track that holds no clips. If every track is empty, the back-most track stays. Other track commands are covered in [Timeline](timeline.md).

*Agents:* `remove_empty_tracks`.

## Snapping

Moves, trims, rolls, marker drags and playhead scrubs snap to nearby points. A point is close enough within about 8 points on screen. Snap points are:

- the start and the end of the timeline;
- the edges of every other clip;
- markers;
- the playhead;
- the in and out points.

Toggle snapping with **N**, **View ▸ Snapping**, or the timeline bar's **Snap** checkbox. Hold ⌘ during a drag to stop snapping for that drag. Pressing or releasing ⌘ mid-drag takes effect at once. When snapping is off or nothing is close, times still land on whole frames. A slip never snaps.

When a drag snaps, a vertical guide line across the timeline marks the point it snapped to. A media row dropped on a lane lands on the nearest frame at the pointer and doesn't snap to edges.

## Undo and redo

**Edit ▸ Undo** (⌘Z) and **Edit ▸ Redo** (⇧⌘Z) walk back and forward one step at a time. The Edit menu names the step, for example "Undo Move Clips".

What counts as one step:

- **A menu command or key** is one step, even when it changes many clips. Examples: Ripple Delete over a range, Un-nest of several nests, Detach Audio on a selection, a Remove Silences pass.
- **A gesture** is one step from mouse-down to mouse-up: a move, trim, rate stretch, slip, roll or duplicate-drag. A click that selects without moving makes no step.
- **No step at all** for anything that doesn't change the project: selecting, moving the playhead, setting the in/out range, going into or out of a nest, a refused edit, and an edit that would leave everything as it was.

A new edit clears the redo history.

*Agents:* `undo` and `redo` take nothing. Each edit tool call is exactly one step, so one `undo` takes back exactly one call. `undo` reports the name of the step it took back. It is an error when there is nothing to undo.

## When an edit is refused

When the project's rules won't allow an edit, the app **beeps** and nothing changes. The rule's own sentence appears at the **foot of the inspector** after "Refused: ", for example "Refused: clips 4 and 7 would overlap by 120000 ticks, more than half of the shorter clip (100000 ticks)". The message stays until the project changes (an edit, an undo or redo, or going into or out of a nest) or until you click it. Moving the playhead or changing the selection doesn't clear it.

An edit that would change nothing, such as a slip already at the end of the footage or a paste of a look the clips already have, beeps too, but shows no message: no rule was broken. A request the project can't use at all, such as a pasted value outside its allowed range, shows an error alert instead.

During a drag, positions the project refuses are skipped and the clip waits at the last allowed position. Only the drop counts.

*Agents:* an applied edit answers `ok` with a project summary and the ids of anything it created. An edit that changed nothing fails with "… made no change: the project is already in that state." A refused edit fails with "… was refused at <op>: <the rule's sentence>". Neither makes an undo step.

## Limits

- **The overlap rule.** On one track, a clip may overlap at most one neighbour on each side, and each overlap may be at most half the length of the shorter clip. Moves, trims, nudges, duplicates, gap closes and nests that would break it are refused. Paste and Un-nest put such clips on a new front track instead. Ripple deletes are never refused by it: a clip a ripple slides onto a neighbour gets a Cross Dissolve (below).
- <a id="overlaps-make-transitions"></a>**Overlaps make transitions.** Any edit that leaves a clip overlapping the clip before it on its track gives it a Cross Dissolve over the overlap, unless it already has a transition: moves, trims, duplicates, pastes, ripple deletes, Close Gap, Nest and Un-nest. See [Motion and transitions](motion-and-transitions.md).
- **Locked tracks.** Their clips can't be dragged, trimmed, slipped or rolled, and a marquee doesn't select them. Split with nothing selected, Lift, and the range form of Ripple Delete leave them uncut. Ripples, gap closes and inserted time don't shift them. Insert onto a locked track and Close Gap on a locked track are refused. A clip on a locked track that you select by clicking is still removed by Delete or Ripple Delete, and Overwrite still clears a locked track.
- **One frame minimum.** Trims and rolls always leave a clip at least one frame long.
- **Footage bounds.** A media clip can't be trimmed, rolled or slipped past either end of its file.
- **Project size.** Up to 4,096 clips, 64 tracks and eight levels of nesting.
- **Times are frames.** Every time you set lands on the project's frame grid.

## Shortcuts

| Keys | Command |
|---|---|
| ⌘T | Split at the playhead |
| W / E | Trim start / end to the playhead |
| ⌫ | Delete the selection, or lift the in/out range |
| ⌘⌫ | Ripple delete the selection or the in/out range |
| ⌘D | Duplicate |
| ⌘X / ⌘C / ⌘V | Cut / copy / paste |
| ⌥⌘V | Paste Attributes |
| ⌥⌘D | Detach Audio |
| ⌘G / ⇧⌘G | Nest / Un-nest |
| ⌘↓ / ⌘↑ | Open Nest / Close Nest |
| `,` / `.` | Nudge one frame earlier / later (⇧: ten frames) |
| ⌘Z / ⇧⌘Z | Undo / Redo |
| N | Snapping on or off |
| ⌘A / ⌥⌘A | Select All / Select After Playhead |
| ⌥-drag clip | Duplicate while moving |
| ⌥-drag end edge | Rate stretch |
| ⌥⇧-drag clip body | Slip |
| ⌥⇧-drag clip edge | Roll |
| ⌘ during a drag | Suppress snapping |
| Double-click a gap | Close Gap |
| Double-click a nest clip | Open the nest |
| ⌥-drop / ⇧⌥-drop a media row | Insert / Overwrite at the drop |

Every shortcut in the app is listed in [Menus and shortcuts](menus-and-shortcuts.md).
