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
        // The CONTAINER's tracks, not the document's (road map 2's phase 9):
        // inside a `scope` the index names a place in the nest's own stack,
        // and bounding it by the timeline's count would refuse a legal index
        // or accept one past the end. `idScope` is the same answer the id
        // readers give.
        let count = try idScope(document).tracks.count
        let index = try intArg(a, "index") ?? count
        guard index >= 0, index <= count else {
            throw ToolError(
                message: "index must be 0…\(count) — 0 is the back of the stack, \(count) the "
                    + "front.")
        }
        return try editResult(
            document, "New Track", [.addTrack(index: index, name: try stringArg(a, "name"))])
    }

    /// `remove_track` — Track ▸ Remove Track (`removeTrackCommand`). A
    /// non-empty track refuses without `with_clips`, which is the question the
    /// UI puts in an alert; here it is a message the model can answer by
    /// retrying with the flag.
    ///
    /// That guard SHADOWS the core's own sentence for the same rule since
    /// deepening D2·3, exactly as `removeMedia`'s does; the core's OTHER
    /// refusal here — the last track in the project — has no guard in front
    /// of it and arrives in the core's words.
    func removeTrack(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let withClips = try boolArg(a, "with_clips")
        let clips = try idScope(document).clips(onTrack: track.id).count
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
        let count = try idScope(document).tracks.count
        guard let index = try intArg(a, "index"), index >= 0, index < max(count, 1) else {
            throw ToolError(message: "index must be 0…\(max(count - 1, 0)).")
        }
        return try editResult(
            document, "Move Track", [.moveTrack(track: track.id, index: index)])
    }

    /// `set_track` — the header's four toggles (`toggleTrack`, mirrored by
    /// Track ▸ Hide Video / Mute Audio / Lock Track / Solo; the header's S is
    /// `TimelineView.toggleHeader`'s `.solo` case) and its inline rename.
    /// Solo is an audio rule on the track's CONTAINER — the timeline, or a
    /// nest's own tracks: while any track there is soloed, every track that
    /// is not is silent, mute wins on a track that is both, and pictures are
    /// untouched (`core/src/audio.rs`).
    func setTrack(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let track = try trackArg(a, "track", document)
        let name = try stringArg(a, "name")
        let hidden = try boolArg(a, "hidden")
        let muted = try boolArg(a, "muted")
        let locked = try boolArg(a, "locked")
        let solo = try boolArg(a, "solo")
        guard name != nil || hidden != nil || muted != nil || locked != nil || solo != nil else {
            throw ToolError(
                message: "set_track needs at least one of name, hidden, muted, locked, solo.")
        }
        return try editResult(
            document, "Track Properties",
            [
                .setTrack(
                    track: track.id, name: name, hidden: hidden, muted: muted, locked: locked,
                    solo: solo)
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
    ///
    /// **`at` defaults to the playhead, and inside an open nest the playhead
    /// is the NEST's** — which is why this tool is refused in there at all,
    /// by `checkDocumentLevelTicks` on the way to the edit rather than here:
    /// a marker is a chapter point on the exported file and the file is the
    /// timeline's. The app greys the M key's menu item out for the same
    /// reason. An explicit `scope` still reaches the core and hears the
    /// core's own sentence.
    func addMarker(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let at = try optionalTimeArg(a, "at", document) ?? document.playhead
        return try editResult(
            document, "Add Marker",
            [
                .addMarker(
                    at: at, name: try stringArg(a, "name"), chapter: try boolArg(a, "chapter"),
                    color: try stringArg(a, "color"))
            ])
    }

    /// `set_marker` — dragging a marker in the ruler (`MarkerDragSession`) and
    /// the Document tab's marker table (rename, chapter checkbox).
    ///
    /// **Those two UI paths part company inside a nest, and this tool follows
    /// them.** No marker is drawn in the ruler in there (the timeline reads
    /// the scoped project, which has no markers at all), so there is no drag
    /// to mirror and a `time` sent from inside would be measured from the
    /// nest's zero — `checkDocumentLevelTicks` refuses exactly that argument.
    /// The Document tab, which is about the FILE, goes on renaming and
    /// chaptering with a nest open, so `name`, `chapter` and `color` are
    /// accepted in there and land on the document, which is where the marker
    /// is.
    func setMarker(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let marker = try markerArg(a, "marker", document)
        let time = try optionalTimeArg(a, "time", document)
        let name = try stringArg(a, "name")
        let chapter = try boolArg(a, "chapter")
        let color = try stringArg(a, "color")
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
    ///
    /// **It is the marker tool that is NOT refused inside an open nest**, and
    /// the reason is the whole shape of the rule next door: it names an id and
    /// reads no clock, so there is no zero for it to be measured from. The
    /// Remove button beside it is live with a nest open for the same reason.
    /// `markerArg` resolves the id against the TIMELINE's markers on purpose
    /// and says so.
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
    ///
    /// **`background` goes to the core UNREAD** (deepening D1·4,
    /// `designs/reelcut-roadmap-7.md` §2.4): a colour is four numbers each
    /// 0–1 everywhere, so the three-element form `colorArg` used to fill an
    /// alpha into and the clamp it used to apply are both gone, and the core
    /// names what it refused — the wrong length by its type, an out-of-range
    /// component as `canvas background`. It is forwarded even when it is an
    /// explicit `null`, which the core reads as absent; so a call carrying
    /// nothing but that null is the core's identity refusal rather than the
    /// "nothing to change" below, which is what a call carrying no colour key
    /// at all still gets.
    func setCanvas(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let width = try intArg(a, "width")
        let height = try intArg(a, "height")
        if let width = width, width < 16 || width > 16384 {
            throw ToolError(message: "width must be 16…16384 px (got \(width)).")
        }
        if let height = height, height < 16 || height > 16384 {
            throw ToolError(message: "height must be 16…16384 px (got \(height)).")
        }
        let fps = try fpsArg(a, "fps")
        let background = a["background"]
        let rescale = try boolArg(a, "rescale_clips")
        let fitNew = try boolArg(a, "fit_new_clips")
        let timecodeFrames = try boolArg(a, "timecode_frames")
        guard width != nil || height != nil || fps != nil || background != nil || rescale != nil
            || fitNew != nil || timecodeFrames != nil
        else {
            throw ToolError(message: "set_canvas: nothing to change.")
        }
        return try editResult(
            document, "Canvas",
            [
                .setCanvasRaw(
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
