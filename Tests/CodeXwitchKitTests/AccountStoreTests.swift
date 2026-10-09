import XCTest
@testable import CodeXwitchKit

final class AccountStoreTests: XCTestCase {
    func testCaptureUpdatesOneSnapshot() throws {
        let d = try TestDirectory(), store = d.store()
        let a = try Credentials.parse(fixture()), refreshed = try Credentials.parse(fixture(access: "fake-access-refreshed"))
        try store.capture(a); try store.capture(refreshed)
        XCTAssertEqual(try store.accounts().count, 1)
        XCTAssertEqual(try store.credential(for: a.account.id).data, refreshed.data)
    }
    func testPartialCurrentPreservesSnapshot() throws {
        let d = try TestDirectory(), store = d.store(), a = try Credentials.parse(fixture())
        try store.capture(a); try Data("{".utf8).write(to: d.auth)
        XCTAssertThrowsError(try store.current())
        XCTAssertEqual(try store.credential(for: a.account.id).data, a.data)
    }
    func testDeleteCurrentSurvivesRefreshAndRestart() throws {
        let d = try TestDirectory(), store = d.store(), a = try Credentials.parse(fixture())
        try store.capture(a); try store.install(a)
        try store.remove(a.account.id, currentID: a.account.id)
        try store.clearCurrent()
        let restarted = d.store()
        XCTAssertNil(try restarted.current())
        try restarted.capture(Credentials.parse(fixture(access: "fake-access-refreshed")))
        XCTAssertTrue(try restarted.accounts().isEmpty)
    }
    func testIdentityChangeOrExplicitAddAllowsCapture() throws {
        let d = try TestDirectory(), store = d.store(), a = try Credentials.parse(fixture())
        let b = try Credentials.parse(fixture(email: "b@example.com", user: "user-b"))
        try store.capture(a); try store.remove(a.account.id, currentID: a.account.id)
        try store.capture(b); try store.capture(a)
        XCTAssertEqual(try store.accounts().count, 2)
        try store.remove(a.account.id, currentID: a.account.id)
        try store.forgetSuppression(); try store.capture(a)
        XCTAssertEqual(try store.accounts().count, 2)
    }
    func testDeleteAlternativeKeepsCurrent() throws {
        let d = try TestDirectory(), store = d.store(), a = try Credentials.parse(fixture())
        let b = try Credentials.parse(fixture(email: "b@example.com", user: "user-b"))
        try store.capture(a); try store.capture(b); try store.install(a)
        try store.remove(b.account.id, currentID: a.account.id)
        XCTAssertEqual(try store.accounts(), [a.account])
        XCTAssertEqual(try Data(contentsOf: d.auth), a.data)
    }
    func testPrivatePermissionsAndRestrictedWrites() throws {
        let d = try TestDirectory(), store = d.store(), a = try Credentials.parse(fixture())
        let sentinels = [d.config, d.url.appendingPathComponent("session.jsonl"), d.url.appendingPathComponent("state.sqlite")]
        for file in sentinels { try Data("# sentinel".utf8).write(to: file) }
        try store.capture(a); try store.install(a)
        let files = [d.auth, d.storage.appendingPathComponent("accounts/\(a.account.id).json")]
        for file in files { XCTAssertEqual(try permissions(file), 0o600) }
        XCTAssertEqual(try permissions(d.storage), 0o700)
        XCTAssertEqual(try permissions(d.storage.appendingPathComponent("accounts")), 0o700)
        try store.remove(a.account.id, currentID: a.account.id)
        XCTAssertEqual(try permissions(d.storage.appendingPathComponent("suppressed-account.json")), 0o600)
        try store.clearCurrent()
        for file in sentinels { XCTAssertEqual(try Data(contentsOf: file), Data("# sentinel".utf8)) }
    }
    func testCredentialBackendPolicy() throws {
        let d = try TestDirectory(), store = d.store()
        try fixture().write(to: d.auth)
        let allowed = ["", "# cli_auth_credentials_store = \"keyring\"", "cli_auth_credentials_store = 'file' # okay", "\"cli_auth_credentials_store\" = \"file\""]
        for config in allowed {
            try Data(config.utf8).write(to: d.config)
            XCTAssertNotNil(try store.current())
        }
        for mode in ["keyring", "auto", "ephemeral", "unknown"] {
            try Data("cli_auth_credentials_store = \"\(mode)\"".utf8).write(to: d.config)
            XCTAssertThrowsError(try store.current())
            XCTAssertThrowsError(try store.clearCurrent())
            XCTAssertEqual(try Data(contentsOf: d.auth), fixture())
        }
    }
    func testCorruptSavedFileDoesNotHideValidAccounts() throws {
        let d = try TestDirectory(), store = d.store(), a = try Credentials.parse(fixture())
        try store.capture(a)
        try Data("{".utf8).write(to: d.storage.appendingPathComponent("accounts/\(String(repeating: "b", count: 64)).json"))
        XCTAssertEqual(try store.accounts(), [a.account])
        XCTAssertThrowsError(try store.credential(for: String(repeating: "b", count: 64)))
    }
    func testEscapedConfigKeyRejectsReadInstallAndRemoval() throws {
        let d = try TestDirectory(), store = d.store(), a = try Credentials.parse(fixture())
        let b = try Credentials.parse(fixture(email: "b@example.com", user: "user-b"))
        let configs = [#""cli_auth_credentials_stor\u0065" = "keyring""#,
                       #""cl\u0069_auth_credentials_store" = "auto""#]
        for config in configs {
            try a.data.write(to: d.auth)
            try Data(config.utf8).write(to: d.config)
            XCTAssertThrowsError(try store.current())
            XCTAssertThrowsError(try store.install(b))
            XCTAssertEqual(try? Data(contentsOf: d.auth), a.data)
            XCTAssertThrowsError(try store.clearCurrent())
            XCTAssertEqual(try? Data(contentsOf: d.auth), a.data)
        }
    }
    private func permissions(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber).intValue
    }
}
