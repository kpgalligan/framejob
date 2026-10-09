#!/usr/bin/env python3
"""What an `AVPlayerLayer` DISPLAYS, seen without capturing the screen — the
precision road map's display instrument (issue batch B94, spec §11 PR-1;
`designs/precision.md`).

Why. The preview probes (`preview_refresh_probe.py`, `preview_validity_probe.py`,
`media_less_playback_probe.swift`) read `AVPlayerLayer.displayedPixelBuffer()`:
the buffer the layer was GIVEN, not what it drew. A 16-bit-float render
context (PR-1) could hand the layer a buffer whose bytes match the export and
still be drawn with another transfer or colour reading. The owner's rule is
never to record the owner's screen, so `screencapture` and a `CGWindowList`
image are out. The instrument here is `CARenderer(mtlTexture:options:)`, given
`kCARendererColorSpace` = sRGB: it draws a layer tree in-process into a
`bgra8Unorm` texture of the layer's size. The tree is an `AVPlayerLayer` that
sits in no window, under a root layer with a magenta background, so a layer
that drew nothing shows magenta.

    python3 tools/proof/preview_display_probe.py --rows spike      # V0–V2

The spike (rows V0–V2; run FIRST, on PR0's tree, before any product edit).
A probe-owned `AVVideoCompositing` hands out a frame of four flat quadrants —
grey 64, grey 128, grey 192 and (200, 60, 30) — UNTAGGED, as the app's
compositor output is; the player is paused at 0.5 s over a 640 × 360 H.264
movie and the layer drawn by the instrument. Each variant runs in its own
process.

  V0  (instrument) the frame as 32BGRA: no magenta pixel inside the video
      rect, and every pair of quadrants differs by >= 32 in some channel —
      the layer's content was drawn.
  V1  (control, must differ) the frame as 64RGBAHalf (k/255) tagged
      `kCVImageBufferTransferFunction_Linear`: the grey-128 quadrant's mean
      is >= 10 levels off V0's.
  V2  the same 64RGBAHalf frame untagged: every quadrant's mean within ±2 of
      V0's.

If V0 or V1 fails the instrument cannot see the display: `designs/precision.md`
says so with the figures, PV is not built, and spec §11 PR-1's check of the
displayed picture is `docs/manual-checks.md`'s PRC-1 alone.

The spike's outcome (2026-10-09, PR0's tree, M2 Max, macOS 26.5.1): V0 and
V2 hold and V1 FAILS — the Linear-tagged half-float frame draws within 0.03
of the untagged one (grey 128: 127.98 against 128). The control does not
move, so the instrument cannot be shown to see how the layer READS a buffer,
and PV — the K3/K6 editor-preview row with `capture DIR` / `compare DIR` —
was not built (`designs/precision.md`, PR0). The instrument does see the
layer's content: the quadrants come out exact, upside down in the texture.
`displayedPixelBuffer()` answers nil for this windowless layer even with
`isReadyForDisplay` true; it is printed, not scored.

Like every probe of the app: embedded Swift compiled against all of
`app/Sources` through `swift_build.py`, `setActivationPolicy(.accessory)` and
never activated, no screen capture and no Screen Recording grant. A build
failure is a scored FAILURE on every row; a locked console is a named skip.
Needs `ffmpeg`, `swiftc` and `core/target/release/libreelcut_core.a`.
"""

import json
import os
import subprocess
import sys

import swift_build

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "preview-display")
PROBE = os.path.join(WORK, "probe")
SOURCES = os.path.join(ROOT, "app", "Sources")

WIDTH, HEIGHT = 640, 360
# The quadrants in the frame the probe's compositor hands out, (R, G, B),
# in reading order: top left, top right, bottom left, bottom right.
QUADRANTS = [("grey64", (64, 64, 64)), ("grey128", (128, 128, 128)),
             ("grey192", (192, 192, 192)), ("colour", (200, 60, 30))]
PAIR_APART = 32       # V0: every pair of quadrants differs by this in some channel
CONTROL_APART = 10    # V1: the mis-tagged grey 128 lands at least this far off V0's
SAME_WITHIN = 2       # V2: every quadrant's mean within this of V0's
VARIANTS = ("bgra8", "half-linear", "half")

passed = failed = skipped = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
    print(f"  {'ok  ' if ok else 'FAIL'} {name}" + (f"\n       {detail}" if detail else ""))


def skip(name, reason):
    global skipped
    skipped += 1
    print(f"  skip {name} — {reason}")


PROBE_SOURCE = r'''
import AppKit
import AVFoundation
import CoreVideo
import Metal
import QuartzCore

NSApplication.shared.setActivationPolicy(.accessory)

let args = CommandLine.arguments
let movieURL = URL(fileURLWithPath: args[1])
let variant = args[2]               // bgra8 | half-linear | half
let width = 640, height = 360

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
}

/// Four flat quadrants, (R, G, B) in reading order.
let quadrants: [(Int, Int, Int)] = [(64, 64, 64), (128, 128, 128), (192, 192, 192), (200, 60, 30)]
func quadrant(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    quadrants[(y < height / 2 ? 0 : 2) + (x < width / 2 ? 0 : 1)]
}

final class ProbeVariant: @unchecked Sendable {
    static var half = false
    static var linear = false
    static var contextAttachments: String = "(no frame composed)"
    static var composed = 0
}

/// The probe's own compositor: it ignores its source frame and hands out the
/// quadrant frame in the variant's format.
final class QuadCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String:
            Int(ProbeVariant.half ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA),
         kCVPixelBufferMetalCompatibilityKey as String: true]
    }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let buffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "probe", code: 1))
            return
        }
        let attached = CVBufferCopyAttachments(buffer, .shouldPropagate) as NSDictionary?
        ProbeVariant.contextAttachments = attached.map { "\($0)" } ?? "none"
        CVPixelBufferLockBaseAddress(buffer, [])
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = quadrant(x, y)
                if ProbeVariant.half {
                    let p = (base + y * row + x * 8).assumingMemoryBound(to: Float16.self)
                    p[0] = Float16(Float(r) / 255); p[1] = Float16(Float(g) / 255)
                    p[2] = Float16(Float(b) / 255); p[3] = 1
                } else {
                    let p = (base + y * row + x * 4).assumingMemoryBound(to: UInt8.self)
                    p[0] = UInt8(b); p[1] = UInt8(g); p[2] = UInt8(r); p[3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        if ProbeVariant.linear {
            CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey,
                                  kCVImageBufferTransferFunction_Linear, .shouldPropagate)
        }
        ProbeVariant.composed += 1
        request.finish(withComposedVideoFrame: buffer)
    }
}

ProbeVariant.half = variant != "bgra8"
ProbeVariant.linear = variant == "half-linear"

var answer: [String: Any] = ["variant": variant]
let asset = AVURLAsset(url: movieURL)
let composition = AVMutableVideoComposition(propertiesOf: asset)
composition.customVideoCompositorClass = QuadCompositor.self
composition.renderSize = CGSize(width: width, height: height)
let item = AVPlayerItem(asset: asset)
item.videoComposition = composition
let player = AVPlayer(playerItem: item)
let playerLayer = AVPlayerLayer(player: player)
playerLayer.videoGravity = .resizeAspect
let root = CALayer()
root.frame = CGRect(x: 0, y: 0, width: width, height: height)
root.backgroundColor = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
root.contentsScale = 1
playerLayer.frame = root.bounds
playerLayer.contentsScale = 1
root.addSublayer(playerLayer)

let started = Date()
while item.status == .unknown, Date().timeIntervalSince(started) < 10 { spin(0.05) }
answer["itemStatus"] = item.status.rawValue
var seekDone = false
player.seek(to: CMTime(value: 1, timescale: 2), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
    seekDone = true
}
while !seekDone, Date().timeIntervalSince(started) < 15 { spin(0.05) }
var displayed = playerLayer.displayedPixelBuffer()
while displayed == nil, Date().timeIntervalSince(started) < 20 {
    spin(0.05)
    displayed = playerLayer.displayedPixelBuffer()
}
spin(0.5)
displayed = playerLayer.displayedPixelBuffer() ?? displayed
answer["seekDone"] = seekDone
answer["readyForDisplay"] = playerLayer.isReadyForDisplay
answer["composed"] = ProbeVariant.composed
answer["contextAttachments"] = ProbeVariant.contextAttachments
answer["videoRect"] = [playerLayer.videoRect.minX, playerLayer.videoRect.minY,
                       playerLayer.videoRect.width, playerLayer.videoRect.height]
if let buffer = displayed {
    let format = CVPixelBufferGetPixelFormatType(buffer)
    answer["displayedFormat"] = String(format: "%08x", format)
    let attached = CVBufferCopyAttachments(buffer, .shouldPropagate) as NSDictionary?
    answer["displayedAttachments"] = attached.map { "\($0)" } ?? "none"
} else {
    answer["displayedFormat"] = NSNull()
}

// The instrument: the tree drawn by CARenderer into a bgra8Unorm texture.
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    print("ANSWER " + "{\"error\":\"no Metal device\"}")
    exit(0)
}
let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
descriptor.usage = [.renderTarget, .shaderRead]
descriptor.storageMode = .shared
let texture = device.makeTexture(descriptor: descriptor)!
let renderer = CARenderer(mtlTexture: texture, options: [
    kCARendererColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    kCARendererMetalCommandQueue: queue,
])
renderer.layer = root
renderer.bounds = root.bounds
for _ in 0..<3 {
    CATransaction.flush()
    renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
    renderer.addUpdate(renderer.bounds)
    renderer.render()
    renderer.endFrame()
    let fence = queue.makeCommandBuffer()!
    fence.commit()
    fence.waitUntilCompleted()
    spin(0.2)
}
var bytes = [UInt8](repeating: 0, count: width * height * 4)
texture.getBytes(&bytes, bytesPerRow: width * 4,
                 from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
/// Each quadrant's per-channel (R, G, B) mean over its middle half, by
/// TEXTURE position in reading order (row 0 the texture's top).
var means: [[Double]] = []
for q in 0..<4 {
    let x0 = (q % 2) * width / 2, y0 = (q / 2) * height / 2
    var sum = [0.0, 0.0, 0.0], n = 0.0
    for y in (y0 + height / 8)..<(y0 + 3 * height / 8) {
        for x in (x0 + width / 8)..<(x0 + 3 * width / 8) {
            let p = (y * width + x) * 4
            sum[0] += Double(bytes[p + 2]); sum[1] += Double(bytes[p + 1]); sum[2] += Double(bytes[p])
            n += 1
        }
    }
    means.append(sum.map { ($0 / n * 100).rounded() / 100 })
}
var magenta = 0
for p in stride(from: 0, to: bytes.count, by: 4)
    where bytes[p + 2] > 200 && bytes[p + 1] < 60 && bytes[p] > 200 { magenta += 1 }
answer["means"] = means
answer["magenta"] = magenta
answer["corner"] = [Int(bytes[2]), Int(bytes[1]), Int(bytes[0]), Int(bytes[3])]
let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER ".data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
'''


def make_movie():
    os.makedirs(WORK, exist_ok=True)
    movie = os.path.join(WORK, "drive.mov")
    if not os.path.exists(movie):
        result = subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-f", "lavfi",
             "-i", f"testsrc2=size={WIDTH}x{HEIGHT}:rate=30", "-t", "2",
             "-c:v", "h264", "-pix_fmt", "yuv420p", movie], capture_output=True, text=True)
        if result.returncode != 0:
            return None, f"ffmpeg failed: {result.stderr.strip()[:300]}"
    return movie, None


def build_probe():
    """`preview_refresh_probe.py`'s `build_probe`: the whole of `app/Sources`
    and this `main.swift` through `swift_build.build`. (binary, None) or
    (None, why)."""
    os.makedirs(PROBE, exist_ok=True)
    binary = os.path.join(PROBE, "displayprobe")
    entry = os.path.join(PROBE, "main.swift")
    if not os.path.exists(entry) or open(entry).read() != PROBE_SOURCE:
        with open(entry, "w") as f:
            f.write(PROBE_SOURCE)
    sources = sorted(os.path.join(SOURCES, name) for name in os.listdir(SOURCES)
                     if name.endswith(".swift") and name != "main.swift")
    try:
        built = swift_build.build(sources=sources + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        tail = error.diagnostics[-4:]
        return None, (f"swiftc exited {error.rc if error.rc is not None else 'before running'}: "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    print(f"probe: {binary} ({'up to date' if built.reused else f'built in {built.seconds:.1f} s'})")
    return binary, None


def run_probe(binary, *arguments):
    if binary is None:
        return None, "the probe did not build"
    try:
        result = subprocess.run([binary, *arguments], capture_output=True, text=True,
                                timeout=120, cwd=PROBE)
    except subprocess.TimeoutExpired:
        return None, "the probe timed out (120 s)"
    for line in result.stdout.splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {result.returncode}): {result.stderr.strip()[-300:]}"


def console_locked():
    """Host state is a proof input (`recording_proof.py`): a locked console
    displays nothing in any layer, so every row is skipped BY NAME."""
    out = subprocess.run(["ioreg", "-n", "Root", "-d1", "-a"], capture_output=True, text=True).stdout
    marker = out.find("<key>IOConsoleLocked</key>")
    return marker >= 0 and out[marker:marker + 60].find("<true/>") >= 0


def apart(a, b):
    return max(abs(x - y) for x, y in zip(a, b))


def spike():
    print("V0–V2 — can CARenderer see what an AVPlayerLayer displays?")
    names = ("V0 (instrument) 32BGRA frame: no magenta in the video rect, every quadrant pair "
             f">= {PAIR_APART} apart in some channel",
             f"V1 (control, must differ) 64RGBAHalf tagged Linear: grey 128 >= {CONTROL_APART} "
             "levels off V0's",
             f"V2 64RGBAHalf untagged: every quadrant within ±{SAME_WITHIN} of V0's")
    if console_locked():
        for name in names:
            skip(name, "the console is locked, and a locked console displays nothing in any layer")
        return
    movie, why = make_movie()
    binary, build_error = build_probe() if movie else (None, why)
    answers = {}
    for variant in VARIANTS:
        answer, error = run_probe(binary, movie, variant) if binary else (None, build_error)
        answers[variant] = answer if answer is not None else {"error": error}
        print(f"  {variant}: {json.dumps(answers[variant], sort_keys=True)}")
    v0, v1, v2 = (answers[v] for v in VARIANTS)

    def means(a):
        return a.get("means") if isinstance(a.get("means"), list) else None

    m0, m1, m2 = means(v0), means(v1), means(v2)
    if m0 is None:
        check(names[0], False, v0.get("error", "no means"))
    else:
        pairs = [(i, j, apart(m0[i], m0[j])) for i in range(4) for j in range(i + 1, 4)]
        ok = v0.get("magenta") == 0 and all(d >= PAIR_APART for _, _, d in pairs)
        check(names[0], ok, f"magenta {v0.get('magenta')}; quadrant means {m0}; "
                            f"smallest pair apart {min(d for _, _, d in pairs):.2f}")
    if m0 is None or m1 is None:
        check(names[1], False, v1.get("error", "no means for V0 or V1"))
    else:
        # The texture's quadrant that holds grey 128 is found in V0's own
        # picture: the instrument's rows run bottom-up (CARenderer draws in
        # the layer's own geometry), so reading order is not texture order.
        grey = min(range(4), key=lambda i: apart(m0[i], QUADRANTS[1][1]))
        d = apart(m1[grey], m0[grey])
        check(names[1], d >= CONTROL_APART,
              f"grey 128 (texture quadrant {grey}) V1 {m1[grey]} against V0 {m0[grey]}: {d:.2f}")
    if m0 is None or m2 is None:
        check(names[2], False, v2.get("error", "no means for V0 or V2"))
    else:
        d = max(apart(a, b) for a, b in zip(m2, m0))
        check(names[2], d <= SAME_WITHIN, f"V2 {m2} against V0 {m0}: largest {d:.2f}")


def main():
    args = sys.argv[1:]
    if args != ["--rows", "spike"]:
        sys.exit(__doc__)
    spike()
    total = passed + failed
    print(f"\n{passed}/{total} checks passed" + (f", {skipped} skipped by name" if skipped else ""))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
