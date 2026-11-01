import AppKit

/// The Volume section's Enhance Voice button (road map "audio" AP6, spec
/// §11 AU-60, AU-65): one row under Normalize's, offered where Normalize is
/// (`AudioPane.normalizable`). Its press is `AudioMeasureDoor.press`, the
/// body Clip ▸ Enhance Voice shares: the clips measured, each rendered
/// through its chosen settings under the Measuring Sound sheet (AU-64), and
/// the settings committed as ONE undo step at the Normalize row's Target —
/// one `set_audio` per clip, never through `InspectorBinding.ops(audio:)`,
/// whose one shared patch and action routing would both be wrong
/// (`AudioPane.normalize`'s argument). Nothing to enhance, or a second
/// press, beeps. `enhance_voice` runs the same read, run and plan.
extension AudioPane {

    /// The button, its tooltip the rules in a sentence.
    func enhanceButton() -> OptionButtonControl {
        let binding = self.binding
        let button = OptionButtonControl(
            title: "Enhance Voice",
            action: { [weak self] in self?.enhanceVoice() },
            enabled: { !AudioPane.normalizable(binding).isEmpty }, onEdit: {})
        button.toolTip =
            "Measure each selected clip's voice and pauses and set its sound up for speech: "
            + "a rumble cut, voice isolation (or noise reduction) and a gate when the pauses "
            + "are noisy, the de-esser when the \"s\" sounds are hot, a compressor from the "
            + "voice's own level, and the limiter and volume that reach the Normalize row's "
            + "target, measured through the new settings. Every setting it writes can be seen "
            + "and changed in its section, and pressing it twice changes nothing."
        return button
    }

    private func enhanceVoice() {
        guard let document = binding.document else { return NSSound.beep() }
        AudioMeasureDoor.press(
            .enhanceVoice, document: document,
            clips: AudioPane.normalizable(binding).map { $0.id }, window: window)
    }
}
