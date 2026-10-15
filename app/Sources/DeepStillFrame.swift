import AVFoundation
import CoreVideo
import ImageIO

/// Whether a frame shows a still deeper than 8 bits a component, and how such
/// a frame is read (issue batch B97, spec §11 PR-9): the question
/// `render_frame` and File ▸ Save Frame… (PNG, HEIC) answer before they ask
/// `Exporter.renderFrame` for `deepStill`, and the reader it then reads the
/// frame through instead of `AVAssetImageGenerator`, whose image is 16-bit
/// only when every video track of the composition is deep. GIF and APNG
/// never ask: ImageIO writes both at 8 bits a component.
///
/// It asks the RECIPE, not the project: a deep still elsewhere on the
/// timeline, or one Show Selection leaves out (`options`), is not on the
/// frame, and a frame that does not show one goes through the generator
/// exactly as before (PR-4's guarantee). Nests need nothing here — the core
/// flattens them into the recipe's one layer list (`core/src/recipe.rs`). A
/// still the recipe draws counts whatever its opacity, crop or cover.
///
/// Every caller is off the main thread already: `shows` reads each still's
/// file header, and `read` blocks on the compositor.
enum DeepStillFrame {

    /// True when the recipe at `max(0, t)` (with `options`) has an `image`
    /// layer whose file `isDeep`.
    static func shows(
        _ project: ReelProject, urls: [UInt32: URL], at t: Ticks, options: RecipeOptions
    ) -> Bool {
        guard let recipe = project.recipe(at: max(0, t), options: options) else { return false }
        for layer in recipe.layers {
            guard case .image(let media) = layer.source, let url = urls[media] else { continue }
            if isDeep(url) { return true }
        }
        return false
    }

    /// The header twin of PR-6's draw test (`LayerRenderers.renderImage`'s
    /// `image.bitsPerComponent > 8`): the depth ImageIO reports for the file's
    /// first image, `kCGImagePropertyDepth`, above 8. An unreadable file is
    /// not deep — it draws a slate, not a still.
    static func isDeep(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let depth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue
        else { return false }
        return depth > 8
    }

    /// The frame at max(0, t) of `built`, read through AVAssetReaderVideoCompositionOutput
    /// at Compositor.outputPixelFormat; 16 bits a component, half float; nil when no sample,
    /// or when `maxWidth` asks for a size it cannot redraw at (never an unscaled frame).
    ///
    /// Export's reader (`ExportWriter.addVideo`'s two settings) over one
    /// frame's range. `cancelReading` runs here, on the thread that called
    /// `copyNextSampleBuffer`, after it returned (G-17), and the caller's
    /// `RecipeSource` key is still registered. The image owns a copy of the
    /// rows. Its space is `FrameWriter.frameSpace`, the BT.709 label every
    /// rendered frame's file carries (spec §11 PR-11), its pixels the buffer's.
    static func read(_ built: BuiltComposition, at t: Ticks, maxWidth: Int?) -> CGImage? {
        guard let reader = try? AVAssetReader(asset: built.composition) else { return nil }
        reader.timeRange = CMTimeRange(
            start: CompositionBuilder.time(max(0, t)),
            duration: built.videoConfiguration.frameDuration)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: built.composition.tracks(withMediaType: .video),
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(Compositor.outputPixelFormat),
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ])
        output.videoComposition = built.videoComposition
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        let sample = output.copyNextSampleBuffer()
        reader.cancelReading()
        guard let sample = sample, let buffer = CMSampleBufferGetImageBuffer(sample) else {
            return nil
        }
        guard let image = image(of: buffer, space: FrameWriter.frameSpace) else { return nil }
        guard let maxWidth = maxWidth, maxWidth > 0 else { return image }
        let size = Exporter.scaledSize(built.videoComposition.renderSize, to: maxWidth)
        let width = max(1, Int(size.width)), height = max(1, Int(size.height))
        if width == image.width && height == image.height { return image }
        guard let space = image.colorSpace,
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0,
                space: space, bitmapInfo: bitmapInfo)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// RGBA, 16-bit half float, premultiplied, little-endian: 64RGBAHalf's layout.
    private static let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
        | CGBitmapInfo.byteOrder16Little.rawValue

    /// A CGImage owning a copy of `buffer`'s rows.
    private static func image(of buffer: CVImageBuffer, space: CGColorSpace) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        guard let provider = CGDataProvider(data: Data(bytes: base, count: rowBytes * height) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
            bytesPerRow: rowBytes, space: space, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
