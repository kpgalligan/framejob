import Foundation

/// The witness of spec §11 #367's rule, no synchronous `AVAssetReader` read
/// on the Swift cooperative pool (audited app-wide by #369): whether the
/// calling thread is on the pool, and, while a probe records, which read
/// sites ran and whether each ran there (`cache_lane_probe.swift` R0–R2).
/// Await-free; always compiled, so its call sites build in every
/// configuration. When not recording, `note` costs one locked Bool read.
enum ReaderPool {
    struct Note: Equatable {
        let site: String
        let onPool: Bool
        let label: String
    }

    private static let lock = NSLock()
    private static var recording = false
    private static var notes: [Note] = []

    /// The label ends in ".cooperative" (`com.apple.root.<qos>-qos.cooperative`).
    static func isCooperative(label: String) -> Bool {
        label.hasSuffix(".cooperative")
    }

    /// Whether the calling thread is one of the cooperative pool's.
    static var onCooperativePool: Bool {
        isCooperative(label: currentLabel)
    }

    private static var currentLabel: String {
        String(cString: __dispatch_queue_get_label(nil))
    }

    /// Appends a note for `site` only while recording.
    static func note(_ site: String) {
        lock.lock()
        let on = recording
        lock.unlock()
        guard on else { return }
        let label = currentLabel
        let note = Note(site: site, onPool: isCooperative(label: label), label: label)
        lock.lock()
        if recording { notes.append(note) }
        lock.unlock()
    }

    /// Empties the record and starts recording.
    static func startRecording() {
        lock.lock()
        notes = []
        recording = true
        lock.unlock()
    }

    /// Stops recording; answers the notes in order and empties the record.
    static func takeNotes() -> [Note] {
        lock.lock()
        defer { lock.unlock() }
        recording = false
        let taken = notes
        notes = []
        return taken
    }
}
