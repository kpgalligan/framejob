import AudioToolbox
import Darwin
import Foundation

/// The rtcheck dylib's API, found with dlsym so the tool also runs without it.
enum RTCheck {
    typealias Fn = @convention(c) () -> Void
    typealias CountsFn = @convention(c) (UnsafeMutablePointer<Int>) -> Void
    typealias DumpFn = @convention(c) (UnsafePointer<CChar>) -> Void

    static let handle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
    static let armFn: Fn? = sym("rtcheck_arm")
    static let disarmFn: Fn? = sym("rtcheck_disarm")
    static let countsFn: CountsFn? = sym("rtcheck_counts")
    static let resetTracesFn: Fn? = sym("rtcheck_reset_traces")
    static let dumpFn: DumpFn? = sym("rtcheck_dump_traces")

    static func sym<T>(_ name: String) -> T? {
        guard let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    static var available: Bool { armFn != nil }

    /// alloc, free, lock, loggerAlloc, loggerFree — read into a caller-owned
    /// buffer so the read itself allocates nothing.
    @inline(__always) static func read(_ into: UnsafeMutablePointer<Int>) {
        if let f = countsFn { f(into) } else { into.update(repeating: 0, count: 5) }
    }
    @inline(__always) static func arm() { armFn?() }
    @inline(__always) static func disarm() { disarmFn?() }
    static func resetTraces() { resetTracesFn?() }
    static func dump(_ label: String) { label.withCString { dumpFn?($0) } }
}

/// What an armed region did: counts of allocations, frees, lock acquisitions,
/// and the malloc_logger's own allocation count.
struct RTCounts: CustomStringConvertible {
    var alloc = 0, free = 0, lock = 0, loggerAlloc = 0, loggerFree = 0
    mutating func add(before: UnsafeMutablePointer<Int>, after: UnsafeMutablePointer<Int>) {
        alloc += after[0] - before[0]
        free += after[1] - before[1]
        lock += after[2] - before[2]
        loggerAlloc += after[3] - before[3]
        loggerFree += after[4] - before[4]
    }
    var description: String {
        "alloc \(alloc) free \(free) lock \(lock) (logger alloc \(loggerAlloc) free \(loggerFree))"
    }
    var clean: Bool { alloc == 0 && free == 0 && lock == 0 && loggerAlloc == 0 && loggerFree == 0 }
}

func loadAverage() -> String {
    var l = [Double](repeating: 0, count: 3)
    getloadavg(&l, 3)
    return String(format: "%.2f %.2f %.2f", l[0], l[1], l[2])
}

nonisolated(unsafe) var timebase: mach_timebase_info_data_t = {
    var t = mach_timebase_info_data_t()
    mach_timebase_info(&t)
    return t
}()

@inline(__always) func nowNanos() -> UInt64 {
    mach_absolute_time() * UInt64(timebase.numer) / UInt64(timebase.denom)
}

/// Planar float buffers with an AudioBufferList over them, allocated once.
final class PlanarBuffers {
    let channels: Int
    let capacity: Int
    let data: [UnsafeMutablePointer<Float>]
    let abl: UnsafeMutableAudioBufferListPointer

    init(channels: Int, capacity: Int) {
        self.channels = channels
        self.capacity = capacity
        data = (0..<channels).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
            p.initialize(repeating: 0, count: capacity)
            return p
        }
        abl = AudioBufferList.allocate(maximumBuffers: channels)
        for c in 0..<channels {
            abl[c] = AudioBuffer(
                mNumberChannels: 1, mDataByteSize: UInt32(capacity * 4), mData: data[c])
        }
    }

    /// Sets every buffer's byte size to `frames` (and restores the pointers,
    /// which a render may have redirected).
    @inline(__always) func setFrames(_ frames: Int) {
        for c in 0..<channels {
            abl[c].mData = UnsafeMutableRawPointer(data[c])
            abl[c].mDataByteSize = UInt32(frames * 4)
        }
    }

    deinit {
        data.forEach { $0.deallocate() }
        free(abl.unsafeMutablePointer)
    }
}

/// Copies planar data from one buffer list into another (same channel count).
@inline(__always) func copyABL(
    from src: UnsafeMutableAudioBufferListPointer, to dst: UnsafeMutableAudioBufferListPointer,
    frames: Int
) {
    let n = min(src.count, dst.count)
    for c in 0..<n {
        guard let s = src[c].mData, let d = dst[c].mData else { continue }
        if s != d { memcpy(d, s, frames * 4) }
    }
}
