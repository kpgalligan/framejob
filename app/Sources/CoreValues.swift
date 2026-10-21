import Foundation

/// The values the core's speed limits and graphics engine decode into — `SpeedLimits`,
/// `GraphicDiagnostic`, `GraphicFailure` and `GraphicRaster` — moved out of `ReelCore.swift`
/// (a pure move, clean-up batch 2) because they name no `rc_*` symbol but in a doc comment.

/// Every number about a clip's speed, as the core publishes it through
/// `rc_speed_limits` (spec §11 #190): the range `set_speed` clamps to and the
/// reader enforces, and the speed above which the plan leaves a clip's audio
/// out, in both pitch modes. No Swift file types one of these numbers; each
/// reads them here.
struct SpeedLimits: Decodable, Equatable {
    let min: Double
    let max: Double
    let audioMax: Double

    enum CodingKeys: String, CodingKey {
        case min, max
        case audioMax = "audio_max"
    }

    var range: ClosedRange<Double> { min...max }
}

/// One `{level, message, line, column, frame}` out of the graphics engine's
/// `diag_out` (road map 10 §5e).
struct GraphicDiagnostic: Decodable, Equatable {
    let level: String
    let message: String
    let line: Int?
    let column: Int?
    let frame: Int?
}

/// A graphic that did not compile, draw or rasterize: the engine's one error.
struct GraphicFailure: Error {
    let diagnostics: [GraphicDiagnostic]
}

/// One drawn frame: premultiplied BGRA rows `stride` bytes apart.
struct GraphicRaster {
    let width: Int
    let height: Int
    let stride: Int
    let bgra: [UInt8]
    let warnings: [GraphicDiagnostic]
}
