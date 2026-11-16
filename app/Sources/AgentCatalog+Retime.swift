import Foundation

/// The catalog row of `retime_range` (spec §11 CU-90 (e); road map
/// "creator-jobs" CU9a), spliced in by `creatorTools()`.
extension AgentServer {

    func retimeTools() -> [[String: Any]] {
        let speed = ReelSpeed.limits
        let ticks = "in TICKS — 600000 per second, so 1 s = 600000 and one 30 fps frame = 20000. "
            + "Rounded to the project's frame grid."
        return [
            // It mirrors Clip ▸ Retime Range… (`showRetimeSheet` in
            // EditorViewController+Retime.swift): the sheet's Apply commits
            // this one op through `SpeedAudioDrop.commit`.
            opTool(
                "retime_range",
                String(
                    format: "Plays [from, to) faster or slower on every unlocked track and moves "
                        + "everything after it up or back to stay in step — Clip ▸ Retime "
                        + "Range… over the In–Out range. One undo step, \"Retime Range\". Each "
                        + "clip across from or to is cut there as split cuts it; each media "
                        + "clip inside plays at its own rate × rate (a speed ramp scales whole), "
                        + "and text, shapes, stills, images, graphics and adjustment clips "
                        + "inside are stretched or squeezed the same way; actions keep their "
                        + "place. Markers inside move with the picture and markers after it "
                        + "move with the rest; a linked partner of a moved clip moves with it. "
                        + "rate 1 changes nothing. Refused, nothing changed: a rate outside "
                        + "%g–%g, a range under two frames, a locked track with a clip after "
                        + "from, a nest clip, a caption page with timed words or a linked clip "
                        + "(Detach Audio's halves) in the range, a transition touching it, two "
                        + "markers landing on one time, a clip whose rate would pass %g–%g or "
                        + "that would last under a frame, each named, and a piece a cut would "
                        + "leave too short for its transition (the overlap rule). Inside a nest "
                        + "(scope) the nest's tracks are retimed and no marker moves. Above "
                        + "×%g the clip's audio is left out, and the answer carries "
                        + "audio_left_out and audio_note; new_clips lists the pieces the cuts "
                        + "made.",
                    speed.min, speed.max, speed.min, speed.max, speed.audioMax),
                [
                    "from": "Where the range starts, \(ticks)",
                    "to": "Where the range ends, \(ticks) Must be after from.",
                    "rate": "2 = twice as fast (the range half as long), 0.5 = half speed.",
                    "keep_pitch": "Keep the audio's pitch at the new speed for every media clip "
                        + "in the range (default: each as it is).",
                ]),
        ]
    }
}
