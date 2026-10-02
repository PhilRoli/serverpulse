import XCTest
@testable import ServerPulse

final class StatusTitleTests: XCTestCase {
    private func issue(_ kind: Issue.Kind) -> Issue {
        Issue(serverID: UUID(), serverName: "A", kind: kind, subject: nil, value: nil)
    }

    func testAllGood() {
        XCTAssertEqual(StatusTitle.make(issues: [], anyStale: false), StatusTitle(text: "", tint: .normal))
    }

    func testHardIssuesCountAllIssuesInRed() {
        let title = StatusTitle.make(issues: [issue(.containerDown), issue(.agentUnreachable)], anyStale: false)
        XCTAssertEqual(title, StatusTitle(text: "2", tint: .red))
    }

    func testOnlyAgentIssuesShowBangInOrange() {
        let title = StatusTitle.make(issues: [issue(.authFailed), issue(.dockerUnavailable)], anyStale: false)
        XCTAssertEqual(title, StatusTitle(text: "!", tint: .orange))
    }

    func testStaleAppendsStar() {
        XCTAssertEqual(StatusTitle.make(issues: [issue(.agentUnreachable)], anyStale: true).text, "!*")
        XCTAssertEqual(StatusTitle.make(issues: [issue(.diskHigh)], anyStale: true).text, "1*")
    }
}
