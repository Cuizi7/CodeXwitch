import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let switcher: Switcher
    private let loginItem: any LoginItemManaging
    private let confirmDeletion: (Account) -> Bool
    private var updatingLoginItem = false
    private var loginItemError: (status: SMAppService.Status, message: String)?

    init(switcher: Switcher, loginItem: any LoginItemManaging, confirmDeletion: @escaping (Account) -> Bool) {
        self.switcher = switcher
        self.loginItem = loginItem
        self.confirmDeletion = confirmDeletion
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 500),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "CodeXwitch 设置"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 460, height: 430)
        window.center()
        super.init(window: window)
        window.delegate = self
        reload()
    }
    required init?(coder: NSCoder) { nil }

    func reload() {
        guard let window else { return }
        let content = NSView(frame: NSRect(origin: .zero, size: window.contentView?.frame.size ?? NSSize(width: 570, height: 500)))
        window.contentView = content
        let loginStatus = loginItem.status
        if loginItemError?.status != loginStatus { loginItemError = nil }
        let launchAtLogin = NSButton(checkboxWithTitle: "登录时启动 CodeXwitch", target: self,
                                     action: #selector(loginItemChanged(_:)))
        launchAtLogin.identifier = NSUserInterfaceItemIdentifier("launchAtLogin")
        launchAtLogin.state = loginStatus == .enabled || loginStatus == .requiresApproval ? .on : .off
        launchAtLogin.isEnabled = !updatingLoginItem && !switcher.state.isBusy
        let loginHelp = NSTextField(wrappingLabelWithString: loginItemDescription(loginStatus))
        loginHelp.identifier = NSUserInterfaceItemIdentifier("loginItemStatus")
        loginHelp.font = .systemFont(ofSize: 12)
        loginHelp.textColor = .secondaryLabelColor
        let loginSettings = NSButton(title: "系统设置…", target: self, action: #selector(openLoginItemSettings))
        loginSettings.identifier = NSUserInterfaceItemIdentifier("loginItemSettings")
        loginSettings.bezelStyle = .rounded
        loginSettings.isHidden = loginStatus != .requiresApproval
        loginSettings.isEnabled = loginStatus == .requiresApproval && !updatingLoginItem && !switcher.state.isBusy
        let divider = NSBox()
        divider.boxType = .separator
        let title = NSTextField(labelWithString: "已保存账号")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "登录后自动保存，可在此移除。")
        subtitle.textColor = .secondaryLabelColor
        let help = NSTextField(wrappingLabelWithString: "删除仅移除本机保存的账号，不会退出 Codex。\n删除当前账号后，不会立即自动保存回来。")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let version = NSTextField(labelWithString: "CodeXwitch \(versionNumber)")
        version.identifier = NSUserInterfaceItemIdentifier("appVersion")
        version.font = .systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .lineBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        let list = AccountListView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = list
        for (index, account) in switcher.state.accounts.enumerated() {
            if index > 0 {
                let separator = NSBox(); separator.boxType = .separator
                list.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            }
            let row = makeRow(account)
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        if switcher.state.accounts.isEmpty {
            let empty = NSTextField(labelWithString: "暂无已保存账号")
            empty.textColor = .secondaryLabelColor
            list.addArrangedSubview(empty)
            list.edgeInsets = NSEdgeInsets(top: 24, left: 16, bottom: 24, right: 16)
        }
        for view in [launchAtLogin, loginHelp, loginSettings, divider, title, subtitle, scroll, help, version] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            launchAtLogin.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            launchAtLogin.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            launchAtLogin.trailingAnchor.constraint(lessThanOrEqualTo: loginSettings.leadingAnchor, constant: -12),
            loginSettings.centerYAnchor.constraint(equalTo: launchAtLogin.centerYAnchor),
            loginSettings.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            loginHelp.topAnchor.constraint(equalTo: launchAtLogin.bottomAnchor, constant: 6),
            loginHelp.leadingAnchor.constraint(equalTo: launchAtLogin.leadingAnchor),
            loginHelp.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            divider.topAnchor.constraint(equalTo: loginHelp.bottomAnchor, constant: 18),
            divider.leadingAnchor.constraint(equalTo: launchAtLogin.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: loginHelp.trailingAnchor),
            title.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            scroll.bottomAnchor.constraint(equalTo: help.topAnchor, constant: -20),
            help.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            help.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            help.bottomAnchor.constraint(equalTo: version.topAnchor, constant: -12),
            version.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            version.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
    }
    func windowDidBecomeKey(_ notification: Notification) { reload() }

    private func loginItemDescription(_ status: SMAppService.Status) -> String {
        if updatingLoginItem { return "正在更新登录项…" }
        if let loginItemError {
            if status == .requiresApproval {
                return loginItemError.message + "\n需要在系统设置的“登录项”中批准 CodeXwitch 启动。"
            }
            return loginItemError.message
        }
        switch status {
        case .enabled: return "登录 Mac 后自动在菜单栏运行。"
        case .notRegistered: return "默认关闭，开启后将在登录 Mac 时运行。"
        case .notFound: return "未找到登录项应用，请将 CodeXwitch 安装到“应用程序”后重试。"
        case .requiresApproval: return "需要在系统设置的“登录项”中批准 CodeXwitch 启动。"
        @unknown default: return "无法读取登录项状态，请稍后重试。"
        }
    }

    @objc private func loginItemChanged(_ sender: NSButton) {
        guard !updatingLoginItem, !switcher.state.isBusy else { return }
        let enabled = sender.state == .on
        updatingLoginItem = true
        loginItemError = nil
        reload()
        Task {
            do {
                try await loginItem.setEnabled(enabled)
            } catch {
                loginItemError = (loginItem.status, "未能更新登录项，请确认应用已安装到“应用程序”后重试。")
                let failure = error as NSError
                Diagnostics.application.error("login-item.update failed code=\(failure.code, privacy: .public)")
            }
            updatingLoginItem = false
            reload()
        }
    }

    @objc private func openLoginItemSettings() { loginItem.openSystemSettings() }

    private func makeRow(_ account: Account) -> NSView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: "账号")
        image.contentTintColor = .tertiaryLabelColor
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 34), image.heightAnchor.constraint(equalToConstant: 34)])
        let email = NSTextField(labelWithString: account.displayName)
        email.font = .systemFont(ofSize: 14, weight: .medium)
        email.lineBreakMode = .byTruncatingMiddle
        let status = NSTextField(labelWithString: account.id == switcher.state.current?.id ? "当前使用" : "备用账号")
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [email, status])
        labels.orientation = .vertical; labels.alignment = .leading; labels.spacing = 4
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let button = NSButton(title: "删除", target: self, action: #selector(deleteRequested(_:)))
        button.bezelStyle = .rounded
        button.contentTintColor = .systemRed
        button.identifier = NSUserInterfaceItemIdentifier(account.id)
        button.isEnabled = !switcher.state.isBusy
        let row = NSStackView(views: [image, labels, button])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 12
        row.distribution = .fill
        row.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        return row
    }
    @objc private func deleteRequested(_ sender: NSButton) {
        guard !switcher.state.isBusy, let id = sender.identifier?.rawValue,
              let account = switcher.state.accounts.first(where: { $0.id == id }) else { return }
        switcher.deleteAccount(id, confirmed: confirmDeletion(account))
        reload()
    }
}

@MainActor
private final class AccountListView: NSStackView {
    override var isFlipped: Bool { true }
}
