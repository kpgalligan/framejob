import Foundation

/// The build's catalog snapshot (road map 14's MC3, spec §11 MC-4): with
/// `-RCWriteCatalog <path>`, the launch writes `{"version":…,"tools":…}` —
/// the bundle's `CFBundleShortVersionString` and the catalog
/// `AgentLane.prepareAtLaunch()` just prepared, verbatim — to `<path>` and
/// exits before `NSApplicationMain`, so no window, Dock icon or socket ever
/// appears. `project.yml`'s "Write Agent Catalog" phase runs the just-built
/// binary this way to put `Contents/Resources/agent-catalog.json` in the
/// bundle, which `framejob-mcp` answers `tools/list` from while no Frame Job
/// runs (MC1 q1 measured the phase; `tools/proof/dist_check.py` D21–D24 check
/// the file).
///
/// The key is read from the ARGUMENT domain only, so no persisted default
/// can turn an ordinary launch into a writer. A failure is one stderr line,
/// `framejob catalog snapshot: …`, and exit 1 — never the `Frame Job: `
/// prefix, which is the parity check's (the phase fails on that too).
enum AgentCatalogSnapshot {
    static let argumentKey = "RCWriteCatalog"

    /// Returns when the launch has no `-RCWriteCatalog`; otherwise writes
    /// the snapshot and exits.
    static func writeIfAsked() {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard let path = arguments[argumentKey] as? String else { return }
        guard let catalog = AgentServer.shared.preparedCatalog else {
            fail("no prepared catalog (the catalog did not build at launch)")
        }
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard
            let versionJSON = try? JSONSerialization.data(
                withJSONObject: version, options: [.fragmentsAllowed]),
            let versionText = String(data: versionJSON, encoding: .utf8)
        else {
            fail("the version \(version) did not encode as JSON")
        }
        let text = "{\"version\":\(versionText),\"tools\":\(catalog)}"
        do {
            try Data(text.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            fail("could not write \(path): \(error.localizedDescription)")
        }
        exit(0)
    }

    private static func fail(_ reason: String) -> Never {
        FileHandle.standardError.write(Data("framejob catalog snapshot: \(reason)\n".utf8))
        exit(1)
    }
}
