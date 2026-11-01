import FernsyCore
import Foundation

extension AppModel {
    /// The in-app assistant on the Mac (cloud-assistant): the tools the relay offers, run by the
    /// MCP server's `MCPTools` as for Claude Desktop, except that cancelling a recording asks the
    /// user first (design 5). The MCP server itself stays unchanged.
    func makeAssistant() -> AssistantModel {
        let tools = MCPTools(app: self)
        weak var asking: AssistantModel?
        let assistant = AssistantModel(cloud: cloud, platform: "Mac") { [weak self] name, args in
            guard AssistantTools.assistantNames.contains(name) else { throw AssistantTools.ToolError("\(name) is not available to the assistant.") }
            if name == "cancel_recording", let question = self?.cancelQuestion(args) {
                guard await asking?.confirm(question) == true else {
                    return ["result": "kept", "recording_id": args["recording_id"] ?? "", "reason": "The user did not confirm; the recording stays scheduled."]
                }
            }
            return try await tools.call(name, args)
        }
        asking = assistant
        return assistant
    }

    /// The question before a scheduled recording is removed; nil when there is none to remove
    /// (the tool then explains why).
    private func cancelQuestion(_ args: [String: Any]) -> String? {
        guard let id = (args["recording_id"] as? String).flatMap(UUID.init(uuidString:)),
              let recording = recorder.recordings.first(where: { $0.id == id }), recording.status == .scheduled else { return nil }
        let when = ItemText.channelAndTime(recording.channelName, recording.start)
        return String(localized: "Remove the scheduled recording of “\(recording.title)” (\(when))?")
    }
}
