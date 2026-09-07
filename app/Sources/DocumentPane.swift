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
    static let rescaleClipsKey = "ReelcutInspectorRescaleClips"

    override var tab: InspectorTab { .document }

    /// The Document tab always has something to show.
    override var emptyMessage: String? { nil }

    /// The markers list is a table, so its rows are part of the shape.
    override var structureSignature: String {
        let markers = binding.snapshot.markers.map { String($0.id) }.joined(separator: ".")
        return "doc|\(binding.snapshot.media.count)|\(markers)"
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
                    "\(binding.canvas.width) × \(binding.canvas.height)"
                },
                summaryRow("Frame rate") { "\(binding.canvas.fps.displayName) fps" },
                summaryRow("Duration") {
                    ReelTime.format(
                        binding.snapshot.duration, fps: binding.canvas.fps,
                        frames: binding.canvas.timecodeFrames)
                },
                summaryRow("Tracks") { String(binding.snapshot.tracks.count) },
                summaryRow("Background") {
                    DocumentPane.colorName(binding.canvas.background)
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
        guard let media = binding.snapshot.media.first(where: { $0.width > 0 && $0.height > 0 })
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
                let canvas = binding.canvas
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
                    read: { Double(binding.canvas.width) },
                    ops: { value in
                        sizeOps(width: Int(value.rounded()), height: binding.canvas.height)
                    }),
                inspectorValueRow(
                    "Height", binding, name: "Canvas Size", unit: " px", decimals: 0, min: 16,
                    max: 16384, slider: false, width: InspectorMetrics.wideFieldWidth,
                    read: { Double(binding.canvas.height) },
                    ops: { value in
                        sizeOps(width: binding.canvas.width, height: Int(value.rounded()))
                    }),
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
                let fps = binding.canvas.fps
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
                                binding.snapshot.duration, fps: binding.canvas.fps,
                                frames: binding.canvas.timecodeFrames)
                        }
                    ]),
            ])
    }

    /// The rate of the earliest clip's media — "match first clip" (§4.3).
    private func firstClipRate() -> Fps? {
        let snapshot = binding.snapshot
        let clips = snapshot.clips.sorted { $0.start < $1.start }
        for clip in clips {
            guard let media = snapshot.media(for: clip), media.hasVideo, media.fps.double > 0
            else { continue }
            return media.fps
        }
        return nil
    }

    // MARK: Appearance

    private func appearanceSection() -> InspectorSection {
        let binding = self.binding
        return InspectorSection(
            id: "doc.appearance", title: "Appearance",
            reset: {
                binding.apply(
                    "Appearance",
                    [
                        .setCanvas(
                            background: [0, 0, 0, 1], fitNewClips: true, timecodeFrames: true)
                    ])
            },
            rows: [
                inspectorColorRow(
                    "Background", binding, name: "Background",
                    read: { binding.canvas.background },
                    ops: { [.setCanvas(background: $0)] }),
                inspectorPopupRow(
                    "Timecode", binding, name: "Timecode Format",
                    items: ["Frames", "Milliseconds"], width: 132,
                    read: { binding.canvas.timecodeFrames ? 0 : 1 },
                    ops: { [.setCanvas(timecodeFrames: $0 == 0)] }),
                inspectorCheckRow(
                    "Fit new clips to canvas", binding, name: "Fit New Clips",
                    read: { binding.canvas.fitNewClips },
                    ops: { [.setCanvas(fitNewClips: $0)] }),
            ])
    }

    // MARK: Markers

    private func markersSection() -> InspectorSection {
        var rows: [NSView] = []
        let markers = binding.snapshot.markers.sorted { $0.time < $1.time }
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
        func marker() -> MarkerSnapshot? { binding.snapshot.marker(id) }
        let time = inspectorReadout(width: 78) {
            guard let marker = marker() else { return "—" }
            return ReelTime.format(
                marker.time, fps: binding.canvas.fps, frames: binding.canvas.timecodeFrames)
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
        func marker() -> MarkerSnapshot? { binding.snapshot.marker(id) }
        let chapter = OptionCheckboxControl(
            label: "Chapter",
            read: { marker()?.chapter ?? false },
            write: { value in
                binding.apply("Chapter Marker", [.setMarker(marker: id, chapter: value)])
            },
            enabled: { true },
            onEdit: { binding.edited() })
        let jump = OptionButtonControl(
            title: "Go",
            action: { [weak self] in
                guard let time = marker()?.time else { return }
                self?.inspector?.onSeek?(time)
            },
            enabled: { true }, onEdit: {})
        jump.toolTip = "Move the playhead to this marker"
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
