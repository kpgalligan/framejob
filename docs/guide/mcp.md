# Driving Frame Job from an AI agent (MCP)

Frame Job serves its whole editor as MCP tools, so an AI agent such as
Claude Code can open projects, cut, style, check its work frame by frame and
export, the same way you do in the window. Every edit an agent makes goes
through the same place your own clicks go: it shows in the window at once,
marks the document edited, and can be undone with ⌘Z. This page covers
connecting a client, how calls behave, and the full list of tools.

## How an agent reaches Frame Job

Frame Job listens on a local Unix socket that it opens every time it
launches:

```
~/Library/Application Support/Frame Job/Agent/agent.sock
```

The socket serves MCP as streamable HTTP: each request is one JSON-RPC
`POST /mcp`, answered with a single JSON response. A client that can speak
HTTP over a Unix socket can connect to it directly. Most MCP clients start
a stdio server instead, and for them the bundle carries **framejob-mcp**, a
small stdio MCP server:

```
Frame Job.app/Contents/Helpers/framejob-mcp
```

The helper does three things:

- **It starts a session without opening Frame Job.** It answers
  `initialize` and `ping` itself, and none of `initialize`, `ping` or
  `tools/list` ever launches the app.
- **It lists the tools even when Frame Job cannot answer.** `tools/list`
  asks the running app first. When the app is not running, or does not
  answer within 5 seconds (for example while another client's long call
  holds it), the helper answers from a copy of the catalog stored in the
  bundle, so a client can start up and see every tool with nothing on
  screen.
- **It opens Frame Job on the first tool call.** If a call finds the app
  not running, the helper launches its own copy of Frame Job in the
  background (it does not come to the front) and waits up to 60 seconds for
  it to start listening. Several clients calling at once start only one copy.
  Everything else is forwarded to the running app, and a long call, such as
  an export or a screen recording, is never timed out by the helper.

If the tool list a client was given from the stored copy differs from the
running app's, the helper tells the client that the list changed so it can
read it again.

Always register the helper at its path inside the app bundle. The helper
launches only the Frame Job it belongs to, so a copy moved out of the
bundle can neither read the stored tool list nor launch Frame Job; its
calls answer a sentence naming the executable instead.

### Who can connect

The socket's folder is readable only by you (`0700`) and the socket itself
is `0600`, so only programs running under your own account can connect —
and any of them can while Frame Job is running. If the folder's permissions
are wrong, Frame Job does not open the socket at all rather than loosen them.

Only one copy of Frame Job holds the socket. A second copy launched while
the first is running leaves it to the first. A socket file left behind by a
copy that crashed (one that no longer answers) is removed and replaced
automatically; only a socket that answers counts as another copy.

When Frame Job does not open the socket — another copy answers there, or the
folder's permissions or owner are wrong — Console shows a line starting
"Frame Job agent socket not bound:" followed by the reason.

## Connect a client

### Settings ▸ MCP

**Frame Job ▸ Settings…** (⌘,) opens with the **MCP** section at the top. It
explains how a client reaches Frame Job, shows the full path of this copy's
`framejob-mcp` (selectable, so you can copy it), and has one button:

| Control | What it does |
|---|---|
| **Copy MCP Command** | Puts the Claude Code registration command for this copy of Frame Job on the clipboard. The status line then reads "Copied. Paste it into Terminal and press Return." |

The command always names the helper inside the copy of Frame Job you ran it
from, so a copy in `~/Applications` or a build folder registers itself. If
the helper is missing from the bundle, the button is dimmed and the status
line says "framejob-mcp is missing from this copy of Frame Job."

Pressing the button is not an edit, so it has no tool of its own.

### Claude Code

Paste the copied command into Terminal. For a copy in `/Applications` it is:

```sh
claude mcp add --scope user framejob -- '/Applications/Frame Job.app/Contents/Helpers/framejob-mcp'
```

`--scope user` makes Frame Job's tools available in every Claude Code
project.

### Claude Desktop and other clients

Any MCP client that starts a stdio server can use the same helper. For
Claude Desktop, add it to `claude_desktop_config.json`:

```json
{"mcpServers":{"framejob":{"command":"/Applications/Frame Job.app/Contents/Helpers/framejob-mcp"}}}
```

Use the path the MCP section shows if your copy lives somewhere else.

### Testing a second copy

This is for testing, not everyday use. Setting the environment variable
`RC_AGENT_SOCKET` to a path, both for Frame Job and for `framejob-mcp`, moves
the socket there, so a test copy of Frame Job is kept apart from your
everyday one.

## How tool calls behave

### One call at a time

Frame Job runs one tool call at a time, across every connected client and
the [Assistant](assistant.md). A call made while you are dragging something
in the window (a clip, a canvas handle, an inspector slider) waits until you
let go of the mouse, then runs as its own undo step after the drag's.

### Never a question

A tool call never puts up an alert or asks permission. Where the app would
normally ask you something, the call answers instead:

- An import that would offer to convert an unsupported file with ffmpeg
  treats the offer as declined and answers with the reason.
- `record_screen` never asks for the Screen Recording, Microphone or Camera grant.
  A missing grant is refused, naming the System Settings pane. A Frame Job
  started from a terminal runs under the terminal's grants, not the app's.
- `close_project` refuses a project with unsaved changes unless it is
  passed `discard: true`, and refuses a window with a sheet open.

### Which project a call acts on

Every tool takes an optional `project`: the path of an open project, as
`get_project` reports it. Without it, the call goes to the frontmost open
project. A path that names no open project is refused, and a call with no
project open at all is told to call `open_project` or `new_project` first.

### Units and ids

- **Times are ticks, 600 000 per second.** One second is 600000, and one
  frame at 30 fps is 20000. Every time you send is rounded to the project's
  frame grid.
- **Clip, track, marker and media ids share one number space**, so an id
  names one thing on its own. `get_project` lists them.
- **`tracks[0]` is the back of the layer stack**, the bottom lane of the
  timeline. A higher index draws in front.
- **Clip and canvas colours are four numbers**, `[r, g, b, a]`, each 0–1.
  Three numbers, or a component out of range, is refused rather than filled
  in or clamped. A chroma key's colour, `video.chroma.key`, is `[r, g, b]`.
  Other colours are spelled differently: a marker's `color` and a clip's
  `label` are colour names such as `"red"`, and a graphic's colour props are
  hex strings such as `"#ff5a36"`.
- **A boolean** may also be sent as `"true"`, `"1"`, `"false"` or `"0"`.
- **Two shorthands:** `add_text_clip`'s `text` may be a plain string (the
  words), and `add_shape_clip`'s `shape` a plain string (the kind).
- **Some keys must be sent even when null**, because null means something:
  `set_transition`'s `kind` (null removes the transition) and
  `add_zoom_action`'s `region` (null zooms back out). Leaving either out is
  refused.
- **Speed rates are clamped, not refused.** `set_speed` and
  `add_speed_ramp` bring a `rate` outside ×0.1–×1000 into that range; a rate
  of zero or less is refused.
- **No list argument may be empty.** An empty `clips`, `ranges`
  (`ripple_delete_ranges`) or `groups` (`paste_attributes`) is refused by
  name. A frame-rate term of 0 in `set_canvas`'s `fps` is refused too.

### Patches

The property tools (`set_video`, `set_audio`, `set_text`, `set_shape`,
`set_graphic`, `set_clip`, `set_action_end`) take a `patch` object, and it
merges into what the clip already has:

- Keys you leave out keep their values, at every depth. A patch of just
  `{shadow: {blur: 20}}` keeps the shadow's colour, angle and distance.
- A key set to `null` clears it.
- A list replaces the whole list (`filters`, for example: send the whole
  stack, or `[]` to clear it).
- An unknown key or a wrong value is refused, naming its dotted path and the
  value you sent, such as `filters[1].kind`. Nothing is dropped, corrected or
  clamped on the way.

### What a call answers

Every answer comes back in band, as the tool's result, so a model can read it
and correct itself. A refused or invalid call is an ordinary tool result
with `isError: true` whose text is the sentence, never a transport or
JSON-RPC error. A call that changed nothing is marked the same way; its
sentence, below, says that nothing was wrong. Only an MCP method the server
does not know gets a JSON-RPC "method not found".

**An edit that landed** answers `ok: true`, the ids it created (`new_clips`,
`new_tracks`, `new_markers`, `new_media`, only those that apply), anything
the tool adds of its own, and a short `project` summary: name, path, width,
height, fps, duration, playhead, counts of tracks, clips, markers and media,
the selection, `unsaved_changes`, and `missing_media` when a file is gone.
Every edit is exactly one undo step, however many clips it touched.

**An edit that did not happen** is one of two kinds, and the answer says
which. Neither leaves an undo step, so it is safe to retry.

| Answer | Meaning |
|---|---|
| "*Step* made no change: the project is already in that state." | Nothing was wrong. The project already says what you asked. |
| "*Step* was refused at *op*: *reason*" | A rule declined the edit. The reason names the op and what you can act on — which track is locked, which clips still use a media file, how far two clips would overlap, or the argument that lets the call through (`with_clips: true`, `ripple: true`). |

**An argument the tool does not take** is refused before anything runs:
"*tool* does not take *x*. It takes *a*, *b* and *c*." A value a tool cannot
read is refused by name rather than ignored.

## Editing inside a nest

A nest is a group of clips collapsed into one clip (**Clip ▸ Nest**, ⌘G;
see [Editing](editing.md)). An agent can edit inside one two ways.

**Open it, as you would.** `set_scope` is double-clicking a nest clip, or
**Clip ▸ Open Nest** (⌘↓). Give it the `nest` id or the `clip` that shows
it, never both:

- `clip` is the precise choice, since two clips can show one nest and each
  measures the times inside from its own start. A clip that shows no nest is
  refused.
- `nest` opens only a nest that a clip on the timeline shows. Where two
  clips show it, the earliest is entered (ties go to the lower id). For a
  nest the timeline does not reach, use an op's `scope` instead (below).

While a nest is open:

- `get_project` reports the nest as if it were the project: its own tracks
  and clips, its frozen size as the canvas, and times from its own zero. It
  also reports `scope`, `scope_clip` and `scope_path` (the trail of nests
  from the timeline). At the timeline, `scope` is `null`.
- `render_frame` draws the nest at its own size.
- Every op lands inside the nest, unless it says otherwise.

Call `set_scope` with no arguments to come back out (**Clip ▸ Close Nest**,
⌘↑).

**Or name it on one call.** Every op tool also takes `scope`, a nest id.
With it, that one call's clip, track and action ids are looked up inside the
nest, and its times are the nest's own. It works from wherever the window
is looking and outranks whatever nest is open. Media ids are unaffected: a
nest shares the document's media. The answer echoes the `scope` it landed in.

**Tools that are not ops follow the open nest.** `detect_silence`,
`normalize_clip`, `sync_audio`, `transcribe`, `import_captions`,
`export_captions` and `record_screen` take no `scope` argument. They work in
whatever nest `set_scope` has open (`record_screen` places its clip there),
so open the nest first to measure or place inside it. `detect_silence`
names, under `protected_nests`, the nest clips a quiet run crossed and left
uncut; open one with `set_scope` and call again to look for dead air inside it. The
`ripple_delete_ranges` call that acts on `detect_silence`'s answer takes
`scope` like any op.

### What does not work inside a nest

- Nine ops have no meaning inside a nest and refuse a `scope` by name:
  `add_marker`, `set_marker`, `remove_marker`, `set_canvas`, `add_media`,
  `relink_media`, `remove_media`, `set_media_color` and
  `add_adjustment_clip`.
- When the nest is only *open* (from `set_scope`) rather than named, most of
  those simply apply to the whole document instead, and the answer lists them
  under `document_ops`. The two that carry a time — `add_marker`, and
  `set_marker` with a `time` — are refused while a nest is open, whatever
  time you send, because a marker is at project time. Leave the nest first
  (`set_scope` with no arguments), then send the marker's time in project
  ticks.
- An edit can be valid inside the nest and still be refused for the
  document's sake. The clip and track limits and the 8-deep nesting limit
  count every container at once.

## A typical session

1. `get_project` — read the ids, the canvas and the playhead.
2. `import_media {path}` — answers the new media id and what the file holds.
3. `add_clip {track, media, at}` — place it.
4. Edit with the op tools.
5. `render_frame {t}` — look at the result. Use it before and after edits.
6. `save_project {path}` — answers once the package is really on disk.
7. `export {preset, path}`, then `export_status {export_id}` until it is done.

## Checking the picture: render_frame

`render_frame` renders one frame of the finished timeline through the same
composition and compositor an export uses, so it shows what the file will
contain at that moment. The picture comes back both as an image the model can
see and as a file on disk, whose path the answer's text names.

| Argument | What it does | Default |
|---|---|---|
| `t` | The moment to render, in ticks. | The playhead |
| `max_width` | Caps the width in pixels (16–8192), aspect kept, never upscaled. | The canvas size |
| `path` | Where to write the file. The folder must exist. | A temporary file |
| `format` | `png`, `jpeg` or `heic`. Wins over the path's extension, which is replaced. PNG and HEIC keep the canvas's transparency; JPEG flattens it onto black. | From the path, else PNG |
| `burn_in_timecode` | Draws the project timecode over the picture. | Off |
| `ungraded` | Draws every clip as if it were not graded (**View ▸ Show Ungraded**'s picture). | Off |
| `sdr_version` | In an HDR project, draws its SDR version (**View ▸ Show SDR Version**'s picture). | Off |
| `selection` | An adjustment clip's id: draws what its qualifier selects (**View ▸ Show Selection**'s picture). | None |
| `waveform`, `parade`, `vectorscope`, `histogram` | Also measures that scope. The text gives the clipping or neutral share, and a JSON file beside the image holds the counts. | Off |
| `vectorscope_zoom` | 1, 2 or 4, with `vectorscope`. | 1 |

It is the same writer as **File ▸ Save Frame…**, so a still saved from the
menu and one written here are identical. When a graphic in the frame failed
or warned, the answer names it, and a failed graphic draws its error card in
the picture.

In an HDR (HLG) project, a PNG is 16-bit and a HEIC 10-bit, both labelled
BT.2100 HLG. A JPEG, and any frame asked for with `sdr_version`, is the
project's SDR version, labelled BT.709. The scopes then read the HLG signal,
and their JSON adds `signal: "hlg"` and, for the waveform, parade and
histogram, a `scale`. Scopes are described in
[Colour grading](color-grading.md), HDR frames in [HDR and colour management](hdr-and-color.md).

## Exporting: start, then poll

`export` does not wait for the file. It puts the job on the Export Queue
(**Window ▸ Export Queue**) and answers at once with `{export_id, path,
status}`, where status is `queued` or `running`. Exports run one at a time.

- **`export_status {export_id}`** answers how it is going and never waits.
  Call it again after a pause until status is `done`, `failed` or
  `cancelled`. It always carries `export_id`, `status`, `path` and
  `elapsed` (seconds since `export` was called, or to the finish). While
  running it adds `progress` (0 to 1), and `phase` while the exporter names
  one (the loudness measurement). When done it adds `bytes` and what the file
  holds: the settings used (preset, container, codec, size, fps, start,
  duration), the loudness measured off the mix, and any warnings a graphic
  gave. `failed` and `cancelled` add the `reason`.
- **`cancel_export {export_id}`** stops it, as the queue row's Cancel does.
  A queued export is cancelled before it starts; a running export's
  half-written file is removed, though the answer may still read `running`
  until the writer has stopped. A finished export is left alone.
- An `export_id` is known until Frame Job quits.

Every refusal — a bad argument, a missing folder, a graphic that does not
compile — comes back from `export` itself, before anything is queued. A
failure while writing comes back from `export_status` as `failed` with its
reason; a graphic that fails during the export stops it, leaving no file,
and the reason names the graphic and the frame.

`export` takes `preset` and `path`, plus `size`, `range` (`project` or
`in_out`), `video_bitrate`, `audio_bitrate`, `loudness_lufs`, `peak_dbtp`,
`burn_in_timecode` and `dynamic_range`. The presets are `h264`, `hevc`,
`hevc_alpha`, `hevc_10bit`, `prores_422`, `prores_4444`, `audio_m4a`,
`audio_wav`, `audio_aiff`, `gif` and `apng`. There is no frame-rate
argument: an export runs at the project's rate, or at 12.5 fps for `gif` and
25 fps for `apng`. An existing file at the path is replaced, and the
format's extension is added when the path has none. `peak_dbtp` without
`loudness_lufs` is refused. `dynamic_range` `hlg` or `pq` is refused outside
`hevc_10bit`, `prores_422` and `prores_4444`, and in an SDR project. What
each option means is in [Export](export.md).

## Reading the project: get_project

`get_project` answers the whole project as JSON, the same document every op
edits:

- **`project`** — the canvas (width, height, fps as `[num, den]`, background,
  `fit_new_clips`, `timecode_frames`, dynamic range and blending), `media`,
  `tracks`, `clips`, `markers`, `nests` (each with its own tracks and clips)
  and `next_id`.
- **The app's own state**, which is not saved in the project: `playhead`,
  `selection`, and `in_out_range` when one is set.
- `path`, `name`, `unsaved_changes` and `duration`.
- The `scope` report (which nest is open, if any).
- `missing_media` when files have moved (`relink_media` points one at its
  new location).
- `graphics` — every module in the package's `graphics/` folder, whether it
  compiles, and the clips drawn by it.

Read it first: every other tool names things by the ids it reports.

## The tools

Ninety-eight tools, grouped by area. A tool marked *op* is one of the
project's edit operations and also takes `scope`. Every tool takes
`project`. The tool's own description, which the client shows the model,
spells out each argument; the area pages cover the features in depth.

### Projects, view and history

| Tool | What it does |
|---|---|
| `open_project` | Opens a `.framejob` package, or a movie, sound or picture as a new untitled project sized and rated to the file, with the file as the first clip on track 1. Answers `already_open` when it is. |
| `new_project` | A blank 1920×1080, 30 fps project (**File ▸ New Project**), saved straight away when given a `path` (`.framejob` is added when missing). A path another open project holds is refused, and nothing is created. |
| `save_project` | Saves; a `path` saves there (Save As). Required the first time. Answers once the package is on disk. A path another open project holds is refused. |
| `close_project` | Closes a project and its window (**File ▸ Close**, ⌘W). Refuses unsaved changes unless `discard: true`. |
| `get_project` | The whole project plus playhead, selection and in/out range. |
| `set_playhead` | Moves the playhead and seeks the preview. Not an edit. |
| `set_range` | Sets the in/out range (**Mark ▸ Set In** I, **Set Out** O); no bounds clears it (**Mark ▸ Clear Range**, ⌥X). Not an edit. |
| `set_selection` | Selects clips, as clicking them or **Edit ▸ Select All** (⌘A) does; no clips selects nothing. The canvas handles and the inspector act on the selection; ops take their own `clips`. Not an edit. |
| `set_scope` | Opens a nest (⌘↓) or, with no arguments, comes back out. Not an edit. |
| `undo` | One step back (**Edit ▸ Undo**, ⌘Z), naming the step. An error when there is nothing to undo. |
| `redo` | One step forward (**Edit ▸ Redo**, ⇧⌘Z). Any new edit clears what there was to redo. |

See [Projects and media](projects-and-media.md) and [Timeline](timeline.md).

### Media

| Tool | What it does |
|---|---|
| `import_media` | Probes a file and adds it to the media list (**File ▸ Add Media…**), answering its new id. A WebM or Matroska file is copied into a `.mov` first. |
| `add_media` | *op* — the raw op behind `import_media`, from a descriptor you supply. Use `import_media` unless you are replaying a project's own JSON. |
| `relink_media` | *op* — points a media entry at a file that moved (the Relink… sheet). |
| `remove_media` | *op* — removes a media entry; refused while clips use it unless `with_clips`. |
| `consolidate_media` | Copies every referenced file into the package (**File ▸ Consolidate Media…**). The project must be saved first. |
| `set_media_color` | *op* — a video file's camera log conversion or LUT, and a PQ file's peak (the Media tab's Camera Log and HDR10 sections). |

See [Projects and media](projects-and-media.md) and [HDR and colour management](hdr-and-color.md).

### Adding clips

| Tool | What it does |
|---|---|
| `add_clip` | *op* — places a whole media file at `at` on `track`. |
| `insert_clip` | *op* — the insert edit (**Edit ▸ Insert at Playhead**): makes room, shifting every unlocked track. |
| `overwrite_clip` | *op* — the overwrite edit (**Edit ▸ Overwrite at Playhead**): takes the room on one track, nothing shifts. |
| `add_text_clip` | *op* — a title; 5 s of the Title preset by default. |
| `add_shape_clip` | *op* — a rectangle, ellipse, line or arrow. |
| `add_adjustment_clip` | *op* — a clip that grades everything behind it (**Insert ▸ Adjustment Clip**). |
| `add_background` | *op* — a backdrop on a new back track (**Clip ▸ Add Background**): white by default, or a `color` or a `media`. |
| `add_blurred_background` | *op* — a muted, blurred, canvas-filling copy of a clip behind it (**Clip ▸ Add Blurred Background**). |
| `add_graphic_clip` | *op* — a motion graphic drawn by a module in the package's `graphics/` folder. |

See [Editing](editing.md), [Canvas and layers](canvas-and-layers.md) and [Graphics](graphics.md).

### Cutting and arranging

| Tool | What it does |
|---|---|
| `move_clip` | *op* — shifts clips by `delta` ticks, optionally onto another `track` (the clip drag). |
| `trim_start` / `trim_end` | *op* — moves a clip's start or end, keeping the content in place. |
| `rate_stretch` | *op* — stretches a clip to a new end by changing its speed (⌥-drag the end edge). |
| `slip` | *op* — slides the source under a fixed clip (⌥⇧-drag the body). |
| `roll` | *op* — moves a hard cut between two clips (⌥⇧-drag an edge). |
| `split` | *op* — cuts clips in two at `at`, the playhead by default (**Clip ▸ Split**, ⌘T). |
| `delete` | *op* — removes clips and leaves the gaps (⌫). |
| `ripple_delete` | *op* — removes clips and closes the gaps (⌘⌫). |
| `ripple_delete_range` | *op* — cuts a time range out of the whole timeline and closes it. |
| `ripple_delete_ranges` | *op* — cuts several ranges as one undo step; the shape `detect_silence` and `detect_fillers` answer. |
| `lift_range` | *op* — cuts a range out and leaves the hole. |
| `insert_time` | *op* — opens a gap of `length` at `at` on every unlocked track. |
| `close_gap` | *op* — closes the gap on a track at `at` (**Clip ▸ Close Gap**, or double-click the gap). |
| `duplicate` | *op* — copies clips just after the originals (⌘D). |
| `paste` | *op* — pastes a Copy payload at `at`, the playhead by default (⌘V). |
| `paste_attributes` | *op* — copies one clip's property groups onto others (**Edit ▸ Paste Attributes**, ⌥⌘V). Each group replaces the target's whole group. Without `groups` it copies each of video, audio, text and shape that both clips have; `graphic` copies only when named (**Edit ▸ Paste Graphic Properties**), onto clips drawn by the same graphic. |
| `nest` / `unnest` | *op* — collapses clips into one nest clip (**Clip ▸ Nest**, ⌘G) and returns its contents to the timeline (**Clip ▸ Un-nest**, ⇧⌘G). |
| `detach_audio` | *op* — splits a clip's audio onto its own clip on the track below (⌥⌘D). |
| `set_enabled` | *op* — turns a clip's video and/or audio half on or off. |

See [Editing](editing.md) and [Timeline](timeline.md).

### Speed and time

| Tool | What it does |
|---|---|
| `set_speed` | *op* — a media clip's rate, or a `duration` to fit (**Clip ▸ Speed…**). Rates run ×0.1–×1000; above ×12 the audio is left out. |
| `add_speed_ramp` | *op* — a speed ramp preset in one step (**Clip ▸ Speed Ramp…**): `ramp_up`, `ramp_down`, `speed_dip` or `speed_burst`. |
| `set_reversed` | *op* — plays a media clip backwards (the Reverse checkbox in the Clip tab's Timing section). |
| `freeze_frame` | *op* — holds one frame at `at`, the playhead by default (⇧⌘F). |

See [Speed](speed.md).

### Clip properties

| Tool | What it does |
|---|---|
| `set_video` | *op* — position, scale, rotation, opacity, crop, corners, shadow, colour and grading, chroma key, filters, reflection, spotlight and motion. |
| `set_audio` | *op* — volume, mute, fades, ducking, mono, keep pitch, pan, compression and noise reduction. |
| `set_text` | *op* — a text clip's words and typography. |
| `set_shape` | *op* — a shape clip's geometry and paint. |
| `set_graphic` | *op* — which module a graphic clip draws, its size, length and props. |
| `set_clip` | *op* — a clip's name and colour label (**Clip ▸ Rename…**, ⇧⌘R; **Clip ▸ Label**). |

See [Canvas and layers](canvas-and-layers.md), [Motion and transitions](motion-and-transitions.md), [Audio](audio.md), [Colour grading](color-grading.md) and [Graphics](graphics.md).

### Animation

| Tool | What it does |
|---|---|
| `add_action` | *op* — an animation span on a clip, in clip time; its end state starts empty. |
| `add_zoom_action` | *op* — an animated zoom to a `region` (`fit` or `fill`), or back out with `region: null`. |
| `set_action` | *op* — moves, re-times or re-curves an action. |
| `set_action_end` | *op* — what an action animates to: video, audio, text, a graphic's props, or a `speed`. |
| `remove_action` | *op* — removes an action. |

See [Motion and transitions](motion-and-transitions.md) and [Speed](speed.md).

### Transitions

| Tool | What it does |
|---|---|
| `add_transition` | *op* — makes an overlap at a hard cut and puts a transition on it (**Clip ▸ Transition**); `ripple: true` makes it by moving clips instead. |
| `set_transition` | *op* — the transition into a clip; `kind: null` removes it. |
| `set_transition_duration` | *op* — makes a transition last `duration` by moving the clip. |
| `set_transition_style` | *op* — the easing curve and whether the sound crossfades. |

See [Motion and transitions](motion-and-transitions.md).

### Tracks, markers and canvas

| Tool | What it does |
|---|---|
| `add_track` | *op* — an empty track; the front by default. |
| `remove_track` | *op* — refused while it holds clips unless `with_clips`. |
| `move_track` | *op* — reorders the layer stack. |
| `set_track` | *op* — name, Hide Video, Mute Audio, Lock Track, Solo and Matte (the **Track** menu). |
| `remove_empty_tracks` | *op* — **Track ▸ Remove Empty Tracks**. |
| `add_marker` | *op* — a marker at `at`, the playhead by default; `chapter` makes it a chapter of the export. |
| `set_marker` | *op* — moves, renames or recolours a marker, or changes its chapter flag. |
| `remove_marker` | *op* — removes a marker. |
| `set_canvas` | *op* — size, frame rate, background, `fit_new_clips`, timecode display, dynamic range (`output`) and `blending`. |

See [Timeline](timeline.md), [Canvas and layers](canvas-and-layers.md) and [HDR and colour management](hdr-and-color.md).

### Audio tools

| Tool | What it does |
|---|---|
| `detect_silence` | Reports the quiet spans, changing nothing (the read half of **Clip ▸ Remove Silences…**). |
| `normalize_clip` | Sets each clip's volume so its loudest moment lands at `peak_db` (**Clip ▸ Normalize**). |
| `sync_audio` | Lines clips up by their sound (**Clip ▸ Synchronize Audio**). |
| `detect_fillers` | Reports filler words as ranges, changing nothing (the read half of **Clip ▸ Remove Filler Words…**). |
| `transcribe_for_fillers` | Re-transcribes one media file with AssemblyAI, adding filler words — a paid upload. |

See [Audio](audio.md) and [Remove Silences and Remove Filler Words](cleanup-tools.md).

### Captions and transcripts

| Tool | What it does |
|---|---|
| `transcribe` | Speech to caption clips (**File ▸ Generate Captions…**), on this Mac or with AssemblyAI. |
| `import_captions` | An `.srt` file as text clips (**File ▸ Import Captions…**). |
| `export_captions` | One text track as `.srt` or `.vtt` (**File ▸ Export Captions…**). |
| `get_transcript` | One clip's spoken words with timeline times; never uploads anything. |

See [Captions](captions.md) and [Remove Silences and Remove Filler Words](cleanup-tools.md).

### Graphics

| Tool | What it does |
|---|---|
| `graphic_reference` | The whole graphics API as Markdown (**Help ▸ Graphics Reference**). |
| `write_graphic` | Writes and compiles a module; answers its compile. |
| `get_graphic` | Reads one module, or lists the folder. |
| `render_graphic` | Draws a module without a clip: a contact sheet, or one frame's SVG. |
| `import_graphic_font` | **File ▸ Add Font to Graphics…**; answers the family names to use. |
| `import_graphic_asset` | **File ▸ Add Image to Graphics…** |
| `delete_graphic` | **File ▸ Delete Graphic…**; refused while a clip draws it. |
| `rename_graphic` | **File ▸ Rename Graphic…**; its clips follow, as one undo step. |
| `restore_graphic` | **File ▸ Restore Graphic Version…** |

Writing, deleting and restoring modules and adding fonts or images in
`graphics/` are not undoable (renaming is, as one step with its clips), but
the last 10 texts each module replaced are kept and `restore_graphic` brings
one back. See
[Graphics](graphics.md).

### Rendering and export

| Tool | What it does |
|---|---|
| `render_frame` | One frame as a picture, the same as the export would hold. |
| `export` | Starts an export (⌘E) and answers an `export_id` at once. |
| `export_status` | How an export is going; never waits. |
| `cancel_export` | Stops an export. |

See [Export](export.md).

### Screen recording

| Tool | What it does |
|---|---|
| `record_screen` | Records a display or window for 1–600 `seconds` and lands it as media (**File ▸ New Recording…**), records the microphone alone with `source: "voice_over"`, or a camera alone with `source: "camera"` (and `camera` to choose one, `camera_format` its format); with `source: "screen"` and `camera`, records that camera beside the screen on a Camera track in front, in the bottom-right corner. |

See [Screen recording](screen-recording.md).

## Limits

- Only programs running as you can connect, and only while Frame Job is
  running (the helper launches it for a call).
- Calls run one at a time. A long call — an export's start is quick, but a
  recording or a transcription is not — holds the next one until it ends,
  and any call waits while you hold the mouse down mid-drag.
- If Frame Job launches but does not start listening within 60 seconds, the
  call is answered with that, and later calls in the same client session do
  not launch another copy; quit the stray copy and try again.
- A tool call never asks you anything, so anything that needs a question
  answered or a system grant given has to be done by a person first.
- Copy MCP Command writes the Claude Code command only; other clients take
  the helper's path by hand.
