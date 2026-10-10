import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var menuController: MenuController?
    private var settingsController: SettingsWindowController?
    private var switcher: Switcher?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastState: SwitcherState?
    private let menuIcons = MenuBarIcons()
    private var iconState: MenuIconState?
    private var iconTimer: Timer?
    private var iconRotation: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        Diagnostics.application.notice("application.start version=\(version, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codex = home.appendingPathComponent(".codex", isDirectory: true)
        let storage = home.appendingPathComponent("Library/Application Support/CodeXwitch", isDirectory: true)
        let repository = AccountStore(authURL: codex.appendingPathComponent("auth.json"), directory: storage,
                                      configURL: codex.appendingPathComponent("config.toml"))
        let switcher = Switcher(repository: repository, app: CodexApplication())
        self.switcher = switcher
        let controller = MenuController(switcher: switcher, openSettings: { [weak self] in self?.openSettings() },
                                        quitManager: { NSApplication.shared.terminate(nil) })
        menuController = controller
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = menuIcons.image(for: .stopped)
        item.button?.toolTip = "CodeXwitch — Codex 账号切换器"
        item.menu = controller.menu
        statusItem = item
        switcher.onChange = { [weak self] state in self?.update(state) }
        switcher.refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.switcher?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                // Carry only Sendable metadata into the actor, not Notification/userInfo.
                let app = event.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleID = app?.bundleIdentifier
                let pid = app?.processIdentifier ?? 0
                let terminated = app?.isTerminated ?? false
                let kind = event.name == NSWorkspace.didTerminateApplicationNotification ? "terminated" : "launched"
                MainActor.assumeIsolated {
                    if bundleID == "com.openai.codex" {
                        Diagnostics.application.notice("workspace.event type=\(kind, privacy: .public) pid=\(pid, privacy: .public) terminated=\(terminated, privacy: .public)")
                    }
                    self?.switcher?.refresh()
                }
            }
            observers.append(observer)
        }
    }
    private func update(_ state: SwitcherState) {
        guard state != lastState else { return }
        let previous = lastState
        lastState = state
        updateStatusIcon(state)
        menuController?.rebuild()
        if settingsController?.window?.isVisible == true { settingsController?.reload() }
        if previous?.isBusy == true, !state.isBusy, let error = state.error {
            let alert = NSAlert()
            alert.messageText = "操作未完成"
            alert.informativeText = error
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
    private func updateStatusIcon(_ state: SwitcherState) {
        let kind = MenuIconState(state)
        statusItem?.button?.toolTip = "CodeXwitch — \(state.progressText ?? kind.description)"
        statusItem?.button?.setAccessibilityLabel("CodeXwitch，\(kind.description)")
        guard kind != iconState else { return }
        iconState = kind
        iconTimer?.invalidate()
        iconTimer = nil
        iconRotation = 0
        statusItem?.button?.image = menuIcons.image(for: kind)
        if kind == .processing {
            let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                    self.iconRotation = (self.iconRotation + 30).truncatingRemainder(dividingBy: 360)
                    self.statusItem?.button?.image = self.menuIcons.image(for: .processing, rotation: self.iconRotation)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            iconTimer = timer
        }
    }
    private func openSettings() {
        guard let switcher else { return }
        switcher.refresh()
        if settingsController == nil {
            settingsController = SettingsWindowController(switcher: switcher) { account in
                let alert = NSAlert()
                alert.messageText = "删除已保存的账号？"
                alert.informativeText = "\(account.displayName)\n这不会退出当前 Codex。若要再次切换到此账号，需要重新登录。"
                alert.addButton(withTitle: "取消")
                let delete = alert.addButton(withTitle: "删除")
                delete.hasDestructiveAction = true
                return alert.runModal() == .alertSecondButtonReturn
            }
        }
        settingsController?.reload()
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switcher?.state.isBusy == true ? .terminateCancel : .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        Diagnostics.application.notice("application.stop pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        timer?.invalidate()
        iconTimer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

@MainActor
public func runCodeXwitch() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
