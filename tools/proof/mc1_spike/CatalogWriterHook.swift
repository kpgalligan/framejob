import Foundation

// Road map 14 MC1, q1 — SPIKE ONLY. `mc1_spike.py` copies this file into the
// TREE COPY's app/Sources (tools/proof/work/mc1_spike/tree), never into the
// tree's, and inserts `mc1WriteCatalogIfAsked()` into the copy's main.swift
// straight after `AgentLane.prepareAtLaunch()`.
//
// `-RCWriteCatalog <path>` writes `{"version":…,"tools":<catalog>}` to <path>
// and exits before NSApplicationMain; without the argument it returns.
func mc1WriteCatalogIfAsked() {
    guard let path = UserDefaults.standard.string(forKey: "RCWriteCatalog") else { return }
    guard let catalog = AgentServer.shared.preparedCatalog else {
        FileHandle.standardError.write(Data("mc1: no prepared catalog\n".utf8))
        exit(1)
    }
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    guard let versionJSON = try? JSONSerialization.data(withJSONObject: version, options: [.fragmentsAllowed]),
          let versionText = String(data: versionJSON, encoding: .utf8)
    else {
        FileHandle.standardError.write(Data("mc1: the version did not encode\n".utf8))
        exit(1)
    }
    let text = "{\"version\":\(versionText),\"tools\":\(catalog)}"
    do {
        try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    } catch {
        FileHandle.standardError.write(Data("mc1: could not write \(path): \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    exit(0)
}
