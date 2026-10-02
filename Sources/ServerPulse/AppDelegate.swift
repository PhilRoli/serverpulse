import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AppConfigStore()
    private let tokens = KeychainTokenStore()
    private let client = AgentClient()
    private lazy var poller = ServerPoller(client: client, tokens: tokens)
    private let statusBar = StatusBarController()
    private let presenter = NotificationPresenter()
    private lazy var notifications = NotificationManager(scheduler: UNUserNotificationCenter.current())
    private var tracker = AlertTracker()
    private var config = AppConfig()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        UNUserNotificationCenter.current().delegate = presenter
        config = store.load()

        statusBar.rows = { [unowned self] in
            MenuModel.rows(servers: self.config.servers, states: self.poller.states,
                           thresholds: self.config.thresholds)
        }
        statusBar.onRefresh = { [unowned self] in self.poller.refreshNow() }
        statusBar.onPreferences = { [unowned self] in self.showPreferences() }
        poller.onUpdate = { [unowned self] id, state in self.handle(id, state) }

        poller.apply(config)
        render()
    }

    private func handle(_ id: UUID, _ state: ServerState) {
        defer { render() }
        guard state != .loading, state != .unconfigured,
              let server = config.servers.first(where: { $0.id == id })
        else { return }
        let issues = HealthEvaluator.issues(server: server, state: state, thresholds: config.thresholds,
                                            active: tracker.activeKeys(for: id))
        let names = state.snapshot.map { Set(($0.containers ?? []).map(\.name)) }
        let events = tracker.update(serverID: id, issues: issues, containers: names)
        if config.notificationsEnabled {
            notifications.post(events, thresholds: config.thresholds)
        }
    }

    private func render() {
        var issues: [Issue] = []
        var anyStale = false
        for server in config.servers {
            let state = poller.states[server.id] ?? .loading
            anyStale = anyStale || state.isStale
            issues += HealthEvaluator.issues(server: server, state: state, thresholds: config.thresholds,
                                             active: tracker.activeKeys(for: server.id))
        }
        statusBar.setTitle(StatusTitle.make(issues: issues, anyStale: anyStale))
    }

    func showPreferences() {
        // Implemented in Task 12.
    }
}
