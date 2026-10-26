// The camera-recording spike's probe — road map "camera-recording", CR0 (spec §11 CAM-2).
//
//     camera-spike-probe <mode> <work-dir> <job.json>
//
// One mode per process; ONE JSON line on stdout. Modes: devices, grant, session, write, mic,
// screen, pause, preview, virtual, aimed, analyze. Compiled AS main.swift through
// `swift_build.build` with nothing from app/Sources: every type is prefixed `Spike` and every
// function `spike`, so `swift_build.py typecheck` beside app/Sources has no clash.
//
// Every wait is bounded. No mode calls `requestAccess` but `grant` with `"ask": true`, and no
// mode ever asks for Screen Recording. A mode reads the camera and microphone status BEFORE any
// `AVCaptureDeviceInput` exists (that initializer prompts on its own), and every mode that
// touches ScreenCaptureKit reads `CGPreflightScreenCaptureAccess()` before any
// `SCShareableContent` or `SCStream` call; without the grant it answers `skipped`, naming the
// responsible process. Host times are seconds of `mach_absolute_time`, the clock
// `CACurrentMediaTime` and `CMClockGetHostTimeClock` read.

import AVFoundation
import AppKit
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import QuartzCore
import ScreenCaptureKit

// MARK: - plumbing

var spikeTimebase = mach_timebase_info_data_t()
_ = mach_timebase_info(&spikeTimebase)
var spikeAppUp = false

func spikeHost(_ ticks: UInt64) -> Double {
    Double(ticks) * Double(spikeTimebase.numer) / Double(spikeTimebase.denom) / 1_000_000_000
}

func spikeNow() -> Double { spikeHost(mach_absolute_time()) }

func spikeMs(_ seconds: Double?) -> Any {
    guard let seconds, seconds.isFinite else { return NSNull() }
    return (seconds * 1_000_000).rounded() / 1000
}

func spikeNum(_ value: Double?) -> Any {
    guard let value, value.isFinite else { return NSNull() }
    return value
}

func spikeClean(_ value: Any) -> Any {
    if let d = value as? [String: Any] { return d.mapValues { spikeClean($0) } }
    if let a = value as? [Any] { return a.map { spikeClean($0) } }
    if let x = value as? Double { return x.isFinite ? x : NSNull() }
    if let x = value as? CGFloat { return Double(x).isFinite ? Double(x) : NSNull() }
    return value
}

func spikeEmit(_ object: [String: Any]) -> Never {
    let clean = spikeClean(object)
    let data = (try? JSONSerialization.data(withJSONObject: clean, options: [.sortedKeys]))
        ?? Data("{\"outcome\":\"failed\",\"reason\":\"the answer was not JSON\"}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

func spikeSpin(_ seconds: Double, until condition: () -> Bool) -> Bool {
    let deadline = spikeNow() + seconds
    while !condition() {
        if spikeNow() >= deadline { return false }
        if spikeAppUp {
            if let event = NSApp.nextEvent(
                matching: .any, until: Date(timeIntervalSinceNow: 0.004), inMode: .default,
                dequeue: true)
            {
                NSApp.sendEvent(event)
            }
        } else {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.004))
        }
    }
    return true
}

func spikeWait(_ seconds: Double) { _ = spikeSpin(seconds) { false } }

func spikeFourCC(_ code: UInt32) -> String {
    let bytes = [UInt8(code >> 24 & 0xff), UInt8(code >> 16 & 0xff), UInt8(code >> 8 & 0xff),
                 UInt8(code & 0xff)]
    if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
    }
    return "\(code)"
}

func spikeCPUSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
}

func spikeRSS() -> Int {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Int(info.resident_size) : -1
}

/// Runs a tool with a hard bound; nil when it does not answer in time.
func spikeRun(_ path: String, _ args: [String], seconds: Double = 10) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let deadline = spikeNow() + seconds
    var data = Data()
    let handle = pipe.fileHandleForReading
    while process.isRunning && spikeNow() < deadline {
        usleep(5000)
    }
    if process.isRunning { process.terminate(); return nil }
    data.append(handle.readDataToEndOfFile())
    return String(data: data, encoding: .utf8)
}

/// `ps` time ("[[dd-]hh:]mm:ss.ss") as seconds.
func spikeParseCPUTime(_ text: String) -> Double? {
    var days = 0.0
    var rest = Substring(text)
    if let dash = rest.firstIndex(of: "-") {
        days = Double(rest[..<dash]) ?? 0
        rest = rest[rest.index(after: dash)...]
    }
    var total = 0.0
    for part in rest.split(separator: ":") {
        guard let value = Double(part) else { return nil }
        total = total * 60 + value
    }
    return total + days * 86400
}

/// Every process whose command's last component contains "camera" (case-insensitive), with
/// its cumulative CPU seconds, through a bounded `ps`.
func spikeCameraDaemons() -> [String: Double] {
    guard let text = spikeRun("/bin/ps", ["-A", "-o", "pid=,time=,comm="], seconds: 10) else {
        return [:]
    }
    var out: [String: Double] = [:]
    for line in text.split(separator: "\n") {
        let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard fields.count == 3 else { continue }
        let name = (String(fields[2]) as NSString).lastPathComponent
        guard name.lowercased().contains("camera"),
            let cpu = spikeParseCPUTime(String(fields[1]))
        else { continue }
        out["\(name)[\(fields[0])]"] = cpu
    }
    return out
}

final class SpikeBox<T>: @unchecked Sendable {
    var value: T?
}

func spikeBlocking<T>(_ seconds: Double, _ body: @escaping () async throws -> T) -> Result<T, Error>? {
    let box = SpikeBox<Result<T, Error>>()
    let done = DispatchSemaphore(value: 0)
    let work = SpikeBox<() async throws -> T>()
    work.value = body
    Task.detached {
        do { box.value = .success(try await work.value!()) } catch { box.value = .failure(error) }
        done.signal()
    }
    return done.wait(timeout: .now() + seconds) == .success ? box.value : nil
}

// MARK: - the responsible process and the grants

typealias SpikeResponsibleFn = @convention(c) (pid_t) -> pid_t

func spikeProcName(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    let n = proc_name(pid, &buffer, UInt32(buffer.count))
    return n > 0 ? String(cString: buffer) : "?"
}

func spikeProcPath(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    return n > 0 ? String(cString: buffer) : "?"
}

func spikeResponsible() -> [String: Any] {
    let pid = getpid()
    guard let lib = dlopen("/usr/lib/system/libquarantine.dylib", RTLD_NOW),
        let symbol = dlsym(lib, "responsibility_get_pid_responsible_for_pid")
    else {
        return ["pid": Int(pid), "error": "responsibility_get_pid_responsible_for_pid not found"]
    }
    let call = unsafeBitCast(symbol, to: SpikeResponsibleFn.self)
    let r = call(pid)
    return ["pid": Int(pid), "name": spikeProcName(pid), "responsiblePid": Int(r),
            "responsibleName": spikeProcName(r), "responsiblePath": spikeProcPath(r)]
}

func spikeStatus(_ type: AVMediaType) -> String {
    switch AVCaptureDevice.authorizationStatus(for: type) {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
}

func spikeSkipped(_ reason: String, _ extra: [String: Any] = [:]) -> [String: Any] {
    var out = extra
    out["outcome"] = "skipped"
    out["reason"] = reason
    return out
}

/// nil when every grant the mode needs is held; else the `skipped` answer naming the
/// responsible process. Reads status only: it never asks.
func spikeGate(video: Bool, audio: Bool, screen: Bool) -> [String: Any]? {
    let who = spikeResponsible()
    let name = who["responsibleName"] as? String ?? "?"
    if screen && !CGPreflightScreenCaptureAccess() {
        return spikeSkipped(
            "Screen Recording is not granted to \(name), the probe's responsible process "
                + "(CGPreflightScreenCaptureAccess false); the spike never asks for it",
            ["responsible": who])
    }
    if video {
        let status = spikeStatus(.video)
        if status != "authorized" {
            return spikeSkipped(
                "the Camera grant is \(status) for \(name), the probe's responsible process; "
                    + "run camera_spike.py --ask once from that terminal",
                ["responsible": who])
        }
    }
    if audio {
        let status = spikeStatus(.audio)
        if status != "authorized" {
            return spikeSkipped(
                "the Microphone grant is \(status) for \(name), the probe's responsible process; "
                    + "run camera_spike.py --ask once from that terminal",
                ["responsible": who])
        }
    }
    return nil
}

// MARK: - devices and formats

func spikeDevices(continuity: Bool) -> [AVCaptureDevice] {
    var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external]
    if continuity { types.append(.continuityCamera) }
    return AVCaptureDevice.DiscoverySession(
        deviceTypes: types, mediaType: .video, position: .unspecified
    ).devices
}

func spikeMicrophones() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(
        deviceTypes: [.microphone], mediaType: .audio, position: .unspecified
    ).devices
}

func spikeMaxRange(_ format: AVCaptureDevice.Format) -> AVFrameRateRange? {
    format.videoSupportedFrameRateRanges.max { $0.maxFrameRate < $1.maxFrameRate }
}

func spikeFormatInfo(_ format: AVCaptureDevice.Format, index: Int) -> [String: Any] {
    let desc = format.formatDescription
    let dims = CMVideoFormatDescriptionGetDimensions(desc)
    return [
        "index": index,
        "subtype": spikeFourCC(CMFormatDescriptionGetMediaSubType(desc)),
        "width": Int(dims.width), "height": Int(dims.height),
        "rates": format.videoSupportedFrameRateRanges.map { [$0.minFrameRate, $0.maxFrameRate] },
        "maxRate": spikeMaxRange(format)?.maxFrameRate ?? 0,
        "colorSpaces": format.supportedColorSpaces.map { $0.rawValue },
    ]
}

func spikeDeviceInfo(_ device: AVCaptureDevice) -> [String: Any] {
    let formats = device.formats
    let active = formats.firstIndex { $0 == device.activeFormat }
    return [
        "uniqueID": device.uniqueID, "localizedName": device.localizedName,
        "modelID": device.modelID, "deviceType": device.deviceType.rawValue,
        "isContinuityCamera": device.isContinuityCamera, "manufacturer": device.manufacturer,
        "transportType": spikeFourCC(UInt32(bitPattern: device.transportType)),
        "isConnected": device.isConnected, "isSuspended": device.isSuspended,
        "activeFormat": active.map { $0 as Any } ?? NSNull(),
        "formats": formats.enumerated().map { spikeFormatInfo($1, index: $0) },
    ]
}

func spikeCamera(_ job: [String: Any]) -> AVCaptureDevice? {
    let want = job["camera"] as? String ?? ""
    let all = spikeDevices(continuity: true)
    return all.first { $0.uniqueID == want }
        ?? all.first { !want.isEmpty && $0.localizedName.localizedCaseInsensitiveContains(want) }
}

func spikeMicrophone(_ job: [String: Any]) -> AVCaptureDevice? {
    guard let want = job["mic"] as? String, !want.isEmpty else { return nil }
    let all = spikeMicrophones()
    return all.first { $0.uniqueID == want }
        ?? all.first { $0.localizedName.localizedCaseInsensitiveContains(want) }
}

/// Puts `index`'s format on the device and, with `lock`, both frame durations at its maximum
/// rate. Answers an error sentence or nil.
/// `owned`: the caller already holds the device's configuration lock (SpikeCamera's hold), so
/// it is neither taken nor released here.
func spikeApplyFormat(_ device: AVCaptureDevice, index: Int?, lock: Bool, owned: Bool = false) -> String? {
    guard let index else { return nil }
    guard index >= 0, index < device.formats.count else { return "the device has no format \(index)" }
    if !owned {
        do { try device.lockForConfiguration() } catch { return "lockForConfiguration threw: \(error)" }
    }
    let format = device.formats[index]
    if device.activeFormat != format { device.activeFormat = format }
    if lock, let best = spikeMaxRange(format) {
        device.activeVideoMinFrameDuration = best.minFrameDuration
        device.activeVideoMaxFrameDuration = best.minFrameDuration
    }
    if !owned { device.unlockForConfiguration() }
    return nil
}

func spikeReadBack(_ device: AVCaptureDevice) -> [String: Any] {
    let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
    let minD = device.activeVideoMinFrameDuration.seconds
    let maxD = device.activeVideoMaxFrameDuration.seconds
    return [
        "activeFormat": device.formats.firstIndex { $0 == device.activeFormat } ?? -1,
        "width": Int(dims.width), "height": Int(dims.height),
        "minFrameDuration": spikeNum(minD), "maxFrameDuration": spikeNum(maxD),
        "maxRateNow": spikeNum(minD > 0 ? 1 / minD : nil),
        "minRateNow": spikeNum(maxD > 0 ? 1 / maxD : nil),
    ]
}

/// The rate a run is judged at: the locked format's maximum, else the read-back maximum.
func spikeTargetRate(_ device: AVCaptureDevice) -> Double {
    let minD = device.activeVideoMinFrameDuration.seconds
    return minD > 0 ? 1 / minD : (spikeMaxRange(device.activeFormat)?.maxFrameRate ?? 0)
}

func spikeToHost(_ time: CMTime, from clock: CMClock?) -> Double? {
    guard time.isValid, let clock else { return nil }
    let converted = CMSyncConvertTime(time, from: clock, to: CMClockGetHostTimeClock())
    guard converted.isValid else { return nil }
    return converted.seconds
}

func spikeClockIsHost(_ clock: CMClock?) -> Bool {
    guard let clock else { return false }
    return CFEqual(clock, CMClockGetHostTimeClock())
}

// MARK: - luma

/// Mean Rec. 709 luma (8-bit) of a BGRA buffer over a rect (pixels, top-left origin),
/// sampled every `step` pixels.
func spikeLuma(_ buffer: CVPixelBuffer, rect: CGRect? = nil, step: Int = 4) -> Double? {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    let area = (rect ?? CGRect(x: 0, y: 0, width: width, height: height))
        .intersection(CGRect(x: 0, y: 0, width: width, height: height))
    guard !area.isNull, area.width >= 1, area.height >= 1 else { return nil }
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    var total = 0.0
    var count = 0
    var y = Int(area.minY)
    while y < Int(area.maxY) {
        var x = Int(area.minX)
        while x < Int(area.maxX) {
            let p = bytes + y * row + x * 4
            total += 0.0722 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.2126 * Double(p[2])
            count += 1
            x += step
        }
        y += step
    }
    return count > 0 ? total / Double(count) : nil
}

// MARK: - capture delegates

final class SpikeFileDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    let lock = NSLock()
    var starts: [(url: String, at: Double, pts: CMTime)] = []
    var finishes: [(url: String, at: Double, error: String?, success: Bool)] = []

    func fileOutput(
        _ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, startPTS: CMTime,
        from connections: [AVCaptureConnection]
    ) {
        let at = spikeNow()
        lock.lock(); starts.append((fileURL.path, at, startPTS)); lock.unlock()
    }

    func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection], error: Error?
    ) {
        let at = spikeNow()
        let ns = error as NSError?
        let success = error == nil
            || (ns?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        lock.lock()
        finishes.append((outputFileURL.path, at, error.map { "\($0)" }, success))
        lock.unlock()
    }

    func start(for path: String) -> (at: Double, pts: CMTime)? {
        lock.lock(); defer { lock.unlock() }
        return starts.first { $0.url == path }.map { ($0.at, $0.pts) }
    }

    func finish(for path: String) -> (at: Double, error: String?, success: Bool)? {
        lock.lock(); defer { lock.unlock() }
        return finishes.first { $0.url == path }.map { ($0.at, $0.error, $0.success) }
    }
}

/// An `AVCaptureVideoDataOutput`'s delegate. It counts every delivered and dropped buffer
/// (arrival host times kept), measures luma when asked, and feeds an `AVAssetWriter` while
/// armed, starting the writer's session at the first buffer's PTS.
final class SpikeFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let lock = NSLock()
    var arrivals: [Double] = []
    var dropped = 0
    var lumas: [Double] = []
    var measureLuma = false
    var writer: AVAssetWriter?
    var input: AVAssetWriterInput?
    var armed = false
    var firstPTS: CMTime?
    var firstAppendAt: Double?
    var appended = 0
    var notReady = 0
    var failedAppends = 0

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let at = spikeNow()
        var luma: Double? = nil
        if measureLuma, let image = CMSampleBufferGetImageBuffer(sampleBuffer) {
            luma = spikeLuma(image, step: 16)
        }
        lock.lock(); defer { lock.unlock() }
        arrivals.append(at)
        if let luma { lumas.append(luma) }
        guard armed, let writer, let input else { return }
        if firstPTS == nil {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: pts)
            firstPTS = pts
            firstAppendAt = at
        }
        if input.isReadyForMoreMediaData {
            if input.append(sampleBuffer) { appended += 1 } else { failedAppends += 1 }
        } else {
            notReady += 1
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock(); dropped += 1; lock.unlock()
    }

    func read<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
}

/// What the writer path writes in: HEVC if the writer can apply it at these dimensions, else
/// H.264. (`availableVideoCodecTypes` is unavailable on macOS; this is its stand-in.)
func spikeCodecs(width: Int, height: Int) -> (hevc: Bool, h264: Bool) {
    let probe = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
        "camera-spike-codec-\(getpid()).mov")
    try? FileManager.default.removeItem(at: probe)
    guard let writer = try? AVAssetWriter(outputURL: probe, fileType: .mov) else {
        return (false, false)
    }
    func can(_ codec: AVVideoCodecType) -> Bool {
        writer.canApply(
            outputSettings: [AVVideoCodecKey: codec, AVVideoWidthKey: width,
                             AVVideoHeightKey: height], forMediaType: .video)
    }
    return (can(.hevc), can(.h264))
}

func spikeMakeWriter(url: URL, width: Int, height: Int, codec: AVVideoCodecType) throws
    -> (AVAssetWriter, AVAssetWriterInput)
{
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height])
    input.expectsMediaDataInRealTime = true
    guard writer.canAdd(input) else {
        throw NSError(domain: "spike", code: 1, userInfo: [NSLocalizedDescriptionKey: "canAdd false"])
    }
    writer.add(input)
    guard writer.startWriting() else {
        throw writer.error ?? NSError(domain: "spike", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "startWriting false"])
    }
    return (writer, input)
}

/// Disarms the feed and finishes its writer; answers (seconds from the call to the
/// completion, the writer's status, an error).
func spikeFinishWriter(_ feed: SpikeFeed, bound: Double = 15) -> (Double?, String, String?) {
    let called = spikeNow()
    let (writer, input) = feed.read { () -> (AVAssetWriter?, AVAssetWriterInput?) in
        feed.armed = false
        return (feed.writer, feed.input)
    }
    guard let writer, let input else { return (nil, "none", "no writer") }
    if feed.read({ feed.firstPTS }) == nil {
        writer.cancelWriting()
        return (nil, "cancelled", "no buffer was appended")
    }
    input.markAsFinished()
    let done = SpikeBox<Double>()
    writer.finishWriting { done.value = spikeNow() }
    _ = spikeSpin(bound) { done.value != nil }
    let status: String
    switch writer.status {
    case .completed: status = "completed"
    case .failed: status = "failed"
    case .cancelled: status = "cancelled"
    case .writing: status = "writing"
    default: status = "unknown"
    }
    return (done.value.map { $0 - called }, status, writer.error.map { "\($0)" })
}

// MARK: - a camera session

final class SpikeCamera {
    let device: AVCaptureDevice
    let session = AVCaptureSession()
    var movie: AVCaptureMovieFileOutput?
    var data: AVCaptureVideoDataOutput?
    let files = SpikeFileDelegate()
    let feed = SpikeFeed()
    let queue = DispatchQueue(label: "camera-spike.feed")
    var formatError: String?
    var formatHeld = true
    var requested: Int?
    var lock = false
    /// macOS has no `.inputPriority` preset (API_UNAVAILABLE(macos)): a session there re-takes
    /// the device's format at startRunning and at a movie output's startRecording unless the
    /// device stays locked for configuration. So a requested format is held under the lock from
    /// build to stop.
    var holding = false

    init(device: AVCaptureDevice) { self.device = device }

    /// Adds the camera, the outputs asked for, and the format. Throws a sentence.
    func build(movie wantMovie: Bool, data wantData: Bool, pixelFormat: OSType?, format: Int?,
               lock: Bool, extraInputs: [AVCaptureDevice] = []) throws {
        requested = format
        self.lock = lock
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw SpikeError("canAddInput(camera) false") }
        session.addInput(input)
        for extra in extraInputs {
            let more = try AVCaptureDeviceInput(device: extra)
            guard session.canAddInput(more) else { throw SpikeError("canAddInput(\(extra.localizedName)) false") }
            session.addInput(more)
        }
        if wantMovie {
            let output = AVCaptureMovieFileOutput()
            guard session.canAddOutput(output) else { throw SpikeError("canAddOutput(movie) false") }
            session.addOutput(output)
            movie = output
        }
        if wantData {
            let output = AVCaptureVideoDataOutput()
            if let pixelFormat {
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
            }
            output.alwaysDiscardsLateVideoFrames = false
            output.setSampleBufferDelegate(feed, queue: queue)
            guard session.canAddOutput(output) else { throw SpikeError("canAddOutput(data) false") }
            session.addOutput(output)
            data = output
        }
        if format != nil {
            do {
                try device.lockForConfiguration()
                holding = true
            } catch {
                formatError = "lockForConfiguration threw: \(error)"
            }
        }
        formatError = formatError ?? spikeApplyFormat(device, index: format, lock: lock, owned: holding)
    }

    /// Starts the session; re-applies the format if starting moved it. Answers whether it runs.
    func run(warm: Double) -> Bool {
        session.startRunning()
        guard session.isRunning || spikeSpin(5, until: { self.session.isRunning }) else { return false }
        if let requested, device.formats.firstIndex(where: { $0 == device.activeFormat }) != requested {
            formatHeld = false
            formatError = formatError ?? spikeApplyFormat(device, index: requested, lock: lock, owned: holding)
        }
        spikeWait(warm)
        return session.isRunning
    }

    var dims: (Int, Int) {
        let d = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return (Int(d.width), Int(d.height))
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
        if holding {
            device.unlockForConfiguration()
            holding = false
        }
    }
}

struct SpikeError: Error, CustomStringConvertible {
    let description: String
    init(_ text: String) { description = text }
}

/// Sets the movie output's codec on its video connection: HEVC if writable, else H.264.
func spikeSetMovieCodec(_ camera: SpikeCamera) -> [String: Any] {
    guard let movie = camera.movie, let connection = movie.connection(with: .video) else {
        return ["error": "no video connection"]
    }
    let (w, h) = camera.dims
    let codecs = spikeCodecs(width: w, height: h)
    let before = movie.outputSettings(for: connection)
    let codec: AVVideoCodecType? = codecs.hevc ? .hevc : (codecs.h264 ? .h264 : nil)
    if let codec { movie.setOutputSettings([AVVideoCodecKey: codec], for: connection) }
    let after = movie.outputSettings(for: connection)
    return ["hevcWritable": codecs.hevc, "h264Writable": codecs.h264,
            "codecAsked": codec?.rawValue ?? NSNull(),
            "settingsBefore": "\(before)", "settingsAfter": "\(after)"]
}

func spikeJobURL(_ job: [String: Any], _ key: String) -> URL {
    URL(fileURLWithPath: job[key] as? String ?? "/dev/null")
}

// MARK: - modes: devices, grant, session

func spikeModeDevices(_ job: [String: Any]) -> [String: Any] {
    let continuity = job["continuity"] as? Bool ?? true
    let devices = spikeDevices(continuity: continuity)
    let key = Bundle.main.object(forInfoDictionaryKey: "NSCameraUseContinuityCameraDeviceType")
    return [
        "outcome": "ok", "continuityTypeAsked": continuity,
        "plistContinuityKey": key.map { "\($0)" } ?? NSNull(),
        "devices": devices.map(spikeDeviceInfo),
        "systemPreferredCamera": AVCaptureDevice.systemPreferredCamera?.uniqueID ?? NSNull(),
        "microphones": spikeMicrophones().map {
            ["uniqueID": $0.uniqueID, "localizedName": $0.localizedName,
             "transportType": spikeFourCC(UInt32(bitPattern: $0.transportType))]
        },
    ]
}

func spikeModeGrant(_ job: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [
        "outcome": "ok", "responsible": spikeResponsible(),
        "video": spikeStatus(.video), "audio": spikeStatus(.audio),
        "screenPreflight": CGPreflightScreenCaptureAccess(),
    ]
    if job["ask"] as? Bool == true {
        for (key, type) in [("askVideo", AVMediaType.video), ("askAudio", AVMediaType.audio)] {
            let answer = SpikeBox<Bool>()
            AVCaptureDevice.requestAccess(for: type) { answer.value = $0 }
            let answered = spikeSpin(60) { answer.value != nil }
            out[key] = answered ? (answer.value! as Any) : "no answer within 60 s"
        }
        out["videoAfter"] = spikeStatus(.video)
        out["audioAfter"] = spikeStatus(.audio)
    }
    return out
}

func spikeModeSession(_ job: [String: Any]) -> [String: Any] {
    if let skip = spikeGate(video: true, audio: false, screen: false) { return skip }
    guard let device = spikeCamera(job) else { return spikeSkipped("no camera matches \(job["camera"] ?? "")") }
    let seconds = job["seconds"] as? Double ?? 2
    let camera = SpikeCamera(device: device)
    camera.feed.measureLuma = true
    do {
        try camera.build(movie: false, data: true, pixelFormat: kCVPixelFormatType_32BGRA,
                         format: nil, lock: false)
    } catch {
        return ["outcome": "ok", "frames": 0, "black": 0, "error": "\(error)"]
    }
    let started = spikeNow()
    let running = camera.run(warm: 0)
    spikeWait(seconds)
    camera.stop()
    let (arrivals, lumas) = camera.feed.read { (camera.feed.arrivals, camera.feed.lumas) }
    let first = arrivals.first.map { $0 - started }
    return [
        "outcome": "ok", "running": running, "frames": arrivals.count,
        "black": lumas.filter { $0 < 24 }.count,
        "meanLuma": spikeNum(lumas.isEmpty ? nil : lumas.reduce(0, +) / Double(lumas.count)),
        "minLuma": spikeNum(lumas.min()), "maxLuma": spikeNum(lumas.max()),
        "firstFrameAfterStartMs": spikeMs(first), "camera": device.localizedName,
    ]
}

// MARK: - mode: write (W1, W2, W3)

func spikeModeWrite(_ job: [String: Any]) -> [String: Any] {
    if let skip = spikeGate(video: true, audio: false, screen: false) { return skip }
    guard let device = spikeCamera(job) else { return spikeSkipped("no camera matches \(job["camera"] ?? "")") }
    let writerPath = (job["writer"] as? String) == "writer"
    let seconds = job["seconds"] as? Double ?? 5
    let url = spikeJobURL(job, "out")
    try? FileManager.default.removeItem(at: url)
    let camera = SpikeCamera(device: device)
    do {
        try camera.build(movie: !writerPath, data: writerPath,
                         pixelFormat: writerPath ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : nil,
                         format: job["format"] as? Int, lock: job["lock"] as? Bool ?? false)
    } catch {
        return ["outcome": "failed", "reason": "the session did not build: \(error)"]
    }
    var out: [String: Any] = ["outcome": "ok", "camera": device.localizedName,
                              "path": writerPath ? "asset-writer" : "movie-output",
                              "file": url.path]
    guard camera.run(warm: 1.0) else {
        return ["outcome": "failed", "reason": "the session did not run"]
    }
    out["formatHeld"] = camera.formatHeld
    out["formatError"] = camera.formatError ?? NSNull()
    out["readBackBefore"] = spikeReadBack(device)
    let clock = camera.session.synchronizationClock
    out["syncClockIsHost"] = spikeClockIsHost(clock)
    let (w, h) = camera.dims
    let cpu0 = spikeCPUSeconds()
    let called: Double
    var startAt: Double? = nil
    var startPTS = CMTime.invalid
    if writerPath {
        let codecs = spikeCodecs(width: w, height: h)
        out["hevcWritable"] = codecs.hevc
        out["h264Writable"] = codecs.h264
        let codec: AVVideoCodecType = codecs.hevc ? .hevc : .h264
        out["codecAsked"] = codec.rawValue
        do {
            let (writer, input) = try spikeMakeWriter(url: url, width: w, height: h, codec: codec)
            called = spikeNow()
            camera.feed.read {
                camera.feed.writer = writer
                camera.feed.input = input
                camera.feed.armed = true
            }
        } catch {
            camera.stop()
            return ["outcome": "failed", "reason": "the writer did not start: \(error)"]
        }
        _ = spikeSpin(10) { camera.feed.read { camera.feed.firstPTS != nil } }
        camera.feed.read {
            startAt = camera.feed.firstAppendAt
            startPTS = camera.feed.firstPTS ?? .invalid
        }
    } else {
        out["codec"] = spikeSetMovieCodec(camera)
        called = spikeNow()
        camera.movie!.startRecording(to: url, recordingDelegate: camera.files)
        _ = spikeSpin(10) { camera.files.start(for: url.path) != nil }
        if let start = camera.files.start(for: url.path) {
            startAt = start.at
            startPTS = start.pts
        }
    }
    out["didStart"] = startAt != nil
    out["didStartMs"] = spikeMs(startAt.map { $0 - called })
    out["startPTS"] = spikeNum(startPTS.isValid ? startPTS.seconds : nil)
    let host = spikeToHost(startPTS, from: clock)
    out["startPTSHost"] = spikeNum(host)
    out["hostConversion"] = host != nil
    out["startPTSHostMinusCallbackMs"] = spikeMs(host.flatMap { h in startAt.map { h - $0 } })
    out["targetRate"] = spikeTargetRate(device)
    spikeWait(seconds / 2)
    out["readBackRecording"] = spikeReadBack(device)
    spikeWait(seconds / 2)
    let stopCalled = spikeNow()
    if writerPath {
        let (closed, status, error) = spikeFinishWriter(camera.feed)
        out["closeMs"] = spikeMs(closed)
        out["writerStatus"] = status
        out["writerError"] = error ?? NSNull()
        camera.feed.read {
            out["appended"] = camera.feed.appended
            out["notReady"] = camera.feed.notReady
            out["failedAppends"] = camera.feed.failedAppends
            out["droppedCallbacks"] = camera.feed.dropped
        }
    } else {
        camera.movie!.stopRecording()
        _ = spikeSpin(15) { camera.files.finish(for: url.path) != nil }
        let finish = camera.files.finish(for: url.path)
        out["closeMs"] = spikeMs(finish.map { $0.at - stopCalled })
        out["finishError"] = finish?.error ?? NSNull()
        out["finishSuccess"] = finish?.success ?? false
        out["droppedCallbacks"] = NSNull()  // a movie output has no drop callback
    }
    out["recordWallSeconds"] = stopCalled - (startAt ?? called)
    out["cpuSeconds"] = spikeCPUSeconds() - cpu0
    camera.stop()
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    out["bytes"] = size ?? 0
    return out
}

// MARK: - mode: mic (M1, M2)

func spikeModeMic(_ job: [String: Any]) -> [String: Any] {
    if let skip = spikeGate(video: true, audio: true, screen: false) { return skip }
    guard let device = spikeCamera(job) else { return spikeSkipped("no camera matches \(job["camera"] ?? "")") }
    guard let mic = spikeMicrophone(job) else {
        return spikeSkipped("no microphone matches \(job["mic"] ?? "")")
    }
    let shape = job["shape"] as? String ?? "M2"
    let seconds = job["seconds"] as? Double ?? 3
    let video = spikeJobURL(job, "outVideo"), audio = spikeJobURL(job, "outAudio")
    try? FileManager.default.removeItem(at: video)
    try? FileManager.default.removeItem(at: audio)
    let camera = SpikeCamera(device: device)
    var out: [String: Any] = ["outcome": "ok", "shape": shape, "camera": device.localizedName,
                              "microphone": mic.localizedName]
    let audioOut = AVCaptureAudioFileOutput()
    let micFiles = SpikeFileDelegate()
    var micSession: AVCaptureSession? = nil
    do {
        if shape == "M1" {
            try camera.build(movie: true, data: false, pixelFormat: nil, format: nil, lock: false,
                             extraInputs: [mic])
            camera.movie?.connection(with: .audio)?.isEnabled = false
            camera.session.beginConfiguration()
            let can = camera.session.canAddOutput(audioOut)
            out["canAddAudioFileOutput"] = can
            if can { camera.session.addOutput(audioOut) }
            camera.session.commitConfiguration()
            if !can {
                out["note"] = "the camera session cannot hold an AVCaptureAudioFileOutput beside its movie output"
                return out
            }
        } else {
            try camera.build(movie: true, data: false, pixelFormat: nil, format: nil, lock: false)
            let session = AVCaptureSession()
            let input = try AVCaptureDeviceInput(device: mic)
            guard session.canAddInput(input), session.canAddOutput(audioOut) else {
                throw SpikeError("the microphone session cannot hold its input and output")
            }
            session.addInput(input)
            session.addOutput(audioOut)
            micSession = session
        }
    } catch {
        return ["outcome": "failed", "reason": "the sessions did not build: \(error)"]
    }
    micSession?.startRunning()
    guard camera.run(warm: 1.0) else { return ["outcome": "failed", "reason": "the session did not run"] }
    if let micSession, !micSession.isRunning {
        camera.stop()
        return ["outcome": "failed", "reason": "the microphone session did not run"]
    }
    let called = spikeNow()
    camera.movie!.startRecording(to: video, recordingDelegate: camera.files)
    audioOut.startRecording(to: audio, outputFileType: .m4a, recordingDelegate: micFiles)
    _ = spikeSpin(10) {
        camera.files.start(for: video.path) != nil && micFiles.start(for: audio.path) != nil
    }
    spikeWait(seconds)
    camera.movie!.stopRecording()
    audioOut.stopRecording()
    _ = spikeSpin(15) {
        camera.files.finish(for: video.path) != nil && micFiles.finish(for: audio.path) != nil
    }
    let cam = camera.files.start(for: video.path), mi = micFiles.start(for: audio.path)
    let camHost = cam.flatMap { spikeToHost($0.pts, from: camera.session.synchronizationClock) }
    let micHost = mi.flatMap {
        spikeToHost($0.pts, from: (micSession ?? camera.session).synchronizationClock)
    }
    out["cameraDidStartMs"] = spikeMs(cam.map { $0.at - called })
    out["micDidStartMs"] = spikeMs(mi.map { $0.at - called })
    out["cameraStartPTSHost"] = spikeNum(camHost)
    out["micStartPTSHost"] = spikeNum(micHost)
    out["offsetPTSMs"] = spikeMs(camHost.flatMap { c in micHost.map { $0 - c } })
    out["offsetCallbackMs"] = spikeMs(cam.flatMap { c in mi.map { $0.at - c.at } })
    out["micSyncClockIsHost"] = spikeClockIsHost((micSession ?? camera.session).synchronizationClock)
    out["cameraFinish"] = camera.files.finish(for: video.path)?.success ?? false
    out["micFinish"] = micFiles.finish(for: audio.path)?.success ?? false
    out["micFinishError"] = micFiles.finish(for: audio.path)?.error ?? NSNull()
    micSession?.stopRunning()
    camera.stop()
    out["video"] = video.path
    out["audio"] = audio.path
    return out
}

// MARK: - the counter window (S, the screen group)

/// A 4×4 block code redrawn on every callback of its window's own display link. Blocks 0–7
/// carry the code's 8 bits, most significant first, row-major; blocks 8–15 their complement
/// (white = 1). Each code is logged with that callback's `targetTimestamp`: the host time the
/// frame is presented, never the time it was drawn.
final class SpikeCounter: NSObject {
    let window: NSWindow
    let blocks: [CALayer]
    var link: CADisplayLink?
    var counter = 0
    var log: [[Double]] = []  // [code, targetTimestamp, timestamp, drawnAt]
    let side: CGFloat = 128

    override init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let frame = NSRect(x: visible.minX + 48, y: visible.maxY - 48 - side, width: side, height: side)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        var made: [CALayer] = []
        let cell = side / 4
        for i in 0..<16 {
            let layer = CALayer()
            let row = i / 4, col = i % 4
            // Row 0 is the TOP row: AppKit's layer origin is bottom-left.
            layer.frame = CGRect(x: CGFloat(col) * cell, y: side - CGFloat(row + 1) * cell,
                                 width: cell, height: cell)
            layer.backgroundColor = NSColor.black.cgColor
            view.layer?.addSublayer(layer)
            made.append(layer)
        }
        blocks = made
        window.contentView = view
        super.init()
    }

    func start() {
        window.orderFrontRegardless()
        if let view = window.contentView {
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc func tick(_ link: CADisplayLink) {
        counter += 1
        let code = counter & 0xff
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for i in 0..<8 {
            let bit = (code >> (7 - i)) & 1
            blocks[i].backgroundColor = (bit == 1 ? NSColor.white : NSColor.black).cgColor
            blocks[8 + i].backgroundColor = (bit == 1 ? NSColor.black : NSColor.white).cgColor
        }
        CATransaction.commit()
        log.append([Double(code), link.targetTimestamp, link.timestamp, spikeNow()])
    }

    func stop() {
        link?.invalidate()
        link = nil
        window.orderOut(nil)
    }

    /// The window in display points, top-left origin, on the main display.
    var rectTopLeft: [Double] {
        let screen = NSScreen.screens[0].frame
        let f = window.frame
        return [Double(f.minX - screen.minX), Double(screen.maxY - f.maxY), Double(f.width), Double(f.height)]
    }
}

final class SpikeStream: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, SCStreamOutput {
    let lock = NSLock()
    var startDone = false, startError: String? = nil
    var stopDone = false
    var didStartAt: Double? = nil
    var didFinishAt: Double? = nil
    var failure: String? = nil
    var frames: [[Double]] = []  // [pts, arrival, complete]

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.lock(); failure = failure ?? "stream stopped: \(error)"; lock.unlock()
    }
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let at = spikeNow()
        lock.lock(); didStartAt = at; lock.unlock()
    }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        lock.lock(); failure = "recording output failed: \(error)"; lock.unlock()
    }
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let at = spikeNow()
        lock.lock(); didFinishAt = at; lock.unlock()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let at = spikeNow()
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        var complete = 0.0
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            SCFrameStatus(rawValue: raw) == .complete
        {
            complete = 1
        }
        lock.lock(); frames.append([pts, at, complete]); lock.unlock()
    }
    func read<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
}

func spikeShareable() -> (SCShareableContent?, String?) {
    let box = SpikeBox<(SCShareableContent?, String?)>()
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
        box.value = (content, error.map { "\($0)" })
    }
    guard spikeSpin(15, until: { box.value != nil }) else {
        return (nil, "getShareableContent did not answer within 15 s")
    }
    return box.value!
}

/// The main display's SCStream with an SCRecordingOutput into `url` at `fps`, plus a
/// `.screen` stream output; not started.
func spikeScreenStream(url: URL, fps: Int, session: SpikeStream) -> (SCStream?, [String: Any], String?) {
    let (content, error) = spikeShareable()
    guard let content else { return (nil, [:], "shareable content: \(error ?? "nil")") }
    let main = CGMainDisplayID()
    guard let display = content.displays.first(where: { $0.displayID == main }) ?? content.displays.first else {
        return (nil, [:], "no display in the shareable content")
    }
    let config = SCStreamConfiguration()
    config.width = display.width
    config.height = display.height
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    config.showsCursor = false
    config.pixelFormat = kCVPixelFormatType_32BGRA
    let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                          configuration: config, delegate: session)
    let recordingConfig = SCRecordingOutputConfiguration()
    try? FileManager.default.removeItem(at: url)
    recordingConfig.outputURL = url
    recordingConfig.outputFileType = .mov
    let recording = SCRecordingOutput(configuration: recordingConfig, delegate: session)
    do {
        try stream.addRecordingOutput(recording)
        try stream.addStreamOutput(session, type: .screen,
                                   sampleHandlerQueue: DispatchQueue(label: "camera-spike.screen"))
    } catch {
        return (nil, [:], "adding the outputs threw: \(error)")
    }
    let info: [String: Any] = ["displayID": Int(display.displayID), "width": display.width,
                               "height": display.height, "fps": fps,
                               "codec": recordingConfig.videoCodecType.rawValue]
    return (stream, info, nil)
}

// MARK: - mode: screen (S1, S2)

func spikeAppStart() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    spikeAppUp = true
}

func spikeModeScreen(_ job: [String: Any]) -> [String: Any] {
    if let skip = spikeGate(video: true, audio: false, screen: true) { return skip }
    guard let device = spikeCamera(job) else { return spikeSkipped("no camera matches \(job["camera"] ?? "")") }
    let cameraFirst = (job["order"] as? String ?? "camera-first") == "camera-first"
    let writerPath = (job["path"] as? String) == "writer"
    let seconds = job["seconds"] as? Double ?? 4
    let screenURL = spikeJobURL(job, "outScreen"), cameraURL = spikeJobURL(job, "outCamera")
    try? FileManager.default.removeItem(at: cameraURL)
    spikeAppStart()
    let counter = SpikeCounter()
    counter.start()
    guard spikeSpin(5, until: { counter.log.count >= 30 }) else {
        counter.stop()
        return ["outcome": "failed", "reason": "the counter's display link did not tick 30 times in 5 s"]
    }
    let camera = SpikeCamera(device: device)
    do {
        try camera.build(movie: !writerPath, data: writerPath,
                         pixelFormat: writerPath ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : nil,
                         format: job["format"] as? Int, lock: job["lock"] as? Bool ?? false)
    } catch {
        counter.stop()
        return ["outcome": "failed", "reason": "the camera session did not build: \(error)"]
    }
    guard camera.run(warm: 1.0) else {
        counter.stop()
        return ["outcome": "failed", "reason": "the camera session did not run"]
    }
    let screen = SpikeStream()
    let (stream, info, error) = spikeScreenStream(url: screenURL, fps: job["fps"] as? Int ?? 60, session: screen)
    guard let stream else {
        counter.stop(); camera.stop()
        return ["outcome": "failed", "reason": error ?? "no stream"]
    }
    var writerPair: (AVAssetWriter, AVAssetWriterInput)? = nil
    if writerPath {
        let (w, h) = camera.dims
        let codecs = spikeCodecs(width: w, height: h)
        writerPair = try? spikeMakeWriter(url: cameraURL, width: w, height: h,
                                          codec: codecs.hevc ? .hevc : .h264)
        if writerPair == nil {
            counter.stop(); camera.stop()
            return ["outcome": "failed", "reason": "the camera's writer did not start"]
        }
    } else {
        _ = spikeSetMovieCodec(camera)
    }
    let cpu0 = spikeCPUSeconds()
    func startCamera() {
        if let (writer, input) = writerPair {
            camera.feed.read {
                camera.feed.writer = writer
                camera.feed.input = input
                camera.feed.armed = true
            }
        } else {
            camera.movie!.startRecording(to: cameraURL, recordingDelegate: camera.files)
        }
    }
    func startStream() {
        stream.startCapture { error in
            screen.lock.lock()
            screen.startDone = true
            screen.startError = error.map { "\($0)" }
            screen.lock.unlock()
        }
    }
    // One run-loop turn: both starts with nothing spun between.
    let calledAt = spikeNow()
    if cameraFirst { startCamera(); startStream() } else { startStream(); startCamera() }
    let cameraStarted: () -> Bool = {
        writerPath ? camera.feed.read { camera.feed.firstPTS != nil }
            : camera.files.start(for: cameraURL.path) != nil
    }
    _ = spikeSpin(20) { screen.read { screen.didStartAt != nil || screen.failure != nil } && cameraStarted() }
    spikeWait(seconds)
    let stopCalled = spikeNow()
    stream.stopCapture { _ in screen.lock.lock(); screen.stopDone = true; screen.lock.unlock() }
    if writerPath { _ = spikeFinishWriter(camera.feed) } else { camera.movie!.stopRecording() }
    _ = spikeSpin(30) {
        screen.read { screen.didFinishAt != nil || screen.failure != nil }
            && (writerPath || camera.files.finish(for: cameraURL.path) != nil)
    }
    let cpu = spikeCPUSeconds() - cpu0
    counter.stop()
    camera.stop()
    var cameraAt: Double? = nil
    var cameraPTS = CMTime.invalid
    if writerPath {
        camera.feed.read {
            cameraAt = camera.feed.firstAppendAt
            cameraPTS = camera.feed.firstPTS ?? .invalid
        }
    } else if let start = camera.files.start(for: cameraURL.path) {
        cameraAt = start.at
        cameraPTS = start.pts
    }
    let screenScale = Double(NSScreen.screens[0].backingScaleFactor)
    return screen.read { () -> [String: Any] in
        [
            "outcome": "ok", "order": cameraFirst ? "camera-first" : "stream-first",
            "path": writerPath ? "asset-writer" : "movie-output", "camera": device.localizedName,
            "calledAt": calledAt, "stopCalledAt": stopCalled,
            "startError": screen.startError ?? NSNull(), "failure": screen.failure ?? NSNull(),
            "E1": spikeNum(screen.didStartAt), "didFinishAt": spikeNum(screen.didFinishAt),
            "frames": screen.frames.count,
            "framesHead": Array(screen.frames.prefix(400)),
            "cameraCallbackAt": spikeNum(cameraAt),
            "cameraStartPTSHost": spikeNum(spikeToHost(cameraPTS, from: camera.session.synchronizationClock)),
            "counterLog": counter.log, "counterRect": counter.rectTopLeft,
            "displayPoints": [Double(NSScreen.screens[0].frame.width), Double(NSScreen.screens[0].frame.height)],
            "backingScale": screenScale, "stream": info,
            "clockCheckMs": spikeMs(CACurrentMediaTime() - spikeNow()),
            "cpuSeconds": cpu, "screenFile": screenURL.path, "cameraFile": cameraURL.path,
        ]
    }
}

// MARK: - mode: pause (P1, P2)

func spikeModePause(_ job: [String: Any]) -> [String: Any] {
    if let skip = spikeGate(video: true, audio: false, screen: false) { return skip }
    guard let device = spikeCamera(job) else { return spikeSkipped("no camera matches \(job["camera"] ?? "")") }
    let writerPath = (job["shape"] as? String) == "P2"
    let segments = job["segments"] as? Int ?? 3
    let segSeconds = job["segSeconds"] as? Double ?? 2
    let pauseSeconds = job["pauseSeconds"] as? Double ?? 1.5
    let dir = URL(fileURLWithPath: job["outDir"] as? String ?? NSTemporaryDirectory())
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var out: [String: Any] = ["outcome": "ok", "shape": writerPath ? "P2" : "P1",
                              "camera": device.localizedName]
    // The microphone in today's shape (its own session), when it is granted and present.
    var micSession: AVCaptureSession? = nil
    let micOut = AVCaptureAudioFileOutput()
    let micFiles = SpikeFileDelegate()
    if spikeStatus(.audio) == "authorized", let mic = spikeMicrophone(job),
        let input = try? AVCaptureDeviceInput(device: mic)
    {
        let session = AVCaptureSession()
        if session.canAddInput(input) && session.canAddOutput(micOut) {
            session.addInput(input)
            session.addOutput(micOut)
            session.startRunning()
            if session.isRunning { micSession = session }
        }
        out["microphone"] = mic.localizedName
    } else {
        out["microphone"] = NSNull()
        out["microphoneNote"] = "the microphone is not granted or not present; segments run without it"
    }
    let camera = SpikeCamera(device: device)
    do {
        try camera.build(movie: !writerPath, data: writerPath,
                         pixelFormat: writerPath ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange : nil,
                         format: job["format"] as? Int, lock: job["lock"] as? Bool ?? false)
    } catch {
        micSession?.stopRunning()
        return ["outcome": "failed", "reason": "the session did not build: \(error)"]
    }
    guard camera.run(warm: 1.0) else {
        micSession?.stopRunning()
        return ["outcome": "failed", "reason": "the session did not run"]
    }
    out["formatHeld"] = camera.formatHeld
    out["targetRate"] = spikeTargetRate(device)
    let (w, h) = camera.dims
    let codecs = spikeCodecs(width: w, height: h)
    if !writerPath { out["codec"] = spikeSetMovieCodec(camera) }
    var rows: [[String: Any]] = []
    var pauses: [[String: Any]] = []
    for index in 0..<segments {
        let url = dir.appendingPathComponent("segment-\(index).mov")
        let micURL = dir.appendingPathComponent("segment-\(index)-mic.m4a")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: micURL)
        var row: [String: Any] = ["index": index, "file": url.path]
        var pair: (AVAssetWriter, AVAssetWriterInput)? = nil
        if writerPath {
            pair = try? spikeMakeWriter(url: url, width: w, height: h, codec: codecs.hevc ? .hevc : .h264)
            if pair == nil { row["error"] = "the writer did not start"; rows.append(row); break }
        }
        let called = spikeNow()
        if let (writer, input) = pair {
            camera.feed.read {
                camera.feed.writer = writer
                camera.feed.input = input
                camera.feed.firstPTS = nil
                camera.feed.firstAppendAt = nil
                camera.feed.appended = 0
                camera.feed.armed = true
            }
        } else {
            camera.movie!.startRecording(to: url, recordingDelegate: camera.files)
        }
        if micSession != nil { micOut.startRecording(to: micURL, outputFileType: .m4a, recordingDelegate: micFiles) }
        let started: () -> (Double, CMTime)? = {
            if writerPath {
                return camera.feed.read {
                    camera.feed.firstAppendAt.map { ($0, camera.feed.firstPTS ?? .invalid) }
                }
            }
            return camera.files.start(for: url.path).map { ($0.at, $0.pts) }
        }
        _ = spikeSpin(10) { started() != nil }
        let start = started()
        let host = start.flatMap { spikeToHost($0.1, from: camera.session.synchronizationClock) }
        row["startMs"] = spikeMs(start.map { $0.0 - called })
        row["startPTSHost"] = spikeNum(host)
        spikeWait(segSeconds / 2)
        row["readBackFormat"] = spikeReadBack(device)["activeFormat"]
        spikeWait(segSeconds / 2)
        let stopCalled = spikeNow()
        row["segmentSeconds"] = stopCalled - (start?.0 ?? called)
        if micSession != nil { micOut.stopRecording() }
        if writerPath {
            let (closed, status, error) = spikeFinishWriter(camera.feed)
            row["closeMs"] = spikeMs(closed)
            row["writerStatus"] = status
            row["writerError"] = error ?? NSNull()
            row["appended"] = camera.feed.read { camera.feed.appended }
        } else {
            camera.movie!.stopRecording()
            _ = spikeSpin(15) { camera.files.finish(for: url.path) != nil }
            let finish = camera.files.finish(for: url.path)
            row["closeMs"] = spikeMs(finish.map { $0.at - stopCalled })
            row["finishSuccess"] = finish?.success ?? false
        }
        if micSession != nil {
            _ = spikeSpin(10) { micFiles.finish(for: micURL.path) != nil }
            let micStart = micFiles.start(for: micURL.path)
            let micHost = micStart.flatMap { spikeToHost($0.pts, from: micSession!.synchronizationClock) }
            row["micFile"] = micURL.path
            row["micStartPTSHost"] = spikeNum(micHost)
            row["micOffsetMs"] = spikeMs(host.flatMap { c in micHost.map { $0 - c } })
            row["micOffsetCallbackMs"] = spikeMs(start.flatMap { c in micStart.map { $0.at - c.0 } })
        }
        rows.append(row)
        if index < segments - 1 {
            let before = camera.feed.read { camera.feed.arrivals.count }
            let pauseStart = spikeNow()
            spikeWait(pauseSeconds)
            let delivered = camera.feed.read { camera.feed.arrivals.count } - before
            pauses.append(["index": index, "seconds": spikeNow() - pauseStart,
                           "dataOutputFrames": writerPath ? (delivered as Any) : NSNull(),
                           "dataOutputRate": writerPath ? (Double(delivered) / (spikeNow() - pauseStart) as Any) : NSNull()])
        }
    }
    let arrivals = camera.feed.read { camera.feed.arrivals }
    if writerPath, let first = arrivals.first, let last = arrivals.last, last > first {
        out["dataOutputRateOverall"] = Double(arrivals.count - 1) / (last - first)
    }
    camera.stop()
    micSession?.stopRunning()
    out["segments"] = rows
    out["pauses"] = pauses
    return out
}

// MARK: - mode: preview (V1)

func spikePhase(_ seconds: Double) -> [String: Any] {
    let daemons0 = spikeCameraDaemons()
    let cpu0 = spikeCPUSeconds(), wall0 = spikeNow()
    spikeWait(seconds)
    let wall = spikeNow() - wall0
    let cpu = spikeCPUSeconds() - cpu0
    let daemons1 = spikeCameraDaemons()
    var daemons: [String: Any] = [:]
    for (name, end) in daemons1 {
        if let begin = daemons0[name] { daemons[name] = (end - begin) / wall * 100 }
    }
    return ["seconds": wall, "cpuPercent": cpu / wall * 100, "rssBytes": spikeRSS(),
            "daemonCpuPercent": daemons]
}

func spikeModePreview(_ job: [String: Any]) -> [String: Any] {
    if let skip = spikeGate(video: true, audio: false, screen: false) { return skip }
    guard let device = spikeCamera(job) else { return spikeSkipped("no camera matches \(job["camera"] ?? "")") }
    let seconds = job["seconds"] as? Double ?? 10
    let url = spikeJobURL(job, "out")
    try? FileManager.default.removeItem(at: url)
    spikeAppStart()
    let camera = SpikeCamera(device: device)
    do {
        try camera.build(movie: false, data: false, pixelFormat: nil, format: job["format"] as? Int,
                         lock: job["lock"] as? Bool ?? false)
    } catch {
        return ["outcome": "failed", "reason": "the session did not build: \(error)"]
    }
    let idle = spikePhase(1)
    guard camera.run(warm: 1.0) else { return ["outcome": "failed", "reason": "the session did not run"] }
    var out: [String: Any] = ["outcome": "ok", "camera": device.localizedName, "readBack": spikeReadBack(device),
                              "formatHeld": camera.formatHeld, "baseline": idle]
    out["sessionOnly"] = spikePhase(seconds)
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 180),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
    view.wantsLayer = true
    let preview = AVCaptureVideoPreviewLayer(session: camera.session)
    preview.frame = view.bounds
    preview.videoGravity = .resizeAspect
    view.layer?.addSublayer(preview)
    window.contentView = view
    window.orderFrontRegardless()
    spikeWait(1)
    out["withPreview"] = spikePhase(seconds)
    let movie = AVCaptureMovieFileOutput()
    camera.session.beginConfiguration()
    let can = camera.session.canAddOutput(movie)
    if can { camera.session.addOutput(movie) }
    camera.session.commitConfiguration()
    if can {
        camera.movie = movie
        _ = spikeSetMovieCodec(camera)
        movie.startRecording(to: url, recordingDelegate: camera.files)
        _ = spikeSpin(10) { camera.files.start(for: url.path) != nil }
        out["withPreviewAndRecording"] = spikePhase(seconds)
        movie.stopRecording()
        _ = spikeSpin(15) { camera.files.finish(for: url.path) != nil }
    } else {
        out["withPreviewAndRecording"] = ["error": "canAddOutput(movie) false"]
    }
    out["readBackEnd"] = spikeReadBack(device)
    window.orderOut(nil)
    camera.stop()
    return out
}

// MARK: - mode: virtual (X1)

func spikeModeVirtual(_ job: [String: Any]) -> [String: Any] {
    let all = spikeDevices(continuity: true)
    let virtual = all.filter {
        let transport = spikeFourCC(UInt32(bitPattern: $0.transportType))
        return transport == "virt" || $0.localizedName.localizedCaseInsensitiveContains("virtual")
    }
    let hostApps = spikeRun("/usr/bin/pgrep", ["-il", "obs"], seconds: 5)?
        .split(separator: "\n").map(String.init) ?? []
    var listed: [[String: Any]] = []
    let granted = spikeStatus(.video) == "authorized"
    for device in virtual {
        var row: [String: Any] = ["uniqueID": device.uniqueID, "localizedName": device.localizedName,
                                  "manufacturer": device.manufacturer,
                                  "transportType": spikeFourCC(UInt32(bitPattern: device.transportType))]
        if granted {
            let camera = SpikeCamera(device: device)
            camera.feed.measureLuma = true
            do {
                try camera.build(movie: false, data: true, pixelFormat: kCVPixelFormatType_32BGRA,
                                 format: nil, lock: false)
                _ = camera.run(warm: 0)
                spikeWait(job["seconds"] as? Double ?? 3)
                camera.stop()
                let (arrivals, lumas) = camera.feed.read { (camera.feed.arrivals, camera.feed.lumas) }
                row["frames"] = arrivals.count
                row["black"] = lumas.filter { $0 < 24 }.count
                row["meanLuma"] = spikeNum(lumas.isEmpty ? nil : lumas.reduce(0, +) / Double(lumas.count))
            } catch {
                row["error"] = "\(error)"
            }
        } else {
            row["frames"] = NSNull()
            row["note"] = "the Camera grant is \(spikeStatus(.video)); delivery not measured"
        }
        listed.append(row)
    }
    return ["outcome": "ok", "virtual": listed, "hostAppsRunning": hostApps, "cameraGrant": spikeStatus(.video)]
}

// MARK: - mode: aimed (A1, a person points the camera at the screen)

func spikeWriteTone(_ url: URL) -> Bool {
    let rate = 48000.0
    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate))
    else { return false }
    buffer.frameLength = AVAudioFrameCount(rate)
    let samples = buffer.floatChannelData![0]
    for i in 0..<Int(rate) { samples[i] = Float(0.5 * sin(2 * Double.pi * 1000 * Double(i) / rate)) }
    try? FileManager.default.removeItem(at: url)
    guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return false }
    return (try? file.write(from: buffer)) != nil
}

func spikeModeAimed(_ job: [String: Any]) -> [String: Any] {
    if let skip = spikeGate(video: true, audio: true, screen: true) { return skip }
    guard let device = spikeCamera(job) else { return spikeSkipped("no camera matches \(job["camera"] ?? "")") }
    guard let mic = spikeMicrophone(job) else { return spikeSkipped("no microphone matches \(job["mic"] ?? "")") }
    let screenURL = spikeJobURL(job, "outScreen"), cameraURL = spikeJobURL(job, "outCamera")
    let micURL = spikeJobURL(job, "outMic"), toneURL = spikeJobURL(job, "tone")
    try? FileManager.default.removeItem(at: cameraURL)
    try? FileManager.default.removeItem(at: micURL)
    guard spikeWriteTone(toneURL) else { return ["outcome": "failed", "reason": "the tone did not write"] }
    spikeAppStart()
    let screenFrame = NSScreen.screens[0].frame
    let flash = NSWindow(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)
    flash.level = .screenSaver
    flash.backgroundColor = .black
    flash.isReleasedWhenClosed = false
    flash.orderFrontRegardless()
    let camera = SpikeCamera(device: device)
    let micOut = AVCaptureAudioFileOutput()
    let micFiles = SpikeFileDelegate()
    let micSession = AVCaptureSession()
    do {
        try camera.build(movie: true, data: false, pixelFormat: nil, format: nil, lock: false)
        let input = try AVCaptureDeviceInput(device: mic)
        guard micSession.canAddInput(input), micSession.canAddOutput(micOut) else {
            throw SpikeError("the microphone session cannot hold its input and output")
        }
        micSession.addInput(input)
        micSession.addOutput(micOut)
    } catch {
        flash.orderOut(nil)
        return ["outcome": "failed", "reason": "the sessions did not build: \(error)"]
    }
    micSession.startRunning()
    guard camera.run(warm: 1.0), micSession.isRunning else {
        flash.orderOut(nil)
        return ["outcome": "failed", "reason": "a session did not run"]
    }
    let screen = SpikeStream()
    let (stream, _, error) = spikeScreenStream(url: screenURL, fps: 60, session: screen)
    guard let stream else {
        flash.orderOut(nil); camera.stop()
        return ["outcome": "failed", "reason": error ?? "no stream"]
    }
    _ = spikeSetMovieCodec(camera)
    camera.movie!.startRecording(to: cameraURL, recordingDelegate: camera.files)
    micOut.startRecording(to: micURL, outputFileType: .m4a, recordingDelegate: micFiles)
    stream.startCapture { _ in }
    _ = spikeSpin(20) { screen.read { screen.didStartAt != nil } && camera.files.start(for: cameraURL.path) != nil }
    spikeWait(3)
    let flashAt = spikeNow()
    flash.backgroundColor = .white
    flash.display()
    let player = Process()
    player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    player.arguments = [toneURL.path]
    try? player.run()
    spikeWait(2)
    flash.backgroundColor = .black
    flash.display()
    spikeWait(1)
    stream.stopCapture { _ in }
    camera.movie!.stopRecording()
    micOut.stopRecording()
    _ = spikeSpin(30) {
        screen.read { screen.didFinishAt != nil || screen.failure != nil }
            && camera.files.finish(for: cameraURL.path) != nil && micFiles.finish(for: micURL.path) != nil
    }
    if player.isRunning { player.terminate() }
    flash.orderOut(nil)
    camera.stop()
    micSession.stopRunning()
    let cam = camera.files.start(for: cameraURL.path), mi = micFiles.start(for: micURL.path)
    return screen.read { () -> [String: Any] in
        [
            "outcome": "ok", "flashAt": flashAt, "E1": spikeNum(screen.didStartAt),
            "framesHead": Array(screen.frames.prefix(400)),
            "cameraStartPTSHost": spikeNum(cam.flatMap { spikeToHost($0.pts, from: camera.session.synchronizationClock) }),
            "micStartPTSHost": spikeNum(mi.flatMap { spikeToHost($0.pts, from: micSession.synchronizationClock) }),
            "screenFile": screenURL.path, "cameraFile": cameraURL.path, "micFile": micURL.path,
        ]
    }
}

// MARK: - mode: analyze

func spikeColor(_ desc: CMFormatDescription, _ key: CFString) -> Any {
    (CMFormatDescriptionGetExtension(desc, extensionKey: key) as? String) ?? NSNull()
}

func spikeModeAnalyze(_ job: [String: Any]) -> [String: Any] {
    let path = job["movie"] as? String ?? ""
    guard FileManager.default.fileExists(atPath: path) else {
        return ["outcome": "failed", "reason": "no file at \(path)"]
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard case .success(let loaded)? = spikeBlocking(30, { () async throws -> ([AVAssetTrack], [AVAssetTrack], CMTime) in
        (try await asset.loadTracks(withMediaType: .video), try await asset.loadTracks(withMediaType: .audio),
         try await asset.load(.duration))
    }) else { return ["outcome": "failed", "reason": "the asset did not load"] }
    let (videos, audios, duration) = loaded
    var out: [String: Any] = ["outcome": "ok", "file": path, "duration": spikeNum(duration.seconds),
                              "bytes": (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0,
                              "videoTracks": videos.count, "audioTracks": audios.count]
    if let track = videos.first {
        guard case .success(let props)? = spikeBlocking(30, { () async throws -> (Float, CGSize, CGAffineTransform, [CMFormatDescription]) in
            try await track.load(.nominalFrameRate, .naturalSize, .preferredTransform, .formatDescriptions)
        }) else { return ["outcome": "failed", "reason": "the video track did not load"] }
        let (rate, size, transform, descs) = props
        out["nominalFrameRate"] = Double(rate)
        out["width"] = Double(size.width)
        out["height"] = Double(size.height)
        out["transform"] = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].map { Double($0) }
        if let desc = descs.first {
            out["codec"] = spikeFourCC(CMFormatDescriptionGetMediaSubType(desc))
            out["primaries"] = spikeColor(desc, kCMFormatDescriptionExtension_ColorPrimaries)
            out["transfer"] = spikeColor(desc, kCMFormatDescriptionExtension_TransferFunction)
            out["matrix"] = spikeColor(desc, kCMFormatDescriptionExtension_YCbCrMatrix)
        }
        // Every frame's PTS, from the compressed samples.
        guard let reader = try? AVAssetReader(asset: asset) else {
            return ["outcome": "failed", "reason": "AVAssetReader did not open"]
        }
        let samples = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        samples.alwaysCopiesSampleData = false
        reader.add(samples)
        guard reader.startReading() else { return ["outcome": "failed", "reason": "reading did not start: \(String(describing: reader.error))"] }
        var pts: [Double] = []
        while let buffer = samples.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(buffer) > 0 {
                pts.append(CMSampleBufferGetPresentationTimeStamp(buffer).seconds)
            }
        }
        if reader.status == .failed { return ["outcome": "failed", "reason": "reading failed: \(String(describing: reader.error))"] }
        pts.sort()
        out["frames"] = pts.count
        out["firstPTS"] = spikeNum(pts.first)
        out["lastPTS"] = spikeNum(pts.last)
        let gaps = zip(pts.dropFirst(), pts).map { $0 - $1 }
        let sorted = gaps.sorted()
        let median = sorted.isEmpty ? nil : sorted[sorted.count / 2]
        out["medianInterval"] = spikeNum(median)
        out["maxInterval"] = spikeNum(sorted.last)
        out["gapsOver1_5"] = median.map { m in gaps.filter { $0 > 1.5 * m }.count } ?? 0
        out["ptsHead"] = Array(pts.prefix(24))
        // Block lumas for the first frames, and every frame's whole luma when asked.
        let blocks = (job["blocks"] as? [[Double]]) ?? []
        let lumaFrames = job["lumaFrames"] as? Int ?? 12
        let allLuma = job["allLuma"] as? Bool ?? false
        if !blocks.isEmpty || allLuma {
            guard let pixels = try? AVAssetReader(asset: asset) else {
                return ["outcome": "failed", "reason": "AVAssetReader did not open (pixels)"]
            }
            let decoded = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            decoded.alwaysCopiesSampleData = false
            pixels.add(decoded)
            guard pixels.startReading() else { return ["outcome": "failed", "reason": "pixel reading did not start"] }
            var blockRows: [[String: Any]] = []
            var whole: [[Double]] = []
            var index = 0
            while let buffer = decoded.copyNextSampleBuffer() {
                guard let image = CMSampleBufferGetImageBuffer(buffer) else { continue }
                let t = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                if index < lumaFrames && !blocks.isEmpty {
                    let lumas = blocks.map { r -> Any in
                        spikeNum(spikeLuma(image, rect: CGRect(x: r[0], y: r[1], width: r[2], height: r[3]), step: 2))
                    }
                    blockRows.append(["pts": t, "lumas": lumas])
                }
                if allLuma { whole.append([t, spikeLuma(image, step: 16) ?? -1]) }
                index += 1
                if !allLuma && index >= lumaFrames { break }
            }
            pixels.cancelReading()
            out["blockFrames"] = blockRows
            if allLuma { out["allLuma"] = whole }
        }
    }
    if let track = audios.first {
        var audio: [String: Any] = [:]
        if case .success(let descs)? = spikeBlocking(30, { try await track.load(.formatDescriptions) }),
            let desc = descs.first, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
        {
            audio["sampleRate"] = asbd.mSampleRate
            audio["channels"] = Int(asbd.mChannelsPerFrame)
            audio["format"] = spikeFourCC(asbd.mFormatID)
        }
        if let reader = try? AVAssetReader(asset: asset) {
            let threshold = Float(job["onsetThreshold"] as? Double ?? 0.1)
            let wantOnset = job["audioOnset"] as? Bool ?? false
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false])
            reader.add(output)
            if reader.startReading() {
                var first: Double? = nil, last: Double? = nil, onset: Double? = nil, frames = 0
                while let buffer = output.copyNextSampleBuffer() {
                    let t = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                    let n = CMSampleBufferGetNumSamples(buffer)
                    if first == nil { first = t }
                    var rate = 48000.0
                    var channels = 1
                    if let d = CMSampleBufferGetFormatDescription(buffer),
                        let a = CMAudioFormatDescriptionGetStreamBasicDescription(d)?.pointee
                    {
                        rate = a.mSampleRate
                        channels = max(1, Int(a.mChannelsPerFrame))
                    }
                    last = t + Double(n) / rate
                    frames += n
                    if wantOnset && onset == nil, let block = CMSampleBufferGetDataBuffer(buffer) {
                        let length = CMBlockBufferGetDataLength(block)
                        var values = [Float](repeating: 0, count: length / 4)
                        _ = values.withUnsafeMutableBytes {
                            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
                        }
                        if let i = values.firstIndex(where: { abs($0) >= threshold }) {
                            onset = t + Double(i / channels) / rate
                        }
                    }
                }
                audio["firstPTS"] = spikeNum(first)
                audio["end"] = spikeNum(last)
                audio["frames"] = frames
                if wantOnset { audio["onset"] = spikeNum(onset) }
            }
        }
        out["audio"] = audio
    }
    return out
}

// MARK: - main

let spikeArgv = CommandLine.arguments
guard spikeArgv.count >= 4 else {
    spikeEmit(["outcome": "failed", "reason": "usage: camera-spike-probe <mode> <work-dir> <job.json>"])
}
let spikeMode = spikeArgv[1]
let spikeJob: [String: Any] = {
    guard let data = FileManager.default.contents(atPath: spikeArgv[3]),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
}()

var spikeAnswer: [String: Any]
switch spikeMode {
case "devices": spikeAnswer = spikeModeDevices(spikeJob)
case "grant": spikeAnswer = spikeModeGrant(spikeJob)
case "session": spikeAnswer = spikeModeSession(spikeJob)
case "write": spikeAnswer = spikeModeWrite(spikeJob)
case "mic": spikeAnswer = spikeModeMic(spikeJob)
case "screen": spikeAnswer = spikeModeScreen(spikeJob)
case "pause": spikeAnswer = spikeModePause(spikeJob)
case "preview": spikeAnswer = spikeModePreview(spikeJob)
case "virtual": spikeAnswer = spikeModeVirtual(spikeJob)
case "aimed": spikeAnswer = spikeModeAimed(spikeJob)
case "analyze": spikeAnswer = spikeModeAnalyze(spikeJob)
default: spikeAnswer = ["outcome": "failed", "reason": "no mode \(spikeMode)"]
}
spikeAnswer["mode"] = spikeMode
spikeEmit(spikeAnswer)
