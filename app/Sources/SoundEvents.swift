import Foundation

/// The `sound_events` kind's pure half (spec §11 FC-30…FC-34; road map
/// "creator-jobs" FC3): the group table, the parameters, `windows.bin` and
/// its merge, and the windows placed on a clip. `AnalysisSoundEvents` runs
/// the job; `AgentServer+AnalysisSoundEvents.swift` answers it.
///
/// **The grid** is the hop grid (`AnalysisGrid(hopTicks:duration:)`): window
/// k starts at k × `hopTicks` of the media's forward source time and lasts
/// `windowTicks`; `count` is ⌈duration / hop⌉, so the last windows overhang
/// the media's end and are stored NaN once a completed read shows they hold
/// no result (FC-31's NaN tail).
///
/// **`windows.bin`**, little-endian: a 16-byte header — ASCII `FJSE`,
/// `UInt16` version 1, `UInt16` record bytes (24), `UInt32` window count,
/// `UInt32` group count (6) — then one record per window from 0: six
/// `Float32`, in `Group` order, each the maximum confidence over the group's
/// labels (NaN: no result). The cache is raw; only the answer rounds.
enum SoundEvents {

    /// FC-31's six groups, in the record's order.
    enum Group: String, CaseIterable {
        case laughter, applause, cheering, crowd, music, speech
    }

    /// FC-31's table: each group's `.version1` labels.
    static let labels: [Group: [String]] = [
        .laughter: ["laughter", "belly_laugh", "chuckle_chortle", "giggling", "snicker"],
        .applause: ["applause", "clapping"],
        .cheering: ["cheering"],
        .crowd: ["crowd"],
        .music: ["music"],
        .speech: ["speech"],
    ]

    /// The table's version, which is the kind's (`AnalysisKind.version`).
    static let tableVersion = 1
    /// FC-30: the window FC-S1 kept, 1.5 s.
    static let windowTicks: Ticks = 900_000
    /// FC-30: the overlap, so the hop is half the window.
    static let overlap = 0.5
    /// windowTicks × (1 − overlap): 0.75 s, 12,000 samples at 16 kHz.
    static let hopTicks = Ticks((Double(windowTicks) * (1 - overlap)).rounded())
    /// The decode's rate (`MediaImporter.speechReader`'s).
    static let sampleRate = 16_000
    /// The hop in decoded samples.
    static var hopSamples: Int { Int(hopTicks) * sampleRate / 600_000 }
    /// Applied thresholds of the first-class groups (FC-30): none while every
    /// group is weak (S-EV owed).
    static let thresholds: [Group: Double] = [:]
    /// Sound Analysis picks its own device; the stamp says so (FC-31).
    static let device = "auto"

    static let payloadName = "windows.bin"
    static let fileVersion: UInt16 = 1
    static let headerBytes = 16
    static var recordBytes: UInt16 { UInt16(Group.allCases.count * 4) }

    /// What the stored windows depend on: the stamp's digest.
    static let parameters: [String: Any] = [
        "classifier": "version1", "analyzer": "stream", "window_ticks": Int(windowTicks),
        "hop_ticks": Int(hopTicks), "overlap": overlap, "sample_rate": sampleRate,
        "decode": "speech_reader_mono_f32", "mp3_trim": true, "file_version": Int(fileVersion),
        "record_bytes": Int(recordBytes), "value": "max_confidence_over_labels",
    ]

    /// One window's values in `Group` order; all NaN is no result. Equal bit
    /// for bit.
    struct Window: Equatable {
        var values: [Float]

        static var empty: Window {
            Window(values: [Float](repeating: .nan, count: Group.allCases.count))
        }

        func value(_ group: Group) -> Float {
            let i = Group.allCases.firstIndex(of: group) ?? 0
            return i < values.count ? values[i] : .nan
        }

        static func == (a: Window, b: Window) -> Bool {
            a.values.map(\.bitPattern) == b.values.map(\.bitPattern)
        }
    }

    // MARK: - windows.bin

    static func encode(_ windows: [Window]) -> Data {
        var data = Data()
        let groups = Group.allCases.count
        data.reserveCapacity(headerBytes + windows.count * groups * 4)
        func put<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("FJSE".utf8))
        put(fileVersion)
        put(recordBytes)
        put(UInt32(windows.count))
        put(UInt32(groups))
        for window in windows {
            for i in 0..<groups {
                put((i < window.values.count ? window.values[i] : .nan).bitPattern)
            }
        }
        return data
    }

    /// nil when `data` is not a `windows.bin` this build reads.
    static func decode(_ data: Data) -> [Window]? {
        guard data.count >= headerBytes else { return nil }
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> UInt16 { UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[at + $1]) << (8 * UInt32($1)) }
        }
        let groups = Group.allCases.count
        guard bytes[0..<4].elementsEqual(Array("FJSE".utf8)), u16(4) == fileVersion,
            u16(6) == recordBytes, Int(u32(12)) == groups
        else { return nil }
        let count = Int(u32(8))
        guard data.count == headerBytes + count * Int(recordBytes) else { return nil }
        var windows: [Window] = []
        windows.reserveCapacity(count)
        for k in 0..<count {
            let at = headerBytes + k * Int(recordBytes)
            windows.append(Window(values: (0..<groups).map { Float(bitPattern: u32(at + $0 * 4)) }))
        }
        return windows
    }

    /// The publish's write: the on-disk file decoded (when it answers for the
    /// stamp and holds `count` windows) with `results`' windows replaced,
    /// else a fresh file of `count` empty windows with them; written to
    /// `partial`. Answers whether it merged, so a damaged file's coverage is
    /// dropped.
    static func write(onDisk: URL?, partial: URL, count: Int, results: [Int: Window]) throws
        -> Bool
    {
        var merged = false
        var all = [Window](repeating: .empty, count: count)
        if let onDisk, let data = try? Data(contentsOf: onDisk), let old = decode(data),
            old.count == count
        {
            all = old
            merged = true
        }
        for (k, window) in results where k >= 0 && k < count { all[k] = window }
        try encode(all).write(to: partial)
        return merged
    }

    // MARK: - On a clip

    /// One covered window placed on a clip: its index, its start in forward
    /// source ticks, and that instant's clip time and timeline time.
    struct Placed: Equatable {
        let index: Int
        let source: Ticks
        let clipTime: Ticks
        let timeline: Ticks
        let window: Window
    }

    /// The covered windows whose start lies in the clip's played window
    /// [lower, upper), each placed through `AnalysisClipTimes` (its speed or
    /// ramp); none for a reversed clip, whose sound plays backwards (FC-33).
    static func events(
        in windows: [Window], covered: [ClosedRange<Int>], grid: AnalysisGrid,
        for clip: AnalysisClipTimes
    ) -> [Placed] {
        guard clip.pivot == nil,
            let span = grid.indices(from: clip.window.lowerBound, to: clip.window.upperBound)
        else { return [] }
        var out: [Placed] = []
        for range in AnalysisStore.merged(covered) where range.overlaps(span) {
            let low = max(range.lowerBound, span.lowerBound)
            let high = min(range.upperBound, span.upperBound, windows.count - 1)
            guard low <= high else { continue }
            for k in low...high {
                let source = grid.ticks(of: k)
                let time = clip.clipTime(ofSource: source)
                out.append(Placed(
                    index: k, source: source, clipTime: time, timeline: clip.start + time,
                    window: windows[k]))
            }
        }
        return out
    }
}
