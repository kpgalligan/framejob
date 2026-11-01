import AppKit

#if FRAMEJOB_DEV_TOOLS
/// A read-out draws its text itself, so `snapshot_ui`'s layout dump names it
/// (dev tools only): one `option.display` part, its text the read-out's, its
/// rect the control's. The Volume section's At volume is read this way by
/// `audio_ap6_proof.py` V15 (spec §11 AU-64 (g)).
extension OptionDisplayControl: UISnapshotParts {
    func snapshotParts() -> [UISnapshotPart] {
        [UISnapshotPart(id: "option.display", text: text, rect: bounds)]
    }
}
#endif
