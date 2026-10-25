import Foundation

/// Where the agent's output tools write: `render_frame`, `export`,
/// `export_captions`, `render_graphic`'s sheet and `snapshot_ui` all take a
/// `path`, and every one of them names its file through `destinationURL`
/// here, refuses a path whose folder does not exist through `requireFolder`,
/// and the three that may omit `path` refuse an empty one through
/// `nonEmptyOutputPath` and name a temporary file through `temporaryOutput`.
extension AgentServer {

    /// An output path as the tools take one: `~` expanded, and the extension
    /// the format actually needs (a `.framejob` package without its extension
    /// is not a package, and an `.mp4` written to a name ending `.mov` claims
    /// a container it does not have).
    ///
    /// A WRONG extension is REPLACED, not appended to. Appending is what
    /// turned an export to `final.mov` with an MP4-container preset into
    /// `final.mov.mp4` — a file at neither the path the caller asked for nor
    /// one they would guess. Every caller reports the URL this returns, so
    /// the substitution is never silent.
    /// The extensions `destinationURL` will REPLACE: the containers this app
    /// writes, its own package, and the media extensions a caller is most
    /// likely to type out of habit. Everything else is part of the name.
    ///
    /// `srt` and `vtt` joined the list when `export_captions` landed, because
    /// they are containers this app writes. `export_captions` no longer reads
    /// this set (spec §11 #43): it replaces only
    /// `CaptionExporter.knownExtensions`, through `captionDestinationURL`, as
    /// the save panel does. The two stay here for the other tools, so a still
    /// or a movie named `talk.srt` is renamed rather than doubled.
    ///
    /// The five image containers joined it in road map 2's phase 7a, on the
    /// same terms and for two reasons rather than one. The new one:
    /// `render_frame` takes a `path` and a `format` now (`FrameWriter`), so
    /// `render_frame {path: "shot.jpg", format: "png"}` would have written
    /// `shot.jpg.png`. The old one is a REAL BUG this fixes rather than
    /// prevents — `gif` has been a container this app writes since M3's image
    /// sequences, and without it `export {path: "loop.gif", preset: "apng"}`
    /// writes `loop.gif.png` today. Both spellings of JPEG are here because a
    /// person types both; `heif` is NOT, because this app never writes one
    /// (`FrameWriter.Format.heic` is `UTType.heic` for the measured reason
    /// recorded there), so a file called `scene.heif` keeps its name.
    private static let replaceableExtensions: Set<String> = [
        "mov", "mp4", "m4v", "m4a", "mp3", "wav", "aif", "aiff", "caf", "framejob", "srt", "vtt",
        "png", "jpg", "jpeg", "heic", "gif",
    ]

    static func destinationURL(_ path: String, extension ext: String) -> URL {
        destinationURL(path, extension: ext, replacing: replaceableExtensions)
    }

    /// `destinationURL` over a caller's own set of replaceable extensions:
    /// `export_captions` passes `CaptionExporter.knownExtensions` (#43).
    static func destinationURL(
        _ path: String, extension ext: String, replacing replaceable: Set<String>
    ) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let current = url.pathExtension
        if current.lowercased() == ext.lowercased() { return url }
        // Only a KNOWN container extension is replaced. A "looks like an
        // extension" heuristic is not good enough: it turns "Talk v1.2" into
        // "Talk v1.mp4", silently dropping a character the caller typed on
        // purpose. Anything not on this list is treated as part of the name
        // and the extension is appended to it.
        let base = replaceable.contains(current.lowercased())
            ? url.deletingPathExtension() : url
        return base.appendingPathExtension(ext)
    }

    /// `url` when its folder already exists; refused BY NAME when it does
    /// not. A tool that created directories would answer a mistyped path by
    /// scattering empty ones, so every output tool takes the folder as given.
    static func requireFolder(of url: URL) throws -> URL {
        let folder = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ToolError(message: "There is no folder at \(folder.path) to write into.")
        }
        return url
    }

    /// A temporary file for a tool whose caller omitted `path`: `stem`, a
    /// short random suffix so two calls never collide, and `ext`.
    static func temporaryOutput(_ stem: String, extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(stem)-\(UUID().uuidString.prefix(8)).\(ext)")
    }

    /// `path` when it names something. Empty is refused rather than read as
    /// absent: a caller that sent a `path` meant to name a file, and silently
    /// writing to a temporary one instead is a success reported for a file
    /// nobody can find.
    static func nonEmptyOutputPath(_ path: String) throws -> String {
        guard !path.isEmpty else {
            throw ToolError(
                message: "path must name a file to write — omit it for a temporary one.")
        }
        return path
    }
}
