import Foundation
@testable import CodeXwitchKit

func fixture(email: String = "a@example.com", user: String = "user-a",
             workspace: String = "workspace-a", access: String = "fake-access-a",
             tokenAccountID: String? = nil, profileEmail: String? = nil) -> Data {
    var auth: [String: Any] = ["chatgpt_account_id": workspace, "chatgpt_user_id": user]
    if workspace.isEmpty { auth.removeValue(forKey: "chatgpt_account_id") }
    var claims: [String: Any] = ["sub": user, "https://api.openai.com/auth": auth]
    if !email.isEmpty { claims["email"] = email }
    if let profileEmail { claims["https://api.openai.com/profile"] = ["email": profileEmail] }
    let payload = try! JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
        .base64EncodedString().replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    var tokens = ["id_token": "e30.\(payload).fake-signature", "access_token": access,
                  "refresh_token": "fake-refresh"]
    if let tokenAccountID { tokens["account_id"] = tokenAccountID }
    return try! JSONSerialization.data(withJSONObject: ["tokens": tokens, "last_refresh": "2026-10-09T00:00:00Z"], options: [.sortedKeys])
}

final class TestDirectory {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("codexwitch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    var auth: URL { url.appendingPathComponent("auth.json") }
    var config: URL { url.appendingPathComponent("config.toml") }
    var storage: URL { url.appendingPathComponent("private") }
    func store() -> AccountStore { AccountStore(authURL: auth, directory: storage, configURL: config) }
}
