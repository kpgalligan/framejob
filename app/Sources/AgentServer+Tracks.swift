import AppKit

/// The agent's track, marker and canvas tools: one per row of the second half
/// of spec §6's op table, same names, same arguments. Same canonical shape as
/// the clip handlers, and the same rule — the typed builders in
/// `ReelCore.swift` are the only place op JSON is spelled.
extension AgentServer {

    // MARK: - Tracks

    /// `add_track` — ⇧⌘N (`EditorViewController+Timeline.newTrackCommand`).
    /// **Index 0 is the BACK of the layer stack** and the BOTTOM lane of the
    /// timeline; the menu command inserts at `tracks.count`, the front.
    func addTrack(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let count = document.project.snapshot.tracks.count
        let index = intArg(a, "index") ?? count
        guard index >= 0, index <= count else {
            throw ToolError(
                message: "index must be 0…\(count) — 0 is the back of the stack, \(count) the "
                    + "front.")
        }
        return try editResult(
            document, "New Track", [.addTrack(index: index, name: stringArg(a, "name"))])
    }

    /// `remove_track` — Track ▸ Remove Track (`removeTrackCommand`). A
    /// non-empty track refuses without `with_clips`, which is the question the
    /// UI puts in an alert; here it is a message the model can answer by
    /// retrying with the flag.
    func removeTrack(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let withClips = boolArg(a, "with_clips")
        let clips = document.project.snapshot.clips(onTrack: track.id).count
        if clips > 0, withClips != true {
            throw ToolError(
                message: "Track \(track.id) (\"\(track.name)\") still holds \(clips) clip"
                    + (clips == 1 ? "" : "s") + ". Pass with_clips: true to remove them too.")
        }
        return try editResult(
            document, "Remove Track", [.removeTrack(track: track.id, withClips: withClips)])
    }

    /// `move_track` — dragging a track header (`TrackDragSession`). Index 0 is
    /// the back of the stack, so a higher index draws in FRONT.
    func moveTrack(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let count = document.project.snapshot.tracks.count
        guard let index = intArg(a, "index"), index >= 0, index < max(count, 1) else {
            throw ToolError(message: "index must be 0…\(max(count - 1, 0)).")
        }
        return try editResult(
            document, "Move Track", [.moveTrack(track: track.id, index: index)])
    }

    /// `set_track` — the header's three toggles (`toggleTrack`, mirrored by
    /// Track ▸ Hide Video / Mute Audio / Lock Track) and its inline rename.
    func setTrack(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let name = stringArg(a, "name")
        let hidden = boolArg(a, "hidden")
        let muted = boolArg(a, "muted")
        let locked = boolArg(a, "locked")
        guard name != nil || hidden != nil || muted != nil || locked != nil else {
            throw ToolError(message: "set_track needs at least one of name, hidden, muted, locked.")
        }
        return try editResult(
            document, "Track Properties",
            [
                .setTrack(
                    track: track.id, name: name, hidden: hidden, muted: muted, locked: locked)
            ])
    }

    /// `remove_empty_tracks` — Track ▸ Remove Empty Tracks
    /// (`removeEmptyTracksCommand`).
    func removeEmptyTracks(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        return try editResult(document, "Remove Empty Tracks", [.removeEmptyTracks()])
    }

    // MARK: - Markers

    /// `add_marker` — M (`addMarkerCommand`). Markers snap to frames and two
    /// may not share a time, so a second marker on the same frame is the
    /// core's refusal.
    func addMarker(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let at = try optionalTimeArg(a, "at", document) ?? document.playhead
        return try editResult(
            document, "Add Marker",
            [
                .addMarker(
                    at: at, name: stringArg(a, "name"), chapter: boolArg(a, "chapter"),
                    color: stringArg(a, "color"))
            ])
    }

    /// `set_marker` — dragging a marker in the ruler (`MarkerDragSession`) and
    /// the Document tab's marker table (rename, chapter checkbox).
    func setMarker(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let marker = try markerArg(a, "marker", document)
        let time = try optionalTimeArg(a, "time", document)
        let name = stringArg(a, "name")
        let chapter = boolArg(a, "chapter")
        let color = stringArg(a, "color")
        guard time != nil || name != nil || chapter != nil || color != nil else {
            throw ToolError(message: "set_marker needs at least one of time, name, chapter, color.")
        }
        return try editResult(
            document, "Marker",
            [
                .setMarker(
                    marker: marker.id, time: time, name: name, chapter: chapter, color: color)
            ])
    }

    /// `remove_marker` — the Document tab's marker-row Remove button.
    func removeMarker(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let marker = try markerArg(a, "marker", document)
        return try editResult(document, "Remove Marker", [.removeMarker(marker: marker.id)])
    }

    // MARK: - Canvas

    /// `set_canvas` — the Document tab (`DocumentPane`): size, frame rate,
    /// background, and the two document switches. `rescale_clips` multiplies
    /// every clip's `x`, `y` and `scale` by the size ratio (the pane's own
    /// checkbox); changing `fps` re-snaps every clip start and duration.
    func setCanvas(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let width = intArg(a, "width")
        let height = intArg(a, "height")
        if let width = width, width < 16 || width > 16384 {
            throw ToolError(message: "width must be 16…16384 px (got \(width)).")
        }
        if let height = height, height < 16 || height > 16384 {
            throw ToolError(message: "height must be 16…16384 px (got \(height)).")
        }
        let fps = try fpsArg(a, "fps")
        let background = try colorArg(a, "background")
        let rescale = boolArg(a, "rescale_clips")
        let fitNew = boolArg(a, "fit_new_clips")
        let timecodeFrames = boolArg(a, "timecode_frames")
        guard width != nil || height != nil || fps != nil || background != nil || rescale != nil
            || fitNew != nil || timecodeFrames != nil
        else {
            throw ToolError(message: "set_canvas: nothing to change.")
        }
        return try editResult(
            document, "Canvas",
            [
                .setCanvas(
                    width: width, height: height, fps: fps, background: background,
                    rescaleClips: rescale, fitNewClips: fitNew, timecodeFrames: timecodeFrames)
            ])
    }

    /// A frame rate as the model spells one: the rational `[num, den]` of spec
    /// §5.1. A bare number is accepted as `[n, 1]`, since "30" is what a model
    /// reaches for first — but 29.97 has no exact integer spelling, so a
    /// fractional bare number is refused with the pair it should have sent.
    private func fpsArg(_ a: [String: Any], _ key: String) throws -> Fps? {
        guard let raw = a[key], !(raw is NSNull) else { return nil }
        if let array = raw as? [Any] {
            guard array.count == 2,
                let num = (array[0] as? NSNumber)?.intValue,
                let den = (array[1] as? NSNumber)?.intValue,
                num > 0, den > 0
            else {
                throw ToolError(
                    message: "\(key) must be [numerator, denominator], e.g. [30, 1] or "
                        + "[30000, 1001].")
            }
            return Fps(num: num, den: den)
        }
        guard let number = (raw as? NSNumber)?.doubleValue, number > 0, number.isFinite else {
            throw ToolError(
                message: "\(key) must be [numerator, denominator], e.g. [30, 1] or [30000, 1001].")
        }
        guard number == number.rounded() else {
            throw ToolError(
                message: "\(key) must be exact: pass the rational pair — 29.97 is [30000, 1001], "
                    + "23.976 is [24000, 1001], 59.94 is [60000, 1001].")
        }
        return Fps(num: Int(number), den: 1)
    }
}
