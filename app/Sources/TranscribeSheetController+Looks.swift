import AppKit

// MARK: - Sheet: the looks row

/// The three LOOKS on the Generate Captions card (spec §11 W-15, issue batch
/// B86): "Slide the pill", "Fill words as spoken" and "Dim in pauses", one
/// per line under the Style popup and above the preview, and the note about
/// on-device pauses under them.
///
/// **A box that does not apply is greyed, not hidden, and keeps its tick.**
/// `refreshLooksRow()` sets each box's `isEnabled` from
/// `CaptionLooks.Look.isLive(for:)` and never its state, so Slide ticked on
/// Pill is still ticked after a trip through Karaoke; `looks` counts a box
/// only while it is ENABLED and on, which is what `finish` hands `place` and
/// what the preview draws.
///
/// **Each box is remembered under its own key**, read when the row is built
/// and written by a CLICK (`lookChanged`) — never by Generate — and never by
/// the tool (R6-2 read across). An absent key is off, so a build that
/// remembered only a style opens with all three off.
///
/// **The note** shows whenever On this Mac is the engine and Dim is live (a
/// word style), ticked or not: the on-device engine's word ranges tile the
/// audio, so its words rarely carry the pause a dim waits for (W-13). It
/// wraps to two lines at the column's width, so the card is about two lines
/// taller while it shows.
extension TranscribeSheetController {

    /// The owner's sentence (spec §11 W-15).
    static let dimNote = "On-device words rarely carry a pause; this shows mostly with AssemblyAI."

    /// The looks a run commits: each box ENABLED and on.
    var looks: CaptionLooks {
        var out = CaptionLooks.none
        for look in CaptionLooks.Look.allCases {
            let box = checkbox(for: look)
            out[look] = box.isEnabled && box.state == .on
        }
        return out
    }

    func checkbox(for look: CaptionLooks.Look) -> NSButton {
        switch look {
        case .slide: return slideCheckbox
        case .fill: return fillCheckbox
        case .dim: return dimCheckbox
        }
    }

    /// Grid row 8: the three boxes stacked, each opening on its remembered
    /// state, and the note. `makeReplaceRow()` is the pattern.
    func makeLooksRow() -> [NSView] {
        var views: [NSView] = []
        for look in CaptionLooks.Look.allCases {
            let box = checkbox(for: look)
            box.title = look.title
            box.font = DS.sans(12)
            box.target = self
            box.action = #selector(lookChanged(_:))
            box.state = defaults.bool(forKey: look.defaultsKey) ? .on : .off
            box.setAccessibilityIdentifier("captions.look.\(look.rawValue)")
            views.append(box)
        }
        dimNoteLabel.stringValue = Self.dimNote
        dimNoteLabel.font = DS.sans(11)
        dimNoteLabel.textColor = DS.textMuted
        dimNoteLabel.isEditable = false
        dimNoteLabel.preferredMaxLayoutWidth = Self.previewSize.width
        dimNoteLabel.setAccessibilityIdentifier("captions.look.dimnote")
        views.append(dimNoteLabel)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return [fieldLabel(""), stack]
    }

    /// A click on one box: remember THAT box's state under its own key, and
    /// recompute. The third `defaults.set` on this card, beside the engine's
    /// and the style's.
    @objc func lookChanged(_ sender: Any?) {
        let clicked = CaptionLooks.Look.allCases.first { checkbox(for: $0) === sender as? NSButton }
        if let look = clicked {
            defaults.set(checkbox(for: look).state == .on, forKey: look.defaultsKey)
        }
        refresh()
    }

    /// Which boxes apply to the chosen style, and whether the note shows.
    /// Each box's STATE is left alone.
    func refreshLooksRow() {
        for look in CaptionLooks.Look.allCases {
            checkbox(for: look).isEnabled = look.isLive(for: style)
        }
        dimNoteLabel.isHidden = !(engine == .apple && dimCheckbox.isEnabled)
    }
}
