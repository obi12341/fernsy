import Foundation

/// Fernsy Server in the recording tools (server-recording-everywhere design 4), shared by the
/// Mac's MCP tools and the tool runner of Apple TV and iOS so they answer alike: where to
/// record, the ids and JSON of server orders, and ordering, listing and cancelling them.
extension AssistantTools {
    /// Where `schedule_recording` records.
    public enum RecordingPlace: String, Sendable { case device, server }

    /// The `where` argument; nil when the request leaves it to the device.
    public static func place(_ args: [String: Any]) throws -> RecordingPlace? {
        guard let value = args["where"] else { return nil }
        guard let place = (value as? String).flatMap(RecordingPlace.init) else { throw ToolError("where is \"device\" or \"server\"") }
        return place
    }

    /// A server order's `recording_id`: "server:<order id>", as `cloud:<id>` names a cloud recording.
    public static func serverRecordingID(_ orderId: String) -> String { "server:" + orderId }

    /// The order id of a `recording_id` that names a server order; nil for a device's recording.
    public static func serverOrderID(_ recordingId: String) -> String? {
        recordingId.hasPrefix("server:") ? String(recordingId.dropFirst("server:".count)) : nil
    }

    /// An order's status: "sent" until the server has seen it, then its phase.
    public static func serverStatus(_ state: ControlOrderState?) -> String {
        switch state?.phase {
        case nil: "sent"
        case .scheduled: "scheduled"
        case .recording: "recording"
        case .uploading: "uploading"
        case .done: "done"
        case .failed: "failed"
        case .refused: "refused"
        }
    }

    /// A server order as `list_recordings` and `schedule_recording` give it.
    public static func serverOrderJSON(_ row: ServerModel.Order) -> [String: Any] {
        let order = row.order
        var value: [String: Any] = [
            "recording_id": serverRecordingID(row.id), "where": "server", "channel_id": order.channelId, "channel": order.channelName,
            "title": order.title, "status": serverStatus(row.state),
            "show_start": iso(order.showStart), "show_end": iso(order.showEnd),
            "record_start": iso(order.showStart.addingTimeInterval(-order.padBefore)), "record_end": iso(order.showEnd.addingTimeInterval(order.padAfter)),
            "ordered_by": order.createdBy,
        ]
        if let reason = row.state?.reason { value["reason"] = ServerText.reason(reason) }
        return value
    }

    /// `schedule_recording` on the server: `order` is the device's ordering step
    /// (`ServerModel.order` with its padding and streams in use). "ordered", "already_ordered"
    /// for a show the server has, or "refused" when it would start now without a free stream.
    @MainActor
    public static func orderOnServer(_ server: ServerModel,
                                     order: () async throws(ServerModel.OrderFailure) -> (order: ServerModel.Order, isNew: Bool)) async throws -> [String: Any] {
        let placed: (order: ServerModel.Order, isNew: Bool)
        do {
            placed = try await order()
        } catch let failure as ServerModel.OrderFailure {
            switch failure {
            case .notPaired:
                throw ToolError("No Fernsy Server is paired. The user can pair one in Fernsy's settings (Fernsy Cloud › Fernsy Server; on the Mac under Recordings).")
            case .streamsInUse:
                return ["result": "refused", "where": "server", "reason": ServerText.order(failure)]
            case .locked, .network:
                throw ToolError(ServerText.order(failure))
            }
        } catch {
            throw ToolError(ServerText.order(caught: error))
        }
        var value: [String: Any] = ["result": placed.isNew ? "ordered" : "already_ordered", "where": "server", "recording": serverOrderJSON(placed.order)]
        // Its state was just read: an order for a server that is away waits until it is back.
        if !server.isOnline() { value["notice"] = ServerText.offline }
        return value
    }

    /// The server's part of `list_recordings`: its orders that are not in Fernsy Cloud yet,
    /// after a fresh look; none without a paired server. `status` is the tool's filter, where
    /// "scheduled" also takes orders the server has not seen yet.
    @MainActor
    public static func serverRecordings(_ server: ServerModel, status: String) async -> [[String: Any]] {
        await server.refresh()
        guard server.isPaired else { return [] }
        return server.orders.filter { $0.state?.phase != .done }.compactMap { row in
            let name = serverStatus(row.state)
            guard status == "all" || status == name || (status == "scheduled" && name == "sent") || (status == "failed" && name == "refused") else { return nil }
            return serverOrderJSON(row)
        }
    }

    /// The server order a `cancel_recording` request names, if it can still be removed (the
    /// server has not started it); throws the explanation otherwise.
    @MainActor
    public static func cancellableServerOrder(_ orderId: String, server: ServerModel) async throws -> ServerModel.Order {
        await server.refresh()
        guard let row = server.orders.first(where: { $0.id == orderId }) else { throw ToolError("No server order with this id") }
        guard row.state == nil || row.state?.phase == .scheduled else {
            throw ToolError("Only server orders that have not started can be cancelled; „\(row.order.title)“ is \(serverStatus(row.state)). Nothing was changed.")
        }
        return row
    }

    /// The question before a server order is removed (cloud-assistant design 5).
    public static func serverCancelQuestion(_ row: ServerModel.Order) -> String {
        let when = ItemText.channelAndTime(row.order.channelName, row.order.showStart)
        return String(localized: "Remove the recording of “\(row.order.title)” (\(when)) from Fernsy Server?", bundle: .module)
    }

    /// `cancel_recording` for a server order: asks through `confirm`, then removes it.
    @MainActor
    public static func cancelServerOrder(_ orderId: String, server: ServerModel, confirm: (String) async -> Bool) async throws -> [String: Any] {
        let row = try await cancellableServerOrder(orderId, server: server)
        let id = serverRecordingID(orderId)
        guard await confirm(serverCancelQuestion(row)) else {
            return ["result": "kept", "recording_id": id, "where": "server", "reason": "The user did not confirm; the order stays on the server."]
        }
        do { try await server.cancel(orderId) } catch { throw ToolError(ServerText.order(.network("\(error)"))) }
        AppLog.info(.recordings, "Fernsy Server: order for \(row.order.title) removed")
        return ["result": "cancelled", "recording_id": id, "where": "server"]
    }
}
