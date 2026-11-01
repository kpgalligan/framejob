import Foundation

/// The 48 kHz frames of the file a segment reads that its isolation render
/// covers (spec §11 AU-51): `[⌊sourceIn·2/25⌋, ⌈(sourceIn + sourceDuration)·2/25⌉)`.
struct IsolationWindow: Equatable {
    let firstFrame: Int64
    let endFrame: Int64
}

/// What the Sound tab's Voice Isolation section says about one clip (AU-56).
enum IsolationStatus: Equatable {
    case off, unsupported, waitingForReverse, rendering, ready, failed(String)
}

/// One isolated segment's render as the builder looks it up: the clip and
/// everything in the segment that places the window. Two segments of one
/// clip are two keys.
struct IsolationSegmentKey: Hashable {
    let clip: UInt32
    let start: Ticks
    let sourceIn: Ticks
    let sourceDuration: Ticks

    init(_ s: PlanSegment) {
        clip = s.clip
        start = s.start
        sourceIn = s.sourceIn
        sourceDuration = s.sourceDuration
    }
}

/// The `cache/isolated/` half of the package (spec §5.6, §11 AU-52): a clip
/// window's isolated voice, rendered once by `IsolationRenderer` on
/// `RampAudioRenders` and named by everything that shapes it — never the
/// Amount, which is a crossfade in the tap (AU-53).
enum IsolationCache {
    /// The subdirectory of `cache/` this feature owns.
    static let directoryName = "isolated"
    /// What "Isolate voice" turns on (AU-56): S2's pauses −14 dB with the
    /// room tone kept, where 1 makes them dead air.
    static let defaultAmount = 0.8

    static func directory(in cache: URL) -> URL {
        cache.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// A segment the render serves (AU-55): ×1, no ramp and no freeze.
    static func isolatable(_ s: PlanSegment) -> Bool {
        s.duration > 0 && s.ramp == nil && !s.isTimeScaled
    }

    /// The nearest 48 kHz frame of a tick count, ⌊(2t + 12) / 25⌋ — floor
    /// division, so a negative count rounds the same way (AU-53). 2t/25 is
    /// never a half, so there is no tie.
    static func frame(ofTicks t: Ticks) -> Int64 {
        floorDiv(2 * t + 12, 25)
    }

    private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    static func window(of s: PlanSegment) -> IsolationWindow {
        let end = s.sourceIn + s.sourceDuration
        return IsolationWindow(
            firstFrame: floorDiv(2 * s.sourceIn, 25), endFrame: -floorDiv(-2 * end, 25))
    }

    /// The wet index's offset from a composition input frame: the
    /// placement's source-in minus its place, rounded ONCE, less the
    /// window's first frame (AU-53), so a place and a source-in off the
    /// 48 kHz grid cannot round apart.
    static func wetOffset(at: Ticks, sourceIn: Ticks, window: IsolationWindow) -> Int64 {
        frame(ofTicks: sourceIn - at) - window.firstFrame
    }

    /// `<media>-<16 hex>.caf`: FNV-1a 64 over the MEDIA file's path, size and
    /// modification second, `IsolationRenderer.version`, the reversal, the
    /// model (0, High Quality Voice), the preroll and the window — not the
    /// Amount (AU-52). `RampAudioCache.name`'s hash. Nil when the media
    /// cannot be stat'ed.
    static func name(media: UInt32, mediaFile: URL, reversed: Bool, window: IsolationWindow)
        -> String?
    {
        let attributes = try? FileManager.default.attributesOfItem(atPath: mediaFile.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value else { return nil }
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(mediaFile.path)|\(size)|\(Int64(modified.rounded()))"
            + "|v\(IsolationRenderer.version)|r\(reversed ? 1 : 0)|model0"
            + "|p\(IsolationRenderer.prerollFrames)|w\(window.firstFrame):\(window.endFrame)"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return "\(media)-" + String(repeating: "0", count: max(0, 16 - hex.count)) + hex + ".caf"
    }

    /// The one segment's request, or nil: the clip asks for isolation, the
    /// segment is isolatable, there is an `isolated` folder, its media
    /// resolves and its reverse (when reversed) is not pending. The source is
    /// the reversed file for a reversed clip, else the media file
    /// (`RampAudioRenders` reads its 48 kHz copy).
    static func request(
        for s: PlanSegment, dsp: AudioDSPParameters, urls: [UInt32: URL],
        reverse: ReverseResolution
    ) -> RampAudioRequest? {
        guard dsp.wantsIsolation(s.clip), isolatable(s), let directory = reverse.isolated,
            let mediaFile = urls[s.media], !reverse.pending.contains(s.clip)
        else { return nil }
        let reversedFile = reverse.ready[s.clip]
        let window = window(of: s)
        guard let name = name(
            media: s.media, mediaFile: mediaFile, reversed: reversedFile != nil, window: window)
        else { return nil }
        return RampAudioRequest(
            clip: s.clip, media: s.media, destination: directory.appendingPathComponent(name),
            source: reversedFile ?? mediaFile, reversed: reversedFile != nil,
            job: .isolation(window))
    }

    /// Every isolated window of `plan`, one request per file.
    static func requests(
        plan: CompositionPlan, dsp: AudioDSPParameters, urls: [UInt32: URL],
        reverse: ReverseResolution
    ) -> [RampAudioRequest] {
        guard dsp.isolates else { return [] }
        var out: [RampAudioRequest] = []
        var seen: Set<URL> = []
        for planTrack in plan.audioTracks {
            for s in planTrack.segments {
                guard let request = request(for: s, dsp: dsp, urls: urls, reverse: reverse),
                    seen.insert(request.destination).inserted
                else { continue }
                out.append(request)
            }
        }
        return out
    }

    /// `.ready` when its file exists, `.failed` when it failed in this
    /// launch, else `.rendering`.
    static func status(of request: RampAudioRequest) -> IsolationStatus {
        if FileManager.default.fileExists(atPath: request.destination.path) { return .ready }
        if let message = RampAudioRenders.shared.failure(for: request.destination) {
            return .failed(message)
        }
        return .rendering
    }

    /// One clip's state in `document`: its built requests' (a failure first,
    /// then a pending render), else why there is none. The plans are decoded
    /// only when the clip asks for isolation (both with a nest open, as
    /// `ensureRampAudio`).
    static func status(of clip: UInt32, in document: ProjectDocument) -> IsolationStatus {
        let dsp = AudioDSPParameters(snapshot: document.project.snapshot)
        guard dsp.wantsIsolation(clip) else { return .off }
        let reverse = ReverseSource.shared.resolution(for: document.recipeKey)
        let urls = document.mediaURLs()
        var states: [IsolationStatus] = []
        var unsupported = false
        var waiting = false
        var missing = false
        let handles = document.scope == nil
            ? [document.project] : [document.project, document.editedProject]
        for handle in handles {
            guard let plan = handle.plan else { continue }
            for s in plan.audioTracks.flatMap(\.segments) where s.clip == clip && s.duration > 0 {
                if !isolatable(s) {
                    unsupported = true
                } else if reverse.pending.contains(clip) {
                    waiting = true
                } else if let request = request(for: s, dsp: dsp, urls: urls, reverse: reverse) {
                    states.append(status(of: request))
                } else {
                    missing = true
                }
            }
        }
        if let failed = states.first(where: { if case .failed = $0 { return true }; return false }) {
            return failed
        }
        if states.contains(.rendering) { return .rendering }
        if states.contains(.ready) { return .ready }
        if waiting { return .waitingForReverse }
        if missing {
            return .failed(
                reverse.isolated == nil
                    ? "the project has no cache folder to render it into"
                    : "its media cannot be found")
        }
        return unsupported ? .unsupported : .off
    }

    /// The Status read-out's last answer (AU-56), so a refresh that changed
    /// neither the document's handles nor its published resolution — a
    /// playhead tick — or that comes mid-gesture (no render is wanted until
    /// it ends, SR-12 (c)) does not decode the plans again. Its owner calls
    /// `invalidate()` on `.reversedMediaDidChange`, which is how a render
    /// landing or failing reaches it. `compute` is the status it holds —
    /// isolation's, or the Voice Effect section's (`VoiceCache.status`).
    final class Memo {
        private weak var document: ProjectDocument?
        private weak var project: ReelProject?
        private weak var edited: ReelProject?
        private var clip: UInt32?
        private var resolution: ReverseResolution?
        private var held: IsolationStatus?
        private let compute: (UInt32, ProjectDocument) -> IsolationStatus

        init(
            compute: @escaping (UInt32, ProjectDocument) -> IsolationStatus =
                IsolationCache.status(of:in:)
        ) {
            self.compute = compute
        }

        func status(of clip: UInt32, in document: ProjectDocument) -> IsolationStatus {
            let resolution = ReverseSource.shared.resolution(for: document.recipeKey)
            if let held, self.document === document, self.clip == clip,
                document.isLiveEditing
                    || (project === document.project && edited === document.editedProject
                        && self.resolution == resolution)
            {
                return held
            }
            let status = compute(clip, document)
            self.document = document
            project = document.project
            edited = document.editedProject
            self.clip = clip
            self.resolution = resolution
            held = status
            return status
        }

        func invalidate() {
            held = nil
            project = nil
            edited = nil
        }
    }
}

extension CompositionBuilder {
    /// Each READY isolated segment's render, read into memory (AU-53): the
    /// file `IsolationCache` names, when it exists as the composition is
    /// built. A pending one is absent, and its clip plays dry.
    static func isolatedAudio(
        plan: CompositionPlan, urls: [UInt32: URL], reverse: ReverseResolution,
        dsp: AudioDSPParameters
    ) -> [IsolationSegmentKey: IsolatedAudio] {
        guard dsp.isolates else { return [:] }
        var out: [IsolationSegmentKey: IsolatedAudio] = [:]
        for planTrack in plan.audioTracks {
            for s in planTrack.segments {
                let key = IsolationSegmentKey(s)
                guard out[key] == nil,
                    let request = IsolationCache.request(
                        for: s, dsp: dsp, urls: urls, reverse: reverse),
                    FileManager.default.fileExists(atPath: request.destination.path),
                    let audio = IsolatedAudioStore.shared.audio(at: request.destination)
                else { continue }
                out[key] = audio
            }
        }
        return out
    }
}
