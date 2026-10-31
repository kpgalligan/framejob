import Foundation

/// The level meter's half of `Playback`: `meterInterval`, the reading and the 30 Hz timer the
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
    ///
    /// **While the live loudness meter is measuring, the bars are the MIX**
    /// (road map "audio" AP7, spec §11 AU-74): its sample peak and RMS per
    /// channel over its last 100 ms, rebuilt from the taps' samples, rather
    /// than the per-track sum above, which over-reads correlated tracks' peak
    /// by up to 3.85 dB (spike S3).
    func meterReading() -> LevelMeterReading {
        if let bars = loudness.bars { return bars }
        guard let meters = built?.meters, !meters.isEmpty else { return .silent }
        return LevelMeterTrack.mix(meters, at: currentTime)
    }

    /// Armed by the rate KVO when the transport starts moving. A run-loop
    /// `Timer`, not a dispatch source, for the reason `Playback.swift`'s header gives
    /// for the debounce: it cancels deterministically, and app/CLAUDE.md's
    /// five `DispatchQueue` seams are not to grow a sixth. It runs in the
    /// `.common` modes, so menu tracking and a live resize still drain the
    /// taps' rings (spec §11 AU-72), and each tick feeds the live loudness
    /// meter before the bars are read.
    func startMetering() {
        guard meterTimer == nil else { return }
        let timer = Timer(timeInterval: Playback.meterInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // A build with track dynamics is approximate in the preview (AU-153).
            self.loudness.consume(
                self.built?.meters ?? [], rate: self.rate,
                now: ProcessInfo.processInfo.systemUptime,
                tracksApproximate: !(self.built?.trackDynamics.isEmpty ?? true))
            LevelMeter.shared.publish(self.meterReading(), from: ObjectIdentifier(self))
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
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
        loudness.stop()
        built?.meters.forEach { $0.sink.clear() }
        LevelMeter.shared.publish(.silent, from: ObjectIdentifier(self))
    }
}
