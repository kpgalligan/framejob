// tools/proof/v2_menu_probe.swift — road map 11's V2b: the app's own menu
// bar walked by `UIMenu.leaves(of:)`, each leaf's `UIMenu.refusal(for:)`,
// and the whole of `UIMenu.verdicts`.
//
// `v2_menu.py` copies it to `work/v2_menu/probe/main.swift` and compiles it
// LAST with every file in `app/Sources` but `main.swift`, over
// `harness/build.sh`'s swiftc line (`-D REELCUT_DEV_TOOLS`), so the walk, the
// refusal and the table are the ones the app ships. `AppDelegate().
// buildMainMenu()` is built and never hung on `NSApp.mainMenu`, nothing is
// validated, and no window opens; `GraphicTemplates/` beside the binary
// gives Insert ▸ Graphic its template items. It prints exactly one stdout
// line, `ANSWER <json>`:
// `{"leaves": [{"path", "selector", "refusal"}], "table": {selector: verdict}}`.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let menu = AppDelegate().buildMainMenu()
var leaves: [[String: Any]] = []
for leaf in UIMenu.leaves(of: menu) {
    leaves.append([
        "path": leaf.path,
        "selector": UIMenu.selector(of: leaf.item).map { $0 as Any } ?? NSNull(),
        "refusal": UIMenu.refusal(for: leaf.item).map { $0.rawValue as Any } ?? NSNull(),
    ])
}
var table: [String: String] = [:]
for (selector, verdict) in UIMenu.verdicts {
    table[selector] = verdict.rawValue
}
do {
    let data = try JSONSerialization.data(
        withJSONObject: ["leaves": leaves, "table": table], options: [.sortedKeys])
    print("ANSWER " + String(decoding: data, as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("encode failed: \(error)\n".utf8))
    exit(1)
}
