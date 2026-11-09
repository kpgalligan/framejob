// Road map "creator-jobs" CJ5b — row D12 of `derived_proof.py` (spec §11 #459), driven through
// the app's own `DerivedCarry.listing` and `DerivedCarry.copy(_ listing:from:to:)`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// against `libframejob_core.a`, through `swift_build.py`. One run:
//
//   derived_carry_probe <work dir>
//
// The work dir is a scratch folder this run owns. The answer is one JSON object on stdout,
// `{"rows": [{"id", "pass", "detail"}]}`; every expected value is worked by hand here, never by
// the code under test.
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: derived_carry_probe <work dir>\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files = FileManager.default

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

/// A fresh, empty folder `name` under the work dir.
func folder(_ name: String) -> URL {
    let url = work.appendingPathComponent(name, isDirectory: true)
    if files.fileExists(atPath: url.path) {
        // A folder left read-only by an earlier run is made writable before it is removed.
        _ = try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        for inner in (try? files.subpathsOfDirectory(atPath: url.path)) ?? [] {
            _ = try? files.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.appendingPathComponent(inner).path)
        }
        try? files.removeItem(at: url)
    }
    try? files.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes `text` at `relative` under `root`, its folders made.
func write(_ root: URL, _ relative: String, _ text: String) throws {
    let url = root.appendingPathComponent(relative)
    try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

// MARK: - D12 (1) a listed file that vanishes before the copy is skipped

// A source cache holding a media's 42 thumbnail tiles, its peaks and marker, and a shots marker
// with one payload: the paths `cachePaths` would answer for media 3. The tile 40.jpg is removed
// between the listing and the copy, as the thumbnail pass's `clearThumbnails` can.
do {
    let source = folder("d12-vanished/source")
    let destination = folder("d12-vanished/destination")
    var written: [String: String] = [:]
    for k in 0...41 { written["thumbs/3/\(k).jpg"] = "tile \(k)" }
    written["peaks/3.bin"] = "peaks of 3"
    written["peaks/3.complete.json"] = "{\"peaks\": 3}"
    written["analysis/shots/3.json"] = "{\"shots\": 3}"
    written["analysis/shots/3/shots.bin"] = "shots of 3"
    for (relative, text) in written { try write(source, relative, text) }
    let paths = [
        "analysis/shots/3", "analysis/shots/3.json", "peaks/3.bin", "peaks/3.complete.json",
        "thumbs/3",
    ]
    let listing = DerivedCarry.listing(paths, in: source)
    let wantFolders = ["analysis/shots/3", "thumbs/3"]
    let listed = listing.folders == wantFolders && listing.files == written.keys.sorted()
    try files.removeItem(at: source.appendingPathComponent("thumbs/3/40.jpg"))
    var problems: [String] = []
    var report: DerivedCarry.Report?
    do {
        report = try DerivedCarry.copy(listing, from: source, to: destination)
    } catch {
        problems.append("threw \(error.localizedDescription)")
    }
    if !listed {
        problems.append(
            "listing folders \(listing.folders) (want \(wantFolders)), \(listing.files.count) "
                + "files (want \(written.count))")
    }
    if let report, report.files != written.count - 1 {
        problems.append("report.files \(report.files) (want \(written.count - 1))")
    }
    for (relative, text) in written where relative != "thumbs/3/40.jpg" {
        let got = try? Data(contentsOf: destination.appendingPathComponent(relative))
        if got != Data(text.utf8) { problems.append("\(relative) not byte-identical") }
    }
    if files.fileExists(atPath: destination.appendingPathComponent("thumbs/3/40.jpg").path) {
        problems.append("thumbs/3/40.jpg exists in the copy")
    }
    row(
        "D12", problems.isEmpty,
        problems.isEmpty
            ? "listed \(written.count) files in 2 folders; 40.jpg removed after the listing; no "
                + "throw, \(written.count - 1) carried, each byte-identical, no 40.jpg"
            : problems.joined(separator: "; "))
} catch {
    row("D12", false, "the fixture could not be written: \(error.localizedDescription)")
}

// MARK: - D12 (2) any other failure still throws, naming the file

// The destination's `thumbs/3/` exists read-only: the first tile's clone fails while its source
// is still there, so the copy throws in the carry's sentence.
do {
    let source = folder("d12-denied/source")
    let destination = folder("d12-denied/destination")
    for k in 0...2 { try write(source, "thumbs/3/\(k).jpg", "tile \(k)") }
    let locked = destination.appendingPathComponent("thumbs/3", isDirectory: true)
    try files.createDirectory(at: locked, withIntermediateDirectories: true)
    try files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    let listing = DerivedCarry.listing(["thumbs/3"], in: source)
    let want = "cache/thumbs/3/0.jpg could not be carried: Permission denied"
    var got = "no throw"
    do {
        _ = try DerivedCarry.copy(listing, from: source, to: destination)
    } catch let error as ReelCoreError {
        got = error.message
    } catch {
        got = "\(error)"
    }
    try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
    row("D12", got == want, "a clone refused by a read-only folder: \(got) (want \(want))")
} catch {
    row("D12", false, "the fixture could not be written: \(error.localizedDescription)")
}

let answer = try JSONSerialization.data(withJSONObject: ["rows": rows])
print(String(decoding: answer, as: UTF8.self))
