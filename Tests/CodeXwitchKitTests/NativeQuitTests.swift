import AppKit
import XCTest
@testable import CodeXwitchKit

@MainActor
final class NativeQuitTests: XCTestCase {
    func testQuitCompletesWhenFreshListIsEmptyDespiteStaleCapturedObject() async throws {
        // Given the captured AppKit wrapper never updates its termination flag.
        let process = StaleRunningApplication()
        let app = CodexApplication(bundleIdentifier: "local.codexwitch.test.stale", quitTimeout: 0.02,
                                   applicationLookup: { _ in process.quitRequested ? [] : [process] })
        // When the accepted termination removes it from the current application list.
        try await app.quit()
        // Then the caller can continue, without waiting for the obsolete wrapper.
        XCTAssertFalse(app.isRunning)
        XCTAssertFalse(process.isTerminated)
    }

    func testQuitTimesOutWhileFreshListStillContainsApplication() async throws {
        let process = StaleRunningApplication()
        let app = CodexApplication(bundleIdentifier: "local.codexwitch.test.stillrunning", quitTimeout: 0.02,
                                   applicationLookup: { _ in [process] })
        do {
            try await app.quit()
            XCTFail("Must stop the operation while the app remains in the current list")
        } catch AppError.quitTimeout {
            XCTAssertTrue(app.isRunning)
        }
    }
}

private final class StaleRunningApplication: NSRunningApplication, @unchecked Sendable {
    private(set) var quitRequested = false
    override var isTerminated: Bool { false }
    override func terminate() -> Bool {
        quitRequested = true
        return true
    }
}
