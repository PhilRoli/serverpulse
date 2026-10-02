import Foundation

enum SSHEdit: Equatable {
    case clear
    case set(String)
    case invalid
}

enum TokenInput: Equatable {
    case keep
    case set(String)
}

/// Pure rules behind the Preferences window, kept out of AppKit so they can be tested.
enum PreferencesLogic {
    /// An empty field means "unchanged": tabbing through must never delete a saved token.
    static func tokenInput(_ raw: String) -> TokenInput {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .keep : .set(trimmed)
    }

    static func validatedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// `user@host` or `host`, letters/digits/`.-_@:` only, since it's turned into an ssh:// URL.
    static func sshTarget(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_@:"))
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return trimmed
    }

    /// Only an empty field clears the target; invalid text must not erase the saved value.
    static func sshEdit(_ raw: String) -> SSHEdit {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .clear }
        return sshTarget(raw).map(SSHEdit.set) ?? .invalid
    }

    static func newServer(existing: [ServerConfig]) -> ServerConfig {
        ServerConfig(id: UUID(), name: "Server \(existing.count + 1)",
                     url: URL(string: "https://example.com/metrics")!, sshTarget: nil)
    }

    /// Non-`MonitorError` failures only come from a missing or unreadable token.
    static func testResult(_ result: Result<AgentSnapshot, Error>) -> String {
        switch result {
        case .success(let snapshot):
            return "✓ \(snapshot.hostname ?? "OK") · \(snapshot.containers?.count ?? 0) containers"
        case .failure(let error as MonitorError):
            return "⚠︎ \(error.label)"
        case .failure:
            return "⚠︎ No token"
        }
    }
}
