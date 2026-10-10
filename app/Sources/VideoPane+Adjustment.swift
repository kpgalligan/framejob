import AppKit

/// The adjustment clip's half of the Clip tab (spec §11 GR-6): the three
/// selection tests `ClipPane` builds its sub-tabs from, and the Adjustment
/// section the Color tab opens with when every selected clip is one.
///
/// An adjustment clip draws nothing of its own — it grades everything behind
/// it in its container — so its only pixel key the chrome writes is
/// `opacity`, shown here as Strength. Picture never appears with one in the
/// selection (its transform, crop and shadow are kept in the model and not
/// drawn), and Color appears when every clip is gradable: source pixels or
/// an adjustment clip.
extension VideoPane {
    // MARK: Applicability

    /// Every selected clip is an adjustment clip; false for no selection.
    var allAdjustment: Bool {
        let clips = binding.clips
        return !clips.isEmpty && clips.allSatisfy { InspectorTab.isAdjustment($0) }
    }

    /// Some selected clip is an adjustment clip.
    var anyAdjustment: Bool {
        binding.clips.contains { InspectorTab.isAdjustment($0) }
    }

    /// Every selected clip takes a grade: it has source pixels or is an
    /// adjustment clip; false for no selection.
    var allGradable: Bool {
        let clips = binding.clips
        return !clips.isEmpty
            && clips.allSatisfy {
                InspectorTab.hasSourcePixels($0, in: binding.snapshot)
                    || InspectorTab.isAdjustment($0)
            }
    }

    // MARK: Adjustment

    /// The Color tab's first section for an all-adjustment selection:
    /// Strength, the clip's `opacity` — how much of its grade is mixed over
    /// what is behind it. The summary is the strength; Reset is full
    /// strength.
    func adjustmentSection() -> InspectorSection {
        let binding = self.binding
        return InspectorSection(
            id: "video.adjustment", title: "Adjustment",
            summary: { String(format: "%.0f%%", binding.videoProps.opacity * 100) },
            reset: { binding.apply("Adjustment", video: VideoPatch(opacity: 1)) },
            defaultExpanded: false,
            rows: [
                inspectorValueRow(
                    "Strength", binding, name: "Strength", unit: "%", decimals: 0, min: 0, max: 100,
                    quick: [0, 25, 50, 75, 100],
                    read: { binding.videoProps.opacity * 100 },
                    ops: { binding.ops(video: VideoPatch(opacity: $0 / 100)) },
                    mixed: { binding.mixedVideo { $0.opacity } }),
            ])
    }
}
