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
   `open build/Build/Products/Release/Reelcut.app`. **Not from a terminal**:
   a terminal-launched app's permissions (Screen Recording, Microphone)
   belong to the terminal, not to Reelcut. Only REC-3, REC-7, REC-8's
   step 6 and HS-2 launch from a terminal on purpose.
3. Have to hand:
   - **Real footage**: a 1080p movie with sound, a long recording (twenty
     minutes or more), an AAC file and a WAV file.
   - **Synthetic test media**, where a check names it: make it once with the
     `ffmpeg` lines under "Make the test media once" in
     `tools/proof/README.md` (into `tools/proof/media/`).
   - **Graphics projects** (GR): `python3 tools/proof/graphics_playback_samples.py`
     builds `Playback-1080p`, `Playback-4K` and `Error-card` into
     `tools/proof/work/playback-check/`. Rebuild them on a fresh checkout.
   - **Keys**: your own AssemblyAI key for Cloud captions (Reelcut ▸
     Settings… ▸ Transcription) and your own Anthropic API key for the
     Assistant (Reelcut ▸ Settings… ▸ Assistant). No script ever uses a real
     key.
4. **The compositor's timing log** (PB-2, PB-3):
   `defaults write com.kgalligan.Reelcut ReelcutCompositorTiming -bool YES`,
   relaunch, and read it in Console.app filtered on `[reelcut] compositor`
   (average and worst milliseconds per 120 frames). Turn it off afterwards
   with `defaults delete com.kgalligan.Reelcut ReelcutCompositorTiming`.

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
- **Do:** 1. Save a project holding the long recording; quit; reopen it. 2. Move one of a project's media files to another folder; reopen the project; relink it in the Relink… sheet it offers. 3. In the Media tab, Relink… a 10 s media to `AV.mov`. 4. Move two of a project's video files away and reopen it; in the Missing media sheet Locate… `toneA.m4a` for one and a video file for the other; press Relink. 5. In the Media tab, Relink… a media with sound (a clip on it showing a waveform) to `A.mov`.
- **Expect:** the reopen is quick, with no long re-analysis. After relinking, the clip's filmstrip redraws with the file's frames. After step 3, the row reads 5 s, and the whole-file clip ends at 5 s. After step 4, the video file relinks, and then an alert sheet shows the refusal in the core's own words ("… is video media and … is audio: relink it to a file of the same kind …"); with two refused files, a second alert follows the first once it is dismissed. After step 5, the clip's waveform goes at once.
- **Source:** #47; step 3, #63; steps 4–5, #180.

**PB-7 — Waveforms have no gaps**
- **Do:** 1. Import an AAC file, a WAV file and a recording made by Reelcut. 2. Look at each clip's waveform at M and L track height. 3. On the long recording, open Clip ▸ Remove Silences… while it is still being analysed.
- **Expect:** no gap or flat tail where there is sound. While decoding, the sheet names the file ("The waveform is still being analysed for …") until the decode finishes.
- **Source:** #47 (#23).

**PB-8 — A project whose media moved opens and offers Relink**
- **Do:** Use the installed or current build, and note which `Reelcut.app` actually opened the file (its path in the Dock menu or Activity Monitor). 1. Save a project with two clips; quit. Move the `.reelcut` and its media together into a new folder, then open it from the Finder with right-click ▸ Open With ▸ Reelcut. 2. Move a media file while the project is OPEN in Reelcut, wait for an autosave, quit, and reopen it. 3. Move a media file to another volume (an external drive or a disk image), unmount it, and reopen the project.
- **Expect:** each time, the project opens. Media that is still findable plays. Media that is gone shows slates, with the Missing media sheet offering Locate… and Relink. Never an open failure, a hang or a crash.
- **Source:** #131 (the owner's report of 2026-09-26, not reproduced by the agents). On a failure, add to #131 which app opened the file and exactly what happened: an alert and its text, a hang, a crash, or no window.

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
- **Do:** 1. Clip ▸ Label ▸ Blue, then None. 2. Click a track's headphones toggle at S, M and L height; watch Track ▸ Solo. 3. Copy a clip, select another, Edit ▸ Paste Attributes (⌥⌘V); try it between a video and an audio-only clip.
- **Expect:** a blue dot on the strip and header, cleared by None; the headphones match eye, speaker and lock at every height and Solo's checkmark follows; paste restyles, and beeps when the clips share no group.
- **Source:** #48.

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

## Chrome and looks

**CH-1 — The zoom slider and square controls**
- **Do:** 1. Drag the timeline's zoom knob. 2. Look at the Export button, S/M/L, the Snap box and fields, then open a sheet (Export…) with its rounded buttons.
- **Expect:** a grey track, a white (dark) or black (light) block knob beside the accent fill; the knob drags smoothly. The square controls sit comfortably beside the sheets' rounded buttons.
- **Source:** #50 (spec §11 SH-1, SH-2).

**CH-2 — States and hovers no proof renders**
- **Do:** 1. Hover and press ghost (borderless) buttons. 2. Find a disabled slider. 3. Hover every control with a tooltip. 4. Switch Timeline Track Height S / M / L.
- **Expect:** a square hover fill and a press state; the disabled slider looks disabled; every tooltip reads as a sentence and is correct; S/M/L relayouts cleanly.
- **Source:** #50; #48.

**CH-3 — The Speed sheet's hint**
- **Do:** Select clips with a gap and an overlap between them; Clip ▸ Speed…; set a speed that one clip refuses. Then set ×0.5 on a clip with a neighbour just after it.
- **Expect:** the hint (gaps, a clip that gains a transition — named below — and a refused clip left unchanged) wraps readably; a line under the lengths names the neighbour and its transition's length, and the sheet grows to show every line unclipped.
- **Source:** #48, #109.

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
- **Do:** 1. Export with a non-default format, size, quality and loudness; quit and relaunch; open Export… again. 2. Save a user preset, change settings, pick the preset. 3. Start two exports; Window ▸ Export Queue. 4. Save Frame… (⌥⌘E) at a paused frame. 5. Open an exported movie in QuickTime Player.
- **Expect:** the sheet reopens on the last choices and the preset restores them; the queue is listed once, with per-row progress and Cancel; the saved frame matches the preview; the movie plays in QuickTime with sound.
- **Source:** #51; spec §10 step 10.

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
- **Do:** 1. Open it; pick a style; relaunch; reopen. 2. With two caption tracks, generate with Replace; ⌘Z once. 3. Look at the style preview at 9:16 and 16:9.
- **Expect:** the Style row and card fit; the popup opens on the last style; Replace swaps both tracks and one ⌘Z brings them back; the preview reads as "this style, second word lit".
- **Source:** #52.

## Cloud captions

Needs your own AssemblyAI key (Setup 3).

**CC-1 — Settings and Verify**
- **Do:** 1. Reelcut ▸ Settings… (⌘, from a document window). 2. Paste a good key, Verify; then a bad one, Verify. 3. Save; Remove. 4. If your account has the EU region, choose `eu` and generate captions.
- **Expect:** "Key accepted" for the good key, a clear sentence for the bad one; the button row is balanced and the paragraph reads; ⌘, never types a `,` nudge or into a rename; the key lands in a file in `~/Library/Application Support/Reelcut/`, and Remove feels final (the file goes). The EU region works.
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
- **Do:** 1. Record a narrated screencast in Reelcut; note by ear where the real pauses are. 2. Clip ▸ Remove Silences…, Voice mode, default padding (0.1 s). 3. Play every cut.
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

Uses the three `tools/proof/work/playback-check/` projects (Setup 3).

**GR-1 — Graphics play, watched**
- **Do:** 1. Open `Playback-1080p` at Preview Quality Full; play. 2. In each of the three projects: play, scrub, and loop an in/out range.
- **Expect:** `lower-third` and `kinetic-type` play smoothly; with no video beneath, the preview shows, Play runs, and scrub and loop look right.
- **Source:** #56.

**GR-2 — Memory at 4K, and a slower machine**
- **Do:** 1. Play `Playback-4K` with Activity Monitor open on Reelcut's memory. 2. If one is available, play it on a slower Mac, or a heavier graphic.
- **Expect / Answer:** memory stays steady (note the figure); no stutter. A stutter reopens graphics performance work.
- **Source:** #56.

**GR-3 — The error card**
- **Do:** Open `Error-card` and play past 2 s.
- **Expect:** a dark red card with the message in white in the live preview, never the last good frame.
- **Source:** #56.

**GR-4 — The Title and marker name fields**
- **Do:** 1. Insert ▸ Graphic ▸ Lower Third, select it, open Clip ▸ Graphic. 2. Press M, then open the Document tab.
- **Expect:** the Title field is the height of the number fields, and the marker's name field is the height of the Rate row's controls, in both appearances. Both are filled and bordered like the number fields, with their text centred vertically, in both appearances; clicking into either moves no text.
- **Source:** #106, #171.

## Screen recording

Launch Reelcut from the Finder or Dock unless the check says otherwise.
To take a permission away again: System Settings ▸ Privacy & Security, or
`tccutil reset ScreenCapture com.kgalligan.Reelcut` (and `Microphone`).

**REC-1 — Record without Screen Recording permission opens Settings**
- **Do:** 1. With Reelcut's Screen Recording permission off, File ▸ New Recording…, press Record. 2. Answer or dismiss the system prompt. 3. Press Record again.
- **Expect:** if Reelcut has never asked on this Mac, the first press shows the system prompt, IN FRONT of the New Recording panel (not hidden behind it). Every later press opens System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, also in front of the panel, with Reelcut's row visible, and the panel's note says Settings is open at that pane. (Once Reelcut has asked, a `tccutil reset` does not bring the prompt back: the first press opens the pane, whose + adds Reelcut. That is accepted.)
- **Source:** spec §11 recording.md (Record asks once, then opens Settings).

**REC-2 — Microphone permission**
- **Do:** 1. Reset Reelcut's Microphone permission; choose a microphone in the panel; Record. 2. Deny it in Settings; Record again.
- **Expect:** first, the system microphone prompt naming Reelcut, in front of the panel; once denied, Record opens System Settings ▸ Privacy & Security ▸ Microphone, in front of the panel.
- **Source:** spec §11 recording.md; #55 R1.

**REC-3 — Launched from a terminal**
- **Do:** Run Reelcut from Terminal (as in CLAUDE.md's "Verifying a build") with the terminal lacking Screen Recording; press Record twice.
- **Expect:** each press shows the system prompt (for the terminal); System Settings never opens.
- **Source:** spec §11 recording.md.

**REC-4 — Picking and recording a window or display**
- **Do:** 1. Launch Reelcut and open New Recording… straight away. 2. Choose window mode; pick a window in the system picker. 3. Record a display with Reelcut playing a timeline. 4. While another app is frontmost, change the panel's popups and switches.
- **Expect:** no freeze on first opening; the picker presents from the panel and the choice arrives; the countdown looks right; the panel is absent from the file from the start and Reelcut's playback does not appear in it; the panel's controls work with another app in front.
- **Source:** #55 R1.

**REC-5 — The menu bar indicator, pause and stop**
- **Do:** 1. During a recording, check the macOS recording indicator and Reelcut's own menu bar item. 2. From the item's menu: Pause, then Resume, then Stop. 3. Record again, Pause, press ⌘Q. 4. Stop from the system indicator. 5. Play the recording across the pause.
- **Expect:** the system indicator names Reelcut and stays up through a pause; paused shows a coral dot, a pause glyph and a frozen time; ⌘Q while paused opens the item's menu instead of quitting; Stop from either place lands the file; the panel returns only with a note; the recording has no visible cut, only the paused span missing.
- **Source:** #55 R1, R2.

**REC-6 — Show Clicks**
- **Do:** Record the main display with Show Clicks on and click a few times; again with it off.
- **Expect:** rings at each click in the first file; none in the second.
- **Source:** #55.

**REC-7 — The panel shown from the background leaves your typing alone**
- **Do:** 1. Launch Reelcut from Terminal as in CLAUDE.md's "Verifying a build" (port 4817) and open a project. 2. In a second Terminal tab, in the repository, run `sleep 5 && python3 -c 'import sys; sys.path.insert(0, "tools/proof"); from mcp import MCP; MCP(4817).call("perform_menu_item", path=["File", "New Recording…"])'`, then within the five seconds click into a TextEdit document. 3. When the panel appears, type a few words and press Return without clicking anything. 4. Click the panel's Close. 5. Click Reelcut's project window and press ⌥⌘N.
- **Expect:** in step 3 the New Recording panel is in front of TextEdit, TextEdit keeps the focus, the words and the Return land in TextEdit, and no countdown starts. In step 4 the panel closes without bringing Reelcut's windows forward. In step 5 the panel comes up key, with Record as its default button.
- **Source:** #137; spec §11 recording.md (the recorder panel takes key only from an active Reelcut).

**REC-8 — File ▸ Pause Recording, and the item's one width**
- **Do:** 1. Start a recording from the panel. 2. Open the File menu: Pause Recording, then open it again: Resume Recording. 3. Watch Reelcut's menu bar item through the pause and resume, and past the first minute. 4. Repeat 2–3 with the menu bar in the light look and in the dark. 5. Stop. 6. Launch Reelcut from Terminal as in REC-7 (port 4817, the terminal holding Screen Recording); in a second Terminal tab, in the repository, run `python3 -c 'import sys; sys.path.insert(0, "tools/proof"); from mcp import MCP; MCP(4817).call("record_screen", seconds=20)'`; while it records, choose File ▸ Pause Recording, then File ▸ Resume Recording, watching the menu bar item. 7. Run the `record_screen` line again; choose File ▸ Pause Recording, then File ▸ Stop Recording, and watch the item until it goes away.
- **Expect:** the File item reads Pause Recording while recording and Resume Recording while paused, and is greyed out with no recording; each choice pauses or resumes as the item's own menu does (coral dot and running time, then the pause glyph and a frozen time). The item keeps one width throughout — the neighbouring menu bar items do not shift as the time ticks or the mark changes — and the title is never clipped, in either look. In step 6 the `record_screen` recording's item flips at each click, not up to a second later. In step 7 the item keeps the pause glyph and its frozen time until it disappears; the coral dot never returns.
- **Source:** #98 (a, b); #181 (item 4, step 6); #193 (item 1, step 7); spec §11 recording.md (File ▸ Pause Recording).

**REC-9 — The microphone meter during the countdown**
- **Do:** 1. File ▸ New Recording…, choose a real microphone (not a virtual device), press Record, and speak through the 3-2-1; stop the recording that follows from the menu bar item. 2. Press Record again for a second countdown and press Cancel during it. 3. Set the microphone to Off and press Record; Cancel.
- **Expect:** in step 1 the panel's bar moves with your voice from the first second of the countdown, and rests at the room's floor when you are quiet. In step 2 the bar is empty the moment you cancel and stays empty. In step 3 the bar stays empty through the countdown. Both looks.
- **Source:** #98 (c).

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
- **Do:** 1. Quit Reelcut and delete `~/Library/Application Support/Reelcut/anthropic-prices.json`. 2. Relaunch; send two messages. 3. Clear; send one more. 4. Open `~/Library/Application Support/Reelcut/spend.jsonl`.
- **Expect:** each turn ends with `Cost: $… · Reelcut's estimate at LiteLLM prices (…)`, the three reading `(bundled table of …)`, then `(fetched <today>)`, then `(cached <today>)`; the ledger has one line per response, with no key and no message text; the month's total is near the Anthropic Console's for the same calls.
- **Source:** road map 13 P2; spec §11 P-4, P-5.

**AS-5 — What a conversation and the month cost**
- **Do:** With your real key, open Reelcut ▸ Settings… and keep it beside the window; View ▸ Assistant (⌃⌘A). 1. Read the tab's Spend row. 2. Send two messages. 3. Clear; send one more.
- **Expect:** the Spend row starts at "Nothing yet"; after the messages it equals the sum of those turns' `Cost:` lines ("$… · Reelcut's estimate"); Clear puts it back to "Nothing yet" and the next turn starts a new sum. Settings' month line ("<Month> <year> (UTC): $… over N responses.") grows with each response while it is open, without flickering to "Reading the spend ledger…", and is near the Anthropic Console's total for the same UTC days.
- **Source:** road map 13 P4; spec §11 P-4, P-7.

**AS-6 — A reply cut short**
- **Do:** With your real key, ask for something long (a paragraph about each clip) and press Stop while the reply streams. Open `~/Library/Application Support/Reelcut/spend.jsonl`, then the Anthropic Console's usage for the same minutes.
- **Expect:** the turn ends with `Cost: at least $… (a response was cut short) · Reelcut's estimate at LiteLLM prices (…)`; the ledger's last line carries `"partial": true`; the Console's charge for that request is at least that figure, and expect it above: the streamed output is not counted (spec §11 P-8).
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

## Host-state proof runs

Scripts that need a state no agent session has. Run from a terminal on an
unlocked Mac; paste each score into the issue in the Source.

**HS-1 — The chrome dispatch rows need an unlocked console**
- **Do:** `python3 tools/proof/phase8_chrome.py` with the screen unlocked.
- **Expect:** no skipped rows; section 4's six dispatch rows scored (the run is 150/150 unlocked).
- **Source:** #57.

**HS-2 — The recorder's microphone rows with a wired or built-in microphone**
- **Do:** 1. Set the default input to the built-in or a wired microphone (not Bluetooth), in System Settings ▸ Sound. 2. Give Terminal Screen Recording and Microphone permission. 3. Launch an instance on port 4817 as in CLAUDE.md's "Verifying a build"; run `python3 tools/proof/recording_proof.py 4817`.
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
