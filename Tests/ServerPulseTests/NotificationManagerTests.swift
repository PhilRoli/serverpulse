import UserNotifications
import XCTest
@testable import ServerPulse

private final class FakeScheduler: NotificationScheduler, @unchecked Sendable {
    var requests: [UNNotificationRequest] = []
    var authRequests = 0

    func add(_ request: UNNotificationRequest,
             withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?) {
        requests.append(request)
        completionHandler?(nil)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authRequests += 1
        return true
    }
}

@MainActor
final class NotificationManagerTests: XCTestCase {
    private let thresholds = Thresholds(diskWarnPct: 85, memWarnPct: 90)

    private func event(_ change: AlertEvent.Change, _ kind: Issue.Kind, _ subject: String? = nil,
                       value: Int? = nil) -> AlertEvent {
        AlertEvent(change: change, issue: Issue(serverID: UUID(), serverName: "Ambulance", kind: kind,
                                                subject: subject, value: value))
    }

    private func body(_ event: AlertEvent) -> String? {
        NotificationManager.message(for: event, thresholds: thresholds)?.body
    }

    func testMessages() {
        XCTAssertEqual(NotificationManager.message(for: event(.raised, .containerDown, "web"), thresholds: thresholds),
                       NotificationMessage(title: "Ambulance", body: "web is down"))
        XCTAssertEqual(body(event(.resolved, .containerDown, "web")), "web is back up")
        XCTAssertEqual(body(event(.raised, .containerUnhealthy, "db")), "db is unhealthy")
        XCTAssertEqual(body(event(.resolved, .containerUnhealthy, "db")), "db recovered")
        XCTAssertEqual(body(event(.raised, .diskHigh, value: 87)), "Disk at 87%")
        XCTAssertEqual(body(event(.resolved, .diskHigh)), "Disk back below 85%")
        XCTAssertEqual(body(event(.raised, .memHigh, value: 93)), "RAM at 93%")
        XCTAssertEqual(body(event(.resolved, .memHigh)), "RAM back below 90%")
        XCTAssertEqual(body(event(.raised, .agentUnreachable)), "Agent unreachable")
        XCTAssertEqual(body(event(.resolved, .agentUnreachable)), "Agent reachable again")
        XCTAssertEqual(body(event(.raised, .dockerUnavailable)), "Docker unavailable")
        XCTAssertEqual(body(event(.resolved, .dockerUnavailable)), "Docker available again")
    }

    func testAuthAndOutdatedAreMenuOnly() {
        XCTAssertNil(body(event(.raised, .authFailed)))
        XCTAssertNil(body(event(.raised, .agentOutdated)))
    }

    func testPostSchedulesOnlyNotifiableEvents() async {
        let scheduler = FakeScheduler()
        let manager = NotificationManager(scheduler: scheduler)
        manager.post([event(.raised, .containerDown, "web"), event(.raised, .authFailed)], thresholds: thresholds)
        XCTAssertEqual(scheduler.requests.count, 1)
        XCTAssertEqual(scheduler.requests.first?.content.body, "web is down")
        XCTAssertEqual(scheduler.requests.first?.content.title, "Ambulance")
    }

    func testNothingToPostSkipsAuthorization() async {
        let scheduler = FakeScheduler()
        NotificationManager(scheduler: scheduler).post([event(.raised, .authFailed)], thresholds: thresholds)
        await Task.yield()
        XCTAssertEqual(scheduler.authRequests, 0)
        XCTAssertTrue(scheduler.requests.isEmpty)
    }
}
