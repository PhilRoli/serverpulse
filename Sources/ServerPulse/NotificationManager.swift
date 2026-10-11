import Foundation
import MenuBarKit
import UserNotifications

struct NotificationMessage: Equatable {
    var title: String
    var body: String
}

@MainActor
final class NotificationManager {
    private let scheduler: NotificationScheduler
    private var authRequested = false

    init(scheduler: NotificationScheduler) {
        self.scheduler = scheduler
    }

    func requestAuthorization() {
        requestAuthIfNeeded()
    }

    func post(_ events: [AlertEvent], thresholds: Thresholds) {
        let messages = events.compactMap { Self.message(for: $0, thresholds: thresholds) }
        guard !messages.isEmpty else { return }
        requestAuthIfNeeded()
        for message in messages {
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            scheduler.add(request, withCompletionHandler: nil)
        }
    }

    /// nil for issues that are only shown in the menu.
    static func message(for event: AlertEvent, thresholds: Thresholds) -> NotificationMessage? {
        let issue = event.issue
        let raised = event.change == .raised
        let subject = issue.subject ?? ""
        let body: String
        switch issue.kind {
        case .containerDown: body = raised ? "\(subject) is down" : "\(subject) is back up"
        case .containerUnhealthy: body = raised ? "\(subject) is unhealthy" : "\(subject) recovered"
        case .diskHigh: body = raised ? "Disk at \(issue.value ?? 0)%" : "Disk back below \(thresholds.diskWarnPct)%"
        case .memHigh: body = raised ? "RAM at \(issue.value ?? 0)%" : "RAM back below \(thresholds.memWarnPct)%"
        case .agentUnreachable: body = raised ? "Agent unreachable" : "Agent reachable again"
        case .dockerUnavailable: body = raised ? "Docker unavailable" : "Docker available again"
        case .authFailed, .agentOutdated: return nil
        }
        return NotificationMessage(title: issue.serverName, body: body)
    }

    private func requestAuthIfNeeded() {
        guard !authRequested else { return }
        authRequested = true
        Task { [scheduler] in _ = try? await scheduler.requestAuthorization(options: [.alert, .sound]) }
    }
}

typealias NotificationPresenter = BannerNotificationPresenter
