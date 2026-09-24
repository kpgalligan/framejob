import AppKit

/// The in-canvas text editor's frame while typing (kpgalligan/reelcut#36).
///
/// The editor is sized from the SAME measurement that sizes the clip's box
/// once the string is applied — `LayerRenderers.measuredSize(for:)` over the
/// clip's text with the typed string in place of its content, placed by
/// `canvasRect` exactly as `CanvasLayerBox.uncroppedRect` places it — so the
/// field grows, wraps and shrinks the way the applied box will, and applying
/// moves nothing. There is deliberately no second measurement here.
///
/// The frame is the source of truth, not the text view: both resizable flags
/// are off, so AppKit's own `sizeToFit` cannot grow the editor past the box.
/// The wrap width follows from the frame (`widthTracksTextView`) less two
/// margins, each in view points at the box's own scale: the container inset
/// takes back the 2 canvas pixels the frame stands outside the box, and the
/// line-fragment padding the backdrop's padding and the outline's overshoot
/// (`LayerRenderers.textInsets`, the margin the measured size includes). What
/// is left is the width CoreText lays the text in, so a fixed-width text
/// breaks where the render breaks it and an auto-sized one does not wrap —
/// measured: with a fixed 2 pt inset, an auto-sized "Hello " wrapped.
extension PreviewCanvasView {
    func fitTextEditor(_ editor: NSTextView, to box: CanvasLayerBox) {
        guard let props = box.clip.text else { return }
        let typed = props.withContent(editor.string)
        let size = LayerRenderers.measuredSize(for: typed)
        let rect = canvasToView(
            canvasRect(of: box.clip, in: box.canvas, sourceSize: size, video: box.uncropped)
                .insetBy(dx: -2, dy: -2))
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 2 * canvasScale, height: 2 * canvasScale)
        editor.textContainer?.lineFragmentPadding =
            LayerRenderers.textInsets(typed).x * box.video.scale * canvasScale
        // The floor the editor always had, widened from the edge the text is
        // aligned to — so a string shorter than the floor starts where it
        // renders, left, right or centred — and always hung from the box's
        // top, where the editor lays out its first line.
        let width = max(rect.width, 60)
        let height = max(rect.height, 24)
        let x: CGFloat
        switch props.align {
        case "center": x = rect.midX - width / 2
        case "right": x = rect.maxX - width
        default: x = rect.minX
        }
        editor.frame = CGRect(x: x, y: rect.minY, width: width, height: height)
    }
}

extension TextProps {
    /// This description with `content` replaced and every other field kept —
    /// what `set_text {content}` will make of it.
    fileprivate func withContent(_ value: String) -> TextProps {
        TextProps(
            content: value, font: font, size: size, color: color, align: align,
            valign: valign, lineSpacing: lineSpacing, tracking: tracking, outline: outline,
            backdrop: backdrop, width: width, animation: animation, textCase: textCase,
            words: words, wordStyle: wordStyle)
    }
}
