# Reelcut

A screencast video editor. A project is a document of tracks and clips that the core edits through ops; the app and the agent both speak in those ops. This glossary holds the terms the spec and the op table use, sharpened as decisions settle them.

## Language

**Op**:
One edit to a project, named by a row of the op table and applied whole. An op the core understood answers one of exactly three ways: it applies and yields a new project, it is an identity, or it is refused. A request the core could not read at all is none of the three — that is a mistake in the asking rather than an answer about the project.
_Avoid_: command, mutation, action (an action is an animation on a clip)

**Identity**:
An op that was understood and had nothing to change: the project already says what was asked, or the op was handed an empty selection. It leaves the project exactly as it was, makes no undo step, and has nothing to explain — a caller told about a rule here would go looking for one it did not break.
_Avoid_: no-op, failure, "nothing happened" (all three hide the difference from a refusal)

**Refusal**:
A rule declining an op, in that rule's own sentence: which track is locked, which clips still show the media, by how many ticks two clips would overlap and how long the shorter one is. Like an identity it leaves the project exactly as it was and makes no undo step; unlike an identity it says why, and it names what a caller could send instead rather than restating the rule. A refusal is not an error — an error is a request that could not be read.
_Avoid_: error, rejection, failure, "invalid"

**Op table**:
The one list of the ops and their arguments, kept by the core and published by it. A row is an op's name and, per **Argument**, its name, its kind and whether it is required — the STRUCTURE of a call and nothing about its meaning, which stays in the prose beside the ops themselves. Everything downstream — the tool catalog an agent reads, the check that compares the two at startup — reads the table rather than restating it, so an argument is written down once and a row that lies is a failing test rather than a call that goes wrong.
_Avoid_: schema, op list, the op enum (the enum is one implementation of the table)

**Argument**:
One named value an **Op** takes, checked against the op table. An argument is part of the CALL: the core knows what it is — ticks, an id, a boolean, a closed vocabulary — and the app says what it is FOR. Distinct from a **Patch**'s keys, which are part of a VALUE and are checked against the property vocabulary instead: `set_video` takes the two arguments `clips` and `patch`, and everything inside that patch is not an argument at all. A name no tool published is not an argument either: it is refused at the door, naming the tool and what it does take, and never dropped.
_Avoid_: parameter, field, key, option

**Patch**:
A partial object a caller writes to say what to change — a clip's property group, a clip's own name and label, or an action's end state. It merges key by key at every depth; a key set to null clears that key, or removes it from an end state; an array replaces the whole list. A key or value the vocabulary does not have is refused by its dotted path, and never dropped, corrected or clamped. The core is the one that reads it, wherever it came from.
_Avoid_: update, delta, diff, replacement

**Selected action**:
The one action of the single selected clip that the Clip tab is editing, or none. It is view state, like the playhead and the clip selection: not an edit, not undoable, not saved, and not something an agent sets — an agent names an action by its id. It is chosen by clicking the action's band, or by the playhead ENTERING the action's span; it stays chosen when the playhead leaves, and goes when the clip selection changes, on esc, or on the lane's Clip chip. While one is chosen the fields show and write its END state (spec §11 CI-1, CI-2). Actions are numbered by time order.
_Avoid_: current action, active action, "the action under the playhead" (the playhead no longer decides)

**Graphic**:
A clip whose picture is drawn by code: a **Module** in the package's `graphics/` folder, run per frame with the clip's props, rasterized at the graphic's own size. It is a clip's CONTENT, in the place a media file or an image sits — not an effect, and not a plugin: its code reaches no other clip, no timeline, no model and no file, and the same frame with the same props always draws the same pixels (spec §11 G-1, G-5).
_Avoid_: effect, plugin, overlay, template (a template is a graphic someone else wrote)

**Template**:
A **Module** the app ships, which a person copies into their package with Insert ▸ Graphic: the file is written into `graphics/` under a free name (`lower-third`, then `lower-third-2`) and a clip drawn by it is placed at the playhead. Once copied it is the package's own module — editing it changes no other package, and no later app version reaches it. Its menu title comes from its file name, never from running it (spec §11 G-16).
_Avoid_: preset (a preset is stored settings, not code), sample, built-in graphic

**Error card**:
What a **Graphic** draws in its own box when it cannot draw itself — its **Module** is missing or does not compile, or a frame throws, runs past its budget or will not rasterize: dark red, a bright red border, and the graphic's name, its frame and the first diagnostic with its line and column in white. Never the last good frame, which would hide the error from someone scrubbing. An export never delivers one: it is refused before it starts, or stopped at the frame, with no file left (spec §11 G-8).
_Avoid_: slate (the slate is what a layer with no source at all draws), error frame, placeholder

**Module**:
A graphic's source: one JavaScript ES module exporting `render(frame, props, ctx)`, which returns SVG, and optionally `meta` and `schema`. It is compiled once and drawn many times; the standard library is global and nothing can be imported. Many clips may name one module, as many clips share one media file.
_Avoid_: script, component, file (the file holds the module), plugin

**Revision**:
Which text of a **Module** drew a frame: the SHA-256 of its source's bytes, 64 hex digits. Two identical texts are one revision wherever they came from; an edit to the file is a new revision, and an export pins the revision it started with.
_Avoid_: version (the font and asset set has a version), hash, edit number

**Kept revision**:
An earlier text of a **Module** the app kept, named by its **Revision**: the text a write replaced while the project was open, or the text a delete removed. The last 10 per module live in the package's `graphics/history/<name>/`, never the current text among them, and move with the module when it is renamed. A name with no file but with kept revisions is a deleted module (spec §11 G-27, G-29).
_Avoid_: backup, snapshot, undo step (restoring one is a file write, not undo), version

**Props**:
The values a **Graphic** is drawn with, stored on its clip in the caller's key order — a title, an accent colour, a size. When the op that sets them carries the module's schema, each is checked by its dotted path (`props.accent`) for its type, its range and its options, and a colour is stored as lowercase hex; without one, only its shape. Distinct from a **Patch**, which is what a caller SENDS to change them: a patch's `props` merges into the stored props key by key, and a null in it removes that key (spec §11 G-4, G-12).
_Avoid_: parameters, inputs, settings, variables
