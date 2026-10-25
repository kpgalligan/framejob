# Motion graphics

A graphic clip is a motion graphic drawn fresh on every frame by a small
JavaScript module kept inside your project. Frame Job ships six ready-made
graphics (titles, a lower third, a counter, a chart and more), and you can
bring in your own module or have an agent write one. Each module declares the
properties it takes, and the inspector turns those into controls, so you can
change text, colours and numbers without touching code, and animate them over
time like any other clip property.

The language a module is written in (the `render` function, `ctx`, the schema,
the standard library, fonts, the sandbox and its limits) is documented in the
[graphics API reference](../graphics-api.md). This page covers using graphics
in the editor.

## What a graphic is

- A **module** is one file, `graphics/<name>.js`, in the project's package. It
  draws an SVG picture for any frame you ask for. The same frame always draws
  the same picture: a module cannot reach the network, the clock or random
  numbers other than its own seeded ones.
- A **graphic clip** is a clip on the timeline drawn by a module. It names the
  module, the size the module draws at, the graphic's own timeline, and the
  property values to draw with. Many clips can share one module, each with
  its own values.
- A module's **properties** (its schema) are typed: number, boolean, colour,
  menu (enum), text, or picture (asset). A value you don't set draws with the
  module's own default.

Module names use lowercase letters, digits and `-`, start with a letter or a
digit, and are at most 63 characters (`lower-third`, `title-2`).

Graphics draw only with the fonts bundled with Frame Job and the ones you add
to the project (see [Fonts and pictures](#fonts-and-pictures)), never with
the fonts installed on your Mac, so a project draws the same everywhere.

## Adding a graphic

**Insert ▸ Graphic** lists the bundled templates, then **From File…**:

| Item | What you get | Default length |
|---|---|---|
| Bar Chart | A titled bar chart whose bars grow in turn, from comma-separated values and labels | 150 frames |
| Callout | A circle that draws itself on, with an arrow and a label, at a position on the frame | 90 frames |
| Counter | A number counting from one value to another with thousands separators, a prefix and a label | 90 frames |
| Kinetic Type | A sentence shown word by word, each word springing in, with an accent colour | 150 frames |
| Lower Third | A name and subtitle that slide in and fade out, boxed or not, aligned left, centre or right | 150 frames |
| Title Card | A title fitted to the frame and a kicker over a two-colour gradient, fading in and out | 120 frames |
| From File… | Asks for a `.js` module and copies it into the project | the module's own |

Each template's properties, as the Graphic sub-tab shows them:

| Template | Properties |
|---|---|
| Bar Chart | values and labels (comma-separated text), title, color |
| Callout | x and y (sliders from 0 to 1, a fraction of the frame's width and height), label, color |
| Counter | from, to, prefix, label, color |
| Kinetic Type | text, stagger (1–30), color, accent |
| Lower Third | Title, subtitle, accent, size (12–200), boxed (a checkbox), align (a pop-up: left, center, right) |
| Title Card | title, kicker, from and to (the gradient's two colours) |

Choosing one:

1. Copies the module into the project's `graphics/` folder under a free name
   (a second Lower Third becomes `lower-third-2`, and so on).
2. Places one graphic clip at the playhead, on the front track if it fits
   there, otherwise on a new track above everything. With a nest open, the
   clip goes on the nest's front track, or a new track inside the nest.
3. Selects the new clip so the inspector shows its Graphic sub-tab.

**From File…** names the module after the chosen file: the name is
lowercased, each run of characters other than a–z and 0–9 becomes one `-`,
dashes are trimmed from the ends, the result is cut to 60 characters, and an
empty result becomes `graphic` (so `My Title.js` becomes `my-title`). If that
name is taken, it gets `-2`, `-3` and so on.

On the timeline a graphic clip is labelled **Graphic**, with a `{}` glyph, and
has no filmstrip.

The clip's length and size come from the module's own `meta`
(`durationInFrames`, `width`, `height`) when it gives them; otherwise it is
5 seconds long and the canvas's size. A graphic is placed at Fit scale, like a
shape.

Placing the clip is one undo step, **Insert Graphic**. Copying the file into
the project is not undone. If the module doesn't compile, the file stays in
`graphics/`, no clip is placed, and an alert gives the first error and its
line. A file that isn't UTF-8 text is refused.

The menu items are greyed until the project's window is open.

*Agents:* `write_graphic` then `add_graphic_clip` (`track`, `at`, `name`, and
optionally `duration`, `width`, `height`, `props`).

## The Graphic sub-tab

Select a graphic clip and open the inspector's **Clip** tab: its sub-tabs
are **Graphic**, **Picture** and **Clip**. Graphic appears only when every
selected clip is a graphic clip.

- **Picture** has Transform (position, scale, rotation, opacity), Shadow,
  Filters, Reflection, Spotlight and Obscure, as for any layer (see
  [Canvas and layers](canvas-and-layers.md)). It has no Crop, Corner Radius
  or Chroma Key, which are for clips drawn from media.
- There is no **Color** sub-tab. To grade a graphic, put an adjustment clip
  above it (see [Color grading](color-grading.md)).
- **Clip** has the clip's timing and Motion, but no Speed section: speed is
  for media clips only.

The Graphic sub-tab has four sections: Source, Properties, Size and Timeline.
Properties opens expanded. Source, Size and Timeline open collapsed, and
their collapsed summaries show, in turn, the error or warning count (or the
module's name), `W × H`, and the length.

### Source

What draws the clip, and what the module reports about it.

| Row | What it shows |
|---|---|
| Name | The module's display name (its `meta.name`), else its file name |
| File | `<name>.js` |
| Revision | The first eight characters of the file's content hash, or "missing" when the file is gone |

Buttons:

- **Open in Editor** opens the module in the app your Mac uses for `.js`
  files. Save there and the preview redraws within a moment.
- **Reveal in Finder** shows the file.
- **Duplicate as New Graphic…** asks for a module name (it suggests
  `<name>-copy`), writes a copy of the module under it, and switches the
  selected clips to the copy. Use it to change one clip's look without
  changing every clip that shares the module. Writing the copy can't be
  undone; switching the clips can. A name that isn't a module name, or that
  already exists, is refused.

When the module file is missing, the three buttons are disabled, Revision
reads "missing", and Source shows the error `No module named "<name>" in
graphics/`.

Under the buttons, grouped by heading:

- **Compiling the module**: the compile error, or the warnings the module's
  top level gave.
- **No errors or warnings at the clip's first frame**, or **Checked at the
  clip's first frame** followed by what drawing that frame reported, such as
  a missing font or a picture that isn't in the project.
- **In the graphics folder**: files the folder scan skipped (a bad module or
  picture name, an empty file, a font that loads no face) or could not watch,
  each with a **Reveal** button.

Each diagnostic reads "line L, column C — message". Click it, or its
**Open** button, to open the module in your editor. The section's summary,
when collapsed, is the error or warning count, or the module's name when all
is well.

When the selected clips are drawn by different modules, Source names them
and asks you to select one module's clips to edit its properties.

### Properties

One row per property the module declares, in the module's own order, with
the module's label and its help text as the tooltip:

| Property type | Control |
|---|---|
| number | A value field, with a slider when the module gives both a minimum and a maximum |
| boolean | A checkbox |
| color | A colour well |
| enum | A pop-up of the module's options |
| asset | A pop-up: **None**, then every picture in the project's graphics assets, then any picture name the selected clips, the selected action's end or the module's default refers to that the folder doesn't have, so a missing picture still shows by name |
| string | A one-line field, or a text area when the module marks it multiline |

With no action selected, setting a value back to the module's default
clears it, so the clip follows the module's default if it changes later. The
section's reset clears every stored value, and beeps when nothing is stored.
With an action selected, the reset instead sets the action's end back to the
module's default for every property (see
[Animating a graphic's properties](#animating-a-graphics-properties)).

A value the clip holds for a property the module no longer declares stays,
dimmed, below the rows, with **⌫** to remove it. If the module doesn't
compile, the section says so and lists the stored values. A module that
declares no properties says "The module declares no properties."

Properties appear only when all the selected clips share one module. With
several clips selected, a change applies to all of them.

### Size

| Row | What it does | Range |
|---|---|---|
| Width | The width the module draws at | 1–8192 px |
| Height | The height the module draws at | 1–8192 px |
| Fit to Canvas | Sets the size to the canvas's and centres the clip at scale 1 | — |

The size is the module's drawing surface, the `ctx.width` and `ctx.height` it
sees, so text and shapes stay sharp at any size. Scaling the clip in the
Picture sub-tab scales that drawn picture.

### Timeline

A graphic has a timeline of its own, counted from its first frame. This
section appears only when one clip is selected.

| Row | What it does |
|---|---|
| In | The graphic frame the clip's first frame shows (read only) |
| Length | How long the graphic's own timeline runs. Typing a value pins it |
| Follow Clip | On (the default): the graphic's timeline ends when the clip ends |

Trimming the start of the clip, rolling the cut before it, or splitting it
moves **In**, so the second half of a split carries on where the first left
off rather than starting the animation over. Trimming the end leaves a pinned
Length alone; with Follow Clip on, the graphic's timeline ends at the clip's
new end. A split pins both halves' Length to the original's, so an outro still
plays at the same point. With Follow Clip on, a front trim doesn't shorten the
graphic's timeline either.

When Length is pinned shorter than the clip, frames keep counting past it but
the module's progress stays at its end. Whether the picture then holds or
keeps moving depends on the module: an animation driven by progress holds its
end state, and one driven by frame numbers keeps going.

*Agents:* `set_graphic` (`clips` and a `patch` of `name`, `width`, `height`,
`length` and `props`; `length: null` is Follow Clip; a `null` prop clears it,
except one an action on the clip animates, which is set to the module's
default instead).

## Animating a graphic's properties

A graphic's properties can be animated by an action, the same way a clip's
position or opacity can (see [Motion and transitions](motion-and-transitions.md)):

1. Add an action to the clip (**Clip ▸ Add Action**, ⌥⌘K) and select it.
2. In the Graphic sub-tab, set the values the properties should end at.

While an action is selected, the Properties rows edit the action's end.
Numbers and colours ramp across the action, colours blending through OKLab.
Text, checkboxes, menus and pictures switch at the action's end, and their
rows say "at end". A value written to an action's end is stored as given,
even when it equals the module's default. A property the module marks as not
animatable still edits the clip itself. Size and Timeline always edit the
clip.

The Graphic sub-tab's badge counts how many properties the selected action
animates. A property the action names that the module no longer declares, or
no longer lets be animated, shows dimmed with **⌫** to take it out of the
action.

An animated number arrives in the module with decimals (64 to 129 is 96.5
halfway). A module that needs whole numbers must round them. See
[the API reference](../graphics-api.md#animating-a-prop-from-the-timeline).

*Agents:* `add_action`, then `set_action_end` with
`{graphic: {props: {…}}}` in its patch.

## Copying properties between graphic clips

**Edit ▸ Paste Graphic Properties** (no shortcut) pastes a copied graphic
clip's properties, text and colours included, onto every selected clip drawn
by the same module. Each target keeps its own size, In and Length. Selected
clips drawn by another module, or that aren't graphics, are skipped. If none
can take the paste, it beeps.

**Edit ▸ Paste Attributes** (⌥⌘V) does not carry graphic properties.

Copying and pasting a graphic clip (⌘C, ⌘V) pastes a clip that names its
module; the module's `.js` file, fonts and pictures are not copied. In a
project without that module, the pasted clip draws the red error card until
you add the module under the same name, for example with **Insert ▸ Graphic ▸
From File…** on a file of that name.

*Agents:* `paste_attributes` with `groups: ["graphic"]`.

## Fonts and pictures

**File ▸ Add Font to Graphics…** copies a `.ttf` or `.otf` file into the
project's `graphics/fonts/`. Every graphic in the project can then use it. A
file that loads no face is refused, and a file with the same name replaces
the old one. Nothing is shown when it works.

The family name a module must use is the one the graphics engine reads from
the file, which can differ from the name Font Book or other apps show. If a
font doesn't draw, the Source section reports the missing font; an agent's
`get_graphic {}` or `import_graphic_font` answer lists the exact family
names.

Graphics also have these bundled families: Anton, Bebas Neue, Darker
Grotesque, IBM Plex Mono, Montserrat, Source Sans 3 and Source Serif 4. The
generic `serif`, `sans-serif` and `monospace` draw in Source Serif 4, Source
Sans 3 and IBM Plex Mono.

**File ▸ Add Image to Graphics…** copies a PNG, JPEG, GIF, WebP, SVG or SVGZ
picture into `graphics/assets/`, where a module can draw it and an asset
property's pop-up lists it. Any other kind of file, and an empty file, is
refused. A file with the same name replaces the old one. A file name a module
can't refer to (one starting with `.` or `#`, or holding `/ : " ' < > &` or a
control character, or longer than 247 bytes) is added under a legal name, and
a notice says which; a renamed copy never replaces an existing file, but
takes `-2`, `-3` and so on.

Neither import is an undo step.

*Agents:* `import_graphic_font` (answers `families`, the exact names
`font-family` must use, `library_families`, every family now available, and
`replaced`) and `import_graphic_asset` (answers `name`, the name to pass to
`asset()`, `renamed_from` when the name was made legal, `replaced`, and every
asset in the folder).

## Editing a module

A module is an ordinary file in the project package's `graphics/` folder.
You can edit it in any editor (**Open in Editor** in the Source section) or
with your own tools. Frame Job watches the folder: when a module, font or
picture changes, the paused preview redraws and the inspector updates within
a moment, and a playing preview picks the change up on its next frame.

The folder is created the first time something is written to it. Frame Job
also keeps `API.md` and `API.d.ts` there, the reference and its type
definitions, for an editor or an agent working in the folder. **Help ▸
Graphics Reference** opens the same reference in your default Markdown app,
with or without a project open.

In an untitled project, graphics are kept in a temporary folder and move into
the package when you first save it.

### Kept versions

Whenever Frame Job sees a module's code replaced while the project is open
(an agent's write, a save from your editor, a restore), it keeps the code
that was there. The last 10 versions of each module are kept in
`graphics/history/`. Leave that folder to Frame Job.

## Renaming, deleting and restoring graphics

The **File** menu has three items that each open a small sheet with a
**Graphic:** pop-up of the project's modules:

| Item | What it does |
|---|---|
| **Rename Graphic…** | Renames the module. Type a **New name:** (lowercase letters, digits and -). Every clip drawn by it, on the timeline and inside nests, follows the new name. The field starts with the chosen module's name and changes when you pick another; **Rename** stays disabled until the name is not empty and differs from the current one |
| **Delete Graphic…** | Deletes a module that no clip uses. Its code is kept, so it can be restored |
| **Restore Graphic Version…** | Puts back the newest kept version of a module's code, deleted modules included (listed as "name (deleted)"). The sheet says how many versions are kept |

Rename and Restore open on the selected clip's module when one clip is
selected. Delete always opens on the first module in the list.

- **Rename** is one undo step when a clip uses the module, and Undo renames
  the file back too. A module no clip uses is renamed back by renaming it
  again. Rename is refused if the new name isn't a module name, if a module
  of that name already exists, or if clips left behind by a deleted module of
  that name still use it. Rename is greyed while a nest is open.
- **Delete** is refused while any clip is drawn by the module, and the sheet
  names those clips: delete them or switch them to another module first.
  Fonts and pictures are left alone. Deleting is not an undo step.
- **Switching clips to another module**: the inspector can't point clips at
  a different existing module. **Duplicate as New Graphic…** only switches
  them to a new copy. To move clips to a module that already exists, delete
  the clips and insert that module again, or have an agent call
  `set_graphic` with `{clips, patch: {name}}`.
- **Restore** keeps the code it replaces, so restoring again returns to where
  you were. Restoring is not an undo step.

On success the sheet closes without a message. A refusal beeps and appears
in the sheet in Frame Job's own words, and the sheet stays open. Rename and Delete are greyed in a project with no graphics, and Restore
when no version of any graphic is kept.

*Agents:* `rename_graphic` (`name`, `to`), `delete_graphic` (`name`),
`restore_graphic` (`name`, and optionally a `revision` from `kept`, where the
menu always restores the newest).

## Showing video inside a graphic

A graphic can't read a video's pixels, but it can shape one. Put the graphic
on the track directly above the video and set that track to a matte with
**Track ▸ Matte**. The video then shows only where the graphic draws (or,
inverted, where it doesn't). See [Canvas and layers](canvas-and-layers.md)
for the matte modes and the
[API reference](../graphics-api.md#video-inside-a-graphic-the-matte) for an
example module.

## Playback, rendering and memory

- **While playing forward**, Frame Job draws upcoming graphic frames on spare
  processor cores ahead of the playhead, and keeps frames it has drawn in
  memory while the window is open, so a stretch you play again comes from
  memory.
- **Background render**: when you leave Frame Job alone, the window you last
  used draws its graphics ahead of the paused playhead, so the next play is
  smooth from the start. A click, a key, an edit, or play, pause or seek in
  any Frame Job window (an agent's edits and playhead moves included) stops
  it at once, and it starts again after the same wait. Moving the pointer
  alone, or working in another app, doesn't stop it. It never runs while a
  window is playing, and it keeps the processor busy while it runs.

  | Setting (Settings ▸ Playback) | What it does | Default |
  |---|---|---|
  | Background render | Turns background drawing on or off | On |
  | Start after … seconds | How long Frame Job must be left alone first, 1–60 | 5 |

  See [Settings](settings.md).
- **Memory**: the drawn frames held ahead and kept use at most a quarter of
  your Mac's memory, and less when memory is short. They are let go when the
  window closes or newer frames replace them.
- **A graphic that fails** (its module is missing, doesn't compile, throws,
  or runs too long) draws a dark red error card with the error's text in
  place of the graphic, in the preview and in stills.
- **Time budget**: each frame has 250 ms to draw in the preview and 2 s in an
  export.
- **HDR projects**: in an HDR (HLG) project, graphics are drawn at HDR
  reference white (203 cd/m²), like titles and shapes, so a white graphic
  matches SDR white rather than reaching into the highlights. See
  [HDR and colour](hdr-and-color.md).

## Exporting

An export draws each graphic as its module stood when the export was queued.
Editing a module while an export runs doesn't change that file. See
[Export](export.md).

- An export that would draw a graphic whose module is missing or doesn't
  compile is not started. The message names each graphic and its first error.
- A graphic that fails partway through stops the export at that frame, names
  the graphic, and writes no file.
- Warnings a graphic gives while drawing don't stop the export. An agent's
  export result lists them as `graphic_warnings`.

## Working with an agent

An agent connected over MCP (see [MCP](mcp.md)) can do the whole job:

1. `graphic_reference`: read the API once. No project needs to be open.
2. `write_graphic {name, source}`: write `graphics/<name>.js`. The answer is
   the compile of that exact text: `ok`, the module's `meta` and `schema`,
   and `diagnostics` with line and column. A module that doesn't compile is an
   answer with `ok: false`, not an error: fix it and write again. Clips
   already drawn by the module redraw at once.
3. `render_graphic {name, frames}`: look at up to 16 frames on a contact sheet
   (a PNG with each frame's number under it) without placing a clip; `frame`
   draws one frame instead (not with `frames`; with neither, frame 0). A frame
   that fails is drawn as its error card, with a sentence giving the engine's
   location. `format: "svg"` answers one frame's SVG text, its diagnostics and
   the `ctx` it was drawn with. It takes `props`, `width`,
   `height`, `max_width` (default 2048), `background` (`transparent`, the
   default, `checker`, or a hex colour) and `path`. A sheet draws at most
   134,217,728 pixels of frames in all.
4. `import_graphic_font {path}` and `import_graphic_asset {path, name?}`: add
   a font or a picture.
5. `add_graphic_clip`: place it. `set_graphic` changes it, and
   `add_action` with `set_action_end` animates it.
6. `render_frame`: check a frame of the timeline.

`get_graphic {name}` reads one module: its source, revision, compile result,
the clips it draws, and `kept`, its kept revisions, newest first.
`get_graphic {}` reads the folder: its path (and whether it exists yet), every
module with its revision, `ok` and clips, the font families and pictures
available, the scan's `warnings`, and `history`, every name with kept
versions, deleted modules included. An agent may also edit the folder with
its own file tools; the app sees the change within a moment.

File writes (`write_graphic`, `restore_graphic`, `delete_graphic` and the
imports) are not undo steps and don't mark the project edited. Placing and
changing clips, and `rename_graphic`'s change to the clips, are undo steps.

## Limits

- A graphic draws at most 8192 pixels on a side.
- Properties show only when all the selected clips share one module, and
  Timeline only for a single clip.
- A clip stores at most 64 property values.
- Rename Graphic… is unavailable while a nest is open.
- Delete Graphic… is refused while any clip, including one inside a nest,
  uses the module.
- Only the last 10 versions of each module are kept.
- Frame Job watches the first 16 module, font and picture files one by one. In
  a folder with more, a save that rewrites a later file in place may not show
  until something else in the folder changes.
- The memory used for drawn frames is capped at a quarter of the Mac's.
