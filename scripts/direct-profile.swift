// direct-profile.swift: finds or creates the Developer ID provisioning profile of the DMG build
// ("Fernsy Direct Developer ID", type MAC_APP_DIRECT, bundle id de.mobilistics.fernsy, all
// Developer ID Application certificates) through the App Store Connect API, installs it for
// Xcode and prints its name. A profile without the app id's iCloud container (made before the
// capability was added) is replaced. The iCloud entitlements need a profile (icloud-sync).
//
//   ASC_KEY=AuthKey.p8 ASC_KEY_ID=… ASC_ISSUER=… swift scripts/direct-profile.swift
import CryptoKit
import Foundation

let env = ProcessInfo.processInfo.environment
func need(_ name: String) -> String {
    guard let value = env[name], !value.isEmpty else { fail("\(name) is missing") }
    return value
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("direct-profile: \(message)\n".utf8))
    exit(1)
}

let bundleIdentifier = env["BUNDLE_ID"] ?? "de.mobilistics.fernsy"
let profileName = "Fernsy Direct Developer ID"
let container = "iCloud." + bundleIdentifier
guard let keyPEM = try? String(contentsOfFile: need("ASC_KEY"), encoding: .utf8) else { fail("ASC_KEY is not readable") }
let keyID = need("ASC_KEY_ID"), issuer = need("ASC_ISSUER")

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

let token: String = {
    guard let key = try? P256.Signing.PrivateKey(pemRepresentation: keyPEM) else { fail("ASC_KEY is not a P-256 key") }
    let now = Int(Date().timeIntervalSince1970)
    let header = base64URL(try! JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"]))
    let claims = base64URL(try! JSONSerialization.data(withJSONObject: ["iss": issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"]))
    let signature = try! key.signature(for: Data("\(header).\(claims)".utf8))
    return "\(header).\(claims).\(base64URL(signature.rawRepresentation))"
}()

func api(_ method: String, _ path: String, _ body: [String: Any]? = nil) -> [String: Any] {
    var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com" + path)!)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: body)
    }
    let done = DispatchSemaphore(value: 0)
    var result: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    URLSession.shared.dataTask(with: request) { result = ($0, $1, $2); done.signal() }.resume()
    done.wait()
    let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
        fail("\(method) \(path): HTTP \(status) \(result.0.flatMap { String(data: $0, encoding: .utf8) } ?? result.2?.localizedDescription ?? "")")
    }
    guard let data = result.0, !data.isEmpty else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
}

func items(_ response: [String: Any]) -> [[String: Any]] { response["data"] as? [[String: Any]] ?? [] }
func attributes(_ item: [String: Any]) -> [String: Any] { item["attributes"] as? [String: Any] ?? [:] }
func query(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value }

/// The profile's entitlements name the iCloud container.
func hasContainer(_ content: Data) -> Bool {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("direct-profile-\(UUID()).mobileprovision")
    try? content.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["cms", "-D", "-i", file.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: output, encoding: .utf8)?.contains(container) == true
}

/// All items of a list endpoint, page by page: the API's name and identifier filters do not
/// match reliably (a profile it did not find by name made the create step fail with 409).
func all(_ path: String) -> [[String: Any]] {
    var result: [[String: Any]] = []
    var next: String? = path
    while let page = next {
        let response = api("GET", page)
        result += items(response)
        next = ((response["links"] as? [String: Any])?["next"] as? String).map { $0.replacingOccurrences(of: "https://api.appstoreconnect.apple.com", with: "") }
    }
    return result
}

var profile = all("/v1/profiles?limit=200")
    .first { attributes($0)["name"] as? String == profileName && attributes($0)["profileState"] as? String == "ACTIVE" }
if let current = profile, let content = (attributes(current)["profileContent"] as? String).flatMap({ Data(base64Encoded: $0) }),
   !hasContainer(content), let id = current["id"] as? String {
    FileHandle.standardError.write(Data("direct-profile: \(profileName) lacks \(container), replacing it\n".utf8))
    _ = api("DELETE", "/v1/profiles/\(id)")
    profile = nil
}
if profile == nil {
    let bundles = all("/v1/bundleIds?limit=200&fields[bundleIds]=identifier,platform,name")
    guard let bundle = bundles.first(where: { attributes($0)["identifier"] as? String == bundleIdentifier }), let bundleID = bundle["id"] as? String else {
        let similar = bundles.compactMap { attributes($0)["identifier"] as? String }.filter { $0.contains("fernsy") }
        fail("no app id \(bundleIdentifier) among \(bundles.count) app ids (similar: \(similar))")
    }
    let certificates = items(api("GET", "/v1/certificates?filter[certificateType]=DEVELOPER_ID_APPLICATION,DEVELOPER_ID_APPLICATION_G2&limit=50"))
        .compactMap { $0["id"] as? String }
    guard !certificates.isEmpty else { fail("no Developer ID Application certificate") }
    let created = api("POST", "/v1/profiles", ["data": [
        "type": "profiles",
        "attributes": ["name": profileName, "profileType": "MAC_APP_DIRECT"],
        "relationships": [
            "bundleId": ["data": ["type": "bundleIds", "id": bundleID]],
            "certificates": ["data": certificates.map { ["type": "certificates", "id": $0] }],
        ],
    ]])
    profile = created["data"] as? [String: Any]
}
guard let profile, let content = (attributes(profile)["profileContent"] as? String).flatMap({ Data(base64Encoded: $0) }),
      let uuid = attributes(profile)["uuid"] as? String else { fail("no profile content") }
guard hasContainer(content) else { fail("\(profileName) has no \(container): is iCloud enabled for \(bundleIdentifier)?") }
let home = FileManager.default.homeDirectoryForCurrentUser
for dir in ["Library/MobileDevice/Provisioning Profiles", "Library/Developer/Xcode/UserData/Provisioning Profiles"] {
    let folder = home.appendingPathComponent(dir)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try? content.write(to: folder.appendingPathComponent("\(uuid).provisionprofile"))
}
print(profileName)
