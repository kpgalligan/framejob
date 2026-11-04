import Foundation

/// `reframe_clip` (road map "creator-jobs" VR2a2 and VR2b1, spec §11 VR-26…VR-28):
/// the op tool whose `subjects` the app fills from the analysis cache. It mirrors
/// Clip ▸ Follow Subject… (VR2b2, spec §11 VR-29: this op with `replace: true` per
/// selected clip and a "Backgrounds" backdrop track); every refusal is the core's
/// sentence, and Swift copies none of VR-26's or VR-27's rules (`replace` is
/// passed through as the caller sent it). It reads no `UserDefaults` (AU-68 (f)).
///
/// **Runs on the SERVER thread** (`creatorOffMainTools`), in three hops:
/// - the first main hop resolves the arguments and TRIES the op with no
///   `subjects`, scoped, on the document's project without committing (as the
///   inspector's probe does). Only the core's "no subjects" refusal (VR-26's
///   tenth, LAST so every other one answers the trial) leads to the analysis;
///   an applied, identity or other refused trial goes straight to the last
///   hop;
/// - the wait is `split_at_shots`'s: a new lane owner and CJ-25's bound. Past
///   it the same requests are wanted again on that owner, held by
///   `FramingWant` until every one has ended or the document closes, and the
///   answer is `analyzing`, with no edit;
/// - the subjects are read off main (`FramingSubjects`), and the last main hop
///   refuses a changed project or scope, then applies one op as one undo step,
///   "Reframe Clip".
///
/// `follow: cursor` (VR5, spec §11 VR-50 (i)) never waits: after the trial's "no
/// subjects" the first hop finds the media's cursor file (`AutoZoom.cursorFiles`, its
/// sentences the refusal), and the file is opened and read off main
/// (`FramingCursor.read`) in place of the analysis; the answer's `cached` is true.
///
/// `follow: speaker` (VR6a, spec §11 VR-60 (c)) waits for the analysis as a following
/// kind does; its `mics` and `mic_faces` are passed through, a call addressed to a
/// container other than the open one is refused before the trial, and the last main
/// hop adds `turns` to the subjects (`FramingSpeaker.turns`, Switch by Speaker's reading
/// of the microphones, its refusals SW-24's).
extension AgentServer {

    /// What the first main hop resolves.
    private struct FramingCall {
        let document: ProjectDocument
        let clip: UInt32
        let follow: FramingFollow
        let zoom: Double?
        let whereEmpty: FramingWhereEmpty?
        let fromWidth: UInt32?
        let fromHeight: UInt32?
        let backdrop: UInt32?
        let replace: Bool?
        let mics: [UInt32]?
        let micFaces: [UInt32]?
        /// The analysis to read, or nil when the trial needs none.
        let reading: FramingReading?
        /// The cursor file to read for `follow: cursor`, or nil.
        let cursor: CursorReading?
        let asked: ReelProject
        let scope: UInt32?

        func op(subjects: [String: Any]?) -> ReelOp {
            .reframeClip(
                clip: clip, follow: follow, zoom: zoom, whereEmpty: whereEmpty,
                fromWidth: fromWidth, fromHeight: fromHeight, backdrop: backdrop,
                replace: replace, mics: mics, micFaces: micFaces, subjects: subjects)
        }

        /// The same call reading `reading` or `cursor` instead.
        func with(reading: FramingReading?, cursor: CursorReading?) -> FramingCall {
            FramingCall(
                document: document, clip: clip, follow: follow, zoom: zoom,
                whereEmpty: whereEmpty, fromWidth: fromWidth, fromHeight: fromHeight,
                backdrop: backdrop, replace: replace, mics: mics, micFaces: micFaces,
                reading: reading, cursor: cursor, asked: asked, scope: scope)
        }
    }

    /// The clip's media, its windows and its cursor file (VR-50 (i)).
    private struct CursorReading {
        let media: MediaSnapshot
        let windows: [ClosedRange<Ticks>]
        let files: [UInt32: URL]
    }

    /// The clip's media, its windows, the cache folder and what is missing.
    private struct FramingReading {
        let media: MediaSnapshot
        let windows: [ClosedRange<Ticks>]
        let cacheDir: URL
        let requests: [AnalysisRequest]
    }

    func reframeClip(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16)
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "reframe_clip must run on the server thread — its name is missing "
                    + "from AgentServer.creatorOffMainTools.")
        }
        let call = try onMain { try self.resolveFraming(a) }
        var subjects: [String: Any]?
        if let reading = call.reading {
            if !reading.requests.isEmpty,
                let analyzing = try waitForAnalysis(
                    reading.requests, document: call.document, stop: stop,
                    unmade: "nothing was framed",
                    note: { percent in
                        "Still analyzing the media of clip \(call.clip) (\(percent) %); call "
                            + "reframe_clip again to apply."
                    })
            {
                return analyzing
            }
            subjects = FramingSubjects.read(
                media: reading.media, windows: reading.windows, cacheDir: reading.cacheDir)
        }
        if let cursor = call.cursor {
            do {
                guard let track = try AutoZoom.readTracks(cursor.files)[cursor.media.id] else {
                    throw ToolError(message: "Media \(cursor.media.id)'s cursor file was not read.")
                }
                subjects = try FramingCursor.read(
                    track, media: cursor.media, windows: cursor.windows)
            } catch let error as ToolError {
                throw error
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
        }
        let cached = call.reading?.requests.isEmpty ?? true
        return try onMain {
            let document = call.document
            guard document.project === call.asked, document.scope == call.scope else {
                throw ToolError(
                    message: "the project changed while reframe_clip read the clip's analysis, "
                        + "so nothing was framed. Call reframe_clip again.")
            }
            // VR-60 (c): who speaks when, read on this hop from the microphones' caches.
            var filled = subjects
            if call.follow == .speaker, filled != nil,
                let shown = document.editedProject.snapshot.clip(call.clip)
            {
                do {
                    filled?["turns"] = try FramingSpeaker.turns(
                        document: document, clip: shown, mics: call.mics ?? [])
                } catch let refusal as FramingSpeaker.Refusal {
                    throw ToolError(message: "reframe_clip was refused: " + refusal.sentence)
                }
            }
            return try self.editResult(
                document, FramingWant.actionName, [call.op(subjects: filled)],
                ["cached": cached])
        }
    }

    /// Every argument in the op's order, the trial, and — only when the core
    /// answered "no subjects" — what the analysis must cover.
    private func resolveFraming(_ a: [String: Any]) throws -> FramingCall {
        let document = try target(a)
        _ = try idArg(a, "clip")
        let follow = try requiredEnumArg(a, "follow", FramingFollow.self)
        let clip = try clipArg(a, "clip", document)
        var backdrop: UInt32?
        if let raw = a["backdrop"], !(raw is NSNull) {
            backdrop = try trackArg(a, "backdrop", document).id
        }
        let call = FramingCall(
            document: document, clip: clip.id, follow: follow, zoom: try doubleArg(a, "zoom"),
            whereEmpty: try enumArg(a, "where_empty", FramingWhereEmpty.self),
            fromWidth: try sideArg(a, "from_width"), fromHeight: try sideArg(a, "from_height"),
            backdrop: backdrop, replace: try boolArg(a, "replace"),
            mics: try numbersArg(a, "mics"), micFaces: try numbersArg(a, "mic_faces"),
            reading: nil, cursor: nil, asked: document.project, scope: document.scope)
        let scope = effectiveScope(document)
        if follow == .speaker, scope != document.scope {
            throw ToolError(
                message: "reframe_clip was refused: follow speaker reads its microphones on the "
                    + "open timeline; open that nest first with set_scope")
        }
        let trial: ReelEdit
        do {
            trial = try document.project.applying(call.op(subjects: nil).scoped(scope))
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        guard case .refused(let refusal) = trial,
            refusal.reason == FramingWant.noSubjects(clip.id)
        else { return call }
        let view = scope.flatMap { document.project.scoped($0) } ?? document.project
        guard let entry = FramingAnalysis.windows(clips: [clip.id], in: view).first,
            let media = view.snapshot.media(entry.media)
        else { return call }
        if follow == .cursor {
            // VR-50 (i): the cursor file in place of the analysis; never a wait.
            guard let shown = view.snapshot.clip(clip.id) else { return call }
            let files: [UInt32: URL]
            do {
                files = try AutoZoom.cursorFiles([shown], in: view.snapshot)
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
            return call.with(
                reading: nil,
                cursor: CursorReading(media: media, windows: entry.windows, files: files))
        }
        guard let cacheDir = document.cacheDirectory else {
            throw ToolError(message: ProjectDocument.AnalysisRequestError.noCache.localizedDescription)
        }
        let requests: [AnalysisRequest]
        do {
            requests = try FramingAnalysis.requests(clips: [clip.id], in: document, project: view)
        } catch {
            throw ToolError(message: error.localizedDescription)
        }
        return call.with(
            reading: FramingReading(
                media: media, windows: entry.windows, cacheDir: cacheDir, requests: requests),
            cursor: nil)
    }

    /// `mics` / `mic_faces` (VR-60 (a)): nil when absent, else whole numbers the core
    /// checks itself (an unknown microphone, a 0, a repeat). `make_vertical_version` reads
    /// its own two through it (VR-64 (a)).
    func numbersArg(_ a: [String: Any], _ key: String) throws -> [UInt32]? {
        guard let raw = a[key], !(raw is NSNull) else { return nil }
        guard let list = raw as? [Any] else {
            throw ToolError(message: "\(key) must be a list of whole numbers.")
        }
        return try list.map { value in
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                let n = Self.whole(number), n >= 0, n <= Int(UInt32.max)
            else { throw ToolError(message: "\(key) must be a list of whole numbers.") }
            return UInt32(n)
        }
    }

    /// A whole number of pixels for `from_width` / `from_height`, nil when
    /// absent; the core refuses a 0 itself.
    private func sideArg(_ a: [String: Any], _ key: String) throws -> UInt32? {
        guard let value = try intArg(a, key) else { return nil }
        guard value >= 0, value <= Int(UInt32.max) else {
            throw ToolError(message: "\(key) must be a whole number of pixels, not \(value).")
        }
        return UInt32(value)
    }

    /// Wants the requests (non-empty) under an owner of the call's own and
    /// waits up to CJ-25's bound: nil once every one landed; past the bound
    /// the `analyzing` answer with `note(percent)`, the want held
    /// (`FramingWant`); a failure or a Stop throws naming the kind and the
    /// media, a Stop saying "so <unmade>.". `reframe_clip`'s and
    /// `make_vertical_version`'s wait (spec §11 VR-28, VR-37).
    func waitForAnalysis(
        _ requests: [AnalysisRequest], document: ProjectDocument, stop: AgentCallCancel?,
        unmade: String, note: @escaping (Int) -> String
    ) throws -> String? {
        let lane = AnalysisLane.shared
        let owner = lane.newOwner()
        lane.want(
            requests, owner: owner,
            alive: { document.isOpenForAnalysis && !(stop?.isCancelled ?? false) },
            settled: { document.packageContentsDidChangeOnDisk() })
        let outcome = lane.wait(
            for: requests, owner: owner,
            deadline: Date().addingTimeInterval(AnalysisLane.callWaitLimit),
            cancelled: { stop?.isCancelled ?? false })
        let open = requests.first { lane.run(of: $0)?.outcome != .landed } ?? requests[0]
        let named = "The \(open.kind.rawValue) analysis of media \(open.media.id)"
        switch outcome {
        case .landed:
            lane.release(owner: owner)
            return nil
        case .failed(let why):
            lane.release(owner: owner)
            throw ToolError(message: "\(named) failed: \(why).")
        case .cancelled:
            lane.release(owner: owner)
            throw ToolError(
                message: "\(named) was stopped before it finished, so \(unmade).")
        case .timedOut:
            let hold = FramingWant(requests: requests)
            lane.want(
                requests, owner: owner,
                alive: { document.isOpenForAnalysis && !hold.done },
                settled: {
                    hold.settle()
                    document.packageContentsDidChangeOnDisk()
                })
            return try onMain {
                let covered = FramingWant.covered(requests)
                let media = FramingWant.notLanded(requests)
                let percent = Int((covered * 100).rounded())
                return try self.jsonResult([
                    "ok": true,
                    "analyzing": ["media": media.map { Int($0) }, "covered": covered],
                    "note": note(percent),
                    "project": self.summary(document),
                ])
            }
        }
    }
}

/// The want `reframe_clip` leaves held past CJ-25's bound (spec §11 VR-28):
/// done once every request has ended, which `settled` marks, so the lane
/// drops the owner at its next poll; the owner is never released, so the
/// jobs run on after the call has answered. Its own `NSLock`, never the
/// lane's: `alive` is asked under the lane's lock.
final class FramingWant: @unchecked Sendable {
    /// The undo step's name.
    static let actionName = "Reframe Clip"

    /// VR-26's tenth refusal, the one sentence a trial waits for; built as
    /// `core/src/edit_reframe.rs`'s `no_subjects` builds it, and pinned by
    /// `core/tests/reframe_clip.rs`.
    static func noSubjects(_ clip: UInt32) -> String {
        "clip \(clip) has no subjects to follow; analyze it first"
    }

    private let lock = NSLock()
    private var ended = false
    private let requests: [AnalysisRequest]

    init(requests: [AnalysisRequest]) {
        self.requests = requests
    }

    var done: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ended
    }

    /// Main thread, from the owner's `settled`: done once every request's
    /// run has an outcome.
    func settle() {
        let lane = AnalysisLane.shared
        let all = requests.allSatisfy { lane.run(of: $0)?.outcome != nil }
        guard all else { return }
        lock.lock()
        ended = true
        lock.unlock()
    }

    /// The share of the requests' missing indices their kinds' markers now
    /// cover (`AnalysisStore.coveredCount`), rounded to 2 decimals.
    static func covered(_ requests: [AnalysisRequest]) -> Double {
        var total = 0
        var held = 0
        for request in requests {
            let marker = AnalysisStore.readMarker(
                request.kind, media: request.media.id, in: request.cacheDir)
            let ranges = marker.map { $0.answers(for: request.stamp) ? $0.ranges : [] } ?? []
            for range in request.ranges {
                total += range.count
                held += AnalysisStore.coveredCount(range, covered: ranges)
            }
        }
        guard total > 0 else { return 1 }
        return (Double(held) / Double(total) * 100).rounded() / 100
    }

    /// The media whose requests have not all landed, in request order.
    static func notLanded(_ requests: [AnalysisRequest]) -> [UInt32] {
        var media: [UInt32] = []
        for request in requests where AnalysisLane.shared.run(of: request)?.outcome != .landed {
            if !media.contains(request.media.id) { media.append(request.media.id) }
        }
        return media
    }
}
