import AppKit

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    /// New config plus the IDs of servers whose token was just saved.
    var onChange: ((AppConfig, Set<UUID>) -> Void)?

    var config: AppConfig
    let tokens: TokenStoring
    let client: MetricsFetching
    let loginItem: LoginItemController
    var selectedID: UUID?
    /// Set while reloading the table so the resulting selection callback doesn't overwrite `selectedID`.
    var isReloading = false

    let table = NSTableView()
    let addRemove = NSSegmentedControl()
    let nameField = NSTextField()
    let urlField = NSTextField()
    let tokenField = NSSecureTextField()
    let sshField = NSTextField()
    let lanOnlyCheck = NSButton(checkboxWithTitle: "Only reachable on its own network", target: nil, action: nil)
    let testButton = NSButton(title: "Test", target: nil, action: nil)
    let testResult = NSTextField(labelWithString: "")
    let intervalPopup = NSPopUpButton()
    let diskPopup = NSPopUpButton()
    let memPopup = NSPopUpButton()
    let notifyCheck = NSButton(checkboxWithTitle: "Notifications", target: nil, action: nil)
    let loginCheck = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)

    var detailControls: [NSControl] { [nameField, urlField, tokenField, sshField, lanOnlyCheck, testButton] }
    var selectedIndex: Int? { config.servers.firstIndex { $0.id == selectedID } }
    var selectedServer: ServerConfig? { selectedIndex.map { config.servers[$0] } }

    init(config: AppConfig, tokens: TokenStoring, client: MetricsFetching, loginItem: LoginItemController) {
        self.config = config
        self.tokens = tokens
        self.client = client
        self.loginItem = loginItem
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ServerPulse"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildLayout()
        loadGeneral()
        selectedID = config.servers.first?.id
        table.reloadData()
        selectRow()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        loginCheck.state = loginItem.isEnabled ? .on : .off
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ends editing so the field being edited commits before the window goes away.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }

    func commit(tokenChanged: Set<UUID> = []) {
        onChange?(config, tokenChanged)
    }
}

extension PreferencesWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        config.servers.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let server = config.servers[row]
        let text = tableColumn?.identifier.rawValue == "url" ? server.url.absoluteString : server.name
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading else { return }
        let row = table.selectedRow
        selectedID = config.servers.indices.contains(row) ? config.servers[row].id : nil
        loadDetail()
    }
}
