import Foundation

/// What a scope's frame holds (spec §11 HD-8, HD-15): `sdr`, Rec. 709 encoded
/// values, every SDR project's frame and an HLG project's SDR version; `hlg`,
/// an HLG project's own picture, BT.2020 HLG-encoded values. It picks the
/// kernels' constants (`Waveform.metal`'s `signal` uniform), the traces'
/// JSON keys, the panel's scale, captions and targets, and `render_frame`'s
/// sentences. An SDR signal adds nothing anywhere: every SDR trace, JSON byte
/// and drawing is what it was before H-4.
///
/// The panel's signal is the recipe canvas the frame was drawn with
/// (`init(canvas:)`, HD-15 (d)), so it follows the frame, not the window's
/// switches: Show SDR Version's frame is `sdr`, Show Ungraded's in an HLG
/// project `hlg`.
enum ScopeSignal: String, Equatable {
    case sdr, hlg

    /// HLG iff the project is HLG and the frame is not its SDR version
    /// (`render_frame {sdr_version}`, a JPEG frame: HD-15 (b)).
    init(output: CanvasOutput, dynamicRange: DynamicRange?) {
        self = output == .hlg && dynamicRange != .sdr ? .hlg : .sdr
    }

    /// The signal of a frame drawn with `canvas`; SDR when there is none.
    init(canvas: RecipeCanvas?) {
        guard let canvas else {
            self = .sdr
            return
        }
        self.init(output: canvas.output, dynamicRange: canvas.dynamicRange)
    }

    /// `Waveform.metal`'s `signal`: 0 Rec. 709's constants, 1 BT.2020's.
    var uniform: UInt32 {
        switch self {
        case .sdr: return 0
        case .hlg: return 1
        }
    }

    /// The vectorscope's matrix, as its JSON's `matrix` names it.
    var matrixName: String {
        switch self {
        case .sdr: return "Rec. 709"
        case .hlg: return "Rec. 2020"
        }
    }

    /// The slot's caption over `kind` (HD-15 (f)).
    func caption(for kind: ScopeKind) -> String {
        switch (self, kind) {
        case (.sdr, _): return "Rec. 709 · encoded"
        case (.hlg, .waveform), (.hlg, .parade): return "HLG · cd/m²"
        case (.hlg, .vectorscope), (.hlg, .histogram): return "Rec. 2100 HLG"
        }
    }

    /// The waveform's and parade's lines at 0/25/50/75/100 %, each with its
    /// gutter label or nil: 0, 50 and 100 in SDR; in HLG every line, its
    /// level's cd/m² (`hlgNits`) rounded — 0, 10, 51, 203 and 1000.
    var graticule: [(percent: Int, label: String?)] {
        stride(from: 0, through: 100, by: 25).map { percent in
            switch self {
            case .sdr:
                return (percent, percent % 50 == 0 ? String(percent) : nil)
            case .hlg:
                let nits = Self.hlgNits(Double(percent) / 100)
                return (percent, String(Int(nits.rounded())))
            }
        }
    }

    /// The line drawn dashed, reference white (HD-15 (f)): 75 % in HLG, none
    /// in SDR. The JSON's `reference_white_percent` reads it too.
    var referenceWhitePercent: Int? {
        switch self {
        case .sdr: return nil
        case .hlg: return 75
        }
    }

    /// The gutter labels' distance from the well, right-aligned: 2 pt in HLG,
    /// so "1000" fits the 24 pt gutter; SDR's 4 pt as before.
    var labelGap: CGFloat {
        switch self {
        case .sdr: return 4
        case .hlg: return 2
        }
    }

    /// An HLG signal's light, in cd/m², as a grey at BT.2100's nominal
    /// 1,000 cd/m² display: 1000·E^1.2, E the HLG inverse OETF (scene light).
    static func hlgNits(_ signal: Double) -> Double {
        let a = 0.17883277
        let b = 1 - 4 * a
        let c = 0.5 - a * log(4 * a)
        let v = max(signal, 0)
        let scene = v <= 0.5 ? v * v / 3 : (exp((v - c) / a) + b) / 12
        return 1000 * pow(scene, 1.2)
    }

    /// A tick's level: round(255·p/100), halves away from zero.
    static func level(percent: Int) -> Int {
        Int((255 * Double(percent) / 100).rounded())
    }

    /// What every trace's JSON adds: nothing in SDR, `signal` in HLG.
    var jsonKeys: [String: Any] {
        switch self {
        case .sdr: return [:]
        case .hlg: return ["signal": rawValue]
        }
    }

    /// The waveform's, parade's and histogram's `scale` (HD-15 (h)); nil in
    /// SDR.
    var scaleJSON: [String: Any]? {
        guard self == .hlg, let reference = referenceWhitePercent else { return nil }
        let ticks: [[String: Any]] = graticule.map { tick in
            [
                "percent": tick.percent, "level": Self.level(percent: tick.percent),
                "nits": (Self.hlgNits(Double(tick.percent) / 100) * 10).rounded() / 10,
            ]
        }
        return [
            "unit": "cd/m²", "ticks": ticks, "reference_white_percent": reference,
            "clip_percent": 100,
        ]
    }

    /// `body` with `jsonKeys` and, when `scaled`, `scaleJSON` added.
    func adding(to body: [String: Any], scaled: Bool) -> [String: Any] {
        var out = body.merging(jsonKeys) { _, new in new }
        if scaled, let scale = scaleJSON { out["scale"] = scale }
        return out
    }
}
