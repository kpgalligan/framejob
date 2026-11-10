import AppKit

/// Every save of the package announced to the cache ledger, so no marker,
/// waveform or voice file lands between the save's listing and its swap
/// (`MediaImporter.CacheLedger`, `MediaCacheLedger.swift`).
///
/// This one override is enough: ⌘S, Save As, autosave and `save_project`
/// all funnel through `save(to:ofType:for:completionHandler:)`, and NSDocument
/// lists the package for its lazy `cache/` wrapper and swaps the new package
/// in before that completion runs. `saveBegan` waits for a publication
/// already being written; `saveEnded` runs before the caller's handler.
///
/// `-RCDevSaveHold <s>` (dev tools only, spec §11 #429) holds each save on
/// the main thread for s seconds after the new package has been written and
/// before NSDocument swaps it in, inside `saveBegan` … `saveEnded`: the
/// window in which a cache file written outside the ledger goes with the old
/// package. A proof publishes during it (`analysis_proof.py` A14).
extension ProjectDocument {
    #if FRAMEJOB_DEV_TOOLS
    static let devSaveHoldKey = "RCDevSaveHold"

    override func write(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
        originalContentsURL absoluteOriginalContentsURL: URL?
    ) throws {
        try super.write(
            to: url, ofType: typeName, for: saveOperation,
            originalContentsURL: absoluteOriginalContentsURL)
        let seconds = UserDefaults.standard.double(forKey: Self.devSaveHoldKey)
        if seconds > 0 { Thread.sleep(forTimeInterval: seconds) }
    }
    #endif

    override func save(
        to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let directory = intendedCacheDirectory else {
            super.save(to: url, ofType: typeName, for: saveOperation,
                       completionHandler: completionHandler)
            return
        }
        let save = MediaImporter.CacheLedger.shared.saveBegan(cacheDir: directory)
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            MediaImporter.CacheLedger.shared.saveEnded(cacheDir: directory, save: save)
            completionHandler(error)
        }
    }
}
