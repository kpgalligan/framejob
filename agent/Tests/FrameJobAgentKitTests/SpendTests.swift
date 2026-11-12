import Anthropic
@testable import FrameJobAgentKit
import XCTest

/// What the spend figures read (spec §11 P-5, P-8, SA-3, SA-6): `prices` at configure, each
/// response's `message_done` and `cost`, a response cut short priced once as partial, a turn
/// keeping the prices it started with, and a tool wait of any length.
final class SpendTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("framejob-spend-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private let bundled = PriceTables.bundled()

    private func price(_ usage: RawJSON?) -> Price {
        Pricing.price(usage: usage ?? .null, model: "claude-opus-5-5", table: bundled.table)
    }

    func testMessageDoneThenCostPerResponseInOrder() async throws {
        let h = Harness(ScriptedAPI([
            .sse(SSE.reply(SSE.toolUse(0, id: "toolu_m", name: "add_marker", input: #"{"at":2}"#), stop: "tool_use")),
            .sse(SSE.reply(SSE.text(0, "Marked."), usage: #"{"output_tokens":7}"#)),
        ]))
        await h.configure()
        await h.line(HostMessage.send(text: "Mark two seconds").json)
        await h.sink.waitUntil { _ in h.sink.toolRequests.count == 1 }
        await h.answer("1", #"{"content":[{"type":"text","text":"ok"}]}"#)
        await h.sink.waitUntil { $0.contains(.turnFinished) }
        let first: RawJSON = ["input_tokens": 10, "output_tokens": 5]
        let second: RawJSON = ["input_tokens": 10, "output_tokens": 7]
        let source = Fixtures.unconfiguredSource
        XCTAssertEqual(h.sink.lastTurn, [
            .turnStarted,
            .messageDone(stopReason: "tool_use", usage: first),
            .cost(model: "claude-opus-5-5", usage: first, cost: price(first), prices: source, partial: false),
            .contextUsage(used: 15, limit: 1_000_000),
            .toolCall(name: "add_marker", arguments: ["at": 2]),
            .toolRequest(callID: "1", name: "add_marker", argumentsJSON: #"{"at":2}"#),
            .toolResult(name: "add_marker", isError: false, summary: "ok"),
            .textDelta("Marked."),
            .messageDone(stopReason: "end_turn", usage: second),
            .cost(model: "claude-opus-5-5", usage: second, cost: price(second), prices: source, partial: false),
            .contextUsage(used: 17, limit: 1_000_000),
            .turnFinished,
        ])
        guard case .dollars(let dollars, let rows) = price(second) else { return XCTFail("not priced") }
        XCTAssertGreaterThan(dollars, 0)
        XCTAssertEqual(rows, ["claude-opus-5-5"])
    }

    func testASummaryIsPricedBeforeItsReportAndHasNoMessageDone() async {
        let h = Harness(ScriptedAPI([
            .sse(SSE.reply(SSE.text(0, "Done"), startUsage: #"{"input_tokens":90,"output_tokens":1}"#, usage: #"{"output_tokens":20}"#)),
            .sse(SSE.reply([SSE.start(0, #"{"type":"compaction","content":"Short."}"#), SSE.stop(0)], stop: "compaction",
                           usage: #"{"output_tokens":3,"iterations":[{"type":"compaction","input_tokens":110,"output_tokens":3}]}"#)),
        ]))
        await h.configure(Fixtures.configure(ChatSettings(autoCompactTokens: 100, clearToolResults: false)))
        await h.turn("Trim")
        let turn = h.sink.lastTurn
        XCTAssertEqual(turn.filter { if case .messageDone = $0 { true } else { false } }.count, 1, "the final reply's only")
        guard let started = turn.firstIndex(of: .compactionStarted(used: 110)),
              let compacted = turn.firstIndex(of: .compacted(before: 110, after: 3)) else { return XCTFail("\(turn)") }
        XCTAssertEqual(compacted, started + 2)
        guard case .cost(_, let usage, _, _, let partial) = turn[started + 1] else { return XCTFail("\(turn[started + 1])") }
        XCTAssertEqual(usage?["iterations"]?[0]?["type"], "compaction")
        XCTAssertFalse(partial)
    }

    /// spend_proof.py's H10: a stream dropped after `message_start` is priced once, partial, from
    /// `message_start`'s counts and output 0 (P-8's lower bound), before the error; no message_done.
    func testAStreamDroppedAfterMessageStartIsPricedPartialBeforeTheError() async {
        let start: RawJSON = ["input_tokens": 100, "output_tokens": 0]
        let h = Harness(ScriptedAPI([.sse([SSE.messageStart(usage: start.serializedString),
                                           SSE.start(0, #"{"type":"text","text":""}"#), SSE.delta(0, #"{"type":"text_delta","text":"Hel"}"#)])]))
        await h.configure()
        await h.turn("Hi")
        XCTAssertEqual(h.sink.lastTurn, [
            .turnStarted, .textDelta("Hel"),
            .cost(model: "claude-opus-5-5", usage: start, cost: price(start), prices: Fixtures.unconfiguredSource, partial: true),
            .error("API error: The stream ended before its `message_stop` event."), .turnFinished,
        ])
    }

    /// H11: a Stop after `message_delta` prices the response once, partial, with the delta's
    /// output count, and reports no error.
    func testACancelAfterMessageDeltaIsPricedPartialWithNoError() async {
        let delta = SSE.event("message_delta",
                              #"{"type":"message_delta","delta":{"stop_reason":null,"stop_sequence":null},"usage":{"output_tokens":10}}"#)
        let h = Harness(ScriptedAPI([.sse([SSE.messageStart(usage: #"{"input_tokens":100,"output_tokens":0}"#), delta,
                                           SSE.start(0, #"{"type":"text","text":""}"#), SSE.delta(0, #"{"type":"text_delta","text":"Wo"}"#)],
                                          hang: true)]))
        await h.configure()
        await h.line(HostMessage.send(text: "Hi").json)
        await h.sink.waitUntil { $0.contains(.textDelta("Wo")) }
        await h.line(HostMessage.cancel.json)
        await h.sink.waitUntil { $0.contains(.turnFinished) }
        let usage: RawJSON = ["input_tokens": 100, "output_tokens": 10]
        XCTAssertEqual(h.sink.lastTurn, [
            .turnStarted, .textDelta("Wo"),
            .cost(model: "claude-opus-5-5", usage: usage, cost: price(usage), prices: Fixtures.unconfiguredSource, partial: true),
            .turnFinished,
        ])
    }

    /// A request that fails before `message_start` has no snapshot: no `cost` at all.
    func testARequestThatFailsBeforeMessageStartIsNotPriced() async {
        let h = Harness(ScriptedAPI([.status(400, body: #"{"type":"error","error":{"type":"invalid_request_error","message":"Bad body"}}"#)]))
        await h.configure()
        await h.turn("Hi")
        XCTAssertEqual(h.sink.lastTurn, [.turnStarted, .error("API error 400: Bad body"), .turnFinished])
        XCTAssertTrue(h.sink.costs.isEmpty)
    }

    /// H12: a complete `tool_use` reply, then a Stop during the tool wait: that reply is priced
    /// once, complete, and nothing more is requested.
    func testACancelDuringTheToolWaitPricesTheCompleteReplyOnce() async throws {
        let h = Harness(ScriptedAPI([
            .sse(SSE.reply(SSE.toolUse(0, id: "toolu_h", name: "render_frame", input: "{}"), stop: "tool_use")),
            .sse(SSE.reply(SSE.text(0, "never sent"))),
        ]))
        await h.configure()
        await h.line(HostMessage.send(text: "Render").json)
        await h.sink.waitUntil { _ in h.sink.toolRequests.count == 1 }
        await h.line(HostMessage.cancel.json)
        await h.answer("1", #"{"content":[{"type":"text","text":"Cancelled by the user."}],"isError":true}"#)
        await h.sink.waitUntil { $0.contains(.turnFinished) }
        XCTAssertEqual(h.sink.costs.map(\.partial), [false])
        XCTAssertEqual(h.api.requests.count, 1)
        XCTAssertEqual(h.sink.errors, [])
    }

    /// `prices` comes after `ready` when a refresh is due, and a refresh that settles mid-turn
    /// prices the next turn, never the rest of this one (P-5).
    func testATurnKeepsItsPricesThroughARefresh() async throws {
        let gate = DispatchSemaphore(value: 0)
        let document = try PriceFiles.json("reduce_cases.json")["litellm"]?.serializedString ?? "{}"
        let feed = try LoopbackServer { _ in
            gate.wait()
            return LoopbackServer.response(200, body: document)
        }
        defer { feed.stop() }
        let cache = scratch.appendingPathComponent("spend/anthropic-prices.json").path
        let h = Harness(ScriptedAPI([
            .sse(SSE.reply(SSE.toolUse(0, id: "toolu_p", name: "get_project", input: "{}"), stop: "tool_use")),
            .sse(SSE.reply(SSE.text(0, "Done."))),
            .sse(SSE.reply(SSE.text(0, "Again."))),
        ]))
        await h.configure(Fixtures.configure(priceCache: cache, priceFeed: feed.baseURL + "/prices.json"))
        XCTAssertFalse(h.sink.events.contains { if case .prices = $0 { true } else { false } }, "nothing before the refresh")
        await h.line(HostMessage.send(text: "One").json)
        await h.sink.waitUntil { _ in h.sink.toolRequests.count == 1 }
        gate.signal()
        await h.sink.waitUntil { $0.contains { if case .prices(let s) = $0 { s.kind == .fetched } else { false } } }
        let ready = try XCTUnwrap(h.sink.events.firstIndex(of: .ready))
        let prices = try XCTUnwrap(h.sink.events.firstIndex { if case .prices = $0 { true } else { false } })
        XCTAssertLessThan(ready, prices)
        await h.answer("1", #"{"content":[{"type":"text","text":"{}"}]}"#)
        await h.sink.waitUntil { $0.contains(.turnFinished) }
        XCTAssertEqual(h.sink.costs.map(\.prices.kind), [.bundled, .bundled], "the turn's own prices, both responses")
        await h.turn("Two")
        XCTAssertEqual(h.sink.costs.map(\.prices.kind), [.bundled, .bundled, .fetched])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache))
    }

    /// No timeout on a tool wait and no request while an answer is outstanding (spec §11 AI-7,
    /// SA-2): an ask-first question held in the app is a long wait, and a cancel does not end it.
    func testAToolWaitOfAnyLengthHoldsTheNextRequest() async throws {
        let h = Harness(ScriptedAPI([
            .sse(SSE.reply(SSE.toolUse(0, id: "toolu_w", name: "add_marker", input: #"{"at":1}"#), stop: "tool_use")),
            .sse(SSE.reply(SSE.text(0, "Marked."))),
            .sse(SSE.reply(SSE.toolUse(0, id: "toolu_v", name: "add_marker", input: #"{"at":2}"#), stop: "tool_use")),
        ]))
        await h.configure()
        await h.line(HostMessage.send(text: "Mark one").json)
        await h.sink.waitUntil { _ in h.sink.toolRequests.count == 1 }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(h.api.requests.count, 1)
        XCTAssertFalse(h.sink.events.contains(.turnFinished))
        await h.answer("1", #"{"content":[{"type":"text","text":"ok"}]}"#)
        await h.sink.waitUntil { $0.contains(.turnFinished) }
        XCTAssertEqual(h.api.requests.count, 2)
        // The same wait with a cancel inside it: still no request and no end until the answer.
        await h.line(HostMessage.send(text: "Mark two").json)
        await h.sink.waitUntil { _ in h.sink.toolRequests.count == 2 }
        await h.line(HostMessage.cancel.json)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(h.sink.count(of: .turnFinished), 1)
        XCTAssertEqual(h.api.requests.count, 3)
        await h.answer("2", #"{"content":[{"type":"text","text":"Cancelled by the user."}],"isError":true}"#)
        await h.sink.waitUntil { $0.filter { $0 == .turnFinished }.count == 2 }
        XCTAssertEqual(h.api.requests.count, 3)
    }
}
