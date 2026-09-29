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
// `{"leaves": [{"path", "selector", "refusal"}], "table": {selector: verdict},
//   "target": {"ok": Bool, "detail": String}}`.
//
// `target` is #133's case: two items share one action in a menu of their
// own, one targeting an object that answers it and one targeting an object
// that does not. `UIMenu.target(for:window:)` must answer nil for the second,
// with no fallback to the chain, and the object for the first.
import AppKit

final class V2ProbeAnswers: NSObject {
    @objc func v2ProbeAction(_ sender: Any?) {}
}

final class V2ProbeSilent: NSObject {}

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
// `target` is weak on an item: both objects are held here for the case.
let answers = V2ProbeAnswers()
let silent = V2ProbeSilent()
let probeMenu = NSMenu(title: "V2 Probe")
let answering = NSMenuItem(
    title: "Answers", action: #selector(V2ProbeAnswers.v2ProbeAction(_:)), keyEquivalent: "")
answering.target = answers
let unanswered = NSMenuItem(
    title: "Silent", action: #selector(V2ProbeAnswers.v2ProbeAction(_:)), keyEquivalent: "")
unanswered.target = silent
probeMenu.addItem(answering)
probeMenu.addItem(unanswered)
let silentTarget = UIMenu.target(for: unanswered, window: nil)
let silentEnabled = UIMenu.isEnabled(unanswered, target: silentTarget)
let answeringTarget = UIMenu.target(for: answering, window: nil)
let answeringEnabled = UIMenu.isEnabled(answering, target: answeringTarget)
let silentName = silentTarget.map { NSStringFromClass(type(of: $0)) } ?? "nil"
let targetCase: [String: Any] = [
    "ok": silentTarget == nil && !silentEnabled && answeringTarget === answers
        && answeringEnabled,
    "detail": "silent item: target \(silentName), enabled \(silentEnabled) (want nil, "
        + "false); answering item: target is its object \(answeringTarget === answers), "
        + "enabled \(answeringEnabled) (want true, true)",
]

do {
    let data = try JSONSerialization.data(
        withJSONObject: ["leaves": leaves, "table": table, "target": targetCase],
        options: [.sortedKeys])
    print("ANSWER " + String(decoding: data, as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("encode failed: \(error)\n".utf8))
    exit(1)
}
