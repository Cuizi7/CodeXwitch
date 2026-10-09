import XCTest
@testable import CodeXwitchKit

final class CredentialsTests: XCTestCase {
    func testSameEmailDifferentWorkspaces() throws {
        XCTAssertNotEqual(try Credentials.parse(fixture(workspace: "workspace-a")).account.id,
                          try Credentials.parse(fixture(workspace: "workspace-b")).account.id)
    }
    func testSameWorkspaceDifferentUsers() throws {
        XCTAssertNotEqual(try Credentials.parse(fixture(user: "user-a")).account.id,
                          try Credentials.parse(fixture(user: "user-b")).account.id)
    }
    func testRefreshKeepsIdentity() throws {
        XCTAssertEqual(try Credentials.parse(fixture()).account.id,
                       try Credentials.parse(fixture(access: "fake-access-refreshed")).account.id)
    }
    func testAccountIDOverrideAndEmailFallback() throws {
        let override = try Credentials.parse(fixture(tokenAccountID: "workspace-b", profileEmail: "profile@example.com"))
        let b = try Credentials.parse(fixture(workspace: "workspace-b"))
        XCTAssertEqual(override.account.id, b.account.id)
        XCTAssertEqual(override.account.email, "a@example.com")
        XCTAssertEqual(try Credentials.parse(fixture(email: "", profileEmail: "profile@example.com")).account.email, "profile@example.com")
    }
    func testInvalidCredentialDoesNotLeakTokens() throws {
        let values = [Data("{\"OPENAI_API_KEY\":\"fake-access-a\"}".utf8),
                      fixture(access: ""), fixture(user: ""), fixture(workspace: ""),
                      Data("{\"tokens\":{\"id_token\":\"invalid\",\"access_token\":\"fake-access-a\",\"refresh_token\":\"fake-refresh\"}}".utf8)]
        for data in values {
            XCTAssertThrowsError(try Credentials.parse(data)) { error in
                XCTAssertFalse(error.localizedDescription.contains("fake-access-a"))
            }
        }
    }
}
