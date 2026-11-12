import Anthropic
@testable import FrameJobAgentKit
import XCTest

/// Where the price fixtures are: agent/prices, beside this package's Tests, unless
/// `FJ_AGENT_PRICES` names a whole copy of that folder (`tools/proof/prices_proof.py`'s
/// `swift-disagrees` mutant: the suite answers a scratch `cases.json` without a rebuild).
enum PriceFiles {
    static let folder: URL = {
        if let copy = ProcessInfo.processInfo.environment["FJ_AGENT_PRICES"], !copy.isEmpty {
            return URL(fileURLWithPath: copy, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("prices")
    }()

    static func data(_ name: String) throws -> Data { try Data(contentsOf: folder.appendingPathComponent(name)) }
    static func json(_ name: String) throws -> RawJSON { try RawJSON.parse(try data(name)) }
}

/// The price function against agent/prices/cases.json, the fixture pricing.test.ts and
/// tools/proof/prices.py answer too (spec §11 P-2, SA-3), and the table compiled in.
final class PricingTests: XCTestCase {
    /// pricing.test.ts's tolerance.
    static let tolerance = 1e-12

    /// Empty when `got` answers `want`, else what differs.
    private func mismatch(_ got: Price, _ want: RawJSON) -> String {
        switch (got, want["kind"]?.stringValue) {
        case (.dollars(let dollars, let rows), "dollars"):
            let expected = want["dollars"]?.doubleValue ?? .nan
            if !(abs(dollars - expected) <= Self.tolerance) { return "dollars \(dollars), expected \(expected)" }
            let wanted = want["rows"]?.arrayValue?.compactMap(\.stringValue) ?? []
            if rows != wanted { return "rows \(rows), expected \(wanted)" }
            return ""
        case (.unknown(let cause, let detail), "unknown"):
            let expected = want["cause"]?.stringValue ?? ""
            return cause == expected ? "" : "cause \(cause) (\(detail)), expected \(expected)"
        default:
            return "kind \(got), expected \(want.serializedString)"
        }
    }

    func testEveryCaseInCasesJSON() throws {
        let fixture = try PriceFiles.json("cases.json")
        guard case .success(let table) = PriceTables.parse(try XCTUnwrap(fixture["table"])) else {
            return XCTFail("the fixture's table does not parse")
        }
        let cases = try XCTUnwrap(fixture["cases"]?.arrayValue)
        XCTAssertEqual(cases.count, 23)
        for c in cases {
            let name = c["name"]?.stringValue ?? "?"
            let got = Pricing.price(usage: c["usage"] ?? .null, model: c["model"]?.stringValue ?? "", table: table)
            XCTAssertEqual(mismatch(got, c["expect"] ?? .null), "", "case \(name)")
        }
    }

    func testTheCommittedTable() throws {
        let file = try PriceFiles.json("anthropic.json")
        guard case .success(let table) = PriceTables.parse(file) else { return XCTFail("anthropic.json does not parse") }
        XCTAssertEqual(file["format"], 1)
        XCTAssertEqual(file["unit"], "USD per million tokens")
        XCTAssertEqual(file["provider"], "anthropic")
        let commit = table.litellmCommit ?? ""
        XCTAssertTrue(commit.count == 40 && commit.allSatisfy { "0123456789abcdef".contains($0) }, commit)
        for model in ["claude-opus-5-5", "claude-fable-5-1"] {
            for key in ["input", "output", "cache_read", "cache_write_5m", "cache_write_1h"] {
                XCTAssertTrue(Pricing.usable(table.models[model]?[key]), "\(model) \(key)")
            }
        }
        guard case .dollars(let dollars, _) = Pricing.price(usage: ["input_tokens": 1000], model: "claude-opus-5-5", table: table)
        else { return XCTFail("opus does not price") }
        XCTAssertGreaterThan(dollars, 0)
    }

    /// The bytes compiled in are agent/prices/anthropic.json's (through the target's symlink,
    /// spec §11 SA-3), so `make prices` reaches the helper with a rebuild.
    func testTheEmbeddedTableIsTheFilesBytes() throws {
        XCTAssertEqual(Data(PackageResources.anthropic_json), try PriceFiles.data("anthropic.json"))
        let bundled = PriceTables.bundled()
        XCTAssertEqual(bundled.source, PriceSource(kind: .bundled, asOf: try XCTUnwrap(
            try PriceFiles.json("anthropic.json")["litellm_commit_date"]?.stringValue)))
    }

    func testNeverThrowsOrAnswersNaN() throws {
        guard case .success(let table) = PriceTables.parse(try XCTUnwrap(try PriceFiles.json("cases.json")["table"])) else {
            return XCTFail("no table")
        }
        let odd: [RawJSON] = [.null, 1, "usage", [], ["input_tokens": 1.5], ["input_tokens": 1.0], ["input_tokens": 1e3],
                              ["iterations": "x"], ["iterations": []], ["cache_creation": [:], "input_tokens": 1]]
        for usage in odd {
            switch Pricing.price(usage: usage, model: "claude-opus-5-5", table: table) {
            case .dollars(let dollars, _): XCTAssertTrue(dollars.isFinite, usage.serializedString)
            case .unknown(let cause, _): XCTAssertFalse(cause.isEmpty)
            }
        }
        // A whole number written with a fraction is a count, as JavaScript reads it.
        XCTAssertEqual(Pricing.price(usage: ["input_tokens": 1.0], model: "claude-opus-5-5", table: table),
                       Pricing.price(usage: ["input_tokens": 1], model: "claude-opus-5-5", table: table))
        XCTAssertEqual(Pricing.price(usage: [:], model: "", table: table), .unknown(cause: "model", detail: "no model id"))
    }
}
