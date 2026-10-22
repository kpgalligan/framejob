import AppKit

/// The editor's two split views, which know when a person is dragging a
/// divider (#327).
///
/// AppKit's divider drag runs inside `mouseDown(with:)` until the mouse is
/// up, so the flag is true for exactly the resizes a drag causes. The
/// notification's `NSSplitViewDividerIndex` user info is not that test:
/// NSSplitView.h says that since macOS 12 it is posted "during resize and
/// layout events as well", so a window resize carries it too.
final class PaneSplitView: NSSplitView {
    private(set) var isDraggingDivider = false

    override func mouseDown(with event: NSEvent) {
        isDraggingDivider = true
        defer { isDraggingDivider = false }
        super.mouseDown(with: event)
    }
}

extension EditorViewController {
    /// A drag of `main`'s divider saves `timeline`'s height under
    /// `timelineHeightKey`; of `upper`'s, `inspector`'s width under
    /// `inspectorWidthKey` (not while hidden, not ≤ 1 pt). Any other resize —
    /// `notification.object` not dragging, as a window resize, a restore or
    /// ⌥⌘I is — saves nothing, so the remembered size is the one a person
    /// chose and a new window opens with it.
    static func savePaneSize(
        after notification: Notification, main: PaneSplitView, upper: PaneSplitView,
        timeline: NSView, inspector: NSView, to defaults: UserDefaults
    ) {
        guard let split = notification.object as? PaneSplitView, split.isDraggingDivider
        else { return }
        if split === main, timeline.bounds.height > 1 {
            defaults.set(Double(timeline.bounds.height), forKey: timelineHeightKey)
        } else if split === upper, !inspector.isHidden, inspector.bounds.width > 1 {
            defaults.set(Double(inspector.bounds.width), forKey: inspectorWidthKey)
        }
    }
}
