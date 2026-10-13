// tools/proof/media_less_playback_probe.swift — the in-process instrument
// behind `media_less_playback_probe.py` (road map 10 §10.8). Compiled with
// every file in `app/Sources` but `main.swift` over `harness/build.sh`'s
// swiftc line, copied in as `main.swift`, with the app's `Fonts`,
// `Blank.mp4` and a `default.metallib` of the app's own shader beside it.
//
//     media_less_playback_probe <graphic> <text> <shape> <image> <empty>
//
// Each argument is a `.framejob` package. Each is opened in a real editor
// window, as the app opens one (`read`, `fileURL` BEFORE
// `makeWindowControllers()` so `startGraphicStore()` finds `graphics/`), and
// the editor's OWN player is read: its item, the Play/Pause validator, the
// transport, the playhead, and `AVPlayerLayer.displayedPixelBuffer()` as a
// 40 × 40-grid mean (`preview_refresh_probe.py`'s `sample()`). The answer is
// one line, `ANSWER <json>`, keyed by fixture name.
import AppKit
import AVFoundation

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
NSApplication.shared.setActivationPolicy(.accessory)
// Preview Quality pinned to Full in the argument domain, so a stored Half
// cannot halve the buffer this probe measures.
UserDefaults.standard.setVolatileDomain(
    ["FrameJobPreviewQuality": 0], forName: UserDefaults.argumentDomain)

/// The displayed buffer's 40 × 40 grid: the mean of (r + g + b) / 3 a pixel
/// in integers, each channel 0…255 — a 32BGRA buffer's bytes, or a
/// 64RGBAHalf buffer's halves × 255, rounded (the precision road map's PR1:
/// the compositor's output is 64RGBAHalf) — and the same mean unrounded, with
/// the buffer's fourcc. The means are nil for any other format, which every
/// row reading them scores as a failure.
func gridMean(_ buffer: CVPixelBuffer) -> (format: String, mean: Int?, exact: Double?) {
    let type = CVPixelBufferGetPixelFormatType(buffer)
    let format = String(bytes: [24, 16, 8, 0].map { UInt8((type >> UInt32($0)) & 0xFF) },
                        encoding: .ascii) ?? "\(type)"
    guard type == kCVPixelFormatType_32BGRA || type == kCVPixelFormatType_64RGBAHalf,
        CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
    else { return (format, nil, nil) }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return (format, nil, nil) }
    var sum = 0, exact = 0.0, n = 0
    for y in stride(from: 0, to: h, by: max(h / 40, 1)) {
        for x in stride(from: 0, to: w, by: max(w / 40, 1)) {
            var channels = [0, 0, 0]
            if type == kCVPixelFormatType_32BGRA {
                let p = (base + y * row).assumingMemoryBound(to: UInt8.self) + x * 4
                channels = [Int(p[0]), Int(p[1]), Int(p[2])]
            } else {
                let p = (base + y * row).assumingMemoryBound(to: Float16.self) + x * 4
                channels = (0..<3).map { Int((Float(p[$0]) * 255).rounded()) }
            }
            sum += (channels[0] + channels[1] + channels[2]) / 3
            exact += Double(channels[0] + channels[1] + channels[2]) / 3
            n += 1
        }
    }
    return (format, sum / max(n, 1), exact / Double(max(n, 1)))
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

let args = CommandLine.arguments
guard args.count == 6 else {
    print("usage: media_less_playback_probe <graphic> <text> <shape> <image> <empty>")
    exit(2)
}

/// Every finding `isValid` reports, as text (`preview_validity_probe.py`'s).
final class Findings: NSObject, AVVideoCompositionValidationHandling {
    var list: [String] = []
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidValueForKey key: String) -> Bool { list.append("invalid value \(key)"); return true }
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingEmptyTimeRange r: CMTimeRange) -> Bool { list.append("empty range at \(r.start.value)/\(r.start.timescale)"); return true }
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidTimeRangeIn i: any AVVideoCompositionInstructionProtocol) -> Bool { list.append("invalid instruction range"); return true }
    func videoComposition(_ c: AVVideoComposition, shouldContinueValidatingAfterFindingInvalidTrackIDIn i: any AVVideoCompositionInstructionProtocol, layerInstruction: AVVideoCompositionLayerInstruction, asset: AVAsset) -> Bool { list.append("invalid track id"); return true }
}

/// One opened document and the editor over it.
final class Opened {
    let document: ProjectDocument
    let editor: EditorViewController
    let layer: AVPlayerLayer
    let player: AVPlayer

    init(_ path: String) {
        let url = URL(fileURLWithPath: path)
        document = ProjectDocument()
        try! document.read(from: url, ofType: ProjectDocument.projectTypeIdentifier)
        document.fileURL = url
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        editor = document.windowControllers.first!.contentViewController as! EditorViewController
        layer = editor.playback.playerLayer
        player = layer.player!
        spin(3)
    }

    /// What the layer displays and where the transport rests, captured on
    /// SETTLE: the layer is polled for a displayed buffer for up to 3 s.
    func sample() -> [String: Any] {
        let started = Date()
        var buffer = layer.displayedPixelBuffer()
        while buffer == nil, Date().timeIntervalSince(started) < 3 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
            buffer = layer.displayedPixelBuffer()
        }
        return state(buffer)
    }

    /// A frame the item composes WHILE PLAYING. `displayedPixelBuffer()`
    /// answers nil for a playing layer — media or not, measured — so the
    /// frame is read from an `AVPlayerItemVideoOutput` added to the item for
    /// the run: the same item, the same video composition, the same
    /// compositor. Polled up to 0.3 s for the item time now.
    func playingSample(_ output: AVPlayerItemVideoOutput) -> [String: Any] {
        let started = Date()
        var buffer: CVPixelBuffer?
        repeat {
            let now = output.itemTime(forHostTime: CACurrentMediaTime())
            buffer = output.copyPixelBuffer(forItemTime: now, itemTimeForDisplay: nil)
            if buffer == nil {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        } while buffer == nil && Date().timeIntervalSince(started) < 0.3
        return state(buffer)
    }

    func state(_ buffer: CVPixelBuffer?) -> [String: Any] {
        var s: [String: Any] = [
            "playhead": document.playhead,
            "playerTicks": CompositionBuilder.ticks(player.currentTime()),
            "rate": player.rate,
            "item": player.currentItem != nil,
        ]
        if let buffer = buffer {
            let grid = gridMean(buffer)
            s["format"] = grid.format
            if let mean = grid.mean {
                s["size"] = [CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer)]
                s["mean"] = mean
                s["meanExact"] = grid.exact
            }
        }
        return s
    }

    /// The item the player holds: there, ready, and a valid composition.
    func item() -> [String: Any] {
        let started = Date()
        while let item = player.currentItem, item.status == .unknown,
            Date().timeIntervalSince(started) < 3
        {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard let item = player.currentItem else { return ["item": false] }
        var s: [String: Any] = ["item": true, "ready": item.status == .readyToPlay]
        if let composition = item.videoComposition {
            let findings = Findings()
            s["valid"] = composition.isValid(
                for: item.asset,
                timeRange: CMTimeRange(start: .zero, duration: item.asset.duration),
                validationDelegate: findings)
            s["findings"] = findings.list
        } else {
            s["valid"] = false
            s["findings"] = ["no video composition"]
        }
        return s
    }

    /// Edit ▸ Play/Pause's validator, asked with a menu item of that action.
    func playEnabled() -> Bool {
        let menuItem = NSMenuItem(
            title: "Play", action: #selector(EditorViewController.playPause(_:)),
            keyEquivalent: "")
        return editor.validateUserInterfaceItem(menuItem)
    }

    /// Play (or run at `rate`) for 1.2 s from where the playhead is.
    func run(rate: Float? = nil) -> [String: Any] {
        let from = document.playhead
        if let rate = rate { editor.playback.setRate(rate) } else { editor.playback.play() }
        spin(1.2)
        var s: [String: Any] = [
            "from": from, "playhead": document.playhead, "rate": player.rate,
            "advanced": Double(document.playhead - from) / Double(ReelTime.ticks(seconds: 1)),
        ]
        editor.playback.pause()
        spin(0.3)
        s["rateAfterPause"] = player.rate
        return s
    }

    func move(_ seconds: Double) -> [String: Any] {
        editor.setPlayhead(ReelTime.ticks(seconds: seconds))
        spin(1.5)
        var s = sample()
        s["expected"] = ReelTime.ticks(seconds: seconds)
        return s
    }

    func edit(_ ops: [ReelOp]) -> [String: Any] {
        document.applyEdit("Probe", ops)
        spin(1.5)
        return sample()
    }
}

func opacity(_ clip: UInt32, _ value: Double) -> ReelOp {
    .setVideo(clips: [clip], patch: VideoPatch(opacity: value))
}

/// The rows every media-less fixture answers (F·1 to F·6), and for the
/// graphic G·7 to G·9.
func mediaLess(_ path: String, graphic: Bool) -> [String: Any] {
    let o = Opened(path)
    var a: [String: Any] = [:]
    a["item"] = o.item()
    a["opened"] = o.sample()
    a["playEnabled"] = o.playEnabled()
    a["play"] = o.run()
    a["at05"] = o.move(0.5)
    a["at25"] = o.move(2.5)
    let clip = o.document.editedProject.snapshot.clips.first?.id ?? 2
    let before = o.editor.playback.builtPlanJSON
    a["opacity0"] = o.edit([opacity(clip, 0)])
    a["opacity1"] = o.edit([opacity(clip, 1)])
    a["samePlan"] = before != nil && before == o.editor.playback.builtPlanJSON
    if graphic {
        _ = o.move(0)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        o.player.currentItem?.add(output)
        o.editor.playback.play()
        spin(0.3)
        let first = o.playingSample(output)
        spin(1.0)
        let second = o.playingSample(output)
        o.editor.playback.pause()
        o.player.currentItem?.remove(output)
        spin(0.3)
        a["playing"] = [first, second]
        _ = o.move(0)
        a["rate2"] = o.run(rate: 2)
        o.editor.setPlayhead(ReelTime.ticks(seconds: 0.5))
        spin(0.5)
        o.editor.setInPoint(nil)
        o.editor.setPlayhead(ReelTime.ticks(seconds: 2.0))
        spin(0.5)
        o.editor.setOutPoint(nil)
        o.editor.toggleLoop(nil)
        o.editor.setPlayhead(ReelTime.ticks(seconds: 1.5))
        spin(1.0)
        let from = o.document.playhead
        o.editor.playback.play()
        spin(1.2)
        a["loop"] = [
            "from": from, "playhead": o.document.playhead, "rate": o.player.rate,
            "range": o.editor.playback.loopRange.map { [$0.start, $0.duration] } ?? [],
        ] as [String: Any]
        o.editor.playback.pause()
        o.editor.clearInOutRange(nil)
        o.editor.toggleLoop(nil)
        spin(0.3)
    }
    o.document.close()
    spin(0.5)
    return a
}

/// The CONTROL: an empty timeline, then Insert ▸ Shape, then undo.
func empty(_ path: String) -> [String: Any] {
    let o = Opened(path)
    var a: [String: Any] = [:]
    a["item"] = o.player.currentItem != nil
    a["play"] = o.run()
    a["playEnabled"] = o.playEnabled()
    o.editor.addShapeClipAtPlayhead(nil)
    spin(2)
    a["inserted"] = [
        "clips": o.document.editedProject.snapshot.clips.count,
        "item": o.player.currentItem != nil,
    ] as [String: Any]
    a["insertedPlay"] = o.run()
    o.document.undoManager?.undo()
    spin(2)
    a["undone"] = [
        "clips": o.document.editedProject.snapshot.clips.count,
        "item": o.player.currentItem != nil,
        "playEnabled": o.playEnabled(),
    ] as [String: Any]
    o.document.close()
    spin(0.5)
    return a
}

var answer: [String: Any] = [:]
answer["graphic"] = mediaLess(args[1], graphic: true)
answer["text"] = mediaLess(args[2], graphic: false)
answer["shape"] = mediaLess(args[3], graphic: false)
answer["image"] = mediaLess(args[4], graphic: false)
answer["empty"] = empty(args[5])

let data = try! JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
FileHandle.standardOutput.write("ANSWER ".data(using: .utf8)! + data + "\n".data(using: .utf8)!)
exit(0)
