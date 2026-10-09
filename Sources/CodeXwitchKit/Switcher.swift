import Foundation
import OSLog

@MainActor
protocol AppLifecycle {
    var isRunning: Bool { get }
    func quit() async throws
    func launch() async throws
    func show() async throws
}

struct SwitcherState: Equatable {
    var isRunning = false
    var current: Account?
    var accounts: [Account] = []
    var isBusy = false
    var isWaitingForQuit = false
    var error: String?
}

@MainActor
final class Switcher {
    private let repository: any AccountRepository
    private let app: any AppLifecycle
    private var operationError: String?
    private var diagnosticID = ""
    private var diagnosticAction = ""
    private(set) var state = SwitcherState()
    var onChange: ((SwitcherState) -> Void)?

    init(repository: any AccountRepository, app: any AppLifecycle) {
        self.repository = repository
        self.app = app
    }

    func refresh() {
        guard !state.isBusy else { return }
        state.isRunning = app.isRunning
        var readError: String?
        do {
            let credential = try repository.current()
            state.current = credential?.account
            if let credential {
                do { try repository.capture(credential) }
                catch { readError = "自动保存失败：\(error.localizedDescription)" }
            }
        } catch {
            state.current = nil
            readError = "读取账号失败：\(error.localizedDescription)"
        }
        do { state.accounts = try repository.accounts() }
        catch { readError = readError ?? "读取保存记录失败：\(error.localizedDescription)" }
        state.error = operationError ?? readError
        onChange?(state)
    }

    func switchTo(_ id: String) async {
        guard beginOperation("switch") else { return }
        defer { finishOperation() }
        var step = "读取当前账号"
        do {
            let before = try repository.current()
            if let before, before.account.id == id {
                step = "保存当前账号"; try repository.capture(before)
                step = "启动 Codex"
                if app.isRunning { try await app.show() } else { try await app.launch() }
                return
            }
            step = "读取目标账号"; let target = try repository.credential(for: id)
            step = "退出 Codex"; try await quitCodex()
            step = "读取当前账号"; let current = try repository.current()
            if let current { step = "保存当前账号"; try repository.capture(current) }
            step = "写入目标账号"; try repository.install(target)
            step = "启动 Codex"; try await app.launch()
        } catch {
            Diagnostics.operations.error("operation.failed id=\(self.diagnosticID, privacy: .public) action=\(self.diagnosticAction, privacy: .public) stage=\(step, privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)")
            operationError = "\(step)失败：\(error.localizedDescription)"
        }
    }

    func addAccount() async {
        guard beginOperation("add") else { return }
        defer { finishOperation() }
        var step = "读取当前账号"
        do {
            // Reject unsupported authentication before stopping the GUI.
            _ = try repository.current()
            step = "退出 Codex"; try await quitCodex()
            step = "读取当前账号"; let current = try repository.current()
            if let current { step = "保存当前账号"; try repository.capture(current) }
            step = "移除活动认证"; try repository.clearCurrent()
            step = "准备重新登录"; try repository.forgetSuppression()
            step = "启动 Codex"; try await app.launch()
        } catch {
            Diagnostics.operations.error("operation.failed id=\(self.diagnosticID, privacy: .public) action=\(self.diagnosticAction, privacy: .public) stage=\(step, privacy: .public) error_type=\(String(reflecting: type(of: error)), privacy: .public)")
            operationError = "\(step)失败：\(error.localizedDescription)"
        }
    }

    func deleteAccount(_ id: String, confirmed: Bool) {
        guard confirmed, beginOperation("delete") else { return }
        defer { finishOperation() }
        do {
            let currentID = try repository.current()?.account.id
            try repository.remove(id, currentID: currentID)
        } catch {
            Diagnostics.operations.error("operation.failed id=\(self.diagnosticID, privacy: .public) action=delete stage=remove_saved error_type=\(String(reflecting: type(of: error)), privacy: .public)")
            operationError = "删除保存记录失败：\(error.localizedDescription)"
        }
    }

    private func quitCodex() async throws {
        state.isWaitingForQuit = true
        onChange?(state)
        defer {
            state.isWaitingForQuit = false
            onChange?(state)
        }
        try await app.quit()
    }

    private func beginOperation(_ action: String) -> Bool {
        guard !state.isBusy else { return false }
        diagnosticID = UUID().uuidString
        diagnosticAction = action
        Diagnostics.operations.notice("operation.begin id=\(self.diagnosticID, privacy: .public) action=\(action, privacy: .public)")
        operationError = nil
        state.error = nil
        state.isBusy = true
        onChange?(state)
        return true
    }
    private func finishOperation() {
        Diagnostics.operations.notice("operation.end id=\(self.diagnosticID, privacy: .public) action=\(self.diagnosticAction, privacy: .public) succeeded=\(self.operationError == nil, privacy: .public)")
        state.isBusy = false
        refresh()
    }
}
