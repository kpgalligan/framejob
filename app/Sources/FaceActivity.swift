import Foundation

/// Mouth activity (road map "creator-jobs" SW8, spec §11 SW-81, SW-82): who
/// is talking when one microphone hears everyone, from each angle's cached
/// `faces` (CJ-30). The largest face is the angle's person; a sample's opening
/// is its mouth's gap over its width; activity is the population standard
/// deviation of the openings over `window` centred on a sample; a speech step
/// is the top angle's when it is `ratio` × the next and above `floor`, else
/// crosstalk. Pure: reads no document, file or clock (SW-25); names no `rc_*`.
enum FaceActivity {
    /// Seconds, centred (SW-81).
    static let window: Double = 0.5
    /// The top angle's activity is at least this times the next's.
    static let ratio: Double = 1.5
    /// The standard deviation of gap/width the top must exceed; PROVISIONAL
    /// until SW-S3 measures S-PC2 (SW-88).
    static let floor: Double = 0.02
    /// Seconds: the faces mode's `min_shot` default, SW-S3's middle band (SW-82).
    static let minShot: Double = 3.0
    /// The first sentence of the sheet's summary and the tool's `note` in the
    /// faces mode (SW-82).
    static let hedge = "Faces guess who is talking; check the cuts."

    /// The face with the largest width × height; ties go to the first in
    /// CJ-31's order. nil for no face.
    static func largest(_ faces: [AnalysisFaces.Face]) -> AnalysisFaces.Face? {
        var best: AnalysisFaces.Face?
        var area = -Double.infinity
        for face in faces {
            let a = Double(face.width) * Double(face.height)
            if best == nil || a > area {
                best = face
                area = a.isNaN ? -.infinity : a
            }
        }
        return best
    }

    /// The largest face's `mouthGap / mouthWidth`; nil for no frame (pts −1),
    /// no face, a non-finite gap or width, or a width ≤ 0.
    static func opening(_ sample: AnalysisFaces.Sample) -> Double? {
        guard sample.pts >= 0, let face = largest(sample.faces) else { return nil }
        let gap = Double(face.mouthGap), width = Double(face.mouthWidth)
        guard gap.isFinite, width.isFinite, width > 0 else { return nil }
        return gap / width
    }

    /// Samples each side of the centre: ⌊window/2 · rate⌋ (2 at 10 a second,
    /// 1 at 5).
    static func halfWidth(rate: Double) -> Int {
        guard rate.isFinite, rate > 0 else { return 0 }
        return Int((window / 2 * rate + 1e-9).rounded(.down))
    }

    /// Per index c, the population standard deviation of the non-nil
    /// openings in c − half … c + half (clipped to the series); nil when
    /// fewer than two are there.
    static func activities(_ openings: [Double?], half: Int) -> [Double?] {
        let n = openings.count
        var out = [Double?](repeating: nil, count: n)
        for c in 0..<n {
            var values: [Double] = []
            for k in max(0, c - half)...min(n - 1, c + half) {
                if let v = openings[k] { values.append(v) }
            }
            guard values.count >= 2 else { continue }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            out[c] = variance.squareRoot()
        }
        return out
    }

    /// A step's label over the contesting angles, front first: no speech or
    /// no activity → nobody; else the top angle (ties: the front-most) when
    /// top ≥ `ratio` × the next (0 when alone) and top > `floor`, otherwise
    /// crosstalk. `person` names the ANGLE track.
    static func label(
        speech: Bool, activities: [(angle: UInt32, activity: Double?)], ratio: Double,
        floor: Double
    ) -> SpeakerSwitch.Label {
        guard speech else { return .nobody }
        var top: (angle: UInt32, value: Double)?
        var next = 0.0
        for case let (angle, value?) in activities {
            if let current = top {
                if value > current.value {
                    next = current.value
                    top = (angle, value)
                } else if value > next {
                    next = value
                }
            } else {
                top = (angle, value)
            }
        }
        guard let top else { return .nobody }
        return top.value >= ratio * next && top.value > floor ? .person(top.angle) : .crosstalk
    }
}
