import ServiceManagement

@MainActor
protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func setEnabled(_ enabled: Bool) async throws
    func openSystemSettings()
}

@MainActor
final class LoginItem: LoginItemManaging {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) async throws {
        if enabled {
            guard status != .enabled, status != .requiresApproval else { return }
            try SMAppService.mainApp.register()
        } else {
            guard status != .notRegistered else { return }
            try await SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
