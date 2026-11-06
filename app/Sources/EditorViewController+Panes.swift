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
    /// ⌥⌘I's re-layout. A shown inspector comes back inside its 280–440 pt:
    /// `adjustSubviews` alone hands back a width scaled by any window resize
    /// made while it was hidden (under 280 pt after a 120 pt wider window).
    /// The canvas keeps its own minimum, as `constrainMaxCoordinate` does.
    static func adjustInspector(in split: NSSplitView, inspector: NSView) {
        split.adjustSubviews()
        guard !inspector.isHidden else { return }
        let width = inspector.frame.width
        let clamped = min(max(width, minInspectorWidth), maxInspectorWidth)
        guard clamped != width else { return }
        let position = max(minCanvasWidth, split.bounds.width - clamped - split.dividerThickness)
        split.setPosition(position, ofDividerAt: 0)
    }

    /// A drag of `main`'s divider saves `timeline`'s height under
    /// `timelineHeightKey`; of `upper`'s, `inspector`'s width under
    /// `inspectorWidthKey` (not while hidden, not ≤ 1 pt), and a drag that
    /// shows the inspector clears `inspectorCollapsedKey`, so a new window
    /// doesn't hide what this one shows. Any other resize —
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
            if defaults.bool(forKey: inspectorCollapsedKey) {
                defaults.set(false, forKey: inspectorCollapsedKey)
            }
        }
    }
}
