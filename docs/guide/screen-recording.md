# Screen recording

Frame Job records your screen itself. You can record a whole display or a single window, with system audio, your microphone and rings around your clicks, and the recording goes straight into a project. You can also record a camera, on its own or beside the screen as a talking head in the corner, and a voice-over, which is the microphone alone with no picture, at the playhead of the project you're editing. Every recording is an ordinary movie or audio file on disk, and Frame Job imports it the way it imports any other media, so every edit, effect and export works on it.

## Opening the recorder

Choose **File ▸ New Recording…** (⌥⌘N), or click **New Recording…** on the welcome window. A small floating panel titled **New Recording** opens. You don't need a project open.

The panel floats above other windows and doesn't make Frame Job the active app when you click it. That lets you bring the app you want to record to the front and still press Record. It also doesn't hide when you switch to another app. If you open it while Frame Job is in the background, it comes to the front without taking the keyboard, so your typing stays in the app you were using.

In the panel, Return presses **Record** and Esc presses **Close**.

## The panel's controls

| Control | What it does | Default |
|---|---|---|
| **Source** | What to record. Lists one row per connected display by name, then **Window…** (pick one window), then **Camera** (a camera on its own), then **Microphone Only** (a voice-over with no picture). | The display you used last, else the main display |
| **Include Frame Job windows** | Puts Frame Job's own windows, such as the editor and the preview, into a display recording. When it's off, they're left out of the picture. | Off |
| **Record the camera too** | With a display or **Window…** as the source, also records the chosen camera beside the screen (see [A camera beside the screen](#a-camera-beside-the-screen)). It's greyed out, keeping its value, with **Camera** or **Microphone Only**. | Off |
| **Camera** | With **Source** set to **Camera**, or with **Record the camera too** ticked, which camera to record: each connected camera by name, or **None connected**. An iPhone used as a Continuity Camera reads "<name> (Continuity Camera)". It's greyed out otherwise. | The camera you used last, else the Mac's preferred camera, then the first built-in camera, then the first one connected |
| **Format** | With **Source** set to **Camera**, or with **Record the camera too** ticked, the size and frame rate to record at. **Best** comes first and names the camera's best format, for example **Best (1760×1328 at 30 fps)**. Then come the camera's other formats, such as **1920×1080 at 30 fps**: sizes wider than tall first, then square, then taller than wide, each largest first and at its highest frame rate. It's greyed out otherwise. | The format you used last when the chosen camera has it, else Best |
| **Preview** | With **Source** set to **Camera**, or with **Record the camera too** ticked, a live picture of the chosen camera at the chosen format, under Format. It's shown as the movie will record it: not mirrored, the whole picture fitted inside. The row appears only then. | — |
| **Microphone** | **Off**, or one of the connected microphones. A live level meter sits beside it. | Off |
| **Enhance the microphone when it lands** | After the recording lands, runs [Enhance Voice](audio.md#enhance-voice) on the microphone's clips (see [Enhancing the microphone](#enhancing-the-microphone)). It works with any source, and it's greyed out, keeping its value, when **Microphone** is **Off** or a recording is under way. | Off |
| **System Audio** | Records what the system plays, as the movie's own stereo 48 kHz sound track. | On |
| **Show Clicks** | Draws a ring around each mouse click. The pointer itself is always recorded. | Off |
| **Record shortcuts** | With a display or **Window…** as the source, writes each keyboard shortcut you press into the recording's cursor files, and when you type, but never what you type (see [Shortcuts and Input Monitoring](#shortcuts-and-input-monitoring)). Needs the **Input Monitoring** permission. A note under it says what it records. It's greyed out, keeping its value, with **Camera** or **Microphone Only**. | Off |
| **Rate** | **30 fps** or **60 fps**: the most frames per second the file may hold. It's also the frame rate of a new project made from the recording. | 60 fps |
| **Size** | **Nominal (points)** records the display at its point size. **Best (pixels)** records every pixel, which is twice the points on a Retina display. | Nominal (points) |
| **Record Into** | **New Project**, or any open project by name. | The front project, else New Project |

Under Size, a note shows what you'll get for the chosen display, for example `1728×1117 points · 3456×2234 pixels`. For a picked window it reads "the picked window's own size". For Microphone Only it reads "no picture — the microphone alone". For Camera it names the format the camera records at, for example `1760×1328 at 30 fps — the camera's best format` with Format set to Best, `1920×1080 at 30 fps — the chosen format` with a format chosen, or "no camera connected".

The footnote at the bottom left shows where recordings are saved (for example `saved in ~/Movies/Frame Job Recordings`). While a recording runs, it shows the elapsed time instead.

The panel remembers your choices between uses, including the display, microphone, camera, camera format, switches, rate, size and the Include Frame Job windows, Record the camera too, Enhance the microphone when it lands and Record shortcuts boxes. The camera format is one choice for every camera: a camera that doesn't have the remembered format shows Best. It doesn't remember a picked window, the Camera or Microphone Only source (each lasts for the session only), or Record Into. A display, microphone or camera that is no longer connected falls back to the main display, to Off, or to the default camera. While the panel is up and not recording, the Camera and Microphone lists follow the devices you plug in or take away (a change made during a recording waits for it to end). A camera that's removed falls back to the default camera, and when it comes back it's chosen again with its format. Plugging in or removing a device doesn't change what the panel remembers.

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

The camera starts as soon as the panel shows **Camera**, and the **Preview** under Format shows its live picture. Because it's already running, it has settled at its frame rate by the time recording begins, and its light stays on while the panel shows **Camera**. Choosing a display or another source (unless **Record the camera too** is ticked there), or closing the panel, turns it off. The preview changes with the camera and format you choose. Instead of the picture it reads "No camera is connected." with no camera, "The preview shows once Frame Job may use the camera." until you've allowed the Camera permission (showing the panel never asks for it, pressing Record does), or the reason the camera couldn't start. Choosing **Camera** again or reopening the panel tries again. **The panel stays up** while a camera records, as it does for a voice-over: nothing on screen is filmed. Its controls lock, the meter stays live, the footnote shows ● or ❚❚ and the elapsed time, Record reads **Stop**, and a **Pause** / **Resume** button appears beside it. If you close the panel, the recording carries on.

The camera's movie lands like a screen recording's picture: on the front track if it fits, else on a new track in front, with the microphone on a new back track named **Microphone**. As a new project, the canvas is the movie's size at the format's frame rate. If the camera stops on its own (for example, it's unplugged), the recording ends there, what was captured lands, and the note gives the reason followed by "What was captured was added." If the camera hadn't settled at its frame rate when recording began, the note says what rate it ran at.

### A camera beside the screen

Choose a display or **Window…** in **Source**, tick **Record the camera too**, then choose the camera in **Camera** and its size and frame rate in **Format**. Frame Job records the screen and the camera at the same time, for a talking head over a screencast:

- **System Audio**, **Show Clicks**, **Size**, **Include Frame Job windows** and **Rate** stay live and apply to the screen. The note under Size describes the screen.
- The camera starts as soon as the box is ticked, and the **Preview** under Format shows its live picture, so it has settled at its frame rate by the time recording begins. Unticking the box, choosing **Microphone Only**, or closing the panel turns it off.
- With no camera connected, Record says "No camera is connected."
- Pressing Record checks the Screen Recording permission, then the Camera permission, then the Microphone permission when one is chosen, then counts down.
- The panel leaves the screen as for any screen recording, and the menu-bar item is its only control.

The recording lands as `record_screen` with `camera` lands it (see [For agents](#for-agents-record_screen)): each stretch's camera movie, named after its screen movie with ` (Camera)` added, goes on one new track named **Camera** in front of everything, in the bottom-right corner, lined up with the screen. If a tool records a camera beside the screen while the panel is up, the panel's **Preview** reads "The camera is recording." until it ends.

### Microphone Only (voice-over)

See [Voice-overs](#voice-overs-microphone-only) below.

## Recording

1. Set up the panel and press **Record**.
2. Frame Job checks the permissions it needs (see [Permissions](#permissions)).
3. A **3, 2, 1** countdown appears in the panel. During the countdown the Record button reads **Cancel**, and the microphone meter already moves so you can check your level. Click **Cancel** or close the panel to stop the countdown. Nothing is recorded.
4. The recording starts and the panel leaves the screen. With **Source** set to **Camera** or **Microphone Only**, the panel stays up instead.

While the recording starts, the button reads **Starting…**. If the recording hasn't started within 20 seconds, the panel says "The recording did not start within 20 s." and goes back to idle. A Stop pressed while the button reads **Starting…** (for example **File ▸ Stop Recording**) abandons the recording, and the note reads "Stopped before the recording began; nothing was recorded."

Only one recording runs at a time. Pressing Record while another recording runs or is paused, including one an agent started, is refused with "A recording is already in progress."

### The menu-bar item

While a recording runs, Frame Job puts an item in the menu bar: a coral **●** and the elapsed time (`m:ss`, or `h:mm:ss` past an hour). Click it for its menu.

| State | Menu bar shows | Menu |
|---|---|---|
| Recording | ● and the running time | **Pause Recording**, **Stop Recording** |
| Paused | ❚❚ and the time, held still | **Resume Recording**, **Stop Recording** |

While the recording records shortcuts, a keyboard mark **⌨︎** follows the ● or ❚❚, in the menu bar's own colour, and the menu starts with a greyed-out **Recording keyboard shortcuts** row and a separator, recording or paused. This holds for a recording an agent started too.

The item keeps one fixed width, so the other menu-bar items don't shift as the seconds tick. It's a little wider when it shows the keyboard mark. It comes down as soon as the recording stops.

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

With **Record Into** set to **New Project**, the recording opens as a new project. The project is named after the recording's file, for example `Screen Recording 2026-09-10 at 14.03.22`, and that's the name Save offers. The canvas takes the movie's size and the frame rate you chose in **Rate**. The first stretch's picture is the project itself, so it has no undo step. Any later stretches, the microphone and a camera recorded beside the screen are added as one undo step: for a single stretch, **Add Microphone** with a microphone, **Add Camera** with a camera, or **Add Camera and Microphone** with both, and **Add Recording Segments** otherwise. A new project made from a recording is unsaved and asks before it closes.

### Enhancing the microphone

With **Enhance the microphone when it lands** ticked, the recording lands exactly as it would otherwise, and then Frame Job runs [Enhance Voice](audio.md#enhance-voice) on the microphone's clips: each stretch's microphone file, or a voice-over's files. It never touches the picture, a camera or the system audio. Enhance Voice needs the microphone's sound analysed first (its loudness and its speech), which takes a few seconds after the files land; it then runs under the **Measuring Sound** sheet, at Normalize's target loudness, and its settings appear in the clip's Sound tab.

It's its own undo step, **Enhance Voice**, after the landing's. Edit ▸ Undo first reads **Undo Enhance Voice**, which takes the processing off and keeps the recording; in an open project the next undo is **Undo Add Recording**. In a new project the next is the landing's own step (**Add Microphone**, **Add Camera and Microphone** or **Add Recording Segments**), or nothing when the recording is a single file, which is the project itself.

It waits while you drag in the project, while a sheet is up on its window, or while you're inside another nest than the one the recording landed in. Pressing **Cancel** on the Measuring Sound sheet leaves the clips as they landed. When there's nothing to enhance (a silent microphone, for example), or the sound wasn't analysed within 5 minutes, the reason appears at the foot of the inspector, and you can select the clip and choose **Clip ▸ Enhance Voice** yourself.

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
| Its cursor | `Screen Recording 2026-09-10 at 14.03.22.fjcursor` | Beside every screen recording's movie (a display, a window or a picked window), one per stretch between pauses: where the pointer was about 120 times a second, every click and scroll, and how the recorded area sat on the screen. The pointer is still drawn into the movie as well. If the file can't be written, the recording still lands and the panel's note says why |

When a name is already taken, Frame Job adds ` (2)`, ` (3)` and so on.

The microphone is always a separate file from system audio, so you can set the level of your voice and the computer's sound independently. Frame Job measures how far apart the two files started and places the microphone clip to match, trimming its head if it started first.

### Frame rate

macOS delivers a new frame only when something on screen changes, so a mostly still screen gives a file with a low, uneven frame rate. That rate comes from the file itself and isn't a fault. The **Rate** setting is the most frames per second the file can hold. A new project uses that setting as its frame rate, while the media entry keeps the file's real rate. Where the picture stops changing before the sound ends, the last frame is held to the end of the clip.

## The cursor

A recording's cursor file (`<name>.fjcursor`, beside its movie) travels with the movie into your project:

- **When a recording lands**, each stretch's movie gets its own cursor file.
- **When you import a movie**, by **File ▸ Add Media…**, a drop, opening it, or an agent's `import_media`, Frame Job looks beside it for a file with the same name ending in `.fjcursor`. It takes the file only when the file reads as a cursor file and was made for a movie of exactly this movie's size. A file that is missing, damaged or made for another size is left alone, and the movie imports without it. A copy Frame Job makes of a WebM or Matroska file is not looked beside.
- **When you relink a movie** (**Relink…**, the Media tab, or an agent's `relink_media`), Frame Job takes the cursor file beside the new movie. If there is none, it keeps the cursor file the media already had, as long as that file is still there and the new movie is the same size. Otherwise the media has no cursor file after the relink.
- **When you consolidate**, the cursor file is copied into the package beside its movie, and a moved package finds it there again (see [Consolidate Media](projects-and-media.md#consolidate-media)).

**On the Media tab.** Select a recording in the list and its **Cursor** section names its cursor file, or says "No cursor file", or adds "— missing" when the file has gone. **Locate…** chooses a `.fjcursor` file for it: Frame Job takes it only when it reads as a cursor file made for a movie of exactly this size, and otherwise says why and changes nothing (undo name "Locate Cursor File"). **Remove** forgets the cursor file, which stays on disk (undo name "Remove Cursor File").

*Agents:* `set_media_cursor` attaches, moves or removes a cursor file as **Locate…** and **Remove** do. `get_cursor_events` reads a recording's clicks, scrolls, shortcuts, typing stretches and pointer path, in the file's own time or in a clip's, with each click's place in the clip's zoom region frame.

**The Cursor section.** A clip whose movie has a cursor file the picture doesn't already show gets a **Cursor** section on the Clip tab's **Picture** sub-tab, after **Background**. It starts closed; its summary says **off**, **on** or **arrow**, with **+ ripples** when clicks ripple. Each row is its own undo step:

| Row | What it does | Range |
|---|---|---|
| **Show cursor** | Draws the pointer from the file over the clip. On by default. | on, off |
| **Size** | How big the pointer is drawn. Quick picks 50, 100, 150, 200 and 400 %; the slider runs to 400 %, the field to 800 %. | 25–800 % |
| **Style** | **As recorded** draws the pointer images the file recorded. **Arrow** draws Frame Job's own arrow instead. | As recorded, Arrow |
| **Smoothing** | Calms a shaky path. The pointer still passes exactly through every click, at the moment of the click, and still holds still where it held still. | Off, Light, Medium, Strong |
| **Hide when idle** | Fades the pointer out after this long with no movement or click, and brings it back just before it next moves. | Never, 1, 2, 3, 5, 10 s |
| **Clicks** | **Ripple** draws a ring growing out of every click. | None, Ripple |
| **Ripple color** | The ring's colour, with opacity. Live only while Clicks is Ripple. | any colour |
| **Ripple size** | How big the ring grows. Live only while Clicks is Ripple. | 25–400 % |

**Polish** sets Smoothing to Medium and Hide when idle to 3 s in one step.

With an action selected, **Size** and **Ripple size** animate across it. **Show cursor**, **Style**, **Clicks** and **Ripple color** switch at the action's end. **Smoothing**, **Hide when idle** and **Polish** belong to the clip, not to an action: their rows show ⊘ and they always change the clip itself. A clip with no cursor settings yet gets them the first time you change any row but Smoothing or Hide when idle with an action selected, so Size and Ripple size can animate rather than jump. Selecting clips that disagree shows a row mixed. **Reset** puts every row back to its default.

**The arrow.** Frame Job's own arrow is drawn crisp at any size, at the size of a standard pointer times **Size**. It is also what a clip draws when its cursor file recorded no pointer images, whichever **Style** is chosen.

**Paste Attributes** (⌥⌘V) carries a clip's cursor settings to another clip, with the rest of its picture settings.

The recorder still draws the pointer into the movie itself, so its cursor files say the pointer is already in the picture. A recording therefore shows no **Cursor** section yet, and nothing is drawn twice.

### Shortcuts and Input Monitoring

With **Record shortcuts** ticked, a display or window recording also writes your keyboard into each stretch's cursor file, in two kinds:

- **A shortcut**, with its keys spelled out, for example `cmd+shift+4`. A key you press while holding ⌘ or ⌃ is a shortcut, and so is ⌥ with an arrow, Delete, Forward Delete, Return, Enter, Tab or Esc. ⇧ on its own never makes one, and neither does ⌥ with any other key (⌥E types é). The modifiers come first, in the order `cmd`, `ctrl`, `opt`, `shift`, then the key: a named key (`return`, `tab`, `space`, `left`, `f5` and so on) or the character the key types with no modifier, lowercased (`+` is spelled `plus`).
- **A typing mark**: the time of every other key you press, and of every key held down until it repeats. A typing mark never says which key it was. Frame Job doesn't read the character of a typed key at all.

**Nothing is recorded while any app holds secure input**, as a password field does: not a shortcut, not even a typing mark. A password field that doesn't turn secure input on, such as a Terminal `sudo` prompt with **Secure Keyboard Entry** off, is recorded as typing marks only, with no characters. Keys pressed while the recording is paused aren't recorded.

Recording keys needs macOS's **Input Monitoring** permission (see [Permissions](#permissions)). While it records, the menu-bar item shows the keyboard mark (see [The menu-bar item](#the-menu-bar-item)). *Agents:* `record_screen` with `keys: "shortcuts"`, and `get_cursor_events` reads the shortcuts and typing back.

## Auto Zoom

**Clip ▸ Auto Zoom…** zooms a screen recording in where things happen, from its cursor file: it arrives just before each click, stays while you keep working there, and zooms back out once you stop. Every zoom it makes is an ordinary action, like one from [Zoom to Region](motion-and-transitions.md#zoom-to-a-region), so you can move, retime, change or delete any of them afterwards. The whole plan is one undo step, "Auto Zoom".

Select one or more clips whose movies have cursor files (see [The cursor](#the-cursor)) and choose the item. It works inside an open nest too. It is greyed when a selected clip is not a movie with a cursor file.

| Control | What it does | Default |
|---|---|---|
| **Zoom** | How far in, as a multiple of the clip's own size. | 2× (1.25–4) |
| **Arrive** | How many seconds before a click the zoom-in starts. | 0.6 s (0.2–2) |
| **Stay** | How long the zoom holds after the last click or typing before it zooms back out. | 2.5 s (0.5–10) |
| **Follow the cursor while zoomed** | Pans along when the pointer stays near the edge of the zoomed view. | on |
| **Zoom on typing** | Zooms in on stretches of typing too, aimed at the last click before them. Greyed when the recording holds no typing (see [Shortcuts and Input Monitoring](#shortcuts-and-input-monitoring)). | on when there is typing |
| **Replace existing zooms** | Removes the clips' existing zooms first. Off keeps your own zooms. | off |

The sheet reads the cursor files first ("Reading cursor files…"), then says what Zoom would do, for example "5 zooms in 2 visits." and, when some planned zooms meet an action already on the clip, "1 dropped where an action is already set." It says so instead when a clip can't be planned. Frame Job remembers Zoom, Arrive, Stay, Follow and Replace for next time, but only once you change one; Zoom on typing is never remembered.

How it plans:

- **A visit** starts at a click (any button) or a stretch of typing. A later click within **Stay** of the last activity joins it; a longer gap, or scrolling, ends it. A visit is a zoom-in that arrives **Arrive** seconds before its first click, a pan to each later click that falls outside the middle 60 % of the view, and a 0.8 s zoom back out. When one visit would zoom out less than a second before the next zooms in, it pans across instead.
- **Follow** adds a half-second pan when the pointer stays outside the middle 70 % of the view for 0.3 s, at most one a second.
- **The view** keeps the canvas's shape and never shows past the edge of the picture: near a corner it stops at the corner.
- **Split clips.** The halves of a split clip are planned as one recording, and every zoom out goes back to the first half's placement. No zoom crosses a cut. A zoom held across a cut carries into the next half, which starts already zoomed; when that half has an action of its own there, or wasn't selected, the zoom goes back out at the cut instead.
- **Your own actions.** A planned zoom that would overlap an action already on the clip is left out. With **Replace existing zooms**, the clips' existing zooms are removed first — only zooms, never a speed change, a fade or anything else.

A clip placed smaller than the canvas (side by side with a camera, or a picture in picture) is refused: "Clip C is placed smaller than the canvas; a zoom would fill the canvas. Nest it (Clip ▸ Nest) and run Auto Zoom inside the nest." Nest it, open the nest and run Auto Zoom there; the zooms then fill the nest. A clip that plays reversed is refused too.

*Agents:* `auto_zoom` plans and applies the same zooms, with the sheet's settings as arguments.

## Shortcut overlays

**Clip ▸ Add Shortcut Overlays** shows each keyboard shortcut you pressed while recording as keycaps on screen, at the moment you pressed it. It needs a recording made with **Record shortcuts** on (see [Shortcuts and Input Monitoring](#shortcuts-and-input-monitoring)); only shortcuts are recorded, never what you typed.

Select one or more clips whose movies have cursor files and choose the item. There is no sheet: it reads the cursor files and places one **Keyboard keys** graphic clip per shortcut, at the bottom of the picture in the dark theme, each shown for 1.5 s. The whole change is one undo step, "Add Shortcut Overlays". It works inside an open nest too, and is greyed when a selected clip is not a movie with a cursor file.

- **Where they go.** On the front-most track named "Shortcuts" when it is in front of the clips, unlocked, shown, not a matte and free where the overlays go; otherwise on a new "Shortcuts" track at the front.
- **How long.** Each overlay lasts 1.5 s, and never less than the keycaps need to press in turn and fade out: (10 × keys + 25) frames, so 1.5 s for a two-key shortcut at 30 fps.
- **Repeats.** Pressing the same shortcut again before its overlay ends keeps it up 1.5 s past the last press, labelled "×2", "×3" and so on.
- **Shortcuts close together.** A different shortcut pressed while one is showing takes over once the first has had its minimum. When that would show it more than half a second late, it is left out, and a sheet says how many were: "1 shortcut came too close to show."
- **The graphic.** The overlays are drawn by the project's copy of the bundled Keyboard keys template, written into the project's graphics the first time and reused after; if you have edited that copy, a fresh one is written beside it. Change a clip's look in its Graphic sub-tab like any graphic.

When no shortcut was recorded in the selected clips, a sheet says "No shortcut was recorded in the selected clips' played windows, so nothing was added." A clip that plays reversed is refused.

*Agents:* `add_shortcut_overlays` places the same overlays, and takes `duration`, `position` (bottom, center, top), `theme` (dark, light) and a `from`/`to` range.

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

A screen recording needs macOS's **Screen Recording** permission (**System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording**). A recording with a microphone, and every voice-over, also needs the **Microphone** permission (**System Settings ▸ Privacy & Security ▸ Microphone**). A camera recording needs the **Camera** permission instead of Screen Recording, and a screen recording with **Record the camera too** needs both. Frame Job asks for each one when you press Record, before the countdown begins:

- **Screen Recording.** The first press without it shows macOS's prompt, and the panel explains what to do. Once you've turned it on, relaunch Frame Job if macOS asks you to, then press Record again. Every later press without the permission opens System Settings at the right pane.
- **Microphone.** Asked only when a microphone is chosen. If you've never answered, macOS's prompt appears, and the countdown starts as soon as you allow it. If you denied it before, the press opens System Settings at the Microphone pane.
- **Input Monitoring.** Asked only with **Record shortcuts** ticked and a display or window as the source (**System Settings ▸ Privacy & Security ▸ Input Monitoring**), after Screen Recording and before the camera and the microphone. macOS shows no prompt for it, and Frame Job isn't in that pane's list until you add it, so the first press both asks and opens System Settings at the Input Monitoring pane; the note says "Input Monitoring is not granted to Frame Job. Turn it on in System Settings ▸ Privacy & Security ▸ Input Monitoring. If Frame Job is not in its list, add it with +." Turn Frame Job on there (add it with **+** if it isn't listed) and press Record again. Every later press without the permission opens the pane again. No relaunch is needed.
- **Camera.** Asked only with **Source** set to **Camera**, or with **Record the camera too** ticked (**System Settings ▸ Privacy & Security ▸ Camera**), after Screen Recording when there is a screen and before the microphone. If you've never answered, macOS's prompt appears; allowing it goes on to the microphone and the countdown, and denying it leaves the panel idle with a note. If you denied it before, the press opens System Settings at the Camera pane and the note says so.

While a system prompt or System Settings is up, the panel stops floating above other windows, so it doesn't cover them. It floats again on your next press of Record, or when the panel is opened again.

If Frame Job was started from a terminal or another app rather than from the Finder or the Dock, macOS applies that app's permissions instead of Frame Job's. In that case the panel's note names the launching process (by its pid) and says to relaunch with `open -a "Frame Job"`, or to grant the permission to that app (the terminal, for a shell launch).

## For agents: `record_screen`

`record_screen` records for a fixed number of seconds, then lands the result exactly as the panel does: into the target project at its playhead, or as a new project when no project is open. A new project is named after the recording's file and is addressed as `project: <the recording's path>`, the path `get_project` reports for it.

There's no countdown: the recording starts at once, and the call blocks for `seconds` plus about a second, returning once the recording is finished, imported and placed. Slow file writers can hold it up to about 75 s more, and 60 s more for each further stretch of a paused recording. A timeout names the movies, which may still finish on their own.

| Argument | What it does | Default |
|---|---|---|
| `seconds` | How long to record, 1–600 s. Required. | — |
| `source` | `screen`, `voice_over` (the panel's Microphone Only) or `camera` (a camera on its own). | `screen` |
| `camera` | With `source: "camera"`, which camera: its unique id, or its name in any case. With `source: "screen"`, a camera to record beside the screen (below). | the default camera with `source: "camera"`; none with `source: "screen"` |
| `camera_format` | With `source: "camera"`, or with `camera` beside the screen, the format to record at: as `camera.format` spells it (`1920x1080@30`), or `WIDTHxHEIGHT` for that size's highest frame rate, or `best`, in any case. | `best` |
| `display` | Index of a shareable display, 0 being the main one. Can't be used with `window`. | 0 |
| `window` | A window id to record on its own. Can't be used with `display`. | — |
| `microphone` | Also record the default microphone to a second file. | false |
| `system_audio` | Record system sound into the movie. | true |
| `show_clicks` | Draw click rings. | false |
| `include_framejob_windows` | Put Frame Job's windows in a display recording. | false |
| `keys` | `off`, or `shortcuts`: write each shortcut, spelled, and a time-only typing mark for every other key into the cursor files, as the panel's **Record shortcuts** does (see [Shortcuts and Input Monitoring](#shortcuts-and-input-monitoring)). `shortcuts` needs the Input Monitoring permission. | `off` |
| `rate` | 30 or 60. | 60 |
| `size` | `nominal` (points) or `best` (pixels). | `nominal` |
| `place` | Put clips on the timeline. `false` adds the recording to the media list only, and the note says to place it with `add_clip {track, media, at}`. In a new project `false` has no effect: the clips are on the timeline anyway, and the note says so. | true |
| `enhance` | After the landing, run `enhance_voice` on the microphone's clips at −16 LUFS as its own undo step (below). Needs `microphone: true` (or `source: "voice_over"`) and `place: true`. | false |
| `path` | A folder to record into instead of `~/Movies/Frame Job Recordings`. The file name is always the dated one. | — |
| `project` | The open project to land in. | the front project |

With `source: "voice_over"`, the default microphone is implied. The arguments `display`, `window`, `system_audio`, `show_clicks`, `size`, `include_framejob_windows`, `keys` and `microphone: false` are refused by name.

With `source: "camera"`, Frame Job records a camera on its own, with no screen, into `Camera Recording <date> at <time>.mov`. The camera is the one `camera` names, or else the default camera: the Mac's preferred camera, then the first built-in camera, then the first one connected. It records at the camera's best format (the largest size wider than tall that runs at 30 fps or more, at that format's highest frame rate), or at the format `camera_format` names. A blank or null `camera_format` means best, and a format the camera doesn't have is refused with a list of the camera's formats. `microphone: true` adds the default microphone as a second file, as for a screen recording. The arguments `display`, `window`, `system_audio`, `show_clicks`, `size`, `include_framejob_windows`, `keys` and `rate` are refused by name, and `camera` and `camera_format` are refused with `source: "voice_over"`. An unknown camera is refused with a list of every camera connected, and with none connected the answer is "No camera is connected." A camera recording needs the **Camera** permission (**System Settings ▸ Privacy & Security ▸ Camera**), which is read and never asked for, like the others. The recording starts once the camera has settled at its frame rate (up to a second), and `seconds` counts from its first frame. A camera recording made this way takes the camera from the panel's preview: while it runs, the panel's **Preview** reads "The camera is recording." and the picture comes back when the recording ends. The answer carries `camera` with the camera's `name`, `id` and `format` (for example `1760x1328@30`), plus `problem` when the camera stopped on its own and `note` when it hadn't settled at its rate by the time recording began. The note repeats both. The movie has no sound of its own, so `has_audio` is false. In a new project, the canvas is the file's size at the format's frame rate.

With `source: "screen"` (the default) and `camera`, Frame Job records that camera **beside the screen**, at the same time, for a talking head over a screencast. Each stretch of the recording gets a camera movie named after its screen movie, for example `Screen Recording 2026-10-26 at 17.14.33 (Camera).mov`, at the camera's best format or the one `camera_format` names (`camera_format` without `camera` is refused: "With source screen, camera_format needs camera — name the camera to record beside the screen."). The camera files land in the same undo step as the screen's, on one new track named **Camera** in front of everything. Each camera clip starts where its screen clip starts, moved by that stretch's measured `camera_offset`: the camera usually starts a little before the screen, so the clip's first frames are trimmed off rather than the clip starting early, and a camera clip never starts before its screen clip or overlaps the one before it. Each camera clip is placed in the **bottom-right corner**: scaled to fit a box a quarter of the canvas wide and a third of it tall, inside the 90 % guide of **View ▸ Safe Areas**. It's an ordinary clip, so you can move or resize it. The microphone, when asked for, lands on its own track as usual. With `place: false` the camera files are added to the media list only. In a new project, the first screen movie is the document, and its camera (with any microphone) is one undo step named **Add Camera**, or **Add Camera and Microphone**. Each entry of `segments` then also carries `camera_path`, `camera_duration` and `camera_offset` (ticks, positive when the camera began after the screen), `camera_problem` and `camera_note` when something went wrong with that stretch's camera, and `camera_media` and `camera_clip` when known. The camera is looked up, and the Camera permission checked, before the Screen Recording permission. The wait after the recording allows about 105 s more, and 90 s more for each further stretch, because each camera file is read too, and a timeout names the camera files after the movies. The panel's **Record the camera too** box, with a display or a window, makes the same recording.

**An agent never asks for a permission.** `record_screen` never shows a system prompt, never opens the window picker and never opens System Settings. The Screen Recording permission, and the Microphone permission when one is needed, must already be granted, usually by pressing Record in the panel once. A missing Screen Recording permission is refused with a sentence naming its System Settings pane. A missing Microphone permission is refused with its status (`notDetermined`, `denied` or `restricted`): when it was never answered, the sentence says to press Record in **File ▸ New Recording…** once; otherwise it names the Microphone pane. With `keys: "shortcuts"`, a missing Input Monitoring permission is refused with "Input Monitoring is not granted to Frame Job. Turn it on in System Settings ▸ Privacy & Security ▸ Input Monitoring." The order is the caller's own mistakes first (`keys` outside `off` and `shortcuts` among them, read after `include_framejob_windows`), then the Microphone permission, then Input Monitoring, then `project`, then the Camera and Screen Recording permissions. When Frame Job was launched from a shell, each refusal also names the launching process (its pid) and says to relaunch with `open -a "Frame Job"` or grant the terminal.

Refusals come in a fixed order. The caller's own argument mistakes come first, so they're answered even without any permission: `seconds` missing or out of range, then `source` and the arguments that source refuses (`camera` and `camera_format` included), `display` with `window`, an unknown `rate` or `size`, `enhance` without a microphone or with `place: false`, `microphone` without the Microphone permission, and a `project` that names nothing open. A camera recording, or a screen recording with `camera`, then looks up the camera, then its `camera_format`, then checks the Camera permission. A screen recording then checks the Screen Recording permission, and only then looks up the display or window. When the screen is locked or every display is asleep, the refusal says so: "No display is shareable right now — the console is locked or every display is asleep; nothing can be recorded until one is."

While an agent records, the same menu-bar item appears, so a person at the Mac can pause, resume or stop it. A person's Stop from the menu-bar item or the File menu ends the call early and the recording still lands, with `stopped_by: stopped` and a `duration` shorter than `seconds`. Starting a second recording while one runs is refused with "A recording is already in progress." Pausing shortens what the call records, because `seconds` is wall-clock time.

The answer includes `path` (the first file), `duration` (the total recorded), `segments` (one entry per stretch), `pauses` (how many times Pause was pressed), `stopped_by` (`stopped`, `user_stopped` for macOS's own indicator only, or `system_stopped` when a display slept or a camera stopped on its own), `landed` (`document` or `new_project`), the new media and clip ids, `mic_offset`, `mic_problem` and `unreadable` when relevant, and a `note`. See [MCP](mcp.md) for the full tool reference.

With `enhance: true`, the call lands the recording as usual and then waits, up to 5 minutes, for the microphone's sound to be analysed, then runs `enhance_voice`'s own steps on the microphone's clips at −16 LUFS (an agent's target never comes from the Normalize row; call `enhance_voice {target_lufs}` afterwards for another). It's its own undo step, **Enhance Voice**, as in [Enhancing the microphone](#enhancing-the-microphone). The answer then also carries `enhance`, the answer `enhance_voice` gives, or `enhance_error`, a sentence saying why it didn't run: nothing measurable (`Nothing could be enhanced. …`), no microphone clip on the timeline, or not analysed within 5 minutes. `project` is read after it. `enhance` is checked right after `place`, before any permission: `enhance: true` without a microphone is refused with "enhance: true enhances the microphone's clip, so it needs microphone: true (or source voice_over).", and with `place: false` with "enhance: true needs place: true — with place: false the microphone lands as media with no clip to enhance."

*Agents:* `record_screen` (`seconds`, plus the options above). There is no MCP tool for pause or resume. Those are a person's actions.

## Limits

- The panel records displays, single windows, a camera on its own, and a camera beside a display or a window. A camera records at one of its formats at that format's highest frame rate (not at a lower rate within the format's range). The panel places a camera beside the screen in the bottom-right corner; it has no control for another corner, scale or inset. There's no keystroke or callout overlay.
- When a stretch of a screen recording is left out because its movie can't be read, its camera file stays on disk and is named with its other kept files, but it isn't added to the project. Only that stretch's microphone is.
- There's no global shortcut to stop. Use the menu-bar item or the File menu.
- While a screen recording runs, the menu-bar item is the only place to pause or resume besides the File menu. If macOS hides the item, for example behind the notch or in a crowded menu bar, **File ▸ Stop Recording** and **File ▸ Pause Recording** still work.
- A recording longer than 9:59:59 shows a label wider than the item was sized for.
- When a project is already at its track limit, a recording that needs a new track can't be added. The files stay on disk and the note names them.
- If the screen is locked or every display is asleep, no display can be shared, so nothing can be recorded until one wakes.
- Record shortcuts writes nothing while any app holds secure input, and a typing mark is a time alone: there's no mode that records what you type.

See also: [Audio](audio.md) for setting the microphone and system-audio levels, [Export](export.md) for writing the finished edit, and [Menus and shortcuts](menus-and-shortcuts.md).
