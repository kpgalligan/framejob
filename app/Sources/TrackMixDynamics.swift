import AppKit

/// The track mix popover's Compressor and Limiter (spec §11 AU-155): under
/// Pan, a "Compressor" checkbox with Threshold, Ratio, Attack, Release and
/// Makeup, and a "Limit peaks" checkbox with Ceiling and Release, in the clip
/// sections' units, ranges and quick picks (`AudioPane.swift`,
/// `AudioPane+Limiter.swift`). Every control writes the WHOLE object through
/// `set_track` (AU-150: an object replaces the value); a drag or a commit is
/// one undo step, "Track Compressor" or "Track Limiter". Inside an open nest
/// both sections are disabled — a nest's tracks have no dynamics, the track
/// holding the nest clip is its bus — and say so in a tooltip.
///
/// Owned by `TrackMixViewController`, which lays the rows out and hands each
/// change of its track on (`update`); the MCP mirror is `set_track
/// {compressor, limiter}` (`AgentServer+Tracks.swift`).
final class TrackMixDynamics {
    private var track: TrackSnapshot
    private let edits: TrackMixEdits
    private let inNest: Bool
    /// What a drag has reached, read in place of the track's own until the
    /// drag ends and the document has answered.
    private var liveCompressor: CompressorProps?
    private var liveLimiter: LimiterProps?
    private var dragging = false
    /// What a field's `write` handed over, committed by its `onEdit`.
    private var typedCompressor: CompressorProps?
    private var typedLimiter: LimiterProps?
    private(set) var controls: [OptionControl] = []
    /// The controller's refresh, run after a drag step.
    var changed: () -> Void = {}

    static let nestTooltip = "A nest's mix plays through the dynamics of the track that holds it."
    static let compressorName = "Track Compressor"
    static let limiterName = "Track Limiter"

    init(track: TrackSnapshot, edits: TrackMixEdits, inNest: Bool) {
        self.track = track
        self.edits = edits
        self.inNest = inNest
    }

    /// The compressor and limiter the rows show: a drag's, else the track's.
    var compressor: CompressorProps? { liveCompressor ?? track.compressor }
    var limiter: LimiterProps? { liveLimiter ?? track.limiter }

    /// The track the popover now shows; a drag in flight keeps its own value.
    func update(_ track: TrackSnapshot) {
        self.track = track
        if !dragging {
            liveCompressor = nil
            liveLimiter = nil
        }
    }

    func refresh() { controls.forEach { $0.refresh() } }

    // MARK: Rows

    /// The two sections' rows, each made by `row` (the popover's own layout)
    /// from a label and its controls; a checkbox row has no label.
    func makeRows(_ row: (String?, [NSView & OptionControl]) -> NSView) -> [NSView] {
        let compressorOn = { [weak self] in self?.compressor != nil }
        let limiterOn = { [weak self] in self?.limiter != nil }
        let compressorRows: [NSView] = [
            row(nil, [check("Compressor", on: compressorOn) { [weak self] value in
                self?.write(compressor: value ? CompressorProps() : nil)
            }]),
            value(
                "Threshold", row, unit: " dB", decimals: 1, min: -60, max: 0,
                quick: [-30, -24, -18, -12, -6], on: compressorOn,
                read: { $0.thresholdDb }, set: { $0.thresholdDb = $1 }),
            value(
                "Ratio", row, unit: ":1", decimals: 1, min: 1, max: 20,
                quick: [1.5, 2, 3, 4, 8, 20], on: compressorOn,
                read: { $0.ratio }, set: { $0.ratio = $1 }),
            value(
                "Attack", row, unit: " ms", decimals: 0, min: 0, max: 200,
                quick: [1, 5, 10, 30, 100], on: compressorOn,
                read: { Self.milliseconds($0.attack) }, set: { $0.attack = Self.ticks($1) }),
            value(
                "Release", row, unit: " ms", decimals: 0, min: 10, max: 2000,
                quick: [50, 100, 200, 500, 1000], on: compressorOn,
                read: { Self.milliseconds($0.release) }, set: { $0.release = Self.ticks($1) }),
            value(
                "Makeup", row, unit: " dB", decimals: 1, min: 0, max: 24,
                quick: [0, 3, 6, 12], on: compressorOn,
                read: { $0.makeupDb }, set: { $0.makeupDb = $1 }),
        ]
        let limiterRows: [NSView] = [
            row(nil, [check("Limit peaks", on: limiterOn) { [weak self] value in
                self?.write(limiter: value ? LimiterProps() : nil)
            }]),
            limit(
                "Ceiling", row, unit: " dBTP", decimals: 1, min: -24, max: 0,
                quick: [-1, -2, -3, -6], on: limiterOn,
                read: { $0.ceilingDb }, set: { $0.ceilingDb = $1 }),
            limit(
                "Release", row, unit: " ms", decimals: 0, min: 1, max: 1000,
                quick: [50, 100, 200, 500], on: limiterOn,
                read: { Self.milliseconds($0.release) }, set: { $0.release = Self.ticks($1) }),
        ]
        let rows = compressorRows + limiterRows
        if inNest { rows.forEach { $0.toolTip = Self.nestTooltip } }
        return rows
    }

    private func check(
        _ label: String, on: @escaping () -> Bool, write: @escaping (Bool) -> Void
    ) -> NSView & OptionControl {
        let control = OptionCheckboxControl(
            label: label, read: on, write: write, enabled: { [weak self] in self?.inNest == false },
            onEdit: {})
        controls.append(control)
        return control
    }

    /// One compressor value row: a slider (a live drag) and a field (a commit).
    private func value(
        _ label: String, _ row: (String?, [NSView & OptionControl]) -> NSView, unit: String,
        decimals: Int, min: Double, max: Double, quick: [Double], on: @escaping () -> Bool,
        read: @escaping (CompressorProps) -> Double,
        set: @escaping (inout CompressorProps, Double) -> Void
    ) -> NSView {
        let current = { [weak self] in self?.compressor ?? CompressorProps() }
        let next = { (value: Double) -> CompressorProps in
            var c = current()
            set(&c, value)
            return c
        }
        return slider(
            label, row, unit: unit, decimals: decimals, min: min, max: max, quick: quick, on: on,
            read: { read(current()) },
            drag: { [weak self] value in self?.drag(compressor: next(value)) },
            type: { [weak self] value in self?.typedCompressor = next(value) },
            commit: { [weak self] in self?.commitCompressor() }, name: Self.compressorName)
    }

    /// One limiter value row.
    private func limit(
        _ label: String, _ row: (String?, [NSView & OptionControl]) -> NSView, unit: String,
        decimals: Int, min: Double, max: Double, quick: [Double], on: @escaping () -> Bool,
        read: @escaping (LimiterProps) -> Double,
        set: @escaping (inout LimiterProps, Double) -> Void
    ) -> NSView {
        let current = { [weak self] in self?.limiter ?? LimiterProps() }
        let next = { (value: Double) -> LimiterProps in
            var l = current()
            set(&l, value)
            return l
        }
        return slider(
            label, row, unit: unit, decimals: decimals, min: min, max: max, quick: quick, on: on,
            read: { read(current()) },
            drag: { [weak self] value in self?.drag(limiter: next(value)) },
            type: { [weak self] value in self?.typedLimiter = next(value) },
            commit: { [weak self] in self?.commitLimiter() }, name: Self.limiterName)
    }

    private func slider(
        _ label: String, _ row: (String?, [NSView & OptionControl]) -> NSView, unit: String,
        decimals: Int, min: Double, max: Double, quick: [Double], on: @escaping () -> Bool,
        read: @escaping () -> Double, drag: @escaping (Double) -> Void,
        type: @escaping (Double) -> Void, commit: @escaping () -> Void, name: String
    ) -> NSView {
        let enabled = { [weak self] in self?.inNest == false && on() }
        let rail = InspectorSliderControl(
            min: min, max: max, read: read, write: drag,
            begin: { [weak self] in self?.beginDrag() },
            end: { [weak self] in self?.endDrag(name) },
            enabled: enabled, start: { nil }, now: { nil })
        let field = OptionFieldControl(
            width: InspectorMetrics.fieldWidth, unit: unit, decimals: decimals, min: min,
            max: max, quick: quick, read: read, write: type, enabled: enabled, onEdit: commit)
        controls += [rail, field]
        return row(label, [rail, field])
    }

    // MARK: Edits

    private func write(compressor: CompressorProps?) {
        edits.edit(
            Self.compressorName,
            [.setTrack(track: track.id, compressor: compressor?.dictionary ?? NSNull())])
    }

    private func write(limiter: LimiterProps?) {
        edits.edit(
            Self.limiterName,
            [.setTrack(track: track.id, limiter: limiter?.dictionary ?? NSNull())])
    }

    private func beginDrag() {
        dragging = true
        edits.liveBegin()
    }

    private func drag(compressor: CompressorProps) {
        liveCompressor = compressor
        edits.liveUpdate([.setTrack(track: track.id, compressor: compressor.dictionary)])
        changed()
    }

    private func drag(limiter: LimiterProps) {
        liveLimiter = limiter
        edits.liveUpdate([.setTrack(track: track.id, limiter: limiter.dictionary)])
        changed()
    }

    private func endDrag(_ name: String) {
        dragging = false
        edits.liveEnd(name)
    }

    private func commitCompressor() {
        guard let value = typedCompressor else { return }
        typedCompressor = nil
        write(compressor: value)
    }

    private func commitLimiter() {
        guard let value = typedLimiter else { return }
        typedLimiter = nil
        write(limiter: value)
    }

    private static func milliseconds(_ ticks: Ticks) -> Double {
        Double(ticks) / Double(ReelTime.perSecond) * 1000
    }

    private static func ticks(_ milliseconds: Double) -> Ticks {
        Ticks((milliseconds / 1000 * Double(ReelTime.perSecond)).rounded())
    }
}
