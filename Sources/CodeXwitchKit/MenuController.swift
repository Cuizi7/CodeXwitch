import AppKit

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let switcher: Switcher
    private let openSettings: () -> Void
    private let quitManager: () -> Void

    init(switcher: Switcher, openSettings: @escaping () -> Void, quitManager: @escaping () -> Void) {
        self.switcher = switcher
        self.openSettings = openSettings
        self.quitManager = quitManager
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        rebuild()
    }
    func menuWillOpen(_ menu: NSMenu) { switcher.refresh(); rebuild() }
    func rebuild() {
        menu.removeAllItems()
        let state = switcher.state
        let status = add(state.isWaitingForQuit ? "Codex：等待退出…" :
                         state.isBusy ? (state.progressText ?? "Codex：正在处理…") : "Codex：\(state.isRunning ? "运行中" : "未运行")")
        status.image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            (state.isRunning ? NSColor.systemGreen : NSColor.secondaryLabelColor).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        let current: String
        if let account = state.current { current = account.displayName }
        else { current = state.error == nil ? "未登录" : "无法读取账号" }
        add("当前：\(current)")
        if state.isWaitingForQuit { add("请在 Codex 中确认退出（最多等待 60 秒）") }
        if !state.isRunning, let account = state.current {
            menu.addItem(.separator())
            let item = add("启动 Codex", action: #selector(switchAccount(_:)), enabled: !state.isBusy)
            item.representedObject = account.id
        }
        let alternatives = state.accounts.filter { $0.id != state.current?.id }
        if !alternatives.isEmpty {
            menu.addItem(.separator()); add("切换账号")
            for account in alternatives {
                let item = add(account.displayName, action: #selector(switchAccount(_:)), enabled: !state.isBusy)
                item.representedObject = account.id
            }
        }
        if let error = state.error { menu.addItem(.separator()); add(error) }
        menu.addItem(.separator())
        add("添加账号…", action: #selector(addAccount), enabled: !state.isBusy)
        add("刷新状态", action: #selector(refresh), enabled: !state.isBusy)
        add("设置…", action: #selector(settings), enabled: true)
        menu.addItem(.separator())
        add("退出菜单栏程序", action: #selector(quit), enabled: !state.isBusy)
    }
    @discardableResult
    private func add(_ title: String, action: Selector? = nil, enabled: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = action != nil && enabled
        menu.addItem(item)
        return item
    }
    @objc private func switchAccount(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Task { await switcher.switchTo(id) }
    }
    @objc private func addAccount() { Task { await switcher.addAccount() } }
    @objc private func refresh() { switcher.refresh() }
    @objc private func settings() { openSettings() }
    @objc private func quit() { quitManager() }
}
