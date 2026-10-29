import Foundation

/// What one bundled-encoder export costs (spec §11 CX-18): its resident peak, which the
/// Export Queue's limit books (`ExportEncoderLedger`), and its time, which the export
/// sheet's estimate reads. Two tables keyed alike, each figure carrying its source.
///
/// **Both are measured, never guessed, and both are a table edit to replace.** The figures
/// are `tools/proof/encoder_memory_measure.py`'s, recorded in `archive/codec-export.md`'s
/// "## C6a" and "## C6b" (`vp9_alpha_webm`'s first in "## C5"'s fix pass): one fresh Release
/// instance per key and size, the resident peak above the instance's own after a warming
/// frame, and the export's wall time. The TIME figures are C6b's: on an idle machine, the
/// GH5 4K clip on a 25 fps canvas, the median of three runs per key and size over 250 and
/// 50 frames, which separate the fixed start from the per-frame time. A MEMORY figure is the
/// larger of C6a's (C5's) single run and C6b's peaks, its source naming the run that won.
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

    /// C6b's run (`archive/codec-export.md`'s "## C6b", spec §11 CX-18's amendment): every
    /// time figure, and each memory figure whose C6b peak passed the earlier one. Each adds
    /// its key and the loads read during its runs (its own encoders' threads).
    private static let run = "encoder_memory_measure.py, Release, 2026-10-29, Apple M2 Max "
        + "(Mac14,6), 96 GiB, idle (load 3.22–3.67 at each batch's start), GH5 borough market "
        + "4K 25p, median of three runs per key and size, C6b; "
    /// C6a's run (`archive/codec-export.md`'s "## C6a"): the memory figures it still wins.
    private static let c6aRun = "encoder_memory_measure.py, Release, 2026-10-28, Apple M2 "
        + "Max, 96 GiB, one run per key and size on a machine shared with another lane's "
        + "builds and proofs; "
    /// `vp9_alpha_webm`'s run (codec-export C5's fix pass), on a quiet machine, with
    /// `vp9_webm:sdr` re-measured beside it as a control (within 0.6 % of C6a's).
    private static let alphaRun = "encoder_memory_measure.py, Release, 2026-10-28, Apple M2 "
        + "Max, 96 GiB, one run per size (codec-export C5's fix pass); "

    /// Bytes, each job's resident peak above the instance's own: the larger of the earlier
    /// run's figure and C6b's largest peak at the size, never lowered below a measured one.
    static let memory: [ExportEncoderKey: ExportEncoderFigure] = [
        ExportEncoderKey(preset: "av1", speed: .faster, bits: 10): ExportEncoderFigure(
            at1080: 1420640256, at2160: 4941070336,
            source: "1080p: " + run + "av1:faster; load 3.22–27.94 — 4K: " + c6aRun
                + "av1:faster; load 9.36"),
        ExportEncoderKey(preset: "av1", speed: .balanced, bits: 10): ExportEncoderFigure(
            at1080: 2386313216, at2160: 8030453760,
            source: run + "av1:balanced; load 3.52–26.91 at 1080p, 8.35–22.85 at 4K"),
        ExportEncoderKey(preset: "av1", speed: .smaller, bits: 10): ExportEncoderFigure(
            at1080: 2613837824, at2160: 8696889344,
            source: run + "av1:smaller; load 3.52–26.43 at 1080p, 7.68–28.90 at 4K"),
        ExportEncoderKey(preset: "av1_webm", speed: .faster, bits: 10): ExportEncoderFigure(
            at1080: 1331265536, at2160: 4758519808,
            source: c6aRun + "av1_webm:faster; load 9.03 at 1080p, 32.63 at 4K"),
        ExportEncoderKey(preset: "av1_webm", speed: .balanced, bits: 10): ExportEncoderFigure(
            at1080: 2342584320, at2160: 8196833280,
            source: run + "av1_webm:balanced; load 7.14–25.20 at 1080p, 8.26–32.50 at 4K"),
        ExportEncoderKey(preset: "av1_webm", speed: .smaller, bits: 10): ExportEncoderFigure(
            at1080: 2378907648, at2160: 8229683200,
            source: c6aRun + "av1_webm:smaller; load 10.14 at 1080p, 33.16 at 4K"),
        ExportEncoderKey(preset: "vp9_webm", speed: nil, bits: 8): ExportEncoderFigure(
            at1080: 397574144, at2160: 1130774528,
            source: "1080p: " + run + "vp9_webm:sdr; load 6.57–26.06 — 4K: " + c6aRun
                + "vp9_webm:sdr; load 31.35"),
        ExportEncoderKey(preset: "vp9_webm", speed: nil, bits: 10): ExportEncoderFigure(
            at1080: 553811968, at2160: 1694040064,
            source: c6aRun + "vp9_webm:hlg; load 10.52 at 1080p, 30.58 at 4K"),
        ExportEncoderKey(preset: "vp9_alpha_webm", speed: nil, bits: 8): ExportEncoderFigure(
            at1080: 802816000, at2160: 2326249472,
            source: "1080p: " + run + "vp9_alpha_webm; load 7.40–22.15 — 4K: " + alphaRun
                + "vp9_alpha_webm; load 4.59"),
    ]

    /// Seconds. `perFrame` is the 250-frame export's median wall time less `setupSeconds`,
    /// over its frames, so it carries the composition, the loudness pass and the container
    /// besides the encoder; `setupSeconds` is the fixed start the 50-frame runs separate
    /// (the smaller of the two sizes' intercepts, 0 when either is under 0.5 s).
    static let time: [ExportEncoderKey: ExportTimeEntry] = [
        ExportEncoderKey(preset: "av1", speed: .faster, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 1.856 / 250, at2160: 6.603 / 250,
                source: run + "av1:faster; load 3.22–27.94 at 1080p, 6.64–20.78 at 4K; C6b"),
            setupSeconds: 0.524),
        ExportEncoderKey(preset: "av1", speed: .balanced, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 3.438 / 250, at2160: 13.233 / 250,
                source: run + "av1:balanced; load 3.52–26.91 at 1080p, 8.35–22.85 at 4K; C6b"),
            setupSeconds: 0.738),
        ExportEncoderKey(preset: "av1", speed: .smaller, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 5.056 / 250, at2160: 19.151 / 250,
                source: run + "av1:smaller; load 3.52–26.43 at 1080p, 7.68–28.90 at 4K; C6b"),
            setupSeconds: 0.736),
        ExportEncoderKey(preset: "av1_webm", speed: .faster, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 1.856 / 250, at2160: 6.603 / 250,
                source: run + "av1_webm:faster; copied from av1:faster (CX-15, within 10 %); "
                    + "load 3.22–27.94 at 1080p, 6.64–20.78 at 4K; C6b"),
            setupSeconds: 0.524),
        ExportEncoderKey(preset: "av1_webm", speed: .balanced, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 3.438 / 250, at2160: 13.233 / 250,
                source: run + "av1_webm:balanced; copied from av1:balanced (CX-15, within "
                    + "10 %: av1_webm's own median −1.9 % at 1080p, −0.1 % at 4K); load "
                    + "3.52–26.91 at 1080p, 8.35–22.85 at 4K; C6b"),
            setupSeconds: 0.738),
        ExportEncoderKey(preset: "av1_webm", speed: .smaller, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 5.056 / 250, at2160: 19.151 / 250,
                source: run + "av1_webm:smaller; copied from av1:smaller (CX-15, within "
                    + "10 %); load 3.52–26.43 at 1080p, 7.68–28.90 at 4K; C6b"),
            setupSeconds: 0.736),
        ExportEncoderKey(preset: "vp9_webm", speed: nil, bits: 8): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 7.020 / 250, at2160: 23.549 / 250,
                source: run + "vp9_webm:sdr; load 6.57–26.06 at 1080p, 8.32–39.50 at 4K; C6b"),
            setupSeconds: 0),
        ExportEncoderKey(preset: "vp9_webm", speed: nil, bits: 10): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 9.043 / 250, at2160: 31.237 / 250,
                source: run + "vp9_webm:hlg; load 7.35–23.50 at 1080p, 8.57–32.01 at 4K; C6b"),
            setupSeconds: 0),
        ExportEncoderKey(preset: "vp9_alpha_webm", speed: nil, bits: 8): ExportTimeEntry(
            perFrame: ExportEncoderFigure(
                at1080: 7.889 / 250, at2160: 26.286 / 250,
                source: run + "vp9_alpha_webm; load 7.40–22.15 at 1080p, 7.96–30.28 at 4K; C6b"),
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
