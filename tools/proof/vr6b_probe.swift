// Road map creator-jobs VR6b — Q8: the Follow key read back through the app's own sources with no
// app (spec §11 VR-66 (a)). With the key `speaker`, `VerticalVersion.remembered` answers Speaker
// and Follow Subject's `FollowSubjectSettings.remembered` answers Subject; Subject chosen on the
// Make Vertical sheet (`remember(changedFrom: VerticalVersion.remembered(d))`) writes the key
// back as `subject`; with the key `cursor` (a follow neither sheet offers) `remembered` answers
// Subject. On a `UserDefaults(suiteName:)` of its own, removed at the end; `vr6b_proof.py` runs
// it under the proof's scratch `CFFIXED_USER_HOME`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`, with
// `FRAMEJOB_DEV_TOOLS`, against `libframejob_core.a`, through `swift_build.py`:
//
//   vr6b_probe <work dir> main   -> {"rows": [{"id", "pass", "detail"}, ...]}
import AppKit

guard CommandLine.arguments.count >= 3, CommandLine.arguments[2] == "main" else {
    FileHandle.standardError.write(Data("usage: vr6b_probe <work dir> main\n".utf8))
    exit(2)
}

let suite = "com.kgalligan.FrameJob.vr6b-probe"
guard let defaults = UserDefaults(suiteName: suite) else {
    FileHandle.standardError.write(Data("vr6b_probe: no suite \(suite)\n".utf8))
    exit(2)
}
defaults.removePersistentDomain(forName: suite)
let key = FollowSubjectSettings.followKey
var problems: [String] = []
var notes: [String] = []

defaults.set("speaker", forKey: key)
let opened = VerticalVersion.remembered(defaults)
let followSubject = FollowSubjectSettings.remembered(defaults, zoom: 1)
notes.append("key speaker: Make Vertical opens \(opened.follow.rawValue), Follow Subject "
    + "\(followSubject.follow.rawValue)")
if opened.follow != .speaker { problems.append("VerticalVersion.remembered answered \(opened.follow.rawValue), not speaker") }
if followSubject.follow != .subject {
    problems.append("FollowSubjectSettings.remembered answered \(followSubject.follow.rawValue), not subject")
}
if opened.zoom != 1 { problems.append("remembered's zoom is \(opened.zoom), not 1") }

var chosen = VerticalVersion.remembered(defaults)
chosen.follow = .subject
chosen.remember(changedFrom: VerticalVersion.remembered(defaults), in: defaults)
let written = defaults.string(forKey: key)
notes.append("Subject chosen after speaker writes \(written ?? "nothing")")
if written != "subject" { problems.append("Subject after a stored speaker wrote \(written ?? "nothing")") }

defaults.set("cursor", forKey: key)
let cursor = VerticalVersion.remembered(defaults)
notes.append("key cursor: Make Vertical opens \(cursor.follow.rawValue)")
if cursor.follow != .subject { problems.append("key cursor opened \(cursor.follow.rawValue), not subject") }

defaults.removePersistentDomain(forName: suite)
let rows: [[String: Any]] = [[
    "id": "Q8", "pass": problems.isEmpty,
    "detail": problems.isEmpty ? notes.joined(separator: "; ") : problems.joined(separator: "; "),
]]
let data = try JSONSerialization.data(withJSONObject: ["rows": rows])
FileHandle.standardOutput.write(data)
