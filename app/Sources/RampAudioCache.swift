import AVFoundation

/// One plan ramp segment's render as the builder looks it up (spec §11
/// SR-12 (a)): the clip and everything in the segment that shapes the file.
/// Equal exactly when the render file is the same one — the media and the
/// reversal are the clip's own, so they need no field — and never keyed by
/// the segment's start, so two instances of one nest clip with different
/// cuts (different maps) are two keys.
struct RampSegmentKey: Hashable {
    let clip: UInt32
    let keepPitch: Bool
    let glide: [[Ticks]]
    let map: [[Ticks]]

    /// Nil for a segment with no `ramp`.
    init?(_ segment: PlanSegment) {
        guard let ramp = segment.ramp else { return nil }
        clip = segment.clip
        keepPitch = ramp.keepPitch
        glide = ramp.glide
        map = ramp.map
    }
}

/// One render a ramp segment asks for: where it lands (the final `.caf`),
/// what it reads (the media file, or the clip's reversed file) and its map.
struct RampAudioRequest: Equatable {
    let clip: UInt32
    let media: UInt32
    let destination: URL
    let source: URL
    let reversed: Bool
    let ramp: PlanSpeedRamp
}

/// The `cache/ramp-audio/` half of the package (spec §5.6, §11 SR-6, SR-12):
/// a ramped clip's audio, rendered once per plan ramp segment and named by
/// everything that shapes it, so a render is reusable and self-invalidating
/// as `ReverseCache`'s reversed files are.
enum RampAudioCache {
    /// The subdirectory of `cache/` this feature owns.
    static let directoryName = "ramp-audio"

    static func directory(in cache: URL) -> URL {
        cache.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// `<media>-<16 hex>.caf`: FNV-1a 64 over the MEDIA file's path, size and
    /// modification second (never the copy or the reversed file the renderer
    /// reads), `RampAudioRenderer.version`, the reversal, Keep pitch, the
    /// glide pairs and the map pairs. Nil when the media cannot be stat'ed.
    /// `ReverseCache.digest`'s hash, spelled again for the reason that one
    /// gives: it keys a different directory.
    static func name(media: UInt32, mediaFile: URL, reversed: Bool, ramp: PlanSpeedRamp)
        -> String?
    {
        let attributes = try? FileManager.default.attributesOfItem(atPath: mediaFile.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value else { return nil }
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        func pairs(_ list: [[Ticks]]) -> String {
            list.map { $0.map(String.init).joined(separator: ":") }.joined(separator: ",")
        }
        let key = "\(mediaFile.path)|\(size)|\(Int64(modified.rounded()))"
            + "|v\(RampAudioRenderer.version)|r\(reversed ? 1 : 0)|k\(ramp.keepPitch ? 1 : 0)"
            + "|g\(pairs(ramp.glide))|m\(pairs(ramp.map))"
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return "\(media)-" + String(repeating: "0", count: max(0, 16 - hex.count)) + hex + ".caf"
    }

    /// The plan's `[clip tick, source tick]` breakpoints as the renderer's map.
    static func map(of ramp: PlanSpeedRamp) -> RampAudioMap {
        RampAudioMap(
            clipTicks: ramp.map.map { $0.first ?? -1 },
            sourceTicks: ramp.map.map { $0.count > 1 ? Double($0[1]) : -1 })
    }

    /// The plan's glide spans as ranges, an empty or malformed one dropped.
    static func glide(of ramp: PlanSpeedRamp) -> [Range<Ticks>] {
        ramp.glide.compactMap { $0.count == 2 && $0[0] < $0[1] ? $0[0]..<$0[1] : nil }
    }

    /// Every ramp segment of `plan` that can be rendered, one request per
    /// file: its media resolves, its reverse (when reversed) is ready, and
    /// there is a `rampAudio` folder (SR-12 (d)). A pending reverse or a
    /// missing media is no request: that clip is empty time, slated, and
    /// nothing waits for it.
    static func requests(plan: CompositionPlan, urls: [UInt32: URL], reverse: ReverseResolution)
        -> [RampAudioRequest]
    {
        var out: [RampAudioRequest] = []
        var seen: Set<URL> = []
        for planTrack in plan.audioTracks {
            for segment in planTrack.segments {
                guard let request = request(for: segment, urls: urls, reverse: reverse),
                    seen.insert(request.destination).inserted
                else { continue }
                out.append(request)
            }
        }
        return out
    }

    /// The one segment's request, or nil (see `requests`).
    static func request(
        for segment: PlanSegment, urls: [UInt32: URL], reverse: ReverseResolution
    ) -> RampAudioRequest? {
        guard let ramp = segment.ramp, segment.duration > 0, let directory = reverse.rampAudio,
            let mediaFile = urls[segment.media], !reverse.pending.contains(segment.clip)
        else { return nil }
        let reversedFile = reverse.ready[segment.clip]
        guard let name = name(
            media: segment.media, mediaFile: mediaFile, reversed: reversedFile != nil, ramp: ramp)
        else { return nil }
        return RampAudioRequest(
            clip: segment.clip, media: segment.media,
            destination: directory.appendingPathComponent(name),
            source: reversedFile ?? mediaFile, reversed: reversedFile != nil, ramp: ramp)
    }

    /// What the renderer reads for `mediaFile`: the file itself, or
    /// `AudioRateCopy`'s 48 kHz copy where it `needsCopy` (SR-6). A reversed
    /// file is 48 kHz LPCM and answers itself. Blocking (the copy is made on
    /// first need); throws `unreadable` when no source can be had.
    static func renderSource(for mediaFile: URL) throws -> URL {
        let asset = AVURLAsset(url: mediaFile)
        guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .audio) else {
            throw RampAudioRenderer.RenderError.unreadable(
                "\(mediaFile.lastPathComponent) has no audio track")
        }
        guard let signature = CompositionBuilder.audioFormatSignature(of: track) else {
            throw RampAudioRenderer.RenderError.unreadable(
                "\(mediaFile.lastPathComponent)'s audio format cannot be read")
        }
        let trim = MP3Gapless.leadingTrim(of: mediaFile, track: track)
        guard AudioRateCopy.needsCopy(signature, trim: trim) else { return mediaFile }
        guard let copy = AudioRateCopy.copy(of: mediaFile, track: track, trim: trim) else {
            throw RampAudioRenderer.RenderError.unreadable(
                "no 48 kHz copy of \(mediaFile.lastPathComponent) could be made")
        }
        return copy
    }

    /// Removes every file in `directory` that no name in `names` prefixes —
    /// a render no owner wants any more, or a temporary of one that died.
    /// Refuses a directory not named `ramp-audio`: this takes a URL and
    /// removes files (`ReverseCache.prune`'s guard, for its reason).
    static func prune(_ directory: URL, keeping names: Set<String>) {
        guard directory.lastPathComponent == directoryName,
            let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for file in files where !names.contains(where: { file.hasPrefix($0) }) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }
}

extension CompositionBuilder {
    /// Each READY ramp segment's render as an asset track (spec §11 SR-12
    /// (b)): the first audio track of the file `RampAudioCache` names, when
    /// it exists as the composition is built. A pending one is absent, and
    /// `resolveSource` answers it as empty time. `assets` holds the opened
    /// files for the build, as `fill`'s caches do.
    static func rampAudioTracks(
        plan: CompositionPlan, urls: [UInt32: URL], reverse: ReverseResolution,
        assets: inout [URL: AVURLAsset]
    ) -> [RampSegmentKey: AVAssetTrack] {
        var tracks: [RampSegmentKey: AVAssetTrack] = [:]
        for planTrack in plan.audioTracks {
            for segment in planTrack.segments {
                guard let key = RampSegmentKey(segment), tracks[key] == nil,
                    let request = RampAudioCache.request(for: segment, urls: urls, reverse: reverse),
                    FileManager.default.fileExists(atPath: request.destination.path)
                else { continue }
                let asset = assets[request.destination] ?? AVURLAsset(
                    url: request.destination,
                    options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                assets[request.destination] = asset
                if let track = firstTrack(of: asset, mediaType: .audio) { tracks[key] = track }
            }
        }
        return tracks
    }
}
