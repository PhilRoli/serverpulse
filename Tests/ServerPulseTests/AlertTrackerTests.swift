import XCTest
@testable import ServerPulse

final class AlertTrackerTests: XCTestCase {
    private let id = UUID()

    private func issue(_ kind: Issue.Kind, _ subject: String? = nil) -> Issue {
        Issue(serverID: id, serverName: "A", kind: kind, subject: subject, value: nil)
    }

    func testFirstUpdateIsSilentBaseline() {
        var tracker = AlertTracker()
        XCTAssertEqual(tracker.update(serverID: id, issues: [issue(.containerDown, "web")], containers: ["web"]), [])
        XCTAssertEqual(tracker.activeKeys(for: id), ["containerDown:web"])
    }

    func testRaiseAndResolve() {
        var tracker = AlertTracker()
        _ = tracker.update(serverID: id, issues: [], containers: ["web"])
        let down = issue(.containerDown, "web")
        XCTAssertEqual(tracker.update(serverID: id, issues: [down], containers: ["web"]),
                       [AlertEvent(change: .raised, issue: down)])
        XCTAssertEqual(tracker.update(serverID: id, issues: [down], containers: ["web"]), [])
        XCTAssertEqual(tracker.update(serverID: id, issues: [], containers: ["web"]),
                       [AlertEvent(change: .resolved, issue: down)])
    }

    func testRemovedContainerDoesNotResolve() {
        var tracker = AlertTracker()
        let down = issue(.containerDown, "web")
        _ = tracker.update(serverID: id, issues: [down], containers: ["web"])
        XCTAssertEqual(tracker.update(serverID: id, issues: [], containers: []), [])
        XCTAssertTrue(tracker.activeKeys(for: id).isEmpty)
    }

    func testNoSnapshotSuppressesSnapshotResolutionsButNotAgentOnes() {
        var tracker = AlertTracker()
        let disk = issue(.diskHigh)
        let unreachable = issue(.agentUnreachable)
        _ = tracker.update(serverID: id, issues: [disk], containers: [])
        XCTAssertEqual(tracker.update(serverID: id, issues: [unreachable], containers: nil),
                       [AlertEvent(change: .raised, issue: unreachable)])
        XCTAssertEqual(tracker.update(serverID: id, issues: [], containers: []),
                       [AlertEvent(change: .resolved, issue: unreachable)])
    }

    func testDockerAvailableAgainNeedsSnapshot() {
        var tracker = AlertTracker()
        let docker = issue(.dockerUnavailable)
        _ = tracker.update(serverID: id, issues: [docker], containers: [])
        XCTAssertEqual(tracker.update(serverID: id, issues: [], containers: nil), [])
        let again = issue(.dockerUnavailable)
        _ = tracker.update(serverID: id, issues: [again], containers: [])
        XCTAssertEqual(tracker.update(serverID: id, issues: [], containers: []),
                       [AlertEvent(change: .resolved, issue: again)])
    }

    func testValueChangesDoNotReRaise() {
        var tracker = AlertTracker()
        var disk = issue(.diskHigh)
        disk.value = 86
        _ = tracker.update(serverID: id, issues: [disk], containers: [])
        disk.value = 88
        XCTAssertEqual(tracker.update(serverID: id, issues: [disk], containers: []), [])
    }

    func testRemoveForgetsServer() {
        var tracker = AlertTracker()
        _ = tracker.update(serverID: id, issues: [issue(.agentUnreachable)], containers: nil)
        tracker.remove(serverID: id)
        XCTAssertTrue(tracker.activeKeys(for: id).isEmpty)
        XCTAssertEqual(tracker.update(serverID: id, issues: [], containers: nil), []) // new baseline
    }
}
