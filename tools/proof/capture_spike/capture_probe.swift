// tools/proof/capture_spike/capture_probe.swift — the capture spike's probe
// (road map 11, V1). The runner copies it to
// `work/capture_spike/probe/main.swift` and compiles it LAST, with every file
// in `app/Sources` but `main.swift` and the five `probe_*.swift` files beside
// this one, over `harness/build.sh`'s swiftc line plus Release's `-O -wmo`:
// the same view classes as the app, optimised as Release is.
//
//     capture_probe <mode> <fixtures-dir> <png-dir>
//     mode ∈ well | sheets | modal | menu | appearance | layout
//
// It prints exactly one stdout line, `ANSWER <json>`:
// `{"mode", "window": {...}, "rows": {"<ID>": {<measured> | "error"}}}`.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(
        "usage: capture_probe <well|sheets|modal|menu|appearance|layout> <fixtures> <png>\n"
            .data(using: .utf8)!)
    exit(64)
}
let mode = arguments[1]
let fixtures = URL(fileURLWithPath: arguments[2])
let png = URL(fileURLWithPath: arguments[3])
try? FileManager.default.createDirectory(at: png, withIntermediateDirectories: true)
ProbeSupport.boot()

let result: (ProbeJSON, ProbeJSON)
switch mode {
case "well": result = ProbeWell.run(fixtures: fixtures, png: png)
case "sheets": result = ProbeSheets.runSheets(fixtures: fixtures, png: png)
case "modal": result = ProbeSheets.runModal()
case "menu": result = ProbeSheets.runMenu()
case "appearance": result = ProbeAppearance.run(fixtures: fixtures, png: png)
case "layout": result = ProbeLayout.run(fixtures: fixtures, png: png)
default:
    FileHandle.standardError.write("unknown mode \(mode)\n".data(using: .utf8)!)
    exit(64)
}
let answer: ProbeJSON = ["mode": mode, "window": result.0, "rows": result.1]
let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER ".data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
