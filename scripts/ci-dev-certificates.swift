// ci-dev-certificates.swift: keeps CI from filling the team's certificate limit. Archiving on a
// fresh runner makes Xcode create a new Apple Development certificate through the API key (the
// runner never has the private key of an earlier one); after enough runs the account reaches its
// maximum and archiving fails ("Your account has reached the maximum number of certificates").
// Before the archive, `snapshot` stores the ids of the development certificates; at the end,
// `revoke-new` revokes those created since, so only the run's own certificate goes.
//
//   ASC_KEY=AuthKey.p8 ASC_KEY_ID=… ASC_ISSUER=… swift scripts/ci-dev-certificates.swift snapshot <file>
//   ASC_KEY=AuthKey.p8 ASC_KEY_ID=… ASC_ISSUER=… swift scripts/ci-dev-certificates.swift revoke-new <file>
import CryptoKit
import Foundation

let env = ProcessInfo.processInfo.environment
func need(_ name: String) -> String {
    guard let value = env[name], !value.isEmpty else { fail("\(name) is missing") }
    return value
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("ci-dev-certificates: \(message)\n".utf8))
    exit(1)
}
func say(_ message: String) { print("ci-dev-certificates: \(message)") }

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2, let mode = arguments.first, ["snapshot", "revoke-new"].contains(mode), let file = arguments.last else {
    fail("usage: ci-dev-certificates.swift snapshot|revoke-new <file>")
}
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

func api(_ method: String, _ path: String) -> [String: Any] {
    var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com" + path)!)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

/// The development certificates (Apple Development and Mac Development), page by page.
func developmentCertificates() -> [(id: String, name: String, type: String, expires: String)] {
    var result: [(String, String, String, String)] = []
    var next: String? = "/v1/certificates?limit=200"
    while let page = next {
        let response = api("GET", page)
        for item in response["data"] as? [[String: Any]] ?? [] {
            let attributes = item["attributes"] as? [String: Any] ?? [:]
            let type = attributes["certificateType"] as? String ?? ""
            guard ["DEVELOPMENT", "MAC_APP_DEVELOPMENT", "IOS_DEVELOPMENT"].contains(type), let id = item["id"] as? String else { continue }
            result.append((id, attributes["name"] as? String ?? "?", type, attributes["expirationDate"] as? String ?? "?"))
        }
        next = ((response["links"] as? [String: Any])?["next"] as? String).map { $0.replacingOccurrences(of: "https://api.appstoreconnect.apple.com", with: "") }
    }
    return result
}

let current = developmentCertificates()
switch mode {
case "snapshot":
    say("\(current.count) development certificates before the archive:")
    for certificate in current { say("  \(certificate.id) \(certificate.type) \(certificate.name) (expires \(certificate.expires))") }
    do { try current.map(\.id).joined(separator: "\n").write(toFile: file, atomically: true, encoding: .utf8) } catch { fail("cannot write \(file)") }
default:
    guard let saved = try? String(contentsOfFile: file, encoding: .utf8) else { fail("no snapshot in \(file)") }
    let before = Set(saved.split(separator: "\n").map(String.init))
    let created = current.filter { !before.contains($0.id) }
    if created.isEmpty { say("no development certificate created by this run") }
    for certificate in created {
        say("revoking \(certificate.id) \(certificate.type) \(certificate.name), created by this run")
        _ = api("DELETE", "/v1/certificates/\(certificate.id)")
    }
}
