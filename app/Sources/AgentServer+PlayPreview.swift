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
        if let seekTo = run.seekTo {
            Thread.sleep(forTimeInterval: seconds / 2)
            seekFrom = onMain { () -> Ticks in
                let here = playback.currentTime
                playback.seek(to: seekTo)
                return here
            }
            Thread.sleep(forTimeInterval: seconds / 2)
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
                + "would, and adds seek_from, where the play was. Refused, changing nothing: "
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
            ],
            required: ["seconds"])
    }
}
#endif
