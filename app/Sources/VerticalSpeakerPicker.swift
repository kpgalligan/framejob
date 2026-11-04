import AppKit

/// The Make Vertical Version sheet's Microphones and Faces block, shown with Follow Speaker (road
/// map "creator-jobs" VR6b, spec §11 VR-66 (b), (d)): one checkbox per microphone track (the
/// first four ticked unless the sheet is restored with its own), one row per ticked microphone
/// with a Face pop-up, and a muted note. It shows the core's match (`offer`) and never computes
/// one: a sure match presets the pop-ups to its assignment, once per ticked set; a match that is
/// not sure, or none, leaves each on "Choose a face". `micFaces` is nil until every ticked
/// microphone has a face of its own. Names no `rc_*`.
final class VerticalSpeakerPicker: NSObject {
    static let chooseTitle = "Choose a face"
    static let sureNote =
        "Each microphone is matched to the face that talks with it; change one if it is wrong."
    static let unsureNote =
        "The faces do not show clearly who is on each microphone: choose each microphone's face."
    /// The most microphones `follow: speaker` takes (VR-60 (a)).
    static let mostMicrophones = 4

    let view: NSView
    private let microphones: [VerticalVersion.Microphone]
    private let onChange: () -> Void
    private var boxes: [NSButton] = []
    private let facesColumn = sheetColumn([])
    private let note = NSTextField(wrappingLabelWithString: "")
    /// The faces' pop-ups, one per ticked microphone, in `mics`' order.
    private var popups: [NSPopUpButton] = []
    /// The faces the pop-ups list, after "Choose a face".
    private var faces: [SpeakerMatch.Face] = []
    /// The ticked set the pop-ups were last offered a match for.
    private var offeredFor: [UInt32]?

    init(
        microphones: [VerticalVersion.Microphone], ticked: [UInt32]?,
        onChange: @escaping () -> Void
    ) {
        self.microphones = microphones
        self.onChange = onChange
        let column = sheetColumn([])
        column.spacing = 4
        let grid = makeSheetGrid([
            [fieldLabel("Microphones:"), column],
            [fieldLabel("Faces:"), facesColumn],
            [NSGridCell.emptyContentView, note],
        ])
        grid.row(at: 0).yPlacement = .top
        grid.row(at: 1).yPlacement = .top
        view = grid
        super.init()
        for (n, microphone) in microphones.enumerated() {
            let box = NSButton(
                checkboxWithTitle: microphone.name, target: self,
                action: #selector(tickChanged(_:)))
            box.font = DS.sans(13)
            box.state =
                (ticked.map { $0.contains(microphone.clip) } ?? (n < Self.mostMicrophones))
                ? .on : .off
            box.setAccessibilityIdentifier("vertical.mic.\(microphone.track)")
            boxes.append(box)
            column.addArrangedSubview(box)
        }
        facesColumn.spacing = 6
        note.font = DS.sans(12)
        note.textColor = DS.textMuted
        note.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2 - 118
        note.setAccessibilityIdentifier("vertical.speakerNote")
        rebuildRows()
    }

    /// The ticked microphones' clips, front to back.
    var mics: [UInt32] {
        zip(microphones, boxes).filter { $0.1.state == .on }.map(\.0.clip)
    }

    /// One face number per ticked microphone, in `mics`' order; nil until each has a face and
    /// no two share one.
    var micFaces: [UInt32]? {
        var chosen: [UInt32] = []
        for popup in popups {
            let index = popup.indexOfSelectedItem
            guard index >= 1, index - 1 < faces.count else { return nil }
            chosen.append(faces[index - 1].face)
        }
        guard !chosen.isEmpty, Set(chosen).count == chosen.count else { return nil }
        return chosen
    }

    /// The core's match for the ticked set: `mics` names, per entry of its `assignment`, the
    /// ticked microphone it is for. The pop-ups list its faces; a sure match presets them, and a
    /// set is preset once, so a person's choice stands through every later refresh.
    func offer(_ match: SpeakerMatch?, mics assigned: [UInt32]) {
        let ticked = mics
        guard offeredFor != ticked else { return }
        offeredFor = ticked
        faces = match?.faces ?? []
        for popup in popups { fill(popup) }
        if let match, match.sure {
            for (n, mic) in assigned.enumerated() where n < match.assignment.count {
                guard let row = ticked.firstIndex(of: mic),
                    let face = faces.firstIndex(where: { $0.face == match.assignment[n] })
                else { continue }
                popups[row].selectItem(at: face + 1)
            }
            note.stringValue = Self.sureNote
        } else {
            note.stringValue = Self.unsureNote
        }
    }

    // MARK: - Rows

    @objc private func tickChanged(_ sender: Any?) {
        rebuildRows()
        onChange()
    }

    @objc private func faceChanged(_ sender: Any?) {
        onChange()
    }

    /// One Faces row per ticked microphone, each on "Choose a face" until the next `offer`.
    private func rebuildRows() {
        for row in facesColumn.arrangedSubviews {
            facesColumn.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        popups = []
        faces = []
        offeredFor = nil
        note.stringValue = ""
        for (microphone, box) in zip(microphones, boxes) where box.state == .on {
            let name = NSTextField(labelWithString: microphone.name)
            name.font = DS.sans(13)
            name.textColor = DS.textStrong
            name.widthAnchor.constraint(equalToConstant: 96).isActive = true
            name.lineBreakMode = .byTruncatingTail
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.font = DS.sans(13)
            popup.target = self
            popup.action = #selector(faceChanged(_:))
            popup.setAccessibilityIdentifier("vertical.face.\(microphone.track)")
            fill(popup)
            popups.append(popup)
            facesColumn.addArrangedSubview(sheetRow([name, popup]))
        }
    }

    /// "Choose a face", then "Face N (X % across)" per face found, on "Choose a face".
    private func fill(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        popup.addItem(withTitle: Self.chooseTitle)
        for face in faces {
            popup.addItem(withTitle: "Face \(face.face) (\(Int((face.x * 100).rounded())) % across)")
        }
        popup.selectItem(at: 0)
    }
}
