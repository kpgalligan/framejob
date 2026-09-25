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
/// `get_graphic` and `graphic_reference`.
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
                    + "set_graphic changes what it is drawn from, set_video places it.",
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
                "Patches what graphic clips are drawn from: name (another module), width, "
                    + "height, length (the graphic's own timeline in ticks; null ends it "
                    + "with the clip) and props, merged key by key — a null prop removes "
                    + "its key. A patch naming props or name is checked against the schema "
                    + "of the module it names, else of the one module every clip is drawn "
                    + "by; clips drawn by two different modules are refused for props. A "
                    + "clip that is not a graphic is an error.",
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
                    + "say where; fix the source and write it again. clips lists the clips "
                    + "drawn by it, which redraw with the new text at once. A file write is "
                    + "not undoable and does not mark the project edited (the previous text "
                    + "is gone), so keep your own copy if you want the old one back. Read "
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
                    + "schema, diagnostics) and the clips drawn by it. Without: folder, the "
                    + "folder's absolute path — where it WILL be when folder_exists is false; "
                    + "the first write_graphic creates it — and every module with its revision, "
                    + "ok and clips. The folder may also be edited with your own file tools: "
                    + "modules (<name>.js), fonts in fonts/ (.ttf, .otf) and pictures in "
                    + "assets/; the app sees a change within a moment. API.md and API.d.ts "
                    + "there are the reference, written by the app.",
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
                    + "project open.",
                [:]),
        ]
    }
}
