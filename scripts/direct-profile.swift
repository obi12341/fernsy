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

var profile = items(api("GET", "/v1/profiles?filter[name]=\(query(profileName))&filter[profileType]=MAC_APP_DIRECT&limit=20"))
    .first { attributes($0)["profileState"] as? String == "ACTIVE" }
if let current = profile, let content = (attributes(current)["profileContent"] as? String).flatMap({ Data(base64Encoded: $0) }),
   !hasContainer(content), let id = current["id"] as? String {
    FileHandle.standardError.write(Data("direct-profile: \(profileName) lacks \(container), replacing it\n".utf8))
    _ = api("DELETE", "/v1/profiles/\(id)")
    profile = nil
}
if profile == nil {
    guard let bundle = items(api("GET", "/v1/bundleIds?filter[identifier]=\(query(bundleIdentifier))&limit=50"))
        .first(where: { attributes($0)["identifier"] as? String == bundleIdentifier }), let bundleID = bundle["id"] as? String else {
        fail("no app id \(bundleIdentifier)")
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
