import AppKit
import XCTest
@testable import CodeXwitchKit

@MainActor
final class NativeQuitTests: XCTestCase {
    func testQuitCompletesWhenFreshListIsEmptyDespiteStaleCapturedObject() async throws {
        // Given the captured AppKit wrapper never updates its termination flag.
        let process = StaleRunningApplication()
        let app = CodexApplication(bundleIdentifier: "local.codexwitch.test.stale", quitTimeout: 0.02,
                                   applicationLookup: { _ in process.quitRequested ? [] : [process] },
                                   processExists: { _ in false })
        // When the accepted termination removes it from the current application list.
        try await app.quit()
        // Then the caller can continue, without waiting for the obsolete wrapper.
        XCTAssertFalse(app.isRunning)
        XCTAssertFalse(process.isTerminated)
    }

    func testQuitTimesOutWhileFreshListStillContainsApplication() async throws {
        let process = StaleRunningApplication()
        let app = CodexApplication(bundleIdentifier: "local.codexwitch.test.stillrunning", quitTimeout: 0.02,
                                   applicationLookup: { _ in [process] }, processExists: { _ in false })
        do {
            try await app.quit()
            XCTFail("Must stop the operation while the app remains in the current list")
        } catch AppError.quitTimeout {
            XCTAssertTrue(app.isRunning)
        }
    }

    func testQuitWaitsForCapturedPIDAfterAppListTemporarilyDisappears() async throws {
        let process = StaleRunningApplication()
        var pidAlive = true
        var completed = false
        let app = CodexApplication(bundleIdentifier: "local.codexwitch.test.exiting", quitTimeout: 1,
                                   applicationLookup: { _ in process.quitRequested ? [] : [process] },
                                   processExists: { _ in pidAlive })
        let operation = Task { try await app.quit(); completed = true }
        while !process.quitRequested { await Task.yield() }
        try await Task.sleep(nanoseconds: 30_000_000)
        // The app list omits an exiting app before its OS process has ended.
        XCTAssertFalse(completed, "Do not let the caller replace auth/reopen while the old PID is alive")
        pidAlive = false
        try await operation.value
        XCTAssertTrue(completed)
    }

    func testQuitTimesOutWhenListIsEmptyButCapturedPIDStillExists() async throws {
        let process = StaleRunningApplication()
        let app = CodexApplication(bundleIdentifier: "local.codexwitch.test.exiting", quitTimeout: 0.02,
                                   applicationLookup: { _ in process.quitRequested ? [] : [process] },
                                   processExists: { _ in true })
        do {
            try await app.quit()
            XCTFail("Must not report successful exit while the captured PID exists")
        } catch AppError.quitTimeout { }
    }

    func testQuitProbesOriginalPIDWhenAppKitWrapperChangesIdentifier() async throws {
        let process = StaleRunningApplication()
        process.changesPIDAfterQuit = true
        let app = CodexApplication(bundleIdentifier: "local.codexwitch.test.changedpid", quitTimeout: 0.02,
                                   applicationLookup: { _ in process.quitRequested ? [] : [process] },
                                   processExists: { pid in pid != 12345 })
        // The original process is gone, though AppKit now reports an invalid PID.
        try await app.quit()
        XCTAssertFalse(app.isRunning)
    }
}

private final class StaleRunningApplication: NSRunningApplication, @unchecked Sendable {
    private(set) var quitRequested = false
    var changesPIDAfterQuit = false
    override var processIdentifier: pid_t { changesPIDAfterQuit && quitRequested ? -1 : 12345 }
    override var isTerminated: Bool { false }
    override func terminate() -> Bool {
        quitRequested = true
        return true
    }
}
