import AppKit
import XCTest
@testable import CodeXwitchKit

@MainActor
final class PresentationTests: XCTestCase {
    private func setup() throws -> (TestDirectory, AccountStore, FakeApp, Switcher, Credentials, Credentials) {
        _ = NSApplication.shared
        let d = try TestDirectory(), store = d.store()
        let a = try Credentials.parse(fixture()), b = try Credentials.parse(fixture(email: "b@example.com", user: "user-b"))
        try store.capture(a); try store.capture(b); try store.install(a)
        let app = FakeApp(trace: EventTrace()), s = Switcher(repository: store, app: app)
        s.refresh(); return (d, store, app, s, a, b)
    }
    func testMenuUsesExternalStatusAndAlternatives() async throws {
        let (d, _, _, s, a, b) = try setup(); defer { withExtendedLifetime(d) {} }
        let menu = MenuController(switcher: s, openSettings: {}, quitManager: {})
        let items = menu.menu.items
        XCTAssertEqual(items.first?.title, "Codex：运行中")
        XCTAssertTrue(items.contains { $0.title == "当前：a@example.com" })
        XCTAssertTrue(items.contains { $0.title == "b@example.com" && $0.representedObject as? String == b.account.id })
        XCTAssertFalse(items.contains { $0.representedObject as? String == a.account.id })
        let actions = items.filter { $0.action != nil }.map(\.title)
        XCTAssertEqual(actions, ["b@example.com", "添加账号…", "刷新状态", "设置…", "退出菜单栏程序"])
        XCTAssertTrue(try XCTUnwrap(items.first { $0.title == "设置…" }).isEnabled)
    }
    func testBusyMenuDisablesMutation() async throws {
        let (d, _, app, s, _, b) = try setup(); defer { withExtendedLifetime(d) {} }
        let menu = MenuController(switcher: s, openSettings: {}, quitManager: {})
        let settings = SettingsWindowController(switcher: s, confirmDeletion: { _ in true })
        app.holdQuit = true; let operation = Task { await s.switchTo(b.account.id) }
        while app.quitContinuation == nil { await Task.yield() }
        menu.rebuild(); settings.reload()
        XCTAssertEqual(menu.menu.items.first?.title, "Codex：等待退出…")
        XCTAssertTrue(menu.menu.items.contains { $0.title == "请在 Codex 中确认退出（最多等待 60 秒）" })
        XCTAssertFalse(try XCTUnwrap(menu.menu.items.first { $0.title == "添加账号…" }).isEnabled)
        XCTAssertFalse(try XCTUnwrap(menu.menu.items.first { $0.title == "b@example.com" }).isEnabled)
        XCTAssertTrue(buttons(try XCTUnwrap(settings.window?.contentView)).allSatisfy { !$0.isEnabled })
        app.quitContinuation?.resume(); await operation.value
        menu.rebuild()
        XCTAssertFalse(menu.menu.items.contains { $0.title == "请在 Codex 中确认退出（最多等待 60 秒）" })
    }
    func testAddAccountShowsConfirmationHintBeforeTouchingAuthentication() async throws {
        let (d, store, app, s, a, _) = try setup(); defer { withExtendedLifetime(d) {} }
        let menu = MenuController(switcher: s, openSettings: {}, quitManager: {})
        app.holdQuit = true
        let operation = Task { await s.addAccount() }
        while app.quitContinuation == nil { await Task.yield() }
        menu.rebuild()
        XCTAssertEqual(menu.menu.items.first?.title, "Codex：等待退出…")
        XCTAssertTrue(menu.menu.items.contains { $0.title == "请在 Codex 中确认退出（最多等待 60 秒）" })
        XCTAssertEqual(try store.current()?.data, a.data)
        app.quitContinuation?.resume(); await operation.value
        menu.rebuild()
        XCTAssertFalse(menu.menu.items.contains { $0.title == "请在 Codex 中确认退出（最多等待 60 秒）" })
    }
    func testMenuShowsStartingUntilRelaunchCompletes() async throws {
        let (d, _, app, s, _, b) = try setup(); defer { withExtendedLifetime(d) {} }
        let menu = MenuController(switcher: s, openSettings: {}, quitManager: {})
        app.holdLaunch = true
        let operation = Task { await s.switchTo(b.account.id) }
        while app.launchContinuation == nil { await Task.yield() }
        menu.rebuild()
        XCTAssertEqual(menu.menu.items.first?.title, "正在启动 Codex…")
        XCTAssertFalse(menu.menu.items.contains { $0.title == "请在 Codex 中确认退出（最多等待 60 秒）" })
        XCTAssertFalse(try XCTUnwrap(menu.menu.items.first { $0.title == "添加账号…" }).isEnabled)
        app.launchContinuation?.resume(); await operation.value
        menu.rebuild()
        XCTAssertEqual(menu.menu.items.first?.title, "Codex：运行中")
    }
    func testSettingsRowsRefreshOnReopen() async throws {
        let (d, _, _, s, _, b) = try setup(); defer { withExtendedLifetime(d) {} }
        let settings = SettingsWindowController(switcher: s, confirmDeletion: { _ in true })
        XCTAssertEqual(settings.window?.title, "CodeXwitch 设置")
        if let output = ProcessInfo.processInfo.environment["CODEXWITCH_RENDER_DIR"] {
            settings.window?.appearance = NSAppearance(named: .aqua)
            let view = try XCTUnwrap(settings.window?.contentView?.superview)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("settings-native.png"))
        }
        XCTAssertTrue(labels(try XCTUnwrap(settings.window?.contentView)).contains("b@example.com"))
        s.deleteAccount(b.account.id, confirmed: true); settings.reload()
        XCTAssertFalse(labels(try XCTUnwrap(settings.window?.contentView)).contains("b@example.com"))
        XCTAssertTrue(labels(try XCTUnwrap(settings.window?.contentView)).contains("a@example.com"))
    }
    func testDeleteConfirmationFalseHasNoSideEffect() async throws {
        let (d, store, _, s, a, b) = try setup(); defer { withExtendedLifetime(d) {} }
        var confirmed = false
        let settings = SettingsWindowController(switcher: s, confirmDeletion: { _ in confirmed })
        let button = try XCTUnwrap(buttons(try XCTUnwrap(settings.window?.contentView)).first { $0.identifier?.rawValue == b.account.id })
        button.performClick(nil)
        XCTAssertEqual(try store.accounts().count, 2)
        confirmed = true; button.performClick(nil)
        XCTAssertEqual(try store.accounts(), [a.account]); XCTAssertEqual(try store.current()?.account, a.account)
    }
    func testUnknownEmailAndReadErrorAreDisplayable() async throws {
        let (d, store, _, s, _, _) = try setup(); defer { withExtendedLifetime(d) {} }
        let menu = MenuController(switcher: s, openSettings: {}, quitManager: {})
        try store.install(Credentials.parse(fixture(email: ""))); s.refresh(); menu.rebuild()
        XCTAssertTrue(menu.menu.items.contains { $0.title == "当前：账号（邮箱未知）" })
        try Data("{".utf8).write(to: d.auth); s.refresh(); menu.rebuild()
        XCTAssertTrue(menu.menu.items.contains { $0.title == "当前：无法读取账号" })
        let emptyDir = try TestDirectory(), empty = Switcher(repository: emptyDir.store(), app: FakeApp(trace: EventTrace()))
        empty.refresh()
        let settings = SettingsWindowController(switcher: empty, confirmDeletion: { _ in false })
        XCTAssertTrue(labels(try XCTUnwrap(settings.window?.contentView)).contains("暂无已保存账号"))
    }
    func testQuitManagerDoesNotQuitCodex() async throws {
        let (d, _, app, s, _, _) = try setup(); defer { withExtendedLifetime(d) {} }
        var quit = false
        let controller = MenuController(switcher: s, openSettings: {}, quitManager: { quit = true })
        let index = try XCTUnwrap(controller.menu.items.firstIndex { $0.title == "退出菜单栏程序" })
        controller.menu.performActionForItem(at: index)
        XCTAssertTrue(quit); XCTAssertFalse(app.trace.events.contains("quit"))
    }
    func testQuitWithNoRunningAppCompletes() async throws {
        let app = CodexApplication(bundleIdentifier: "local.codexwitch.test.nonexistent", quitTimeout: 0.01)
        XCTAssertFalse(app.isRunning)
        try await app.quit()
        XCTAssertFalse(app.isRunning)
    }
    func testMissingOfficialAppReportsError() async throws {
        let app = CodexApplication(bundleIdentifier: "local.codexwitch.test.nonexistent")
        XCTAssertFalse(app.isRunning)
        do { try await app.launch(); XCTFail("Must report missing app") }
        catch { XCTAssertTrue(error.localizedDescription.contains("未找到")) }
    }
    func testSettingsRowsStartAtTopAndDeleteButtonsAlignRight() async throws {
        let (d, _, _, s, a, _) = try setup(); defer { withExtendedLifetime(d) {} }
        let settings = SettingsWindowController(switcher: s, confirmDeletion: { _ in false })
        let content = try XCTUnwrap(settings.window?.contentView)
        content.superview?.layoutSubtreeIfNeeded()
        let all = allViews(content)
        let scroll = try XCTUnwrap(all.compactMap { $0 as? NSScrollView }.first)
        let email = try XCTUnwrap(all.compactMap { $0 as? NSTextField }.first { $0.stringValue == "a@example.com" })
        let button = try XCTUnwrap(buttons(content).first { $0.identifier?.rawValue == a.account.id })
        let visible = content.convert(scroll.contentView.bounds, from: scroll.contentView)
        let emailRect = content.convert(email.bounds, from: email)
        let buttonRect = content.convert(button.bounds, from: button)
        XCTAssertLessThan(visible.maxY - emailRect.maxY, 40, "First account should begin at the top of the list")
        XCTAssertLessThan(visible.maxX - buttonRect.maxX, 24, "Delete should align with the right edge")
    }
    func testStoppedAppCanLaunchCurrentAccountFromMenu() async throws {
        let (d, store, app, s, a, _) = try setup(); defer { withExtendedLifetime(d) {} }
        app.isRunning = false; s.refresh()
        let controller = MenuController(switcher: s, openSettings: {}, quitManager: {})
        let index = try XCTUnwrap(controller.menu.items.firstIndex { $0.title == "启动 Codex" })
        XCTAssertTrue(controller.menu.items[index].isEnabled)
        XCTAssertEqual(controller.menu.items[index].representedObject as? String, a.account.id)
        controller.menu.performActionForItem(at: index)
        for _ in 0..<100 where !app.isRunning { await Task.yield() }
        XCTAssertTrue(app.isRunning)
        XCTAssertEqual(try store.current()?.data, a.data)
        XCTAssertFalse(app.trace.events.contains("quit"))
    }
    private func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
    private func labels(_ view: NSView) -> [String] {
        (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap(labels)
    }
    private func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
    }
}
