import AppKit

/// The preview's tags, in the canvas's 24 pt top-left void, each shown only
/// while its View switch is on (`EditorViewController+Seeing.swift`).
enum PreviewTag {
    /// The "Ungraded" tag (spec §11 GR-4): top-left of the preview pane, inside
    /// the canvas's 24 pt void, shown while View ▸ Show Ungraded is on.
    case ungraded
    /// The "Selection" tag (spec §11 GR-13): Show Selection's, beside
    /// "Ungraded" in the preview's top-left void, shown only while the switch
    /// is on.
    case selection
    /// The "SDR Version" tag (spec §11 HD-7, HD-14 (g)): Show SDR Version's,
    /// third in the preview's top-left void, shown only while the switch is on —
    /// in an SDR project too, where the picture does not change.
    case sdrVersion

    var text: String {
        switch self {
        case .ungraded: return "Ungraded"
        case .selection: return "Selection"
        case .sdrVersion: return "SDR Version"
        }
    }

    var identifier: String {
        switch self {
        case .ungraded: return "preview.ungraded"
        case .selection: return "preview.selection"
        case .sdrVersion: return "preview.sdrVersion"
        }
    }
}

/// One preview tag. It takes no clicks, so a gesture on the canvas beneath it
/// is the canvas's.
final class PreviewTagView: NSTextField {
    /// Which tag — not `tag`, which `NSView` already has as an `Int`.
    let kind: PreviewTag

    init(_ kind: PreviewTag) {
        self.kind = kind
        super.init(frame: .zero)
        stringValue = kind.text
        isEditable = false
        isSelectable = false
        isBezeled = false
        isBordered = false
        drawsBackground = true
        backgroundColor = DS.chromeBackground
        textColor = DS.textMuted
        font = DS.mono(10)
        isHidden = true
        setAccessibilityIdentifier(kind.identifier)
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("PreviewTagView does not support NSCoder")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
