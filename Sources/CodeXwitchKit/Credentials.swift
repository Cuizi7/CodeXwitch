import Foundation
import CryptoKit

struct Account: Equatable, Sendable {
    let id: String
    let email: String?
    var displayName: String { email ?? "账号（邮箱未知）" }
}

struct Credentials: Equatable, Sendable {
    let account: Account
    let data: Data

    static func parse(_ data: Data) throws -> Credentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["OPENAI_API_KEY"] as? String).flatMap(nonempty) == nil,
              root["auth_mode"] == nil || root["auth_mode"] as? String == "chatgpt",
              let tokens = root["tokens"] as? [String: Any],
              let idToken = (tokens["id_token"] as? String).flatMap(nonempty),
              (tokens["access_token"] as? String).flatMap(nonempty) != nil,
              (tokens["refresh_token"] as? String).flatMap(nonempty) != nil else {
            throw CredentialError.invalid
        }
        let parts = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw CredentialError.invalid }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let payload = Data(base64Encoded: encoded),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw CredentialError.invalid
        }
        let auth = claims["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        guard let user = (auth["chatgpt_user_id"] as? String).flatMap(nonempty)
                ?? (claims["sub"] as? String).flatMap(nonempty),
              let workspace = (tokens["account_id"] as? String).flatMap(nonempty)
                ?? (auth["chatgpt_account_id"] as? String).flatMap(nonempty),
              !user.contains("\0"), !workspace.contains("\0") else { throw CredentialError.invalid }
        let profile = claims["https://api.openai.com/profile"] as? [String: Any] ?? [:]
        let email = (claims["email"] as? String).flatMap(nonempty)
            ?? (profile["email"] as? String).flatMap(nonempty)
        let key = SHA256.hash(data: Data("\(user)\0\(workspace)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        // JWT metadata is used only for local labels and archive matching, not authentication.
        return Credentials(account: Account(id: key, email: email), data: data)
    }

    private static func nonempty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum CredentialError: LocalizedError {
    case invalid
    var errorDescription: String? { "无法识别完整的 ChatGPT 登录凭据，请在官方 Codex 中登录。" }
}
