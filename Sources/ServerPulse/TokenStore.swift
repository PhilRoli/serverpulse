import Foundation
import MenuBarKit

typealias TokenStoreError = SecurityCLIKeychainError

/// Blocking by design; callers run it off the main actor.
protocol TokenStoring: Sendable {
    func token(for id: UUID) throws -> String?
    func setToken(_ token: String, for id: UUID) throws
    func deleteToken(for id: UUID) throws
}

struct KeychainTokenStore: TokenStoring {
    var service = "ServerPulse"

    private func keychain(for id: UUID) -> SecurityCLIKeychain {
        SecurityCLIKeychain(service: service, account: id.uuidString)
    }

    func token(for id: UUID) throws -> String? { try keychain(for: id).read() }
    func setToken(_ token: String, for id: UUID) throws { try keychain(for: id).save(token) }
    func deleteToken(for id: UUID) throws { try keychain(for: id).delete() }
}
