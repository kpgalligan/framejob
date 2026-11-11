import Foundation

/// One voice render's whole input (spec §11 AU-143, AU-144): the window it
/// covers (`IsolationCache.window`, the same window an isolation render of
/// the segment covers), the chain's settings, and — when the clip isolates —
/// the isolated render it crossfades from and how much.
struct VoiceJob: Equatable {
    let window: IsolationWindow
    let settings: VoiceSettings
    let isolated: URL?
    let isolation: Double
    /// A retimed segment's window is wider than what the clip plays (AU-55
    /// as amended, #387): the frames it plays, the input silent outside
    /// them, so the effect starts cold at the clip's first frame as it does
    /// at ×1 (AU-142). Nil for a ×1 segment, whose window is what it plays.
    var sounding: IsolationWindow? = nil
}

/// The `cache/voiced/` half of the package (spec §5.6, §11 AU-144): a clip
/// window's voice effect, rendered once by `VoiceRenderer` on
/// `RampAudioRenders` and named by everything that shapes it.
enum VoiceCache {
    /// The subdirectory of `cache/` this feature owns.
    static let directoryName = "voiced"

    static func directory(in cache: URL) -> URL {
        cache.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// `<media>-<16 hex>.caf`: FNV-1a 64 over the MEDIA file's path, size and
    /// modification second, `VoiceChain.version`, the reversal, the window,
    /// the kind, amount and semitones, the isolation amount with the
    /// isolated file's name (or `none`), and a retimed segment's sounding
    /// frames (appended only then). `IsolationCache.name`'s hash. Nil
    /// when the media cannot be stat'ed.
    static func name(media: UInt32, mediaFile: URL, reversed: Bool, job: VoiceJob) -> String? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: mediaFile.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value else { return nil }
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let window = job.window
        let s = job.settings
        let key = "\(mediaFile.path)|\(size)|\(Int64(modified.rounded()))"
            + "|v\(VoiceChain.version)|r\(reversed ? 1 : 0)"
            + "|w\(window.firstFrame):\(window.endFrame)"
            + "|k\(s.kind.rawValue)|a\(s.amount)|s\(s.semitones)"
            + "|i\(job.isolation)|f\(job.isolated?.lastPathComponent ?? "none")"
            + (job.sounding.map { "|o\($0.firstFrame):\($0.endFrame)" } ?? "")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return "\(media)-" + String(repeating: "0", count: max(0, 16 - hex.count)) + hex + ".caf"
    }

    /// The one ×1 segment's request, or nil (a retimed segment's is a stage
    /// of `RetimedSound.chain`, AU-145 as amended): the clip has a voice that
    /// is not inert, the segment is tapped, there is a `voiced`
    /// folder, its media resolves, its reverse (when reversed) is not
    /// pending — and, when the clip isolates, its isolated render is on disk
    /// (AU-143), whose file the job names.
    static func request(
        for s: PlanSegment, dsp: AudioDSPParameters, urls: [UInt32: URL],
        reverse: ReverseResolution
    ) -> RampAudioRequest? {
        guard let settings = dsp.voice(for: s.clip), IsolationCache.isTapped(s),
            let directory = reverse.voiced, let mediaFile = urls[s.media],
            !reverse.pending.contains(s.clip)
        else { return nil }
        let isolation = dsp.isolation(for: s.clip)
        var isolated: URL? = nil
        if isolation > 0 {
            guard let request = IsolationCache.request(
                for: s, dsp: dsp, urls: urls, reverse: reverse),
                FileManager.default.fileExists(atPath: request.destination.path)
            else { return nil }
            isolated = request.destination
        }
        let reversedFile = reverse.ready[s.clip]
        let job = VoiceJob(
            window: IsolationCache.window(of: s), settings: settings, isolated: isolated,
            isolation: isolated == nil ? 0 : isolation)
        guard let name = name(
            media: s.media, mediaFile: mediaFile, reversed: reversedFile != nil, job: job)
        else { return nil }
        return RampAudioRequest(
            clip: s.clip, media: s.media, destination: directory.appendingPathComponent(name),
            source: reversedFile ?? mediaFile, reversed: reversedFile != nil, job: .voice(job))
    }

    /// Every voiced window of `plan`, one request per file.
    static func requests(
        plan: CompositionPlan, dsp: AudioDSPParameters, urls: [UInt32: URL],
        reverse: ReverseResolution
    ) -> [RampAudioRequest] {
        guard dsp.voices else { return [] }
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

    /// One clip's state in `document` (AU-146), in Voice Isolation's words:
    /// off with no voice or an inert one; a failure first (the voice's own,
    /// or its isolation's as "its isolated voice was not rendered"), then a
    /// pending render (isolation's included), then ready; else why there is
    /// none. A retimed segment answers from its chain's last file (AU-145
    /// as amended); a clip no plan sounds answers `.noSound`.
    static func status(of clip: UInt32, in document: ProjectDocument) -> IsolationStatus {
        let dsp = AudioDSPParameters(snapshot: document.project.snapshot)
        guard dsp.voice(for: clip) != nil else { return .off }
        let reverse = ReverseSource.shared.resolution(for: document.recipeKey)
        let urls = document.mediaURLs()
        var states: [IsolationStatus] = []
        var sounds = false
        var waiting = false
        var missing = false
        let handles = document.scope == nil
            ? [document.project] : [document.project, document.editedProject]
        for handle in handles {
            guard let plan = handle.plan else { continue }
            for s in plan.audioTracks.flatMap(\.segments) where s.clip == clip && s.duration > 0 {
                sounds = true
                if reverse.pending.contains(clip) {
                    waiting = true
                } else if !IsolationCache.isTapped(s) {
                    if let chain = RetimedSound.chain(
                        for: s, dsp: dsp, urls: urls, reverse: reverse)
                    {
                        states.append(chain.status(voice: true))
                    } else {
                        missing = true
                    }
                } else if let request = request(for: s, dsp: dsp, urls: urls, reverse: reverse) {
                    states.append(IsolationCache.status(of: request))
                } else if dsp.isolation(for: clip) > 0, reverse.voiced != nil,
                    let isolation = IsolationCache.request(
                        for: s, dsp: dsp, urls: urls, reverse: reverse)
                {
                    let state = IsolationCache.status(of: isolation)
                    if case .failed = state {
                        states.append(.failed("its isolated voice was not rendered"))
                    } else {
                        states.append(.rendering)
                    }
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
                reverse.voiced == nil
                    ? "the project has no cache folder to render it into"
                    : "its media cannot be found")
        }
        return sounds ? .off : .noSound
    }
}

extension CompositionBuilder {
    /// Each READY voiced ×1 segment's render, read into memory (AU-143, AU-145):
    /// the file `VoiceCache` names, when it exists as the composition is
    /// built. A pending one is absent, and its clip plays without the effect
    /// (with its isolation, if that render is ready).
    static func voicedAudio(
        plan: CompositionPlan, urls: [UInt32: URL], reverse: ReverseResolution,
        dsp: AudioDSPParameters
    ) -> [IsolationSegmentKey: IsolatedAudio] {
        guard dsp.voices else { return [:] }
        var out: [IsolationSegmentKey: IsolatedAudio] = [:]
        for planTrack in plan.audioTracks {
            for s in planTrack.segments {
                let key = IsolationSegmentKey(s)
                guard out[key] == nil,
                    let request = VoiceCache.request(
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
