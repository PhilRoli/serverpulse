import XCTest
@testable import ServerPulse

/// Uses the real login Keychain with a unique service per test; every item is deleted in tearDown.
final class TokenStoreTests: XCTestCase {
    private var store: KeychainTokenStore!
    private var ids: [UUID] = []

    override func setUpWithError() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil, "no interactive Keychain on CI")
        store = KeychainTokenStore(service: "ServerPulseTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        for id in ids { try? store?.deleteToken(for: id) }
        ids = []
    }

    private func newID() -> UUID {
        let id = UUID()
        ids.append(id)
        return id
    }

    func testMissingTokenIsNil() throws {
        XCTAssertNil(try store.token(for: newID()))
    }

    func testRoundTripAndOverwrite() throws {
        let id = newID()
        try store.setToken("first", for: id)
        XCTAssertEqual(try store.token(for: id), "first")
        try store.setToken("second", for: id)
        XCTAssertEqual(try store.token(for: id), "second")
    }

    func testTrimsWhitespaceAndNewlines() throws {
        let id = newID()
        try store.setToken("  abc123\n", for: id)
        XCTAssertEqual(try store.token(for: id), "abc123")
    }

    func testQuotesAndBackslashesSurvive() throws {
        let id = newID()
        let token = #"a"b\c d"#
        try store.setToken(token, for: id)
        XCTAssertEqual(try store.token(for: id), token)
    }

    func testDelete() throws {
        let id = newID()
        try store.setToken("gone", for: id)
        try store.deleteToken(for: id)
        XCTAssertNil(try store.token(for: id))
    }

    func testRejectsEmptyAndMultiline() {
        let id = newID()
        XCTAssertThrowsError(try store.setToken("  \n", for: id))
        XCTAssertThrowsError(try store.setToken("a\nb", for: id))
    }
}
