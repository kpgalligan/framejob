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
        ]
    }
}
