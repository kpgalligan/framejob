// app/Sources/GraphicContactSheet.swift — `render_graphic`'s contact sheet
// (road map 10 §5h, G4b): the frames of one module laid out on a grid, each
// with its frame number printed in a strip under it. Pure: cells in, one
// `CGImage` out; no document, no file, no thread of its own.
//
// **The scale is over the CELLS alone** (G4b's objection 2): the gaps and
// the label strips are drawn at full size and never scaled, so the bound
// they are subtracted from is exactly the sheet's size — `width ≤ maxWidth`
// and `height ≤ maxSide` hold by construction.
//
// **At scale 1 a cell is the raster's own bytes**: drawn at its exact pixel
// size and an integer origin, so no resampling touches it and a proof can
// compare it with `render_frame`'s picture pixel for pixel. A cell whose
// frame failed is the error card, through the one painter
// (`LayerRenderers.paintErrorCard`).

import AppKit
import CoreText

/// What the sheet is painted on before the cells.
enum GraphicSheetBackground {
    case transparent, checker, color(CGColor)

    static let accepted = "transparent, checker, or a hex colour (#rgb, #rrggbb, #rrggbbaa)"

    /// `transparent`, `checker`, or `#rgb` / `#rrggbb` / `#rrggbbaa`, in any
    /// case; nil for anything else.
    init?(_ argument: String) {
        let lowered = argument.lowercased()
        switch lowered {
        case "transparent":
            self = .transparent
        case "checker":
            self = .checker
        default:
            guard lowered.hasPrefix("#") else { return nil }
            let hex = Array(lowered.dropFirst())
            guard [3, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) else { return nil }
            let digits = hex.count == 3 ? hex.flatMap { [$0, $0] } : hex
            var channels = stride(from: 0, to: digits.count, by: 2).map { at -> CGFloat in
                CGFloat(UInt8(String(digits[at...at + 1]), radix: 16) ?? 0) / 255
            }
            if channels.count == 3 { channels.append(1) }
            self = .color(CGColor(
                srgbRed: channels[0], green: channels[1], blue: channels[2], alpha: channels[3]))
        }
    }
}

/// One cell: the frame it shows and either its picture or its card's text.
struct GraphicSheetCell {
    let frame: Int
    let image: CGImage?
    let cardText: String?
}

enum GraphicContactSheet {
    static let gap = 8, labelHeight = 24, maxWidthDefault = 2048, maxWidthMin = 64
    static let maxFrames = 16, maxSide = GraphicLibrary.maxSide
    /// The most pixels of frames a png sheet draws (spec §11 G-20 (d)):
    /// every cell's raster is held until paint. Two 8192² frames, or
    /// sixteen 3840×2160.
    static let maxCellPixels = 2 * maxSide * maxSide

    /// Where every cell goes. Row-major from the top left, no outer margin.
    struct Layout {
        let columns, rows: Int
        let scale: Double
        let cellWidth, cellHeight, width, height: Int

        /// Cell `index`'s top-left corner, y down.
        func origin(of index: Int) -> (x: Int, y: Int) {
            let column = index % columns, row = index / columns
            return (
                column * (cellWidth + GraphicContactSheet.gap),
                row * (cellHeight + GraphicContactSheet.labelHeight + GraphicContactSheet.gap))
        }
    }

    /// `count` cells of `cellWidth`×`cellHeight` on a near-square grid, the
    /// cells scaled down (never up) so the sheet is at most `maxWidth` wide
    /// and `maxSide` tall.
    static func layout(count: Int, cellWidth: Int, cellHeight: Int, maxWidth: Int) -> Layout {
        let count = max(count, 1)
        var columns = 1
        while columns * columns < count { columns += 1 }
        let rows = (count + columns - 1) / columns
        let byWidth = Double(maxWidth - (columns - 1) * gap) / Double(columns * cellWidth)
        let byHeight = Double(maxSide - rows * labelHeight - (rows - 1) * gap)
            / Double(rows * cellHeight)
        let scale = min(1, byWidth, byHeight)
        let drawnWidth = max(1, Int((Double(cellWidth) * scale).rounded(.down)))
        let drawnHeight = max(1, Int((Double(cellHeight) * scale).rounded(.down)))
        return Layout(
            columns: columns, rows: rows, scale: scale,
            cellWidth: drawnWidth, cellHeight: drawnHeight,
            width: columns * drawnWidth + (columns - 1) * gap,
            height: rows * (drawnHeight + labelHeight) + (rows - 1) * gap)
    }

    /// The sheet: `background`, then each cell at `layout`'s place with its
    /// label strip under it. Premultiplied BGRA in sRGB, exactly
    /// `layout.width`×`layout.height`.
    static func paint(
        _ cells: [GraphicSheetCell], layout: Layout, background: GraphicSheetBackground
    ) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: layout.width, height: layout.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let whole = CGRect(x: 0, y: 0, width: layout.width, height: layout.height)
        switch background {
        case .transparent:
            context.clear(whole)
        case .color(let color):
            context.setFillColor(color)
            context.fill(whole)
        case .checker:
            paintChecker(context, width: layout.width, height: layout.height)
        }
        context.interpolationQuality = layout.scale < 1 ? .high : .none
        for (index, cell) in cells.enumerated() {
            let (x, top) = layout.origin(of: index)
            // Core Graphics is y up: the cell's bottom edge, from the top-left place.
            let rect = CGRect(
                x: x, y: layout.height - top - layout.cellHeight,
                width: layout.cellWidth, height: layout.cellHeight)
            if let text = cell.cardText {
                LayerRenderers.paintErrorCard(text, in: context, bounds: rect)
            } else if let image = cell.image {
                context.draw(image, in: rect)
            }
            paintLabel(
                cell.frame, in: context,
                strip: CGRect(
                    x: rect.minX, y: rect.minY - CGFloat(labelHeight), width: rect.width,
                    height: CGFloat(labelHeight)))
        }
        return context.makeImage()
    }

    /// 16 px squares of (128,128,128) and (192,192,192), from the top left.
    static func paintChecker(_ context: CGContext, width: Int, height: Int) {
        let side = 16
        context.setFillColor(CGColor(srgbRed: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 192 / 255, green: 192 / 255, blue: 192 / 255, alpha: 1))
        for row in 0...(height / side) {
            for column in 0...(width / side) where (row + column) % 2 == 1 {
                context.fill(CGRect(
                    x: column * side, y: height - (row + 1) * side, width: side, height: side))
            }
        }
    }

    /// The frame number in white `DS.mono(13)` on an opaque (30,30,30) strip,
    /// clipped to the strip.
    private static func paintLabel(_ frame: Int, in context: CGContext, strip: CGRect) {
        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: strip)
        context.setFillColor(CGColor(srgbRed: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1))
        context.fill(strip)
        let attributed = NSAttributedString(
            string: String(frame),
            attributes: [.font: DS.mono(13), .foregroundColor: NSColor.white])
        let line = CTLineCreateWithAttributedString(attributed)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: strip.minX + 6, y: strip.minY + 7)
        CTLineDraw(line, context)
    }
}

extension GraphicRaster {
    /// The raster as a `CGImage`: premultiplied BGRA in sRGB, rows `stride`
    /// bytes apart — the layout the engine wrote, so nothing is converted.
    func cgImage() -> CGImage? {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: Data(bgra) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: stride, space: space,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
