import Foundation

/// What one bundled-encoder export costs (spec §11 CX-18): its resident peak, which the
/// Export Queue's limit books (`ExportEncoderLedger`), and its time, which the export
/// sheet's estimate reads. Two tables keyed alike, each figure carrying its source.
///
/// **Both are measured, never guessed, and both are a table edit to replace.** The figures
/// are `tools/proof/encoder_memory_measure.py`'s, recorded in `designs/codec-export.md`'s
/// "## C6a" (`vp9_alpha_webm`'s in "## C5"'s fix pass): one fresh Release instance per key
/// and size, AV.mov twice on the canvas (10 s, 300 frames), the resident peak above the
/// instance's own after a warming frame, and the export's wall time. The TIME figures are provisional — one run each on a shared machine —
/// until C6b measures 4K on every row and the idle three-run speeds and writes them here.
///
/// A figure is given at 1920 × 1080 and 3840 × 2160 and read at an export's pixels:
/// proportionally below 1080p, linearly through both points above it, extrapolated past 4K.

/// What a cost is keyed by: the row, the AV1 speed, and the bit depth the encoder runs at.
struct ExportEncoderKey: Hashable {
    /// `av1`, `av1_webm`, `vp9_webm` or `vp9_alpha_webm`.
    let preset: String
    /// The AV1 rows' speed (`settings.encoderSpeed ?? .balanced`); nil on every other row.
    let speed: EncoderSpeed?
    /// 10 on `svt_av1` (CX-14: always 10-bit); on `libvpx` 10 for `hlg`/`pq` (Profile 2,
    /// CX-16 (3)), else 8.
    let bits: Int

    init(preset: String, speed: EncoderSpeed?, bits: Int) {
        self.preset = preset
        self.speed = speed
        self.bits = bits
    }

    /// The key of an export's settings; nil for an AVFoundation row (no `writer`).
    init?(settings: ExportSettings) {
        guard let writer = settings.writer else { return nil }
        let av1 = writer == "svt_av1"
        let deep = settings.dynamicRange == .hlg || settings.dynamicRange == .pq
        self.init(
            preset: settings.preset, speed: av1 ? settings.encoderSpeed ?? .balanced : nil,
            bits: av1 || deep ? 10 : 8)
    }
}

/// One measured quantity at the two sizes, and where it came from.
struct ExportEncoderFigure {
    /// At 1920 × 1080.
    let at1080: Double
    /// At 3840 × 2160.
    let at2160: Double
    /// The run, its date, the machine and its load.
    let source: String

    /// The figure at `pixels`: proportional below 1080p, linear through both points above.
    func value(pixels: Int) -> Double {
        let low = Double(ExportEncoderCosts.pixels1080)
        let high = Double(ExportEncoderCosts.pixels2160)
        let p = Double(max(0, pixels))
        if p <= low { return at1080 * p / low }
        return at1080 + (at2160 - at1080) * (p - low) / (high - low)
    }
}

/// A row's time: seconds per frame at the two sizes, plus a fixed start.
struct ExportTimeEntry {
    let perFrame: ExportEncoderFigure
    let setupSeconds: Double
}

enum ExportEncoderCosts {
    static let pixels1080 = 1920 * 1080
    static let pixels2160 = 3840 * 2160

    /// The run every figure below comes from; each adds its key and the load at its start.
    private static let run = "encoder_memory_measure.py, Release, 2026-10-28, Apple M2 Max, "
        + "96 GiB, one run per key and size on a machine shared with another lane's builds "
        + "and proofs; "
    /// `vp9_alpha_webm`'s run (codec-export C5's fix pass), on a quiet machine, with
    /// `vp9_webm:sdr` re-measured beside it as a control (within 0.6 % of the run above).
    private static let alphaRun = "encoder_memory_measure.py, Release, 2026-10-28, Apple M2 "
        + "Max, 96 GiB, one run per size (codec-export C5's fix pass); "

    /// Bytes, each job's resident peak above the instance's own.
    static let memory: [ExportEncoderKey: ExportEncoderFigure] = [
        ExportEncoderKey(preset: "av1", speed: .faster, bits: 10): ExportEncoderFigure(
            at1080: 1354825728, at2160: 4941070336,
            source: run + "av1:faster; load 10.47 at 1080p, 9.36 at 4K"),
        ExportEncoderKey(preset: "av1", speed: .balanced, bits: 10): ExportEncoderFigure(
            at1080: 2172993536, at2160: 7060766720,
            source: run + "av1:balanced; load 9.79 at 1080p, 8.77 at 4K"),
        ExportEncoderKey(preset: "av1", speed: .smaller, bits: 10): ExportEncoderFigure(
            at1080: 2419654656, at2160: 8450867200,
            source: run + "av1:smaller; load 9.72 at 1080p, 34.83 at 4K"),
        ExportEncoderKey(preset: "av1_webm", speed: .faster, bits: 10): ExportEncoderFigure(
            at1080: 1331265536, at2160: 4758519808,
            source: run + "av1_webm:faster; load 9.03 at 1080p, 32.63 at 4K"),
        ExportEncoderKey(preset: "av1_webm", speed: .balanced, bits: 10): ExportEncoderFigure(
            at1080: 2158755840, at2160: 7193591808,
            source: run + "av1_webm:balanced; load 9.03 at 1080p, 33.14 at 4K"),
        ExportEncoderKey(preset: "av1_webm", speed: .smaller, bits: 10): ExportEncoderFigure(
            at1080: 2378907648, at2160: 8229683200,
            source: run + "av1_webm:smaller; load 10.14 at 1080p, 33.16 at 4K"),
        ExportEncoderKey(preset: "vp9_webm", speed: nil, bits: 8): ExportEncoderFigure(
            at1080: 388530176, at2160: 1130774528,
            source: run + "vp9_webm:sdr; load 10.21 at 1080p, 31.35 at 4K"),
        ExportEncoderKey(preset: "vp9_webm", speed: nil, bits: 10): ExportEncoderFigure(
            at1080: 553811968, at2160: 1694040064,
            source: run + "vp9_webm:hlg; load 10.52 at 1080p, 30.58 at 4K"),
        ExportEncoderKey(preset: "vp9_alpha_webm", speed: nil, bits: 8): ExportEncoderFigure(
            at1080: 795197440, at2160: 2326249472,
            source: alphaRun + "vp9_alpha_webm; load 5.33 at 1080p, 4.59 at 4K"),
    ]

    /// Seconds. `perFrame` is the measured export's wall time over its 300 frames, so it
    /// carries the composition, the loudness pass and the container besides the encoder;
    /// `setupSeconds` is 0 until C6b separates them.
    static let time: [ExportEncoderKey: ExportTimeEntry] = [
        ExportEncoderKey(preset: "av1", speed: .faster, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 1.342 / 300, at2160: 3.621 / 300,
                source: run + "av1:faster; load 10.47 at 1080p, 9.36 at 4K"
                    + "; provisional until C6b"),
            setupSeconds: 0),
        ExportEncoderKey(preset: "av1", speed: .balanced, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 2.088 / 300, at2160: 8.403 / 300,
                source: run + "av1:balanced; load 9.79 at 1080p, 8.77 at 4K"
                    + "; provisional until C6b"),
            setupSeconds: 0),
        ExportEncoderKey(preset: "av1", speed: .smaller, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 2.614 / 300, at2160: 8.043 / 300,
                source: run + "av1:smaller; load 9.72 at 1080p, 34.83 at 4K"
                    + "; provisional until C6b"),
            setupSeconds: 0),
        ExportEncoderKey(preset: "av1_webm", speed: .faster, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 1.296 / 300, at2160: 3.795 / 300,
                source: run + "av1_webm:faster; load 9.03 at 1080p, 32.63 at 4K"
                    + "; provisional until C6b"),
            setupSeconds: 0),
        ExportEncoderKey(preset: "av1_webm", speed: .balanced, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 2.038 / 300, at2160: 6.163 / 300,
                source: run + "av1_webm:balanced; load 9.03 at 1080p, 33.14 at 4K"
                    + "; provisional until C6b"),
            setupSeconds: 0),
        ExportEncoderKey(preset: "av1_webm", speed: .smaller, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 2.661 / 300, at2160: 7.792 / 300,
                source: run + "av1_webm:smaller; load 10.14 at 1080p, 33.16 at 4K"
                    + "; provisional until C6b"),
            setupSeconds: 0),
        ExportEncoderKey(preset: "vp9_webm", speed: nil, bits: 8): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 2.061 / 300, at2160: 5.533 / 300,
                source: run + "vp9_webm:sdr; load 10.21 at 1080p, 31.35 at 4K"
                    + "; provisional until C6b"),
            setupSeconds: 0),
        ExportEncoderKey(preset: "vp9_webm", speed: nil, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 2.827 / 300, at2160: 9.078 / 300,
                source: run + "vp9_webm:hlg; load 10.52 at 1080p, 30.58 at 4K"
                    + "; provisional until C6b"),
            setupSeconds: 0),
        ExportEncoderKey(preset: "vp9_alpha_webm", speed: nil, bits: 8): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 3.574 / 300, at2160: 9.194 / 300,
                source: alphaRun + "vp9_alpha_webm; load 5.33 at 1080p, 4.59 at 4K"
                    + "; provisional until C6b"),
            setupSeconds: 0),
    ]

    /// What `settings` books in the ledger: 0 for an AVFoundation row, the whole `budget`
    /// for a writer row with no measured entry (CX-18 (4)), else its figure at its size.
    static func memoryBytes(for settings: ExportSettings, budget: UInt64) -> UInt64 {
        guard let key = ExportEncoderKey(settings: settings) else { return 0 }
        guard let figure = memory[key] else { return budget }
        return UInt64(max(0, figure.value(pixels: settings.width * settings.height)).rounded())
    }

    /// The whole write's estimate in seconds, or nil for a row with no time entry or a
    /// rate that cannot be stepped (no frame count, so no estimate rather than 0 frames).
    static func estimatedSeconds(for settings: ExportSettings) -> Double? {
        guard let key = ExportEncoderKey(settings: settings), let entry = time[key],
            let frames = settings.sequenceFrameCount
        else {
            return nil
        }
        return entry.setupSeconds
            + Double(frames) * entry.perFrame.value(pixels: settings.width * settings.height)
    }

    /// "about 25 s", "about 3 min", "about 1 h 5 min" — 5 s steps under a minute, whole
    /// minutes under an hour.
    static func estimateText(seconds s: Double) -> String {
        if s < 60 { return "about \(max(5, Int((s / 5).rounded()) * 5)) s" }
        if s < 3600 { return "about \(max(1, Int((s / 60).rounded()))) min" }
        let m = Int((s / 60).rounded())
        return "about \(m / 60) h \(m % 60) min"
    }

    /// The export sheet's line under the summary, or nil on a row with no estimate.
    static func sheetLine(for settings: ExportSettings) -> String? {
        estimatedSeconds(for: settings).map { "Estimated time: " + estimateText(seconds: $0) }
    }
}
