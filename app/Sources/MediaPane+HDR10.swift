import AppKit

/// The Media tab's **HDR10** section (spec §11 HD-12, §4.3): the peak of the
/// PQ file selected in the list — what import read from its HDR10 metadata,
/// which places step 0's PQ shoulder — with a Peak field that overrides it, a
/// Use File's button that clears the override, and a line saying where the
/// peak came from; one undo step "PQ Peak". It is there once the project has
/// a PQ file (`MediaPane.makeSections`), acts on `selectedMedia`, the row a
/// click selects, and is disabled when that is not a PQ file. Every write
/// keeps the media's Camera Log, as the Camera Log section's writes keep the
/// peak. The agent's mirror is `set_media_color {peak}`
/// (`AgentServer+Media.swift`).
extension MediaPane {
    func hdr10Section() -> InspectorSection {
        let binding = self.binding
        /// The selected row when it is a PQ file: a video or a still (spec §11
        /// HD-20 (b)).
        func selected() -> MediaSnapshot? {
            guard let id = binding.document?.selectedMedia,
                let media = binding.documentSnapshot.media(id),
                media.kind == .video || media.kind == .image,
                media.color?.pq != nil
            else { return nil }
            return media
        }
        /// The override set to `peak` (nil: the file's), the Camera Log kept.
        func write(_ media: MediaSnapshot, peak: UInt32?) {
            guard var color = media.color, var pq = color.pq, pq.peak != peak else { return }
            pq.peak = peak
            color.pq = pq
            binding.apply("PQ Peak", [.setMediaColor(media: media.id, color: color)])
        }
        let field = OptionFieldControl(
            width: InspectorMetrics.wideFieldWidth + 14, unit: "cd/m²", decimals: 0,
            min: 1, max: 10_000, quick: [1000, 2000, 4000, 10_000],
            read: {
                Double(selected()?.color?.pq?.effectivePeak
                    ?? UInt32(InputConversions.pqWhite))
            },
            write: { value in
                guard let media = selected(), let pq = media.color?.pq else { return }
                let peak = UInt32(max(1, min(10_000, value.rounded())))
                // The value already shown is no new choice.
                guard peak != pq.effectivePeak else { return }
                write(media, peak: peak)
            },
            enabled: { selected() != nil },
            onEdit: { binding.edited() })
        field.toolTip = "The brightness this file's highlights roll off to white at"
        let useFile = OptionButtonControl(
            title: "Use File's",
            action: {
                guard let media = selected() else { return }
                write(media, peak: nil)
            },
            enabled: { selected()?.color?.pq?.peak != nil },
            onEdit: { binding.edited() })
        useFile.toolTip = "Go back to the peak the file's HDR10 metadata names"
        let readout = inspectorReadout(width: InspectorMetrics.popupWidth + 52) {
            guard let pq = selected()?.color?.pq else { return "Select a PQ file in the list" }
            return MediaPane.hdr10Line(pq)
        }
        return InspectorSection(
            id: "media.hdr10", title: "HDR10",
            summary: {
                selected()?.color?.pq.map {
                    "\(MediaPane.nits($0.effectivePeak ?? UInt32(InputConversions.pqWhite))) cd/m²"
                }
            },
            rows: [inspectorRow("Peak", [field, useFile]), inspectorRow(nil, [readout])])
    }

    /// Where a PQ file's peak came from, in the readout's words.
    static func hdr10Line(_ pq: PQColor) -> String {
        let file = pq.file.map { "\(nits($0)) cd/m²" }
        let field = pq.from.map { $0 == .maxCLL ? "MaxCLL" : "mastering display" }
        if pq.peak != nil {
            guard let file else { return "Set by hand; the file has no HDR10 metadata" }
            return "Set by hand; the file says \(file)" + (field.map { " (\($0))" } ?? "")
        }
        guard let file else {
            return "No HDR10 metadata — \(nits(UInt32(InputConversions.pqWhite))) cd/m² assumed"
        }
        return "Mastered at \(file) (" + (field.map { "\($0), " } ?? "") + "from the file)"
    }

    /// A whole number of cd/m² with thousands grouped by commas ("4,000"),
    /// whatever the locale, as the spec writes them.
    static func nits(_ value: UInt32) -> String {
        let digits = String(value)
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return out
    }
}
