import AppKit
import CoreGraphics

// Road map 14 MC1, q2: the windows a pid owns, the console's state and the
// frontmost app, as one JSON line. `mc1_spike.py` compiles it into
// tools/proof/work/mc1_spike/windows_probe.
//
//     windows_probe <pid>
//
// It reads CGWindowList's layer, on-screen flag and bounds, never a title,
// so it needs no Screen Recording grant.

let arguments = CommandLine.arguments
guard arguments.count == 2, let pid = Int32(arguments[1]) else {
    FileHandle.standardError.write(Data("usage: windows_probe <pid>\n".utf8))
    exit(2)
}

var onConsole = false
var locked = false
if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
    onConsole = (session[kCGSessionOnConsoleKey as String] as? Bool) ?? false
    locked = (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
}

let frontPid = Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)

var windows: [[String: Any]] = []
let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for window in info {
    guard let owner = window[kCGWindowOwnerPID as String] as? Int32, owner == pid else { continue }
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    let onscreen = window[kCGWindowIsOnscreen as String] as? Bool ?? false
    var bounds: [Double] = [0, 0, 0, 0]
    if let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
       let rect = CGRect(dictionaryRepresentation: dictionary) {
        bounds = [Double(rect.origin.x), Double(rect.origin.y), Double(rect.width), Double(rect.height)]
    }
    windows.append(["layer": layer, "onscreen": onscreen, "bounds": bounds])
}

let answer: [String: Any] = [
    "on_console": onConsole,
    "locked": locked,
    "front_pid": frontPid,
    "windows": windows,
]
let data = try JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
