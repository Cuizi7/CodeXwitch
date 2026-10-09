import Foundation
import Darwin

protocol AccountRepository {
    func current() throws -> Credentials?
    func accounts() throws -> [Account]
    func credential(for id: String) throws -> Credentials
    func capture(_ credential: Credentials) throws
    func remove(_ id: String, currentID: String?) throws
    func forgetSuppression() throws
    func install(_ credential: Credentials) throws
    func clearCurrent() throws
}

final class AccountStore: AccountRepository {
    private let authURL: URL
    private let directory: URL
    private let configURL: URL
    private let fm = FileManager.default
    private var accountsURL: URL { directory.appendingPathComponent("accounts", isDirectory: true) }
    private var suppressionURL: URL { directory.appendingPathComponent("suppressed-account.json") }

    init(authURL: URL, directory: URL, configURL: URL) {
        self.authURL = authURL
        self.directory = directory
        self.configURL = configURL
    }

    func current() throws -> Credentials? {
        try validateFileStore()
        guard fm.fileExists(atPath: authURL.path) else { return nil }
        return try Credentials.parse(read(authURL))
    }

    func accounts() throws -> [Account] {
        guard fm.fileExists(atPath: accountsURL.path) else { return [] }
        let urls: [URL]
        do { urls = try fm.contentsOfDirectory(at: accountsURL, includingPropertiesForKeys: nil) }
        catch { throw StoreError.read }
        return urls.compactMap { url -> Account? in
            let id = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "json", validID(id),
                  let credential = try? credential(for: id) else { return nil }
            return credential.account
        }.sorted { ($0.email ?? "", $0.id) < ($1.email ?? "", $1.id) }
    }

    func credential(for id: String) throws -> Credentials {
        guard validID(id) else { throw StoreError.read }
        let result = try Credentials.parse(read(snapshotURL(id)))
        guard result.account.id == id else { throw StoreError.read }
        return result
    }

    func capture(_ credential: Credentials) throws {
        try ensurePrivateDirectories()
        let suppressed = try suppressedID()
        if suppressed == credential.account.id { return }
        try writeProtected(credential.data, to: snapshotURL(credential.account.id))
        if suppressed != nil { try forgetSuppression() }
    }

    func remove(_ id: String, currentID: String?) throws {
        guard validID(id) else { throw StoreError.write }
        if id == currentID {
            try ensurePrivateDirectories()
            try writeProtected(JSONEncoder().encode(id), to: suppressionURL)
        }
        try removeIfPresent(snapshotURL(id))
    }

    func forgetSuppression() throws { try removeIfPresent(suppressionURL) }

    func install(_ credential: Credentials) throws {
        try validateFileStore()
        // A saved target must still be a complete ChatGPT credential.
        guard try Credentials.parse(credential.data).account.id == credential.account.id else { throw CredentialError.invalid }
        if !fm.fileExists(atPath: authURL.deletingLastPathComponent().path) {
            do { try fm.createDirectory(at: authURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700]) }
            catch { throw StoreError.write }
        }
        try writeProtected(credential.data, to: authURL)
    }

    func clearCurrent() throws {
        try validateFileStore()
        try removeIfPresent(authURL)
    }

    private func snapshotURL(_ id: String) -> URL { accountsURL.appendingPathComponent("\(id).json") }
    private func validID(_ id: String) -> Bool {
        id.utf8.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func suppressedID() throws -> String? {
        guard fm.fileExists(atPath: suppressionURL.path) else { return nil }
        guard let id = try? JSONDecoder().decode(String.self, from: read(suppressionURL)), validID(id) else { throw StoreError.read }
        return id
    }
    private func ensurePrivateDirectories() throws {
        do {
            for url in [directory, accountsURL] {
                try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            }
        } catch { throw StoreError.write }
    }
    private func read(_ url: URL) throws -> Data {
        do { return try Data(contentsOf: url) } catch { throw StoreError.read }
    }
    private func removeIfPresent(_ url: URL) throws {
        do { try fm.removeItem(at: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError { return }
        catch { throw StoreError.write }
    }
    private func writeProtected(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".codexwitch-\(UUID().uuidString)")
        let descriptor = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw StoreError.write }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        defer { try? handle.close(); try? fm.removeItem(at: temp) }
        do {
            try handle.write(contentsOf: data)
            guard fchmod(descriptor, 0o600) == 0,
                  rename(temp.path, url.path) == 0 else { throw StoreError.write }
        } catch { throw StoreError.write }
    }

    private func validateFileStore() throws {
        guard fm.fileExists(atPath: configURL.path) else { return }
        guard let text = String(data: try read(configURL), encoding: .utf8) else { throw StoreError.backend }
        var inTable = false, multiline = false, seen = false
        for raw in text.components(separatedBy: .newlines) {
            let line = stripComment(raw).trimmingCharacters(in: .whitespaces)
            // Escaped quoted keys require a full TOML decoder; do not assume file mode.
            if !multiline, line.hasPrefix("\""), let equals = line.firstIndex(of: "="),
               line[..<equals].contains("\\") { throw StoreError.backend }
            let hasKey = line.contains("cli_auth_credentials_store")
            let tripleCount = line.components(separatedBy: "\"\"\"").count - 1
                + line.components(separatedBy: "'''").count - 1
            if multiline || tripleCount > 0 {
                if hasKey { throw StoreError.backend }
                if tripleCount % 2 == 1 { multiline.toggle() }
                continue
            }
            if line.hasPrefix("[") { inTable = true }
            guard hasKey else { continue }
            guard !inTable, !seen,
                  line.range(of: #"^(?:cli_auth_credentials_store|"cli_auth_credentials_store"|'cli_auth_credentials_store')\s*=\s*(?:"file"|'file')\s*$"#,
                             options: .regularExpression) != nil else { throw StoreError.backend }
            seen = true
        }
    }
    private func stripComment(_ line: String) -> String {
        var quote: Character?, escaped = false, result = ""
        for c in line {
            if escaped { escaped = false; result.append(c); continue }
            if c == "\\", quote == "\"" { escaped = true; result.append(c); continue }
            if let active = quote { if c == active { quote = nil } }
            else if c == "\"" || c == "'" { quote = c }
            else if c == "#" { break }
            result.append(c)
        }
        return result
    }
}

enum StoreError: LocalizedError {
    case read, write, backend
    var errorDescription: String? {
        switch self {
        case .read: "无法读取账号凭据或保存记录，请检查文件权限。"
        case .write: "无法保存或替换账号凭据，请检查文件权限。"
        case .backend: "CodeXwitch 仅支持默认目录的 file 文件认证；当前认证配置不受支持。"
        }
    }
}
