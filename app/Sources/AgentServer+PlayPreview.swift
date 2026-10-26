import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `play_preview` — a dev tool (issue #127, spec §11 G-36): play a project's
/// preview forward for a while, through the transport's own `setRate` and
/// `seek(to:)`, and answer how many of the frames it passed the compositor
/// composed, and how long each took (`PlaybackTrial.swift`'s record). What
/// `playback_prefetch_proof.py` measures preview playback with, before and
/// after the graphics prefetch follows it.
///
/// **It runs on the SERVER thread** (`devOffMainTools`): it sleeps for the
/// play, and a wait may not hold the main thread. Every touch of the
/// transport is an `onMain` hop.
///
/// **Arguments are read and refused before anything moves**, and so are a
/// document with no editor window and a preview with no item. Then it
/// pauses, waits up to 5 s for any seek to land (refused when one has not),
/// notes the playhead, starts the trial, sets the rate and sleeps; with
/// `seek_to`, half way through it notes the playhead (`seek_from`) and seeks
/// there through the asked door. It ends paused where the play reached.
///
/// **`stale_ticks`** (issue #329) hands the prefetch requests the seek's
/// session must not follow, through `GraphicPrefetch.reach`, the
/// compositor's own call: in the seek's hop, before the session is armed,
/// or with `stale_armed` once a frame in its first `armFrames` frames was
/// composed (so its request armed it), waited for at most `min(2 s,
/// seconds / 2)` from the seek. The second half is still `seconds / 2` from
/// the seek, the wait included. `stale_reached` answers the ticks reported:
/// all of them, or none when the armed wait ran out.
extension AgentServer {

    /// What the first hop read, carried to the next ones.
    private struct PlayRun {
        let playback: Playback
        let key: Int
        let frameTicks: Ticks
        let seekTo: Ticks?
    }

    func playPreview(_ a: [String: Any]) throws -> String {
        guard let seconds = try doubleArg(a, "seconds") else {
            throw ToolError(message: "Missing required argument: seconds (0.5 to 60)")
        }
        guard seconds >= 0.5, seconds <= 60 else {
            throw ToolError(message: "seconds must be from 0.5 to 60 (got \(seconds)).")
        }
        let rate = try doubleArg(a, "rate") ?? 1
        guard [1.0, 2.0, 4.0].contains(rate) else {
            throw ToolError(message: "rate must be 1, 2 or 4 (got \(rate)).")
        }
        let digests = try boolArg(a, "digests") ?? false
        let staleTicks = try intsArg(a, "stale_ticks").map { $0.map(Ticks.init) }
        let staleArmed = try boolArg(a, "stale_armed")
        let asksSeek = a["seek_to"].map { !($0 is NSNull) } ?? false
        if let staleTicks {
            guard asksSeek else {
                throw ToolError(
                    message: "stale_ticks needs seek_to: a stale request is served after a seek.")
            }
            guard !staleTicks.isEmpty else {
                throw ToolError(message: "stale_ticks must list at least one tick.")
            }
            if let negative = staleTicks.first(where: { $0 < 0 }) {
                throw ToolError(
                    message: "stale_ticks must hold ticks of 0 or more (got \(negative)).")
            }
        } else if staleArmed != nil {
            throw ToolError(
                message: "stale_armed needs stale_ticks: it says when those ticks are reported.")
        }

        let run = try onMain { () throws -> PlayRun in
            let document = try self.target(a)
            let name = Self.path(of: document) ?? document.displayName ?? "Untitled"
            guard let editor = self.editor(document) else {
                throw ToolError(
                    message: "The project \(name) has no window: play_preview plays only its "
                        + "editor window's preview.")
            }
            let seekTo = try self.optionalTimeArg(a, "seek_to", document)
            let playback = editor.playback
            guard let built = playback.built else {
                throw ToolError(
                    message: "The project \(name) has nothing to play: its preview has no item "
                        + "(an empty timeline, or a build still in flight).")
            }
            playback.pause()
            let frame = CompositionBuilder.ticks(built.videoConfiguration.frameDuration)
            return PlayRun(
                playback: playback, key: playback.recipeKey, frameTicks: max(1, frame),
                seekTo: seekTo)
        }
        let playback = run.playback
        let settleBy = Date().addingTimeInterval(5)
        while onMain({ playback.isSeeking }) {
            guard Date() < settleBy else {
                throw ToolError(
                    message: "The preview was still seeking after 5 s, so play_preview did not "
                        + "start.")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        let (from, started) = onMain { () -> (Ticks, Date) in
            let from = playback.currentTime
            PlaybackTrials.shared.begin(run.key, digests: digests)
            let started = Date()
            playback.setRate(Float(rate))
            return (from, started)
        }
        var seekFrom: Ticks?
        var staleReached: [Ticks]?
        if let seekTo = run.seekTo {
            Thread.sleep(forTimeInterval: seconds / 2)
            let armed = staleArmed ?? false
            let (here, before) = onMain { () -> (Ticks, Int) in
                let here = playback.currentTime
                let before = PlaybackTrials.shared.recorded(run.key).count
                // The seek's session is installed synchronously here
                // (`startSeek` → `syncPrefetch(seeking: true)`).
                playback.seek(to: seekTo)
                if let staleTicks, !armed {
                    for tick in staleTicks { GraphicPrefetch.shared.reach(run.key, ticks: tick) }
                }
                return (here, before)
            }
            let seekAt = Date()
            seekFrom = here
            if let staleTicks {
                staleReached = armed
                    ? reachOnceArmed(
                        run, staleTicks, after: before, from: seekTo,
                        by: seekAt.addingTimeInterval(min(2, seconds / 2)))
                    : staleTicks
            }
            Thread.sleep(
                forTimeInterval: max(0, seconds / 2 - Date().timeIntervalSince(seekAt)))
        } else {
            Thread.sleep(forTimeInterval: seconds)
        }
        let (to, wall, served) = onMain { () -> (Ticks, Double, [PlaybackTrials.Served]) in
            let to = playback.currentTime
            playback.pause()
            let wall = Date().timeIntervalSince(started)
            return (to, wall, PlaybackTrials.shared.end(run.key))
        }

        let f = run.frameTicks
        let k0 = Self.floorDiv(run.seekTo ?? from, f)
        let k1 = Self.floorDiv(to - 1, f)
        let expected = max(0, k1 - k0 + 1)
        let composed = Set(
            served.map { Self.floorDiv($0.ticks, f) }.filter { $0 >= k0 && $0 <= k1 })
        let ratio = expected > 0 ? Double(composed.count) / Double(expected) : 0
        var fields: [(String, Any)] = [
            ("from", from), ("to", to), ("rate", rate),
            ("wall_seconds", Self.rounded(wall, 3)),
            ("frame_ticks", f),
            ("frames_expected", expected),
            ("frames_composed", composed.count),
            ("composed_ratio", Self.rounded(ratio, 3)),
            ("compose_ms", Self.composeMs(served)),
        ]
        if let seekFrom { fields.append(("seek_from", seekFrom)) }
        if let staleReached { fields.append(("stale_reached", staleReached)) }
        if digests {
            var table: [String: String] = [:]
            for frame in served {
                guard let digest = frame.digest, table[String(frame.ticks)] == nil else { continue }
                table[String(frame.ticks)] = digest
            }
            fields.append(("digests", table))
        }
        return try orderedResult(fields)
    }

    /// `stale_armed`'s wait: polls every 10 ms, until `deadline`, for a frame
    /// served after the first `before` with ticks in the seek's first
    /// `armFrames` frames — composed, so its `reach` armed the session —
    /// then reports `ticks` and answers them; [] when the deadline came
    /// first. On the server thread.
    private func reachOnceArmed(
        _ run: PlayRun, _ ticks: [Ticks], after before: Int, from seekTo: Ticks, by deadline: Date
    ) -> [Ticks] {
        let window = seekTo..<(seekTo + Ticks(GraphicPrefetch.armFrames) * run.frameTicks)
        while true {
            let served = PlaybackTrials.shared.recorded(run.key)
            if served.dropFirst(before).contains(where: { window.contains($0.ticks) }) {
                for tick in ticks { GraphicPrefetch.shared.reach(run.key, ticks: tick) }
                return ticks
            }
            guard Date() < deadline else { return [] }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    /// ⌊a / b⌋ for a positive `b`, negative `a` included.
    private static func floorDiv(_ a: Ticks, _ b: Ticks) -> Ticks {
        let q = a / b
        return (a % b != 0 && a < 0) ? q - 1 : q
    }

    private static func rounded(_ value: Double, _ places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }

    /// Mean, nearest-rank 95th percentile and worst of the served frames'
    /// compose times, in milliseconds; zeros when none was served.
    private static func composeMs(_ served: [PlaybackTrials.Served]) -> [String: Any] {
        let ms = served.map { $0.seconds * 1000 }.sorted()
        guard let worst = ms.last else { return ["mean": 0, "p95": 0, "worst": 0] }
        let mean = ms.reduce(0, +) / Double(ms.count)
        let rank = max(1, Int((0.95 * Double(ms.count)).rounded(.up)))
        return [
            "mean": rounded(mean, 2), "p95": rounded(ms[rank - 1], 2), "worst": rounded(worst, 2),
        ]
    }

    /// `jsonResult`, with the answer's keys in `fields`' order.
    private func orderedResult(_ fields: [(String, Any)]) throws -> String {
        var parts: [String] = []
        for (key, value) in fields {
            let name = try JSONSerialization.data(withJSONObject: key, options: .fragmentsAllowed)
            let body = try JSONSerialization.data(
                withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
            parts.append(String(decoding: name, as: UTF8.self) + ":"
                + String(decoding: body, as: UTF8.self))
        }
        return try callResult(
            content: [["type": "text", "text": "{" + parts.joined(separator: ",") + "}"]],
            isError: false)
    }

    // MARK: - Catalog

    func playPreviewTool() -> [String: Any] {
        tool(
            "play_preview",
            "DEV TOOL (absent from Distribution builds). Play a project's preview forward for "
                + "seconds at rate (1, 2 or 4) through the transport's own calls, then pause, "
                + "and answer how much of it the compositor composed: from and to (ticks), "
                + "rate, wall_seconds, frame_ticks, frames_expected (the frames from from — or "
                + "from seek_to — up to to), frames_composed (how many of those the compositor "
                + "finished), composed_ratio, and compose_ms {mean, p95, worst} over every "
                + "frame it served. It pauses first and waits up to 5 s for a seek to land. "
                + "digests: true adds a tick → SHA-256 table of each served frame's pixels "
                + "(slower). seek_to seeks there half way through, as a click on the ruler "
                + "would, and adds seek_from, where the play was. stale_ticks (with seek_to) "
                + "reports those ticks to the graphics prefetch as requests the compositor "
                + "reached just after the seek, the way a request for the old position served "
                + "before AVFoundation cancels it would; stale_armed: true reports them only "
                + "once a frame in the seek's first 4 frames was composed (waiting at most 2 s "
                + "or half of seconds, whichever is less). Either adds stale_reached, the ticks "
                + "actually reported ([] when the armed wait ran out). Refused, changing "
                + "nothing: stale_ticks without seek_to, an empty or negative stale_ticks, "
                + "stale_armed without stale_ticks, "
                + "a project with no editor window and a preview with nothing to play. "
                + "Refused after pausing the preview: a preview still seeking after 5 s.",
            [
                "seconds": [
                    "type": "number", "minimum": 0.5, "maximum": 60,
                    "description": "How long to play, in wall seconds (0.5 to 60).",
                ],
                "rate": [
                    "type": "number", "enum": [1, 2, 4],
                    "description": "The transport rate, forward: 1 (default), 2 or 4.",
                ],
                "digests": [
                    "type": "boolean",
                    "description": "Answer each served frame's SHA-256 by its tick. Default "
                        + "false.",
                ],
                "seek_to": [
                    "type": "integer",
                    "description": "A time in ticks (600000 per second), snapped to the frame "
                        + "grid, to seek to half way through the play.",
                ],
                "stale_ticks": [
                    "type": "array", "items": ["type": "integer", "minimum": 0], "minItems": 1,
                    "description": "Times in ticks to report to the graphics prefetch as "
                        + "requests reached after the seek (needs seek_to). Answered back as "
                        + "stale_reached.",
                ],
                "stale_armed": [
                    "type": "boolean",
                    "description": "Report stale_ticks only once the seek's session is armed: "
                        + "a frame in its first 4 frames composed. Default false: report "
                        + "them in the seek's own step.",
                ],
            ],
            required: ["seconds"])
    }
}
#endif
