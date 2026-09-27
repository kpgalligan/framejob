// tools/proof/v2_cover.swift — road map 11's V2a: an opaque panel put over a
// screen rect so the Reelcut editor under it reads OCCLUDED, without ever
// activating this process or Reelcut.
//
//   v2_cover <x> <y> <w> <h> <seconds> <release-file>
//
// The rect is in Cocoa screen points (bottom-left origin), as `snapshot_ui`'s
// listing reports a window's `frame`. The panel is borderless and
// non-activating at `.floating` level, under an `.accessory` policy, ordered
// front with `orderFrontRegardless`; it prints `UP` once it is on screen and
// exits when `<release-file>` exists (polled every 50 ms) or after
// `<seconds>`, whichever comes first. It covers the person's screen for that
// long, which is why `v2_snapshot.py` keeps each episode under 60 s.
//
// Standalone: no app sources. `swiftc v2_cover.swift -o v2_cover`.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 7,
    let x = Double(arguments[1]), let y = Double(arguments[2]),
    let w = Double(arguments[3]), let h = Double(arguments[4]),
    let seconds = Double(arguments[5])
else {
    FileHandle.standardError.write(
        Data("usage: v2_cover <x> <y> <w> <h> <seconds> <release-file>\n".utf8))
    exit(2)
}
let releaseFile = arguments[6]

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let panel = NSPanel(
    contentRect: NSRect(x: x, y: y, width: w, height: h),
    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = true
panel.backgroundColor = NSColor(calibratedWhite: 0.5, alpha: 1)
panel.hasShadow = false
panel.level = .floating
panel.ignoresMouseEvents = false
panel.hidesOnDeactivate = false
panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
panel.orderFrontRegardless()

let deadline = Date().addingTimeInterval(seconds)
DispatchQueue.main.async {
    print("UP")
    fflush(stdout)
}
let poll = Timer(timeInterval: 0.05, repeats: true) { _ in
    if FileManager.default.fileExists(atPath: releaseFile) || Date() >= deadline {
        panel.orderOut(nil)
        exit(0)
    }
}
RunLoop.main.add(poll, forMode: .common)
app.run()
