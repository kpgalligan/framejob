import AppKit

/// The in-canvas text editor's frame while typing (kpgalligan/framejob#36).
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
/// The wrap width is set from the same unrounded width the frame is given,
/// not tracked from the frame (`widthTracksTextView` is off): AppKit aligns
/// the frame to backing pixels, which could widen the wrap by up to a pixel
/// and keep a word the render breaks (kpgalligan/framejob#186). That width
/// loses two margins, each in view points at the box's own scale: the
/// container inset takes back the 2 canvas pixels the frame stands outside
/// the box, and the line-fragment padding the backdrop's padding and the
/// outline's overshoot (`LayerRenderers.textInsets`, the margin the measured
/// size includes). What is left is the width CoreText lays the text in, so
/// a fixed-width text breaks where the render breaks it and an auto-sized
/// one does not wrap — measured: with a fixed 2 pt inset, an auto-sized
/// "Hello " wrapped.
///
/// Inside that frame the text is laid out in the render's own attributes
/// (spec §11 K-3, kpgalligan/framejob#117): `LayerRenderers.textAttributes` at
/// the box's view scale, unclamped — the font, the kern and the paragraph
/// style, so tracking, line spacing and a small or large size break lines
/// where the render does — in the editor's own ink and with no stroke. An
/// UPPERCASE text is edited as typed, because the storage is what `set_text`
/// commits; a rotated clip is edited axis-aligned.
extension PreviewCanvasView {
    func fitTextEditor(_ editor: NSTextView, to box: CanvasLayerBox) {
        guard let props = box.clip.text else { return }
        var typed = props
        typed.content = editor.string
        styleTextEditor(editor, as: typed, scale: box.video.scale * canvasScale)
        let size = LayerRenderers.measuredSize(for: typed)
        let rect = canvasToView(
            canvasRect(of: box.clip, in: box.canvas, sourceSize: size, video: box.video.uncropped)
                .insetBy(dx: -2, dy: -2))
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = false
        editor.textContainer?.widthTracksTextView = false
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
        editor.textContainer?.containerSize = NSSize(
            width: width - 2 * editor.textContainerInset.width,
            height: CGFloat.greatestFiniteMagnitude)
    }

    /// The live editor to the box its string will have, in the render's
    /// attributes at the canvas's current scale (#36, K-3).
    func refitTextEditor() {
        guard let editor = textEditor, let id = editingClip, let box = box(for: id),
              box.clip.text != nil else { return }
        fitTextEditor(editor, to: box)
    }

    /// The render's attribute set at `scale`, in the editor's ink and with
    /// no stroke, as the editor's typing attributes, default paragraph style
    /// and — when it differs — its storage. The storage is written with
    /// `addAttributes`, so nothing else in it is dropped, and never while an
    /// input method holds marked text, whose own attributes that would
    /// overwrite. An EMPTY storage is not read (index 0 of an empty string
    /// raises) or written; the typing attributes are what the next letter
    /// takes.
    private func styleTextEditor(_ editor: NSTextView, as props: TextProps, scale: CGFloat) {
        var attributes = LayerRenderers.textAttributes(props, scale: scale)
        attributes[.foregroundColor] = DS.textStrong
        attributes[.strokeWidth] = nil
        attributes[.strokeColor] = nil
        editor.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        editor.typingAttributes = attributes
        guard let storage = editor.textStorage, storage.length > 0, !editor.hasMarkedText()
        else { return }
        let current = storage.attributes(at: 0, effectiveRange: nil)
        let same = (current[.font] as? NSFont) == (attributes[.font] as? NSFont)
            && (current[.kern] as? CGFloat) == (attributes[.kern] as? CGFloat)
            && (current[.paragraphStyle] as? NSParagraphStyle)
                == (attributes[.paragraphStyle] as? NSParagraphStyle)
        if same { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttributes(attributes, range: whole)
        if attributes[.kern] == nil { storage.removeAttribute(.kern, range: whole) }
        storage.endEditing()
    }
}
