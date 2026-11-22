import XCTest
@testable import ServerPulse

final class SSHLauncherTests: XCTestCase {
    func testSystemDefaultOpensSSHURL() {
        XCTAssertEqual(SSHLauncher.plan(target: "me@host", terminal: nil),
                       .url(URL(string: "ssh://me@host")!, app: nil))
    }

    func testTerminalAndITermUseURLWithApp() {
        XCTAssertEqual(SSHLauncher.plan(target: "host", terminal: .iterm),
                       .url(URL(string: "ssh://host")!, app: .iterm))
        XCTAssertEqual(SSHLauncher.plan(target: "host", terminal: .terminal),
                       .url(URL(string: "ssh://host")!, app: .terminal))
    }

    func testGhosttyRunsSSHCommand() {
        XCTAssertEqual(SSHLauncher.plan(target: "me@host", terminal: .ghostty),
                       .process(executable: "/usr/bin/open",
                                arguments: ["-n", "-b", "com.mitchellh.ghostty", "--args", "-e", "ssh", "me@host"]))
    }
}
