import Foundation
import Testing
@testable import FernsyCore

/// The assistant's tools (cloud-assistant design 4): one source for the Mac's MCP server, the
/// apps and the Fernsy Cloud worker, whose copy (`cloud-server/assistant-tools.json`) must match.
/// `scripts/assistant-tools.sh` rewrites that copy.
struct AssistantToolsTests {
    static let workerCopy = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("cloud-server/assistant-tools.json")

    @Test func everyAssistantToolExists() {
        let names = Set(AssistantTools.definitions.compactMap { $0["name"] as? String })
        for name in AssistantTools.assistantNames { #expect(names.contains(name), "unknown tool \(name)") }
        #expect(AssistantTools.assistantDefinitions.count == AssistantTools.assistantNames.count)
    }

    @Test func diagnosticsAndImagesStayOut() {
        for name in ["get_log", "playback_diagnostics", "snapshot", "frames"] {
            #expect(!AssistantTools.assistantNames.contains(name), "\(name) is not an assistant tool")
        }
    }

    @Test func chatCompletionsForm() throws {
        let first = try #require(AssistantTools.assistantDefinitions.first)
        #expect(first["type"] as? String == "function")
        let function = try #require(first["function"] as? [String: Any])
        #expect(function["name"] as? String == "find_channels")
        #expect((function["parameters"] as? [String: Any])?["type"] as? String == "object")
    }

    @Test func workerCopyMatches() throws {
        let current = try AssistantTools.assistantJSON()
        if ProcessInfo.processInfo.environment["FERNSY_WRITE_ASSISTANT_TOOLS"] == "1" {
            try current.write(to: Self.workerCopy)
        }
        let copy = try Data(contentsOf: Self.workerCopy)
        #expect(copy == current, "cloud-server/assistant-tools.json is out of date: run scripts/assistant-tools.sh")
    }
}
