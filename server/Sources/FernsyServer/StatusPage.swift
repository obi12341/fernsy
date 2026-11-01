#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
import Darwin
#endif
import Foundation

/// The local status page (design 4, 6): `/` as HTML, `/status.json` for scripts. A minimal
/// HTTP/1.0 server on its own thread; it answers GET only and shows no secrets (the pairing
/// code is meant to be read, and only while unpaired).
final class StatusPage: @unchecked Sendable {
    let board: StatusBoard
    let port: UInt16

    init(board: StatusBoard, port: UInt16) {
        self.board = board
        self.port = port
    }

    func start() throws {
        #if canImport(Glibc)
        let fd = socket(AF_INET6, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var yes: Int32 = 1, no: Int32 = 0
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, Int32(IPPROTO_IPV6), IPV6_V6ONLY, &no, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in6()
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        address.sin6_addr = in6addr_any
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE)
        }
        let thread = Thread { [self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { continue }
                handle(client)
            }
        }
        thread.start()
    }

    private func handle(_ client: Int32) {
        defer { close(client) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(client, &buffer, buffer.count)
        guard count > 0, let request = String(bytes: buffer[0..<count], encoding: .utf8) else { return }
        let parts = request.split(separator: " ", maxSplits: 2)
        let path = parts.count > 1 ? String(parts[1]) : "/"
        let response: (status: String, type: String, body: Data)
        if parts.first != "GET" {
            response = ("405 Method Not Allowed", "text/plain", Data("GET only\n".utf8))
        } else if path == "/status.json" {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            response = ("200 OK", "application/json", (try? encoder.encode(board.current)) ?? Data())
        } else if path == "/" {
            response = ("200 OK", "text/html; charset=utf-8", Data(Self.html(board.current).utf8))
        } else {
            response = ("404 Not Found", "text/plain", Data("not found\n".utf8))
        }
        let head = "HTTP/1.0 \(response.status)\r\nContent-Type: \(response.type)\r\nContent-Length: \(response.body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        let all = Data(head.utf8) + response.body
        all.withUnsafeBytes { raw in
            var sent = 0
            while sent < all.count {
                let n = write(client, raw.baseAddress! + sent, all.count - sent)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func html(_ s: StatusBoard.Snapshot) -> String {
        let time = { (d: Date?) in d.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "–" }
        var body = ""
        if !s.paired {
            body += "<p>Not paired. Enter this code in Fernsy under Settings › Fernsy Cloud › Server:</p>"
            body += "<p class=code>\(escape(s.pairingCode ?? "…"))</p>"
            if let expires = s.pairingExpires { body += "<p class=dim>Valid until \(time(expires)); a new one follows.</p>" }
        } else if let status = s.status {
            body += "<p>Paired. Last contact \(time(status.lastContact))."
            if let free = status.freeBytes { body += " Free space \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))." }
            if let limit = status.streamLimit { body += " Stream limit \(limit)." }
            body += "</p>"
            if let error = status.error { body += "<p class=error>\(escape(error))</p>" }
            if let start = status.nextStart { body += "<p>Next recording starts \(time(start)).</p>" }
            body += "<table><tr><th>Show</th><th>Channel</th><th>Time</th><th>State</th></tr>"
            for row in s.orders.prefix(50) {
                let state = row.phase + (row.reason.map { " (\($0))" } ?? "")
                body += "<tr><td>\(escape(row.title))</td><td>\(escape(row.channel))</td><td>\(time(row.start))</td><td>\(escape(state))</td></tr>"
            }
            body += "</table>"
        } else {
            body += "<p>Paired, starting…</p>"
        }
        return """
        <!doctype html><html><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
        <meta http-equiv=refresh content=15><title>Fernsy Server</title>
        <style>body{font:16px -apple-system,system-ui,sans-serif;margin:24px auto;max-width:760px;padding:0 16px;color:#222}
        .code{font:600 40px ui-monospace,monospace;letter-spacing:4px}.dim{color:#777}.error{color:#b00020}
        table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:6px 8px;border-bottom:1px solid #ddd}
        @media(prefers-color-scheme:dark){body{background:#111;color:#eee}td,th{border-color:#333}}</style></head>
        <body><h1>Fernsy Server</h1>\(body)<p class=dim>Version \(escape(s.version))</p></body></html>
        """
    }
}
