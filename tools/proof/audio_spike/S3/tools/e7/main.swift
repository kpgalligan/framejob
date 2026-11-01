import AVFoundation
import Foundation

// E7: an AVPlayer's taps at shuttle rates (JKL: Playback.setRate), PreEffects and PostEffects:
// are they called, how much composition time does each wall second cover, and does a
// PostEffects tap in the PLAYER see the volume ramp (E4 found the reader's does not).

setvbuf(stdout, nil, _IOLBF, 0)
let media = makeMedia()
let specs = [
    TrackSpec(url: media.a, at: 0, from: 0, duration: 20, legs: [Leg(start: 0, duration: 20, from: 0.5, to: 0.5)]),
    TrackSpec(url: media.b, at: 2, from: 0, duration: 16, legs: [Leg(start: 0, duration: 18, from: 0.25, to: 0.25)]),
]
func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

for post in [false, true] {
    print("== \(post ? "PostEffects" : "PreEffects") taps in an AVPlayer (muted)")
    let built = build(specs, seconds: 20, postEffects: post)
    let item = AVPlayerItem(asset: built.composition)
    item.audioMix = built.mix
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    var w = 0
    while item.status != .readyToPlay && w < 100 { wait(0.02); w += 1 }
    for rate: Float in [1, 2, 4, 8, 0.5, -1] {
        player.pause()
        var done = false
        player.seek(to: cmTime(rate < 0 ? 16 : 6), toleranceBefore: .zero, toleranceAfter: .zero) { _ in done = true }
        while !done { wait(0.01) }
        let before = built.records.map { $0.calls.count }
        let wall0 = Date()
        player.rate = rate
        wait(1.5)
        let actual = player.rate
        player.pause()
        let wall = Date().timeIntervalSince(wall0)
        wait(0.2)
        var parts: [String] = []
        for (k, r) in built.records.enumerated() {
            let calls = Array(r.calls[before[k]...]).filter { $0.start >= 0 }
            let span = (calls.map { $0.start }.max() ?? 0) - (calls.map { $0.start }.min() ?? 0)
            let frames = calls.map { $0.frames }.reduce(0, +)
            parts.append(String(format: "T%d %d calls, %.2f s of comp time stamped, %.2f s of frames", k + 1, calls.count, span, Double(frames) / 48000))
        }
        print(String(format: "  rate %+.1f (player reports %+.1f) over %.2f s wall: ", rate, actual, wall) + parts.joined(separator: "; "))
    }
    if post {
        // Gain seen by T1's PostEffects tap at rate 1 against its source (volume 0.5).
        let r = built.records[0]
        var num = 0.0, den = 0.0
        for i in (48000 * 6 + 4800)..<(48000 * 7) where r.store[0][i] != 0 {
            num += Double(r.store[0][i] * media.aSamples[0][i]); den += Double(media.aSamples[0][i] * media.aSamples[0][i])
        }
        print(String(format: "  T1 PostEffects tap in the player, 6.1-7.0 s: gain against source %.4f (volume ramp 0.5)", den > 0 ? num / den : -1))
    }
}
