// Road map "codec-export" C5 — `vp9_alpha_webm`'s pairing of its two libvpx streams
// (spec §11 CX-17 (4)) through `VP9AlphaEncoder` with stub encoders, and
// `VP9Encoder.keyInterval(fps:)`. The probe only answers what it saw; the proof
// (`vp9_alpha_export_proof.py` P1) holds what is expected.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// module `FrameJob`, against `libframejob_core.a` and the encoder archives, on
// `swift_build.py`'s line. No window, no app, no encoder opened.
//
//   vp9_alpha_probe <answer.json>
//
// One JSON object out: `matched` (the pairs a matched pair of streams answers: [pts, key,
// picture bytes, alpha bytes] each, then whether a drained pair answers nil), `pts` and `key`
// (the sentence each disagreement throws, or "no error"), `ended` (one stream ending first),
// and `intervals` {fps: frames} at 24, 30000/1001, 30 and 60.
import Foundation

/// An encoder that answers the packets it was given, in order, and nothing else.
final class StubEncoder: ExportVideoEncoder {
    let name = "stub"
    var packets: [ExportEncodedPacket]
    var ended = false

    init(_ packets: [ExportEncodedPacket]) {
        self.packets = packets
    }

    func send(_ frame: I010Frame, index: Int64) throws {}
    func sendEndOfStream() throws { ended = true }

    func nextPacket(wait: Bool) throws -> ExportEncodedPacket? {
        packets.isEmpty ? nil : packets.removeFirst()
    }

    func containerBytes(_ data: Data) throws -> Data { data }
}

func packet(_ pts: Int64, key: Bool, byte: UInt8) -> ExportEncodedPacket {
    ExportEncodedPacket(data: Data([byte, UInt8(pts)]), pts: pts, isLast: false, isKey: key)
}

/// Every pair the encoder answers, waiting at the end as the pump's finish does, or the
/// sentence it threw.
func drain(_ encoder: VP9AlphaEncoder) -> (pairs: [[Any]], error: String?) {
    var pairs: [[Any]] = []
    do {
        while let p = try encoder.nextPacket(wait: false) {
            pairs.append([p.pts, p.isKey, [UInt8](p.data), [UInt8](p.alpha ?? Data())])
        }
        try encoder.sendEndOfStream()
        while let p = try encoder.nextPacket(wait: true) {
            pairs.append([p.pts, p.isKey, [UInt8](p.data), [UInt8](p.alpha ?? Data())])
        }
        return (pairs, nil)
    } catch {
        return (pairs, error.localizedDescription)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let answerPath = arguments.first else {
    FileHandle.standardError.write("usage: vp9_alpha_probe <answer.json>\n".data(using: .utf8)!)
    exit(2)
}

let keys = [true, false, false, true]
let matched = drain(VP9AlphaEncoder(
    picture: StubEncoder(keys.enumerated().map { packet(Int64($0), key: $1, byte: 0x50) }),
    alpha: StubEncoder(keys.enumerated().map { packet(Int64($0), key: $1, byte: 0xA1) })))
let pts = drain(VP9AlphaEncoder(
    picture: StubEncoder([packet(0, key: true, byte: 0x50), packet(1, key: false, byte: 0x50)]),
    alpha: StubEncoder([packet(0, key: true, byte: 0xA1), packet(2, key: false, byte: 0xA1)])))
let key = drain(VP9AlphaEncoder(
    picture: StubEncoder([packet(0, key: true, byte: 0x50), packet(1, key: false, byte: 0x50)]),
    alpha: StubEncoder([packet(0, key: true, byte: 0xA1), packet(1, key: true, byte: 0xA1)])))
let ended = drain(VP9AlphaEncoder(
    picture: StubEncoder([packet(0, key: true, byte: 0x50), packet(1, key: false, byte: 0x50)]),
    alpha: StubEncoder([packet(0, key: true, byte: 0xA1)])))

var intervals: [String: Int] = [:]
for (label, fps) in [("24", Fps(num: 24, den: 1)), ("29.97", Fps(num: 30000, den: 1001)),
                     ("30", Fps(num: 30, den: 1)), ("60", Fps(num: 60, den: 1))] {
    intervals[label] = VP9Encoder.keyInterval(fps: fps)
}

let answer: [String: Any] = [
    "matched": ["pairs": matched.pairs, "error": matched.error ?? "no error"],
    "pts": pts.error ?? "no error",
    "pts_pairs": pts.pairs.count,
    "key": key.error ?? "no error",
    "key_pairs": key.pairs.count,
    "ended": ended.error ?? "no error",
    "intervals": intervals,
]
let data = try JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted])
try data.write(to: URL(fileURLWithPath: answerPath))
