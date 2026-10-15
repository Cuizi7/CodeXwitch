import AppKit
import ServiceManagement
import XCTest
@testable import CodeXwitchKit

@MainActor
final class LoginItemTests: XCTestCase {
    private func setup(_ service: FakeLoginItem) throws -> (TestDirectory, SettingsWindowController) {
        _ = NSApplication.shared
        let directory = try TestDirectory()
        let switcher = Switcher(repository: directory.store(), app: FakeApp(trace: EventTrace()))
        return (directory, SettingsWindowController(switcher: switcher, loginItem: service, confirmDeletion: { _ in false }))
    }

    func testOpeningSettingsDoesNotRegisterAndRefreshReadsSystemState() async throws {
        let service = FakeLoginItem()
        let (directory, settings) = try setup(service); defer { withExtendedLifetime(directory) {} }
        XCTAssertEqual(try toggle(settings).state, .off)
        XCTAssertTrue(service.requests.isEmpty)
        service.status = .enabled
        settings.reload()
        XCTAssertEqual(try toggle(settings).state, .on)
        service.status = .notRegistered
        settings.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        XCTAssertEqual(try toggle(settings).state, .off)
        XCTAssertTrue(service.requests.isEmpty)
    }

    func testToggleRegistersThenUnregisters() async throws {
        let service = FakeLoginItem()
        let (directory, settings) = try setup(service); defer { withExtendedLifetime(directory) {} }
        try toggle(settings).performClick(nil)
        try await waitForCompletion(settings)
        XCTAssertEqual(service.requests, [true])
        XCTAssertEqual(try toggle(settings).state, .on)
        try toggle(settings).performClick(nil)
        try await waitForCompletion(settings)
        XCTAssertEqual(service.requests, [true, false])
        XCTAssertEqual(try toggle(settings).state, .off)
    }

    func testFailureRestoresActualStateAndShowsError() async throws {
        let service = FakeLoginItem()
        service.fail = true
        let (directory, settings) = try setup(service); defer { withExtendedLifetime(directory) {} }
        try toggle(settings).performClick(nil)
        try await waitForCompletion(settings)
        XCTAssertEqual(try toggle(settings).state, .off)
        XCTAssertTrue(try status(settings).stringValue.contains("未能更新"))
        service.status = .enabled
        settings.reload()
        try toggle(settings).performClick(nil)
        try await waitForCompletion(settings)
        XCTAssertEqual(try toggle(settings).state, .on, "Failed removal must not falsely show disabled")
    }

    func testApprovalAfterRegistrationOffersSystemSettingsEvenOnError() async throws {
        let service = FakeLoginItem()
        service.registrationStatus = .requiresApproval
        service.fail = true
        service.changeStatusBeforeFailure = true
        let (directory, settings) = try setup(service); defer { withExtendedLifetime(directory) {} }
        try toggle(settings).performClick(nil)
        try await waitForCompletion(settings)
        XCTAssertTrue(try status(settings).stringValue.contains("批准"))
        let button: NSButton = try view("loginItemSettings", in: settings)
        XCTAssertFalse(button.isHidden)
        XCTAssertTrue(button.isEnabled)
        button.performClick(nil)
        XCTAssertEqual(service.settingsOpenCount, 1)
        service.fail = false
        try toggle(settings).performClick(nil)
        try await waitForCompletion(settings)
        XCTAssertEqual(service.status, .notRegistered, "Pending registration can be removed")
    }

    func testRegistrationWaitsForSystemResultAndBlocksRepeatedActions() async throws {
        let service = FakeLoginItem()
        service.hold = true
        let (directory, settings) = try setup(service); defer { withExtendedLifetime(directory) {} }
        let first = try toggle(settings)
        first.performClick(nil)
        settings.reload()
        XCTAssertFalse(try toggle(settings).isEnabled)
        first.performClick(nil)
        for _ in 0..<100 where service.continuation == nil { await Task.yield() }
        XCTAssertEqual(service.requests, [true])
        let continuation = try XCTUnwrap(service.continuation)
        continuation.resume()
        try await waitForCompletion(settings)
        XCTAssertEqual(try toggle(settings).state, .on)
    }

    func testFailedPendingRemovalShowsErrorAndExternalApprovalClearsIt() async throws {
        let service = FakeLoginItem()
        service.status = .requiresApproval
        service.fail = true
        let (directory, settings) = try setup(service); defer { withExtendedLifetime(directory) {} }
        try toggle(settings).performClick(nil)
        try await waitForCompletion(settings)
        XCTAssertTrue(try status(settings).stringValue.contains("未能更新"))
        XCTAssertTrue(try status(settings).stringValue.contains("批准"))
        service.status = .enabled
        settings.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        XCTAssertEqual(try toggle(settings).state, .on)
        XCTAssertFalse(try status(settings).stringValue.contains("未能更新"))
    }

    func testMissingAppIsNotShownAsEnabled() async throws {
        let service = FakeLoginItem()
        service.status = .notFound
        let (directory, settings) = try setup(service); defer { withExtendedLifetime(directory) {} }
        XCTAssertEqual(try toggle(settings).state, .off)
        XCTAssertTrue(try status(settings).stringValue.contains("应用"))
    }

    private func toggle(_ settings: SettingsWindowController) throws -> NSButton {
        try view("launchAtLogin", in: settings)
    }
    private func status(_ settings: SettingsWindowController) throws -> NSTextField {
        try view("loginItemStatus", in: settings)
    }
    private func view<T: NSView>(_ id: String, in settings: SettingsWindowController) throws -> T {
        let content = try XCTUnwrap(settings.window?.contentView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        return try XCTUnwrap(descendants(content).first { $0.identifier?.rawValue == id } as? T)
    }
    private func waitForCompletion(_ settings: SettingsWindowController) async throws {
        for _ in 0..<200 {
            if try toggle(settings).isEnabled { return }
            await Task.yield()
        }
        XCTFail("Login-item operation did not complete")
    }
}

@MainActor
final class FakeLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var requests: [Bool] = []
    var fail = false
    var changeStatusBeforeFailure = false
    var hold = false
    var continuation: CheckedContinuation<Void, Never>?
    var settingsOpenCount = 0

    func setEnabled(_ enabled: Bool) async throws {
        requests.append(enabled)
        if hold { await withCheckedContinuation { continuation = $0 } }
        if !fail || changeStatusBeforeFailure { status = enabled ? registrationStatus : .notRegistered }
        if fail { throw NSError(domain: "FakeLoginItem", code: 1) }
    }
    func openSystemSettings() { settingsOpenCount += 1 }
}
