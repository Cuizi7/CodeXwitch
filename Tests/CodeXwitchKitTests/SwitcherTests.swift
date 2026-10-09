import XCTest
@testable import CodeXwitchKit

@MainActor
final class SwitcherTests: XCTestCase {
    private func setup() throws -> (TestDirectory, AccountStore, RecordingRepository, FakeApp, Switcher, Credentials, Credentials, EventTrace) {
        let d = try TestDirectory(), store = d.store(), trace = EventTrace()
        let a = try Credentials.parse(fixture()), b = try Credentials.parse(fixture(email: "b@example.com", user: "user-b"))
        try store.capture(a); try store.capture(b); try store.install(a)
        let repo = RecordingRepository(store: store, trace: trace), app = FakeApp(trace: trace)
        let switcher = Switcher(repository: repo, app: app)
        switcher.refresh(); trace.events = []
        return (d, store, repo, app, switcher, a, b, trace)
    }
    func testAddClearFailureStopsLaunchAndPreservesCurrent() async throws {
        let (d, store, repo, _, s, a, _, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        repo.failClear = true; await s.addAccount()
        XCTAssertFalse(trace.events.contains("forget-suppression")); XCTAssertFalse(trace.events.contains("launch"))
        XCTAssertEqual(try store.current()?.data, a.data); XCTAssertFalse(s.state.isBusy)
        XCTAssertTrue(s.state.error?.contains("移除活动认证") == true)
    }
    func testAddForgetFailureStopsLaunchAndRetainsSavedAccounts() async throws {
        let (d, store, repo, _, s, _, _, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        repo.failForget = true; await s.addAccount()
        XCTAssertFalse(trace.events.contains("launch")); XCTAssertNil(try store.current())
        XCTAssertEqual(try store.accounts().count, 2); XCTAssertFalse(s.state.isBusy)
        XCTAssertTrue(s.state.error?.contains("准备重新登录") == true)
    }
    func testSwitchOrder() async throws {
        let (d, store, _, app, s, _, b, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        await s.switchTo(b.account.id)
        XCTAssertEqual(Array(trace.events.prefix(7)), ["read-current", "read-target", "quit", "read-current", "capture-current", "install-target", "launch"])
        XCTAssertEqual(try store.current()?.account, b.account)
        XCTAssertTrue(app.isRunning); XCTAssertFalse(s.state.isBusy); XCTAssertNil(s.state.error)
    }
    func testAddOrder() async throws {
        let (d, store, _, _, s, _, _, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        await s.addAccount()
        XCTAssertEqual(Array(trace.events.prefix(7)), ["read-current", "quit", "read-current", "capture-current", "clear-current", "forget-suppression", "launch"])
        XCTAssertNil(try store.current()); XCTAssertEqual(try store.accounts().count, 2)
    }
    func testCancelledDelete() async throws {
        let (d, store, _, _, s, _, b, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        s.deleteAccount(b.account.id, confirmed: false)
        XCTAssertTrue(trace.events.isEmpty); XCTAssertEqual(try store.accounts().count, 2)
    }
    func testBusyOperationIgnoresSecondClick() async throws {
        let (d, _, _, app, s, _, b, _) = try setup(); defer { withExtendedLifetime(d) {} }
        app.holdQuit = true
        let first = Task { await s.switchTo(b.account.id) }
        while app.quitContinuation == nil { await Task.yield() }
        XCTAssertTrue(s.state.isBusy)
        await s.switchTo(b.account.id)
        app.quitContinuation?.resume(); await first.value
        XCTAssertEqual(app.launchCount, 1)
    }
    func testRefreshDiscoversExternalAppAndLogin() async throws {
        let d = try TestDirectory(), store = d.store(), trace = EventTrace()
        let a = try Credentials.parse(fixture()); try store.install(a)
        let s = Switcher(repository: store, app: FakeApp(trace: trace)); s.refresh()
        XCTAssertTrue(s.state.isRunning); XCTAssertEqual(s.state.current, a.account)
        XCTAssertEqual(try store.accounts(), [a.account]); XCTAssertTrue(trace.events.isEmpty)
    }
    func testSameAccountNeverInstallsStaleSnapshot() async throws {
        let (d, store, _, app, s, a, _, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        let refreshed = try Credentials.parse(fixture(access: "fake-access-refreshed")); try store.install(refreshed)
        await s.switchTo(a.account.id)
        XCTAssertFalse(trace.events.contains("install-target")); XCTAssertFalse(trace.events.contains("quit"))
        XCTAssertTrue(trace.events.contains("show")); XCTAssertEqual(try store.credential(for: a.account.id).data, refreshed.data)
        app.isRunning = false; trace.events = []; await s.switchTo(a.account.id)
        XCTAssertTrue(trace.events.contains("launch")); XCTAssertFalse(trace.events.contains("install-target"))
    }
    func testExternalIdentityChangeBeforeClickNeverRestoresStaleSnapshot() async throws {
        let (d, store, _, _, s, _, b, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        let refreshed = try Credentials.parse(fixture(email: "b@example.com", user: "user-b", access: "fake-b-refreshed"))
        try store.install(refreshed)
        await s.switchTo(b.account.id)
        XCTAssertFalse(trace.events.contains("quit")); XCTAssertFalse(trace.events.contains("install-target"))
        XCTAssertEqual(try store.current()?.data, refreshed.data)
    }
    func testQuitFailureStopsMutation() async throws {
        let (d, store, _, app, s, a, b, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        app.failQuit = true; await s.switchTo(b.account.id)
        XCTAssertFalse(trace.events.contains("install-target")); XCTAssertFalse(trace.events.contains("launch"))
        XCTAssertEqual(try store.current()?.data, a.data); XCTAssertFalse(s.state.isBusy)
        XCTAssertFalse(s.state.isWaitingForQuit)
        XCTAssertTrue(s.state.error?.contains("退出 Codex") == true)
    }
    func testCaptureFailureStopsMutation() async throws {
        let (d, store, repo, _, s, a, b, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        repo.failCapture = true; await s.switchTo(b.account.id)
        XCTAssertFalse(trace.events.contains("install-target")); XCTAssertFalse(trace.events.contains("launch"))
        XCTAssertEqual(try store.current()?.data, a.data); XCTAssertFalse(s.state.isBusy)
        XCTAssertTrue(s.state.error?.contains("保存当前账号") == true)
    }
    func testInstallFailureStopsLaunch() async throws {
        let (d, store, repo, app, s, a, b, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        repo.failInstall = true; await s.switchTo(b.account.id)
        XCTAssertFalse(trace.events.contains("launch")); XCTAssertFalse(app.isRunning)
        XCTAssertEqual(try store.current()?.data, a.data); XCTAssertFalse(s.state.isBusy)
        XCTAssertTrue(s.state.error?.contains("写入目标账号") == true)
    }
    func testLaunchFailureRetainsSavedAccountsAndAllowsRetry() async throws {
        let (d, store, _, app, s, _, b, _) = try setup(); defer { withExtendedLifetime(d) {} }
        app.failLaunch = true; await s.switchTo(b.account.id)
        XCTAssertEqual(try store.accounts().count, 2); XCTAssertFalse(s.state.isBusy); XCTAssertNotNil(s.state.error)
        XCTAssertEqual(try store.current()?.account, b.account)
        app.failLaunch = false; await s.switchTo(b.account.id)
        XCTAssertTrue(app.isRunning); XCTAssertNil(s.state.error)
    }
    func testMissingAuthAfterCancelledAddCanSwitchBack() async throws {
        let (d, store, _, app, s, a, _, _) = try setup(); defer { withExtendedLifetime(d) {} }
        await s.addAccount(); XCTAssertNil(try store.current())
        await s.switchTo(a.account.id)
        XCTAssertEqual(try store.current()?.account, a.account); XCTAssertTrue(app.isRunning)
    }
    func testDeletedCurrentIsNotRecapturedDuringSwitch() async throws {
        let (d, store, _, _, s, a, b, _) = try setup(); defer { withExtendedLifetime(d) {} }
        s.deleteAccount(a.account.id, confirmed: true)
        await s.switchTo(b.account.id)
        XCTAssertEqual(try store.accounts(), [b.account]); XCTAssertEqual(try store.current()?.account, b.account)
    }
    func testAddReenablesCaptureAfterRemoval() async throws {
        let (d, store, _, _, s, a, _, _) = try setup(); defer { withExtendedLifetime(d) {} }
        s.deleteAccount(a.account.id, confirmed: true); await s.addAccount()
        try store.install(a); s.refresh()
        XCTAssertTrue(try store.accounts().contains(a.account))
    }
    func testMalformedRefreshDoesNotRemoveSavedAccounts() async throws {
        let (d, store, _, _, s, _, _, trace) = try setup(); defer { withExtendedLifetime(d) {} }
        try Data("{".utf8).write(to: d.auth); s.refresh()
        XCTAssertNil(s.state.current); XCTAssertNotNil(s.state.error)
        XCTAssertEqual(try store.accounts().count, 2); XCTAssertFalse(trace.events.contains("quit"))
    }
}
