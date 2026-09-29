import AppKit

/// The inspector scroll view's clip view (#142), installed before the scroll
/// view's `drawsBackground` is set (a fresh clip view would paint the pane). When an autohiding legacy scroller hides, the clip
/// view widens but its document view was not re-laid: screens 06 and 10
/// measured the clip view at 304, the stack at 304 and the ClipPane frame
/// stale at 287. A width change here re-lays the document view, and a layout
/// pass brings its width to the clip view's own.
final class InspectorClipView: NSClipView {
    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(newSize)
        if abs(newSize.width - oldWidth) > 0.5 {
            needsLayout = true
            documentView?.needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        if let documentView = documentView,
            abs(documentView.frame.width - bounds.width) > 0.5
        {
            documentView.setFrameSize(
                NSSize(width: bounds.width, height: documentView.frame.height))
        }
    }
}
