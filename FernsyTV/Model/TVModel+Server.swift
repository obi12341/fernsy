import FernsyCore
import FernsyPlayer
import Foundation
#if os(iOS)
import UIKit
#endif

/// Fernsy Server on Apple TV, iPhone and iPad (headless-recorder, server-recording-everywhere).
extension TVModel {
    /// The device's name on the orders it writes, as the lists show it.
    var serverDeviceName: String {
        #if os(iOS)
        UIDevice.current.name
        #else
        "Apple TV"
        #endif
    }

    /// Orders a show on the server through the shared step (design 1): no second order for a
    /// show the server already has, none that would start now without a free stream.
    func orderOnServer(_ show: EPGEntry, on channel: LiveChannel) async throws(ServerModel.OrderFailure) -> (order: ServerModel.Order, isNew: Bool) {
        try await cloud.server.order(show, on: channel, padding: Recorder.padding, createdBy: serverDeviceName,
                                     streamsInUse: tuners.connectionsInUse, limit: tuners.limit)
    }
}
