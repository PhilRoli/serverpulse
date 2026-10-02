import XCTest
@testable import ServerPulse

final class PreferencesLogicTests: XCTestCase {
    func testEmptyTokenInputKeepsToken() {
        XCTAssertEqual(PreferencesLogic.tokenInput(""), .keep)
        XCTAssertEqual(PreferencesLogic.tokenInput("  \n"), .keep)
    }

    func testTokenInputIsTrimmed() {
        XCTAssertEqual(PreferencesLogic.tokenInput(" abc\n"), .set("abc"))
    }

    func testValidatedURL() {
        XCTAssertEqual(PreferencesLogic.validatedURL(" https://metrics.example.com/metrics "),
                       URL(string: "https://metrics.example.com/metrics"))
        XCTAssertNotNil(PreferencesLogic.validatedURL("http://10.0.0.5:4099/metrics"))
        XCTAssertNil(PreferencesLogic.validatedURL("metrics.example.com/metrics"))
        XCTAssertNil(PreferencesLogic.validatedURL("ftp://example.com"))
        XCTAssertNil(PreferencesLogic.validatedURL("https://"))
        XCTAssertNil(PreferencesLogic.validatedURL(""))
    }

    func testSSHTarget() {
        XCTAssertEqual(PreferencesLogic.sshTarget(" deploy@46.225.72.0 "), "deploy@46.225.72.0")
        XCTAssertNil(PreferencesLogic.sshTarget("   "))
        XCTAssertNil(PreferencesLogic.sshTarget("deploy@host; rm -rf"))
    }

    func testSSHEdit() {
        XCTAssertEqual(PreferencesLogic.sshEdit("  "), .clear)
        XCTAssertEqual(PreferencesLogic.sshEdit(" a@b "), .set("a@b"))
        XCTAssertEqual(PreferencesLogic.sshEdit("a b;"), .invalid)
    }

    func testNewServerNaming() {
        XCTAssertEqual(PreferencesLogic.newServer(existing: []).name, "Server 1")
        XCTAssertEqual(PreferencesLogic.newServer(existing: [.fixture(), .fixture()]).name, "Server 3")
    }

    func testTestResult() {
        let snap = AgentSnapshot.fixture(containers: [.fixture("a"), .fixture("b")])
        XCTAssertEqual(PreferencesLogic.testResult(.success(snap)), "✓ host · 2 containers")
        XCTAssertEqual(PreferencesLogic.testResult(.failure(MonitorError.unauthorized)), "⚠︎ Token rejected")
        XCTAssertEqual(PreferencesLogic.testResult(.failure(TokenStoreError.denied)), "⚠︎ No token")
    }
}
