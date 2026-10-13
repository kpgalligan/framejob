// tools/proof/capture_spike/probe_layout.swift — the `layout` mode (Q4):
// do the layout dump's two signals answer truthfully in an `-O`,
// whole-module build?
//
// `hasAmbiguousLayout` against a view pinned leading, top and width only
// (ambiguous: nothing fixes its height) and one with its height pinned too;
// then over the whole editor tree. "Intrinsic width > frame width" against a
// truncating single-line label, one whose text fits, and a wrapping label;
// then issue #70's note (`TextPane.wordStyleNote`) in the Text sub-tab.
import AppKit

enum ProbeLayout {
    static func frameJSON(_ r: NSRect) -> [Double] {
        [r.minX, r.minY, r.width, r.height].map { Double(($0 * 100).rounded() / 100) }
    }

    static func label(_ field: NSTextField) -> ProbeJSON {
        let intrinsic = field.intrinsicContentSize.width
        return [
            "intrinsic_w": Double((intrinsic * 100).rounded() / 100),
            "frame_w": Double((field.frame.width * 100).rounded() / 100),
            "truncated": intrinsic > field.frame.width,
        ]
    }

    static func run(fixtures: URL, png: URL) -> (ProbeJSON, ProbeJSON) {
        var rows: ProbeJSON = [:]
        // The controls, in a window of their own.
        let window = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 480, height: 480),
            styleMask: [.titled], backing: .buffered, defer: false)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 480))
        window.contentView = root
        ProbeSupport.place(window)

        let loose = NSView()
        loose.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(loose)
        let pinned = NSView()
        pinned.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(pinned)
        NSLayoutConstraint.activate([
            loose.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            loose.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            loose.widthAnchor.constraint(equalToConstant: 100),
            pinned.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 200),
            pinned.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            pinned.widthAnchor.constraint(equalToConstant: 100),
            pinned.heightAnchor.constraint(equalToConstant: 40),
        ])
        root.layoutSubtreeIfNeeded()
        rows["L1"] = [
            "ambiguous": loose.hasAmbiguousLayout, "frame": frameJSON(loose.frame),
        ] as ProbeJSON
        rows["L2"] = [
            "ambiguous": pinned.hasAmbiguousLayout, "frame": frameJSON(pinned.frame),
        ] as ProbeJSON

        let long = "Word style and animation do not compose; the word style wins, always."
        let truncating = NSTextField(labelWithString: long)
        truncating.lineBreakMode = .byTruncatingTail
        truncating.usesSingleLineMode = true
        truncating.frame = NSRect(x: 10, y: 100, width: 120, height: 20)
        root.addSubview(truncating)
        let fits = NSTextField(labelWithString: "Fits")
        fits.lineBreakMode = .byTruncatingTail
        fits.usesSingleLineMode = true
        fits.frame = NSRect(x: 10, y: 130, width: 200, height: 20)
        root.addSubview(fits)
        let wrapping = NSTextField(wrappingLabelWithString: long)
        wrapping.usesSingleLineMode = false
        wrapping.lineBreakMode = .byWordWrapping
        wrapping.preferredMaxLayoutWidth = 120
        wrapping.frame = NSRect(x: 10, y: 160, width: 120, height: 200)
        root.addSubview(wrapping)
        root.layoutSubtreeIfNeeded()
        rows["L4"] = label(truncating)
        rows["L5"] = label(fits)
        var l6 = label(wrapping)
        l6["preferred_max"] = Double(wrapping.preferredMaxLayoutWidth)
        l6["intrinsic_h"] = Double(wrapping.intrinsicContentSize.height)
        rows["L6"] = l6

        // The editor: note.framejob's text clip selected, the Text sub-tab.
        let url = fixtures.appendingPathComponent("note.framejob")
        guard let e = try? ProbeEditor(url, select: [2], playhead: 0.5) else {
            rows["L3"] = probeError("open failed")
            rows["L7"] = probeError("open failed")
            return (ProbeSupport.windowFacts(nil, activation: nil), rows)
        }
        e.editor.inspector?.select(.clip)
        e.editor.inspector?.selectClipSubTab(.text)
        ProbeSupport.spin(0.5)
        e.contentView.layoutSubtreeIfNeeded()
        let facts = ProbeSupport.windowFacts(e.window, activation: nil)
        let tree = e.contentView.probeTree
        var ambiguous: [ProbeJSON] = []
        for view in tree where view.hasAmbiguousLayout {
            ambiguous.append([
                "class": probeClassName(view), "id": view.accessibilityIdentifier(),
                "frame": frameJSON(view.convert(view.bounds, to: nil)),
            ])
        }
        rows["L3"] = ["ambiguous": ambiguous, "views": tree.count] as ProbeJSON

        // L7: #70.
        let notes = tree.compactMap { $0 as? InspectorNoteLabel }
            .filter { $0.stringValue == TextPane.wordStyleNote }
        var l7: ProbeJSON = ["notes_found": notes.count]
        if let note = notes.first(where: { !$0.isHiddenOrHasHiddenAncestor }) {
            note.scrollToVisible(note.bounds)
            ProbeSupport.spin(0.3)
            e.contentView.layoutSubtreeIfNeeded()
            let visible = !note.visibleRect.isEmpty && note.window != nil
            l7["on_screen"] = visible
            l7["frame"] = frameJSON(note.convert(note.bounds, to: nil))
            l7.merge(label(note), uniquingKeysWith: { a, _ in a })
            if let shot = ProbeSupport.settle(e.contentView) {
                ProbeSupport.writePNG(shot.rep, png, "note")
            }
        } else {
            l7["on_screen"] = false
        }
        var wide: [ProbeJSON] = []
        for view in e.contentView.probeTree {
            guard let field = view as? NSTextField, !field.isHiddenOrHasHiddenAncestor,
                !field.visibleRect.isEmpty, !field.stringValue.isEmpty
            else { continue }
            let intrinsic = field.intrinsicContentSize.width
            if intrinsic != NSView.noIntrinsicMetric, intrinsic > field.frame.width {
                wide.append([
                    "class": probeClassName(field), "text": String(field.stringValue.prefix(60)),
                    "intrinsic_w": Double((intrinsic * 100).rounded() / 100),
                    "frame_w": Double((field.frame.width * 100).rounded() / 100),
                    "wraps": !field.usesSingleLineMode
                        && field.cell?.wraps == true,
                ])
            }
        }
        l7["wider_than_frame"] = wide
        rows["L7"] = l7
        e.close()
        return (facts, rows)
    }
}
