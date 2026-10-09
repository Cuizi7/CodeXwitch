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

final class EventTrace { var events: [String] = [] }
final class RecordingRepository: AccountRepository {
    let store: AccountStore
    let trace: EventTrace
    var failCapture = false
    var failInstall = false
    init(store: AccountStore, trace: EventTrace) { self.store = store; self.trace = trace }
    func current() throws -> Credentials? { trace.events.append("read-current"); return try store.current() }
    func accounts() throws -> [Account] { try store.accounts() }
    func credential(for id: String) throws -> Credentials { trace.events.append("read-target"); return try store.credential(for: id) }
    func capture(_ c: Credentials) throws {
        trace.events.append("capture-current")
        if failCapture { throw StoreError.write }
        try store.capture(c)
    }
    func remove(_ id: String, currentID: String?) throws { trace.events.append("remove-saved"); try store.remove(id, currentID: currentID) }
    func forgetSuppression() throws { trace.events.append("forget-suppression"); try store.forgetSuppression() }
    func install(_ c: Credentials) throws {
        trace.events.append("install-target")
        if failInstall { throw StoreError.write }
        try store.install(c)
    }
    func clearCurrent() throws { trace.events.append("clear-current"); try store.clearCurrent() }
}

@MainActor
final class FakeApp: AppLifecycle {
    var isRunning = true
    let trace: EventTrace
    var failQuit = false
    var failLaunch = false
    var holdQuit = false
    var quitContinuation: CheckedContinuation<Void, Never>?
    var launchCount = 0
    init(trace: EventTrace) { self.trace = trace }
    func quit() async throws {
        trace.events.append("quit")
        if failQuit { throw StoreError.write }
        if holdQuit { await withCheckedContinuation { quitContinuation = $0 } }
        isRunning = false
    }
    func launch() async throws {
        trace.events.append("launch"); launchCount += 1
        if failLaunch { throw StoreError.write }
        isRunning = true
    }
    func show() async throws { trace.events.append("show") }
}
