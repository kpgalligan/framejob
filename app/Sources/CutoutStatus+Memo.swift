import AppKit

extension CutoutStatus {
    /// The Background section's Status read-out's last answer (road map creator-jobs CO3, spec
    /// §11 CO-30 (d)), after `IsolationCache.Memo`: held through a live gesture and while the
    /// document's handles and its published `ReverseSource` resolution are unchanged, so a
    /// playhead tick reads nothing again.
    ///
    /// **The ticker.** While the held state is analysing or failed and the watched read-out is in
    /// a window, a 0.5 s timer on the main run loop re-reads only the lane: each of the owner's
    /// requests' runs (outcome and `endedAt`) and the running job's progress. A changed run — a
    /// job ending, `AnalysisLane.retry` clearing a failure, a re-run failing again — or a `masks`
    /// or `foreground` `.analysisDidPublish` for the document's cache folder recomputes the
    /// status: `onChange` when its state changed, else the read-out refreshed alone. Otherwise an
    /// analysing status takes the new progress from the held ranges. One per `ClipPane`; main
    /// only.
    final class Memo {
        /// The pane's refresh, when a tick changed the state.
        var onChange: (() -> Void)?

        private weak var document: ProjectDocument?
        private weak var project: ReelProject?
        private weak var edited: ReelProject?
        private var clip: UInt32?
        private var resolution: ReverseResolution?
        private var held: Detail?
        private var runs = ""
        private var published = false
        private weak var readout: OptionDisplayControl?
        private var timer: Timer?
        private var observer: NSObjectProtocol?

        init() {
            observer = NotificationCenter.default.addObserver(
                forName: .analysisDidPublish, object: nil, queue: .main
            ) { [weak self] note in
                MainActor.assumeIsolated { self?.didPublish(note) }
            }
        }

        deinit {
            timer?.invalidate()
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func status(of clip: UInt32, in document: ProjectDocument) -> CutoutClipStatus {
            let resolution = ReverseSource.shared.resolution(for: document.recipeKey)
            if let held, self.document === document, self.clip == clip,
                document.isLiveEditing
                    || (project === document.project && edited === document.editedProject
                        && self.resolution == resolution)
            {
                return held.status
            }
            let detail = CutoutStatus.detail(of: clip, in: document)
            self.document = document
            project = document.project
            edited = document.editedProject
            self.clip = clip
            self.resolution = resolution
            held = detail
            runs = Self.runs(of: detail)
            published = false
            return detail.status
        }

        /// Keeps the ticker running while the held status for `clip` is analysing or failed and
        /// `readout` is in a window; the read-out's refresh calls it.
        func watch(_ readout: OptionDisplayControl, clip: UInt32, document: ProjectDocument) {
            self.readout = readout
            guard let held, self.clip == clip, self.document === document, Self.ticks(held)
            else {
                stop()
                return
            }
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        /// Drops the held status: the next read computes it again.
        func invalidate() {
            held = nil
            project = nil
            edited = nil
        }

        private func stop() {
            timer?.invalidate()
            timer = nil
        }

        private static func ticks(_ detail: Detail) -> Bool {
            switch detail.status.state {
            case .analyzing, .failed: return true
            default: return false
            }
        }

        /// Each of the owner's requests of the held media: its ranges, outcome and end.
        private static func runs(of detail: Detail) -> String {
            guard let media = detail.media, let cacheDir = detail.cacheDir else { return "" }
            return CutoutStatus.ownerRequests(
                detail.owner, media: media.id, cacheDir: cacheDir, kind: detail.kind)
                .map { request -> String in
                    let run = AnalysisLane.shared.run(of: request)
                    return "\(request.ranges)|\(String(describing: run?.outcome))|"
                        + "\(String(describing: run?.endedAt))"
                }.joined(separator: ";")
        }

        private func didPublish(_ note: Notification) {
            guard [AnalysisKind.masks.rawValue, AnalysisKind.foreground.rawValue]
                .contains(note.userInfo?["kind"] as? String ?? ""),
                let folder = note.userInfo?["cacheDir"] as? String,
                document?.intendedCacheDirectory?.standardizedFileURL.path == folder
            else { return }
            published = true
        }

        private func tick() {
            guard let document, let clip, let readout, readout.window != nil, let held,
                Self.ticks(held)
            else {
                stop()
                return
            }
            if published || Self.runs(of: held) != runs {
                let before = held.status.state
                invalidate()
                let next = status(of: clip, in: document)
                if next.state.sameKind(as: before) {
                    readout.refresh()
                    watch(readout, clip: clip, document: document)
                } else {
                    onChange?()
                }
                return
            }
            guard case .analyzing = held.status.state, let media = held.media,
                let cacheDir = held.cacheDir
            else { return }
            let running = CutoutStatus.runningRequest(
                CutoutStatus.ownerRequests(
                    held.owner, media: media.id, cacheDir: cacheDir, kind: held.kind))
            let fraction = running.flatMap { AnalysisLane.shared.progress(of: $0) } ?? 0
            let progress = CutoutStatus.progress(
                need: held.need, covered: held.coverage, running: running?.ranges,
                fraction: fraction)
            guard held.status.state != .analyzing(progress) else { return }
            let status = held.status
            self.held = Detail(
                status: CutoutClipStatus(
                    clip: status.clip, media: status.media, state: .analyzing(progress),
                    frames: status.frames, covered: status.covered,
                    subjectFound: status.subjectFound, error: status.error),
                media: held.media, need: held.need, coverage: held.coverage, pack: held.pack,
                owner: held.owner, cacheDir: held.cacheDir, kind: held.kind)
            readout.refresh()
        }
    }
}
