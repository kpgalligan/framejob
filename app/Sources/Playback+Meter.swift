import Foundation

/// The level meter's half of `Playback`: the reading and the 30 Hz timer the
/// rate KVO arms and disarms. A pure move out of `Playback.swift`, which sat
/// at the 600-line cap; the stored state (`built`, `meterTimer`) stays there
/// because an extension cannot add stored properties.
extension Playback {
    /// How often the level meter is re-read while the transport is moving.
    ///
    /// It is a READ rate, not a measurement rate: the taps publish once per
    /// buffer, which is 12–20 Hz on the paths this app has measured (4096
    /// frames is 85 ms at 48 kHz), so 30 Hz merely makes sure a new buffer is
    /// picked up within a frame of arriving. `Exporter.progressInterval` is
    /// the same idea at a slower cadence.
    static let meterInterval: TimeInterval = 1.0 / 30

    /// The transport's levels, right now: every metered track SOUNDING at the
    /// playhead, its last buffer multiplied by the mix envelope over it,
    /// summed — `LevelMeterTrack.mix`, where the fold lives so the offscreen
    /// harness calls it rather than a copy of it.
    ///
    /// **Only a track sounding at the playhead counts** (#65): a sink keeps
    /// its last buffer across an empty stretch of its composition track, and
    /// without that test a finished clip's level stayed lit —
    /// `LevelMeterTrack`'s doc says why.
    ///
    /// **The envelope is the multiply that makes the number post-fader.** The
    /// taps are `PreEffects`, so what they measured is the track before
    /// volume, the fades and ducking — and the plan's ramps are exactly what
    /// `CompositionBuilder` handed AVFoundation to apply downstream of them.
    /// `LevelMeter.swift` argues why the meter must be computed this way
    /// rather than observed from a second tap.
    ///
    /// It is read at the PLAYHEAD's tick, while the buffer the taps last
    /// published is a little ahead of it — the audio path renders in front of
    /// the picture. The two differ by under one buffer, so on a fade the
    /// displayed level lags the applied gain by up to 85 ms, which is under
    /// this meter's own resolution and far under the eye's.
    func meterReading() -> LevelMeterReading {
        guard let meters = built?.meters, !meters.isEmpty else { return .silent }
        return LevelMeterTrack.mix(meters, at: currentTime)
    }

    /// Armed by the rate KVO when the transport starts moving. A run-loop
    /// `Timer`, not a dispatch source, for the reason `Playback.swift`'s header gives
    /// for the debounce: it cancels deterministically, and app/CLAUDE.md's
    /// five `DispatchQueue` seams are not to grow a sixth.
    func startMetering() {
        guard meterTimer == nil else { return }
        meterTimer = Timer.scheduledTimer(
            withTimeInterval: Playback.meterInterval, repeats: true
        ) { [weak self] _ in
            guard let self = self else { return }
            LevelMeter.shared.publish(self.meterReading(), from: ObjectIdentifier(self))
        }
    }

    /// Disarmed on every stop, with a final zero. Nothing is pulled through
    /// the taps at rate 0, so the last buffer's peak would otherwise sit lit
    /// on the meter for as long as the window was open — which reads as a bug
    /// rather than as a paused transport. The sinks are cleared as well, so a
    /// resumed preview does not flash the peak it paused on before its first
    /// buffer arrives.
    func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        built?.meters.forEach { $0.sink.clear() }
        LevelMeter.shared.publish(.silent, from: ObjectIdentifier(self))
    }
}
