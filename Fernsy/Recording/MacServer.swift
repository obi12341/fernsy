import FernsyCore
import FernsyPlayer
import Foundation

/// Fernsy Server on the Mac (headless-recorder, server-recording-everywhere): ordering a show
/// from every place that records one, with this Mac's padding and its count of streams in use.
extension AppModel {
    /// Orders a show on the server through the shared step (design 1): no second order for a
    /// show the server already has, none that would start now without a free stream.
    func orderOnServer(_ entry: EPGEntry, on channel: LiveChannel) async throws(ServerModel.OrderFailure) -> (order: ServerModel.Order, isNew: Bool) {
        try await cloud.server.order(entry, on: channel, padding: Recorder.padding, createdBy: Host.current().localizedName ?? "Mac",
                                     streamsInUse: tuners.connectionsInUse, limit: tuners.limit)
    }

    /// "Record on Server" from a button or menu: says why it did not work, or that the server is
    /// away right now (its state was just read, so "away" is not an old picture).
    func recordOnServer(_ entry: EPGEntry, on channel: LiveChannel) {
        Task {
            do {
                _ = try await orderOnServer(entry, on: channel)
                if !cloud.server.isOnline() { Prompt.inform(title: String(localized: "Recording on Fernsy Server"), message: ServerText.offline) }
            } catch {
                Prompt.inform(title: String(localized: "Can’t Record"), message: ServerText.order(caught: error))
            }
        }
    }

    /// "Remove from Server": the server drops the order, and stops it while it records.
    func removeFromServer(_ order: ServerModel.Order) {
        Task {
            do { try await cloud.server.cancel(order.id) } catch {
                Prompt.inform(title: String(localized: "Fernsy Server"), message: ServerText.order(.network("\(error)")))
            }
        }
    }
}
