import AppKit

@MainActor
final class CodexApplication: AppLifecycle {
    private let bundleIdentifier: String
    private let quitTimeout: TimeInterval
    private var rememberedURL: URL?
    private var running: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter { !$0.isTerminated }
    }
    var isRunning: Bool { !running.isEmpty }
    init(bundleIdentifier: String = "com.openai.codex", quitTimeout: TimeInterval = 10) {
        self.bundleIdentifier = bundleIdentifier
        self.quitTimeout = quitTimeout
    }
    func quit() async throws {
        let applications = running
        rememberedURL = applications.first?.bundleURL ?? rememberedURL
        for app in applications where !app.isTerminated {
            guard app.terminate() else { throw AppError.quitRefused }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + quitTimeout
        while applications.contains(where: { !$0.isTerminated }) || isRunning {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw AppError.quitTimeout }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    func launch() async throws {
        guard let url = rememberedURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              Bundle(url: url)?.bundleIdentifier == bundleIdentifier else { throw AppError.notFound }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                if application != nil && error == nil { continuation.resume() }
                else { continuation.resume(throwing: AppError.launch) }
            }
        }
    }
    func show() async throws {
        guard let app = running.first else { try await launch(); return }
        guard app.activate(options: [.activateAllWindows]) else { throw AppError.activate }
    }
}

enum AppError: LocalizedError {
    case notFound, quitRefused, quitTimeout, launch, activate
    var errorDescription: String? {
        switch self {
        case .notFound: "未找到官方 Codex App，请先安装并正常启动它。"
        case .quitRefused: "Codex 拒绝退出，请处理其窗口中的提示后重试。"
        case .quitTimeout: "等待 Codex 退出超时，认证尚未替换，请退出后重试。"
        case .launch: "无法启动官方 Codex App，请重试或从 Finder 启动。"
        case .activate: "无法显示 Codex 窗口，请从 Dock 打开。"
        }
    }
}
