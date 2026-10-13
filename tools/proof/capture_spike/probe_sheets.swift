// tools/proof/capture_spike/probe_sheets.swift — the `sheets`, `modal` and
// `menu` modes (Q2).
//
// `sheets`: the app's own menu bar (`AppDelegate().buildMainMenu()`) hung
// off `NSApp`, the probe activated, and three menu items that put up a sheet
// — File ▸ Export… (`presentAsSheet`), Track ▸ Remove Track
// (`NSAlert.beginSheetModal`), File ▸ Add Media… (`NSOpenPanel
// .beginSheetModal`) — each run through `NSMenu.performActionForItem(at:)`,
// then `NSApp.sendAction` if no sheet came; the sheet captured, the parent
// captured under it, the sheet closed.
//
// `modal`: the control for "a route that returns with the main queue
// unserviced": a probe item whose action is `NSAlert().runModal()`, aborted
// by a `.modalPanel`-mode timer at 1 s, with a background thread's
// `DispatchQueue.main.sync` at 0.3 s.
//
// `menu`: every leaf of `buildMainMenu()` — path, selector, key — for the
// inventory (`inventory.py`).
import AppKit

enum ProbeSheets {
    struct Case {
        let id: String
        let path: [String]
        let close: String
    }

    static let cases = [
        Case(id: "a", path: ["File", "Export…"], close: "dismiss"),
        Case(id: "b", path: ["Track", "Remove Track"], close: "endSheet"),
        Case(id: "c", path: ["File", "Add Media…"], close: "endSheet"),
    ]

    /// The item at `path` and the menu that holds it.
    static func find(_ menu: NSMenu, _ path: [String]) -> (NSMenu, Int)? {
        guard let first = path.first else { return nil }
        guard let index = menu.items.firstIndex(where: { $0.title == first }) else { return nil }
        if path.count == 1 { return (menu, index) }
        guard let sub = menu.items[index].submenu else { return nil }
        return find(sub, Array(path.dropFirst()))
    }

    static func runSheets(fixtures: URL, png: URL) -> (ProbeJSON, ProbeJSON) {
        var rows: ProbeJSON = [:]
        let ids = ["S0", "S1a", "S1b", "S1c", "S2a", "S2b", "S2c", "S3"]
        let e: ProbeEditor
        do {
            e = try ProbeEditor(
                fixtures.appendingPathComponent("well.framejob"), select: [2], playhead: 1)
        } catch {
            for id in ids { rows[id] = probeError("open failed: \(error)") }
            return (ProbeSupport.windowFacts(nil, activation: nil), rows)
        }
        let delegate = AppDelegate()
        let mainMenu = delegate.buildMainMenu()
        NSApp.mainMenu = mainMenu
        let activation = ProbeSupport.activate(e.window)
        let facts = ProbeSupport.windowFacts(e.window, activation: activation)
        var found: [String: (NSMenu, Int)] = [:]
        var items: [ProbeJSON] = []
        var targets: ProbeJSON = [:]
        for c in cases {
            let hit = find(mainMenu, c.path)
            if let hit = hit { found[c.id] = hit }
            let item = hit.map { $0.0.items[$0.1] }
            let action = item?.action
            items.append([
                "case": c.id, "path": c.path, "found": hit != nil,
                "selector": action.map { NSStringFromSelector($0) } ?? NSNull(),
                "enabled": item?.isEnabled ?? false,
            ])
            if let action = action {
                targets[NSStringFromSelector(action)] = probeClassName(
                    NSApp.target(forAction: action, to: nil, from: item) as AnyObject?)
            }
        }
        rows["S0"] = [
            "menu_set": NSApp.mainMenu === mainMenu, "menus": mainMenu.items.map(\.title),
            "items": items, "all_found": found.count == cases.count, "targets": targets,
            "is_active": NSApp.isActive, "active_ms": activation["active_ms"] ?? NSNull(),
            "key_is_editor": NSApp.keyWindow === e.window,
            "main_is_editor": NSApp.mainWindow === e.window,
            "first_responder": probeClassName(e.window.firstResponder),
        ] as ProbeJSON
        var s3: [ProbeJSON] = []
        for c in cases {
            guard let (menu, index) = found[c.id] else {
                rows["S1" + c.id] = probeError("menu item \(c.path) not found")
                rows["S2" + c.id] = probeError("menu item \(c.path) not found")
                continue
            }
            let item = menu.items[index]
            var s1 = route(1, e.window) { menu.performActionForItem(at: index) }
            if (s1["sheet"] as? Bool) != true, let action = item.action {
                e.window.makeKeyAndOrderFront(nil)
                var second = route(2, e.window) { NSApp.sendAction(action, to: nil, from: item) }
                second["route1"] = s1
                s1 = second
            }
            rows["S1" + c.id] = s1
            guard let sheet = e.window.attachedSheet else {
                rows["S2" + c.id] = probeError("no sheet to capture")
                continue
            }
            var s2: ProbeJSON = ["sheet_class": probeClassName(sheet)]
            if let content = sheet.contentView, let shot = ProbeSupport.settle(content) {
                ProbeSupport.writePNG(shot.rep, png, "sheet_" + c.id)
                let want = [
                    Int((content.bounds.width * sheet.backingScaleFactor).rounded()),
                    Int((content.bounds.height * sheet.backingScaleFactor).rounded()),
                ]
                s2["px"] = [shot.pixels.width, shot.pixels.height]
                s2["want_px"] = want
                s2["size_ok"] = [shot.pixels.width, shot.pixels.height] == want
                s2["distinct_colours"] = shot.pixels.distinctColours()
                s2["settled"] = shot.settled
                s2["content_class"] = probeClassName(content)
                s2["subviews"] = content.subviews.count
                // S3: the parent's capture under the sheet's frame.
                if let parent = ProbeSupport.settle(e.contentView) {
                    ProbeSupport.writePNG(parent.rep, png, "parent_" + c.id)
                    let inWindow = e.window.convertFromScreen(sheet.frame)
                    let rect = parent.pixelRect(
                        e.contentView.convert(inWindow, from: nil), from: e.contentView)
                    let w = min(rect.width, shot.pixels.width)
                    let h = min(rect.height, shot.pixels.height)
                    var same = 0
                    for y in 0..<max(h, 0) {
                        for x in 0..<max(w, 0) {
                            let a = parent.pixels.rgb(rect.x0 + x, rect.y0 + y)
                            let b = shot.pixels.rgb(x, y)
                            if abs(a.0 - b.0) <= 3 && abs(a.1 - b.1) <= 3 && abs(a.2 - b.2) <= 3 {
                                same += 1
                            }
                        }
                    }
                    let n = max(w * h, 1)
                    s3.append([
                        "case": c.id, "rect_px": rect.json, "compared": w * h,
                        "matching": same,
                        "fraction": (Double(same) / Double(n) * 10000).rounded() / 10000,
                    ])
                }
            } else {
                s2["error"] = "sheet has no content view or it would not capture"
            }
            // Close it.
            let closeStart = Date()
            if c.close == "dismiss" {
                if let presented = e.editor.presentedViewControllers?.first {
                    e.editor.dismiss(presented)
                } else {
                    e.window.endSheet(sheet, returnCode: .cancel)
                    s2["close_fallback"] = "endSheet (no presented view controller)"
                }
            } else {
                e.window.endSheet(sheet, returnCode: .cancel)
            }
            while e.window.attachedSheet != nil, Date().timeIntervalSince(closeStart) < 3 {
                ProbeSupport.pump()
            }
            s2["closed"] = e.window.attachedSheet == nil
            s2["close_ms"] = ProbeSupport.ms(since: closeStart)
            s2["close_by"] = c.close
            rows["S2" + c.id] = s2
            ProbeSupport.spin(0.5)
        }
        rows["S3"] = ["sheets": s3] as ProbeJSON
        e.close()
        return (facts, rows)
    }

    /// One delivery route: a main-queue marker enqueued just before the call,
    /// then the call, then a ≤ 3 s wait for an attached sheet.
    static func route(_ number: Int, _ window: NSWindow, _ call: () -> Void) -> ProbeJSON {
        var markerRan = false
        DispatchQueue.main.async { markerRan = true }
        let start = Date()
        call()
        let returnedMs = ProbeSupport.ms(since: start)
        let unrun = !markerRan
        let modalNil = NSApp.modalWindow == nil
        let waitStart = Date()
        while window.attachedSheet == nil, Date().timeIntervalSince(waitStart) < 3 {
            ProbeSupport.pump()
        }
        let sheet = window.attachedSheet
        return [
            "route": number, "returned_ms": returnedMs, "marker_unrun_at_return": unrun,
            "modal_window_nil": modalNil, "sheet": sheet != nil,
            "sheet_ms": sheet != nil ? ProbeSupport.ms(since: start) : -1,
            "sheet_class": probeClassName(sheet),
            "modal_window_after": probeClassName(NSApp.modalWindow),
        ]
    }

    // MARK: - modal (S4)

    final class ModalTarget: NSObject {
        var inCall = false
        @objc func runAlert(_ sender: Any?) {
            let alert = NSAlert()
            alert.messageText = "capture spike S4"
            _ = alert.runModal()
        }
    }

    static func runModal() -> (ProbeJSON, ProbeJSON) {
        let target = ModalTarget()
        let menu = NSMenu(title: "Probe")
        let item = NSMenuItem(
            title: "Run Modal", action: #selector(ModalTarget.runAlert(_:)), keyEquivalent: "")
        item.target = target
        menu.addItem(item)
        var markerRan = false, markerInside = false
        let lock = NSLock()
        var syncRan = false, syncInside = false, syncMs = -1
        let t0 = Date()
        DispatchQueue.main.async {
            markerRan = true
            markerInside = target.inCall
        }
        let timer = Timer(timeInterval: 1.0, repeats: false) { _ in NSApp.abortModal() }
        RunLoop.main.add(timer, forMode: .modalPanel)
        let thread = Thread {
            Thread.sleep(forTimeInterval: 0.3)
            DispatchQueue.main.sync {
                lock.lock()
                syncRan = true
                syncInside = target.inCall
                syncMs = ProbeSupport.ms(since: t0)
                lock.unlock()
            }
        }
        thread.start()
        target.inCall = true
        let start = Date()
        menu.performActionForItem(at: 0)
        let elapsed = Date().timeIntervalSince(start)
        target.inCall = false
        ProbeSupport.spin(1.0)
        timer.invalidate()
        lock.lock()
        let s4: ProbeJSON = [
            "elapsed_s": (elapsed * 1000).rounded() / 1000, "marker_ran": markerRan,
            "marker_inside": markerInside, "sync_completed": syncRan, "sync_inside": syncInside,
            "sync_ms": syncMs,
        ]
        lock.unlock()
        return (ProbeSupport.windowFacts(nil, activation: nil), ["S4": s4])
    }

    // MARK: - menu (I1)

    static func runMenu() -> (ProbeJSON, ProbeJSON) {
        let delegate = AppDelegate()
        let mainMenu = delegate.buildMainMenu()
        var leaves: [ProbeJSON] = []
        func walk(_ menu: NSMenu, _ path: [String]) {
            for item in menu.items where !item.isSeparatorItem {
                let here = path + [item.title]
                if let sub = item.submenu {
                    walk(sub, here)
                    continue
                }
                var mods: [String] = []
                let mask = item.keyEquivalentModifierMask
                if mask.contains(.control) { mods.append("⌃") }
                if mask.contains(.option) { mods.append("⌥") }
                if mask.contains(.shift) { mods.append("⇧") }
                if mask.contains(.command) { mods.append("⌘") }
                let key = item.keyEquivalent.isEmpty
                    ? "" : mods.joined() + item.keyEquivalent.unicodeScalars.map {
                        $0.value < 0x20 || $0.value >= 0xF700 || $0.value == 0x7F
                            ? String(format: "U+%04X", $0.value) : String($0)
                    }.joined()
                leaves.append([
                    "path": here, "selector": item.action.map { NSStringFromSelector($0) } ?? NSNull(),
                    "key": key, "tag": item.tag,
                ])
            }
        }
        walk(mainMenu, [])
        return (
            ProbeSupport.windowFacts(nil, activation: nil),
            ["I1": ["leaves": leaves, "count": leaves.count] as ProbeJSON]
        )
    }
}
