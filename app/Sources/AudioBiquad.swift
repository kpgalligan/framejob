import Foundation

// The EQ's and the hum notch's arithmetic (spec §11 AU-30, AU-31, AU-33, AU-36): RBJ cookbook
// biquads designed in Double, the settings a clip's `EqProps` and `HumProps` ask for, and the
// response the inspector draws. `AudioEQStage.swift` runs what `AudioEQDesign.design` designs;
// the drawn curve evaluates the SAME design, so it is the stage's coefficients and not a
// second formula.

/// One biquad section's coefficients, normalised by a0:
/// `H(z) = (b0 + b1 z⁻¹ + b2 z⁻²) / (1 + a1 z⁻¹ + a2 z⁻²)`.
struct AudioBiquadCoefficients: Equatable {
    var b0, b1, b2, a1, a2: Double

    static let identity = AudioBiquadCoefficients(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
}

/// What one clip's EQ and hum notch ask the stage for, in the stage's units,
/// held to the model's ranges (a hand-edited file can carry anything; the
/// core's `clamp_eq` and `clamp_hum` say the same for every value a file can
/// hold. A NaN frequency, which no JSON carries, is 1000 Hz here and its
/// slot's own default there). Plain stored values and small structs only, so
/// comparing two on the audio thread allocates nothing.
struct AudioEQSettings: Equatable {
    /// A Butterworth pass: its corner and how many sections (1 is
    /// 12 dB/octave, 2 is 24).
    struct Pass: Equatable {
        var frequency: Double
        var sections: Int
    }
    struct Shelf: Equatable {
        var frequency: Double
        var gainDb: Double
    }
    struct Bell: Equatable {
        var frequency: Double
        var gainDb: Double
        var q: Double
    }
    /// The hum comb: the mains, each notch's depth, the harmonic count.
    struct Comb: Equatable {
        var frequency: Double
        var depthDb: Double
        var harmonics: Int
    }

    var highPass: Pass?
    var lowShelf: Shelf?
    var band1: Bell?
    var band2: Bell?
    var band3: Bell?
    var highShelf: Shelf?
    var lowPass: Pass?
    var hum: Comb?

    /// nil when no position would be designed: no EQ (or a bypassed one, or
    /// only flat shelves and bells) and no hum.
    init?(eq: EqProps?, hum: HumProps?) {
        if let eq, !eq.bypass {
            highPass = eq.highPass.map(Self.pass)
            lowShelf = eq.lowShelf.map(Self.shelf)
            band1 = eq.band1.map(Self.bell)
            band2 = eq.band2.map(Self.bell)
            band3 = eq.band3.map(Self.bell)
            highShelf = eq.highShelf.map(Self.shelf)
            lowPass = eq.lowPass.map(Self.pass)
        }
        self.hum = hum.map {
            Comb(
                frequency: $0.frequency >= 55 ? 60 : 50,
                depthDb: Self.bounded($0.depthDb, 6, 60, 30),
                harmonics: Swift.min(Swift.max($0.harmonics, 1), 8))
        }
        let shaped = [lowShelf?.gainDb, band1?.gainDb, band2?.gainDb, band3?.gainDb,
                      highShelf?.gainDb].contains { ($0 ?? 0) != 0 }
        guard highPass != nil || lowPass != nil || shaped || self.hum != nil else { return nil }
    }

    private static func bounded(_ value: Double, _ low: Double, _ high: Double, _ neutral: Double)
        -> Double
    {
        value.isNaN ? neutral : Swift.min(Swift.max(value, low), high)
    }
    private static func hz(_ value: Double, _ neutral: Double) -> Double {
        bounded(value, 20, 20_000, neutral)
    }
    private static func pass(_ p: EqPassProps) -> Pass {
        Pass(frequency: hz(p.frequency, 1000), sections: p.slope >= 18 ? 2 : 1)
    }
    private static func shelf(_ s: EqShelfProps) -> Shelf {
        Shelf(frequency: hz(s.frequency, 1000), gainDb: bounded(s.gainDb, -24, 24, 0))
    }
    private static func bell(_ b: EqBandProps) -> Bell {
        Bell(
            frequency: hz(b.frequency, 1000), gainDb: bounded(b.gainDb, -24, 24, 0),
            q: bounded(b.q, 0.1, 10, 1))
    }
}

/// The design: settings → 17 fixed positions of coefficients (AU-30).
enum AudioEQDesign {
    /// High-pass sections 1 and 2, the low shelf, bands 1–3, the high shelf,
    /// low-pass sections 1 and 2, hum harmonics 1…8 — in the stage's order.
    static let positions = 17
    static let humFirst = 9

    /// Butterworth's section Qs (AU-31): one section at 1/√2 for
    /// 12 dB/octave; two at 1/(2 cos(π/8)) and 1/(2 cos(3π/8)) for 24.
    /// Literals, so the audio thread never runs a lazy initialiser.
    static func butterworthQ(sections: Int, index: Int) -> Double {
        if sections < 2 { return 0.707_106_781_186_547_6 }
        return index == 0 ? 0.541_196_100_146_197 : 1.306_562_964_876_376_6
    }

    /// Fills all 17 positions: an inactive one is the identity and `false`.
    /// A shelf or a bell at exactly 0 dB is not designed, and no section at
    /// or above 0.49·fs is. Allocates nothing.
    static func design(
        _ s: AudioEQSettings, sampleRate: Double,
        into coefficients: UnsafeMutablePointer<AudioBiquadCoefficients>,
        active: UnsafeMutablePointer<Bool>
    ) {
        for p in 0..<positions {
            coefficients[p] = .identity
            active[p] = false
        }
        let limit = 0.49 * sampleRate
        if let pass = s.highPass, pass.frequency < limit {
            for k in 0..<Swift.min(pass.sections, 2) {
                coefficients[k] = highPass(
                    pass.frequency, q: butterworthQ(sections: pass.sections, index: k),
                    sampleRate: sampleRate)
                active[k] = true
            }
        }
        if let shelf = s.lowShelf, shelf.gainDb != 0, shelf.frequency < limit {
            coefficients[2] = lowShelf(shelf.frequency, gainDb: shelf.gainDb, sampleRate: sampleRate)
            active[2] = true
        }
        // Three calls rather than a loop over a literal: an array would
        // allocate on the audio thread.
        put(s.band1, at: 3, limit: limit, sampleRate: sampleRate, coefficients, active)
        put(s.band2, at: 4, limit: limit, sampleRate: sampleRate, coefficients, active)
        put(s.band3, at: 5, limit: limit, sampleRate: sampleRate, coefficients, active)
        if let shelf = s.highShelf, shelf.gainDb != 0, shelf.frequency < limit {
            coefficients[6] = highShelf(
                shelf.frequency, gainDb: shelf.gainDb, sampleRate: sampleRate)
            active[6] = true
        }
        if let pass = s.lowPass, pass.frequency < limit {
            for k in 0..<Swift.min(pass.sections, 2) {
                coefficients[7 + k] = lowPass(
                    pass.frequency, q: butterworthQ(sections: pass.sections, index: k),
                    sampleRate: sampleRate)
                active[7 + k] = true
            }
        }
        if let hum = s.hum {
            // AU-33: Q = 10·k / A holds every notch's pole bandwidth at f0/10
            // at any depth and any harmonic.
            let a = pow(10, -hum.depthDb / 40)
            for k in 1...Swift.max(1, Swift.min(hum.harmonics, 8)) {
                let frequency = Double(k) * hum.frequency
                guard frequency < limit else { break }
                coefficients[humFirst + k - 1] = peaking(
                    frequency, gainDb: -hum.depthDb, q: 10 * Double(k) / a,
                    sampleRate: sampleRate)
                active[humFirst + k - 1] = true
            }
        }
    }

    private static func put(
        _ bell: AudioEQSettings.Bell?, at index: Int, limit: Double, sampleRate: Double,
        _ coefficients: UnsafeMutablePointer<AudioBiquadCoefficients>,
        _ active: UnsafeMutablePointer<Bool>
    ) {
        guard let bell, bell.gainDb != 0, bell.frequency < limit else { return }
        coefficients[index] = peaking(
            bell.frequency, gainDb: bell.gainDb, q: bell.q, sampleRate: sampleRate)
        active[index] = true
    }

    // MARK: The cookbook

    private static func normalised(
        _ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double
    ) -> AudioBiquadCoefficients {
        AudioBiquadCoefficients(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func highPass(_ f: Double, q: Double, sampleRate: Double) -> AudioBiquadCoefficients {
        let w = 2 * Double.pi * f / sampleRate
        let c = cos(w)
        let alpha = sin(w) / (2 * q)
        return normalised((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }

    static func lowPass(_ f: Double, q: Double, sampleRate: Double) -> AudioBiquadCoefficients {
        let w = 2 * Double.pi * f / sampleRate
        let c = cos(w)
        let alpha = sin(w) / (2 * q)
        return normalised((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }

    static func peaking(_ f: Double, gainDb: Double, q: Double, sampleRate: Double)
        -> AudioBiquadCoefficients
    {
        let a = pow(10, gainDb / 40)
        let w = 2 * Double.pi * f / sampleRate
        let c = cos(w)
        let alpha = sin(w) / (2 * q)
        return normalised(1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a)
    }

    /// RBJ's shelves at S = 1, where `alpha = sin(w)/2 · √2`.
    static func lowShelf(_ f: Double, gainDb: Double, sampleRate: Double)
        -> AudioBiquadCoefficients
    {
        let a = pow(10, gainDb / 40)
        let w = 2 * Double.pi * f / sampleRate
        let c = cos(w)
        let beta = 2 * a.squareRoot() * (sin(w) / 2 * 2.0.squareRoot())
        return normalised(
            a * ((a + 1) - (a - 1) * c + beta), 2 * a * ((a - 1) - (a + 1) * c),
            a * ((a + 1) - (a - 1) * c - beta),
            (a + 1) + (a - 1) * c + beta, -2 * ((a - 1) + (a + 1) * c),
            (a + 1) + (a - 1) * c - beta)
    }

    static func highShelf(_ f: Double, gainDb: Double, sampleRate: Double)
        -> AudioBiquadCoefficients
    {
        let a = pow(10, gainDb / 40)
        let w = 2 * Double.pi * f / sampleRate
        let c = cos(w)
        let beta = 2 * a.squareRoot() * (sin(w) / 2 * 2.0.squareRoot())
        return normalised(
            a * ((a + 1) + (a - 1) * c + beta), -2 * a * ((a - 1) + (a + 1) * c),
            a * ((a + 1) + (a - 1) * c - beta),
            (a + 1) - (a - 1) * c + beta, 2 * ((a - 1) - (a + 1) * c),
            (a + 1) - (a - 1) * c - beta)
    }

    // MARK: The response

    /// |H(e^{jω})| in dB at `frequency`.
    static func magnitudeDB(_ c: AudioBiquadCoefficients, frequency: Double, sampleRate: Double)
        -> Double
    {
        let w = 2 * Double.pi * frequency / sampleRate
        let (c1, s1, c2, s2) = (cos(w), sin(w), cos(2 * w), sin(2 * w))
        let nr = c.b0 + c.b1 * c1 + c.b2 * c2
        let ni = -(c.b1 * s1 + c.b2 * s2)
        let dr = 1 + c.a1 * c1 + c.a2 * c2
        let di = -(c.a1 * s1 + c.a2 * s2)
        return 10 * log10((nr * nr + ni * ni) / (dr * dr + di * di))
    }

    /// The whole cascade's response in dB at each frequency: the sum over
    /// the designed positions (AU-36). Off the audio thread.
    static func responseDB(_ s: AudioEQSettings, frequencies: [Double], sampleRate: Double)
        -> [Double]
    {
        var coefficients = [AudioBiquadCoefficients](repeating: .identity, count: positions)
        var active = [Bool](repeating: false, count: positions)
        coefficients.withUnsafeMutableBufferPointer { c in
            active.withUnsafeMutableBufferPointer { a in
                design(s, sampleRate: sampleRate, into: c.baseAddress!, active: a.baseAddress!)
            }
        }
        return frequencies.map { f in
            var total = 0.0
            for p in 0..<positions where active[p] {
                total += magnitudeDB(coefficients[p], frequency: f, sampleRate: sampleRate)
            }
            return total
        }
    }
}
