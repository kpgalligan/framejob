# Screen recording

Frame Job records your screen itself. You can record a whole display or a single window, with system audio, your microphone and rings around your clicks, and the recording goes straight into a project. You can also record a voice-over, which is the microphone alone with no picture, at the playhead of the project you're editing. Every recording is an ordinary movie or audio file on disk, and Frame Job imports it the way it imports any other media, so every edit, effect and export works on it.

## Opening the recorder

Choose **File ▸ New Recording…** (⌥⌘N), or click **New Recording…** on the welcome window. A small floating panel titled **New Recording** opens. You don't need a project open.

The panel floats above other windows and doesn't make Frame Job the active app when you click it. That lets you bring the app you want to record to the front and still press Record. It also doesn't hide when you switch to another app. If you open it while Frame Job is in the background, it comes to the front without taking the keyboard, so your typing stays in the app you were using.

In the panel, Return presses **Record** and Esc presses **Close**.

## The panel's controls

| Control | What it does | Default |
|---|---|---|
| **Source** | What to record. Lists one row per connected display by name, then **Window…** (pick one window), then **Camera** (a camera on its own), then **Microphone Only** (a voice-over with no picture). | The display you used last, else the main display |
| **Include Frame Job windows** | Puts Frame Job's own windows, such as the editor and the preview, into a display recording. When it's off, they're left out of the picture. | Off |
| **Camera** | With **Source** set to **Camera**, which camera to record: each connected camera by name, or **None connected**. An iPhone used as a Continuity Camera reads "<name> (Continuity Camera)". It's greyed out for every other source. | The camera you used last, else the Mac's preferred camera, then the first built-in camera, then the first one connected |
| **Format** | With **Source** set to **Camera**, the size and frame rate to record at. **Best** comes first and names the camera's best format, for example **Best (1760×1328 at 30 fps)**. Then come the camera's other formats, such as **1920×1080 at 30 fps**: sizes wider than tall first, then square, then taller than wide, each largest first and at its highest frame rate. It's greyed out for every other source. | The format you used last when the chosen camera has it, else Best |
| **Preview** | With **Source** set to **Camera**, a live picture of the chosen camera at the chosen format, under Format. It's shown as the movie will record it: not mirrored, the whole picture fitted inside. The row appears only with **Source** set to **Camera**. | — |
| **Microphone** | **Off**, or one of the connected microphones. A live level meter sits beside it. | Off |
| **System Audio** | Records what the system plays, as the movie's own stereo 48 kHz sound track. | On |
| **Show Clicks** | Draws a ring around each mouse click. The pointer itself is always recorded. | Off |
| **Rate** | **30 fps** or **60 fps**: the most frames per second the file may hold. It's also the frame rate of a new project made from the recording. | 60 fps |
| **Size** | **Nominal (points)** records the display at its point size. **Best (pixels)** records every pixel, which is twice the points on a Retina display. | Nominal (points) |
| **Record Into** | **New Project**, or any open project by name. | The front project, else New Project |

Under Size, a note shows what you'll get for the chosen display, for example `1728×1117 points · 3456×2234 pixels`. For a picked window it reads "the picked window's own size". For Microphone Only it reads "no picture — the microphone alone". For Camera it names the format the camera records at, for example `1760×1328 at 30 fps — the camera's best format` with Format set to Best, `1920×1080 at 30 fps — the chosen format` with a format chosen, or "no camera connected".

The footnote at the bottom left shows where recordings are saved (for example `saved in ~/Movies/Frame Job Recordings`). While a recording runs, it shows the elapsed time instead.

The panel remembers your choices between uses, including the display, microphone, camera, camera format, switches, rate, size and the Include Frame Job windows box. The camera format is one choice for every camera: a camera that doesn't have the remembered format shows Best. It doesn't remember a picked window, the Camera or Microphone Only source (each lasts for the session only), or Record Into. A display, microphone or camera that is no longer connected falls back to the main display, to Off, or to the default camera. While the panel is up and not recording, the Camera and Microphone lists follow the devices you plug in or take away (a change made during a recording waits for it to end). A camera that's removed falls back to the default camera, and when it comes back it's chosen again with its format. Plugging in or removing a device doesn't change what the panel remembers.

### Record Into

**Record Into** follows whichever project is in front, until you choose a row yourself. After that it keeps your choice for as long as that project stays open. When you press Record, the row freezes, so switching to another window during the recording doesn't change where the recording goes.

## Choosing what to record

### A display

Choose a display by name in **Source**. Frame Job's own windows are left out of a display recording unless **Include Frame Job windows** is on. Even with the box on, the recorder panel itself is never in the picture. The panel leaves the screen as soon as the recording starts.

Frame Job's own sound is never recorded, with or without the box. That means you can play the timeline during a recording and it won't end up in the file.

### A window

Choose **Window…** in **Source** and macOS's window picker opens. Click the window you want. The Source row then reads **Window (picked)** and the recording is that window alone, at its own size. If you cancel the picker, Source goes back to the display you used last. If the picker can't open at all, Source also goes back to the display you used last, and the note reads "The window picker could not open: …" with the reason.

When **Include Frame Job windows** is off, the picker lists none of Frame Job's windows. When it's on, the picker lists them, but never the recorder panel. The box only changes the next time the picker opens. A window you've already picked stays picked.

If you press Record while the row reads **Window…** with nothing picked, the panel says "Choose a window with Window… first, or pick a display." and nothing records.

### A camera

Choose **Camera** in **Source**, then the camera in **Camera**:

- **System Audio**, **Show Clicks**, **Size**, **Include Frame Job windows** and **Rate** grey out. Their values are kept for next time. A camera records at the format chosen in **Format**, at that format's highest frame rate. **Best** is the largest size wider than tall that runs at 30 fps or more. The note under Size names the format.
- **Microphone** and **Record Into** stay live. The microphone you choose, which can be the camera's own when macOS lists it, is recorded to its own file beside the movie. **Off** records the camera alone.
- With no camera connected, Record says "No camera is connected."
- Only the Camera permission (and the Microphone permission, when one is chosen) is checked. Screen Recording isn't needed.

The camera starts as soon as the panel shows **Camera**, and the **Preview** under Format shows its live picture. Because it's already running, it has settled at its frame rate by the time recording begins, and its light stays on while the panel shows **Camera**. Choosing a display or another source, or closing the panel, turns it off. The preview changes with the camera and format you choose. Instead of the picture it reads "No camera is connected." with no camera, "The preview shows once Frame Job may use the camera." until you've allowed the Camera permission (showing the panel never asks for it, pressing Record does), or the reason the camera couldn't start. Choosing **Camera** again or reopening the panel tries again. **The panel stays up** while a camera records, as it does for a voice-over: nothing on screen is filmed. Its controls lock, the meter stays live, the footnote shows ● or ❚❚ and the elapsed time, Record reads **Stop**, and a **Pause** / **Resume** button appears beside it. If you close the panel, the recording carries on.

The camera's movie lands like a screen recording's picture: on the front track if it fits, else on a new track in front, with the microphone on a new back track named **Microphone**. As a new project, the canvas is the movie's size at the format's frame rate. If the camera stops on its own (for example, it's unplugged), the recording ends there, what was captured lands, and the note gives the reason followed by "What was captured was added." If the camera hadn't settled at its frame rate when recording began, the note says what rate it ran at.

### Microphone Only (voice-over)

See [Voice-overs](#voice-overs-microphone-only) below.

## Recording

1. Set up the panel and press **Record**.
2. Frame Job checks the permissions it needs (see [Permissions](#permissions)).
3. A **3, 2, 1** countdown appears in the panel. During the countdown the Record button reads **Cancel**, and the microphone meter already moves so you can check your level. Click **Cancel** or close the panel to stop the countdown. Nothing is recorded.
4. The recording starts and the panel leaves the screen. For a camera or a voice-over, the panel stays up instead.

While the recording starts, the button reads **Starting…**. If the recording hasn't started within 20 seconds, the panel says "The recording did not start within 20 s." and goes back to idle. A Stop pressed while the button reads **Starting…** (for example **File ▸ Stop Recording**) abandons the recording, and the note reads "Stopped before the recording began; nothing was recorded."

Only one recording runs at a time. Pressing Record while another recording runs or is paused, including one an agent started, is refused with "A recording is already in progress."

### The menu-bar item

While a recording runs, Frame Job puts an item in the menu bar: a coral **●** and the elapsed time (`m:ss`, or `h:mm:ss` past an hour). Click it for its menu.

| State | Menu bar shows | Menu |
|---|---|---|
| Recording | ● and the running time | **Pause Recording**, **Stop Recording** |
| Paused | ❚❚ and the time, held still | **Resume Recording**, **Stop Recording** |

The item keeps one fixed width, so the other menu-bar items don't shift as the seconds tick. It comes down as soon as the recording stops.

### Pausing and stopping

You can pause, resume and stop from any of these places:

- the menu-bar item's menu
- **File ▸ Pause Recording**, directly under New Recording…, which reads **Resume Recording** while paused and works only while a recording runs (it has no shortcut)
- **File ▸ Stop Recording** (⌥⌘N). While any recording runs, including a paused one, **File ▸ New Recording…** reads **Stop Recording** and stops it.

The welcome window's **New Recording…** button never stops a recording. During a screen recording it only beeps, so use **File ▸ Stop Recording** or the menu-bar item. During a camera recording or a voice-over it shows the panel again.

macOS's own screen-recording indicator in the menu bar can also stop the recording. Frame Job keeps what was captured and adds it.

If you choose **Quit Frame Job** (⌘Q) during a recording, Frame Job doesn't quit. Instead it opens the menu-bar item's menu so you can stop or resume first. For a camera recording or a voice-over, it shows the panel instead.

### Paused recordings are stretches

A pause ends the current file and a resume starts a new one, so a paused recording is several files, one for each stretch between a start or resume and a pause or the stop. Each file is named by the time its stretch began. When the recording lands, the stretches sit end to end on one track, touching, with no transition between them. Each stretch's microphone file goes on the Microphone track, lined up with its own picture.

The paused time is in no file. The elapsed time counts only what was recorded.

## Where it lands

When you stop, the panel's button reads **Stopping…** and then **Adding…** while the files are written and imported.

### Into an open project

The recording goes into the project you chose in **Record Into**, at its playhead, in whatever container is open (inside a nest if you're working in one):

- The picture goes on the front track if it fits there. If not, Frame Job adds a new track in front of everything.
- The microphone goes on a new back track named **Microphone**.
- Everything is one undo step, **Add Recording**. Undo removes the clips and media entries but leaves the files on disk, just as undoing Add Media… does.
- The new clips are selected.

If you're in the middle of a drag in that project when the recording stops, Frame Job waits for the drag to end before adding the recording, for up to 20 seconds. After that it gives up, and the panel names the files, which are on disk either way.

If the project you chose was closed while you were recording, the recording opens as a new project instead, and the panel says so.

### As a new project

With **Record Into** set to **New Project**, the recording opens as a new project. The project is named after the recording's file, for example `Screen Recording 2026-09-10 at 14.03.22`, and that's the name Save offers. The canvas takes the movie's size and the frame rate you chose in **Rate**. The first stretch's picture is the project itself, so it has no undo step. Any later stretches and the microphone are added as one undo step, **Add Microphone** for a single stretch with a microphone and **Add Recording Segments** otherwise. A new project made from a recording is unsaved and asks before it closes.

### When the panel comes back

A recording that lands cleanly doesn't bring the panel back. Press ⌥⌘N to open it again. The panel returns on its own, with a note, only when it was on screen when the recording began and there's something to say, for example:

- the recording was stopped from macOS's indicator, or the display slept or went away, or the camera stopped on its own
- the project you chose had closed, so it opened as a new project
- a stretch's movie couldn't be read (for example an empty file from a pause right after a resume) and was left out. Its microphone file still lands on the Microphone track where the picture would have been, and the next picture starts after that gap. The note names the left-out file and the files it kept. Only a recording with no readable movie at all fails, and its note names every file.
- the files didn't finish writing within 10 s of Stop. The note reads "The recording did not finish writing within 10 s." and names the movie and microphone files kept on disk.
- the microphone stopped or failed (the picture still landed)
- a resume failed
- a file couldn't be placed and was added to the media list only
- the recording was saved but couldn't be added. The note reads "The recording was saved at … but could not be added: …" and names every file.

## Files and formats

Recordings are saved in **`~/Movies/Frame Job Recordings/`**, which Frame Job creates the first time it's needed. They're never stored inside the project package. To carry them into the package, use Consolidate (see [Projects and media](projects-and-media.md)).

| File | Name | Format |
|---|---|---|
| Screen recording | `Screen Recording 2026-09-10 at 14.03.22.mov` | QuickTime movie, HEVC (H.264 where HEVC isn't available), with system audio as one stereo 48 kHz track when System Audio is on |
| Its microphone | `Screen Recording 2026-09-10 at 14.03.22 (Microphone).m4a` | Mono 48 kHz AAC, beside the movie |
| Voice-over | `Voice-over 2026-10-02 at 09.15.04.m4a` | Mono 48 kHz AAC |
| Camera recording | `Camera Recording 2026-10-26 at 17.14.33.mov` | QuickTime movie at the camera's format, HEVC (H.264 where HEVC isn't available), no sound of its own; its microphone file sits beside it as for a screen recording |

When a name is already taken, Frame Job adds ` (2)`, ` (3)` and so on.

The microphone is always a separate file from system audio, so you can set the level of your voice and the computer's sound independently. Frame Job measures how far apart the two files started and places the microphone clip to match, trimming its head if it started first.

### Frame rate

macOS delivers a new frame only when something on screen changes, so a mostly still screen gives a file with a low, uneven frame rate. That rate comes from the file itself and isn't a fault. The **Rate** setting is the most frames per second the file can hold. A new project uses that setting as its frame rate, while the media entry keeps the file's real rate. Where the picture stops changing before the sound ends, the last frame is held to the end of the clip.

## Voice-overs (Microphone Only)

To record narration over your edit, choose **Microphone Only** in **Source**:

- **System Audio**, **Show Clicks**, **Size** and **Include Frame Job windows** grey out. Their values are kept for next time.
- **Rate** stays live, because it sets the rate of a new project. **Microphone** and **Record Into** stay live too.
- You must choose a microphone. With **Off**, Record says "Microphone Only records the microphone alone — choose a microphone first."
- Only the Microphone permission is checked. Screen Recording isn't needed.

The countdown and the menu-bar item work as they do for a screen recording. Unlike a screen recording, **the panel stays up** while a voice-over records. Its controls lock, the meter stays live, the footnote shows ● or ❚❚ and the elapsed time, Record reads **Stop**, and a **Pause** / **Resume** button appears beside it. If you close the panel, the voice-over carries on. Stop it from the menu-bar item or **File ▸ Stop Recording** (⌥⌘N), and use the welcome window's **New Recording…** button to bring the panel back.

Each stretch between pauses is its own `.m4a` file. In an open project, every file lands on a **new back track named Microphone**, end to end from the playhead, as one **Add Recording** undo step. It never goes on an existing track. As a new project, the first file is the project (1920×1080 at the chosen rate) and later files follow it on its one track.

While a voice-over records, the panel's note shows a refused **Resume** as it happens: the reason appears there and the voice-over stays paused.

If the microphone stops on its own (for example, it's unplugged), the voice-over ends there and what was recorded still lands, with a note.

## Permissions

A screen recording needs macOS's **Screen Recording** permission (**System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording**). A recording with a microphone, and every voice-over, also needs the **Microphone** permission (**System Settings ▸ Privacy & Security ▸ Microphone**). A camera recording needs the **Camera** permission instead of Screen Recording. Frame Job asks for each one when you press Record, before the countdown begins:

- **Screen Recording.** The first press without it shows macOS's prompt, and the panel explains what to do. Once you've turned it on, relaunch Frame Job if macOS asks you to, then press Record again. Every later press without the permission opens System Settings at the right pane.
- **Microphone.** Asked only when a microphone is chosen. If you've never answered, macOS's prompt appears, and the countdown starts as soon as you allow it. If you denied it before, the press opens System Settings at the Microphone pane.
- **Camera.** Asked only with **Source** set to **Camera** (**System Settings ▸ Privacy & Security ▸ Camera**), before the microphone. If you've never answered, macOS's prompt appears; allowing it goes on to the microphone and the countdown, and denying it leaves the panel idle with a note. If you denied it before, the press opens System Settings at the Camera pane and the note says so.

While a system prompt or System Settings is up, the panel stops floating above other windows, so it doesn't cover them. It floats again on your next press of Record, or when the panel is opened again.

If Frame Job was started from a terminal or another app rather than from the Finder or the Dock, macOS applies that app's permissions instead of Frame Job's. In that case the panel's note names the launching process (by its pid) and says to relaunch with `open -a "Frame Job"`, or to grant the permission to that app (the terminal, for a shell launch).

## For agents: `record_screen`

`record_screen` records for a fixed number of seconds, then lands the result exactly as the panel does: into the target project at its playhead, or as a new project when no project is open. A new project is named after the recording's file and is addressed as `project: <the recording's path>`, the path `get_project` reports for it.

There's no countdown: the recording starts at once, and the call blocks for `seconds` plus about a second, returning once the recording is finished, imported and placed. Slow file writers can hold it up to about 75 s more, and 60 s more for each further stretch of a paused recording. A timeout names the movies, which may still finish on their own.

| Argument | What it does | Default |
|---|---|---|
| `seconds` | How long to record, 1–600 s. Required. | — |
| `source` | `screen`, `voice_over` (the panel's Microphone Only) or `camera` (a camera on its own). | `screen` |
| `camera` | With `source: "camera"`, which camera: its unique id, or its name in any case. | the default camera |
| `camera_format` | With `source: "camera"`, the format to record at: as `camera.format` spells it (`1920x1080@30`), or `WIDTHxHEIGHT` for that size's highest frame rate, or `best`, in any case. | `best` |
| `display` | Index of a shareable display, 0 being the main one. Can't be used with `window`. | 0 |
| `window` | A window id to record on its own. Can't be used with `display`. | — |
| `microphone` | Also record the default microphone to a second file. | false |
| `system_audio` | Record system sound into the movie. | true |
| `show_clicks` | Draw click rings. | false |
| `include_framejob_windows` | Put Frame Job's windows in a display recording. | false |
| `rate` | 30 or 60. | 60 |
| `size` | `nominal` (points) or `best` (pixels). | `nominal` |
| `place` | Put clips on the timeline. `false` adds the recording to the media list only, and the note says to place it with `add_clip {track, media, at}`. In a new project `false` has no effect: the clips are on the timeline anyway, and the note says so. | true |
| `path` | A folder to record into instead of `~/Movies/Frame Job Recordings`. The file name is always the dated one. | — |
| `project` | The open project to land in. | the front project |

With `source: "voice_over"`, the default microphone is implied. The arguments `display`, `window`, `system_audio`, `show_clicks`, `size`, `include_framejob_windows` and `microphone: false` are refused by name.

With `source: "camera"`, Frame Job records a camera on its own, with no screen, into `Camera Recording <date> at <time>.mov`. The camera is the one `camera` names, or else the default camera: the Mac's preferred camera, then the first built-in camera, then the first one connected. It records at the camera's best format (the largest size wider than tall that runs at 30 fps or more, at that format's highest frame rate), or at the format `camera_format` names. A blank or null `camera_format` means best, and a format the camera doesn't have is refused with a list of the camera's formats. `microphone: true` adds the default microphone as a second file, as for a screen recording. The arguments `display`, `window`, `system_audio`, `show_clicks`, `size`, `include_framejob_windows` and `rate` are refused by name, and `camera` and `camera_format` are refused with any other source. An unknown camera is refused with a list of every camera connected, and with none connected the answer is "No camera is connected." A camera recording needs the **Camera** permission (**System Settings ▸ Privacy & Security ▸ Camera**), which is read and never asked for, like the others. The recording starts once the camera has settled at its frame rate (up to a second), and `seconds` counts from its first frame. A camera recording made this way takes the camera from the panel's preview: while it runs, the panel's **Preview** reads "The camera is recording." and the picture comes back when the recording ends. The answer carries `camera` with the camera's `name`, `id` and `format` (for example `1760x1328@30`), plus `problem` when the camera stopped on its own and `note` when it hadn't settled at its rate by the time recording began. The note repeats both. The movie has no sound of its own, so `has_audio` is false. In a new project, the canvas is the file's size at the format's frame rate.

**An agent never asks for a permission.** `record_screen` never shows a system prompt, never opens the window picker and never opens System Settings. The Screen Recording permission, and the Microphone permission when one is needed, must already be granted, usually by pressing Record in the panel once. A missing Screen Recording permission is refused with a sentence naming its System Settings pane. A missing Microphone permission is refused with its status (`notDetermined`, `denied` or `restricted`): when it was never answered, the sentence says to press Record in **File ▸ New Recording…** once; otherwise it names the Microphone pane. When Frame Job was launched from a shell, either refusal also names the launching process (its pid) and says to relaunch with `open -a "Frame Job"` or grant the terminal.

Refusals come in a fixed order. The caller's own argument mistakes come first, so they're answered even without any permission: `seconds` missing or out of range, then `source` and the arguments that source refuses (`camera` and `camera_format` included), `display` with `window`, an unknown `rate` or `size`, `microphone` without the Microphone permission, and a `project` that names nothing open. A screen recording then checks the Screen Recording permission, and only then looks up the display or window. A camera recording looks up the camera first, then its `camera_format`, then checks the Camera permission. When the screen is locked or every display is asleep, the refusal says so: "No display is shareable right now — the console is locked or every display is asleep; nothing can be recorded until one is."

While an agent records, the same menu-bar item appears, so a person at the Mac can pause, resume or stop it. A person's Stop from the menu-bar item or the File menu ends the call early and the recording still lands, with `stopped_by: stopped` and a `duration` shorter than `seconds`. Starting a second recording while one runs is refused with "A recording is already in progress." Pausing shortens what the call records, because `seconds` is wall-clock time.

The answer includes `path` (the first file), `duration` (the total recorded), `segments` (one entry per stretch), `pauses` (how many times Pause was pressed), `stopped_by` (`stopped`, `user_stopped` for macOS's own indicator only, or `system_stopped` when a display slept or a camera stopped on its own), `landed` (`document` or `new_project`), the new media and clip ids, `mic_offset`, `mic_problem` and `unreadable` when relevant, and a `note`. See [MCP](mcp.md) for the full tool reference.

*Agents:* `record_screen` (`seconds`, plus the options above). There is no MCP tool for pause or resume. Those are a person's actions.

## Limits

- The panel records displays, single windows and a camera on its own. A camera records at one of its formats at that format's highest frame rate (not at a lower rate within the format's range), and not at the same time as the screen. There's no keystroke or callout overlay.
- There's no global shortcut to stop. Use the menu-bar item or the File menu.
- While a screen recording runs, the menu-bar item is the only place to pause or resume besides the File menu. If macOS hides the item, for example behind the notch or in a crowded menu bar, **File ▸ Stop Recording** and **File ▸ Pause Recording** still work.
- A recording longer than 9:59:59 shows a label wider than the item was sized for.
- When a project is already at its track limit, a recording that needs a new track can't be added. The files stay on disk and the note names them.
- If the screen is locked or every display is asleep, no display can be shared, so nothing can be recorded until one wakes.

See also: [Audio](audio.md) for setting the microphone and system-audio levels, [Export](export.md) for writing the finished edit, and [Menus and shortcuts](menus-and-shortcuts.md).
