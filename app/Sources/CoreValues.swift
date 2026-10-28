import Foundation

/// The values the core's speed limits and graphics engine decode into — `SpeedLimits`,
/// `GraphicDiagnostic`, `GraphicFailure` and `GraphicRaster` — moved out of `ReelCore.swift`
/// (a pure move, clean-up batch 2) because they name no `rc_*` symbol but in a doc comment,
/// with `GraphicDiagnostic.of`, `.error` and `.noModule`, the one reading of a thrown error;
/// and, for the same reason, the core's error `ReelCoreError` and `Fps.ffiPair` (a pure
/// move, #127 G6 phase 5's toll); and the JSON-reading halves of `ReelProject.clipState(_:at:)`
/// and `snapCandidates(excluding:)` as `CoreJSON` (a pure move, clean-up 3 batch B's toll),
/// which also took `ReelCore.swift`'s `jsonArray` as `CoreJSON.array` (codec-export C1's
/// toll T2, a pure move). C1's fix pass moved `ReelAV1.Config` and `.Color`, then the
/// rc_*-free halves of `ReelExport.settings` (`CoreJSON.overrides`), `takeDiagnostics`
/// (`GraphicDiagnostic.list(json:)`), `GraphicLibrary.rasterize` (`GraphicFailure.checkSides`)
/// and `ReelSpeed.limits` (`SpeedLimits.decoded`), and `ReelHDR10.withBytes` (two pure moves).

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

    /// A JSON array of integers, built by hand rather than through
    /// `JSONSerialization` because the core's parsers want plain `[1,2,3]` and
    /// this cannot fail.
    static func array<T: FixedWidthInteger>(_ values: [T]) -> String {
        "[" + values.map { String($0) } .joined(separator: ",") + "]"
    }

    /// `ReelExport.settings`' overrides as the JSON text `rc_export_settings` takes, keys
    /// sorted; nil for none or an empty object. Throws when they are not valid JSON.
    static func overrides(_ overrides: [String: Any]?) throws -> String? {
        guard let overrides = overrides, !overrides.isEmpty else { return nil }
        guard JSONSerialization.isValidJSONObject(overrides),
              let data = try? JSONSerialization.data(
                withJSONObject: overrides, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { throw ReelCoreError(message: "The export overrides are not valid JSON.") }
        return text
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

    /// `rc_speed_limits`' answer, read once by `ReelSpeed.limits`. An answer that does not
    /// decode is a broken build, not a state the app can carry on in, so it stops here. A
    /// plain decoder, not `ReelJSON`'s: its snake-case conversion would turn `audio_max` into
    /// a key the explicit `CodingKeys` do not name.
    static func decoded(_ json: String?) -> SpeedLimits {
        guard let json,
            let limits = try? JSONDecoder().decode(SpeedLimits.self, from: Data(json.utf8))
        else { preconditionFailure("rc_speed_limits did not answer its documented JSON") }
        return limits
    }
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

    /// `GraphicLibrary.rasterize`'s refusal of a side outside `0…max`, before a buffer is
    /// allocated for it.
    static func checkSides(_ width: Int, _ height: Int, max: Int) throws {
        let sides = 0...max
        guard sides.contains(width), sides.contains(height) else {
            throw GraphicFailure(diagnostics: [GraphicDiagnostic(
                level: "error", message: "\(width)×\(height) is outside 0…\(max)",
                line: nil, column: nil, frame: nil)])
        }
    }
}

extension GraphicDiagnostic {
    /// A `diag_out`'s text decoded. An unreadable one is one error saying so.
    static func list(json text: String) -> [GraphicDiagnostic] {
        guard let list = try? JSONDecoder().decode([GraphicDiagnostic].self, from: Data(text.utf8))
        else {
            return [GraphicDiagnostic(
                level: "error", message: "The core's diagnostics could not be read: \(text)",
                line: nil, column: nil, frame: nil)]
        }
        return list
    }

    /// An error with no place in the source: no line, column or frame.
    static func error(_ message: String) -> GraphicDiagnostic {
        GraphicDiagnostic(level: "error", message: message, line: nil, column: nil, frame: nil)
    }

    /// A clip naming a module the graphics folder does not hold.
    static func noModule(_ name: String) -> GraphicDiagnostic {
        .error("No module named \"\(name)\" in graphics/")
    }

    /// The engine's diagnostics out of a thrown error — one error saying
    /// what was thrown when it carries none.
    static func of(_ error: any Error) -> [GraphicDiagnostic] {
        if let failure = error as? GraphicFailure, !failure.diagnostics.isEmpty {
            return failure.diagnostics
        }
        return [.error(error.localizedDescription)]
    }
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

/// `ReelAV1`'s two decoded answers, which name no `rc_*` symbol, moved out of
/// `ReelCore.swift` (a pure move, codec-export C1's fix pass).
extension ReelAV1 {
    struct Color: Decodable {
        let primaries, transfer, matrix: Int
        let fullRange: Bool
    }

    /// `rc_av1_config`'s answer; `record` is the `av1C` atom's body.
    struct Config: Decodable {
        let record: Data
        let seqProfile, seqLevelIdx, seqTier, bitDepth: Int
        let monochrome: Bool
        let color: Color

        private enum CodingKeys: String, CodingKey {
            case av1cHex, seqProfile, seqLevelIdx, seqTier, bitDepth, monochrome, color
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let hex = Array(try c.decode(String.self, forKey: .av1cHex).utf8)
            let bytes = stride(from: 0, to: hex.count - 1, by: 2).compactMap {
                UInt8(String(decoding: hex[$0...$0 + 1], as: UTF8.self), radix: 16)
            }
            guard bytes.count * 2 == hex.count else {
                throw DecodingError.dataCorruptedError(
                    forKey: .av1cHex, in: c, debugDescription: "not hex")
            }
            record = Data(bytes)
            seqProfile = try c.decode(Int.self, forKey: .seqProfile)
            seqLevelIdx = try c.decode(Int.self, forKey: .seqLevelIdx)
            seqTier = try c.decode(Int.self, forKey: .seqTier)
            bitDepth = try c.decode(Int.self, forKey: .bitDepth)
            monochrome = try c.decode(Bool.self, forKey: .monochrome)
            color = try c.decode(Color.self, forKey: .color)
        }
    }
}

/// `data`'s bytes and count for an `rc_*` call (`ReelHDR10`'s), or NULL and 0 when absent or
/// empty.
func withBytes<R>(_ data: Data?, _ body: (UnsafePointer<UInt8>?, Int) -> R) -> R {
    guard let data, !data.isEmpty else { return body(nil, 0) }
    return data.withUnsafeBytes { body($0.bindMemory(to: UInt8.self).baseAddress, $0.count) }
}
