import Foundation

enum TokenStoreError: Error, Equatable {
    case denied
    case writeFailed
}

/// Blocking by design; callers run it off the main actor.
protocol TokenStoring: Sendable {
    func token(for id: UUID) throws -> String?
    func setToken(_ token: String, for id: UUID) throws
    func deleteToken(for id: UUID) throws
}

/// Talks to /usr/bin/security rather than SecItem: this app's ad-hoc signature changes on every rebuild,
/// which would invalidate Keychain ACLs, while the Apple-signed `security` binary stays stable.
/// Writes go through `security -i` on stdin so a token never shows up in the process list.
struct KeychainTokenStore: TokenStoring {
    var service = "ServerPulse"

    func token(for id: UUID) throws -> String? {
        let result = Self.run(["find-generic-password", "-s", service, "-a", id.uuidString, "-w"])
        if result.status == 44 { return nil } // errSecItemNotFound
        guard result.status == 0 else { throw TokenStoreError.denied }
        let text = String(bytes: result.output, encoding: .utf8) ?? ""
        let value = text.trimmingCharacters(in: .newlines)
        return value.isEmpty ? nil : value
    }

    func setToken(_ token: String, for id: UUID) throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: \.isNewline) else { throw TokenStoreError.writeFailed }
        let command = "add-generic-password -U -s \(Self.quote(service)) -a \(Self.quote(id.uuidString))"
            + " -w \(Self.quote(token))\n"
        _ = Self.run(["-i"], input: command)
        // `security -i` exits 0 even when a command fails, so verify by reading back.
        guard (try? self.token(for: id)) == token else { throw TokenStoreError.writeFailed }
    }

    func deleteToken(for id: UUID) throws {
        let command = "delete-generic-password -s \(Self.quote(service)) -a \(Self.quote(id.uuidString))\n"
        _ = Self.run(["-i"], input: command)
    }

    static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func run(_ arguments: [String], input: String? = nil) -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        process.standardInput = stdin
        do { try process.run() } catch { return (-1, Data()) }
        if let input { try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
        try? stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}
