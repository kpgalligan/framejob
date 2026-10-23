import AVFoundation

extension CompositionBuilder {
    // MARK: - Source orientation

    /// One orientation code per media with a video track, read from the
    /// source's `preferredTransform`.
    ///
    /// This exists because a CUSTOM compositor gets RAW decoded frames: unlike
    /// the built-in one, nothing applies the preferred transform for us, and a
    /// portrait phone clip — whose model size is the DISPLAY size the importer
    /// probed (§7.7) — would otherwise render sideways and squashed. The code
    /// travels to the shader, which turns the sampling coordinates.
    static func orientationCodes(
        plan: CompositionPlan, urls: [UInt32: URL], assets: inout [UInt32: AVURLAsset]
    ) -> [UInt32: Int] {
        var codes: [UInt32: Int] = [:]
        for planTrack in plan.videoTracks {
            for segment in planTrack.segments where codes[segment.media] == nil {
                guard let track = sourceTrack(
                    for: segment.media, mediaType: .video, urls: urls, assets: &assets)
                else { continue }
                codes[segment.media] = orientationCode(track.preferredTransform)
            }
        }
        return codes
    }

    /// The composition tracks an instruction needs, mapped to the orientation
    /// of whatever each is showing across it. An instruction boundary falls
    /// wherever the visible clips change (§7.2), so a track shows exactly one
    /// segment inside one instruction and this lookup is exact rather than a
    /// per-track approximation.
    static func trackOrientations(
        plan: CompositionPlan, instruction: PlanInstruction, codes: [UInt32: Int]
    ) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for trackID in instruction.requiredTrackIDs {
            guard let planTrack = plan.videoTracks.first(where: { $0.id == trackID }),
                let segment = planTrack.segments.first(where: {
                    instruction.start >= $0.start && instruction.start < $0.start + $0.duration
                }),
                let code = codes[segment.media], code != 0
            else { continue }
            result[trackID] = code
        }
        return result
    }

    /// A preferred transform as `quarterTurns | (mirrored ? 4 : 0)`, the
    /// encoding `Compositor.metal`'s `orientedUV` undoes.
    ///
    /// Only the four quarter turns and a horizontal mirror are classified —
    /// which is every transform a camera or an editor actually writes. A
    /// transform that is something else (a shear, an arbitrary angle) falls
    /// back to the nearest of them rather than refusing the file, and the
    /// frame is at worst turned wrong, never dropped.
    static func orientationCode(_ transform: CGAffineTransform) -> Int {
        let mirrored = transform.a * transform.d - transform.b * transform.c < 0
        // A reflection is one mirror away from a rotation: undo the mirror,
        // then classify what is left.
        let a = mirrored ? -transform.a : transform.a
        let b = mirrored ? -transform.b : transform.b
        let c = transform.c
        let d = transform.d
        func near(_ x: CGFloat, _ y: CGFloat) -> Bool { abs(x - y) < 0.001 }
        var turns = 0
        if near(a, 0), near(b, 1), near(c, -1), near(d, 0) {
            turns = 1
        } else if near(a, -1), near(b, 0), near(c, 0), near(d, -1) {
            turns = 2
        } else if near(a, 0), near(b, -1), near(c, 1), near(d, 0) {
            turns = 3
        }
        return turns | (mirrored ? 4 : 0)
    }
}
