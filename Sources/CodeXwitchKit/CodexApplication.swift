import AppKit
import OSLog

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
        let attempt = UUID().uuidString
        let started = ProcessInfo.processInfo.systemUptime
        let applications = running
        rememberedURL = applications.first?.bundleURL ?? rememberedURL
        Diagnostics.lifecycle.notice("quit.begin attempt=\(attempt, privacy: .public) bundle=\(self.bundleIdentifier, privacy: .public) timeout_s=\(self.quitTimeout, privacy: .public) captured=\(self.describe(applications), privacy: .public)")
        for app in applications where !app.isTerminated {
            let accepted = app.terminate()
            Diagnostics.lifecycle.notice("quit.request attempt=\(attempt, privacy: .public) pid=\(app.processIdentifier, privacy: .public) accepted=\(accepted, privacy: .public)")
            guard accepted else {
                Diagnostics.lifecycle.error("quit.refused attempt=\(attempt, privacy: .public) pid=\(app.processIdentifier, privacy: .public)")
                throw AppError.quitRefused
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + quitTimeout
        var lastSnapshot = ""
        var nextSample = started
        // Preserve the exit decision. Fresh enumeration below is diagnostic only.
        while applications.contains(where: { !$0.isTerminated }) || isRunning {
            let now = ProcessInfo.processInfo.systemUptime
            let captured = describe(applications)
            let fresh = describe(running)
            let snapshot = "captured=[\(captured)] fresh=[\(fresh)]"
            let elapsed = Int((now - started) * 1000)
            if snapshot != lastSnapshot || now >= nextSample {
                Diagnostics.lifecycle.notice("quit.wait attempt=\(attempt, privacy: .public) elapsed_ms=\(elapsed, privacy: .public) \(snapshot, privacy: .public)")
                lastSnapshot = snapshot
                nextSample = now + 1
            }
            guard now < deadline else {
                Diagnostics.lifecycle.error("quit.timeout attempt=\(attempt, privacy: .public) elapsed_ms=\(elapsed, privacy: .public) \(snapshot, privacy: .public)")
                throw AppError.quitTimeout
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        Diagnostics.lifecycle.notice("quit.completed attempt=\(attempt, privacy: .public) elapsed_ms=\(elapsed, privacy: .public) captured=\(self.describe(applications), privacy: .public) fresh=\(self.describe(self.running), privacy: .public)")
    }
    private func describe(_ applications: [NSRunningApplication]) -> String {
        applications.map { "pid=\($0.processIdentifier),terminated=\($0.isTerminated)" }.joined(separator: ";")
    }
    func launch() async throws {
        Diagnostics.lifecycle.notice("launch.begin bundle=\(self.bundleIdentifier, privacy: .public)")
        guard let url = rememberedURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              Bundle(url: url)?.bundleIdentifier == bundleIdentifier else {
            Diagnostics.lifecycle.error("launch.not_found bundle=\(self.bundleIdentifier, privacy: .public)")
            throw AppError.notFound
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                if application != nil && error == nil { continuation.resume() }
                else {
                    let failure = error as NSError?
                    Diagnostics.lifecycle.error("launch.failed domain=\(failure?.domain ?? "unknown", privacy: .public) code=\(failure?.code ?? 0, privacy: .public)")
                    continuation.resume(throwing: AppError.launch)
                }
            }
        }
        Diagnostics.lifecycle.notice("launch.completed fresh=\(self.describe(self.running), privacy: .public)")
    }
    func show() async throws {
        guard let app = running.first else { try await launch(); return }
        let accepted = app.activate(options: [.activateAllWindows])
        Diagnostics.lifecycle.notice("activate.request pid=\(app.processIdentifier, privacy: .public) accepted=\(accepted, privacy: .public)")
        guard accepted else { throw AppError.activate }
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
