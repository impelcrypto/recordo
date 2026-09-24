import XCTest
@testable import RecordoKit

final class ClaudeRunnerTests: XCTestCase {
    func json(_ data: Data) -> NSDictionary? {
        try? JSONSerialization.jsonObject(with: data) as? NSDictionary
    }

    func testParseReturnsTheStructuredOutput() throws {
        let output = Data(#"{"type":"result","is_error":false,"result":"","structured_output":{"ok":true}}"#.utf8)
        XCTAssertEqual(json(try ClaudeRunner.parse(output)), ["ok": true])
    }

    func testParseRecognisesALoggedOutCli() {
        let output = Data(#"{"is_error":true,"result":"Not logged in · Please run /login"}"#.utf8)
        XCTAssertThrowsError(try ClaudeRunner.parse(output)) { XCTAssertEqual($0 as? ClaudeError, .notLoggedIn) }
    }

    func testParseReportsOtherErrors() {
        let output = Data(#"{"is_error":true,"result":"boom"}"#.utf8)
        XCTAssertThrowsError(try ClaudeRunner.parse(output)) { XCTAssertEqual($0 as? ClaudeError, .failed("boom")) }
    }

    func testParseRejectsMissingOrBrokenOutput() {
        for raw in [#"{"is_error":false,"result":"hi"}"#, "not json", ""] {
            XCTAssertThrowsError(try ClaudeRunner.parse(Data(raw.utf8))) {
                XCTAssertEqual($0 as? ClaudeError, .badResponse, raw)
            }
        }
    }

    func testEveryCallSkipsHistoryAndLoadsNothingExtra() {
        let arguments = ClaudeRunner.arguments(prompt: "P", schema: "{}", model: "sonnet")
        XCTAssertEqual(arguments.first, "-p")
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        let tools = try! XCTUnwrap(arguments.firstIndex(of: "--tools"))
        XCTAssertEqual(arguments[tools + 1], "")
        XCTAssertEqual(arguments.last, "P")
        XCTAssertEqual(ClaudeRunner.environment(["HOME": "/x"])["CLAUDE_CODE_SKIP_PROMPT_HISTORY"], "1")
        XCTAssertEqual(ClaudeRunner.environment(["HOME": "/x"])["HOME"], "/x")
    }

    func testResolvePrefersTheOverrideThenTheLookup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tool = dir.appendingPathComponent("claude")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        XCTAssertEqual(ClaudePath.resolve(override: tool.path, lookup: { nil })?.path, tool.path)
        XCTAssertEqual(ClaudePath.resolve(override: nil, lookup: { "noise from zshrc\n" + tool.path })?.path, tool.path)
        XCTAssertEqual(ClaudePath.resolve(override: "", lookup: { tool.path + "\n" })?.path, tool.path)
        XCTAssertNil(ClaudePath.resolve(override: nil, lookup: { nil }))
        XCTAssertNil(ClaudePath.resolve(override: dir.appendingPathComponent("missing").path, lookup: { tool.path }))
    }

    func testLiveRunReturnsStructuredOutput() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLAUDE_LIVE"] == "1", "set CLAUDE_LIVE=1 to call the real claude")
        let path = try XCTUnwrap(ClaudePath.resolve(override: nil, lookup: ClaudePath.loginShellLookup))
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runner = ClaudeRunner(executable: path, workDir: workDir)
        let schema = #"{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"]}"#
        let data = try await runner.run(prompt: "Return ok=true.", schema: schema)
        XCTAssertEqual(json(data), ["ok": true])
    }
}
