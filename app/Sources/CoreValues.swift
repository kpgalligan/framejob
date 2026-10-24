import Foundation

/// The values the core's speed limits and graphics engine decode into — `SpeedLimits`,
/// `GraphicDiagnostic`, `GraphicFailure` and `GraphicRaster` — moved out of `ReelCore.swift`
/// (a pure move, clean-up batch 2) because they name no `rc_*` symbol but in a doc comment;
/// and, for the same reason, the core's error `ReelCoreError` and `Fps.ffiPair` (a pure
/// move, #127 G6 phase 5's toll); and the JSON-reading halves of `ReelProject.clipState(_:at:)`
/// and `snapCandidates(excluding:)` as `CoreJSON` (a pure move, clean-up 3 batch B's toll).

/// Error thrown by the Rust core, carrying the message from `err_out`.
struct ReelCoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The parsing halves of two `ReelProject` reads whose `rc_*` calls stay in `ReelCore.swift`.
enum CoreJSON {
    /// `json`'s UTF-8 through `JSONSerialization`; nil for a nil or unreadable string.
    static func value(_ json: String?) -> Any? {
        guard let json = json, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return object
    }

    /// The core's snap candidates — grouped by kind as an object of arrays, or one array —
    /// merged, de-duplicated and sorted.
    static func snapTicks(_ answer: Any) -> [Ticks] {
        var out = Set<Ticks>()
        func absorb(_ value: Any) {
            if let numbers = value as? [NSNumber] {
                for number in numbers { out.insert(number.int64Value) }
            }
        }
        if let grouped = answer as? [String: Any] {
            for value in grouped.values { absorb(value) }
        } else {
            absorb(answer)
        }
        return out.sorted()
    }
}

extension Fps {
    /// The rate as the two `uint32_t` arguments every `rc_*` time function
    /// takes; nil for a degenerate or out-of-range rate — impossible in a
    /// document the core wrote, possible in a hand-written JSON.
    var ffiPair: (num: UInt32, den: UInt32)? {
        guard num > 0, den > 0, num <= Int(UInt32.max), den <= Int(UInt32.max) else { return nil }
        return (UInt32(num), UInt32(den))
    }
}

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

/// `ReelTime`'s three members that name no `rc_*` symbol, moved out of `ReelCore.swift` (a pure
/// move, speed ramps SR4-0's toll).
extension ReelTime {
    /// Ticks per second — `RC_TIMESCALE`. Divides every common frame
    /// duration exactly, and `CMTime` at this timescale round-trips.
    static let perSecond: Ticks = 600_000

    /// Seconds to ticks, rounded. 0 for a non-finite input.
    static func ticks(seconds: Double) -> Ticks {
        guard seconds.isFinite else { return 0 }
        let scaled = (seconds * Double(perSecond)).rounded()
        guard scaled >= Double(Ticks.min), scaled <= Double(Ticks.max) else { return 0 }
        return Ticks(scaled)
    }

    /// Ticks to seconds, for `CMTime` and for anything measured in seconds
    /// in the inspector (fades, ducking attack/release).
    static func seconds(_ t: Ticks) -> Double {
        Double(t) / Double(perSecond)
    }
}
