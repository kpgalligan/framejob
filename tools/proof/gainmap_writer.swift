// gainmap_writer — hdr_proof.py's gain-map HEIC (clean-up 3 batch B, phase 3, #322,
// spec §11 HD-22): `gainmap_writer <out.heic> <width> <height>`.
//
// Eight equal vertical bands of extended-linear grey, L = 0.05, 0.18, 0.5, 1, 2, 4, 6,
// 8 left to right, drawn into a 16-bit-float `extendedLinearSRGB` image whose content
// headroom is set to 8, then written by ImageIO's HEIC writer with
// `kCGImageDestinationEncodeRequest: kCGImageDestinationEncodeToISOGainmap` at
// quality 0.99 — M2's writer route (HD-22 (a)): at the image's default headroom (0)
// the file carries a gain map but every band from L = 1 up reads back 1.0. ImageIO
// writes an SDR base (Display P3, 8 bits, its own tone map of the bands) and an ISO
// 21496-1 gain map.
//
// It then reads what it wrote: exit 0 only when the file answers one of the two
// gain-map lookups `StillGainMap.hasGainMap` makes (ISO, Apple) and its base's space is
// neither HLG- nor PQ-based (what `StillColor.conversion(of:)` answers nil for); 1
// otherwise. One line out: the lookups and the base's space.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ text: String) -> Never {
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let width = Int(arguments[2]), let height = Int(arguments[3]),
    width >= 8, height >= 1
else { fail("usage: gainmap_writer <out.heic> <width ≥ 8> <height ≥ 1>") }
let output = URL(fileURLWithPath: arguments[1])
let bands: [CGFloat] = [0.05, 0.18, 0.5, 1, 2, 4, 6, 8]

guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
else { fail("no 16-bit-float extendedLinearSRGB context") }
let bandWidth = Double(width) / Double(bands.count)
for (i, l) in bands.enumerated() {
    let x0 = (Double(i) * bandWidth).rounded(), x1 = (Double(i + 1) * bandWidth).rounded()
    guard let grey = CGColor(colorSpace: space, components: [l, l, l, 1]) else {
        fail("no colour for L = \(l)")
    }
    context.setFillColor(grey)
    context.fill(CGRect(x: x0, y: 0, width: x1 - x0, height: Double(height)))
}
guard let drawn = context.makeImage(),
    let image = CGImageCreateCopyWithContentHeadroom(8, drawn),
    let destination = CGImageDestinationCreateWithURL(
        output as CFURL, UTType.heic.identifier as CFString, 1, nil)
else { fail("no image or destination") }
CGImageDestinationAddImage(
    destination, image,
    [kCGImageDestinationEncodeRequest: kCGImageDestinationEncodeToISOGainmap,
     kCGImageDestinationLossyCompressionQuality: 0.99] as CFDictionary)
guard CGImageDestinationFinalize(destination) else { fail("the HEIC was not written") }

guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
    let base = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fail("the HEIC does not read back") }
let iso = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
    source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
let apple = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
    source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
let claimed = base.colorSpace.map { CGColorSpaceIsHLGBased($0) || CGColorSpaceIsPQBased($0) }
    ?? false
let name = (base.colorSpace?.name as String?) ?? "unnamed"
print("iso \(iso) apple \(apple) base \(name) \(base.bitsPerComponent)-bit "
    + "\(base.width)×\(base.height) claimed \(claimed)")
exit((iso || apple) && !claimed ? 0 : 1)
