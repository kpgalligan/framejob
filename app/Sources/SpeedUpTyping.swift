import Foundation

/// Speed Up Typing's Swift half (road map "creator-jobs" CU9b, spec §11 CU-91…CU-93): the
/// sheet's settings and their remembered keys, `plan_typing` asked of the core through
/// `ReelCursor` (this file names no `rc_*`, CJ-8 (l)) with its answer read into ops, and the
/// speech step — a media with sound under a stretch and no stored `speech` gets its spans from
/// its voice-activity cache, as Duck by Speech does, in the same undo step. Both doors —
/// Clip ▸ Speed Up Typing… (`SpeedUpTypingSheetController`) and `speed_up_typing`
/// (`AgentServer+SpeedUpTyping.swift`) — resolve here. The cursor files are found and read
/// through `AutoZoom.cursorFiles` and `AutoZoom.readTracks`.

/// What the sheet sets (CU-92's defaults; Keep pitch on is the owner's answer).
struct SpeedUpTypingSettings: Equatable {
    var rate = 4.0, shortest = 3.0, keepPitch = true

    static let rateRange: ClosedRange<Double> = 2...8
    static let shortestRange: ClosedRange<Double> = 1...30

    static let rateKey = "FrameJobSpeedUpTypingRate"
    static let shortestKey = "FrameJobSpeedUpTypingShortest"
    static let keepPitchKey = "FrameJobSpeedUpTypingKeepPitch"

    /// The remembered values, each clamped into its range; the default for a key not stored.
    /// Read through `double(forKey:)` and `bool(forKey:)`, so a launch argument's string
    /// (`-FrameJobSpeedUpTypingRate 6`) reads as its number.
    static func remembered(_ d: UserDefaults) -> SpeedUpTypingSettings {
        var s = SpeedUpTypingSettings()
        func number(_ key: String, _ range: ClosedRange<Double>, _ value: inout Double) {
            guard d.object(forKey: key) != nil else { return }
            let v = d.double(forKey: key)
            if v.isFinite, v > 0 { value = min(max(v, range.lowerBound), range.upperBound) }
        }
        number(rateKey, rateRange, &s.rate)
        number(shortestKey, shortestRange, &s.shortest)
        if d.object(forKey: keepPitchKey) != nil { s.keepPitch = d.bool(forKey: keepPitchKey) }
        return s
    }

    /// Writes only the keys whose value differs from `opened`'s, so a sheet whose controls
    /// were not changed writes nothing (mcp.py's DEFAULTS MOVED guard).
    func remember(changedFrom opened: SpeedUpTypingSettings, in d: UserDefaults) {
        if rate != opened.rate { d.set(rate, forKey: Self.rateKey) }
        if shortest != opened.shortest { d.set(shortest, forKey: Self.shortestKey) }
        if keepPitch != opened.keepPitch { d.set(keepPitch, forKey: Self.keepPitchKey) }
    }
}

/// `plan_typing`'s answer: the `retime_range` ops right to left, the counts, each range with
/// where its end lands, and the time saved.
struct SpeedUpTypingPlan {
    let ops: [ReelOp]
    let stretches, short: Int
    let ranges: [(from: Ticks, to: Ticks, spedTo: Ticks)]
    let saved: Ticks
}

/// The speech step's answer (CU-93): the `set_media_speech` ops to send first, the names of
/// media whose detection has not finished, or a sentence.
enum SpeedUpTypingSpeech: Equatable {
    case ready([ReelOp])
    case pending([String])
    case refused(String)

    static func == (a: SpeedUpTypingSpeech, b: SpeedUpTypingSpeech) -> Bool {
        switch (a, b) {
        case (.ready(let x), .ready(let y)): return x.map(\.json) == y.map(\.json)
        case (.pending(let x), .pending(let y)): return x == y
        case (.refused(let x), .refused(let y)): return x == y
        default: return false
        }
    }
}

/// What `resolve` answers: a plan with the speech ops it needs first, or the media waited for.
enum SpeedUpTypingOutcome {
    case planned(speechOps: [ReelOp], plan: SpeedUpTypingPlan)
    case waiting([String])
}

enum SpeedUpTyping {
    /// The undo step's name, both doors.
    static let actionName = "Speed Up Typing"
    /// How long the sheet waits for speech detection (AU-68's bound, as
    /// `RecordingEnhance.waitLimit`).
    static let waitLimit: TimeInterval = 300

    /// Whether a wait of `elapsed` seconds has reached `waitLimit`.
    static func gaveUp(waitingFor elapsed: TimeInterval) -> Bool {
        elapsed >= waitLimit
    }

    /// A sentence either door shows as it is.
    struct Refusal: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// `plan_typing`'s request JSON for `clips` (container ticks `from`/`to`, nil for none).
    static func request(
        _ clips: [UInt32], settings: SpeedUpTypingSettings, from: Ticks?, to: Ticks?
    ) -> String {
        var args: [String: Any] = [
            "clips": clips.map { Int($0) }, "rate": settings.rate,
            "shortest": settings.shortest, "keep_pitch": settings.keepPitch,
        ]
        if let from { args["from"] = from }
        if let to { args["to"] = to }
        let data = (try? JSONSerialization.data(withJSONObject: ["plan_typing": args])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The speech step for the media `plan_typing` named in `needs_speech` (CU-93), in order:
    /// a media whose `speech` is stored is skipped (AU-111); no file is refused; a current
    /// cache (`isCurrent`) that loads becomes a `set_media_speech` op; otherwise pending while
    /// detection is `available`, and refused when it is not.
    static func speech(
        for media: [UInt32], in snapshot: ProjectSnapshot, cacheDirectory: URL?,
        available: Bool, isCurrent: (MediaSnapshot) -> Bool
    ) -> SpeedUpTypingSpeech {
        var ops: [ReelOp] = []
        var pending: [String] = []
        for id in media {
            guard let m = snapshot.media(id), m.speech == nil else { continue }
            guard mediaURL(for: m) != nil else {
                return .refused("\(m.name) is offline, so its speech cannot be read.")
            }
            if isCurrent(m), let directory = cacheDirectory,
                let p = MediaImporter.loadSpeech(for: id, in: directory)
            {
                ops.append(.setMediaSpeech(media: id, spans: DuckSpeech.spans(p, duration: m.duration)))
            } else if available {
                pending.append(m.name)
            } else {
                return .refused(
                    "Speech detection is unavailable on this Mac, so Speed Up Typing cannot "
                        + "tell typing from talking.")
            }
        }
        return pending.isEmpty ? .ready(ops) : .pending(pending)
    }

    /// Whether `media`'s speech cache in `cacheDirectory` is current, its file stat'ed.
    static func cacheIsCurrent(_ media: MediaSnapshot, in cacheDirectory: URL?) -> Bool {
        guard let cacheDirectory, let url = mediaURL(for: media) else { return false }
        let stamp = MediaImporter.CacheStamp.stamp(for: media, url: url)
        return MediaImporter.speechIsCurrent(for: media, stamp: stamp, in: cacheDirectory)
    }

    /// Plans over `clips` of `project` (the edited one, so inside a nest the nest's), makes the
    /// speech ops it asks for, applies them to the pure handle and plans again; throws the
    /// core's sentence or the speech step's as a `Refusal`.
    static func resolve(
        _ clips: [ClipSnapshot], tracks: [UInt32: ReelCursor], project: ReelProject,
        cacheDirectory: URL?, settings: SpeedUpTypingSettings, from: Ticks?, to: Ticks?,
        available: Bool = SileroVAD.isAvailable
    ) throws -> SpeedUpTypingOutcome {
        let first = try plan(
            clips, tracks: tracks, project: project, settings: settings, from: from, to: to)
        guard !first.needs.isEmpty else { return .planned(speechOps: [], plan: first.plan) }
        let speechOps: [ReelOp]
        switch speech(
            for: first.needs, in: project.snapshot, cacheDirectory: cacheDirectory,
            available: available, isCurrent: { cacheIsCurrent($0, in: cacheDirectory) })
        {
        case .refused(let why): throw Refusal(message: why)
        case .pending(let names): return .waiting(names)
        case .ready(let ops): speechOps = ops
        }
        guard case .applied(let spoken)? = try? project.applying(speechOps) else {
            throw Refusal(message: "The speech spans could not be saved, so nothing was sped up.")
        }
        let second = try plan(
            clips, tracks: tracks, project: spoken, settings: settings, from: from, to: to)
        guard second.needs.isEmpty else {
            throw Refusal(message: "The speech spans could not be saved, so nothing was sped up.")
        }
        return .planned(speechOps: speechOps, plan: second.plan)
    }

    /// Asks the core for the plan, one track per clip; the media it needs speech for, and the
    /// plan (empty while any are needed).
    private static func plan(
        _ clips: [ClipSnapshot], tracks: [UInt32: ReelCursor], project: ReelProject,
        settings: SpeedUpTypingSettings, from: Ticks?, to: Ticks?
    ) throws -> (needs: [UInt32], plan: SpeedUpTypingPlan) {
        var ordered: [ReelCursor] = []
        for clip in clips {
            guard case .media(let id, _, _) = clip.source, let track = tracks[id] else {
                throw Refusal(message: "Clip \(clip.id)'s cursor file was not read.")
            }
            ordered.append(track)
        }
        let text: String
        do {
            text = try ReelCursor.query(
                request(clips.map(\.id), settings: settings, from: from, to: to),
                tracks: ordered, project: project)
        } catch {
            let reason = (error as? ReelCoreError)?.message ?? error.localizedDescription
            throw Refusal(message: AutoZoom.sentence(reason))
        }
        guard let answer = try? JSONSerialization.jsonObject(with: Data(text.utf8))
            as? [String: Any]
        else { throw Refusal(message: "Speed Up Typing's plan could not be read.") }
        func number(_ o: [String: Any], _ key: String) -> Int64 {
            (o[key] as? NSNumber)?.int64Value ?? 0
        }
        let ops = try ((answer["ops"] as? [[String: Any]]) ?? []).map { o -> ReelOp in
            guard o["op"] as? String == "retime_range" else {
                throw Refusal(message: "Speed Up Typing's plan named an op it does not make.")
            }
            return .retimeRange(
                from: number(o, "from"), to: number(o, "to"),
                rate: (o["rate"] as? NSNumber)?.doubleValue ?? settings.rate,
                keepPitch: (o["keep_pitch"] as? Bool) ?? settings.keepPitch)
        }
        let ranges = ((answer["ranges"] as? [[String: Any]]) ?? []).map {
            (from: number($0, "from"), to: number($0, "to"), spedTo: number($0, "sped_to"))
        }
        let needs = ((answer["needs_speech"] as? [NSNumber]) ?? []).map(\.uint32Value)
        return (
            needs,
            SpeedUpTypingPlan(
                ops: ops, stretches: Int(number(answer, "stretches")),
                short: Int(number(answer, "short")), ranges: ranges,
                saved: number(answer, "saved"))
        )
    }

    /// The sheet's summary: what Apply would do, or why it would change nothing.
    static func summary(_ plan: SpeedUpTypingPlan, settings: SpeedUpTypingSettings) -> String {
        guard !plan.ops.isEmpty else {
            return "No typing stretch without speech or a shortcut lasts "
                + "\(plain(settings.shortest)) s or more in the selected clips, so nothing "
                + "would change."
        }
        let n = plan.ops.count
        let stretches = n == 1 ? "1 typing stretch" : "\(n) typing stretches"
        let seconds = String(format: "%.1f", Double(plan.saved) / Double(ReelTime.perSecond))
        return "\(stretches) sped up ×\(plain(settings.rate)), saving \(seconds) s."
    }

    /// A number with no ".0" on a whole one.
    static func plain(_ v: Double) -> String {
        v.rounded() == v && abs(v) < 1e15 ? String(Int64(v)) : String(format: "%g", v)
    }
}
