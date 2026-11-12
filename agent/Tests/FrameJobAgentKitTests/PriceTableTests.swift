import Anthropic
@testable import FrameJobAgentKit
import XCTest

/// The LiteLLM reducer against agent/prices/reduce_cases.json (the fixture update.py's and
/// priceTable.ts's reducers answer), and the refresh in each of priceTable.test.ts's cases,
/// against a feed on 127.0.0.1 only. No test reaches the network.
final class PriceTableTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("framejob-prices-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// A new empty folder under the scratch folder.
    private func folder() throws -> URL {
        let url = scratch.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var fixture: RawJSON { get throws { try PriceFiles.json("reduce_cases.json") } }
    private var litellm: RawJSON { get throws { try XCTUnwrap(try fixture["litellm"]) } }
    private var bundledDate: String { get throws { try XCTUnwrap(try PriceFiles.json("anthropic.json")["litellm_commit_date"]?.stringValue) } }

    private func withoutFable() throws -> RawJSON {
        var document = try XCTUnwrap(try litellm.objectValue)
        _ = document.removeValue(forKey: "claude-fable-5-1")
        return .object(document)
    }

    /// A feed on 127.0.0.1 answering `body` with `status`; its GETs are the server's requests.
    private func feed(_ body: String, status: Int = 200) throws -> LoopbackServer {
        try LoopbackServer { _ in LoopbackServer.response(status, body: body) }
    }

    private func fixed(_ text: String) -> @Sendable () -> Date {
        let date = PriceTables.date(text)!
        return { date }
    }

    private func reduced(_ source: String, _ at: String) throws -> PriceTable {
        guard case .success(let table) = PriceTables.reduceLiteLLM(try litellm, source: source, fetchedAt: at) else {
            throw ProtocolError("the fixture does not reduce")
        }
        return table
    }

    func testReduceTheFixturesAnthropicRows() throws {
        let table = try reduced("https://feed.example/p.json", "2026-09-28T12:00:00.000Z")
        // Compared as values, as `toEqual` does: the expected rows' key order is not the reducer's.
        XCTAssertEqual(table.models.jsonValueObject, try XCTUnwrap(try fixture["models"]).numeric)
        XCTAssertEqual(table.source, "https://feed.example/p.json")
        XCTAssertEqual(table.fetchedAt, "2026-09-28T12:00:00.000Z")
        XCTAssertEqual(table.json["format"], 1)
        XCTAssertNil(table.litellmCommit)
        guard case .success = PriceTables.parse(try RawJSON.parse(table.json.serialized())) else { return XCTFail("does not parse") }
    }

    func testReduceRefusesADocumentWithoutFableByName() throws {
        guard case .failure(let why) = PriceTables.reduceLiteLLM(try withoutFable(), source: "s", fetchedAt: "t") else {
            return XCTFail("taken")
        }
        XCTAssertEqual(why.message, "no claude-fable-5-1 row")
    }

    func testReduceRefusesNotAnObjectNoAnthropicEntryAndABadRate() throws {
        guard case .failure = PriceTables.reduceLiteLLM([], source: "s", fetchedAt: "t") else { return XCTFail("[] taken") }
        guard case .failure = PriceTables.reduceLiteLLM(["x": ["litellm_provider": "bedrock"]], source: "s", fetchedAt: "t") else {
            return XCTFail("bedrock taken")
        }
        var bad = try litellm
        bad["claude-opus-5-5"]?["input_cost_per_token"] = -1
        guard case .failure(let why) = PriceTables.reduceLiteLLM(bad, source: "s", fetchedAt: "t") else { return XCTFail("taken") }
        XCTAssertTrue(why.message.contains("claude-opus-5-5.input_cost_per_token"), why.message)
    }

    func testNoCacheConfiguredIsTheBundledTableAndNothingDue() throws {
        let initial = PriceTables.initial(PriceOptions(cache: nil, feed: nil))
        XCTAssertEqual(initial.prices.source, PriceSource(kind: .bundled, asOf: try bundledDate, problem: "no price cache is configured"))
        XCTAssertFalse(initial.refreshDue)
    }

    func testAPathThatIsNotAbsoluteIsRefused() async {
        let options = PriceOptions(cache: "relative/anthropic-prices.json", feed: nil)
        let initial = PriceTables.initial(options)
        XCTAssertEqual(initial.prices.source.problem, "the price cache path is not absolute")
        XCTAssertFalse(initial.refreshDue)
        let again = await PriceTables.refresh(initial.prices, options)
        XCTAssertEqual(again.source.problem, "the price cache path is not absolute")
    }

    func testNoCacheFetchesOnceAndWritesTheCache() async throws {
        let served = try feed(try litellm.serializedString)
        defer { served.stop() }
        let cache = try folder().appendingPathComponent("nested/anthropic-prices.json").path
        let options = PriceOptions(cache: cache, feed: served.baseURL + "/prices.json", now: fixed("2026-09-28T12:00:00.000Z"))
        let initial = PriceTables.initial(options)
        XCTAssertTrue(initial.refreshDue)
        XCTAssertEqual(initial.prices.source.kind, .bundled)
        let loaded = await PriceTables.refresh(initial.prices, options)
        XCTAssertEqual(loaded.source, PriceSource(kind: .fetched, asOf: "2026-09-28T12:00:00.000Z"))
        XCTAssertEqual(served.requests.count, 1)
        XCTAssertEqual(served.requests.first?.line, "GET /prices.json HTTP/1.1")
        XCTAssertEqual(served.requests.first?.header("user-agent"), "framejob-agent")
        guard case .success(let written) = PriceTables.parse(try RawJSON.parse(Data(contentsOf: URL(fileURLWithPath: cache)))) else {
            return XCTFail("the cache does not parse")
        }
        XCTAssertEqual(written.source, served.baseURL + "/prices.json")
        XCTAssertEqual(written.fetchedAt, "2026-09-28T12:00:00.000Z")
        XCTAssertEqual(written.models.jsonValueObject, try XCTUnwrap(try fixture["models"]).numeric)
    }

    func testTheCachesMissingFoldersAreMade0700AndAnExistingFolderKeepsItsMode() async throws {
        let served = try feed(try litellm.serializedString)
        defer { served.stop() }
        let base = try folder()
        chmod(base.path, 0o755)
        let cache = base.appendingPathComponent("made/deeper/anthropic-prices.json").path
        let options = PriceOptions(cache: cache, feed: served.baseURL + "/prices.json")
        let loaded = await PriceTables.refresh(PriceTables.initial(options).prices, options)
        XCTAssertEqual(loaded.source.kind, .fetched)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache))
        func mode(_ path: String) -> Int { ((try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? Int) ?? -1 }
        XCTAssertEqual(mode(base.appendingPathComponent("made").path), 0o700)
        XCTAssertEqual(mode(base.appendingPathComponent("made/deeper").path), 0o700)
        XCTAssertEqual(mode(base.path), 0o755)
    }

    func testAFreshCacheIsInForceAndNoRefreshIsDue() throws {
        let url = "http://127.0.0.1:1/prices.json"
        let cache = try folder().appendingPathComponent("anthropic-prices.json")
        try reduced(url, "2026-09-28T12:00:00.000Z").json.serialized().write(to: cache)
        let start = try XCTUnwrap(PriceTables.date("2026-09-28T12:00:00.000Z"))
        let later = PriceOptions(cache: cache.path, feed: url, now: { start.addingTimeInterval(PriceTables.refreshAfter - 0.001) })
        let initial = PriceTables.initial(later)
        XCTAssertEqual(initial.prices.source, PriceSource(kind: .cached, asOf: "2026-09-28T12:00:00.000Z"))
        XCTAssertFalse(initial.refreshDue)
        let future = PriceOptions(cache: cache.path, feed: url, now: fixed("2026-09-27T12:00:00.000Z"))
        XCTAssertTrue(PriceTables.initial(future).refreshDue)
        let stale = PriceOptions(cache: cache.path, feed: url, now: { start.addingTimeInterval(PriceTables.refreshAfter) })
        XCTAssertTrue(PriceTables.initial(stale).refreshDue)
    }

    func testAStaleCacheAndADeadFeedKeepTheCacheWithTheProblem() async throws {
        let url = "http://127.0.0.1:1/prices.json"  // nothing listens on port 1
        let cache = try folder().appendingPathComponent("anthropic-prices.json")
        try reduced(url, "2026-09-27T11:00:00.000Z").json.serialized().write(to: cache)
        let before = try Data(contentsOf: cache)
        let options = PriceOptions(cache: cache.path, feed: url, now: fixed("2026-09-28T12:00:00.000Z"))
        let initial = PriceTables.initial(options)
        XCTAssertTrue(initial.refreshDue)
        XCTAssertEqual(initial.prices.source.kind, .cached)
        let loaded = await PriceTables.refresh(initial.prices, options)
        XCTAssertEqual(loaded.source.kind, .cached)
        XCTAssertEqual(loaded.source.asOf, "2026-09-27T11:00:00.000Z")
        XCTAssertTrue(loaded.source.problem?.hasPrefix("fetching \(url): ") == true, loaded.source.problem ?? "nil")
        XCTAssertEqual(try Data(contentsOf: cache), before)
    }

    func testARejectedDocumentKeepsTheBundledTableAndWritesNothing() async throws {
        let served = try feed(try withoutFable().serializedString)
        defer { served.stop() }
        let cache = try folder().appendingPathComponent("anthropic-prices.json").path
        let feedURL = served.baseURL + "/prices.json"
        let options = PriceOptions(cache: cache, feed: feedURL)
        let loaded = await PriceTables.refresh(PriceTables.initial(options).prices, options)
        XCTAssertEqual(loaded.source.kind, .bundled)
        XCTAssertEqual(loaded.source.problem, "\(feedURL) was rejected: no claude-fable-5-1 row")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache))
        // A failed status is said by its number and writes nothing either.
        let failing = try feed("{}", status: 404)
        defer { failing.stop() }
        let failed = await PriceTables.refresh(loaded, PriceOptions(cache: cache, feed: failing.baseURL + "/p.json"))
        XCTAssertEqual(failed.source.problem, "fetching \(failing.baseURL)/p.json: HTTP 404")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache))
    }

    func testAnInsecureFeedIsRefusedBeforeAnyRequest() async throws {
        XCTAssertNil(PriceTables.feedProblem(PriceTables.liteLLMURL))
        XCTAssertNil(PriceTables.feedProblem("http://127.0.0.1:9/x"))
        XCTAssertNil(PriceTables.feedProblem("http://localhost:9/x"))
        XCTAssertNil(PriceTables.feedProblem("http://[::1]:9/x"))
        let insecure = "http://example.invalid/"
        XCTAssertEqual(PriceTables.feedProblem(insecure), "the price feed \(insecure) is neither https nor a loopback http URL")
        let cache = try folder().appendingPathComponent("anthropic-prices.json").path
        let options = PriceOptions(cache: cache, feed: insecure)
        let loaded = await PriceTables.refresh(PriceTables.initial(options).prices, options)
        XCTAssertEqual(loaded.source.problem, "the price feed \(insecure) is neither https nor a loopback http URL")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache))
    }

    func testAnUnreadableCacheIsDueAndSaysWhy() throws {
        let cache = try folder().appendingPathComponent("anthropic-prices.json")
        try Data("{ not json".utf8).write(to: cache)
        let initial = PriceTables.initial(PriceOptions(cache: cache.path, feed: nil))
        XCTAssertTrue(initial.refreshDue)
        XCTAssertEqual(initial.prices.source.kind, .bundled)
        XCTAssertTrue(initial.prices.source.problem?.hasPrefix("the price cache is unreadable: ") == true)
    }

    /// The TypeScript helper writes the cache indented (`JSON.stringify(table, null, 2)`), with
    /// `toISOString`'s milliseconds; this helper reads that file, and its own compact one.
    func testACacheInTheBunHelpersLayoutIsRead() throws {
        let cache = try folder().appendingPathComponent("anthropic-prices.json")
        let table = try reduced("https://feed.example/p.json", "2026-09-28T12:00:00.000Z")
        let pretty = try JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: table.json.serialized()),
                                                options: [.prettyPrinted])
        try (pretty + Data("\n".utf8)).write(to: cache)
        let options = PriceOptions(cache: cache.path, feed: nil, now: fixed("2026-09-28T13:00:00.000Z"))
        let initial = PriceTables.initial(options)
        XCTAssertEqual(initial.prices.source, PriceSource(kind: .cached, asOf: "2026-09-28T12:00:00.000Z"))
        XCTAssertFalse(initial.refreshDue)
        XCTAssertEqual(initial.prices.table.models.jsonValueObject, table.models.jsonValueObject)
        // A `fetched_at` without fractional seconds is read too.
        XCTAssertEqual(PriceTables.date("2026-09-28T12:00:00Z"), PriceTables.date("2026-09-28T12:00:00.000Z"))
    }
}

extension RawJSONObject {
    /// The object as `toEqual` compares it: key order does not count, and a number is its
    /// value (`20.0` in update.py's file is `20`).
    var jsonValueObject: JSONValue { RawJSON.object(self).numeric }
}

extension RawJSON {
    var numeric: JSONValue {
        switch self {
        case .number(let n): return .double(n.doubleValue ?? .nan)
        case .array(let a): return .array(a.map(\.numeric))
        case .object(let o): return .object(Dictionary(uniqueKeysWithValues: o.map { ($0.key, $0.value.numeric) }))
        default: return jsonValue
        }
    }
}
