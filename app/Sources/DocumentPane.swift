import AppKit

/// The Document tab (spec §4.3): what the document is, then canvas size,
/// frame rate, background, the timecode format, "fit new clips", and the
/// markers list.
///
/// Nothing here is a clip property, so nothing here goes through
/// `InspectorBinding.ops` — every row is one `set_canvas` or one marker op,
/// applied through the same `applyEdit` seam.
final class DocumentPane: InspectorPaneView {
    /// Whether a size change rescales the clips with it (§6's
    /// `rescale_clips`). A UI preference, not a project value, so it lives in
    /// `UserDefaults` and rides along with the next size edit.
    static let rescaleClipsKey = "FrameJobInspectorRescaleClips"

    /// **This whole pane reads `binding.documentSnapshot` / `documentCanvas`
    /// / `documentProject` and never `binding.snapshot`** (road map 2's phase
    /// 9). The Clip tab follows the nest scope, because the clip it is
    /// showing is inside one; this tab is about the FILE — its canvas, its
    /// markers, its media count, what its background lets an export carry —
    /// and every one of those is the document's whatever container the
    /// timeline happens to be showing. `set_canvas` and the two marker ops it
    /// writes are document-level (`ReelOp.isDocumentLevel`), so they are sent
    /// unscoped and go on working with a nest open; reading a scoped snapshot
    /// here would mean answering about one project and editing another — and
    /// visibly so, since a scoped view has NO markers and the nest's frozen
    /// size for a canvas.
    override var tab: InspectorTab { .document }

    /// The Document tab always has something to show.
    override var emptyMessage: String? { nil }

    /// The markers list is a table, so its rows are part of the shape.
    override var structureSignature: String {
        let markers = binding.documentSnapshot.markers.map { String($0.id) }.joined(separator: ".")
        return "doc|\(binding.documentSnapshot.media.count)|\(markers)"
    }

    override func makeSections() -> [InspectorSection] {
        [summarySection(), canvasSection(), rateSection(), appearanceSection(), markersSection()]
    }

    // MARK: Summary

    /// The label column of the summary rows. Deliberately NOT
    /// `InspectorMetrics.labelWidth` (76): these labels are whole words
    /// ("Resolution", "Frame rate", "Background") where the clip panes' are
    /// single properties, and widening the shared metric would re-flow every
    /// row in every other pane to fix five rows here.
    private static let summaryLabelWidth: CGFloat = 86

    /// What the document IS, read-only, before the controls that change it
    /// (handoff README, Part 2 §5). The tab used to open on a size popup,
    /// which answers "what can I set" before "what am I looking at".
    ///
    /// The design lists a sixth row, Colour. `CanvasSnapshot` (spec §5.2)
    /// carries no colour space — a canvas is a size, a rate, a background and
    /// a timecode format, and the whole pipeline is sRGB — so the row is left
    /// out rather than filled with a value the model does not hold.
    private func summarySection() -> InspectorSection {
        let binding = self.binding
        return InspectorSection(
            id: "doc.summary", title: "Document",
            rows: [
                summaryRow("Resolution") {
                    "\(binding.documentCanvas.width) × \(binding.documentCanvas.height)"
                },
                summaryRow("Frame rate") { "\(binding.documentCanvas.fps.displayName) fps" },
                summaryRow("Duration") {
                    ReelTime.format(
                        binding.documentSnapshot.duration, fps: binding.documentCanvas.fps,
                        frames: binding.documentCanvas.timecodeFrames)
                },
                summaryRow("Tracks") { String(binding.documentSnapshot.tracks.count) },
                summaryRow("Background") {
                    DocumentPane.colorName(binding.documentCanvas.background)
                },
            ])
    }

    /// One read-out on the 86 pt column. `inspectorRow` would be the natural
    /// builder, but its label column is `InspectorMetrics`' shared width and
    /// takes no override, so the row is assembled here.
    ///
    /// The value is an `inspectorReadout` — an `OptionControl` — because none
    /// of these five is in `structureSignature`: adding a track or moving the
    /// last clip changes what the row says without rebuilding the pane, and a
    /// plain label would go stale where a control is refreshed.
    private func summaryRow(_ label: String, _ read: @escaping () -> String) -> NSView {
        let field = InspectorRowLabel(label)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(
            equalToConstant: DocumentPane.summaryLabelWidth).isActive = true
        let trailing = NSView()
        trailing.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        trailing.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [field, inspectorReadout(width: 150, read), trailing])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    /// The background as a word when it is one of the two the eye names, and
    /// as a hex triplet otherwise — a read-out, so it is spelled the way a
    /// machine-produced number is. Alpha is reported separately because a
    /// transparent canvas is a fact about the EXPORT, not about the colour.
    private static func colorName(_ rgba: RGBA) -> String {
        let color = rgba.nsColor
        let alpha = color.alphaComponent
        guard alpha > 0.005 else { return "Transparent" }
        func byte(_ value: CGFloat) -> Int { Int((value * 255).rounded()) }
        let r = byte(color.redComponent)
        let g = byte(color.greenComponent)
        let b = byte(color.blueComponent)
        let name: String
        switch (r, g, b) {
        case (0, 0, 0): name = "Black"
        case (255, 255, 255): name = "White"
        default: name = String(format: "#%02X%02X%02X", r, g, b)
        }
        guard alpha < 0.995 else { return name }
        return "\(name) · \(Int((alpha * 100).rounded()))%"
    }

    // MARK: Canvas size

    /// The source size offered as a preset: the first media entry with real
    /// pixels (§4.3's "source size").
    private var sourceSize: (width: Int, height: Int)? {
        guard let media = binding.documentSnapshot.media.first(where: { $0.width > 0 && $0.height > 0 })
        else { return nil }
        return (media.width, media.height)
    }

    private func canvasSection() -> InspectorSection {
        let binding = self.binding
        let presets = CanvasPreset.all
        var items = presets.map { $0.name }
        items.append("Source Size")
        items.append("Custom")
        let sourceIndex = presets.count

        // Reads the flag inside the closure rather than through a property:
        // an `ops` closure outlives this call, and capturing `self` here would
        // be a retain cycle through the section it ends up in.
        func sizeOps(width: Int, height: Int) -> [ReelOp] {
            [
                .setCanvas(
                    width: width, height: height,
                    rescaleClips: UserDefaults.standard.bool(
                        forKey: DocumentPane.rescaleClipsKey))
            ]
        }

        let popup = OptionPopupControl(
            width: 168, items: items,
            read: { [weak self] in
                let canvas = binding.documentCanvas
                if let index = presets.firstIndex(where: {
                    $0.width == canvas.width && $0.height == canvas.height
                }) {
                    return index
                }
                if let source = self?.sourceSize, source.width == canvas.width,
                   source.height == canvas.height
                {
                    return sourceIndex
                }
                return items.count - 1
            },
            write: { [weak self] index in
                guard let self = self else { return }
                if presets.indices.contains(index) {
                    binding.apply(
                        "Canvas Size",
                        sizeOps(width: presets[index].width, height: presets[index].height))
                } else if index == sourceIndex, let source = self.sourceSize {
                    binding.apply(
                        "Canvas Size", sizeOps(width: source.width, height: source.height))
                } else {
                    // "Custom" is what the popup SHOWS for a size no preset
                    // matches; picking it changes nothing — the two fields
                    // below are where a custom size is typed.
                    NSSound.beep()
                }
            },
            enabled: { true },
            onEdit: { binding.edited() })

        return InspectorSection(
            id: "doc.canvas", title: "Canvas",
            rows: [
                inspectorRow("Preset", [popup]),
                inspectorValueRow(
                    "Width", binding, name: "Canvas Size", unit: " px", decimals: 0, min: 16,
                    max: 16384, slider: false, width: InspectorMetrics.wideFieldWidth,
                    read: { Double(binding.documentCanvas.width) },
                    ops: { value in
                        sizeOps(width: Int(value.rounded()), height: binding.documentCanvas.height)
                    }, resets: false),
                inspectorValueRow(
                    "Height", binding, name: "Canvas Size", unit: " px", decimals: 0, min: 16,
                    max: 16384, slider: false, width: InspectorMetrics.wideFieldWidth,
                    read: { Double(binding.documentCanvas.height) },
                    ops: { value in
                        sizeOps(width: binding.documentCanvas.width, height: Int(value.rounded()))
                    }, resets: false),
                inspectorRow(
                    nil,
                    [
                        OptionCheckboxControl(
                            label: "Resize clips proportionally",
                            read: {
                                UserDefaults.standard.bool(forKey: DocumentPane.rescaleClipsKey)
                            },
                            write: { value in
                                UserDefaults.standard.set(
                                    value, forKey: DocumentPane.rescaleClipsKey)
                            },
                            enabled: { true },
                            onEdit: { binding.edited() })
                    ]),
            ])
    }

    // MARK: Frame rate

    /// Changing the rate re-snaps every clip start and duration (§6), so this
    /// is one op and one undo step like any other edit.
    private func rateSection() -> InspectorSection {
        let binding = self.binding
        let rates = Fps.common
        let items = rates.map { $0.displayName } + ["Match First Clip"]
        let popup = OptionPopupControl(
            width: 168, items: items,
            read: {
                let fps = binding.documentCanvas.fps
                return rates.firstIndex { $0.num == fps.num && $0.den == fps.den } ?? 0
            },
            write: { [weak self] index in
                if rates.indices.contains(index) {
                    binding.apply("Frame Rate", [.setCanvas(fps: rates[index])])
                } else if let fps = self?.firstClipRate() {
                    binding.apply("Frame Rate", [.setCanvas(fps: fps)])
                } else {
                    NSSound.beep()
                }
            },
            enabled: { true },
            onEdit: { binding.edited() })
        return InspectorSection(
            id: "doc.rate", title: "Frame Rate",
            rows: [
                inspectorRow("Rate", [popup]),
                inspectorRow(
                    "Duration",
                    [
                        inspectorReadout {
                            ReelTime.format(
                                binding.documentSnapshot.duration, fps: binding.documentCanvas.fps,
                                frames: binding.documentCanvas.timecodeFrames)
                        }
                    ]),
            ])
    }

    /// The rate of the earliest clip's media — "match first clip" (§4.3).
    private func firstClipRate() -> Fps? {
        let snapshot = binding.documentSnapshot
        let clips = snapshot.clips.sorted { $0.start < $1.start }
        for clip in clips {
            guard let media = snapshot.media(for: clip), media.hasVideo, media.fps.double > 0
            else { continue }
            return media.fps
        }
        return nil
    }

    // MARK: Appearance

    /// The memo `alphaFormats` fills. Never holds an empty list — see there.
    private static var alphaFormatCache: [String]?

    /// The export rows that carry an alpha channel, by the CORE's own display
    /// name, memoized for the process once there is an answer worth keeping.
    ///
    /// The names are read rather than spelled, so a row renamed in
    /// `export_table.rs` renames itself in the note below. Memoizing is sound
    /// and not a shortcut: `ExportSettings.alpha` is a capability of the ROW
    /// and never a statement about the project (`ReelCore.swift` argues it at
    /// length), so one project's answer is every project's — which is exactly
    /// why the note can be built once at section time instead of asking the
    /// FFI on every inspector refresh.
    ///
    /// **An EMPTY answer is never memoized, and that is not tidiness.** The
    /// flag is per-ROW but the only way to ASK for it is a per-PROJECT call,
    /// and that call can fail: `export_settings` refuses a project whose
    /// duration is zero ("export range is empty"), so on a document nobody has
    /// put a clip in yet every row throws and the filter answers nothing.
    /// Caching that would pin `[]` for the life of the process, and the note
    /// would go on naming no row however much footage arrived afterwards — a
    /// whole session's worth of a discoverability line saying nothing, bought
    /// by one glance at the Document tab of an empty project. Re-asking costs
    /// ten FFI calls per section build, and only in the state where the
    /// answer is useless.
    ///
    /// Internal, not private, as `transparencyNote` is, so a probe can call
    /// them; no script does today. A render cannot read TEXT, so the note's
    /// words are checked where they can be read: `hevc_alpha_proof.py`'s row
    /// N1 takes them off the live Document tab's layout dump, and
    /// `phase7_chrome.py` section 5 photographs the note's row.
    static func alphaFormats(_ project: ReelProject?) -> [String] {
        if let cached = alphaFormatCache, !cached.isEmpty { return cached }
        guard let project = project else { return [] }
        let names = ReelExport.presets()
            .filter { (try? ReelExport.settings(project, preset: $0.id))?.alpha == true }
            .map { $0.name }
        if !names.isEmpty { alphaFormatCache = names }
        return names
    }

    /// The note the Appearance section shows while the canvas background is
    /// translucent, and nothing at all while it is opaque.
    ///
    /// **This is a discoverability line, not plumbing.** A transparent canvas
    /// has been reachable since M1 — `NSColorPanel.shared.showsAlpha` is set
    /// app-wide, the swatch draws a checkerboard behind the colour, and the
    /// Document summary above already reads "Transparent". What was missing is
    /// the consequence: alpha is a property of the FILE FORMAT, so a canvas
    /// somebody deliberately made transparent comes back opaque from most
    /// exports, and there was nowhere in the app that said so before the file
    /// existed. So the note appears exactly when the fact starts to matter and
    /// names every row that keeps it.
    ///
    /// **Every claim here is POSITIVE — the rows that KEEP the alpha, named,
    /// never the ones that flatten it.** That is the rule the export sheet's
    /// footnote follows one file over (`ExportSheetResolve.swift` appends
    /// "alpha" for a row that carries it and says nothing for one that does
    /// not), and it is what lets the line survive a table that grows: a new
    /// row joins the list or is silent, where an enumeration of the rows that
    /// flatten would be wrong the moment the core added one.
    ///
    /// **It names them while the names fit, and counts them when they do
    /// not** (spec §11 G-33 (a)). One or two rows are named, joined by a
    /// comma; three or more are counted — "kept by 3 export formats." — and
    /// the count is the list's own, so a fourth row changes the number and
    /// nothing here. With no row to name (a document with no duration answers
    /// none) it says the class of format instead.
    ///
    /// Short on purpose, and the arithmetic is what decided the wording.
    /// `InspectorNoteLabel` truncates rather than wraps; its row is 268 pt in
    /// the default 304 pt pane (`DS.panelWidth` less the scroller and two
    /// insets) and **244 pt at the 280 pt narrowest a person can drag the
    /// inspector to**, which is the width that has to be met. In
    /// `DS.sans(11)` — Source Sans 3, the BUNDLED face — two names are 229 pt
    /// and fit, and three run to about 295 pt and do not, which is why the
    /// third row turned the list into a count.
    static func transparencyNote(_ background: RGBA, formats: [String]) -> String? {
        guard background.nsColor.alphaComponent < 0.995 else { return nil }
        // Nothing to name is a real state rather than a bug — `alphaFormats`
        // asks a per-ROW question through a per-PROJECT call, and a document
        // with no duration answers nothing — so the class of format is still
        // worth saying, and it is still said positively.
        guard !formats.isEmpty else { return "Transparent — needs an alpha format." }
        guard formats.count < 3 else {
            return "Transparent — kept by \(formats.count) export formats."
        }
        return "Transparent — " + formats.joined(separator: ", ") + "."
    }

    private func appearanceSection() -> InspectorSection {
        let binding = self.binding
        let alphaFormats = DocumentPane.alphaFormats(binding.documentProject)
        return InspectorSection(
            id: "doc.appearance", title: "Appearance",
            note: {
                DocumentPane.transparencyNote(binding.documentCanvas.background, formats: alphaFormats)
            },
            reset: {
                binding.apply(
                    "Appearance",
                    [
                        .setCanvas(
                            background: [0, 0, 0, 1], fitNewClips: true, timecodeFrames: true)
                    ])
            },
            differs: {
                let canvas = binding.documentCanvas
                return canvas.background != [0, 0, 0, 1] || !canvas.fitNewClips
                    || !canvas.timecodeFrames
            },
            rows: [
                inspectorColorRow(
                    "Background", binding, name: "Background",
                    read: { binding.documentCanvas.background },
                    ops: { [.setCanvas(background: $0)] }, resets: false),
                inspectorPopupRow(
                    "Timecode", binding, name: "Timecode Format",
                    items: ["Frames", "Milliseconds"], width: 132,
                    read: { binding.documentCanvas.timecodeFrames ? 0 : 1 },
                    ops: { [.setCanvas(timecodeFrames: $0 == 0)] }, resets: false),
                inspectorCheckRow(
                    "Fit new clips to canvas", binding, name: "Fit New Clips",
                    read: { binding.documentCanvas.fitNewClips },
                    ops: { [.setCanvas(fitNewClips: $0)] }, resets: false),
            ])
    }

    // MARK: Markers

    private func markersSection() -> InspectorSection {
        var rows: [NSView] = []
        let markers = binding.documentSnapshot.markers.sorted { $0.time < $1.time }
        for marker in markers {
            rows.append(markerRow(marker.id))
            rows.append(markerActionRow(marker.id))
        }
        if markers.isEmpty {
            rows.append(inspectorRow(nil, [InspectorRowLabel("No markers. Press M to add one.")]))
        }
        return InspectorSection(id: "doc.markers", title: "Markers", rows: rows)
    }

    /// Rows bind by marker id and read fresh: a marker dragged on the ruler
    /// moves under the panel, and only the value changed — no rebuild.
    private func markerRow(_ id: UInt32) -> NSView {
        let binding = self.binding
        func marker() -> MarkerSnapshot? { binding.documentSnapshot.marker(id) }
        let time = inspectorReadout(width: 78) {
            guard let marker = marker() else { return "—" }
            return ReelTime.format(
                marker.time, fps: binding.documentCanvas.fps, frames: binding.documentCanvas.timecodeFrames)
        }
        let name = InspectorNameField(
            read: { marker()?.name ?? "" },
            write: { value in
                binding.apply("Rename Marker", [.setMarker(marker: id, name: value)])
            },
            enabled: { true },
            onEdit: { binding.edited() })
        name.placeholderString = "Marker"
        name.translatesAutoresizingMaskIntoConstraints = false
        name.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        return inspectorRow(nil, [time, name])
    }

    private func markerActionRow(_ id: UInt32) -> NSView {
        let binding = self.binding
        func marker() -> MarkerSnapshot? { binding.documentSnapshot.marker(id) }
        let chapter = OptionCheckboxControl(
            label: "Chapter",
            read: { marker()?.chapter ?? false },
            write: { value in
                binding.apply("Chapter Marker", [.setMarker(marker: id, chapter: value)])
            },
            enabled: { true },
            onEdit: { binding.edited() })
        // **Go is the one control in this row that carries a TIME, and so the
        // one disabled inside a nest** (road map 2's phase 9). A marker's
        // `time` is PROJECT time; `onSeek` writes `document.playhead`, which
        // with a nest open is measured from the NEST's zero — so the button
        // would move the playhead to a nest-local tick numerically equal to a
        // project one, i.e. an unrelated frame, silently. Chapter, Delete and
        // the name field beside it read no clock and stay live, which is the
        // same split the MCP side makes (`AgentServer+Scope.swift` refuses
        // `add_marker` and `set_marker`'s TIME while letting the rest through)
        // and the same one `validateNestScopeAction` makes in the Clip menu.
        // Leaving the nest is the way to use it; the tooltip says so.
        let scoped = { binding.document?.scope != nil }
        let jump = OptionButtonControl(
            title: "Go",
            action: { [weak self] in
                guard !scoped(), let time = marker()?.time else { return }
                self?.inspector?.onSeek?(time)
            },
            enabled: { !scoped() }, onEdit: {})
        jump.toolTip =
            scoped()
            ? "A marker is at project time, and the playhead inside a nest is not — "
                + "leave the nest (⌘↑) to jump to it"
            : "Move the playhead to this marker"
        let remove = OptionButtonControl(
            title: "Delete",
            action: { binding.apply("Remove Marker", [.removeMarker(marker: id)]) },
            enabled: { true }, onEdit: {})
        return inspectorRow(nil, [chapter, jump, remove])
    }
}

// MARK: - Canvas presets

/// The canvas sizes of §4.3, in the order the popup lists them.
struct CanvasPreset {
    let name: String
    let width: Int
    let height: Int

    static let all: [CanvasPreset] = [
        CanvasPreset(name: "1080p · 1920 × 1080", width: 1920, height: 1080),
        CanvasPreset(name: "4K · 3840 × 2160", width: 3840, height: 2160),
        CanvasPreset(name: "720p · 1280 × 720", width: 1280, height: 720),
        CanvasPreset(name: "Vertical · 1080 × 1920", width: 1080, height: 1920),
        CanvasPreset(name: "Square · 1080 × 1080", width: 1080, height: 1080),
        CanvasPreset(name: "1440p · 2560 × 1440", width: 2560, height: 1440),
    ]
}
