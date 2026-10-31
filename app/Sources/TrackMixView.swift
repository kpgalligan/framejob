import AppKit

/// The Volume row's scale (spec §11 AU-105): the track's linear fader as
/// decibels, −60…+12 on the rail and in the field. The floor is Off — it reads
/// for every volume at or under it and writes 0 — and its readout says "Off".
enum TrackMixLevel {
    static let floorDB = -60.0
    static let ceilingDB = 12.0

    /// The fader's decibels, never under the floor. A volume above the rail's
    /// top (4 is +12.04 dB, `set_track`'s ceiling) reads as itself: the rail
    /// pins its knob at the end, as the clip Volume row's does.
    static func decibels(_ volume: Double) -> Double {
        guard volume.isFinite, volume > 0 else { return floorDB }
        return max(20 * log10(volume), floorDB)
    }

    /// The linear volume for `decibels`: 0 at or under the floor, and never
    /// past the rail's top.
    static func volume(_ decibels: Double) -> Double {
        guard decibels.isFinite, decibels > floorDB else { return 0 }
        return pow(10, min(decibels, ceilingDB) / 20)
    }

    /// The row's readout: "Off" at 0, else the gain as a percentage.
    static func readout(_ volume: Double) -> String {
        guard volume.isFinite, volume > 0 else { return "Off" }
        return String(format: "%.0f %%", volume * 100)
    }
}

/// How the popover edits: the timeline's own live trio for a drag, and its
/// one-shot edit for a field commit and Reset, so a drag is one undo step.
struct TrackMixEdits {
    let liveBegin: () -> Void
    let liveUpdate: ([ReelOp]) -> Void
    let liveEnd: (String) -> Void
    let edit: (String, [ReelOp]) -> Void
}

/// The track mix popover's content (spec §11 AU-105): Volume in dB (a slider
/// and a field with quick picks, and the readout), Pan −100…100 (a slider and
/// a field), and Reset. It reads the track it was last handed (`update`),
/// and a value being dragged until the drag ends.
final class TrackMixViewController: NSViewController {
    private(set) var track: TrackSnapshot
    private let edits: TrackMixEdits
    /// The value a drag has reached, read in place of the track's own until
    /// the drag ends and the document has answered.
    private var liveVolume: Double?
    private var livePan: Double?
    private var dragging = false
    /// What a field's `write` handed over, committed by its `onEdit`.
    private var typedVolume: Double?
    private var typedPan: Double?
    private var controls: [OptionControl] = []
    private var resetButton: StickerButton?
    private let titleLabel = NSTextField(labelWithString: "")

    static let volumeQuick: [Double] = [-12, -6, -3, 0, 3, 6]
    static let panQuick: [Double] = [-100, -50, 0, 50, 100]

    init(track: TrackSnapshot, edits: TrackMixEdits) {
        self.track = track
        self.edits = edits
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TrackMixViewController does not support NSCoder")
    }

    private var volume: Double { liveVolume ?? track.volume }
    private var pan: Double { livePan ?? track.pan }

    override func loadView() {
        titleLabel.font = DS.sans(11, weight: .semibold)
        titleLabel.textColor = DS.textStrong
        let volumeRow = row(
            "Volume",
            InspectorSliderControl(
                min: TrackMixLevel.floorDB, max: TrackMixLevel.ceilingDB,
                read: { [weak self] in TrackMixLevel.decibels(self?.volume ?? 1) },
                write: { [weak self] db in self?.drag(volume: TrackMixLevel.volume(db)) },
                begin: { [weak self] in self?.beginDrag() },
                end: { [weak self] in self?.endDrag("Track Volume") },
                enabled: { true }, start: { nil }, now: { nil }),
            OptionFieldControl(
                width: InspectorMetrics.fieldWidth, unit: " dB", decimals: 1,
                min: TrackMixLevel.floorDB, max: TrackMixLevel.ceilingDB,
                quick: Self.volumeQuick,
                read: { [weak self] in TrackMixLevel.decibels(self?.volume ?? 1) },
                write: { [weak self] db in self?.typedVolume = TrackMixLevel.volume(db) },
                enabled: { true },
                onEdit: { [weak self] in self?.commitVolume() }),
            OptionDisplayControl(
                width: 44, read: { [weak self] in TrackMixLevel.readout(self?.volume ?? 1) },
                enabled: { true }))
        let panRow = row(
            "Pan",
            InspectorSliderControl(
                min: -100, max: 100, read: { [weak self] in (self?.pan ?? 0) * 100 },
                write: { [weak self] value in self?.drag(pan: value / 100) },
                begin: { [weak self] in self?.beginDrag() },
                end: { [weak self] in self?.endDrag("Track Pan") },
                enabled: { true }, start: { nil }, now: { nil }),
            OptionFieldControl(
                width: InspectorMetrics.fieldWidth, unit: "", decimals: 0, min: -100, max: 100,
                quick: Self.panQuick,
                read: { [weak self] in (self?.pan ?? 0) * 100 },
                write: { [weak self] value in self?.typedPan = value / 100 },
                enabled: { true },
                onEdit: { [weak self] in self?.commitPan() }),
            nil)
        let reset = StickerButton(
            title: "Reset", style: .secondary, target: self, action: #selector(resetMix(_:)))
        resetButton = reset
        let footer = NSStackView(views: [NSView(), reset])
        footer.orientation = .horizontal
        let stack = NSStackView(views: [titleLabel, volumeRow, panRow, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = InspectorMetrics.rowSpacing
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        for view in [volumeRow, panRow, footer] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }
        stack.widthAnchor.constraint(equalToConstant: 340).isActive = true
        view = stack
        refresh()
    }

    /// One labelled row: the slider takes the width the fixed controls leave.
    private func row(
        _ label: String, _ slider: InspectorSliderControl, _ field: OptionFieldControl,
        _ readout: OptionDisplayControl?
    ) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.font = DS.sans(11)
        title.textColor = DS.textMuted
        title.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let views: [NSView] = [title, slider, field] + (readout.map { [$0] } ?? [])
        controls += [slider, field] + (readout.map { [$0] } ?? [])
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 6
        row.setHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    /// The track the popover now shows, after any change to its document. A
    /// drag in flight keeps its own value.
    func update(_ track: TrackSnapshot) {
        self.track = track
        if !dragging {
            liveVolume = nil
            livePan = nil
        }
        refresh()
    }

    private func refresh() {
        titleLabel.stringValue = track.name.isEmpty ? "Track" : track.name
        controls.forEach { $0.refresh() }
        resetButton?.isEnabled = volume != 1 || pan != 0
    }

    // MARK: Edits

    private func beginDrag() {
        dragging = true
        edits.liveBegin()
    }

    private func drag(volume: Double) {
        liveVolume = volume
        edits.liveUpdate([.setTrack(track: track.id, volume: volume)])
        refresh()
    }

    private func drag(pan: Double) {
        livePan = pan
        edits.liveUpdate([.setTrack(track: track.id, pan: pan)])
        refresh()
    }

    private func endDrag(_ name: String) {
        dragging = false
        edits.liveEnd(name)
    }

    private func commitVolume() {
        guard let value = typedVolume else { return }
        typedVolume = nil
        edits.edit("Track Volume", [.setTrack(track: track.id, volume: value)])
    }

    private func commitPan() {
        guard let value = typedPan else { return }
        typedPan = nil
        edits.edit("Track Pan", [.setTrack(track: track.id, pan: value)])
    }

    @objc private func resetMix(_ sender: Any?) {
        edits.edit("Reset Track Mix", [.setTrack(track: track.id, volume: 1, pan: 0)])
    }
}
