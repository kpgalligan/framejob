// Road map "codec-export" C4 — the bundled encoders' rate tables through the shared
// `ExportRateTable` (spec §11 CX-13 (3), CX-14 (6), CX-16 (7)): `SVTAV1Encoder.crf` per speed
// and `VP9Encoder.cqLevel` per depth at the bits per pixel per frame `vp9_export_proof.py`'s
// P1 asks. The probe only answers the values; the proof holds the expected table.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// module `FrameJob`, against `libframejob_core.a` and the encoder archives, on
// `swift_build.py`'s line. No window, no app, no encoder opened.
//
//   vp9_rate_probe <answer.json> <bpp>...
//
// One JSON object out: `bpp` (as asked), `svt` {faster, balanced, smaller: [CRF per bpp]}
// and `vp9` {"8", "10": [CQ per bpp]}.
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard let answerPath = arguments.first else {
    FileHandle.standardError.write("usage: vp9_rate_probe <answer.json> <bpp>...\n".data(using: .utf8)!)
    exit(2)
}
let points = arguments.dropFirst().compactMap(Double.init)

var svt: [String: [UInt32]] = [:]
for speed in EncoderSpeed.allCases {
    svt[speed.rawValue] = points.map { SVTAV1Encoder.crf(speed: speed, bitsPerPixel: $0) }
}
var vp9: [String: [UInt32]] = [:]
for depth in [8, 10] {
    vp9[String(depth)] = points.map { VP9Encoder.cqLevel(bitDepth: depth, bitsPerPixel: $0) }
}
let answer = try JSONSerialization.data(
    withJSONObject: ["bpp": points, "svt": svt, "vp9": vp9], options: [.prettyPrinted])
try answer.write(to: URL(fileURLWithPath: answerPath))
