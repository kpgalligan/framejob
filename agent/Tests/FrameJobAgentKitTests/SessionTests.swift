import Anthropic
import FrameJobAgentKit
import XCTest

/// configure, the refusals, settings, `reset`, and the context limit.
final class SessionTests: XCTestCase {
    func testSendBeforeConfigureIsRefusedWithoutTurnEvents() async {
        let h = Harness()
        await h.line(HostMessage.send(text: "Hi").json)
        XCTAssertEqual(h.sink.events, [.error("The assistant helper was not configured.")])
        XCTAssertEqual(h.api.requests.count, 0)
    }

    func testASendDuringATurnIsRefused() async {
        let h = Harness(ScriptedAPI([.sse([SSE.messageStart()], hang: true)]))
        await h.configure()
        await h.line(HostMessage.send(text: "First").json)
        await h.sink.waitUntil { _ in h.api.requests.count == 1 }
        await h.line(HostMessage.send(text: "Second").json)
        XCTAssertEqual(h.sink.errors, ["The assistant is busy."])
        XCTAssertEqual(h.sink.count(of: .turnStarted), 1)
        await h.line(HostMessage.cancel.json)
        await h.sink.waitUntil { $0.contains(.turnFinished) }
        // The refused text never reached the history.
        let history = await h.history
        XCTAssertEqual(RawJSON.array(history).serializedString, #"[{"role":"user","content":[{"type":"text","text":"First"}]}]"#)
    }

    func testBadAndBlankLines() async {
        let h = Harness()
        await h.line("   ")
        await h.line("")
        await h.line("{nope")
        await h.line(#"{"type":"send"}"#)
        XCTAssertEqual(h.sink.events.count, 2)
        for message in h.sink.errors { XCTAssertTrue(message.hasPrefix("Bad message from the app: "), message) }
        XCTAssertEqual(h.sink.errors.last, "Bad message from the app: send needs a string text")
        // An unknown type is ignored, as is an answer no call waits for.
        await h.line(#"{"type":"mystery"}"#)
        await h.line(#"{"type":"tool_result","call_id":"99","result":null}"#)
        XCTAssertEqual(h.sink.events.count, 2)
    }

    /// Spec §11 SA-6: `reset`, which the app never sends, is ignored like any unknown type. The
    /// TypeScript helper's arm aborted the turn, emptied the history and reported the context at 0.
    func testResetIsIgnoredAndTheHistoryKept() async throws {
        let h = Harness(ScriptedAPI([.sse(SSE.reply(SSE.text(0, "One"))), .sse(SSE.reply(SSE.text(0, "Two")))]))
        await h.configure()
        await h.turn("First")
        let before = h.sink.events.count
        let history = await h.history
        await h.line(#"{"type":"reset"}"#)
        XCTAssertEqual(h.sink.events.count, before, "reset answers nothing")
        let after = await h.history
        XCTAssertEqual(after, history)
        await h.turn("Second")
        XCTAssertEqual(try h.api.body(1)["messages"]?.arrayValue?.count, 3)
    }

    func testConfigureAnswersPricesThenReadyThenTheContextLimit() async {
        let h = Harness()
        await h.configure()
        XCTAssertEqual(h.sink.events, [
            .prices(Fixtures.unconfiguredSource), .ready, .contextUsage(used: 0, limit: 1_000_000),
        ])
    }

    func testAModelsFailureLeavesTheLimitUnknown() async {
        let api = ScriptedAPI(models: .status(404, body: #"{"type":"error","error":{"type":"not_found_error","message":"no"}}"#))
        let h = Harness(api)
        await h.configure()
        XCTAssertEqual(h.sink.events, [.prices(Fixtures.unconfiguredSource), .ready, .contextUsage(used: 0, limit: nil)])
    }

    /// Spec §11 AI-20: settings that change while a tool call waits do not reach the same turn's next
    /// round, whose clearing and betas are the turn's, but their compaction limit applies at this turn's
    /// end: round 2's reply (200 tokens) is past the new limit of 100, so the summary is asked for, still
    /// without clearing, and the next turn clears.
    func testSettingsApplyFromTheNextTurnAndTheirLimitAtThisTurnsEnd() async throws {
        let base = "thinking-display-updates-2026-08-18,server-side-fallback-2026-07-01,compact-2026-09-04"
        let summary = SSE.reply(
            [SSE.start(0, #"{"type":"compaction","content":null}"#),
             SSE.delta(0, #"{"type":"compaction_delta","content":"A frame was rendered."}"#), SSE.stop(0)],
            stop: "compaction", usage: #"{"output_tokens":40,"iterations":[{"type":"compaction","input_tokens":200,"output_tokens":40}]}"#)
        let h = Harness(ScriptedAPI([
            .sse(SSE.reply(SSE.toolUse(0, id: "toolu_s", name: "render_frame", input: "{}"), stop: "tool_use")),
            .sse(SSE.reply(SSE.text(0, "rendered"), startUsage: #"{"input_tokens":190,"output_tokens":1}"#,
                           usage: #"{"output_tokens":10}"#)),
            .sse(summary),
            .sse(SSE.reply(SSE.text(0, "ok"))),
        ]))
        await h.configure()
        await h.line(HostMessage.send(text: "one").json)
        await h.sink.waitUntil { _ in h.sink.toolRequests.count == 1 }
        await h.line(HostMessage.settings(ChatSettings(autoCompactTokens: 100, clearToolResults: true)).json)
        await h.answer(h.sink.toolRequests[0].callID, #"{"content":[{"type":"text","text":"ok"}]}"#)
        await h.sink.waitUntil { $0.contains(.turnFinished) }
        XCTAssertEqual(h.api.requests.count, 3)
        XCTAssertEqual(Array(h.sink.lastTurnPlain.suffix(5)), [
            .contextUsage(used: 200, limit: 1_000_000), .compactionStarted(used: 200), .compacted(before: 200, after: 40),
            .contextUsage(used: 40, limit: 1_000_000), .turnFinished,
        ])
        // Without the summary request the indexes below would trap rather than fail.
        guard h.api.requests.count == 3 else { return }
        XCTAssertNotNil(try h.api.body(2)["compaction"])
        for request in 0..<3 {
            XCTAssertNil(try h.api.body(request)["context_management"])
            XCTAssertEqual(h.api.requests[request].headers["anthropic-beta"], base)
        }
        await h.turn("two")
        XCTAssertNotNil(try h.api.body(3)["context_management"])
        XCTAssertEqual(h.api.requests[3].headers["anthropic-beta"], base + ",context-management-2025-06-27")
    }

    /// Spec §11 AI-20: compaction turned off while a tool call waits is off at that turn's end, though
    /// the turn started with a limit its final reply passes.
    func testALimitTurnedOffMidTurnDoesNotCompactAtItsEnd() async {
        let h = Harness(ScriptedAPI([
            .sse(SSE.reply(SSE.toolUse(0, id: "toolu_t", name: "render_frame", input: "{}"), stop: "tool_use")),
            .sse(SSE.reply(SSE.text(0, "rendered"), startUsage: #"{"input_tokens":190,"output_tokens":1}"#,
                           usage: #"{"output_tokens":10}"#)),
        ]))
        await h.configure(Fixtures.configure(ChatSettings(autoCompactTokens: 100, clearToolResults: false)))
        await h.line(HostMessage.send(text: "one").json)
        await h.sink.waitUntil { _ in h.sink.toolRequests.count == 1 }
        await h.line(HostMessage.settings(ChatSettings(autoCompactTokens: nil, clearToolResults: false)).json)
        await h.answer(h.sink.toolRequests[0].callID, #"{"content":[{"type":"text","text":"ok"}]}"#)
        await h.sink.waitUntil { $0.contains(.turnFinished) }
        XCTAssertEqual(h.api.requests.count, 2)
        XCTAssertEqual(Array(h.sink.lastTurnPlain.suffix(2)), [.contextUsage(used: 200, limit: 1_000_000), .turnFinished])
    }

    func testErrorWording() {
        let response = HTTPResponse(statusCode: 200, body: Data(), request: HTTPRequest(method: "POST", url: URL(fileURLWithPath: "/")))
        let mapped = APIStatusError("raw", response: response, body: ["error": ["type": "overloaded_error", "message": "Overloaded"]],
                                    statusCode: 529)
        XCTAssertEqual(AgentSession.describe(mapped), "API error 529: Overloaded")
        let unmapped = APIStatusError("{'error': ...}", response: response, body: ["error": ["type": "mystery", "message": "Odd"]])
        XCTAssertEqual(AgentSession.describe(unmapped), "API error: Odd")
        let bare = APIStatusError("Error code: 502", response: HTTPResponse(statusCode: 502, body: Data(), request: response.request), body: nil)
        XCTAssertEqual(AgentSession.describe(bare), "API error 502: Error code: 502")
        XCTAssertEqual(AgentSession.describe(APIConnectionError(request: nil)), "API error: Connection error.")
        XCTAssertEqual(AgentSession.describe(ProtocolError("send needs a string text")), "send needs a string text")
    }
}
