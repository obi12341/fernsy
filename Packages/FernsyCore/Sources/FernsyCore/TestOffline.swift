import Foundation

/// `IPTV_TESTOFFLINE=1` (debug builds, offline-recording-downloads 3.3): every request of
/// Fernsy's sessions fails as without network, so the offline start can be tested on a Mac
/// whose network is on. The debug MCP tool `set_offline` switches it during a run.
public enum TestOffline {
    #if DEBUG
    nonisolated(unsafe) public static var isOn = ["1", "requests"].contains(ProcessInfo.processInfo.environment["IPTV_TESTOFFLINE"])
    /// `IPTV_TESTOFFLINE=requests`: the requests fail but the network path says there is
    /// network, as after a request timed out while the network was coming back.
    public static let keepsPath = ProcessInfo.processInfo.environment["IPTV_TESTOFFLINE"] == "requests"
    #else
    public static let isOn = false
    public static let keepsPath = false
    #endif

    /// Adds the failing protocol to a session's configuration (it answers only while `isOn`).
    public static func configure(_ config: URLSessionConfiguration) -> URLSessionConfiguration {
        #if DEBUG
        config.protocolClasses = [OfflineURLProtocol.self] + (config.protocolClasses ?? [])
        #endif
        return config
    }

    /// `URLSession.shared` and the system's default sessions.
    public static func installShared() {
        #if DEBUG
        URLProtocol.registerClass(OfflineURLProtocol.self)
        #endif
    }
}

#if DEBUG
final class OfflineURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        // The debug MCP server on 127.0.0.1 stays reachable for the tests.
        TestOffline.isOn && request.url?.host != "127.0.0.1"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
#endif
