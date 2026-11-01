#if DEBUG
import Foundation

/// Debug switches the Mac and the Apple TV read the same way (code-structure-cleanup 3.2).
/// Debug builds only; each app decides when it applies them.
public enum DebugEnv {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// IPTV_SERVER/IPTV_USER/IPTV_PASS: a login without the keychain. An empty IPTV_SERVER= starts
    /// without an account.
    public static var credentials: XtreamCredentials? {
        guard let server = env["IPTV_SERVER"], !server.isEmpty, let user = env["IPTV_USER"], let pass = env["IPTV_PASS"] else { return nil }
        return XtreamCredentials(server: server, username: user, password: pass)
    }

    /// IPTV_TESTRESUME=<key>:<position s>:<duration s>,…: resume positions for this run (keys such
    /// as movie.500, episode.<id>).
    public static var resumePositions: [(key: String, position: Double, duration: Double)] {
        (env["IPTV_TESTRESUME"] ?? "").split(separator: ",").compactMap { item in
            let p = item.split(separator: ":")
            guard p.count == 3, let position = Double(p[1]), let duration = Double(p[2]) else { return nil }
            return (String(p[0]), position, duration)
        }
    }

    /// IPTV_TESTWATCHED=<key>,…: items that count as watched for this run (in memory).
    public static var watchedKeys: [String] {
        (env["IPTV_TESTWATCHED"] ?? "").split(separator: ",").map(String.init)
    }

    /// One step of IPTV_TESTHIDE=channel:102,category:3,wait:20,show:channel:102: hide (or with
    /// "show:" show) a channel or category, or pause.
    public enum HideStep: Equatable {
        case channel(Int, hidden: Bool)
        case category(String, hidden: Bool)
        case wait(Double)
    }

    public static var hideSteps: [HideStep] { parseHideSteps(env["IPTV_TESTHIDE"] ?? "") }

    static func parseHideSteps(_ spec: String) -> [HideStep] {
        spec.split(separator: ",").compactMap { item in
            var parts = item.split(separator: ":").map(String.init)
            let hidden = parts.first != "show"
            if !hidden { parts.removeFirst() }
            guard parts.count == 2 else { return nil }
            switch parts[0] {
            case "wait": return .wait(Double(parts[1]) ?? 0)
            case "channel": return Int(parts[1]).map { .channel($0, hidden: hidden) }
            case "category": return .category(parts[1], hidden: hidden)
            default: return nil
            }
        }
    }

    /// A provider list repeated with new ids up to `target` items (IPTV_TESTBIGLIVE,
    /// IPTV_TESTBIGCATALOG): each round adds 1,000,000 × round to `id`; with `date`, copies get
    /// older by a minute per round and a numbered name.
    public static func enlarged(_ data: Data, to target: Int, id: String, date: String? = nil) -> Data {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !items.isEmpty else { return data }
        var out = items
        var copy = 1
        while out.count < target {
            for item in items where out.count < target {
                var item = item
                let base = (item[id] as? Int) ?? Int("\(item[id] ?? 0)") ?? 0
                item[id] = base + copy * 1_000_000
                if let date {
                    item["name"] = "\(item["name"] ?? "") \(copy)"
                    let stamp = (item[date] as? Int) ?? Int("\(item[date] ?? 0)") ?? 0
                    item[date] = "\(max(0, stamp - copy * 60))"
                }
                out.append(item)
            }
            copy += 1
        }
        return (try? JSONSerialization.data(withJSONObject: out)) ?? data
    }
}
#endif
