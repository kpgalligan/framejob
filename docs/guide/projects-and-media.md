# Projects and media

A Frame Job project is a `.framejob` package: one file in the Finder that holds the edit, the caches that make it quick to reopen, and, when you ask for it, copies of the footage itself. This page covers starting a project (most often by opening a movie), saving it, what is inside the package, the canvas settings on the Document tab, bringing files in, the Media tab, and what to do when files go missing.

## Starting a project

### Open a movie

The quickest way in is to open the footage itself. **File ▸ Open…** (⌘O) on a movie, **Open With ▸ Frame Job** in the Finder (or a double-click, once Frame Job is that file type's default app), a drop on the Dock icon, or a drop onto a Frame Job window all do the same thing:

- an **untitled** project is created, sized and rated to the file;
- the file becomes the first media item and the first clip on Track 1, starting at 0;
- the window is titled after the movie (`Interview.mov` opens as "Interview").

The canvas takes the movie's *display* size, so a portrait phone clip opens as 1080 × 1920, not sideways. Its frame rate is read exactly: a 29.97 or 23.976 file stays 29.97 or 23.976, not 30 or 24.

Opening a sound file works the same way, but a sound file has no picture: its project is 1920 × 1080 at 30 fps. Opening a picture (PNG, JPEG, HEIC) makes a project at the picture's pixel size, 30 fps, with the picture as a 5-second clip.

The new project lives only in memory until you save it, so it opens already marked as changed. Closing it asks whether to save. The first **Save** offers to put the package next to the source file, under the source's name.

Opening a `.framejob` package opens that project (a double-click on a package always opens it in Frame Job). If it is already open, its window comes forward.

Dropping several files at once on a window, the Welcome window or the Dock icon opens each one as its own untitled project. Only `.framejob` packages and the movie, sound and picture types File ▸ Open… lists are taken; anything else dropped there is ignored. To add files to the project you already have open, drop them on the [Media tab](#the-media-tab) instead.

*Agents:* `open_project` (takes a `path` to a package, movie, sound file or picture; answers `already_open: true` when that file is already open).

### New Project

**File ▸ New Project** (⌘N) opens a blank 1920 × 1080, 30 fps project with no dialog, in a window titled "Untitled Project". Change the size and rate afterwards on the Document tab (see [The Document tab](#the-document-tab-canvas-settings)).

*Agents:* `new_project` (an optional `path` saves it there straight away; without one it stays an untitled draft).

### The Welcome window

When Frame Job starts with nothing to open, and when you click its Dock icon with no window open, it shows the Welcome window. It holds:

| Control | What it does |
|---|---|
| **Open Video…** | The same open panel as File ▸ Open…. |
| **New Project** | A blank 1920 × 1080, 30 fps project. |
| **New Recording…** | Opens the screen recorder panel; see [Screen recording](screen-recording.md). |
| **Recent** | Up to five recently opened projects, by name; hover for the full path. Hidden when there are none. |

The line at the foot lists the file types it opens: MOV · MP4 · M4V · M4A · MP3 · WAV · AIFF · PNG · JPEG · HEIC. You can also drop a file or a package anywhere on the Welcome window to open it. The window closes itself as soon as a project window comes up.

## Saving, reverting and closing

| Command | Shortcut | What it does |
|---|---|---|
| **File ▸ New Project** | ⌘N | A blank 1920 × 1080, 30 fps project. |
| **File ▸ Open…** | ⌘O | Opens a package, or builds an untitled project around a movie, sound file or picture. |
| **File ▸ Open Recent ▸** | | Recently opened projects; **Clear Menu** empties the list. |
| **File ▸ Close** | ⌘W | Closes the window. A project that has been saved writes its changes and closes without asking; an untitled project with changes (an opened movie always counts) asks whether to save first. |
| **File ▸ Save** | ⌘S | Writes the package. An untitled project asks where. |
| **File ▸ Save As…** | ⇧⌘S | Writes the project to a new package. |
| **File ▸ Revert To ▸** | | Goes back to the last saved version, or browses earlier versions of the package. |

Once a project has been saved it autosaves in place, the macOS way: changes are written to the package as you work, and the package is written beside the old one and swapped in, so a crash part-way through a save cannot leave half a package behind. Because of this, macOS adds its standard document commands to the File menu: **Duplicate**, **Rename…**, **Move To…**, **Revert To ▸** (in place of Revert to Saved) and **Share**, and the same Rename and Move To controls appear when you click the window's title. A project only ever saves as a `.framejob` package. Making a movie or a still is a separate step; see [Export](export.md).

*Agents:* `save_project` (a `path` is required the first time and always means Save As), `close_project` (refused when `get_project` reports `unsaved_changes` unless `discard: true`, and refused while a sheet is open), `get_project` (the whole project as JSON plus the playhead, selection, in/out range, `unsaved_changes` and `missing_media`). `new_project` adds `.framejob` to a `path` that lacks it. `new_project` and `save_project` refuse a path another open project holds (close that one first) or one a window is still opening.

## What a `.framejob` package holds

A package is a folder that the Finder shows as one file:

| Inside | What it is |
|---|---|
| `project.json` | The edit itself: canvas, media list, tracks, clips, markers. The only thing a package needs in order to open. |
| `cache/` | Things Frame Job can rebuild: filmstrip thumbnails, waveforms, the voice-detection and sync analyses, transcripts, reversed clips and speed-ramp audio. A package with a missing or damaged `cache/` still opens and just redraws. |
| `media/` | Only after **Consolidate Media…**: copies of the footage (see [Consolidate Media](#consolidate-media)). |
| `graphics/` | Only once you add a graphic: graphic modules, their fonts, images and kept versions. See [Graphics](graphics.md). |

**Media is referenced, not copied.** By default a project remembers where each file lives (its path and a Finder bookmark, so a moved file is often found again) and reads it from there. The package stays small, but it depends on the footage staying put. Consolidate Media is how you make a package hold everything it needs.

Caches are built in the background after an open, an import or a relink, and the timeline fills in as they finish. Frame Job builds at most two files' sound caches at a time, on threads of their own, so importing many long files at once does not hold up playback or a speed ramp's sound. A cache that already matches its file is never rebuilt. Moving, copying or consolidating the package keeps its caches. Until an untitled project is first saved, its caches live in a temporary folder; the first save copies them in.

*Transcripts* cost money to rebuild when they came from the cloud engine, so treat `cache/transcripts/` as worth keeping. See [Captions](captions.md).

## The Document tab: canvas settings

The canvas is the fixed frame every clip is composited into, and every export starts from its size. It is set on the inspector's **Document** tab, in five sections. Every change there to the project is one undo step (**Resize clips proportionally** is a preference on this Mac, not part of the project, so it is not undone).

### Document (summary)

Read-only rows: **Resolution**, **Frame rate**, **Duration**, **Tracks**, **Background** (Black, White, a `#RRGGBB` value, "Transparent", or a colour with its opacity as a percentage) and **Colour** ("SDR — Rec. 709" or "HDR — Rec. 2100 HLG").

### Canvas

| Control | What it does | Default |
|---|---|---|
| **Preset** | 1080p · 1920 × 1080, 4K · 3840 × 2160, 720p · 1280 × 720, Vertical · 1080 × 1920, Square · 1080 × 1080, 1440p · 2560 × 1440, or **Source Size** (the size of the first media file that has one). Shows **Custom** when the size matches none of these. | 1080p |
| **Width** / **Height** | Type an even number of pixels from 16 to 16384. | 1920 × 1080 |
| **Resize clips proportionally** | When on, changing the size also scales every clip's position and scale by the same ratio, so the layout looks the same at the new size. When off, clips keep their pixel positions. Remembered on this Mac, not in the project. | Off |
| **Dynamic Range** | SDR or HDR (HLG). See [HDR and colour](hdr-and-color.md). | SDR |
| **Blending** | Encoded or Linear light. See [HDR and colour](hdr-and-color.md). | Encoded |

Choosing **Custom** in the popup only beeps; type the size into Width and Height instead. **Source Size** also beeps when no media file has a picture size.

Width and height must both be even. An odd value is refused, for example "canvas width must be even (h.264 encodes in macroblocks), not 1081". A project opened from an odd-sized movie keeps that size, but once you change either field both sides are checked, and Source Size on an odd-sized file is refused the same way.

### Frame Rate

| Control | What it does |
|---|---|
| **Rate** | 24, 23.976, 25, 30, 29.97, 50, 60, or **Match First Clip**, which takes the rate of the earliest clip on the timeline whose file has video (beeps if there is none). |
| **Duration** | Read-only: the timeline's length. |

A project can run at a rate the popup does not list. An opened file at 24, 23.976, 25, 30, 29.97, 48, 50, 60 or 59.94 fps keeps that exact rate; any other rate (screen recordings often have odd ones) is kept to three decimals. The popup then shows **24**, while the Document summary's **Frame rate** row shows the real rate. Picking a popup item changes the rate, and **Match First Clip** brings the file's rate back.

Changing the rate moves every clip start, length, action and marker onto the new frame grid. If two markers land on the same frame at the new rate, the later one is dropped.

### Appearance

| Control | What it does | Default |
|---|---|---|
| **Background** | The colour behind every layer. Lower its opacity for a transparent background; the section's note then names the export formats that keep transparency, or counts them when there are three or more. | Black, opaque |
| **Timecode** | Frames (`HH:MM:SS:FF`) or Milliseconds (`HH:MM:SS.mmm`), everywhere the project shows a time. | Frames |
| **Fit new clips to canvas** | A clip added from a file larger than the canvas is scaled down to fit. | On |

**Reset** on the section header puts all three back to their defaults. It is offered only while one of them differs.

### Markers

Every marker in the project, with its name, **Chapter**, **Go** and **Delete**. See [Timeline](timeline.md).

*Agents:* `set_canvas` (takes `width`, `height`, `fps`, `background`, `rescale_clips`, `fit_new_clips`, `timecode_frames`, `output`, `blending`; anything left out keeps its value; `fps` takes any `[num, den]`).

## Bringing files in

### What Frame Job reads

| Kind | Files |
|---|---|
| Movies | MOV, MP4, M4V and other containers macOS plays: H.264, HEVC, ProRes, MJPEG and MPEG-4 video; VP9 Profile 0 and 2 in MP4; AV1 on an M3 or later Mac. |
| WebM and Matroska | `.webm` and `.mkv` with VP9, AV1, H.264 or HEVC video and Opus, Vorbis or AAC sound (see below). |
| Sound | M4A (AAC, ALAC), MP3, WAV and AIFF everywhere. Other formats macOS plays, such as CAF and FLAC, import when dropped on the Media tab. |
| Pictures | PNG, JPEG and HEIC everywhere. TIFF, GIF, BMP, HEIF and WebP also import when dropped on the Media tab. |
| LUTs | `.cube` 3D LUTs, applied as a clip's look or as a file's Camera Log. See [Color grading](color-grading.md). |

Caption files (`.srt`) are not media: bring them in with **File ▸ Import Captions…**. See [Captions](captions.md).

### Add Media

**File ▸ Add Media…** (⇧⌘I), or the Media tab's **Add Media…** button, opens a panel for one or more files. Every file is checked first. The readable ones are added to the Media tab together as one undo step ("Add Media", or "Add 3 Media Files"). A file that cannot be read shows an alert naming it, and the rest are still added. Adding a file that is already in the list changes nothing.

Adding puts files in the Media tab, **not** on the timeline. Place them from there (see [Putting media on the timeline](#putting-media-on-the-timeline)).

You can also drag files from the Finder onto the **Media tab**. That adds them to this project. A Finder drop anywhere else on the window (the canvas, the timeline) *opens* the file as a project of its own, as a drop on the Dock icon does.

*Agents:* `import_media` (takes a `path`; answers the new media id and what the check found: kind, duration, display size, frame rate, video/audio/alpha). `add_media` is the raw op behind it, taking a descriptor you supply.

### WebM and Matroska files

macOS cannot play WebM or MKV directly, so Frame Job copies the video and sound streams into a movie, without re-encoding, the first time you add or open one. The copy goes into `~/Library/Application Support/Frame Job/Rewrapped/`; your original is left where it is.

- There is no question to answer. A copy that takes more than a second shows a small **Copying Movie** window with its progress, and **Cancel** stops it and adds nothing.
- Before copying, Frame Job checks the disk has room. If it does not: "Not enough free space to open *file*: its video and sound need about *size* on "*volume*", which has *size* free. Nothing was copied."
- Importing the same file again reuses the copy.
- The media keeps the original's name, and its tooltip on the Media tab says where the copy lives.
- If the copy is later deleted, or moved to the Trash, the project makes it again from the original the next time it opens. If that copy is cancelled or fails, the file shows as missing (a slate, the **missing** badge, Relink…) until the next open tries again.
- Frame Job never deletes anything from the Rewrapped folder, which every project shares, so copies pile up there. You can clear it: WebM and MKV copies are made again on the next open (ffmpeg conversions are not; see below).
- **Consolidate Media** copies the copy, not the WebM, into the package's `media/` folder, and the row's tooltip then says it was copied into this project's package.

A stream the built-in copy cannot carry (FLAC, MP3, AC-3, MPEG-2 and similar) is refused with a sentence naming it. If you have ffmpeg installed, Frame Job then offers to help (next section).

### Files macOS cannot open, and ffmpeg

When macOS refuses a file and `ffmpeg` and `ffprobe` are both installed on this Mac, Frame Job asks before doing anything. It looks in your `PATH` first, then in `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, `/usr/bin` and `/bin`; to use one particular build, run `defaults write com.kgalligan.FrameJob RCFFmpegPath /path/to/ffmpeg` (its `ffprobe` is taken from the same folder when one is there). The alert, "Frame Job cannot open *file*.", says what it would cost: a quick **Repackage** that copies the streams, or a **Convert** that re-encodes, with the size and the time it would take. Tick **Do this automatically from now on** to have your answer remembered: always, if you accept, or never, if you cancel. The converted file goes into the same Rewrapped folder, and the original is untouched. A conversion that fails shows "Could not convert *file* with ffmpeg: *reason*". Unlike a WebM copy, a conversion that is later deleted is not made again when the project opens: the media stays missing until you relink it. Frame Job does not ship ffmpeg; without one, this step never appears. To be asked again after ticking "Do this automatically", see [Settings](settings.md#limits).

An agent's import never shows this question. Unless you have chosen "always", the file is refused instead.

### Files that are refused

- **A codec this Mac cannot decode** is refused at import with a sentence naming it, for example "*file* is AV1 video, which needs an M3 or later Mac." or "*file* is VP9 Profile 1 video, which this Mac cannot decode; VP9 Profiles 0 and 2 import." VP8 is refused the same way. A file in a codec this Mac does decode still imports even when some of its data is damaged.
- **A `.cube` the LUT reader cannot read** is refused naming the line and the problem, for example "“Film.cube” is not a LUT Frame Job reads: line 2: LUT_3D_SIZE 200 is outside 2–65."
- "Could not read *file*." means the file is damaged or not a format Frame Job reads.
- "*file* has no video or audio the app can open." means the file holds neither.
- "Timed out reading *file*." means the check took longer than 30 seconds, usually because the file is on a stalled network volume.

## The Media tab

The inspector's **Media** tab lists every file the project has imported, in a bar, a find band, the list and a footer.

- **The top bar:** **Add Media…** (⇧⌘I) and a count: "No media", "1 item", "12 items", or "3 of 12 items" while the list is narrowed.
- **The find band:** a **Search by name** field that filters as you type, ignoring case and accents ("resume" finds "Résumé.mov"; Esc clears it), a **Sort** popup (**Import Order**, Name, Duration, Kind), and an **Unused only** checkbox that shows only files no clip uses. Every sort is ascending, and files that tie stay in import order. A file used only inside a nest counts as used. None of these is saved with the project. If nothing matches: "No media matches the search or the filter." If the search or Unused only hides the selected row, that row is deselected.
- **The footer:** **Consolidate…**, with "Copies sources into the package" beside it.

With no media yet, the tab reads "Drop files here, or use Add Media…."

### A media row

Each row shows a thumbnail (a frame for video, a waveform glyph for sound, a cube for a LUT), the file's name, and a line with what applies to that file:

| Kind | The line reads |
|---|---|
| Movie | duration · width×height · frame rate, e.g. `00:01:12:04 · 1920×1080 · 29.97 fps` |
| Picture | width×height |
| Sound | duration |
| LUT | LUT |

Badges on the right mark a file that has **audio** and a file that is **missing**. Hover a row for its tooltip: "Drag to a timeline track, or onto the canvas. Hold ⌥ to insert, ⇧⌥ to overwrite." A LUT's reads "A LUT: apply it to clips as a look." A WebM, MKV or ffmpeg copy's tooltip adds a line above with the original's path and where the copy lives.

Click a row to select it; the selected row is outlined in the accent colour. Selecting a row is not an edit and does not mark the project as changed. Two more sections appear below the list for the selected row when the project has the right kind of file:

- **Camera Log**, once the project has a video file: how the selected file's log footage is converted. See [HDR and colour](hdr-and-color.md).
- **HDR10**, once the project has a PQ file: the peak brightness used for the selected file. See [HDR and colour](hdr-and-color.md).

### Putting media on the timeline

- **Drag a row onto a timeline track.** With no modifier it lands at the pointer, snapped to a frame, if that part of the track is free; if it would overlap a clip already there, the drop is refused and the drag springs back. Hold **⌥** as you drop to *insert* (the track opens up to make room) or **⇧⌥** to *overwrite* (whatever is under it on that track is replaced).
- **Drag a row onto the canvas.** It lands on a new track at the front, at the playhead.
- **Edit ▸ Insert at Playhead** / **Edit ▸ Overwrite at Playhead** place the selected row at the playhead. They have no shortcut, and they are off until a row (not a LUT) is selected on the Media tab. The track is the selected clip's track, or the front track when no clip is selected. With a nest open, that is a track inside the nest.

A row can only be placed in its own project's window; dragged into another project's window, it is refused.

A new clip is the whole file, as long as the file runs. A picture is 5 seconds long. With **Fit new clips to canvas** on, a file larger than the canvas is scaled to fit. A LUT row cannot be dragged or placed; it is applied as a look instead. What insert and overwrite do to the clips around them is covered in [Editing](editing.md).

*Agents:* `add_clip`, `insert_clip`, `overwrite_clip` (each takes `track`, `media` and `at`).

### The row's menu

Right-click a row for:

| Item | What it does |
|---|---|
| **Insert at Playhead** | As Edit ▸ Insert at Playhead, for this row. Off for a LUT. |
| **Overwrite at Playhead** | As Edit ▸ Overwrite at Playhead, for this row. Off for a LUT. |
| **Reveal in Timeline** | Selects every clip on the timeline that shows this file and scrolls to the earliest one; the inspector switches to the Clip tab. Off when nothing on the timeline uses the file, including when its only clips are inside a nest. For a LUT, it selects the clips whose look it is. |
| **Reveal in Finder** | Shows the file in the Finder. For a WebM or MKV copy, shows the original, or the copy when the original is gone. |
| **Relink…** | Points this media at another file (see [Missing media and Relink](#missing-media-and-relink)). |
| **Remove** | Takes the file out of the project (see below). |

### Removing media

**Remove** on an unused file removes it at once, as one undo step. If clips use it, Frame Job asks first:

- For footage: "Remove "*name*"? It is used by 3 clips, which will be removed with it." **Remove and Delete Clips** removes the file and those clips, including any inside nests, as one undo step.
- For a LUT: the alert counts the clips whose look it is ("which keep their place and lose the look") and the files whose Camera Log it is ("which lose it"). **Remove and Clear Looks** removes the LUT and clears those looks and conversions; the clips stay.

Removing media never deletes the file from disk.

*Agents:* `remove_media` (refused while clips use it unless `with_clips: true`).

## Missing media and Relink

A project always opens, even when files it uses have moved or been deleted. Clips whose file is gone keep their place on the timeline and show a slate in their place, and their media rows wear the **missing** badge.

When a project opens with files missing, Frame Job offers the **Missing media** sheet once: "The project opened without these files: their clips keep their place on the timeline and show a slate until the files are found." Each missing file is listed with its old path and a **Locate…** button.

- Choosing a file for one entry also looks in that file's folder for the other missing files by name, and fills in each one it finds. A shoot moved as one folder is usually found with one Locate….
- A located row's button turns into **Change…**.
- The footnote counts the missing files ("3 files").
- **Relink** stays off until at least one file is located, then applies every choice as one undo step ("Relink Media"). You do not have to locate them all: the ones you skip stay missing, and you can relink them later from the Media tab. **Cancel** changes nothing.
- The sheet is offered once, when the window opens, and not over another sheet that is already showing.

Relinking checks the new file as an import does. The media takes the new file's duration, size, frame rate and audio/video flags. A clip that runs past the end of a shorter new file is shortened to end with it. A file of another kind (a sound file for a video entry, say) is refused, and the reason is shown after the other relinks are applied. A WebM or MKV chosen as the new file is copied as on import.

To relink one file at any time, use **Relink…** on its Media-tab row: "Choose the file for "*name*"."

A consolidated package that has been moved or renamed finds its own copies again when it opens: any missing media whose file sits in the package's `media/` folder under the same name is pointed back at it, with no sheet.

*Agents:* `relink_media` (takes `media` and `path`; the app checks the new file itself). `get_project`'s `missing_media` lists what needs it.

## Consolidate Media

**File ▸ Consolidate Media…**, or **Consolidate…** at the foot of the Media tab, copies every file in the project's media list (used on the timeline or not) into the package's `media/` folder and points the project at the copies. Afterwards the package is the whole edit: you can hand it to someone, move it, or archive it and delete the originals.

- The project must have been saved first. On an untitled project the command asks "Save this project first?" and offers **Save…**; after the save it carries on.
- A **Consolidating Media** sheet shows progress ("Copying 4 files (2.1 GB) into the package…") and the file being copied. **Cancel** stops the copying; what was copied stays copied and the rest keep pointing at the originals, so the project always opens.
- When it finishes the sheet says what happened ("Copied 4 files (2.1 GB) into the package.", plus any files that could not be copied and any missing files it left alone) and offers **Show in Finder** and **Close**. The relinks are one undo step, "Consolidate Media".
- Two files with the same name are kept apart (`intro.mov`, `intro-2.mov`). Two entries that point at the same file share one copy. Files already inside the package are not copied again.
- Missing files cannot be copied: relink them first. If there is nothing to do, it says "Nothing to consolidate." and why.
- LUTs are consolidated like footage.

The command is off when the project has no media.

*Agents:* `consolidate_media` (needs a saved project; can take a while and copies as many bytes as the footage weighs).

## Limits

- Consolidate Media needs a saved project.
- Canvas width and height are even numbers from 16 to 16384 px.
- A project holds at most 4,096 clips and 64 tracks (counting those inside nests), 1,024 markers and 1,024 media files, with nests up to 8 deep.
- The Add Media… and Open panels list movies, M4A, MP3, WAV, AIFF, PNG, JPEG, HEIC and (Add Media… only) `.cube`. Other sound and picture formats import only by a drop on the Media tab, or through `import_media`.
- `.cube` files are imported, not opened: File ▸ Open… does not take one, and a `.cube` dropped on the window or the Dock is not imported. Use Add Media… or a drop on the Media tab.
- A project file that is damaged or out of range fails to open with a message naming the problem; the package is not rewritten. A package saved by a newer Frame Job reports "project format version *N* is newer than this build understands (version *M*); update Frame Job to open it". A package with no readable `project.json` reports "*name* does not contain a readable project.json."
