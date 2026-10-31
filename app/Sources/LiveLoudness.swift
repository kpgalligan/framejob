import Foundation

/// The live loudness meter (road map "audio" AP7, spec §11 AU-70…AU-74):
/// momentary, short-term and integrated LUFS and the true-peak maximum of
/// the TRUE mix, rebuilt on the main thread from what each tap copied into
/// its sink's `MixRing`.
///
/// **The sum is by frame, not by arrival.** Each tap is called on one
/// thread in a cycle, but the tracks' buffers in one cycle start up to
/// 13 ms apart (spike S3), so the consumer adds each track's samples at
/// their own frame, times the plan's envelope there (`MediaPeaks.envelope`,
/// the level meter's multiply), a mono track in both channels. Frame f is
/// summed once every track has delivered past it, except a track not
/// sounding at f (outside its own spans: a gap, or past its last clip, where
/// the tap delivers nothing, #65) or `stallLag` behind the leading track;
/// such a track is silence at f.
///
/// **Continuity** (AU-72). A chunk that continues its own track's stream is
/// summed; one that MOVES its track is asked the reset rule once the chunks
/// before it are summed: more than `behindTolerance` behind the frame the
/// sum reached, or more than `aheadTolerance` past it with a track sounding
/// in between, is a `jump` and the measurement starts again from it; inside
/// the tolerances, frames before the reached frame are dropped, so pause and
/// continue and an edit's rebuild neither reset nor count a frame twice.
/// After a seek the player hands each track a buffer or two of the OLD
/// position first, not in step across tracks (measured, AP7), which is why
/// a track that has not moved yet drops its old stream until it does
/// (`LiveLoudness+Sum.swift`'s `admit`).
///
/// The lane and the sum are `LiveLoudness+Sum.swift`, under the 400-line rule.
///
/// MAIN THREAD ONLY: `Playback`'s meter timer is its one caller, so, like
/// `LevelMeter`, it holds no lock.
struct LiveLoudnessReading: Equatable {
    var momentaryLUFS: Double?
    var shortTermLUFS: Double?
    var integratedLUFS: Double?
    var truePeakDBTP: Double?
    /// Summing frames at ×1 now (within `LiveLoudness.liveWindow`).
    var measuring: Bool
    /// The first frame measured since the reset, and the frame the sum reached.
    var fromFrame: Int64?
    var toFrame: Int64?
    var sampleRate: Int?
    var resets: Int
    var lastReset: LiveLoudness.ResetReason?
    /// Playing at a rate other than ×1: nothing is measured (the footer says so).
    var offSpeed = false

    static let empty = LiveLoudnessReading(
        momentaryLUFS: nil, shortTermLUFS: nil, integratedLUFS: nil, truePeakDBTP: nil,
        measuring: false, fromFrame: nil, toFrame: nil, sampleRate: nil, resets: 0,
        lastReset: nil)
}

final class LiveLoudness {
    enum ResetReason: String { case manual, jump, overrun }

    /// Seconds of frames (AU-72, AU-70).
    static let aheadTolerance = 0.1, behindTolerance = 1.0, stallLag = 0.5
    /// How recently the sum must have moved for the reading to be live (AU-74).
    static let liveWindow: TimeInterval = 0.15

    private(set) var reading = LiveLoudnessReading.empty
    /// The mix's last 100 ms per channel: sample peak and RMS. Nil unless
    /// measuring.
    private(set) var bars: LevelMeterReading?
    /// Called when `reading` changes.
    var onReading: ((LiveLoudnessReading) -> Void)?
    /// Frames fed to the meter since the last reset (what a proof counts).
    var fedFrames: Int64 = 0

    // The sum's state is internal only so `LiveLoudness+Sum.swift` can write
    // it; nothing else does.
    var lanes: [ObjectIdentifier: LiveLoudnessLane] = [:]
    var order: [ObjectIdentifier] = []
    var meter: LoudnessMeter?
    /// The taps' rate the measurement is at.
    var rate: Int?
    /// The next frame the sum adds; nil before the first one after a reset.
    var reached: Int64?
    /// The first frame summed since the reset.
    var measuredFrom: Int64?
    var lastAdvance: TimeInterval?
    private var barLeft: [Float] = []
    private var barRight: [Float] = []
    private var barNext = 0
    private var barCount = 0

    init() {}

    // MARK: - The tick

    /// The meter timer's tick: drains every track's ring and sums what it can.
    func consume(_ meters: [LevelMeterTrack], rate playRate: Float, now: TimeInterval) {
        syncLanes(meters)
        var overran = false
        var drained: [(lane: LiveLoudnessLane, chunks: [MixChunk])] = []
        for id in order {
            guard let lane = lanes[id] else { continue }
            let got = lane.track.sink.ring.drain()
            overran = overran || got.overran
            drained.append((lane, got.chunks))
        }
        if playRate == 0 {
            stop()
            return
        }
        // AU-72: measured only at ×1; at any other rate the chunks are discarded.
        guard playRate == 1 else {
            for item in drained { item.lane.stream = item.chunks.last?.end ?? item.lane.stream }
            dropPending()
            bars = nil
            lastAdvance = nil
            var next = reading
            next.momentaryLUFS = nil
            next.shortTermLUFS = nil
            next.measuring = false
            next.offSpeed = true
            commit(next)
            return
        }
        if overran { reset(.overrun) }
        let rates = Set(drained.flatMap { $0.chunks.map(\.sampleRate) })
        if rates.count == 1, let taps = rates.first, taps != rate {
            rate = taps
            if measuredFrom != nil {
                reset(.jump)
            } else {
                meter = LoudnessMeter(sampleRate: Double(taps), channelCount: 2)
            }
        }
        if rates.count <= 1, let sampleRate = rate, meter != nil {
            admit(drained, rate: sampleRate, now: now)
        }
        let live = lastAdvance.map { now - $0 <= Self.liveWindow } ?? false
        bars = live ? mixBars() : nil
        refresh(measuring: live)
    }

    /// Clears the measurement; the next chunk starts a new one.
    func reset(_ reason: ResetReason) {
        meter = rate.flatMap { LoudnessMeter(sampleRate: Double($0), channelCount: 2) }
        for lane in lanes.values {
            lane.pending = []
            lane.end = nil
            lane.awaiting = nil
            if reason == .overrun { lane.stream = nil }
        }
        reached = nil
        measuredFrom = nil
        fedFrames = 0
        barNext = 0
        barCount = 0
        var next = reading
        next.momentaryLUFS = nil
        next.shortTermLUFS = nil
        next.integratedLUFS = nil
        next.truePeakDBTP = nil
        next.fromFrame = nil
        next.toFrame = nil
        next.resets += 1
        next.lastReset = reason
        commit(next)
    }

    /// Rate 0: what the rings still hold was rendered ahead and never heard,
    /// so it is dropped; frames already summed stay measured, though the
    /// player renders ahead of the playhead (AU-72). M, S, I and TP hold
    /// their last ×1 values.
    func stop() {
        for lane in lanes.values {
            lane.stream = lane.track.sink.ring.drain().chunks.last?.end ?? lane.stream
        }
        dropPending()
        bars = nil
        lastAdvance = nil
        var next = reading
        next.momentaryLUFS = meter?.momentaryLUFS
        next.shortTermLUFS = meter?.shortTermLUFS
        next.measuring = false
        next.offSpeed = false
        commit(next)
    }

    // MARK: - The sum

    private func syncLanes(_ meters: [LevelMeterTrack]) {
        let ids = meters.map { ObjectIdentifier($0.sink) }
        guard ids != order else { return }
        var next: [ObjectIdentifier: LiveLoudnessLane] = [:]
        for meter in meters {
            let id = ObjectIdentifier(meter.sink)
            next[id] = lanes[id] ?? LiveLoudnessLane(meter)
        }
        lanes = next
        order = ids
    }

    var allLanes: [LiveLoudnessLane] { order.compactMap { lanes[$0] } }

    private func dropPending() {
        for lane in lanes.values {
            lane.pending = []
            if let end = lane.end, let reached { lane.end = min(end, reached) }
        }
    }

    // MARK: - The bars and the reading

    func pushBars(_ left: [Float], _ right: [Float], rate: Int) {
        let size = max(1, rate / 10)
        if barLeft.count != size {
            barLeft = [Float](repeating: 0, count: size)
            barRight = barLeft
            barNext = 0
            barCount = 0
        }
        for i in left.indices {
            barLeft[barNext] = left[i]
            barRight[barNext] = right[i]
            barNext = (barNext + 1) % size
        }
        barCount = min(size, barCount + left.count)
    }

    /// Sample peak and RMS per channel of the mix's last 100 ms.
    private func mixBars() -> LevelMeterReading? {
        guard barCount > 0 else { return nil }
        var peak: (Float, Float) = (0, 0)
        var power: (Float, Float) = (0, 0)
        for k in 0..<barCount {
            let i = (barNext - 1 - k + barLeft.count) % barLeft.count
            peak = (max(peak.0, abs(barLeft[i])), max(peak.1, abs(barRight[i])))
            power = (power.0 + barLeft[i] * barLeft[i], power.1 + barRight[i] * barRight[i])
        }
        let n = Float(barCount)
        return LevelMeterReading(
            peakLeft: peak.0, peakRight: peak.1, rmsLeft: (power.0 / n).squareRoot(),
            rmsRight: (power.1 / n).squareRoot())
    }

    private func refresh(measuring: Bool) {
        var next = reading
        next.measuring = measuring
        next.offSpeed = false
        next.sampleRate = rate
        next.fromFrame = measuredFrom
        next.toFrame = measuredFrom == nil ? nil : reached
        if let meter, fedFrames > 0 {
            let report = meter.finish()
            next.momentaryLUFS = meter.momentaryLUFS
            next.shortTermLUFS = meter.shortTermLUFS
            next.integratedLUFS = report.integratedLUFS
            next.truePeakDBTP = report.truePeakDBTP
        }
        commit(next)
    }

    private func commit(_ next: LiveLoudnessReading) {
        guard next != reading else { return }
        reading = next
        onReading?(next)
    }
}
