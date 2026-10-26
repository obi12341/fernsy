import Foundation
import Testing
@testable import FernsyCore

/// Credentials never reach a log entry (app-log spec).
struct AppLogTests {
    static let samples = [
        "GET http://example.com:8080/live/alice/s3cr3t-Pass/101.ts failed",
        "player_api.php?username=alice&password=s3cr3t-Pass&action=get_live_streams",
        "https://jf.example/Videos/1/stream?api_key=abcdef123&Static=true",
        "token=xyz789 rejected, password is s3cr3t-Pass",
    ]

    @Test(arguments: samples)
    func credentialsAreRemoved(_ sample: String) {
        let text = AppLog.shared.redact(sample, secrets: ["s3cr3t-Pass"])
        for secret in ["alice/", "s3cr3t-Pass", "abcdef123", "xyz789"] {
            #expect(!text.contains(secret), "\(secret) survived in \(text)")
        }
    }

    @Test func storedEntriesAreRedacted() {
        AppLog.shared.setSecret("test", "s3cr3t-Pass")
        defer { AppLog.shared.setSecret("test", nil) }
        AppLog.shared.add(.detail, .app, "login with s3cr3t-Pass")
        let stored = AppLog.shared.entries(after: nil).last?.message ?? ""
        #expect(stored == "login with •••")
    }

    @Test func lineRoundTripsThroughTheFileFormat() {
        let entry = LogEntry(id: 1, date: Date(timeIntervalSince1970: 1_800_000_000), level: .warning, category: .network, message: "slow")
        let parts = entry.line.split(separator: "\t")
        #expect(parts.count == 4)
        #expect(LogLevel(code: String(parts[1])) == .warning)
        #expect(LogCategory(rawValue: String(parts[2])) == .network)
    }
}
