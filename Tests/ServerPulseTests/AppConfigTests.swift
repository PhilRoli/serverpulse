import XCTest
@testable import ServerPulse

final class AppConfigTests: XCTestCase {
    private var suite: TestDefaults!

    override func setUp() { suite = TestDefaults() }
    override func tearDown() { suite.tearDown() }

    func testDefaultsWhenEmpty() {
        let config = AppConfigStore(defaults: suite.defaults).load()
        XCTAssertEqual(config, AppConfig())
        XCTAssertEqual(config.pollInterval, 30)
        XCTAssertEqual(config.diskWarnPct, 85)
        XCTAssertEqual(config.memWarnPct, 90)
        XCTAssertTrue(config.notificationsEnabled)
        XCTAssertTrue(config.servers.isEmpty)
    }

    func testRoundTrip() {
        let store = AppConfigStore(defaults: suite.defaults)
        var config = AppConfig()
        config.servers = [.fixture(name: "Ambulance")]
        config.servers[0].sshTarget = "deploy@1.2.3.4"
        config.pollInterval = 60
        config.diskWarnPct = 80
        store.save(config)
        XCTAssertEqual(store.load(), config)
    }

    func testMissingKeysFallBackToDefaults() {
        suite.defaults.set(Data(#"{"pollInterval":120}"#.utf8), forKey: "config")
        let config = AppConfigStore(defaults: suite.defaults).load()
        XCTAssertEqual(config.pollInterval, 120)
        XCTAssertEqual(config.memWarnPct, 90)
        XCTAssertTrue(config.servers.isEmpty)
    }

    func testCorruptDataFallsBackToDefaults() {
        suite.defaults.set(Data("nope".utf8), forKey: "config")
        XCTAssertEqual(AppConfigStore(defaults: suite.defaults).load(), AppConfig())
    }

    func testThresholds() {
        var config = AppConfig()
        config.diskWarnPct = 70
        XCTAssertEqual(config.thresholds, Thresholds(diskWarnPct: 70, memWarnPct: 90))
    }
}
