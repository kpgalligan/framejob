# Exporting

Frame Job writes the timeline out as a movie, an audio file or an animated image, and saves single frames as stills. One export sheet covers every format. You choose the format, then the size, frame rate, quality, loudness and range, and the sheet shows what the file will be before anything is written. Exports can run at once behind a progress sheet, or wait in the Export Queue while you keep editing. Every export of a file with sound reports what that sound measured.

## Opening the export sheet

Choose **File ▸ Export…** (⌘E), or click **Export…** at the right end of the toolbar. Playback pauses and the sheet opens over the editor window.

The command is greyed out while the timeline is empty. An export always writes the whole top-level timeline, even when you are working inside a nest.

The sheet reopens on the **last choices you exported with**. Clicking **Export…** or **Add to Queue** records them; Cancel does not. With nothing remembered, it opens on H.264 at the document's own size.

The remembered choice belongs to the app, not to the project, so every document's sheet opens on it. A remembered **In/out range** falls back to **Whole project** on a document that has no range.

## The controls

From top to bottom:

| Control | What it does | Default |
|---|---|---|
| **Preset** | Applies a saved set of choices (see [Presets](#presets)). The gear beside it saves and deletes presets. | Custom |
| **Format** | The encoding: container and codec together. | H.264 (MP4) |
| **Dynamic Range** | Shown only in an HDR (HLG) project. See [HDR projects](#hdr-projects). | HDR (HLG) |
| **Size** | The frame size, or **Custom…** with width and height fields on the row below. | The format's first row |
| **Frame rate** | **Project rate**, or a fixed rate. | Project rate |
| **Quality** | **Format default**, or a bit-rate tier. | Format default |
| **Loudness** | **Off**, a loudness target, or **Custom…** with a LUFS field. | Off |
| **Range** | **Whole project**, or **In/out range** when one is set. | Whole project |
| **Burn in timecode** | Draws the project timecode into the picture. | Off |

Under the controls, a readout line describes the file and a footnote names the codec, the container and the rates the file will use. Every number they show is the size, rate and duration the file will actually have.

- **Readout:** `1920 × 1080 · 30 fps · 00:01:12:05` (size, frame rate, duration). For the audio-only formats it reads `Audio only · 00:01:12.200`. For GIF and APNG it adds the frame count: `· 360 frames, no audio`.
- **Footnote:** the codec, the container (left out when it is the same word, as in `GIF`), the video rate, the audio rate (`192 kbps audio`), the loudness target (`−14 LUFS`) and `alpha` when the format keeps transparency. When you pick a Quality tier and the format sets its own rate, it reads `format's own rate` instead of a number.

A control the chosen format cannot use is greyed out rather than hidden. Its value is not sent.

### Format

| Format | Container | What it is for |
|---|---|---|
| H.264 (MP4) | `.mp4` | The everyday delivery file. 8-bit. |
| HEVC (MP4) | `.mp4` | A smaller file at the same picture. 8-bit (Main profile). |
| HEVC with Alpha (MOV) | `.mov` | A small delivery file that keeps a transparent canvas, for laying over another background. 8-bit. |
| HEVC 10-bit (MP4) | `.mp4` | Keeps a 10-bit source's gradients (Main 10). |
| ProRes 422 (MOV) | `.mov` | An editing master for another application. 10-bit. |
| ProRes 4444 (MOV) | `.mov` | A master that keeps the alpha channel. 12-bit. |
| Audio only (M4A) | `.m4a` | AAC sound only. |
| Audio only (WAV) | `.wav` | Uncompressed 16-bit, 48 kHz sound. |
| Audio only (AIFF) | `.aiff` | The same samples as WAV, in an AIFF file. |
| Animated GIF | `.gif` | A short silent loop. Capped at 480 × 270 and 12.5 fps by default. |
| Animated PNG | `.png` | A lossless silent loop with real transparency. Capped at 960 × 540 and 25 fps by default. |

Sound in the movie formats is stereo at 48 kHz: AAC in H.264, HEVC and HEVC with Alpha, and 16-bit LPCM in both ProRes formats. GIF and APNG carry no sound. A file's sound is exactly as long as the range it exports, including when a clip in it plays faster or slower.

Changing the format rebuilds the Size list and puts it back on that format's default. Your frame rate, quality, loudness and range choices stay as they were.

### Size

The Size popup lists, in order:

- **GIF default** or **APNG default**: the format's cap. Only on those two formats, and it is their default.
- **Document size**: the canvas as it is. On a format that needs even dimensions and a canvas with an odd edge, this row is named **Document (even)** and is one pixel smaller on that edge.
- **4K**, **1440p**, **1080p**, **720p**: the number is the short edge. The long edge follows the document's shape, rounded to an even number, so a vertical project's 1080p is 1080 × 1920.
- **Custom…**: type a width and a height, each from 16 to 8192 pixels. The fields start from the size that was chosen a moment before.

A row with the same numbers as an earlier row is hidden, so a 1920 × 1080 document shows Document size and no separate 1080p. Sizes larger than the document are offered, so a 720p recording can be exported at 4K.

How the picture fits the frame:

- **Even dimensions.** H.264, HEVC, HEVC with Alpha, HEVC 10-bit and ProRes 422 need them, so an odd width or height is written one pixel smaller. ProRes 4444, GIF and APNG keep an odd edge.
- **Movies** are written at exactly the size you choose. When that size is within a pixel of the canvas's shape, the picture fills the frame edge to edge. Any other shape is letterboxed with black.
- **ProRes 4444 and HEVC with Alpha** refuse a size of a different shape instead of letterboxing it, because the padding would destroy the alpha channel. Every row in the Size popup has the canvas's shape, so this only happens with a Custom size.
- **GIF and APNG** fit the picture inside the size you choose, keeping its shape and never enlarging it. The readout shows the size the file will have: a 1080 × 1920 project's GIF default is 152 × 270.

The Size control is greyed out for the audio-only formats.

### Frame rate

**Project rate** exports at the document's frame rate, or at the format's own rate for GIF (12.5 fps) and APNG (25 fps). The fixed choices are 24, 23.976, 25, 30, 29.97, 50 and 60 fps. Greyed out for the audio-only formats.

### Quality

**Format default** lets the encoder choose the video rate. The sound uses 192 kbps AAC.

The four tiers set a video rate from the frame's size, so a tier means the same picture quality at every size. Each tier's title shows the rate it would ask for at the size and frame rate now chosen.

| Tier | Video at 1080p, 30 fps or less (H.264) | AAC sound |
|---|---|---|
| **Low** | 4.0 Mbps | 128 kbps |
| **Medium** | 6.0 Mbps | 192 kbps |
| **High** | 8.0 Mbps | 256 kbps |
| **Maximum** | 12.0 Mbps | 320 kbps |

- The video rate scales with the frame's area. High is about 3.6 Mbps at 720p and 32 Mbps at 4K.
- Above 30 fps, the video rate is 1.5 times higher.
- HEVC formats ask for 60 % of the H.264 rate.
- Audio only (M4A) uses the tier's AAC rate alone.
- Quality is greyed out for ProRes, WAV, AIFF, GIF and APNG, where the format fixes the rate.

### Loudness

Loudness normalises the whole mix to an integrated loudness target, measured to ITU-R BS.1770-4.

| Choice | Target |
|---|---|
| **Off** | No normalisation. The export still measures its sound and reports it. |
| **−14 LUFS (streaming)** | Where the main streaming services normalise. |
| **−16 LUFS** | The usual target for stereo podcasts. |
| **−23 LUFS (broadcast)** | EBU R 128 broadcast delivery. |
| **Custom…** | Type any target from −70 to 0 LUFS, to one decimal place. |

How normalisation works:

- The export measures the real mix first. The progress line reads "Measuring loudness…" during this pass.
- It then applies **one gain** to everything. Levels inside the timeline keep their relationship to each other, and there is no limiter.
- The gain is capped so the true peak stays under **−1 dBTP**. When the cap applies, the file comes out quieter than the target.

The sheet fixes the ceiling at −1 dBTP. An agent can choose another (see [For agents](#for-agents)). Loudness is greyed out for GIF and APNG.

For per-clip levels, fades and Normalize, see [Audio](audio.md).

### Range

**Whole project** writes the whole timeline. **In/out range** writes only the range set on the timeline (see [Timeline](timeline.md)), snapped to the export's frame grid. The popup is greyed out when there is no range.

Inside a nest, the popup is greyed out even when the nest has a range, and its tooltip says why: an export writes the whole timeline, so it cannot use a range that belongs to the nest. Leave the nest (⌘↑) and set the range on the timeline.

### Burn in timecode

**Burn in timecode** writes the project's timecode into the exported picture, centred near the bottom and on top of everything, including captions. It appears only in the exported file, never in the preview.

- It uses the document's own timecode format, `HH:MM:SS:FF` or `HH:MM:SS.mmm`, non-drop, as the toolbar shows it.
- It shows **project time**. A file exported from an in/out range that starts at 00:00:10:00 begins at 00:00, but its first frame reads 00:00:10:00. That is the number a reviewer's note needs.

Greyed out for the audio-only formats.

## Presets

A preset stores the **choices** on the card: the format, size row or custom size, frame rate, quality tier, loudness, range and burn-in. It does not store the numbers they resolve to. A preset saved on a 1080p document that says "4K, High" exports at the right 4K size and rate on any other document.

- **Apply a preset:** pick it from the **Preset** popup. Every control is set exactly as if you had clicked it.
- **Save a preset:** click the gear and choose **Save…**, type a name and click **Save**. The name field starts with the name of the preset now chosen. Saving under a name that already exists (ignoring case) replaces that preset. The name "Custom" is reserved. While the card has an error, for example an empty custom field, **Save…** beeps and saves nothing.
- **Delete a preset:** choose it in the popup, then choose **Delete** from the gear. Delete is available only while a saved preset is chosen, and it asks no confirmation. The controls keep the preset's values, so **Save…** under the same name puts it back.
- **Change a preset:** apply it, adjust the controls, and save again under the same name. There is no separate rename.

Changing any control by hand puts the popup back on **Custom**. The popup also opens on Custom each time, even when the remembered choices happen to match a preset.

Presets are kept for your whole account in `~/Library/Application Support/Frame Job/ExportPresets.json`, so every project and window shares them. The **Dynamic Range** choice is not stored in a preset or in the remembered choices.

## Writing the file

The sheet has three buttons:

- **Cancel** closes the sheet. Nothing is written and nothing is remembered.
- **Export…** opens a save panel, then writes the file behind a progress sheet.
- **Add to Queue** opens the same save panel, then puts the job in the Export Queue so you can keep editing.

Both are greyed out while the sheet cannot work out a valid file, for example when a custom field is empty. The readout then says what to fix.

The save panel suggests the project's name with the format's extension (`Board v1.2.mp4`). It says what is being written: "Export the timeline as a movie.", "Export the timeline as an animated GIF." or "Export the timeline's audio."

### The progress sheet

**Exporting** shows a progress bar and a percentage. The status line reads "Preparing “*name*”…", then "Measuring loudness…" while the sound is measured, then "Writing “*name*”…".

- **Cancel** stops the export ("Stopping…") and removes the half-written file.
- When it finishes, the line reads "Exported “*name*”." followed by what the sound measured, for example `Peak −1.0 dBTP · −14.0 LUFS`. **Show in Finder** reveals the file, and **Close** dismisses the sheet.
- If a graphic warned while the file was drawn, the line adds a count ("1 graphic warning"), and the tooltip lists each warning with its frame.
- A failure shows its reason on the sheet, and **Close** dismisses it.

### What the loudness line means

| Line | Meaning |
|---|---|
| `Peak −1.0 dBTP · −14.0 LUFS` | The true peak and integrated loudness of the file. |
| `Peak … · loudness not measurable` | The sound is too short or too quiet to have a loudness. |
| `Silent` | The sound is digital silence. |
| `… — measured on the mix, which clipped at +x dBFS before it was written` | The mix went over full scale and was written without normalisation, so the file is clipped and these are the mix's figures. Turn the clips down, or export with a loudness target, which brings a hot mix back under full scale before it is written. |

## The Export Queue

**Window ▸ Export Queue** lists queued exports. It opens on its own whenever you click **Add to Queue**.

- Jobs run **one at a time**, in the order they were added, while you keep editing.
- A job holds the timeline **as it was when you confirmed it**, including its media files, reversed clips and graphics. Edits, undos, relinks and even closing the document afterwards do not change what it writes.
- Each row shows the file's name and its state: **Waiting**, *Writing · 42 %* (or the measuring phase), the "Exported …" line with its loudness figures, **Cancelled.**, **Cancelled before it started.**, or the reason a job failed. The tooltip shows the full path, the format, size and frame rate, and any graphic warnings.
- **Cancel** on a row stops that job and removes its half-written file. On a finished row the button reads **Remove** and takes the row out of the list. **Show** reveals a finished file in the Finder.
- If a later export writes to the same file, the earlier finished row reads "Overwritten by a later export to the same file."
- **Clear Finished** removes every finished, cancelled and failed row. **Cancel All** stops the running job and every waiting one.
- The line at the bottom, beside **Clear Finished** and **Cancel All**, counts the jobs: "1 exporting · 2 waiting · 3 finished".
- With nothing queued, the window says so: "Nothing queued. The Export card's Add to Queue button puts a confirmed export here instead of waiting for it, and they run one at a time while you keep editing."

Closing the window stops nothing. Opening the export sheet pauses playback whichever button you use, but after **Add to Queue** there is no progress sheet in the way: you can resume playback and keep editing while the job runs.

Quitting while a queued job runs or waits asks first: "An export is still being written." The message names the running file and counts the jobs still waiting ("“*name*” is not finished, and 2 more are waiting."). **Quit Anyway** cancels the queue and deletes the partly written file. This question comes after Frame Job has asked about unsaved documents.

Only queued exports are protected this way. Quitting while an **Export…** progress sheet is writing does not ask, and the half-written file is left behind. Cancel that export first.

## Saving a single frame

**File ▸ Save Frame…** (⌥⌘E) saves the frame under the playhead as a still. The save panel suggests the project's name and the timecode, with `-` for `:` (`Board 00-00-12-05.png`). Its **Format** popup offers:

| Format | Alpha | Notes |
|---|---|---|
| **PNG** | Kept | The default. |
| **JPEG** | None | A transparent canvas is flattened onto black. |
| **HEIC** | Kept | |

- The **Format** popup opens on PNG every time. It does not remember your last choice.
- Under the popup, a line says what the chosen format does with transparency: "PNG keeps the canvas's alpha channel." or "JPEG has no alpha channel: a transparent canvas is flattened onto black."
- Choosing a format changes the file name's extension in the panel. A name you typed is kept.
- JPEG and HEIC are written at 90 % quality.

- The frame is drawn the way an export draws it, at the canvas's full size. Preview Quality, Show Ungraded and Show SDR Version never change it. There is no timecode burn-in.
- Inside a nest, the frame is the nest's own picture at the nest's time.
- A frame showing a deep still or a 10-bit VP9 clip is saved as a 16-bit PNG or 10-bit HEIC. JPEG is always 8-bit.
- In an HDR (HLG) project, PNG and HEIC keep the HLG picture and a JPEG is the SDR version (see [HDR and colour](hdr-and-color.md)).
- When there is no frame at the playhead, an alert says so.
- If the file cannot be written, an alert says why: the folder is missing or Frame Job cannot write into it, or this Mac has no encoder for the format.

Save Frame… is greyed out while the timeline is empty.

*Agents:* `render_frame` writes the same file for the same frame (see [For agents](#for-agents)).

## HDR projects

In an HDR (HLG) project the sheet has a **Dynamic Range** row under Format:

| Choice | What the file holds |
|---|---|
| **HDR (HLG)** | The HLG master. The default. |
| **HDR10 (PQ)** | An HDR10 file with fixed mastering metadata. |
| **SDR version** | The project converted to SDR. |

Only HEVC 10-bit, ProRes 422 and ProRes 4444 can carry HDR. On every other video format the row is greyed out on **SDR version**, which is what those formats write. What each choice contains, and how the SDR version is made, is in [HDR and colour](hdr-and-color.md#exporting-hdr).

## Transparency

A canvas whose background is transparent (the **Background** row in the Document tab's Appearance section; see [Projects and media](projects-and-media.md#appearance)) keeps its transparency only in **ProRes 4444**, **HEVC with Alpha** and **Animated PNG**. When the format carries an alpha channel, the footnote ends in "alpha". Every other format composites the picture onto black. A GIF can show a pixel as fully transparent but has no partial transparency, so it is not one of the three.

While the canvas background is transparent, the Document tab says how many formats will keep it: "Transparent — kept by 3 export formats." These are the three formats above.

## Chapters

Chapter markers on the timeline (see [Timeline](timeline.md)) become chapters in MP4, MOV and M4A files, in time order. A chapter's name is the marker's name, or "Chapter *n*" for an unnamed one. A range export keeps the chapters inside the range, with their times counted from the start of the file, and the chapter already running when the range starts opens the file. WAV, AIFF, GIF and APNG have no chapters.

MP4 and M4A files are written with their index at the front, so a player can start before the whole file has downloaded.

## What an export includes

- **The same picture and sound as the preview.** The export uses the same composition and the same compositor. View-only settings never reach it: Preview Quality, Show Ungraded, Show SDR Version, Show Selection, safe areas and the scopes.
- **Speed ramps and Keep pitch off.** An export waits for the rendered audio of every speed ramp, and of every clip at a constant speed other than ×1 with Keep pitch off, to finish before it writes, and shows "Preparing…" meanwhile. That sound is never exported silent (see [Speed](speed.md)). If it cannot be rendered, the export fails with "Clip *n*'s retimed audio could not be rendered: …".
- **Missing media.** A clip whose file is missing still exports, showing its slate and with no sound. An audio track none of whose clips can be read is written as silence instead of failing the export.
- **Graphics.** An export draws the graphics as they were when it was asked for, even if a module is saved again mid-export. If a graphic in the range, or in a nest the range reaches, does not compile or has no module, the export does not start and names the graphic. If a graphic fails while the file is being written, the export stops at that frame, names the graphic, and leaves no file. See [Graphics](graphics.md).
- **Captions** are ordinary text clips, so they are always burned into the picture. To write a separate subtitle file, use **File ▸ Export Captions…** (see [Captions](captions.md)).

## For agents

`export` mirrors **Export…** with **Add to Queue**: it checks the request, puts the job in the Export Queue and answers at once with `{export_id, path, status}`. Status is `queued` or `running`.

| Argument | The sheet's control | Notes |
|---|---|---|
| `preset` (required) | Format | `h264`, `hevc`, `hevc_alpha`, `hevc_10bit`, `prores_422`, `prores_4444`, `audio_m4a`, `audio_wav`, `audio_aiff`, `gif`, `apng`. |
| `path` (required) | Save panel | The folder must exist. An existing file is replaced. The format's extension is added when the path has none, and a different known media extension is replaced: `cut.mov` with `h264` writes `cut.mp4`. Any other suffix stays part of the name. |
| `size` | Size | `document`, `2160p`, `1440p`, `1080p`, `720p`, `preset` (GIF and APNG only), or `[width, height]`. |
| `range` | Range | `project` (default) or `in_out`. Refused when there is no in/out range. |
| `video_bitrate`, `audio_bitrate` | Quality | Bits per second. |
| `loudness_lufs` | Loudness | −70 to 0. |
| `peak_dbtp` | (fixed at −1 on the sheet) | −20 to 0. Refused without `loudness_lufs`. |
| `burn_in_timecode` | Burn in timecode | |
| `dynamic_range` | Dynamic Range | `hlg`, `pq` or `sdr`. |

There is no frame-rate argument. An agent's export uses the document's rate, or GIF's and APNG's own.

Every refusal comes back from `export` itself, before anything is queued: a bad argument, a missing folder, an empty timeline, or a graphic that does not compile.

- `export_status {export_id}` answers the job's row without waiting: `queued`, `running` (with `progress` from 0 to 1 and `phase`), `done`, `failed` or `cancelled`. Call it again after a pause until the job finishes.
  - Every answer has `path` and `elapsed` (seconds).
  - `done` adds `bytes`, the settings the file was written with, `burn_in_timecode`, `dynamic_range` in an HLG project, any `graphic_warnings` and, for every format with sound, `loudness`: `summary`, `integrated_lufs`, `true_peak_dbtp`, `sample_peak_dbfs`, `gain_db`, `ceiling_dbtp`, `capped_by_peak` and `target_lufs`.
  - `failed` and `cancelled` add `reason`, the queue row's sentence.
- `cancel_export {export_id}` is the row's Cancel.
- An `export_id` lasts until Frame Job quits.
- `render_frame` renders one frame through the same path as Save Frame…. It returns the image inline and as a file, and with no `path` it writes a temporary PNG and names it. An explicit `format` wins and replaces the path's extension, so `{path: "shot.jpg", format: "png"}` writes `shot.png`. When a graphic in the frame warned or failed, the reply names it, its frame and the message, and a failed graphic draws its error card in the picture. It takes `t` (default: the playhead), `path`, `format` (`png`, `jpeg`, `heic`), `max_width` and `burn_in_timecode`, plus `sdr_version`, `ungraded`, `selection` and the scope measurements described in [Colour grading](color-grading.md) and [HDR and colour](hdr-and-color.md).

The full reference is [MCP](mcp.md).

## Limits

- An animated GIF or APNG holds at most **600 frames**: 48 seconds at GIF's 12.5 fps, or 24 seconds at APNG's 25 fps. A longer range is refused. Shorten the range or lower the frame rate.
- Loudness normalisation is gain only, with no limiter. A target the ceiling will not allow lands quieter than asked.
- An unnormalised mix that goes over full scale is clipped in the file.
- ProRes 4444 and HEVC with Alpha refuse a custom size of a different shape from the canvas.
- A Mac with no encoder for a format reports "This Mac cannot export with the “*preset*” preset." and leaves no file.
- WAV and AIFF are 16-bit only.
- Captions are burned in, never a switchable subtitle track.
- Queued jobs run one at a time. **Export…** does not join the queue: it writes straight away, behind its own progress sheet.
- Quitting during an **Export…** progress-sheet export does not ask and leaves a half-written file. Only the Export Queue is guarded at quit.
