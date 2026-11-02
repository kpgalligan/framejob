import CoreGraphics

/// Frame Job's own pointer (road map creator-jobs CU4, spec §11 CU-41): one vector arrow in a
/// 14 × 21 pt box, its tip — the hot spot — at (1.5, 1.5). Its geometry is Frame Job's, no Apple
/// artwork (CU-8). `CursorSprites.arrow` rasterizes `svg` through the graphic engine once per
/// pixel size and output; the compositor draws it for `style: arrow` and for a frame whose file
/// recorded no cursor image (`cursor_image: none`, CU-6's fallback).
enum CursorArrow {
    /// The arrow's box in points.
    static let size = CGSize(width: 14, height: 21)
    /// The tip in points from the box's top-left.
    static let hotSpot = CGPoint(x: 1.5, y: 1.5)

    /// The arrow's pixel size at `pxPerPoint` (the file's) and the clip's `scale`:
    /// max(1, round(14·k)) × max(1, round(21·k)), k = pxPerPoint × scale.
    static func pixelSize(pxPerPoint: Double, scale: Double) -> (width: Int, height: Int) {
        let k = pxPerPoint * scale
        func side(_ points: Double) -> Int {
            let px = (points * k).rounded()
            guard px.isFinite, px >= 1 else { return 1 }
            return Int(min(px, Double(GraphicLibrary.maxSide)))
        }
        return (side(Double(size.width)), side(Double(size.height)))
    }

    /// The arrow as SVG drawn at `width` × `height` pixels: one path, black fill, a white
    /// 1.25 pt stroke with round joins.
    static func svg(width: Int, height: Int) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(width)\" height=\"\(height)\" "
            + "viewBox=\"0 0 14 21\"><path d=\"M1.5 1.5 L1.5 17 L5.3 13.4 L7.9 19.4 L10.6 18.3 "
            + "L8.1 12.4 L13 12.4 Z\" fill=\"#000\" stroke=\"#fff\" stroke-width=\"1.25\" "
            + "stroke-linejoin=\"round\"/></svg>"
    }
}
