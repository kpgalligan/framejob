# Manual checks

The standing list of checks only a person at the machine can do: things
that need eyes, ears, a real mouse and keyboard, a second display, a real
network, a real API key or macOS permissions. Everything a script can
measure is already in `tools/proof/` and is not repeated here.

**When to run it.** Run every section before a release. Between releases,
run the sections whose area changed. Unless a check says otherwise, run it
in both appearances (System Settings ▸ Appearance, Light then Dark).

## Setup, once per run

1. Build: `make app`.
2. Open the Release app from the Finder, or with
   `open "build/Build/Products/Release/Frame Job.app"`. **Not from a terminal**:
   a terminal-launched app's permissions (Screen Recording, Microphone)
   belong to the terminal, not to Frame Job. Only REC-3, REC-7, REC-8's
   step 6 and HS-2 launch from a terminal on purpose.
3. Have to hand:
   - **Real footage**: a 1080p movie with sound, a long recording (twenty
     minutes or more), an AAC file and a WAV file.
   - **Synthetic test media**, where a check names it: make it once with the
     `ffmpeg` lines under "Make the test media once" in
     `tools/proof/README.md` (into `tools/proof/media/`).
   - **Graphics projects** (GR): `RC_PROOF_APP=release python3 tools/proof/graphics_playback_samples.py`
     builds `Playback-1080p`, `Playback-4K`, `Error-card` and
     `Playback-4K-animated` into `tools/proof/work/playback-check/`. Rebuild them on a fresh checkout.
   - **Keys**: your own AssemblyAI key for Cloud captions (Frame Job ▸
     Settings… ▸ Transcription) and your own Anthropic API key for the
     Assistant (Frame Job ▸ Settings… ▸ Assistant). No script ever uses a real
     key.
4. **The compositor's timing log** (PB-2, PB-3):
   `defaults write com.kgalligan.FrameJob FrameJobCompositorTiming -bool YES`,
   relaunch, and read it in Console.app filtered on `[framejob] compositor`
   (average and worst milliseconds per 120 frames). Turn it off afterwards
   with `defaults delete com.kgalligan.FrameJob FrameJobCompositorTiming`.

## Reporting a failure

File a GitHub issue naming the check ID in its title, for example
`PB-4: the preview window forgets its display after a relaunch`, with what
you did and what you saw. A check marked **Answer:** asks for a judgement;
put the answer in an issue (or a comment on the issue cited in its Source)
the same way.

---

## Playback and picture

**PB-1 — A clip plays with audio, in sync, frame-exact**
- **Do:** 1. Import a 1080p movie with sound. 2. Play with Space; use J / K / L (L again for 2×, 4×). 3. Scrub the playhead. 4. Pause and step with ← / → and ⇧← / ⇧→.
- **Expect:** sound in sync with the picture; J/K/L reverse, pause and speed up; scrubbing follows the pointer; each arrow press moves exactly one frame (ten with ⇧).
- **Source:** spec §10 step 4; #47.

**PB-2 — Playback holds 60 fps**
- **Do:** 1. Turn on the timing log (Setup 4). 2. Play the 1080p movie for a minute at View ▸ Preview Quality ▸ Full.
- **Expect:** no visible stutter; the log's average stays under 16.7 ms and its worst rarely passes it.
- **Source:** spec §10 step 5; #47.

**PB-3 — Preview Quality is actually faster**
- **Do:** 1. With the timing log on, play the same span at Full, then at Quarter. 2. Repeat with a drop shadow on the clip.
- **Expect:** Quarter's average is clearly lower than Full's. With a shadow, the gap is smaller (shadow passes run at canvas size; known). At Half and Quarter the picture is Full's, softer: the same framing, nothing shifted or cropped.
- **Source:** #47, #91.

**PB-4 — The two previews agree, and the preview window remembers where it was**
- **Do:** 1. Press ⇧⌘P on the real keyboard (View ▸ Preview Window). 2. Play, pause, scrub; compare it with the main preview side by side. 3. Drag the preview window to a second display, quit, relaunch, reopen it.
- **Expect:** both previews show the same frame at every pause; the window comes back on the second display, at the same size.
- **Source:** #47.

**PB-5 — A nest plays once open**
- **Do:** 1. Select two clips, Clip ▸ Nest (⌘G). 2. With the nest selected press ⌘↓ on the real keyboard; play. 3. Press ⌘↑.
- **Expect:** inside the nest, sound plays and the frame rate is smooth; ⌘↓ and ⌘↑ open and close it from the keyboard.
- **Source:** #47.

**PB-6 — A saved project opens quickly; a relinked clip updates on screen**
- **Do:** 1. Save a project holding the long recording; quit; reopen it. 2. Move one of a project's media files to another folder; reopen the project; relink it in the Relink… sheet it offers. 3. In the Media tab, Relink… a 10 s media to `AV.mov`. 4. Move two of a project's video files away and reopen it; in the Missing media sheet Locate… `toneA.m4a` for one and a video file for the other; press Relink. 5. In the Media tab, Relink… a media with sound (a clip on it showing a waveform) to `A.mov`. 6. File ▸ Add Media… two files that are not media (two text files renamed `.png`).
- **Expect:** the reopen is quick, with no long re-analysis. After relinking, the clip's filmstrip redraws with the file's frames. After step 3, the row reads 5 s, and the whole-file clip ends at 5 s. After step 4, the video file relinks, and then an alert sheet shows the refusal in the core's own words ("… is video media and … is audio: relink it to a file of the same kind …"); with two refused files, a second alert follows the first once it is dismissed. After step 5, the clip's waveform goes at once. After step 6, an alert names the first file, and once it is dismissed a second names the other.
- **Source:** #47; step 3, #63; steps 4–5, #180; step 6, #195.

**PB-7 — Waveforms have no gaps**
- **Do:** 1. Import an AAC file, a WAV file and a recording made by Frame Job. 2. Look at each clip's waveform at M and L track height. 3. On the long recording, open Clip ▸ Remove Silences… while it is still being analysed.
- **Expect:** no gap or flat tail where there is sound. While decoding, the sheet names the file ("The waveform is still being analysed for …") until the decode finishes.
- **Source:** #47 (#23).

**PB-8 — A project whose media moved opens and offers Relink**
- **Do:** Use the installed or current build, and note which `Frame Job.app` actually opened the file (its path in the Dock menu or Activity Monitor). 1. Save a project with two clips; quit. Move the `.framejob` and its media together into a new folder, then open it from the Finder with right-click ▸ Open With ▸ Frame Job. 2. Move a media file while the project is OPEN in Frame Job, wait for an autosave, quit, and reopen it. 3. Move a media file to another volume (an external drive or a disk image), unmount it, and reopen the project.
- **Expect:** each time, the project opens. Media that is still findable plays. Media that is gone shows slates, with the Missing media sheet offering Locate… and Relink. Never an open failure, a hang or a crash.
- **Source:** #131 (the owner's report of 2026-09-26, not reproduced by the agents). On a failure, add to #131 which app opened the file and exactly what happened: an alert and its text, a hang, a crash, or no window.

**PB-9 — A VP9 MP4 plays, in sync, and scrubs**
- **Do:** 1. Make a VP9 MP4 with sound, e.g. `ffmpeg -f lavfi -i testsrc2=size=1280x720:rate=30:duration=10 -f lavfi -i sine=frequency=440:duration=10 -c:v libvpx-vp9 -pix_fmt yuv420p -c:a aac vp9.mp4`, or use a VP9 download from the web in an MP4. 2. Drop it into a project and place it. 3. Play it in the preview, then scrub the playhead across it and step with ← and →.
- **Expect:** it imports with no alert, plays with its sound in sync, and every scrub and step shows the right picture; the filmstrip fills in.
- **Source:** #216 (issue batch B72; `codec_import_proof.py` scripts import, frames and export).

**PB-10 — Real WebM and MKV files import, play in sync, scrub and export**
- **Do:** 1. Get three real files: a YouTube VP9 WebM (e.g. from `yt-dlp -f 'bv*[ext=webm]+ba[ext=webm]'`), a Chrome screen recording (a page using `MediaRecorder`, or any site that saves a `.webm` recording) and an OBS recording saved as MKV with sound. On an M3 or later Mac, also an AV1 WebM. Make a Vorbis WebM beside them: `ffmpeg -f lavfi -i testsrc2=size=640x360:duration=10 -f lavfi -i sine=frequency=440:duration=10 -c:v libvpx-vp9 -c:a vorbis -strict -2 -ac 2 v.webm`. 2. Drop each into a project with no ffmpeg setting changed, and place it. 3. Play it, scrub across it and step with ← and →. 4. Export the project as H.264 and play the export.
- **Expect:** each imports with no question and no alert, as a `.mov` under `~/Library/Application Support/Frame Job/Rewrapped/`. It plays with its sound in sync, every scrub and step shows a picture, and the export plays in sync. The Vorbis WebM imports the same way and plays with its sound in sync.
- **Source:** #216 (issue batch B73, spec §11 #216-R; `container_rewrap_probe.py` and `container_import_proof.py` script generated files only); Vorbis by issue batch B77 (spec §11 #228-V).

**PB-11 — A long WebM or MKV copy shows its progress and can be cancelled**
- **Do:** 1. Make or get a WebM or MKV of 2 GB or more (e.g. `ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30:duration=1200 -f lavfi -i sine=frequency=440:duration=1200 -c:v libvpx-vp9 -b:v 12M -deadline realtime -cpu-used 8 -c:a libopus big.webm`); if a copy of it is already in `~/Library/Application Support/Frame Job/Rewrapped/`, delete it first. 2. In an open project with a text clip, choose File ▸ Add Media… and pick it with a short `.mov`; as soon as the window appears, double-click the text clip on the canvas and type, then press Escape. 3. Click into the copy window, press Escape. 4. Add the same file again and let it finish. 5. Delete its copy, quit, and open the file from the Finder with Open With ▸ Frame Job; press Cancel.
- **Expect:** a small "Copying Movie" window appears about a second after the copy starts, naming the file, with a moving bar, "`<copied>` of `<total>`" and Cancel. It does not take the keyboard: the typing and the first Escape reach the text editor, and the copy goes on. After the click into the window, Escape cancels: the button reads "Cancelling…", the window closes, no alert appears, the `.mov` is added and the WebM is not, and `Rewrapped/` holds no `.partial.mov`. The second import shows the window and ends with the file added; a third import of it adds it at once with no window. The Finder open shows the window in front with the keyboard, and its Cancel opens no project and shows no alert.
- **Source:** #228 (issue batch B76, spec §11 #228-P; `container_rewrap_probe.py` C20–C30 script the copy, the doors and the Cancel, never the window on screen).

**PB-12 — A WebM or MKV keeps its own name, Reveal in Finder shows it, and a deleted copy comes back**
- **Do:** 1. Make a WebM of 2 GB or more as in PB-11 (`big.webm`), or use PB-11's; delete any copy of it in `~/Library/Application Support/Frame Job/Rewrapped/`. 2. Add it to a project, place it and save. 3. Look at its row in the Media tab and at the clip's name on the timeline; hold the pointer over the row. 4. Right-click the row ▸ Reveal in Finder. 5. Quit. In the Finder, delete its `.mov` in `Rewrapped/` (Move to Trash; do NOT empty the Trash). 6. Open the project again; let the copy finish. 7. Play the clip.
- **Expect:** the row and the clip are named `big.webm`, not `big-<16 hex>.mov`. The tooltip's first line is "`<the WebM's path>` — copied into Frame Job's Rewrapped folder.", above the drag hint. Reveal in Finder selects the WebM, not the `.mov`. On reopening, the "Copying Movie" window appears about a second in, and when it closes the project shows no missing badge and no Missing media sheet; the clip plays from a new `.mov` in `Rewrapped/` (Reveal in Finder still shows the WebM), and the `.mov` in the Trash is left there.
- **Source:** #228 (issue batch B78, spec §11 #228-O; `container_rewrap_probe.py` O31–O43 and `container_import_proof.py` M8–M11 script the name, the tooltip text, the reveal URL and the re-copy, never the window, the tooltip or Finder on screen).

**PB-13 — An MKV the ffmpeg step converts copies its VP9 video, keeps its own name and steps frame by frame**
- **Do:** 1. Make an MKV: `ffmpeg -f lavfi -i testsrc2=size=640x360:rate=30:duration=10 -f lavfi -i sine=frequency=440:duration=10 -c:v libvpx-vp9 -pix_fmt yuv420p -c:a flac v.mkv`. 2. Quit Frame Job and launch it with `open "build/Build/Products/Release/Frame Job.app" --args -RCFFmpegImport ask`. 3. Drop the MKV into a project and read the question; press the first button. 4. Place the clip, play it, scrub across it and step with ← and →.
- **Expect:** the question says the video can be copied as it is and the flac soundtrack has to be re-encoded to AAC. The Media tab row and the clip are named `v.mkv`. It plays with its sound in sync, every scrub shows a picture and every single-frame step shows a new one.
- **Source:** #227, #233 (issue batch B80, spec §11 #227 and #233; `ffmpeg_rewrap_proof.py` scripts the plan, the copy's frame times, the original and the fallbacks on generated files, never the question, the names or playback on screen).

## Timeline, canvas and keys

**TL-1 — Timeline basics**
- **Do:** 1. Drag the playhead; click clips; zoom in and out; View ▸ Zoom to Fit; play past the right edge.
- **Expect:** the playhead's time matches the timecode display; the view auto-scrolls during play; Fit shows the whole project.
- **Source:** spec §10 step 6.

**TL-2 — Drags, trims and their transients feel right**
- **Do:** 1. Drag a clip near another's edge. 2. Trim both edges. 3. ⌥-drag a body (duplicate) and ⌥-drag an edge (rate stretch). 4. Drop a clip where it is refused. 5. Drag a clip's fade handles. 6. ⌘Z after each.
- **Expect:** the snap guide shows; the trim cursor appears at an edge; a refused drop springs back; each gesture is one undo step and undo restores the frame.
- **Source:** #48; spec §10 step 7.

**TL-3 — Markers and the in/out range**
- **Do:** 1. Add markers (Mark ▸ Add Marker); drag a flag; double-click it and rename. 2. Set In and Set Out.
- **Expect:** the flag moves and takes the name; the range outside in/out is shaded on the ruler.
- **Source:** #48; spec §10 step 9.

**TL-4 — The canvas: handles, crop, snapping**
- **Do:** 1. Move, scale and rotate a clip on the canvas. 2. Press C for crop mode and drag a crop edge. 3. Drag a clip near the canvas centre and edges.
- **Expect:** the Video inspector updates live during the drag and one undo step lands; crop shows the cropped-away part as a 30 % ghost; snap guides appear.
- **Source:** #48; spec §10 step 8.

**TL-5 — Slip, roll and nudge**
- **Do:** 1. ⌥⇧-drag a clip's body. 2. ⌥⇧-drag the edge between two clips. 3. Select a clip, press `,` and `.`, then the same with ⇧; nudge it into a neighbour. 4. ⌘Z after each.
- **Expect:** slip scrolls the filmstrip in place; roll moves the neighbour's edge with it and shows a snap line; nudge moves ±1 frame (±10 with ⇧); a refused nudge beeps.
- **Source:** #48.

**TL-6 — Lift a range, close a gap, select a track, drop from Media**
- **Do:** 1. Set a range with nothing selected; press ⌫. Repeat while typing in an inspector field. 2. Double-click an empty span of a lane. 3. ⌥-click a track header. 4. From the Media tab, ⌥-drop a clip onto the timeline, then ⇧⌥-drop one.
- **Expect:** ⌫ lifts the range, but not while a field is being edited; the gap closes; the track's clips are selected; ⌥-drop inserts and ⇧⌥-drop overwrites. Each undoes with ⌘Z.
- **Source:** #48.

**TL-7 — Renaming a clip**
- **Do:** 1. Double-click a (non-nest) clip, type, Enter. 2. Double-click again and press Enter unchanged. 3. Edit the Clip tab's header name; leave with Tab, then with a click away; empty it. 4. Select a far-off clip and press ⇧⌘R. 5. Zoom or resize the window with a rename open; delete the clip with a rename open. 6. Double-click a clip, type, press Esc; double-click again, type, then click a track's M; ⌘Z twice.
- **Expect:** "Rename Clip" updates the strip, the Clip tab header and the selection block; the unchanged Enter makes no undo step; an emptied header restores the fallback name (nothing on an unnamed clip); ⇧⌘R scrolls the clip into view first; the field follows zoom and closes with no rename on delete. The header's text sits centred in its box. Esc keeps the old name with no undo step; the first ⌘Z unmutes and keeps the new name, the second undoes the rename.
- **Source:** #48, #69.

**TL-8 — Labels, solo and Paste Attributes**
- **Do:** 1. Clip ▸ Label ▸ Blue, then None. 2. Click a track's headphones toggle at S, M and L height; watch Track ▸ Solo. 3. Copy a clip, select another, Edit ▸ Paste Attributes (⌥⌘V); try it between a video and an audio-only clip. 4. Copy a graphic clip; select another clip drawn by the same graphic and a video clip; Edit ▸ Paste Graphic Properties; then ⌥⌘V.
- **Expect:** a blue dot on the strip and header, cleared by None; the headphones match eye, speaker and lock at every height and Solo's checkmark follows; paste restyles, and beeps when the clips share no group; the second graphic shows the first's text and colours at its own size and length, the video clip is unchanged; ⌥⌘V then copies position and opacity and not the text.
- **Source:** #48, #103.

**TL-9 — Region mode**
- **Do:** 1. Select a video clip, press Z, drag a band on the canvas; hold ⇧ during a second drag. 2. End the mode with Z, Esc, a selection change, and the chroma eyedropper in turn. 3. Press ⇧Z. 4. Use Place on Canvas until four regions exist. 5. Obscure a face with a region; view at 100 %.
- **Expect:** a crosshair; the band shows its rectangle ghosted; ⇧ switches to fill; each release adds one action; every listed way ends the mode; ⇧Z still fits the timeline; Place on Canvas greys out at four; the face is really hidden.
- **Source:** #48.

**TL-10 — Marquee, context menu and Space**
- **Do:** 1. Drag a marquee starting below the last lane with a real mouse. 2. ⌃-click a track header and a lane. 3. Commit an inspector number with Return, then press Space. 4. Turn on Full Keyboard Access, Tab to a button, press Space.
- **Expect:** the band draws and the selection block counts up; ⌃-click pops the menu at the pointer (no drag starts) and its checkmarks read; Space plays with no beep; with Full Keyboard Access, Space presses the button instead.
- **Source:** #48 (#35).

**TL-11 — Editing text on the canvas**
- **Do:** 1. Double-click a centred auto-sized text on the canvas and type a long line. 2. Do the same on a fixed-width text. 3. Return, then ⌘Z; ⇧Return for a new line. 4. Change the text and press Esc; answer the sheet with Esc, then Return. 5. Type with a Japanese or Chinese input method. 6. Give a fixed-width text tracking 20, line spacing 1.6 and UPPERCASE case; zoom the canvas to 50 %; double-click it and type.
- **Expect:** the auto-sized field widens about its centre with no wrap, and commit moves only the grey plate; the fixed-width one keeps its width and grows down; Esc on a change asks Cancel / Revert / Apply. Input-method text types correctly (it may not refit; note what it does). In step 6 the editor's letters and lines sit over the rendered ones, UPPERCASE shows as typed (spec §11 K-3), and input-method text still types.
- **Source:** #48 (#36, #37, #117).

**TL-12 — Dragging leaves the timeline still**
- **Do:** 1. Drag a clip with the playhead on screen. 2. Scroll the playhead off screen and drag a clip. 3. Press ← / →, and click the ruler.
- **Expect:** the playhead does not flash to 0 and the view does not jump back; the arrows and a ruler click still bring the playhead into view.
- **Source:** #48.

**TL-13 — Bare keys after a field, and with Caps Lock**
- **Do:** 1. Change an inspector number, press Return, then press I, O, ←, →, ↑, ↓, Home, End without clicking. 2. Click into another number field, press Esc, then L and K. 3. Turn Caps Lock on and repeat 1 and J / K / L.
- **Expect:** every key acts with no beep and no click first.
- **Source:** #60, #61.

**TL-14 — Obscure regions on the canvas**
- **Do:** 1. On a rotated, scaled clip with two obscure regions, select the clip and drag a region's centre, a corner and an edge. 2. ⌥-drag an edge. 3. Press Esc mid-drag of a region, then mid-drag of the clip itself. 4. ⌘Z each drag. 5. Repeat 1 with an action selected. 6. Press Place on Canvas.
- **Expect:** the dashed outlines sit on the hidden areas and turn with the clip; the cursors change over the grips; a drag has no jump or lag; each Esc puts the drag back with no step (Edit ▸ Undo names the step before it); each drag is one "Move Region" or "Resize Region" step; with an action selected the region animates to where it was dragged; the outlines stay drawn under the band.
- **Source:** #85.

**TL-15 — Pane sizes remembered from a drag only**
- **Do:** 1. Drag the divider above the timeline to make the timeline clearly taller, and the divider beside the inspector to make it wider. 2. Open a new window (File ▸ New). 3. In that window, make the window itself much smaller and then larger again, and press ⌥⌘I twice. 4. Open a third window.
- **Expect:** the second window opens with the timeline height and inspector width from step 1; the third opens with those same sizes, not the ones the window resize in step 3 left behind.
- **Source:** #327.

## Clip tab and action lane

Run each in both appearances. An action is a keyframed segment (Clip ▸ Add Action, ⌥⌘K).

**CT-1 — The action lane and its bands**
- **Do:** 1. Add two actions to a clip. 2. Look at the lane's header row, the Clip chip and the detail row. 3. Look at the timeline bands at S, M and L. 4. Click a band; press Esc; press Esc again with nothing selected; select a band and press ⌫.
- **Expect:** the header reads ACTIONS, its count, "· editing N", Zoom to Region, Zoom Back, Add Action; the detail row has Start, Length, Curve and a trash button. Bands are pale mint with stronger ends; the selected band is solid with a dark number and its curve, its span washed and shaded on the ruler. A click selects and parks the playhead at the band's end; Esc leaves the mode and passes through when nothing is selected; ⌫ removes the action, not the clip.
- **Answer:** does the light-mode mint read? (It is a placeholder colour.)
- **Source:** #49 phase 1.

**CT-2 — Sub-tabs and the pinned block**
- **Do:** 1. Scroll the Clip tab's sections. 2. Click each sub-tab. 3. Pick an action, then another clip. 4. Drag a slider through its range.
- **Expect:** the pinned block stays while sections scroll; a sub-tab switches at once and returns to the top; the choice survives picking an action and resets on another clip; the active cell and the mint `◆N` read in light; the slider's block knob meets its fill cleanly at every value.
- **Source:** #49 phase 2.

**CT-3 — Row marks**
- **Do:** 1. With an action selected, change several rows; scrub across the action. 2. Close a section by hand, select another action, then leave.
- **Expect:** ◆ ◇ ○ ⊘ in gutters and headers are visible (⊘ and ◇ may be faint in light); keyed rows have a 1 pt border; a mint segment and coral tick while scrubbing; "now" on a field-only row; "at end" on a keyed popup. Keyed sections open on their own, a hand-closed one stays closed, and leaving restores your layout.
- **Source:** #49 phase 3a.

**CT-4 — Reset, Clear, menus and the refusal strip**
- **Do:** 1. Change a section from default and back. 2. Select an action and look at the same header. 3. Hover a keyed gutter (window in front). 4. Right-click a label, a slider, empty space, a field and a popup. 5. Choose "Go to action N". 6. Inside an action press ⌥⌘K; then move the playhead; then edit, undo or click.
- **Expect:** Reset appears off-default and goes on return; Clear takes its place with an action selected; the × and its tooltip show on the gutter; label/slider/empty space open the row menu, fields and popups their own; "Go to action N" lands on it. ⌥⌘K beeps and shows "Refused: …" (at most three lines), kept across the playhead move, gone on the next edit, undo or click.
- **Source:** #49 phase 3b.

**CT-5 — Retiming an action by drag**
- **Do:** 1. Hover a band; drag its body and each end, on the timeline and in the lane. 2. Try a very narrow band. 3. ⌘Z. 4. Narrow the inspector to its minimum.
- **Expect:** hover brightens the band and shows grips; open-hand and resize cursors (none on a too-narrow band); the band stops flush at limits; a dashed ghost and a time HUD (above the clip, or in place of ACTIONS in the lane); the drop re-selects and parks the playhead; one ⌘Z undoes it; a lane click selects on release without a jump; lane hatch, fades and wedges match the timeline's; the curve glyph still fits.
- **Source:** #49 phase 4.

**CT-6 — Editing inside an action**
- **Do:** 1. With an action selected, move / scale / rotate / crop on the canvas and nudge with the arrows. 2. Drag a text's width, and a shape's box. 3. Uncheck Drop shadow (and outline, backdrop, stroke). 4. Click section headers with System Settings ▸ Accessibility ▸ Display ▸ Reduce motion on, then off.
- **Expect:** the change lands on the action's END state while the box is drawn at the playhead (accepted by design; judge whether it is tolerable); a text width drag starts from the end width; a shape box still resizes; unchecking shows ◆ "at end". Collapse is instant with Reduce motion, animated (about a quarter second) without; auto-open is always instant.
- **Source:** #49 phase 5; spec §11 CI-13.

**CT-7 — Section header hover**
- **Do:** 1. Window in front, move slowly onto and off several Clip-tab section headers. 2. Repeat with System Settings ▸ Accessibility ▸ Display ▸ Reduce motion on, then off.
- **Expect:** a header darkens one step with a quick fade, instantly with Reduce motion; its title, marks, summary and Reset/Clear stay legible; rows never darken.
- **Source:** #102 (spec §11 CI-15, amended); the "clip" tag is clip_inspector7_proof.py T1, T2, T4 since #209.

**CT-8 — A graphic's props under a selected action**
- **Do:** 1. Insert ▸ Graphic ▸ Lower Third, select it, open Clip ▸ Graphic, add an action (⌥⌘K) and keep it selected. 2. Change Size, Align, the "boxed" checkbox, Title and the accent colour; set the timeline to L. 3. Scrub across the action; hover a keyed gutter; look at the Graphic sub-tab. 4. Rewrite the module without one of the props the action keys, then put it back. Use Properties' Clear. 5. With a module that has an image (`asset`) prop, pick an image in its row; look at Size's Width and Height and Timeline's Follow Clip. 6. On a text clip, select an action and change the Content and Font ▸ Family. 7. Give a module of your own a boolean whose `label` is a long sentence ("Show the long descriptive label for this toggle"), put it on the timeline, select an action and click that checkbox; then deselect the action. Repeat in the other appearance.
- **Expect:** ◆ on each keyed row; the mint border on the Size field and the Align pop-up only; "at end" after "boxed", Align and Title; a mint segment and a coral playhead tick on Size's slider; × on a hovered keyed gutter, Clear empties the action's props, and the Graphic sub-tab's `◆N` counts them; a prop the module no longer declares gets its own faint row with ◆ and ⌫ ("… remove it from action N"); an image row shows ⊘ and still changes the clip; Width, Height and Follow Clip show ⊘ with their sections' "Actions don't animate this" note; the action's band reads its keys sorted, "accent, align, boxed, size, title", cut short with "…" where the band is narrow, at L on both the timeline and the lane; the text clip's Content and Family rows read "at end", and the Title field and the Family pop-up, narrower only while keyed, still read cleanly (their widths are measured by K6b and K18; judge only the look); the long checkbox label stops at the checkbox's edge (cut, no "…") with "at end" whole after it, and reads whole again with the action deselected (K18c measures it). All of it in both appearances.
- **Source:** #239 (issue batch B87 phases 3 and 4, spec §11 G-34 (l)); `graphics_inspector_proof.py` K1–K18c and screen 07b cover the arithmetic and the capture.

## Chrome and looks

**CH-1 — The zoom slider and square controls**
- **Do:** 1. Drag the timeline's zoom knob. 2. Look at the Export button, S/M/L, the Snap box and fields, then open a sheet (Export…).
- **Expect:** a grey track, a white (dark) or black (light) block knob beside the accent fill; the knob drags smoothly. The toolbar's square controls and the sheets' square buttons read as one family.
- **Source:** #50, #100 (spec §11 SH-2, SH-4).

**CH-2 — States and hovers no proof renders**
- **Do:** 1. Hover and press ghost (borderless) buttons. 2. Find a disabled slider. 3. Hover every control with a tooltip. 4. Switch Timeline Track Height S / M / L.
- **Expect:** a square hover fill and a press state; the disabled slider looks disabled; every tooltip reads as a sentence and is correct; S/M/L relayouts cleanly.
- **Source:** #50; #48.

**CH-3 — The Speed sheet's hint**
- **Do:** Select clips with a gap and an overlap between them; Clip ▸ Speed…; set a speed that one clip refuses. Then set ×0.5 on a clip with a neighbour just after it.
- **Expect:** the hint (gaps, a clip that gains a transition — named below — and a refused clip left unchanged) wraps readably; a line under the lengths names the neighbour and its transition's length, and the sheet grows to show every line unclipped.
- **Source:** #48, #109.

**CH-4 — The square buttons**
- **Do:** 1. Close every document so Welcome shows, then open Frame Job ▸ Settings…. 2. In a project: File ▸ Export…, Clip ▸ Speed…, Clip ▸ Remove Silences…, File ▸ Generate Captions…, File ▸ Consolidate Media…, File ▸ New Recording…, Window ▸ Export Queue. 3. In each, hover every button, press and hold one, and look at a disabled one (Settings' Remove with no key set).
- **Expect:** square buttons with no shadow. The blue one lightens slightly on hover, and the outlined one takes a faint grey fill. A press shrinks the button a little about its centre, and a disabled one is dimmed. No title is clipped and no row is cramped or off-centre, in both appearances.
- **Source:** #100 (spec §11 SH-4).

**CH-5 — Settings' info buttons**
- **Do:** 1. Frame Job ▸ Settings…; hover each ⓘ beside "Assistant" and "Transcription", then move off. 2. Flick the pointer across an ⓘ without stopping. 3. Click one, then click elsewhere. 4. Click one, then click the same ⓘ again. 5. Rest on one until it opens, then click it and move off. 6. With Keyboard navigation on (System Settings ▸ Keyboard), Tab to an ⓘ and press Space. 7. With VoiceOver on, move to each ⓘ. 8. Close Settings with a popover up. 9. Repeat in both appearances, with Reduce motion on and off.
- **Expect:** a popover opens after a short beat, not on a flick across, and closes on leaving the icon; a second click on the ⓘ closes it (no flicker back open); a click on a hover-opened one keeps it open after the pointer leaves; the text is large and high-contrast, in short paragraphs, and wraps without clipping; VoiceOver says "About Assistant" / "About Transcription" and reads the text; the popover goes with the window.
- **Source:** issue batch B71 (spec §11 SH-5).

**CH-6 — Settings' MCP section**
- **Do:** 1. On a 13" display, open Frame Job ▸ Settings… in the light appearance and read the MCP section's blurb. 2. Press Copy MCP Command. 3. Scroll down to the Playback section's Background render row, if Settings scrolls. 4. Repeat in the dark appearance.
- **Expect:** the window fits on screen, top and bottom (on a display shorter than its four panes, such as 1440 × 900, the panes scroll and the Background render row is reached by scrolling); the blurb is large and high-contrast; the button is below the blurb; nothing is selected or highlighted when Settings opens (the Assistant key field has focus); the status line appears after a press.
- **Answer:** did the window fit, read clearly, open with nothing selected, and show the status line after the press, in both appearances?
- **Source:** issue batch B74 (#222; `settings_layout_probe.py` L9, L10; spec §11 MC-7); the scrolling, #127 G6 phase 4's fix pass 1 (`settings_layout_probe.py` L13; spec §11 G-38 (a)).

## Sound and export

**SE-1 — M3's inspector sections and sheets**
- **Do:** 1. ⌘G and ⇧⌘G (Nest / Un-nest). 2. Turn on the Clip tab's Reverse for a long clip; Cancel the progress sheet; reverse again to the end. 3. Try the Filters, Spotlight, Reflection, Noise Reduction and Compressor sections. 4. Open Export… and look at the Quality row.
- **Expect:** each works and reads cleanly; Cancel stops the reverse and leaves the clip as it was.
- **Source:** #51.

**SE-2 — The level meter, mono and pan**
- **Do:** 1. Play speech and music; watch the meter. 2. In the Audio inspector's Mix section, turn on Mix to Mono for a stereo clip. 3. Sweep its Pan from left to right while playing.
- **Expect:** the meter holds peaks and decays smoothly, with no stutter; mono sounds mono; the pan sweeps across the speakers.
- **Source:** #51.

**SE-3 — Loudness and mixed formats**
- **Do:** 1. Export at −14 LUFS; play it beside commercial streaming material at the same volume. 2. Put an AAC clip and a WAV clip (different sample rates) on one track; play across the join on the built-in speakers. 3. Watch the meter across the join, and past the end of a short clip playing under a longer one.
- **Expect:** the export sits level with the commercial material; the mixed-format track plays clean, at the right pitch, with no gap. (The scripted half is HS-3.) The meter follows what plays: none of the AAC's level stays lit once the WAV plays, and a finished track adds nothing.
- **Source:** #51 (#34, #65).

**SE-4 — Blends, gradients and the blurred background**
- **Do:** 1. Try each blend mode on real footage. 2. Add a gradient shape across the canvas. 3. Clip ▸ Add Blurred Background on a portrait clip in a landscape canvas, at the Fill default.
- **Expect:** blends look as their names say; the gradient is smooth, not banded.
- **Answer:** is the blurred background's default look (blur 1.0) right?
- **Source:** #51.

**SE-5 — Export remembers, queues, and plays**
- **Do:** 1. Export with a non-default format, size, quality and loudness; quit and relaunch; open Export… again. 2. Save a user preset, change settings, pick the preset. 3. Start two exports; Window ▸ Export Queue. 4. Save Frame… (⌥⌘E) at a paused frame. 5. Open an exported movie in QuickTime Player. 6. Ask the Assistant to export the project, allow it, and open Window ▸ Export Queue; press its row's Cancel.
- **Expect:** the sheet reopens on the last choices and the preset restores them; the queue is listed once, with per-row progress and Cancel; the saved frame matches the preview; the movie plays in QuickTime with sound; the Assistant's export is a row in the queue with its progress, and Cancel stops it.
- **Source:** #51; spec §10 step 10; #326.

**SE-6 — A ×120 preview is watchable**
- **Do:** 1. Put an hour-long recording on the timeline. 2. In the Clip tab's Speed section, type 120 into Rate, or Fit to 30 s. 3. Play it from the start to the end.
- **Expect:** the picture moves through the hour with only short stalls. B52a measured 841 of 869 frames shown, with one 3.4 s stall, on the development machine.
- **Answer:** is a ×120 preview good enough to scan a recording by?
- **Source:** #190.

**SE-7 — The ×1000 preview and export**
- **Do:** 1. Set the same hour-long recording to ×1000 (Clip ▸ Speed… ▸ 1000, or Fit to 3.6 s). 2. Play it. 3. Export it as H.264 and play the movie in QuickTime Player.
- **Expect:** the preview does NOT keep up (B52a measured 14 of 936 frames and a 30 s stall) and the export takes a long time (about 25 minutes for 32 s in B52a's run), but the export finishes and plays.
- **Answer:** are the ×1000 preview and export acceptable as they are (the owner's later test, spec §11 #190)?
- **Source:** #190.

**SE-8 — Audio at and above the ceiling, and Fit to**
- **Do:** 1. On a clip of speech, set ×12 with Keep pitch on and play it; then turn Keep pitch off and play it again. 2. Set ×13 (the question "“N” will be silent at ×13." appears; answer Set Speed), with Keep pitch on and then off; play each and read the Speed section. 3. Type a length into Fit to and press Return.
- **Expect:** at ×12 the audio plays in both pitch modes and sounds like sped-up speech; setting ×13 first shows the question, and Set Speed applies it; at ×13 the clip is silent in both modes and the Speed section says "Audio is silent above ×12"; Fit to commits, the clip takes the typed length, and Rate shows the new rate.
- **Answer:** does the speech at the ceiling sound right?
- **Source:** #190, #212.

**SE-9 — HEVC with alpha and ProRes 4444 play transparent**
- **Do:** 1. Set the Document tab's Background opacity to 0 on a project with a title; read the note under it at the inspector's narrowest width. 2. Export… ▸ HEVC with Alpha (MOV); read the footnote on its own line above the sheet's buttons, then rest the pointer on it. 3. Export it, and export the same project as ProRes 4444 (MOV). Play the HEVC file in a Safari page with a coloured background; open each file in QuickTime Player, and lay each over a clip in Final Cut.
- **Expect:** the note reads "Transparent — kept by 3 export formats." uncut; the footnote reads "HEVC_ALPHA · MOV · alpha" whole, on a line of its own above the buttons, and resting the pointer on it shows the same line; for both files, the title's edges are clean in every player, with no dark fringe and no line at the frame's edge.
- **Source:** #103, #242, spec §11 G-33, G-35.

**SE-10 — Synchronize Audio on real camera and recorder footage**
- **Do:** 1. Record one take on a camera (its own microphone) and a separate recorder at once, starting them a few seconds apart; clap once near the start. 2. Import both, put the camera clip on one track and the recorder on another anywhere, select both and choose Clip ▸ Synchronize Audio. 3. Mute the camera clip's audio and play the start, the middle and the end of the take; then unmute it and listen to the two together. 4. Try it on a take longer than 10 minutes, and on two clips that are not the same take. 5. On the long take, select the recorder and read its speed in the inspector; export the timeline and watch the end of the exported file too. 6. Trim a long recorder clip so its speech sits near the camera's (as on a real project, within a second or two), then Synchronize Audio. 7. Put both clips at 0:00 where the recorder's matching sound comes later in its file than the camera's, and Synchronize Audio. 8. Select two clips that are not the same take — two takes of the same words, if you have them, each trimmed to the same sentence — and Synchronize Audio.
- **Expect:** a press straight after import may beep, nothing moved, with the inspector's foot saying the clip "is still being analysed for Synchronize Audio" — try again once the analysis lands (about 3 s for a phone clip and a recorder file like the owner's); then the recorder moves and the camera stays; the clap and the speech line up with the picture by eye and ear at the start; the two together sound like one recording, not an echo (a frame is 33 ms at 30 fps, so a slight doubling can remain); one ⌘Z puts the recorder back. Two unrelated clips beep and the inspector's foot says "no matching sound found …", nothing moved. On a long take the END lines up as well as the start (the drift is corrected): the recorder's speed reads a hair from ×1 (×0.9998 or ×1.0002, say), "Keep pitch" is off, and the corrected sound has no audible artefact — no warble, no pitch change you can hear, no clicks. In the exported file the recorder still sits under the picture at the start, middle and end (since #298's phase 2 the proof finds an exported near-×1 clip within 1 ms of the same clip at ×1; the preview is SE-13's). The trimmed recorder lines up with the speech you trimmed it to, even when the files share other sound elsewhere. With both at 0:00, the recorder stays at 0:00 and plays in sync, having lost just the head that would have fallen before 0:00 (its in point moves later); one ⌘Z puts both back. With both at 0:00 a match found only near where the clip sits is a WEAK one, so the Weak match sheet (SE-11) comes first. Two clips from different takes — even two takes of the same words — beep, nothing moved, and no Weak match sheet comes up: the inspector's foot either names the candidates ("… moving clip N by +0.77 s (confidence 4.31) or …") and the rule, or says the sound matches but "their waveforms do not line up there (GCC-PHAT confidence …), so they are not one recording." (since round 3, spec §11 SY-29).
- **Answer:** does the result line up by eye and ear at the start, middle and end of a long take, in playback and in the export, does the corrected recorder sound clean, does a trimmed or head-trimmed recorder line up, and does the refusal's list read sensibly?
- **Source:** road maps "audio-sync" and "audio-sync-2" and round 3 (`designs/adr/audio-sync.md`), spec §11 SY-1..SY-22, SY-28..SY-30.

**SE-11 — The Weak match sheet**
- **Do:** 1. Take a camera clip and a recorder from ONE recording, each trimmed to the same few seconds of speech, and place the recorder about a second from where it lines up (as the proof's S29 does with the owner's second pair: `IMG_0019.MOV` from 2 s for 3 s at 6.27 s, `record.aifc` from 150 s for 3 s at 5 s); select both and choose Clip ▸ Synchronize Audio. 2. Read the sheet, then press Cancel. 3. Choose Synchronize Audio again and press Apply. 4. Press ⌘Z.
- **Expect:** the sheet names the recorder and the move in plain words ("Weak match: move “record.aifc” 1.00 s later?", naming a trim too when the move would start it before 0:00) and says the match's confidence fell short of what applies on its own; Cancel changes nothing and leaves no undo step; Apply lines the recorder up as SE-10 says; one ⌘Z puts it back.
- **Answer:** does the sheet read clearly, and would you know from it what Apply will do?
- **Source:** road map "audio-sync-2" and round 3 (`designs/adr/audio-sync.md`), spec §11 SY-19, SY-30.

**SE-12 — The Synchronizing Audio sheet**
- **Do:** 1. Put two long clips (a camera take and its recorder, ten minutes or more) on two tracks, select both and choose Clip ▸ Synchronize Audio. 2. While the sheet is up, try to scroll the timeline and open a menu. 3. Choose Synchronize Audio again and press Cancel while the sheet is up. 4. Choose it once more and let it finish.
- **Expect:** a "Synchronizing Audio" sheet with a moving bar and Cancel comes up at once, and the window does not beach-ball while it matches; the Clip menu's Synchronize Audio is greyed while it is up; Cancel takes the sheet down and nothing moves, with no undo step; left alone the sheet goes by itself and the result is SE-10's, and a weak one brings SE-11's sheet once this one has gone.
- **Answer:** does the app stay responsive while it matches, and is it clear that it is working and how to stop it?
- **Source:** road map "audio-sync-2" (`designs/adr/audio-sync.md`), spec §11 SY-22.

**SE-13 — Sound in sync in the preview at both output rates**
- **Do:** 1. In Audio MIDI Setup set the output device to 48 kHz. 2. On one timeline, put a 44.1 kHz clip and a 16 kHz clip (a phone voice memo or a recorder file), each with a clap placed at 5:00, and a clip with a clap or a flash at its start set to ×0.5 with Keep pitch off, and a clip with Noise reduction turned up — each against a flash or a visible clap on the picture track. 3. Play each in the preview. 4. Set the output device to 44.1 kHz in Audio MIDI Setup and play each again.
- **Expect:** in both passes each clap lands on its flash by eye and ear in the preview: the 44.1 kHz and 16 kHz claps at 5:00, the ×0.5 varispeed clip and the noise-reduced clip all in sync, with no echo or lag you can see or hear.
- **Record:** the output device's rate for each pass, and any clip that was out of sync in either.
- **Answer:** is every clip in sync in the preview at 48 kHz and at 44.1 kHz?
- **Source:** #298 phase 2, spec §11 SY-23..SY-27 (the export is pinned by `export_offset_proof.py`; the preview's output latency and a 44.1 kHz device are not measured).

**SE-14 — Keep pitch sounds clean**
- **Do:** on a clip of speech set ×0.9995, ×0.9 and ×1.5 with Keep pitch on, play each and export each.
- **Expect:** ×0.9995 sounds the same as ×1; ×0.9 and ×1.5 keep the voice's pitch with no warble, phasing or echo.
- **Answer:** does Keep pitch sound clean?
- **Source:** #299, spec §11 SY-39, SY-40.

## Captions

**CAP-1 — Text reveals and legibility**
- **Do:** 1. On a text clip, set Animation to Typewriter, Word Fade and Line Rise in turn; play. 2. Add a Caption-preset caption over real footage.
- **Expect:** each reveal plays at 60 fps with no stutter; the caption is legible over busy footage.
- **Source:** #52.

**CAP-2 — The on-device model download**
- **Do:** 1. Turn off Wi-Fi; File ▸ Generate Captions… with a language never downloaded (e.g. French (France)). 2. Turn Wi-Fi on; Download. 3. Mid-download, try Language and Engine; close and reopen the sheet. 4. Start another language and press Cancel mid-way.
- **Expect:** offline, the row says why it cannot download. Online: an indeterminate bar, then "Downloading French (France)… 42%" with the percentage moving; Language and Engine stay locked throughout; the row then reads installed and Generate is live. A reopened sheet offers a second request. Cancel stops at once, nothing is half-installed, and "Download" returns with no note.
- **Source:** #52.

**CAP-3 — The model stays installed**
- **Do:** Check the downloaded language in the sheet straight after, after a relaunch, and again some days later.
- **Expect:** installed each time; no re-download.
- **Source:** #52.

**CAP-4 — The bundled caption fonts**
- **Do:** On a Mac without Montserrat, Anton or Bebas Neue in Font Book, generate captions in each style.
- **Expect:** the styles show those faces, not a fallback.
- **Source:** #52.

**CAP-5 — Word captions: sync and styles**
- **Do:** 1. Generate captions on real speech with On Device, then with AssemblyAI. 2. Try Highlight, Pill, Karaoke, Build and One Word at 9:16 and 16:9, hand-written and generated.
- **Expect:** each word lights as it is spoken, with both engines; every style plays at 60 fps with a pop on every word.
- **Answer:** if an engine runs early or late, by roughly how much? (A correction is a one-line constant.)
- **Source:** #52.

**CAP-6 — The Generate Captions sheet**
- **Do:** 1. Open it; pick a style; relaunch; reopen. 2. With two caption tracks, generate with Replace; ⌘Z once. 3. Look at the style preview at 9:16 and 16:9. 4. Choose Pill and tick "Slide the pill"; relaunch; reopen. 5. Still with Slide ticked, choose Karaoke, then Subtitles, then Pill again. 6. With Engine on "On this Mac", choose Subtitles, then Highlight; then switch Engine to AssemblyAI. 7. On Karaoke tick "Fill words as spoken"; on Pill tick "Slide the pill"; tick "Dim in pauses". 8. On a 13-inch display, select AssemblyAI and a word style.
- **Expect:** the Style row and card fit; the popup opens on the last style; Replace swaps both tracks and one ⌘Z brings them back; the preview reads as "this style, second word lit". The three boxes sit one per line under Style, and a ticked box is still ticked after the relaunch. A box that does not apply to the style is greyed and keeps its tick: Slide is greyed on Karaoke and Subtitles and is on again, still ticked, back on Pill. Under "Dim in pauses" the note "On-device words rarely carry a pause; this shows mostly with AssemblyAI." shows on two lines with On this Mac and a word style, and goes with Subtitles or AssemblyAI; the card grows by about two lines when it appears and nothing is cut off. With Fill the preview's lit word is half filled; with Slide the pill in the second frame sits half-way between the first word and the second; ticking Dim changes nothing in the preview. With AssemblyAI selected the whole card, buttons included, fits on the 13-inch display.
- **Source:** #52, spec §11 W-15.

**CAP-7 — Word caption looks**
- **Do:** 1. On real speech, generate Pill with "Slide the pill" ticked, with On this Mac and then with AssemblyAI; play. 2. Generate Karaoke, then Highlight and Build, with "Fill words as spoken" ticked, with each engine; play. 3. Generate Karaoke — which pages to two lines — with "Dim in pauses" ticked, with each engine, over speech that has real pauses; play. 4. Select one of the Pill pages from step 1 and, in the Clip tab's Text ▸ Box section, narrow its width until the page wraps onto two lines; play across the line break. 5. Play a page with a fill running and read the compositor's timing log (Setup 4).
- **Expect:** the pill slides from word to word instead of jumping, and never covers a word's letters; between two lines it travels diagonally, under the ink, and arrives the right size for the new line. A word fills left to right in time with the voice and is full when the word ends, with both engines. In a pause the page fades to half and comes back as the next word starts; with On this Mac it rarely dims at all (the sheet says so). Playback holds 60 fps with a fill running.
- **Answer:** is 0.6 s the right longest time for one word to fill, and is 50 % the right depth for the dim? Does the glide look right, and does the dim read as a pause rather than a glitch?
- **Source:** spec §11 W-12..W-15 (issue batch B86).

## Cloud captions

Needs your own AssemblyAI key (Setup 3).

**CC-1 — Settings and Verify**
- **Do:** 1. Frame Job ▸ Settings… (⌘, from a document window). 2. Paste a good key, Verify; then a bad one, Verify. 3. Save; Remove. 4. If your account has the EU region, choose `eu` and generate captions.
- **Expect:** "Key accepted" for the good key, a clear sentence for the bad one; the button row is balanced and each ⓘ's text reads; ⌘, never types a `,` nudge or into a rename; the key lands in a file in `~/Library/Application Support/Frame Job/`, and Remove feels final (the file goes). The EU region works.
- **Source:** #53.

**CC-2 — The sheet and a real recording**
- **Do:** 1. File ▸ Generate Captions…; switch Engine between On Device and AssemblyAI; hover the summary label. 2. Generate on a twenty-minute recording over a home connection.
- **Expect:** the three cloud rows appear and go with Engine; the tooltip gives the reasons. During the upload and wait, "Waiting for AssemblyAI · N s", the four progress bands and the megabytes read as progress, not a hang; cues line up by eye.
- **Source:** #53.

**CC-3 — Hard cases**
- **Do:** 1. Generate on a Korean or Polish recording. 2. Generate on a media over ten hours. 3. With an account out of credit, generate.
- **Expect:** the other-language run completes and its report card says which model answered; the ten-hour run completes; the out-of-credit run shows the balance sentence.
- **Source:** #53.

**CC-4 — Speaker colours**
- **Do:** 1. Generate Captions with AssemblyAI, Speakers on, Subtitles, over a two-person recording. 2. Generate again with Pill.
- **Expect:** each voice reads in its own colour (white, then yellow), legible over the band; Pill ignores it; the Speakers row reads whole.
- **Source:** #93.

## Silence, transitions and motion

**SIL-1 — Remove Silences by voice, listened to**
- **Do:** 1. Record a narrated screencast in Frame Job; note by ear where the real pauses are. 2. Clip ▸ Remove Silences…, Voice mode, default padding (0.1 s). 3. Play every cut.
- **Expect:** no clipped word at any cut.
- **Answer:** is the padding breathing room or a clipped word? Should it be 0.05 s?
- **Source:** #54.

**SIL-2 — The Remove Silences sheet**
- **Do:** 1. Open it with one file still being analysed and another judged by level. 2. Look at the shading on the ruler and lanes. 3. Select only silent clips.
- **Expect:** the two notes read sensibly together; shading marks the spans to remove; the "Selected clips" row is disabled with a silent selection.
- **Source:** #54.

**TRN-1 — Transitions**
- **Do:** 1. Add a crossfade across a Remove Silences cut. 2. Compare an eased push with a linear one. 3. At a hard cut, use Clip ▸ Transition. 4. Apply each of the three wipes.
- **Expect:** the crossfade sounds even; the eased push feels better; the submenu does what you expect; each wipe moves in its named direction.
- **Source:** #54.

**MOT-1 — Motion presets**
- **Do:** 1. Apply each Clip ▸ Motion preset (In, Out, During) at ordinary clip lengths; use Clip ▸ Motion ▸ Preview. 2. Drag a clip on the canvas mid-motion. 3. Look at the timeline wedges at S, M and L. 4. Apply `spin`, and a slide inside a nest.
- **Expect:** the numbers feel right; `pop` reads as a pop; Preview loops the clip; a mid-motion drag is tolerable; wedges read at every height; `spin` turns the way the preset table says; the slide leaves by the nest's edge.
- **Source:** #54.

## Graphics

Uses the four `tools/proof/work/playback-check/` projects (Setup 3).

**GR-1 — Graphics play, watched**
- **Do:** 1. Open `Playback-1080p` at Preview Quality Full; play. 2. In each of `Playback-1080p`, `Playback-4K` and `Error-card`: play, scrub, and loop an in/out range.
- **Expect:** `lower-third` and `kinetic-type` play smoothly; with no video beneath, the preview shows, Play runs, and scrub and loop look right.
- **Source:** #56.

**GR-2 — Memory at 4K, and a slower machine**
- **Do:** 1. Play `Playback-4K` with Activity Monitor open on Frame Job's memory. 2. If one is available, play it on a slower Mac, or a heavier graphic.
- **Expect / Answer:** memory stays steady (note the figure); no stutter. A stutter goes on #127 with the project and the machine: playback rasterizes graphics ahead (spec §11 G-36), so a stutter is graphics performance work again.
- **Source:** #56.

**GR-3 — The error card**
- **Do:** Open `Error-card` and play past 2 s.
- **Expect:** a dark red card with the message in white in the live preview, never the last good frame.
- **Source:** #56.

**GR-4 — The Title and marker name fields**
- **Do:** 1. Insert ▸ Graphic ▸ Lower Third, select it, open Clip ▸ Graphic. 2. Press M, then open the Document tab. 3. In the Document tab, click into a marker's name field, select all, delete, then type a letter.
- **Expect:** the Title field is the height of the number fields, and the marker's name field is the height of the Rate row's controls, in both appearances. Both are filled and bordered like the number fields, with their text centred vertically, in both appearances; clicking into either moves no text. With the name deleted, a grey "Marker" sits where the text sat and did not move on the click; the first letter typed replaces it at once.
- **Source:** #106, #171, #199.

**GR-5 — The renamed-image notice after the real panel**
- **Do:** 1. Copy a PNG to the Desktop as `#logo&mark.png`. 2. In a project, File ▸ Add Image to Graphics…, choose it, Open. 3. Click OK. Repeat in the other appearance.
- **Expect:** once the open panel has closed, a sheet on the editor window reads `"#logo&mark.png" was added as "logo-mark.png": asset(name) cannot use the name it had.` (the second run says `logo-mark-2.png`); OK dismisses it, in both appearances.
- **Source:** #105.

**GR-6 — A graphic's warnings on the export sheet, the queue and the Source section**
- **Do:** 1. In a project, write `graphics/nofont.js` drawing text in `font-family="'Nope Sans'"` and `graphics/late.js` the same in `'Late Sans'`; place a 3 s `nofont` clip, then a 1 s `late` clip after it. 2. File ▸ Export…, export it; hover the sheet's finish line. 3. Export it again with Add to Queue, open Window ▸ Export Queue at its default width and hover the finished row. 4. Add an audio clip under the graphics and Add to Queue once more; look at that row. 5. Put a file named `Bad.js` into the package's `graphics/` folder, select a graphic clip, open Clip ▸ Graphic ▸ Source (reselect the clip if the row is not there yet), and click Reveal. Repeat 2–5 in the other appearance.
- **Expect:** the sheet's line reads `Exported “…”. 2 graphic warnings (hover for details).` and its tooltip lists `"nofont" at frame …` and `"late" at frame …`, each naming its font. Each queue row shows `Exported “…”. 2 graphic warnings.` visibly, straight after the Exported sentence and ahead of the loudness figures on the audio row, and its tooltip lists the two warnings under the path. The Source section shows "In the graphics folder" and a row reading `graphics/Bad.js is not a module name…`; Reveal shows the `graphics` folder selected in Finder. All of it in both appearances.
- **Source:** #105.

**GR-7 — The Rename, Delete and Restore Graphic sheets**
- **Do:** 1. In a project with one graphic a clip uses, one no clip uses and one deleted (delete a third with File ▸ Delete Graphic…), open File ▸ Rename Graphic…, File ▸ Delete Graphic… and File ▸ Restore Graphic Version… in turn. 2. In Delete Graphic…, choose the graphic the clip uses and press Delete. 3. In Rename Graphic…, type a name on the keyboard. Repeat 1–3 in the other appearance.
- **Expect:** in each sheet the wording reads whole and nothing looks cramped, loose or misaligned, in both appearances (Delete Graphic… has one row and the most empty space between its pop-up and its buttons); the refused Delete's sentence shows inside the sheet, which stays open and grows to hold it; the name typed lands in New name.
- **Source:** #103.

**GR-8 — An animated prop at 4K**
- **Setup:** Low Power Mode off — `pmset -g | grep powermode` reads 0 before and after the run (if it does not, skip this check and note it). View ▸ Preview Quality ▸ Full.
- **Do:** Play `Playback-4K-animated` through both actions (title-card's colours, then kinetic-type's stagger and accent).
- **Expect:** no stutter through the two action spans.
- **Answer:** stutter, yes or no. A stutter goes on #127: playback rasterizes graphics ahead (spec §11 G-36), so a stutter is graphics performance work again.
- **Source:** #239 (issue batch B87 phase 3, spec §11 G-34 (g)); the project is built by `graphics_playback_samples.py`.

**GR-9 — A heavy graphics project plays**
- **Setup:** Low Power Mode off — `pmset -g | grep powermode` reads 0 before and after the run (if it does not, skip this check and note it). View ▸ Preview Quality ▸ Full. Activity Monitor open on Frame Job's memory. Background render off in Settings ▸ Playback (spec §11 G-38), so no frame is drawn ahead while the window waits; tick it again after GR-10.
- **Do:** Open a COPY of a parive-like project — many graphic clips drawing images and text, such as `~/temp/testmotiongraphics/parive-promo.framejob` — and play one of its `section` scenes (in parive-promo, clip 8, from 41.87 s) for ten seconds or more.
- **Expect:** the play runs on and stays in sync. Until #127's later phases a `section` scene still stutters (the bench composes about 28 % of its frames at Full), so a stutter goes to #127, not a new issue. Frame Job's memory rises while it plays and stays raised after it: G-37 holds the rasters held ahead and the graphic frames the window keeps to one budget, a quarter of the Mac's physical memory (less under memory pressure), and the kept frames stay held after the play, up to that quarter, until the window closes. Outside the budget are the workers' rasters in flight and the freed memory the system keeps for the app. A rise well past a quarter of physical memory above the start, or one that keeps growing over a longer play, is the failure.
- **Answer:** stutter, yes or no, and the memory figure before, at its highest while playing, and after.
- **Source:** #127 G6 phases 2 and 3 (spec §11 G-36, G-37); `tools/proof/playback_prefetch_proof.py --bench` measures the share of frames composed, not how the play looks.

**GR-10 — A replay plays from memory, and the memory is given back**
- **Setup:** as GR-9's, Background render still off in Settings ▸ Playback; tick it on again when this check is done.
- **Do:** Open a COPY of `~/temp/testmotiongraphics/parive-promo.framejob` and play its `section` scene (clip 8, from 41.87 s) for 10 s, then play the same 10 s again, then close the window.
- **Expect:** the replay stutters visibly less than the first play. Frame Job's memory stays raised after the plays, at most a quarter of physical memory above the start, and falls when the window closes.
- **Answer:** smoother, yes or no; the memory figure before, after both plays, and after the close.
- **Source:** #127 G6 phase 3 (spec §11 G-37); `tools/proof/graphic_memory_proof.py --bench` measures the share of frames composed on each play, not how the replay looks.

**GR-11 — Background render draws while Frame Job is left alone, and stops when you touch it**
- **Setup:** GR-9's, with Background render on at 5 s in Settings ▸ Playback, and Activity Monitor showing Frame Job's CPU and memory.
- **Do:** Open a COPY of `~/temp/testmotiongraphics/parive-promo.framejob`, park the playhead at 41.87 s, and leave Frame Job alone for 20 s. Press Shift once, wait 20 s, then play 10 s. Park at 41.87 s again, press ⌘H to hide Frame Job and wait 20 s with it hidden. Then show it, untick Background render and leave Frame Job alone for 20 s.
- **Expect:** CPU stays low for about 5 s after you stop, then rises, and falls at the Shift. Hidden, the CPU rises about 5 s after the ⌘H and stays up (a pass opts out of App Nap). Memory stays within a quarter of physical memory above the start. The play is visibly smoother than GR-9's first play. With the box unticked, the CPU stays low while Frame Job is idle.
- **Answer:** CPU low, then up, then down at the Shift, yes or no; smoother than GR-9's first play, yes or no; CPU up while hidden, yes or no; idle CPU low with the box off, yes or no; the memory figure before and at its highest.
- **Source:** #127 G6 phase 4 (spec §11 G-38); `tools/proof/background_render_proof.py` measures this by tool, not the keyboard path or the look.

## Mattes

**MAT-1 — A matte plays**
- **Do:** 1. Put a 1080p movie on a track and a large bold text clip on the track above it; give the text a motion preset or an action that moves it across the frame. 2. Track ▸ Matte ▸ Alpha with the text selected. 3. Play it at View ▸ Preview Quality ▸ Full, then at Quarter. 4. Switch the mode to Luma, then Inverted Alpha, and play again. 5. In a 3840×2160 project, put a full-frame shape filled with a slow black-to-white linear gradient (one edge to the other) over the movie, set its track to Matte ▸ Luma, and look at a still frame at Full; then set it to Matte ▸ Off and look at the gradient itself.
- **Expect:** only the movie shows, and only through the letters (outside them, the canvas background; with Inverted Alpha, the reverse); the window follows the text's movement frame for frame with no lag behind it; the letters' edges are clean at Full and at Quarter, with no fringe, flicker or banding; Luma shows the movie through the text's brightness; in step 5 the movie fades in smoothly across the frame, with no step or band you cannot also see in the gradient drawn on its own.
- **Source:** #240 (mattes MT4 and MT5, spec §11 MT-1..MT-7).

**MAT-2 — The matte chrome reads right**
- **Do:** 1. In a project with three tracks (a movie, then a shape above it, then a text clip above that), make the shape's track Track ▸ Matte ▸ Alpha and the text's track Matte ▸ Inverted Luma (it has a matte behind it, so it cuts nothing). 2. Look at the timeline at View ▸ Timeline Track Height Small, Medium and Large, and scroll the timeline sideways and back. 3. Select the shape, then the text, and look at each Clip sub-tab. Repeat in the other appearance.
- **Expect:** the shape's header reads "Matte · Alpha" in the ordinary label colour on a faint accent tint and the text's a dimmed "Matte · nothing behind" — under the name on Medium and Large, beside it on Small, where the name is clipped (on a Small text or audio row the text's tag reads "Matte" alone and its name stays readable); the two matte lanes' clips are half-transparent with a dashed outline; an accent bracket just right of the header column joins the shape's lane to the movie's and stays there while scrolling, with no stale copy left behind; the note under the sub-tab strip reads whole on every sub-tab ("Matte for the track below (Alpha). …" for the shape, "Nothing is behind this matte track, so it cuts nothing." for the text). Nothing is cramped, clipped or low-contrast, the dimmed tag included, in both appearances.
- **Source:** #240 (mattes MT4, spec §11 MT-7); `tools/proof/screens.py --only 10c-matte-track` captures the Medium case.

**MAT-3 — A dissolve or zoom between nested clips plays smoothly**
- **Do:** 1. In a 3840×2160 project, put two movies on one track, select both and Nest them. 2. Split the nest clip in the middle and add a cross dissolve at the split. 3. Play the dissolve at View ▸ Preview Quality ▸ Full, then at Quarter. 4. Put the same two movies, un-nested, on a second project's track with the same dissolve, and play that too. 5. Change both transitions to Zoom and play both again.
- **Expect:** the nested dissolve plays without a stutter or a dark dip at its middle, and looks like the un-nested one; the nested zoom also plays without a dip, its picture as sharp as the un-nested zoom's to the eye.
- **Source:** #252 (issue batch B90 phase 4, spec §11 MT-8).

## Precision

**PRC-1 — The preview looks as before**
- **Do:** 1. In a 1920×1080 project, put a screen recording (or a movie of one) on a track, a title over it, and a shape filled with a slow black-to-white linear gradient at 50 % opacity with its blend set to Multiply over both. 2. Look at the preview, paused and playing, at View ▸ Preview Quality ▸ Full, then at Quarter. 3. If a build from before the precision road map is at hand, open the same project in it beside this one and compare. 4. In a new 1920×1080 project, import a 10-bit ProRes ramp — `tools/proof/work/precision/media/ramp10_prores422hq.mov` once `precision_proof.py` has run, or made by the one-line ffmpeg recipe in `tools/proof/README.md`'s precision section — and play it at Full. 5. If real camera footage is at hand (10-bit if possible, a sky or a wall with a soft gradient), play it the same way.
- **Expect:** the colours, the sharpness of the recording's text and the title's edges are as they were (no tint, no lighter or darker cast, no softening); the gradient is smooth; nothing flickers or shimmers, paused or playing, at either quality. The ramp plays with no new banding: no visible steps across it, and no worse than an 8-bit view of the same file; the camera footage shows no new banding, tint or edge fringes.
- **Source:** the precision road map's PR1 (spec §11 PR-1: the preview shows the compositor's 16-bit-float frames, with no EDR and no HDR flag; `preview_display_probe.py`'s spike found no script can see how the layer reads them, so this row is the check), and PR2 (spec §11 PR-2: every video source decodes to 16-bit float; `precision_proof.py` R1 measures the ramp's levels in a render, not on screen).

**PRC-2 — Deep exports play and look right**
- **Do:** 1. In a project with a full-frame shape filled with a slow black-to-white linear gradient (one edge to the other) and a title over it, export `prores_422` and then `prores_4444` (File ▸ Export…). 2. Open each file in QuickTime Player and look at it beside Frame Job's preview of the same frame. 3. In a 1920×1080 project holding the 10-bit ProRes ramp (PRC-1's step 4), export "HEVC 10-bit (MP4)" (`hevc_10bit`) and then "HEVC (MP4)" (`hevc`), and play both in QuickTime Player side by side.
- **Expect:** both ProRes files play; the gradient is smooth in each, with no band or step you cannot also see in the preview; the colours and the title are the ones the preview shows. The HEVC 10-bit file plays, smooth across the ramp, the same colours as the preview; beside it the `hevc` file may show faint bands, and the 10-bit one shows fewer or none.
- **Source:** the precision road map's PR1 (spec §11 PR-3: the ProRes rows take the compositor's 16-bit frames) and PR3 (spec §11 PR-3: the `hevc_10bit` row writes Main 10; `precision_proof.py` T2 measures the ramp, not what the player shows).

**PRC-3 — A reversed clip looks like its forward twin**
- **Do:** 1. In a project, put an iPhone HDR (HLG) clip on a track twice, end to end, and turn on the Clip tab's Reverse for the second copy; let the reverse render. 2. Play across the join and pause on a frame of each half, at View ▸ Preview Quality ▸ Full. 3. If log footage and a `.cube` LUT for it are at hand, do the same with a log clip, the LUT on both copies (File ▸ Add Media…, then its tile in the Color sub-tab's Look section). 4. Export `prores_422` (File ▸ Export…) and look at the join in QuickTime Player.
- **Expect:** the reversed half looks the same as the forward half — the same brightness, contrast and colour, not flatter, greyer or tinted — and shows no new banding in a sky or a soft gradient, in the preview and in the export.
- **Source:** precision-2 P2-2 (spec §11 PR-7: the reversed intermediate is 10-bit and carries the source's colour labels); `precision_proof.py` V2 and V3 measure an HLG ramp's labels and render on synthetic fixtures, not how real footage looks.

**PRC-4 — A 16-bit still grades without bands**
- **Do:** 1. Make a 16-bit gradient still — the `ramp16.png` recipe in `tools/proof/README.md`'s "precision-2 P2-1" paragraph (or `tools/proof/work/precision/media/ramp16.png` once `precision_proof.py` has run), or a 16-bit sky exported from Lightroom or Photoshop. 2. Put it alone in a 1920×1080 project and select its clip. 3. On the Clip tab's Color sub-tab, give it a strong Master curve (an S-curve). 4. Look at the preview at View ▸ Preview Quality ▸ Full. 5. Export `prores_422` (File ▸ Export…) and open the file in QuickTime Player.
- **Expect:** no contour bands across the gradient, in the preview or in the export.
- **Source:** precision-2 P2-1 (spec §11 PR-6: a still deeper than 8 bits a component is drawn at 16-bit float); `precision_proof.py` S1 measures the levels through `prores_422`, not the look.

**PRC-5 — A saved frame of a 16-bit still is 16-bit and looks like its export**
- **Do:** 1. Put PRC-4's 16-bit gradient still alone in a 1920×1080 project, and in a second project put it at half size (the Clip tab's Scale at 50 %) over an ordinary 8-bit movie. 2. In each, park the playhead on the still and choose File ▸ Save Frame…, once as PNG and once as JPEG. 3. In Finder, Get Info on each file (or `sips -g bitsPerSample <file>` in Terminal), and open each in Preview beside Frame Job's preview of the same frame.
- **Expect:** each PNG is 16 bits a sample and each JPEG 8; both look like the same frame in a `prores_422` export of it opened in QuickTime Player — the same brightness and colour, no tint, nothing shifted — and the PNG's gradient shows no bands.
- **Source:** issue batch B97 (spec §11 PR-9: a frame showing a deep still is read through export's reader); `precision_proof.py` S4, S5 and S14 measure the depth and the pixels against the generator's render, not how a viewer shows the file. Issue batch B102 (spec §11 PR-11) labels every saved frame BT.709, as every movie export is tagged, so the comparison is with an export rather than the preview.

**PRC-6 — A saved frame of an untagged H.264 clip looks like its export in the darks**
- **Do:** 1. Import an ordinary untagged H.264 movie (a phone or screen-capture clip whose `ffprobe` colour tags read `unknown`) into a project of its own size and park the playhead on a frame with dark areas. 2. Choose File ▸ Save Frame… three times, as PNG, JPEG and HEIC. 3. Export the project with the `h264` preset. 4. Open the three stills in Preview, each beside the export paused on the same frame in QuickTime Player.
- **Expect:** every still looks the same as the export in the darks and shadows: no lifted or crushed blacks, no tint, the same brightness overall.
- **Source:** issue batch B102 (spec §11 PR-11: every rendered frame's file is labelled BT.709, the tag every movie export carries); `frame_label_proof.py` F1 and F11 measure the label and the pixels, not how a viewer shows the file.

## Grading

These rows are run on a Release build (`make app`), with real camera footage of your own (1080p or 4K; a face, some sky or a wall with a soft gradient, and some foliage help), in a project you can spare or a copy of one. GRD-5 and GRD-6 need a `.cube` 3D LUT you own; GRD-8 spends from your own Assistant key and budget.

**GRD-1 — Light looks right on real footage**
- **Do:** 1. Open real camera footage (1080p or 4K, a face and a sky or a wall with a soft gradient if possible) and select the clip. 2. On the Clip tab's Color sub-tab, open Light and drag Exposure to +1.00 EV, then −1.00 EV, then back to 0. 3. Set Temperature to +0.5, then −0.5; then Tint to +0.5 and −0.5. 4. Try Highlights −0.5, Shadows +0.5, Whites +0.5, Blacks −0.5, Vibrance +0.5 and Fade 0.5, one at a time, each back to 0 after. 5. Play the clip with a few of them set, at View ▸ Preview Quality ▸ Full and Quarter. Repeat in the other appearance.
- **Expect:** +1 EV looks like one stop brighter (twice the light, highlights rolling into white rather than turning flat grey) and −1 EV one stop darker; positive temperature reads warmer and negative cooler, with no green or magenta cast creeping in, and tint moves only along green–magenta; highlights and whites move the bright end, shadows and blacks the dark end; vibrance lifts dull colours more than strong ones (skin does not go orange); fade lifts the blacks to a matte look; no new banding in the sky or wall at any setting; playback is smooth; every slider, field and the section's "neutral"/"adjusted" summary read clearly in both appearances, and Reset puts the clip back exactly as it was.
- **Source:** the grading road map's GR2 (spec §11 GR-2); `tools/proof/tone_proof.py` measures each strength on synthetic cards, not how it looks on footage.

**GRD-2 — Show Ungraded and the waveform read right on real footage**
- **Do:** 1. Open real camera footage and grade a clip with Light (say Exposure +1.00 EV and Temperature +0.5). 2. View ▸ Show Ungraded (⌃⌘U) on and off a few times, paused and while playing; open View ▸ Preview Window (⇧⌘P) and toggle it again there. 3. View ▸ Scopes (⌃⌘W), its top slot on Waveform: scrub, play, and drag the Exposure slider up until the sky or a window clips, then down until the shadows clip. 4. Park the playhead at the very end of the timeline (play through it) and drag Exposure again. 5. Export a short range with Show Ungraded on and look at the file. 6. Close the window and reopen the project. Repeat 2–3 in the other appearance and at Preview Quality ▸ Quarter.
- **Expect:** the switch flips the picture between graded and ungraded at once in both the editor and the Preview Window, with the "Ungraded" tag at the pane's top-left only while it is on and never in the way of a click; the waveform's shape follows the picture (a bright sky high, shadows low, left to right as in the frame), its red marks appear on the top edge over exactly the clipping columns and on the bottom edge for crushed blacks, and the two readouts move with the slider; after a drag the paused waveform ends on the last value, also when parked at the end; playback stays smooth with the panel shown; the export is graded whatever the switch says; both are off after reopening, and the panel, the well, the trace and the labels read clearly in both appearances.
- **Source:** the grading road map's GR3 (spec §11 GR-4, GR-5); `tools/proof/seeing_proof.py` measures the option's bytes and the readouts on synthetic fixtures, not how the panel reads on footage.

**GRD-3 — An adjustment clip grades the footage under it**
- **Do:** 1. Open real camera footage with a title over it, set an In/Out range over part of the clip (I, O), and choose Insert ▸ Adjustment Clip. 2. On the Color sub-tab, set Light ▸ Exposure to +1.00 EV and Color ▸ Saturation to −1, then drag Adjustment ▸ Strength from 100% down to 0% and back to 75%. 3. Play across the clip's edges, at View ▸ Preview Quality ▸ Full and Quarter. 4. Clear the range, select nothing and insert another one; then select a clip with the playhead elsewhere and insert again. 5. Undo each insert once. 6. Make the adjustment clip's track a matte (Track ▸ Matte) and look at the Clip tab. Repeat 2 in the other appearance.
- **Expect:** the first clip covers exactly the range and appears selected, with the inspector on Clip ▸ Color showing Adjustment, Light and Color, and no Picture tab; the footage AND the title under it go brighter and grey, by less as Strength drops and not at all at 0%; the grade starts and stops on the clip's edges with no flash; the second clip covers the whole timeline and the third the selected clip's span, on the front track when it is free there and on a new front "Adjustment" track when not; one undo removes each insert (with its track when one was added); on a matte track the Clip tab says "An adjustment clip on a matte track has no effect." and the picture shows no grade; every row reads clearly in both appearances.
- **Source:** the grading road map's GR4b (spec §11 GR-6); `tools/proof/adjustment_proof.py` measures the grade on synthetic shapes and the menu, tabs and note over MCP, not how it looks on footage.

**GRD-4 — The Look gallery and Clip ▸ Look ▸ on real footage**
- **Do:** 1. Open real camera footage (a face and some sky or foliage if possible), select the clip, and on the Clip tab's Color sub-tab open Look. 2. Wait a moment, then look at the nine tiles; move the playhead to another moment of the clip and wait again; play the clip and stop it. 3. Click Warm, then Teal & Orange, then drag Amount from 100% down to 0% and back to 60%; click Cool and check the amount stays. 4. Select two clips with different looks and open Clip ▸ Look; pick Vivid; undo (⌘Z) once. 5. Click None; Reset; undo. 6. With View ▸ Show Ungraded on, look at the tiles and the preview. 7. Close the Look section, move the playhead, reopen it. Repeat 1–3 in the other appearance.
- **Expect:** each tile shows the frame at the playhead as that look would make it, None the clip without a look, and the eight read as their names say (warm golden, cool crisp, teal shadows with warm skin, punchy, soft matte, an old print, moody, monochrome); the tiles follow the playhead shortly after it stops and never flicker or stall the window during playback; a click changes the preview at once, outlines that tile in the accent and adds the Amount row, and a new kind keeps the amount; with two clips of different looks the menu shows dashes on both kinds and the gallery outlines none; one undo puts back exactly what was there; with Show Ungraded on the preview is ungraded but the tiles still show each look; a closed section renders nothing and catches up when reopened; every tile, name, outline and the summary read clearly in both appearances.
- **Source:** the grading road map's GR5b (spec §11 GR-7); `tools/proof/look_proof.py` holds the thumbnails to `render_frame`'s bytes, the menu, the section and the gallery's timing over MCP and a probe, not how the looks or the gallery read on footage.

**GRD-5 — A `.cube` LUT through the Media tab and the paused preview**
- **Do:** 1. Open a project with footage on the timeline, pause, and choose File ▸ Add Media… — check `.cube` files are offered — and add a `.cube` LUT you own. 2. Drag a second `.cube` file from the Finder onto the Media tab. 3. Look at the two LUT rows; try to drag one to the timeline; right-click it and look at Insert/Overwrite at Playhead. 4. Apply one to the paused clip (its tile in the Look section's Imported group) and look at the preview without moving the playhead. 5. Rename or move the LUT file away in the Finder, reopen the project, and use Relink… on its row; look at the paused preview again. 6. Right-click the LUT row ▸ Remove; read the alert; choose Remove and Clear Looks; undo (⌘Z). Repeat 3 in the other appearance.
- **Expect:** the open panel lists `.cube`; both ways import a row with a cube glyph, the meta "LUT", no thumbnail; it cannot be dragged and Insert/Overwrite are dimmed; applying it changes the PAUSED preview at once (no play or scrub needed), and so does the relink (a missing LUT row shows the missing badge and the clip draws ungraded, with no slate); Remove asks "It is the look of 1 clip, which keeps its place and loses the look." with Remove and Clear Looks, the clip stays and loses the look, and undo brings both back; the row reads clearly in both appearances.
- **Source:** the grading road map's GR6a (spec §11 GR-8); `tools/proof/lut_proof.py` holds the import, the refusals, the picture (`render_frame`), relink, consolidate, remove and paste over MCP and the probe holds where a look finds its file, not the open panel, the Finder drop, the row's look or the live preview.

**GRD-6 — Imported LUTs in the Look gallery, Import LUT… and Clip ▸ Look ▸**
- **Do:** 1. Open real camera footage, select the clip, and on the Clip tab's Color sub-tab open Look. 2. Click Import LUT… — check only `.cube` files can be chosen — and pick a `.cube` LUT you own. 3. Look at the Imported group and the preview; undo (⌘Z) once; redo. 4. Import a second LUT through File ▸ Add Media…; click its tile, then open Clip ▸ Look and pick the first LUT's item. 5. Select two clips, one with each LUT, and open Clip ▸ Look. 6. Click Import LUT… again and pick the first file a second time. 7. Choose a file that is not a LUT (rename a text file to `.cube`). 8. Move one LUT file away in the Finder and look at its tile and item. Repeat 1–4 in the other appearance.
- **Expect:** the panel is a sheet on the window; the imported LUT appears in the Media tab, as a tile under "Imported" named after its file without `.cube`, outlined, with a thumbnail of the frame as that LUT draws it, and the preview changes at once; one undo removes both the look and the row, and redo brings both back; the menu lists the LUTs after the eight looks under a separator, before None, with a checkmark on the clip's LUT and dashes on both when two clips differ; choosing the same file again adds no second row and applies it; a non-LUT file shows an alert naming the file and the reason, and nothing changes; a missing LUT keeps its tile (its thumbnail ungraded, as the clip draws) and its item; the tiles, names, outline, the button and the summary ("<name> 80%") read clearly in both appearances.
- **Source:** the grading road map's GR6b (spec §11 GR-8 [b]); `tools/proof/lut_proof.py` holds the LUT thumbnails to `render_frame`'s bytes, the gallery's layout, the menu and the undo steps over MCP and the probe, not the open panel, the alert, or how the group reads on footage.

**GRD-7 — One adjustment clip grades a whole video**
- **Do:** 1. Open a real project with several camera clips on the timeline, select nothing, and choose Insert ▸ Adjustment Clip. 2. On the Color sub-tab, grade it (say Light ▸ Temperature +0.3 and Exposure +0.5 EV). 3. Trim one camera clip under it, move another, and reorder two; play across every edit. 4. Export a short range and look at the file.
- **Expect:** the adjustment clip covers the whole timeline in one undo step; every camera clip under it takes the grade, and a clip trimmed, moved or reordered under it keeps the grade with no re-grade; there is no flash at the edits; the export shows the same grade as the preview.
- **Source:** the grading road map's trial task T2 (spec §11 GR-6); the owner did not run it in the trial (GR7b), and `tools/proof/adjustment_proof.py` measures the grade on synthetic shapes, not a real project.

**GRD-8 — The Assistant warms and brightens the camera clips**
- **Do:** 1. With your own key in Settings ▸ Assistant (it spends from your own budget), open a real project with camera clips and open View ▸ Assistant. 2. Ask "make the camera clips warmer and a bit brighter". 3. Look at the camera clips' Light sections, then open Edit and press ⌘Z once per op the Assistant made.
- **Expect:** the Assistant does it through its tools (no instructions to you to do it by hand); the camera clips' Temperature and Exposure (or Brightness) moved and nothing else did; each op it made is one undo step, named in Edit ▸ Undo, and undoing all of them puts the project back exactly as it was.
- **Source:** the grading road map's trial task T5 (spec §11 GR-2); the owner did not run it in the trial (GR7b), and no script spends a key on it.

**GRD-9 — A power window: brighten a face inside an ellipse**
- **Do:** 1. Open real camera footage with a face in it. 2. Without looking anything up, brighten only the face, inside an ellipse, leaving the rest of the frame as it was. 3. Play the clip.
- **Expect:** it can be done without being shown how; the face inside the ellipse is brighter and nothing outside it changes; the ellipse's edge has no fringe. If it needs showing, that is the answer: the shape mask (cut from grading's tier 1, spec §11 GR-1) comes back as an issue.
- **Source:** the grading road map's trial task T6 (spec §11 GR-1, GR-6); the owner did not run it in the trial (GR7b). Read only after trying: it is built as an adjustment clip over the footage, graded brighter, with an ellipse shape on a matte track over it.

**GRD-10 — Someone other than the owner tries the grading tasks**
- **Do:** 1. Give someone who has not used Frame Job's grading a Release build, real camera footage and the six tasks: fix a clip that is too warm and too dark with Light alone (T1); grade a whole video with one adjustment clip (T2); give it a built-in look and set its amount (T3); import and apply a `.cube` LUT they have (T4); ask the Assistant to make the camera clips warmer and a bit brighter (T5); brighten a face inside an ellipse without being shown how (T6). 2. Watch without helping, and note where they stop, ask or guess.
- **Expect:** each task is done without help; the owner records what they found hard and what to adjust, and files each adjustment as an issue.
- **Source:** the owner's verdict, 2026-10-10 (GR7b): "I'll get feedback later from others and we can adjust."

**GRD-11 — The scopes read right on real footage**
- **Do:** 1. Open real camera footage with a face in it and choose View ▸ Scopes (⌃⌘W); the panel opens with Waveform over Vectorscope. 2. Set the top slot's picker to Parade and give the clip a warm cast (Light ▸ Temperature +0.5). 3. Look at the vectorscope with the face filling much of the frame. 4. Set the bottom slot to Histogram and drag Light ▸ Exposure from −1.00 EV to +1.00 EV. 5. Play the clip with both slots shown; pick each scope in each slot once, and the same scope in both. 6. Hide and show the panel; close the window and reopen the project. 7. Make the window laptop height (or drag the timeline divider up until the preview pane is short), then shorter still. 8. With the face filling the frame, click the vectorscope's 2× cell, then 4×; then frame a grey card or a grey wall and do the same; set the bottom slot to Parade and back to Vectorscope, and hide and show the panel. 9. Put a solid-colour slide or title (a strong red, say) on the timeline and play across it with the vectorscope shown. Repeat 2–5 in the other appearance and at View ▸ Preview Quality ▸ Quarter.
- **Expect:** the parade shows the warm cast as red high and blue low; the vectorscope's skin tones sit near the skin line (up and to the left of centre) and a grey wall at the centre; the histogram moves right with Exposure and its "Highlights clipped" readout rises when the sky clips; both slots follow the picture while playing and playback stays smooth; the picks survive hiding and showing, and a reopened project starts at Waveform over Vectorscope; on a laptop-height window both slots shrink together and stay readable, the vectorscope square and centred, and only when the pane is very short (under 360 pt) does the bottom slot go away; the pickers, captions, wells, graticules, targets and labels read clearly in both appearances; at 2× and 4× the face's and the grey card's blobs grow and their shape and lean show (a slight cast reads as an off-centre blob), the six targets become short ticks on the square's edge pointing toward their colours, each still labelled and legible, the skin line stays, and the cell clicked is the filled one; the zoom stays across the pick away and back and across hiding and showing, and a reopened project's vectorscope is at 1×; playing across the solid-colour slide stays as smooth as across footage.
- **Source:** grading-2's G2-1 (spec §11 GR-10) and grading-4's T4-1 (GR-26, GR-31); `tools/proof/scopes_proof.py` measures the bins, counts, timings and layout on synthetic fixtures (T1 the GPU time on a flat saturated colour), not how the scopes read on footage or whether the slide plays smoothly.

**GRD-12 — The wheels grade real footage**
- **Do:** 1. Open real camera footage with a colour cast (or give a clip one: Light ▸ Temperature +0.5) and show View ▸ Scopes with Parade on top. 2. On the Color tab, open Wheels and drag the Gain puck away from the cast until the parade's red, green and blue tops line up. 3. Drag the Lift puck toward orange to warm the shadows; watch the vectorscope's trace move toward the puck. 4. Drag a puck and a master strip with ⌥ held, then without. 5. Double-click a puck, then a strip; then the section's Reset. 6. Undo after each drag, and hover a disc. 7. Repeat 2–5 in the other appearance, at the 280 pt and the 440 pt inspector widths.
- **Expect:** Gain alone removes the cast in the highlights and the parade's tops meet; Lift warms the shadows and leaves white white; a puck's drag moves the vectorscope's trace the same way the puck moves; ⌥ moves the puck and the knob a tenth as far, with no jump when the press lands; a double-click centres the puck (or the knob) and nothing else, and Reset centres all three; a strip double-click, on or off the knob, undoes in one step to the value before it (#272); each drag undoes in one step named Lift, Gamma or Gain; the hover reads "Hue …° · …" or "Neutral"; the discs, pucks, strips and fields read clearly in both appearances at every width, and the picture never stutters while dragging.
- **Source:** grading-2's G2-2 (spec §11 GR-11); `tools/proof/wheels_proof.py` measures the formulas on a grey card and ramp, export parity and the gesture's arithmetic, not how a grade looks on footage.

**GRD-13 — Curves on real footage**
- **Do:** 1. Open real camera footage and show View ▸ Scopes with Histogram on top. 2. On the Color tab, open Curves and, on Master, click the curve near a quarter and three quarters and drag them into a gentle S. 3. Choose Blue and lift the shadows: click low on the curve and drag up. 4. On Master, drag the bottom-left end point right and the top-right end point left (black and white points). 5. Select a point and press ⌫, double-click another, nudge one with the arrows (and ⇧-arrows), type an In and an Out. 6. Drag with ⌥ held, then without; press Esc, then Space. 7. Undo after each step; right-click the Blue cell and Reset Blue; then the section's Reset. 8. Repeat 2–7 in the other appearance, at the 280 pt and the 440 pt inspector widths. 9. (T4-2) Choose Hue: on a shot with grass or foliage, click the curve over the green of the spectrum strip and drag up, then choose Sat and drag the red region down; on a face, nudge the orange with the arrows. 10. Hover the plot on Master, Hue and Sat and read the label; drag a point with ⇧ held, first mostly sideways then mostly up, then with ⇧ and ⌥ together. 11. Repeat 9–10 on an adjustment clip over the shot. 12. (T4-3) On Master make a 3-point curve, add a one-second action, select it and add two points to make a 5-point curve at the action's end (each click, with the action selected, keys the curve); play across the action and scrub its ends.
- **Expect:** the S-curve deepens the shadows and brightens the highlights with no banding or sudden kink; the Blue curve tints only the shadows blue and the Blue cell gains a dot; moving the end points clips black and white as the histogram shows; a new point lands on the curve where clicked and never jumps; ⌫ deletes only while a point is selected (with none, ⌫ still deletes the selected clip) and a curve never drops below two points; ⌥ moves a tenth as far; Esc deselects and Space plays; each edit undoes in one step named Curves; the plot, the cells, the points and the fields read clearly in both appearances at every width, and the picture never stutters while dragging. (T4-2) Dragging the green up turns the foliage toward teal and blue with its brightness kept and no banding or tearing at the edges of the green; Sat down mutes the reds only; greys and whites stay grey; the six cell labels fit without clipping at 280 pt; the readout follows the pointer, reads the curve's value under it ("Hue 120° → +30°"), flips inward at the plot's top and right edges and never covers the point being dragged out of view; with ⇧ the point stays on the first axis it moved along; on the adjustment clip the hue curves grade everything behind it the same way. (T4-3) Adding a point with the action selected keys the curve (the action's mark appears on the Curves row), and the action between the 3-point and the 5-point curve eases smoothly from one to the other with no jump at either end.
- **Source:** grading-2's G2-3 (spec §11 GR-12) and grading-4's T4-2 (GR-32) and T4-3 (GR-34); `tools/proof/curves_proof.py` measures the curve on a grey card and ramp, the hue curves on a synthetic hue sweep (HSV-hue change and luma), export parity and the editor's gestures, not how a curve looks on footage.

**GRD-14 — Pick and grade skin on real footage**
- **Do:** 1. Open real camera footage with a face in it and add an adjustment clip over it (Insert ▸ Adjustment Clip). 2. On its Color tab, open Qualifier, press Pick from Canvas and click the cheek. 3. Turn on Show Selection (the switch, or View ▸ Show Selection) and play. 4. Widen the hue softness and the saturation band (drag the squares and knobs, then type in the fields) until the face is white with a clean edge and the background black; try ⌥ on a drag and a double-click on a strip. 5. Turn Show Selection off, warm the face (Light ▸ Temperature +0.3) and play. 6. Select a media clip, then the adjustment clip again; press Esc during a pick. 7. Repeat 2–4 on a darker shot with shadow noise, and in the other appearance, at the 280 pt and 440 pt inspector widths. 8. Export a few seconds with Show Selection on. 9. (T4-4) On noisy footage with the skin pick of step 2, Show Selection on, raise the Qualifier's Blur from 0 % until the speckled edge is clean, type a value, then Reset; turn Show Selection off and play the graded shot at 4K with Blur at about 25 %, at Full and at Half preview quality.
- **Expect:** the pick turns hue and saturation on around the skin; Show Selection shows the face white and greys and dark noise black (the chroma and near-black guards), the "Selection" tag beside the preview; the softness widens the edge smoothly with no hard ring; only the face warms, and the background and greys stay as they were; selecting a media clip turns Show Selection off and Esc leaves a pick; each strip drag and each pick undoes in one step (Hue, Saturation, Luma, Qualifier); the export is the graded picture, never the selection; the strips, knobs, squares and fields read clearly in both appearances at every width, and playback stays smooth. If the guards pick dark noise or drop real skin, the first numbers in spec §11 GR-13 are what to retune. (T4-4) Blur melts the speckle into a smooth grey edge without growing the selection onto the background, the same at Full and Half; the blur undoes in one step named Qualifier Blur and Reset sets it to 0 %; with the blur on, 4K playback stays smooth (no dropped frames you can see); if 100 % is too little or too much on real footage, the 24 px of spec §11 GR-35 is the number to retune.
- **Source:** grading-2's G2-4 (spec §11 GR-13) and grading-4's T4-4 (GR-35); `tools/proof/qualifier_proof.py` measures the ranges on synthetic hue, saturation and ramp cards and the blur on a synthetic noise card against a scripted Gaussian, not how a selection holds up on skin.

**GRD-15 — A sky inside a shape**
- **Do:** 1. Open footage with a sky and add an adjustment clip over it with a qualifier on the blue of the sky (Pick from Canvas on it) and Light ▸ Exposure −0.5. 2. Add a track in front of the adjustment clip's, draw a rectangle shape over the top half and make that track an alpha matte. 3. Turn Show Selection on and off; move the rectangle down over something else blue. 4. Animate the qualifier's hue centre with an action from blue to cyan and play it.
- **Expect:** only the sky inside the rectangle darkens — blue outside it and the rest of the frame are untouched; Show Selection shows white only where the sky meets the rectangle; moving the rectangle moves the darkened area; the animated centre sweeps the short way between the two hues, never through red.
- **Source:** grading-2's G2-4 (spec §11 GR-13, matte × qualifier); `qualifier_proof.py`'s M1 measures the product on a card.

**GRD-16 — iPhone HDR footage**
- **Do:** 1. Import an ordinary iPhone HDR clip (default Camera settings, HEVC) into a project of its own. 2. Look at it in the preview — with the playhead parked, paused, on the clip's first frame, and again just after Play from there; then play the composition through to its end — save a frame (File ▸ Save Frame…) and export a short GIF, and compare each side by side with the clip in QuickTime Player. 3. Export `prores_422` and step through the first frames where the clip starts in QuickTime Player. 4. Select the clip, open the Chroma Key section, press Pick from Canvas and click something green (or any distinct colour) in the frame; play. 5. Re-run PRC-3's HLG half (steps 1, 2 and 4) on this clip. 6. In another project, put a short Frame Job screen recording (File ▸ New Recording…) beside the iPhone HDR clip, and look at the recording there, in a project of its own, and in QuickTime Player. 7. (hdr H-2) In the first project set the Document tab's Dynamic Range to HDR (HLG) and repeat step 4's key on the same colour; export `hevc_10bit` and open it in QuickTime Player.
- **Expect:** the preview, the saved frame and the GIF all look like QuickTime Player's picture — not flat and grey, highlights rolling off rather than clipping, saturated colours not clipped; the preview's first frame, paused and on Play, is not washed out, and playback to the end stays smooth and never turns washed out; no washed-out flash on the clip's first exported frame; the key removes the colour that was picked, in the preview and in an export; PRC-3's expectations hold; the screen recording looks the same in all three places; the clip's timeline filmstrip and its Media-tab thumbnail look like the preview (spec §11 GR-21); (step 7) in the HLG project the clip's highlights are brighter than in the SDR one on an XDR display and nothing washes out, the key still removes the colour with no re-pick (in an HLG project a key on an HDR clip compares the colour an SDR project shows, spec §11 HD-19 (c)), a fresh pick in the HLG project keys the same colour, and the HEVC file looks the same in QuickTime Player as in the preview.
- **Source:** grading-3 T3-1 (spec §11 GR-15 as amended: Frame Job's own HDR→SDR at step 0, chosen per composition, and the sRGB arm), and step 7's key clean-up batch 2's phase 2 (HD-19 (c), #312); `tools/proof/hdr_proof.py` measures synthetic ramps and greens (HKh), not real footage, and its R0 read only a recording's labels.

**GRD-17 — Apple Log footage**
- **Do:** 1. Import an iPhone Apple Log clip (iPhone 15 Pro or later, ProRes with Log, or Blackmagic Camera in Apple Log; or Apple Log 2 from a newer iPhone) into a project of its own. 2. Select its row in the Media tab and read the Camera Log section. 3. Set Camera Log to None, then back to the detected setting. 4. On the clip, Color: raise Brightness a little; then Look: apply Warm. 5. If you have Apple's Apple Log LUT, import it with Use LUT… and compare with the built-in conversion. 6. Note the 18 % grey patch or a face's level in the preview with the waveform open.
- **Expect:** the clip looks like normal video on import (not flat and grey); the section reads "Apple Log — from the file" (or "Apple Log 2 — from the file"); None shows the flat log picture and the detected setting brings it back, one undo step each; the grade and the look act on the converted picture; Apple's LUT and the built-in agree closely in mid-tones (the built-in's mid-grey is Frame Job's 0.42, so they may differ in contrast); mid-grey sits near 42 % on the waveform; the clip's timeline filmstrip and its Media-tab thumbnail look like the preview — like normal video while Camera Log is set, the flat log picture with None — and follow each change of the setting (spec §11 GR-21); whether the file is flagged full range or video range does not change the picture (spec §11 GR-22: Apple Log reads the normalized signal in both). (hdr H-2) Set the Document tab's Dynamic Range to HDR (HLG) and look again on an XDR display: the clip becomes real HDR — the brightest parts glow above the interface's white while 18 % grey (or a face) sits about where it did, near 38 % on the waveform's HLG scale; Color and the look still act on it; a `.cube` LUT applied as a look shows the Look section's warning "This project is HDR (HLG): a .cube LUT reads its values as Rec. 709."
- **Source:** grading-3 T3-2 (spec §11 GR-16: Apple Log detected from its label, converted at step 0 with Apple's published curve); `tools/proof/log_proof.py` measures synthetic ramps only, so whether a real iPhone file carries the label, and whether its code range is what GR-16 assumes, is this check's. Issue batch B95's L11 measures a synthetic full-range Apple Log file.

**GRD-18 — Sony or Panasonic log footage**
- **Do:** 1. If you have an S-Log3 (S-Gamut3.Cine or S-Gamut3) or V-Log (V-Gamut) clip, import it, and note the file's range (QuickTime Player's Window ▸ Show Movie Inspector, or `ffprobe -show_streams`: `color_range` `pc` is full, `tv` video). 2. In the Media tab, set Camera Log to the camera's curve and gamut. 3. Compare with the camera maker's own Rec. 709 LUT applied through Use LUT…, if you have it. 4. Key a green screen in it, if it has one.
- **Expect:** the file imports with Camera Log None (no label is read for these); once set it looks like normal video; it is close to the maker's LUT in mid-tones; the key removes the green as on any other clip; the clip's timeline filmstrip and its Media-tab thumbnail look like the preview — like normal video once Camera Log is set, the flat log picture with None (spec §11 GR-21); black and the 0 % patch sit at black and are not lifted, whichever range the file is flagged (spec §11 GR-22).
- **Source:** grading-3 T3-2 (spec §11 GR-16: S-Log3 and V-Log chosen by hand); `tools/proof/log_proof.py` measures synthetic ramps, so how real Sony and Panasonic files are tagged and coded is this check's. Issue batch B95's L10 and L12 measure synthetic files flagged full and video range (spec §11 GR-22).

**GRD-19 — Canon log footage**
- **Do:** 1. Import a Canon Log 2 or Canon Log 3 clip (Cinema Gamut, or BT.2020 if the camera recorded so) into a project of its own, and note the file's range (QuickTime Player's Window ▸ Show Movie Inspector, or `ffprobe -show_streams`: `color_range` `pc` is full, `tv` video). 2. In the Media tab, set Camera Log to the clip's curve and gamut (C-Log2 or C-Log3, / Cinema Gamut or / BT.2020). 3. Compare with Canon's own Rec. 709 LUT applied through Use LUT…, if you have it. 4. Key a green screen in it, if it has one. 5. Set the Document tab's Dynamic Range to HDR (HLG) and look at it again.
- **Expect:** the file imports with Camera Log None (no label is read for Canon); once set it looks like normal video; it is close to Canon's LUT in mid-tones; 18 % grey (or a face) sits near 42 % on the waveform, and about 38 % on the HLG scale in the HLG project; black is neither lifted nor crushed, whichever range the file is flagged (Canon records full range, spec §11 HD-17 (e): a non-ProRes file flagged video range but storing full-range codes reads too contrasty, an accepted limit this check is for); the key removes the green as on any other clip; the clip's timeline filmstrip and its Media-tab thumbnail follow the setting.
- **Source:** hdr H-5 (spec §11 HD-17: Canon Log 2 and 3 from Canon's *Canon Log Gamma Curves* white paper, Cinema Gamut from the ACES project's Canon CSC, chosen by hand); `tools/proof/log_proof.py` L19–L21 measure synthetic ramps and cards, so how real Canon files are tagged, ranged and coded is this check's.

## HDR

These rows are run on a Release build (`make app`), with real HDR footage of your own, in a project you can spare or a copy of one. Each row was added by the HDR road map's phase that created it, as `designs/adr/hdr.md` records.

**HDR-1 — An HLG project on an XDR display and on an SDR display**
- **Do:** 1. In a new project, put an iPhone HLG clip (default Camera settings), a white text title over it, and a short Frame Job screen recording (File ▸ New Recording…) after it. 2. In the Document tab read the Colour row, then set Dynamic Range to HDR (HLG); read the Colour row again; undo and redo the switch once. 3. Look at all three on the built-in XDR display, paused and playing, beside the interface's own white (a Finder window). 4. Drag the window to an SDR display (or turn the XDR display's HDR off in System Settings ▸ Displays) and look again. 5. Export `hevc_10bit` and `prores_422` and open each in QuickTime Player on both displays. 6. Try Save Frame… as PNG, HEIC and JPEG. 7. (hdr H-3) Turn View ▸ Show SDR Version on, on both displays, paused and playing; turn it off again. 8. (clean-up batch 2) Import the HEIC saved in step 6 into the same project, place it after the recording, and look at it on the XDR display beside the clip, and at its timeline filmstrip and its Media-tab thumbnail; then in a new SDR project of its own.
- **Expect:** the Colour row reads "SDR — Rec. 709", then "HDR — Rec. 2100 HLG"; the switch is one undo step named Dynamic Range; on the XDR display the iPhone clip's highlights glow above the interface's white while the title and the screen recording sit at reference white — as bright as the interface's white, never dimmer or washed out, and the recording looks as it does in an SDR project; on the SDR display the picture is tone-mapped by macOS (highlights compressed, nothing clipped flat, no washed-out grey); each export looks the same in QuickTime Player as the preview on each display; PNG and HEIC save, and JPEG saves the project's SDR version (it looks like step 7's picture, not dim or washed out; hdr H-3); with Show SDR Version on, an "SDR Version" tag sits in the preview's corner and the picture is the SDR version on both displays — no highlight above the interface's white, the title white or very nearly, faces natural — and turning it off brings the HDR picture back at once, with no rebuild flash; (step 8) the HEIC still's highlights glow as the clip's do on the XDR display, not flat at reference white, and in the SDR project it looks like the clip there (spec §11 HD-19 (a)); the HEIC still's timeline filmstrip and Media-tab thumbnail look like its SDR-project preview, in either project (spec §11 HD-21). If the preview on the XDR display looks tone-mapped (no highlight above the interface's white) where QuickTime Player's does not, that is spec §11 HD-2's named risk: report it (the first fallback is the preview layer's `preferredDynamicRange`, the owner's call).
- **Source:** the HDR road map's H-2 (spec §11 HD-2, HD-3, HD-13: the HLG working space, the lift, the frames and the 10-bit exports, #277) and H-3 (HD-7, HD-14: Show SDR Version, JPEG the SDR version), and clean-up batch 2's phase 2 (HD-19 (a): an HDR still by its own label, #311), and clean-up 3 batch B's phase 2 (HD-21: an HDR still's thumbnail drawn through step 0, #323); `tools/proof/hdr_proof.py`'s HS–HX and HI rows and `tools/proof/log_thumbs_proof.py`'s TS measure synthetic ramps' code values against oracles, not how a panel shows them.

**HDR-2 — An HLG project's exports in QuickTime Player and on an iPhone**
- **Do:** 1. In an HLG project (Document tab ▸ Dynamic Range ▸ HDR (HLG)) with an iPhone HLG clip of a face, a white text title over it and a short Frame Job screen recording after it, open File ▸ Export… and read the Dynamic Range row on `hevc_10bit`, then on `h264`. 2. Export `hevc_10bit` and `prores_422` (Dynamic Range: HDR (HLG)) and `h264` (the SDR version). 3. Open the three side by side in QuickTime Player on the XDR display, then AirDrop the `hevc_10bit` and `h264` files to an iPhone and open them in Photos. 4. Turn View ▸ Show SDR Version on and compare the preview with the `h264` file.
- **Expect:** the Dynamic Range row offers HDR (HLG), HDR10 (PQ) and SDR version on `hevc_10bit`; on `h264`, and on every other row that does not carry HDR (all but `hevc_10bit`, `prores_422` and `prores_4444`), it shows "SDR version", greyed and disabled (a click on it opens no menu); the two HLG files show the highlights above the interface's white on the XDR display and on the iPhone, with no Dolby Vision badge or shift (Dolby Vision is off, spec §11 HD-5); in the `h264` SDR version the title is white (not grey), faces look natural (not dark or flat), and only the brightest highlights are compressed; the `h264` file matches Show SDR Version's picture.
- **Source:** the HDR road map's H-3 (spec §11 HD-4, HD-5, HD-14: the SDR version as the inverse of the lift, the deliverables, #277); `tools/proof/hdr_proof.py`'s DT, DV, DI and DE rows measure synthetic ramps' tags and code values against oracles, not how a panel or a phone shows them.

**HDR-3 — An HDR10 (PQ) export**
- **Do:** 1. In the same HLG project, export `hevc_10bit` with Dynamic Range: HDR10 (PQ). 2. Open it in QuickTime Player on the XDR display beside the HLG `hevc_10bit` export. 3. Open it in a player that shows HDR10 metadata (for example IINA's or VLC's media information, or MediaInfo).
- **Expect:** the PQ file looks like the HLG one on the XDR display (the same highlights, the title at reference white); the metadata reads a mastering display of P3 D65 primaries at 0.005–1,000 cd/m², MaxCLL 1,000 and MaxFALL 0 (unknown), and no Dolby Vision.
- **Source:** the HDR road map's H-3 (spec §11 HD-5, HD-14 (d): PQ at 1,000 cd/m² with fixed HDR10 metadata); `tools/proof/hdr_proof.py`'s DP row reads the side data ffprobe names and a synthetic ramp's PQ codes, not how a player shows them.

**HDR-4 — A real HDR10 file mastered above 1,000 cd/m²**
- **Do:** 1. Import an HDR10 PQ file whose mastering peak is above 1,000 cd/m² and whose stated peak you know (a Resolve export, a camera's HDR10 recording or a downloaded HDR10 sample; ideally one at 4,000 cd/m²) into an ordinary (SDR) project of its own. 2. Select its row in the Media tab and read the HDR10 section. 3. Look at its brightest part — a sky, a lamp, a specular highlight — in the preview, paused and playing, and in a saved frame (File ▸ Save Frame…), side by side with the same file in QuickTime Player. 4. Set Peak to 1,000 cd/m², look at the same highlights again, then press Use File's. 5. Undo and redo each step once. 6. If you have one, import an HDR10 file mastered at 1,000 cd/m² or below and repeat 2–3. 7. On an M3 or later Mac, import an HDR10 AV1 file (MP4 or WebM) whose stated peak you know, and an HDR10 VP9 WebM if you have one, and repeat 2. Repeat 2 in the other appearance.
- **Expect:** the section reads "Mastered at <its peak> cd/m² (MaxCLL, from the file)" (or "(mastering display, from the file)"), the number the file's maker states, and Peak shows it; the highlights roll off smoothly toward white with their gradation kept — the clouds in a bright sky, the shape of a lamp — rather than flattening into a clipped white patch; at 1,000 cd/m² the brightest parts clip to white sooner, and Use File's brings the gradation back; each change is one undo step named PQ Peak and the clip's timeline filmstrip and Media-tab thumbnail follow it; a 1,000 cd/m² (or lower) file looks as it did before this change; the AV1 and VP9 files' sections read their stated peaks too; the section, the field and its line read clearly in both appearances. Frame Job's picture need not match QuickTime Player's (Apple's own conversion ignores the file's peak, spec §11 HD-6), but it should not look clipped or grey where QuickTime's does not.
- **Source:** the HDR road map's H-1 (spec §11 HD-6, HD-12: the peak read at import, the override, step 0's shoulder at the file's peak, #281) and clean-up batch 2 (spec §11 HD-18: the WebM/Matroska Colour element and AV1's metadata OBUs, #316; step 7); `tools/proof/hdr_proof.py`'s H7 family, H7w and P10 measure synthetic x265, AVAssetWriter, libvpx-vp9 and libsvtav1 ramps against an oracle (P10 without a decode: an M1 or M2 Mac refuses AV1 imports), not how a real mastered file's highlights look.

**HDR-6 — The scopes on real HDR footage**
- **Do:** 1. In an HLG project (Document tab ▸ Dynamic Range ▸ HDR (HLG)), put a real iPhone HLG clip of a face against a bright sky, a white text title over it, and a short Frame Job screen recording after it. 2. Turn View ▸ Scopes on and pick each scope in turn in both slots — Waveform, Parade, Vectorscope, Histogram — paused on the face with the title, then on the recording; look in both appearances. 3. Turn View ▸ Show SDR Version on and look at every scope again; turn it off. 4. Turn View ▸ Show Ungraded on and off with a grade on the clip. 5. Open an ordinary (SDR) project with its own footage and look at its scopes.
- **Expect:** the waveform's and parade's labels read 0, 10, 51, 203 and 1000, each legible beside its line in both appearances, "1000" not clipped by the slot's edge; the title's trace sits on the dashed 75 % line (203 cd/m²), the sky's highlights above it, and only truly clipped highlights get red marks at the top; the captions read "HLG · cd/m²" over the waveform and parade and "Rec. 2100 HLG" over the vectorscope and histogram; on the vectorscope the face sits near the skin line and the six target boxes lie on the hues they name; with Show SDR Version on every scope turns to its Rec. 709 reading ("Rec. 709 · encoded", labels 0/50/100, no dashed line) and the title sits near the top; Show Ungraded keeps the HLG scale and shows the clip without its grade; the SDR project's scopes look exactly as they did before.
- **Source:** the HDR road map's H-4 (spec §11 HD-8, HD-15: the HLG project's scopes, #277); `tools/proof/hdr_proof.py`'s SW–SP rows and P8 measure synthetic ramps, bars and offscreen bitmaps, not how the panel reads on real footage.

**HDR-7 — An iPhone HDR photo**
- **Do:** 1. Copy a photo from the iPhone 18 Pro (an HDR HEIC, default Camera settings) into a new project, and look at it on the XDR display beside the same photo in Photos. 2. Set the Document tab's Dynamic Range to HDR (HLG) and look again. 3. Export `hevc_10bit` and open it in QuickTime Player beside the preview. 4. Turn View ▸ Show SDR Version on, then off. 5. Undo back to SDR and look at the photo, its timeline filmstrip and its Media-tab thumbnail. 6. Repeat 1–5 with a photo from iOS 17 or older if one is at hand.
- **Expect:** in the HLG project the photo's highlights glow above the interface's white as they do in Photos; mid-tones look natural, though they may sit a little darker than in the SDR project (spec §11 HD-22 (c), the owner's choice); with Show SDR Version on the photo is the HDR picture toned down, not the photo's own SDR picture (HD-22 (h)); the export matches the preview; the SDR project, the filmstrip and the thumbnail look as they did before (HD-22 (d)).
- **Source:** clean-up 3 batch B's phase 3 (spec §11 HD-22: a gain-map still drawn as HDR in an HLG project, #322); `tools/proof/hdr_proof.py`'s HG, HGu, HGk and P15 measure a synthetic ISO gain-map HEIC from Apple's own encoder, so Apple's pre-ISO gain map, a real photo's headroom and look, and JPEG or AVIF gain maps are this check's.

**LIN-1 — Linear-light blending, on and off**
- **Do:** 1. In an SDR project put a cross dissolve between two saturated clips (a red-dominated one and a green-dominated one), a white text title fading in over video, a black shape at 50 % opacity dimming video, and a soft white shape with blend mode `add` (a glow) over video. 2. With the Document tab's Blending popup on Encoded, play each and pause on its middle; then set Blending to Linear light and look again; undo and redo the switch once. 3. Put a grade (Color and Light), a chroma key and a qualified adjustment clip on the video, and switch Blending again. 4. Set Dynamic Range to HDR (HLG) and repeat 2 and 3 on an XDR display. 5. Export `prores_422` with Blending on Linear light and open it in QuickTime Player beside the preview.
- **Expect:** with Linear light the dissolve has no dark dip at its middle (on Encoded it does), the title's and the shapes' soft edges are brighter, the 50 % black dim is far lighter, and the glow adds light; grades, the key and the adjustment clip's selection look the same in both settings; each switch is one undo step named Blending; the HLG project behaves the same way, its titles still at reference white; the export matches the preview.
- **Source:** the HDR road map's H-6 (spec §11 GR-18, HD-9, HD-16: `canvas.blending`, #276); `tools/proof/hdr_proof.py`'s LT–LU rows measure flat cards, ramps and a synthetic dissolve against GR-18's formulas, not how real footage looks blended.

## Screen recording

Launch Frame Job from the Finder or Dock unless the check says otherwise.
To take a permission away again: System Settings ▸ Privacy & Security, or
`tccutil reset ScreenCapture com.kgalligan.FrameJob` (and `Microphone`).

**REC-1 — Record without Screen Recording permission opens Settings**
- **Do:** 1. With Frame Job's Screen Recording permission off, File ▸ New Recording…, press Record. 2. Answer or dismiss the system prompt. 3. Press Record again.
- **Expect:** if Frame Job has never asked on this Mac, the first press shows the system prompt, IN FRONT of the New Recording panel (not hidden behind it). Every later press opens System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, also in front of the panel, with Frame Job's row visible, and the panel's note says Settings is open at that pane. (Once Frame Job has asked, a `tccutil reset` does not bring the prompt back: the first press opens the pane, whose + adds Frame Job. That is accepted.)
- **Source:** spec §11 recording.md (Record asks once, then opens Settings).

**REC-2 — Microphone permission**
- **Do:** 1. Reset Frame Job's Microphone permission; choose a microphone in the panel; Record. 2. Deny it in Settings; Record again.
- **Expect:** first, the system microphone prompt naming Frame Job, in front of the panel; once denied, Record opens System Settings ▸ Privacy & Security ▸ Microphone, in front of the panel.
- **Source:** spec §11 recording.md; #55 R1.

**REC-3 — Launched from a terminal**
- **Do:** Run Frame Job from Terminal (as in CLAUDE.md's "Verifying a build") with the terminal lacking Screen Recording; press Record twice.
- **Expect:** each press shows the system prompt (for the terminal); System Settings never opens.
- **Source:** spec §11 recording.md.

**REC-4 — Picking and recording a window or display**
- **Do:** 1. Launch Frame Job and open New Recording… straight away. 2. Choose window mode; pick a window in the system picker. 3. Record a display with Frame Job playing a timeline. 4. While another app is frontmost, change the panel's popups and switches.
- **Expect:** no freeze on first opening; the picker presents from the panel and the choice arrives; the countdown looks right; the panel is absent from the file from the start and Frame Job's playback does not appear in it; the panel's controls work with another app in front.
- **Source:** #55 R1.

**REC-5 — The menu bar indicator, pause and stop**
- **Do:** 1. During a recording, check the macOS recording indicator and Frame Job's own menu bar item. 2. From the item's menu: Pause, then Resume, then Stop. 3. Record again, Pause, press ⌘Q. 4. Stop from the system indicator. 5. Play the recording across the pause.
- **Expect:** the system indicator names Frame Job and stays up through a pause; paused shows a coral dot, a pause glyph and a frozen time; ⌘Q while paused opens the item's menu instead of quitting; Stop from either place lands the file; the panel returns only with a note; the recording has no visible cut, only the paused span missing.
- **Source:** #55 R1, R2.

**REC-6 — Show Clicks**
- **Do:** Record the main display with Show Clicks on and click a few times; again with it off.
- **Expect:** rings at each click in the first file; none in the second.
- **Source:** #55.

**REC-7 — The panel shown from the background leaves your typing alone**
- **Do:** 1. Launch Frame Job from Terminal as in CLAUDE.md's "Verifying a build" (a scratch socket; the block prints its folder, `<dir>`) and open a project. 2. In a second Terminal tab, in the repository, run `sleep 5 && python3 -c 'import sys; sys.path.insert(0, "tools/proof"); from mcp import MCP; MCP("<dir>/agent.sock").call("perform_menu_item", path=["File", "New Recording…"])'`, then within the five seconds click into a TextEdit document. 3. When the panel appears, type a few words and press Return without clicking anything. 4. Click the panel's Close. 5. Click Frame Job's project window and press ⌥⌘N.
- **Expect:** in step 3 the New Recording panel is in front of TextEdit, TextEdit keeps the focus, the words and the Return land in TextEdit, and no countdown starts. In step 4 the panel closes without bringing Frame Job's windows forward. In step 5 the panel comes up key, with Record as its default button.
- **Source:** #137; spec §11 recording.md (the recorder panel takes key only from an active Frame Job).

**REC-8 — File ▸ Pause Recording, and the item's one width**
- **Do:** 1. Start a recording from the panel. 2. Open the File menu: Pause Recording, then open it again: Resume Recording. 3. Watch Frame Job's menu bar item through the pause and resume, and past the first minute. 4. Repeat 2–3 with the menu bar in the light look and in the dark. 5. Stop. 6. Launch Frame Job from Terminal as in REC-7 (a scratch socket in `<dir>`, the terminal holding Screen Recording); in a second Terminal tab, in the repository, run `python3 -c 'import sys; sys.path.insert(0, "tools/proof"); from mcp import MCP; MCP("<dir>/agent.sock").call("record_screen", seconds=20)'`; while it records, choose File ▸ Pause Recording, then File ▸ Resume Recording, watching the menu bar item. 7. Run the `record_screen` line again; choose File ▸ Pause Recording, then File ▸ Stop Recording, and watch the item until it goes away.
- **Expect:** the File item reads Pause Recording while recording and Resume Recording while paused, and is greyed out with no recording; each choice pauses or resumes as the item's own menu does (coral dot and running time, then the pause glyph and a frozen time). The item keeps one width throughout — the neighbouring menu bar items do not shift as the time ticks or the mark changes — and the title is never clipped, in either look. In step 6 the `record_screen` recording's item flips at each click, not up to a second later. In step 7 the item keeps the pause glyph and its frozen time until it disappears; the coral dot never returns.
- **Source:** #98 (a, b); #181 (item 4, step 6); #193 (item 1, step 7); spec §11 recording.md (File ▸ Pause Recording).

**REC-9 — The microphone meter during the countdown**
- **Do:** 1. File ▸ New Recording…, choose a real microphone (not a virtual device), press Record, and speak through the 3-2-1; stop the recording that follows from the menu bar item. 2. Press Record again for a second countdown and press Cancel during it. 3. Set the microphone to Off and press Record; Cancel.
- **Expect:** in step 1 the panel's bar moves with your voice from the first second of the countdown, and rests at the room's floor when you are quiet. In step 2 the bar is empty the moment you cancel and stays empty. In step 3 the bar stays empty through the countdown. Both looks.
- **Source:** #98 (c).

**REC-10 — A voice-over: your voice, the panel up, pause and resume across files**
- **Do:** 1. With no project open (the welcome window up), File ▸ New Recording…, choose Source ▸ Microphone Only and a real microphone (not a virtual device), Record Into New Project, and press Record. 2. Through the countdown and the recording, speak and watch the panel. 3. Press the panel's Pause, wait, then Resume and speak again. 4. Press Close; press the welcome window's New Recording… button. Press Close again, then ⌘Q. 5. Choose File ▸ Stop Recording (⌥⌘N). 6. In the project that opened, put the playhead a few seconds in; New Recording…, Microphone Only, Record Into that project, Record, speak, and stop from the menu bar item's Stop Recording. Then Edit ▸ Undo. 7. Choose Microphone Only with the microphone set to Off and press Record.
- **Expect:** with Microphone Only chosen, System Audio, Show Clicks and Size grey out and keep their values; Rate stays live; no Screen Recording prompt or System Settings pane appears. In step 2 the panel stays up the whole time: its rows are locked, the meter moves with your voice, the footnote shows the coral dot and the running time, and Record reads Stop with Pause beside it. In step 3 the button reads Resume while paused (the pause glyph and a frozen time in the footnote) and Pause again after. In step 4 Close takes the panel away and the recording carries on under the menu bar item; the welcome button shows the panel again, and ⌘Q shows it again instead of quitting. In step 5 the recording stops and opens as a new project: two `Voice-over <date> at <time>.m4a` files in `~/Movies/Frame Job Recordings/`, touching from 0 on its one track — your voice in both, the paused stretch missing. In step 6 the voice-over lands on a new back track named Microphone, starting at the playhead; Undo removes the clip and the track in one step and leaves the file. In step 7 nothing starts and the note asks you to choose a microphone. Both looks.
- **Source:** #99; spec §11 recording.md ("A voice-over is a recording with no picture").
**REC-11 — Include Frame Job windows**
- **Do:** 1. Open a project, File ▸ New Recording…, leave Include Frame Job windows off, and record the display showing the editor for 5 s. 2. Tick Include Frame Job windows and record again. 3. Choose Window… in Source with the box off, then with it on. 4. Quit, relaunch, and reopen the panel.
- **Expect:** the first file holds no Frame Job window. The second shows the editor from its first frame. The New Recording panel is in neither. The picker offers no Frame Job window with the box off; with it on, it offers the editor but not the panel. The box keeps its setting.
- **Source:** spec §11 recording.md (Include Frame Job windows).

## Assistant

Needs your own Anthropic API key (Setup 3).

**AS-1 — A real conversation**
- **Do:** Open a project with a few clips; View ▸ Assistant (⌃⌘A); ask for a marker, a split at the playhead, a caption's text change and a move inside a nest.
- **Expect:** the reply streams; each tool call shows one line; each edit is its own step in Edit ▸ Undo.
- **Source:** #159.

**AS-2 — Allow, Deny and Stop**
- **Do:** 1. Ask it to export; press Return; Deny. 2. Ask again; Allow. 3. Ask over an existing file. 4. Send something long and press Stop; ask for an export and press Stop while the question is up. 5. Ask for an export of a long project, Allow, and press Stop while it writes.
- **Expect:** the row names the file ("export writes …", or "export REPLACES …"); Return does not answer, only a click does; Deny writes nothing and the model carries on; Allow writes the file; Send reads Stop while working, and Stop with a question pending writes nothing; Stop during the allowed export leaves no file at the path and the transcript's tool line reads `failed: The export was cancelled.`.
- **Source:** #159; step 5 issue batch B15 (#149), spec §11 AI-16.

**AS-3 — How the tab reads**
- **Do:** Before saving a key, open the tab; then with a key, after a conversation, in light and dark.
- **Expect:** the no-key pointer to Settings; the context meter, Clear, the transcript's wrapping and the composer all read at a glance.
- **Source:** #159.

**AS-4 — What a turn cost**
- **Do:** 1. Quit Frame Job and delete `~/Library/Application Support/Frame Job/anthropic-prices.json`. 2. Relaunch; send two messages. 3. Clear; send one more. 4. Open `~/Library/Application Support/Frame Job/spend.jsonl`.
- **Expect:** each turn ends with `Cost: $… · Frame Job's estimate at LiteLLM prices (…)`, the three reading `(bundled table of …)`, then `(fetched <today>)`, then `(cached <today>)`; the ledger has one line per response, with no key and no message text; the month's total is near the Anthropic Console's for the same calls.
- **Source:** road map 13 P2; spec §11 P-4, P-5.

**AS-5 — What a conversation and the month cost**
- **Do:** With your real key, open Frame Job ▸ Settings… and keep it beside the window; View ▸ Assistant (⌃⌘A). 1. Read the tab's Spend row. 2. Send two messages. 3. Clear; send one more.
- **Expect:** the Spend row starts at "Nothing yet"; after the messages it equals the sum of those turns' `Cost:` lines ("$… · Frame Job's estimate"); Clear puts it back to "Nothing yet" and the next turn starts a new sum. Settings' month line ("<Month> <year> (UTC): $… over N responses.") grows with each response while it is open, without flickering to "Reading the spend ledger…", and is near the Anthropic Console's total for the same UTC days.
- **Source:** road map 13 P4; spec §11 P-4, P-7.

**AS-6 — A reply cut short**
- **Do:** With your real key, ask for something long (a paragraph about each clip) and press Stop while the reply streams. Open `~/Library/Application Support/Frame Job/spend.jsonl`, then the Anthropic Console's usage for the same minutes.
- **Expect:** the turn ends with `Cost: at least $… (a response was cut short) · Frame Job's estimate at LiteLLM prices (…)`; the ledger's last line carries `"partial": true`; the Console's charge for that request is at least that figure, and expect it above: the streamed output is not counted (spec §11 P-8).
- **Source:** issue batch B15 (#162); spec §11 P-8.

**AS-7 — Selecting the conversation, and a message of several lines**
- **Do:** In light, then dark, after a turn with a tool call: 1. Drag from inside a reply down into the next person line and a tool line; ⌘C; paste into TextEdit. 2. In the composer type a line, ⇧Return, another, ⌥Return, a third, and keep adding lines past five. 3. Press Return. 4. With an input method that composes (Japanese, say), start a word so it is underlined and press Return. 5. Send something long and, while it is working, type in the composer and press Return.
- **Expect:** 1. the drag selects across entries, and the paste is plain text (no fonts or colours), each entry starting on its own line. 2. each modified Return starts a new line; the field grows a line at a time up to five, then holds its height and scrolls. 3. the whole message is sent, lines intact, and the field is one line again. 4. Return commits the word and sends nothing. 5. Return beeps and the text stays.
- **Source:** issue batch B18 (#153, #154); spec §11 AI-17 and K-2.

**AS-8 — The tab at its narrowest**
- **Do:** With a real key, after a turn: 1. Drag the inspector to its narrowest and back, watching the Context figures, and hover them. 2. In a short conversation, click below the last entry, then drag from there up into it. 3. Type a message that wraps to two lines at the narrowest width, and drag the inspector slowly wider and narrower. 4. Empty the composer at the narrowest width.
- **Expect:** 1. The figures are full when there is room, and shorter ("N / L · P%", then "P%") as the inspector narrows. They are never cut off with "…", and the tooltip reads the full figure. 2. The click clears the selection, and the drag selects up from the end. 3. The field follows the width, two lines while the message wraps and one line when it does not, with no jump or flicker. 4. The placeholder sits on one line.
- **Source:** #182 (items 1, 2 and 4; step 3 watches item 3, an accepted limit since B47, where a refit from `AssistantView.layout()` lagged a pass as B37's had), issue batches B37 and B47.

**AS-9 — A question while another tab shows**
- **Do:** With a real key, light then dark: View ▸ Assistant; ask for an export; while the question is up click Clip, Media, Document, then Assistant and Deny; repeat and press Stop; repeat and Allow; with a question up drag the inspector to its narrowest.
- **Expect:** a small accent dot right of "Assistant" in the strip while the question waits, on every tab, never touching the word at the narrowest width; a click on the tab only shows it; the dot goes at Deny, Stop and Allow; Return in the composer answers nothing.
- **Source:** issue batch B47 (#152); spec §11 AI-19.

## Agent connections

Whether an MCP client refetches its tool list when a stdio server says it
changed (road map 14's MC1, question 3). The fixture is the spike's stub
server, which has two tools only after it sends
`notifications/tools/list_changed`. Run
`python3 tools/proof/mc1_spike/mc1_spike.py --only q3` once first: it writes
`tools/proof/work/mc1_spike/q3/ac-mcp.json`, a scratch configuration naming
the stub with `--mode during-call`, whose log is
`tools/proof/work/mc1_spike/q3/ac-stub.jsonl`. Each run is your own spend
on your own account, never the spike's.

**AC-1 — Claude Code refetches after `list_changed`**
- **Do:** 1. Delete `ac-stub.jsonl` if it is there. 2. In a terminal, `claude --mcp-config tools/proof/work/mc1_spike/q3/ac-mcp.json --strict-mcp-config`. 3. Ask it to call the `probe_wait` tool of the `mc1-stub` server, and when that answers, to call `probe_new`. 4. Quit, and read `ac-stub.jsonl`.
- **Expect:** among the log's lines (it also holds `notifications/initialized` and any other calls the client makes), in this order: `initialize`, `tools/list`, the `tools/call` of `probe_wait`, the `"dir": "out"` notification, then a second `tools/list`; then a `tools/call` of `probe_new`. The log holds only what the stub received and the notifications it sent, never its answers, so that `probe_new` answered `probe_new answered` is seen in the client.
- **Answer:** did a second `tools/list` follow the notification, and was `probe_new` callable in the same session?
- **Source:** road map 14 MC1 (q3, rows T1–T3 and D1).

**AC-2 — Claude Desktop refetches after `list_changed`**
- **Do:** 1. Delete `ac-stub.jsonl` if it is there. 2. Copy the `mc1-stub` entry of `ac-mcp.json` into the `mcpServers` of Claude Desktop's `~/Library/Application Support/Claude/claude_desktop_config.json` and restart Claude Desktop. 3. In a new chat, ask it to call `probe_wait`, then `probe_new`. 4. Read `ac-stub.jsonl`. 5. Remove the `mc1-stub` entry and restart Claude Desktop.
- **Expect:** as AC-1: a second `tools/list` after the notification, and `probe_new` called and answered.
- **Answer:** did a second `tools/list` follow the notification, and was `probe_new` callable in the same chat?
- **Source:** road map 14 MC1 (q3, rows T1–T3 and D1).

**AC-3 — Claude Code reaches Frame Job through `framejob-mcp`**
- **Do:** 1. `make app`, then `RC_PROOF_APP=release python3 tools/proof/mcp_proxy_proof.py` once: it writes `tools/proof/work/mcp-proxy/ac-mcp.json`, a scratch configuration whose `framejob` server is the tree's Release `Contents/Helpers/framejob-mcp`, with no env. 2. Quit Frame Job (every copy). 3. In a terminal, `claude --mcp-config tools/proof/work/mcp-proxy/ac-mcp.json --strict-mcp-config`. 4. Ask it to list the `framejob` server's tools (`/mcp`). 5. Ask it to call `get_project`. 6. Quit Claude Code, and quit the Frame Job it opened.
- **Expect:** step 4 lists Frame Job's tools with no Frame Job launched (the Dock shows none). Step 5 opens Frame Job in the background — the terminal keeps focus — and the call answers in Frame Job's own words (with no project open, "No project is open…"). Per MC1's q3, a running Frame Job newer than the bundle the proxy came from shows its own tools after the first call; whether Claude Code refetches on `list_changed` is AC-1's question.
- **Answer:** were the tools listed before Frame Job ran, and did the first call open Frame Job without taking focus from the terminal and answer?
- **Source:** road map 14 MC3 (`mcp_proxy_proof.py` X1, X2; spec §11 MC-3, MC-4).

**AC-4 — Copy MCP Command's line registers Frame Job with Claude Code**
- **Do:** 1. Open the Frame Job you use (an installed copy, or the tree's Release build), choose Frame Job ▸ Settings…, and under MCP press Copy MCP Command. 2. Paste the line into Terminal and run it. 3. Run `claude mcp list`.
- **Expect:** step 2 answers that `framejob` was added; step 3 lists `framejob` with the pasted helper path and shows it connected.
- **Answer:** did the pasted line run as it stood, and does `claude mcp list` show `framejob` connected?
- **Source:** `agent_socket_proof.py` K13; `settings_layout_probe.py` L10; spec §11 MC-7.

**AC-5 — A person's own import still asks while an agent's call runs**
- **Do:** 1. Launch Frame Job from Terminal as in CLAUDE.md's "Verifying a build", adding `-RCFFmpegImport ask` to its arguments (ffmpeg installed), and open a project with a few seconds of media on the timeline. 2. In a second Terminal tab, in the repository, start an export over MCP: `python3 -c 'import sys; sys.path.insert(0, "tools/proof"); from mcp import MCP; print(MCP("<dir>/agent.sock").call("export", preset="h264", path="/tmp/ac5.mp4"))'`. 3. While it runs, drag onto the timeline from the Finder an `.mkv` whose video the built-in copy cannot carry, so it goes on to the ffmpeg question (since #216-R an H.264, VP9 or AV1 Matroska opens with no question; make one with `ffmpeg -f lavfi -i testsrc=duration=2 -c:v mpeg4 /tmp/ac5.mkv`). 4. Cancel the question.
- **Expect:** the conversion question ("Frame Job cannot open …", Repackage or Convert) appears for the dragged file while the export is still being written; the export finishes either way.
- **Answer:** did the question appear during the agent's export?
- **Source:** road map 14 MC4 (spec §11 MC-5: a click still asks; `agent_socket_proof.py` K12 holds the tool call's half).

## The name

**NAME-1 — Finder opens a `.framejob` with Frame Job; the Debug app stays the Alternate**
- **Do:** 1. `make app` and `make app-debug`. 2. Rename a saved project's package to end in `.framejob`. 3. Double-click it in the Finder. 4. Right-click it and open the Open With submenu.
- **Expect:** step 3 opens it in Frame Job (the Release build), not Frame Job Debug; step 4 lists Frame Job as the default and Frame Job Debug as another choice.
- **Answer:** did the double-click open Frame Job, and does Open With list Frame Job Debug as an alternate?
- **Source:** spec §11 NM-3, V-5.

**NAME-2 — The Dock icon, the About panel and the document icon carry the Frame Job mark**
- **Do:** 1. `make app`. 2. Open the Release app from the Finder and look at the Dock icon. 3. Choose Frame Job ▸ About Frame Job, in Light and then in Dark. 4. Look at a saved `.framejob` package in the Finder's icon view at a large size, and in Get Info.
- **Expect:** the Dock shows the cream rounded tile with four green corner brackets, a yellow frame and a coral playhead; About shows the same mark with no tile, sharp-edged, in both appearances; the package's document icon carries the new icon. An old two-block icon after a rebuild is the icon cache: log out and back in, then look again before answering.
- **Answer:** do the Dock, the About panel (Light and Dark) and the package's document icon all show the new viewfinder mark?
- **Source:** spec §11 NM-11, rename R2.

## Published build

After a push to `publish` has made a release (README, "Publishing a
release"). These use the DOWNLOADED app, not the tree's build, and one
appearance is enough.

**REL-1 — The DMG installs and opens on another Mac**
- **Do:** On a Mac that has never run Frame Job (or in a fresh user account), on macOS 26 and Apple silicon: 1. Download `FrameJob.dmg` from the release with a browser, so the file is quarantined. 2. Open it and drag Frame Job to Applications. 3. Double-click Frame Job in Applications. 4. Choose Frame Job ▸ About Frame Job.
- **Expect:** the one "downloaded from the Internet" question, naming the developer, and no "cannot be opened", "damaged" or "unidentified developer" alert; the Welcome window; About shows the release's version with the run number in parentheses (e.g. 0.2.7 (7)).
- **Source:** spec §11 PUB-1, PUB-5.

**REL-2 — The downloaded build's microphone, recorder, assistant and MCP helper work**
- **Do:** In the downloaded app: 1. File ▸ New Recording… with a microphone chosen; answer the Microphone and Screen Recording prompts; record a few seconds while speaking; stop. 2. Open the Assistant tab with your own Anthropic key set and send one short message. 3. Frame Job ▸ Settings… ▸ MCP ▸ Copy MCP Command; paste the line into Terminal, run it, then `claude mcp list`.
- **Expect:** both prompts name Frame Job; your voice is in the recording's microphone file; the assistant answers (the helper did not die at launch); `claude mcp list` shows `framejob` connected, with its path inside `/Applications/Frame Job.app`.
- **Source:** spec §11 PUB-4 (`published_check.py` holds that the entitlements are there; this is whether they do their job under a Developer ID signature).

**REL-3 — Permissions survive an update**
- **Do:** With REL-2's grants given, download the NEXT release's DMG, replace the app in Applications, open it, and start a recording with the same microphone.
- **Expect:** no Microphone or Screen Recording prompt, and the recording starts.
- **Source:** spec §11 PUB-1 (a Developer ID signature is stable across builds; an ad-hoc one is not).

## Host-state proof runs

Scripts that need a state no agent session has. Run from a terminal on an
unlocked Mac; paste each score into the issue in the Source.

**HS-1 — The chrome dispatch rows need an unlocked console**
- **Do:** `python3 tools/proof/phase8_chrome.py` with the screen unlocked.
- **Expect:** no skipped rows; section 4's six dispatch rows scored (the run is 150/150 unlocked).
- **Source:** #57.

**HS-2 — The recorder's microphone rows with a wired or built-in microphone**
- **Do:** 1. Set the default input to the built-in or a wired microphone (not Bluetooth), in System Settings ▸ Sound. 2. Give Terminal Screen Recording and Microphone permission. 3. `make app`, then `python3 tools/proof/proof_app.py launch --app release` (it prints its folder, `<dir>`); run `python3 tools/proof/recording_proof.py <dir>/agent.sock`.
- **Expect:** every microphone row passes (only the named Bluetooth-output skips).
- **Answer:** should the proof skip its microphone rows by name on a Bluetooth input?
- **Source:** #57.

**HS-3 — Mixed audio formats on the built-in speakers**
- **Do:** Set the output to the built-in speakers; `python3 tools/proof/mixed_audio_probe.py`.
- **Expect:** section 4 passes (so far only measured on Bluetooth).
- **Source:** #51 (#34).

**HS-4 — The screen catalog on a Mac whose system look is Light**
- **Do:** 1. Set System Settings ▸ Appearance to Light. 2. `python3 tools/proof/screens.py`. 3. Compare its light PNGs with the latest catalog run from a Dark host (under `tools/proof/work/screens/`, captured with `-RCDevAppearance light`), e.g. with `python3 -c` over two PNGs or any image-diff tool.
- **Expect:** the run passes. On the Dark host, `-RCDevAppearance light` and `-NSRequiresAquaSystemAppearance YES` differed only in the timeline's alternate lanes (grey 140 against 139) and its vertical scroller track (233 against 255). Record which of the two a real Light host matches. Explain any other difference in the screen's prose, or file it.
- **Source:** #139 (road map 11's V3).

**HS-5 — The screen catalog on a second display**
- **Do:** Run `python3 tools/proof/screens.py` on a display at a different scale from the usual one, e.g. a Mac's built-in Retina screen (scale 2); every run so far was at scale 1 on one external display.
- **Expect:** the run passes. Screens and prose that depend on the host are noted in the screen's prose, or filed.
- **Source:** #139 (road map 11's V3).

**HS-6 — AV1 on an M3 or later Mac**
- **Do:** On an M3 or later Mac: 1. `python3 tools/proof/formats_probe.py`. 2. `python3 tools/proof/codec_import_proof.py` (it launches its own instance on a scratch socket). 3. Drop an AV1 MP4 into a project and play it.
- **Expect:** the formats probe prints `hw_av1 True` and the AV1 rows `opens` (`mp4_av1.mp4`; `mkv_av1.mkv` stays refused); the codec proof's R5 takes its M3 branch and passes; the AV1 clip plays and scrubs like any other. On an M1/M2 the same file is refused with "… is AV1 video, which needs an M3 or later Mac."
- **Source:** #216 (issue batch B72; measured only on an M2 so far).

**HS-7 — `make test` in Low Power Mode**
- **Do:** Next time the Mac is in Low Power Mode anyway (`pmset -g | grep powermode` reads 1), run `cd mcp-proxy && cargo test --release --test stdio`, then `make test`.
- **Expect:** both pass. If a test fails with `no answer within …`, the line ends with the host's power state and load; paste it into a new issue. Issue batch B93 changed the proxy tests to wait up to 60 s for the proxy to start, then time each request alone. The failure did not reproduce on AC power, so the fix is untested on a throttled host.
- **Source:** #244.
