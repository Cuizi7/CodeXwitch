import OSLog

// Only lifecycle metadata belongs here: never credentials, email or account IDs.
enum Diagnostics {
    static let lifecycle = Logger(subsystem: "local.codexwitch.app", category: "AppLifecycle")
    static let operations = Logger(subsystem: "local.codexwitch.app", category: "AccountSwitch")
    static let application = Logger(subsystem: "local.codexwitch.app", category: "Application")
}
