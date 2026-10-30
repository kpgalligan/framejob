import Foundation

/// The agent's two GRAPHIC op rows — `add_graphic_clip` and `set_graphic`,
/// road map 10's G2a ops, given their tools in G3b (§5h).
///
/// A file of its own for `AgentCatalog+Transitions.swift`'s reason: the clip
/// rows' file is over the size cap. Spliced into `catalogJSON()` right after
/// the transition rows and never at the very end of the catalog, which is
/// where `tools/proof/recording_probe.py` reads the last eleven names from.
///
/// Both rows are `opTool`'s: the prose is here, the structure is printed
/// from the core's table, and `scope` arrives through `tool()`. Neither
/// publishes `schema` — the app fills it from the module's current revision
/// (`AgentCatalog+Declarations.swift`'s two `.filledByTheApp` rows, G-4) —
/// so there is no sentence for it here either.
///
/// Road map 10's G4a appends three APP-STATE rows after them, `tool`'s, with
/// their own schemas and no `scope` (they have no op): `write_graphic`,
/// `get_graphic` and `graphic_reference`; G4b three more the same way:
/// `render_graphic`, `import_graphic_font` and `import_graphic_asset`; and
/// issue batch B84 (#103) three more after those: `delete_graphic`,
/// `rename_graphic` and `restore_graphic` (spec §11 G-27, G-28, G-29); and
/// the graphic browser two after those, the Insert ▸ Graphic… sheet's acts:
/// `list_graphics` and `insert_graphic` (spec §11 G-45); and its phase 2 one more, the
/// sheet's Export…: `export_graphic` (spec §11 G-46); and the `.fjgraphic` import one more,
/// `import_graphic` (spec §11 G-47).
extension AgentServer {
    /// The graphic rows, given the sentences the clip group already hoisted.
    func graphicTools(
        ticks: String, trackDescription: String, clipDescription: String
    ) -> [[String: Any]] {
        return [
            opTool(
                "add_graphic_clip",
                "Adds a GRAPHIC clip — a motion graphic drawn every frame by the JavaScript "
                    + "module graphics/<name>.js in the project's package. The module must be "
                    + "in that folder and must compile, or the call is refused naming what "
                    + "the folder holds or the module's first error. Its props are checked "
                    + "against the module's own schema, read by the app from the file as it "
                    + "is now; a key the schema lacks, a wrong type or a value out of range "
                    + "is refused by its dotted path. Like a shape it has no source: "
                    + "set_graphic changes what it is drawn from, set_video places it. "
                    + "Insert ▸ Graphic… (insert_graphic) is write_graphic of a template "
                    + "then this op.",
                [
                    "track": trackDescription,
                    "at": "Start, \(ticks)",
                    "duration": "Length, \(ticks) Default: the module's meta.durationInFrames "
                        + "at the canvas rate, else 5 s.",
                    "name": "The module: graphics/<name>.js, lowercase letters, digits and -.",
                    "width": "Width the module draws at, in pixels. Default: meta.width, else "
                        + "the canvas.",
                    "height": "Height the module draws at, in pixels. Default: meta.height, "
                        + "else the canvas.",
                    "props": "The values to draw with, keyed by the schema's names; a key "
                        + "left out draws with the schema's default.",
                ]),
            opTool(
                "set_graphic",
                "Patches what graphic clips are drawn from: name (another module), width, height, "
                    + "length (the graphic's own timeline in ticks; null ends it with the clip) "
                    + "and props, merged key by key — a null prop removes its key, except a key "
                    + "the module's schema has that an action on the clip animates "
                    + "(set_action_end's graphic): that one is set to the schema's default, so the "
                    + "animation keeps its start. A patch naming props or name is checked against "
                    + "the schema of the module it names, else of the one module every clip is "
                    + "drawn by; clips drawn by two different modules are refused for props. A "
                    + "clip that is not a graphic is an error. These are the BASE props; to "
                    + "animate one, add_action and then set_action_end.",
                [
                    "clips": "Clip ids (get_project lists them).",
                    "patch": "The keys to change: name, width, height, length, props.",
                ]),
            tool(
                "write_graphic",
                "Writes the JavaScript module graphics/<name>.js in the project's package — "
                    + "atomically, creating graphics/ if it is absent — compiles it, and "
                    + "answers the compile of THAT text: ok, the module's meta and schema, and "
                    + "diagnostics [{level, message, line, column, frame}]. A module that does "
                    + "not compile is an answer, not an error: ok is false and the diagnostics "
                    + "say where; fix the source and write it again. With ok true, diagnostics "
                    + "are the module's top-level warnings (e.g. asset() outside render). "
                    + "clips lists the clips "
                    + "drawn by it, which redraw with the new text at once. A file write is "
                    + "not undoable and does not mark the project edited, but the text it "
                    + "replaced is kept — the last 10 per module; kept lists their "
                    + "revisions, newest first — and restore_graphic brings one back. Read "
                    + "graphic_reference first for the API.",
                [
                    "name": [
                        "type": "string",
                        "description": "The module: lowercase letters, digits and -, starting "
                            + "with a letter or a digit, at most 63 characters.",
                    ],
                    "source": [
                        "type": "string",
                        "description": "The whole module's JavaScript: export render, and "
                            + "optionally meta and schema.",
                    ],
                ], required: ["name", "source"]),
            tool(
                "get_graphic",
                "Reads the project's graphics/ folder. With name: that module's source, "
                    + "revision (the SHA-256 of its bytes), path, whether it compiles (ok, meta, "
                    + "schema, diagnostics), the clips drawn by it and kept, the revisions of "
                    + "its kept earlier texts, newest first (restore_graphic takes one). "
                    + "Without: folder, the "
                    + "folder's absolute path — where it WILL be when folder_exists is false; "
                    + "the first write_graphic creates it — and every module with its revision, "
                    + "ok and clips, warnings: what the folder's scan skipped or could not "
                    + "watch, in its own sentences, and history: [{name, kept}] for every name "
                    + "with a kept text, deleted modules included. The folder may also be "
                    + "edited with your own file tools: "
                    + "modules (<name>.js), fonts in fonts/ (.ttf, .otf) and pictures in "
                    + "assets/; the app sees a change within a moment. API.md and API.d.ts "
                    + "there are the reference, written by the app, and history/ is the "
                    + "app's too: the kept texts, which restore_graphic reads.",
                [
                    "name": [
                        "type": "string",
                        "description": "The module to read. Omit for the folder.",
                    ],
                ]),
            tool(
                "graphic_reference",
                "Answers the whole graphics API — the module's shape, ctx, the schema's "
                    + "types, the standard library, fonts, the sandbox, limits and idioms — as "
                    + "Markdown, for an LLM to read once before writing a graphic. Needs no "
                    + "project open; a project, when given, must name an open one. Help ▸ "
                    + "Graphics Reference opens the same file.",
                [:]),
            tool(
                "render_graphic",
                "Renders a module in graphics/ WITHOUT a clip — to look at it before placing "
                    + "it. png (the default) answers a contact sheet: the frames on a grid, "
                    + "each frame number printed under its cell, the cells scaled down (never "
                    + "the gaps or labels) so the sheet fits max_width; plus one sentence per "
                    + "frame that failed (drawn as its error card) or warned, with the "
                    + "engine's location. svg answers one frame's SVG text, its diagnostics and "
                    + "the ctx it was drawn with. ctx is a clip's: the canvas fps, "
                    + "durationInFrames from meta (else 5 s), the size from width/height, else "
                    + "meta, else the canvas. svg takes no path, background or max_width, which "
                    + "are the png sheet's, and writes no file. A frame at or past "
                    + "durationInFrames is drawn, with progress 1, as a longer clip draws it. "
                    + "A png sheet draws at most \(GraphicContactSheet.maxCellPixels) px of "
                    + "frames (frames × width × height); past that the call is refused before "
                    + "any frame is drawn. "
                    + "No inspector control mirrors it: a person looks at the preview well.",
                [
                    "name": [
                        "type": "string",
                        "description": "The module: graphics/<name>.js.",
                    ],
                    "frames": [
                        "type": "array",
                        "items": ["type": "integer", "minimum": 0],
                        "maxItems": 16,
                        "description": "The frames to draw, 1 to 16 of them, in order. Not with "
                            + "frame. Omit both for frame 0.",
                    ],
                    "frame": [
                        "type": "integer", "minimum": 0,
                        "description": "One frame to draw. Not with frames.",
                    ],
                    "props": [
                        "type": "object",
                        "description": "The values to draw with, keyed by the schema's names; "
                            + "a key left out draws with the schema's default.",
                    ],
                    "width": [
                        "type": "integer", "minimum": 1, "maximum": GraphicLibrary.maxSide,
                        "description": "Width to draw at, in pixels. Default: meta.width, else "
                            + "the canvas.",
                    ],
                    "height": [
                        "type": "integer", "minimum": 1, "maximum": GraphicLibrary.maxSide,
                        "description": "Height to draw at, in pixels. Default: meta.height, "
                            + "else the canvas.",
                    ],
                    "max_width": [
                        "type": "integer", "minimum": 64, "maximum": GraphicLibrary.maxSide,
                        "description": "The widest the png sheet may be, in pixels. Default "
                            + "2048; 8192 keeps a 1920-wide graphic's two cells at full size. Not "
                            + "with format svg.",
                    ],
                    "background": [
                        "type": "string",
                        "description": "What the png sheet is painted on: transparent (the "
                            + "default), checker, or a hex colour (#rgb, #rrggbb, #rrggbbaa). Not "
                            + "with format svg.",
                    ],
                    "format": [
                        "type": "string", "enum": ["png", "svg"],
                        "description": "png (default): the contact sheet. svg: one frame's "
                            + "SVG text.",
                    ],
                    "path": [
                        "type": "string",
                        "description": "Where to write the png sheet; its folder must exist. "
                            + "Omit for a temporary file. The reply ends \"Written to <path>.\" "
                            + "Not with format svg.",
                    ],
                ], required: ["name"]),
            tool(
                "import_graphic_font",
                "Copies a .ttf or .otf file into the project's graphics/fonts/ (creating the "
                    + "folders if they are absent), rebuilds the graphics' font set, and answers "
                    + "families — the family names the ENGINE reads from that file, which are "
                    + "the exact strings a font-family must say (they can differ from what "
                    + "other apps show) — and library_families, every family the graphics can "
                    + "now draw with. A file that loads no face is refused in the engine's "
                    + "words. A file of the same name is replaced (replaced is true). Not "
                    + "undoable. Mirrors File ▸ Add Font to Graphics…",
                [
                    "path": [
                        "type": "string",
                        "description": "The font file to copy; ~ is expanded.",
                    ],
                ], required: ["path"]),
            tool(
                "import_graphic_asset",
                "Copies a PNG, JPEG, GIF, WebP, SVG or SVGZ file into the project's "
                    + "graphics/assets/ (creating the folders if they are absent), where a "
                    + "module draws it with <image href=\"${asset(name)}\">; answers every "
                    + "asset the folder now holds. Anything else, and an empty file, is "
                    + "refused. A file of the same name is replaced (replaced is true). A name "
                    + "asset(name) cannot use (a leading . or #, any of / : \" ' < > &, a control "
                    + "character, more than 247 bytes) is filed under a legal one — name says "
                    + "which, renamed_from what was asked; a renamed copy never replaces, it "
                    + "takes -2, -3 and so on. Not undoable. Mirrors File ▸ Add Image to Graphics…",
                [
                    "path": [
                        "type": "string",
                        "description": "The picture to copy; ~ is expanded.",
                    ],
                    "name": [
                        "type": "string",
                        "description": "The name to file it under, which asset(name) says; its "
                            + "extension must be one of the six. Default: the file's own name.",
                    ],
                ], required: ["path"]),
            tool(
                "delete_graphic",
                "Deletes the module graphics/<name>.js from the project's package. Refused "
                    + "while any clip is drawn by it, on the timeline or inside a nest, in a "
                    + "sentence naming those clips: delete them or point them at another "
                    + "module (set_graphic {name}) first. The deleted text is kept with the "
                    + "module's other kept texts (kept, newest first), so restore_graphic "
                    + "{name} brings the module back; get_graphic {} lists it under history. "
                    + "Fonts and assets are left alone. Not undoable, and it does not mark "
                    + "the project edited. Mirrors File ▸ Delete Graphic…",
                [
                    "name": [
                        "type": "string",
                        "description": "The module to delete: graphics/<name>.js.",
                    ],
                ], required: ["name"]),
            tool(
                "rename_graphic",
                "Renames the module graphics/<name>.js to graphics/<to>.js. Every clip drawn "
                    + "by it, on the timeline and inside every nest, follows the new name as "
                    + "ONE undo step (Rename Graphic; clips lists them), and its kept texts "
                    + "move with it — when to is a deleted module's name (no file, kept "
                    + "texts), the two sets join under to and, past 10, the oldest, the "
                    + "deleted module's, are dropped for good. Undo renames the file back "
                    + "together with the clips, and redo forward again. Refused when to is "
                    + "not a module name, when "
                    + "graphics/<to>.js already exists, when a clip already names to with no "
                    + "file behind it (a clip left by a deleted module), and while a nest is "
                    + "open (set_scope with no arguments comes back out). The file rename "
                    + "itself does not mark the project edited; the clips' change does. "
                    + "Mirrors File ▸ Rename Graphic…",
                [
                    "name": [
                        "type": "string",
                        "description": "The module to rename: graphics/<name>.js.",
                    ],
                    "to": [
                        "type": "string",
                        "description": "The new name: lowercase letters, digits and -, starting "
                            + "with a letter or a digit, at most 63 characters.",
                    ],
                ], required: ["name", "to"]),
            tool(
                "restore_graphic",
                "Writes a kept earlier text of a module back as graphics/<name>.js — the "
                    + "newest kept one, or the one revision names — compiles it and answers "
                    + "as write_graphic does (ok, meta, schema, diagnostics, clips), with "
                    + "restored, the revision put back, and kept, what is kept now. The text "
                    + "it replaced is kept in turn, so restoring twice returns to where you "
                    + "were. Works for a module delete_graphic removed. A text is kept "
                    + "whenever the app sees a module's text replaced while the project is "
                    + "open (write_graphic, a save from an outside editor, a restore) and "
                    + "when delete_graphic removes it; the last 10 per module. Not undoable, "
                    + "and it does not mark the project edited. Mirrors File ▸ Restore "
                    + "Graphic Version… (which restores the newest).",
                [
                    "name": [
                        "type": "string",
                        "description": "The module: graphics/<name>.js, present or deleted.",
                    ],
                    "revision": [
                        "type": "string",
                        "description": "The kept revision to put back, one of kept (get_graphic "
                            + "lists them). Default: the newest kept.",
                    ],
                ], required: ["name"]),
            tool(
                "list_graphics",
                "Lists the graphics Insert ▸ Graphic… offers, in the dialog's order: "
                    + "categories [{name, graphics: [{name, title, description, category, from, "
                    + "ok}]}]. \"This Project\" comes first when the project's graphics/ holds a "
                    + "module, listing every one of them whatever its own category; then the app's "
                    + "bundled templates by category (each module's meta.category, else "
                    + "\"Other\", which is last). title is the module's meta.name, else its name "
                    + "made a title; two This Project graphics with one title are shown as "
                    + "\"<title> — <name>\". from is template or project — what insert_graphic "
                    + "takes with name; ok is false for a module that does not compile.",
                [:]),
            tool(
                "insert_graphic",
                "Places a graphic clip at the playhead, as Insert ▸ Graphic…'s Insert does: on "
                    + "the front track when it fits there, else on a new track above everything, "
                    + "at the module's meta duration and size, as ONE undo step (Insert Graphic). "
                    + "A template (from template) is first copied into graphics/ under a free "
                    + "name (lower-third, lower-third-2, …), which is not undoable; a project "
                    + "module (from project) is placed as it is, with no copy. name in the "
                    + "reply is the module the clip is drawn by. A module that does not compile "
                    + "places nothing and is refused with its first error; the template's copy "
                    + "stays in graphics/. With a nest open the clip lands inside it. "
                    + "list_graphics lists what there is.",
                [
                    "name": [
                        "type": "string",
                        "description": "The graphic's name as list_graphics gives it: a template's "
                            + "or a module's.",
                    ],
                    "from": [
                        "type": "string", "enum": ["template", "project"],
                        "description": "template: one of the app's bundled templates. project: a "
                            + "module already in the project's graphics/.",
                    ],
                ], required: ["name", "from"]),
            tool(
                "export_graphic",
                "Writes one graphic as a .fjgraphic package, as Insert ▸ Graphic…'s Export… "
                    + "does: a zip of manifest.json, the module and only the project fonts and "
                    + "assets it was seen to use. The app draws every frame up to 900 (else 900 "
                    + "evenly spaced) with the default props, then each enum option and each "
                    + "boolean's opposite (at most 32, over 30 frames each), and packs the "
                    + "project fonts and assets the engine drew, measured, fell back to or "
                    + "resolved; a bundled font is never packed, and string and asset props are "
                    + "sampled only at their defaults. An existing file is replaced. Reply: "
                    + "{path, files (the package's entries, manifest.json first), frames, "
                    + "failed_frames (frames that threw, skipped)}. Refused, writing nothing, "
                    + "for an unknown name, a module that does not compile, or a missing folder. "
                    + "No edit and no undo step.",
                [
                    "name": [
                        "type": "string",
                        "description": "The graphic's name as list_graphics gives it: a template's "
                            + "or a module's.",
                    ],
                    "from": [
                        "type": "string", "enum": ["template", "project"],
                        "description": "template: one of the app's bundled templates. project: a "
                            + "module in the project's graphics/.",
                    ],
                    "path": [
                        "type": "string",
                        "description": "Where to write it; .fjgraphic is added when the path "
                            + "lacks it. Its folder must exist.",
                    ],
                ], required: ["name", "from", "path"]),
            tool(
                "import_graphic",
                "Copies a .fjgraphic package (one export_graphic or Export… wrote) into the "
                    + "project's graphics/: its module, fonts and assets under the names the "
                    + "manifest gives, as the Import Graphic sheet's Import does. The package "
                    + "is checked first — a stored zip whose entries match its manifest by "
                    + "path, size and SHA-256, a format this app reads, each font loading and "
                    + "each picture a name asset(name) can use — and a refusal writes nothing. "
                    + "A name the project already holds with the same bytes is reused; a "
                    + "module or font name holding something else is suffixed (-2, -3, …; "
                    + "renamed_from says what the package called it); a picture name holding "
                    + "a different picture is refused, since the module reaches it by name. "
                    + "No file is replaced, and a failure part-way removes what was written. "
                    + "Reply: {name (the module), renamed_from?, title, module (written or "
                    + "reused), fonts [{name, renamed_from?, action}], assets [{name, action}], "
                    + "note}. Not undoable. Mirrors a .fjgraphic opened from the Finder, or "
                    + "Insert ▸ Graphic…'s From File…",
                [
                    "path": [
                        "type": "string",
                        "description": "The .fjgraphic file to import; ~ is expanded.",
                    ],
                ], required: ["path"]),
        ]
    }
}
