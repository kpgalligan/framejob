// heic10_writer — precision_proof.py's 10-bit HEIC fixture (precision-2
// P2-1's fix pass): `heic10_writer <in.png> <out.heic>`.
//
// The PNG is drawn into a 16-bit-float sRGB bitmap and that image handed to
// ImageIO's HEIC writer at quality 0.99. Measured on the 16-bit `ramp16.png`
// (M2 Max, macOS 26.5.1; the middle row's distinct 10-bit Y codes, ffmpeg's
// decode): from the float image, HEVC Main 10 `yuv420p10le` holding 1024;
// from the PNG's own 16-bit INTEGER image, Main 10 holding 256 at 0.99 (and
// 285 at 0.9, 448 at 0.75 — coding noise, not levels), and `sips -s format
// heic` likewise (410 at its default, 256 at `best`, Rext 4:4:4). So only
// the float route writes a HEIC whose content is 10-bit. Exit 0 when the
// file is written, 1 otherwise.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB)
else {
    FileHandle.standardError.write("usage: heic10_writer <in.png> <out.heic> (a readable image)\n"
        .data(using: .utf8)!)
    exit(1)
}
let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
    | CGBitmapInfo.byteOrder16Little.rawValue
guard let context = CGContext(data: nil, width: image.width, height: image.height,
                              bitsPerComponent: 16, bytesPerRow: 0, space: space,
                              bitmapInfo: info)
else { exit(1) }
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
guard let deep = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: arguments[2]) as CFURL, UTType.heic.identifier as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(destination, deep,
                           [kCGImageDestinationLossyCompressionQuality: 0.99] as CFDictionary)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
