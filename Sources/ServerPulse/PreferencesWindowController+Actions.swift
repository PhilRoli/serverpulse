import AppKit

extension PreferencesWindowController {
    private static let savedTokenPlaceholder = "••••••••"

    func loadGeneral() {
        intervalPopup.selectItem(at: AppConfig.intervals.firstIndex(of: config.pollInterval) ?? 1)
        diskPopup.selectItem(at: AppConfig.warnChoices.firstIndex(of: config.diskWarnPct) ?? 3)
        memPopup.selectItem(at: AppConfig.warnChoices.firstIndex(of: config.memWarnPct) ?? 4)
        notifyCheck.state = config.notificationsEnabled ? .on : .off
        loginCheck.state = loginItem.isEnabled ? .on : .off
    }

    func selectRow() {
        if let index = selectedIndex {
            table.selectRowIndexes([index], byExtendingSelection: false)
        }
        loadDetail()
    }

    func loadDetail() {
        let server = selectedServer
        detailControls.forEach { $0.isEnabled = server != nil }
        addRemove.setEnabled(server != nil, forSegment: 1)
        nameField.stringValue = server?.name ?? ""
        urlField.stringValue = server?.url.absoluteString ?? ""
        sshField.stringValue = server?.sshTarget ?? ""
        tokenField.stringValue = ""
        tokenField.placeholderString = nil
        testResult.stringValue = ""
        guard let id = server?.id else { return }
        let store = tokens
        Task { [weak self] in
            let hasToken = await Task.detached { (try? store.token(for: id)) != nil }.value
            guard let self, self.selectedID == id else { return }
            self.tokenField.placeholderString = hasToken ? Self.savedTokenPlaceholder : nil
        }
    }

    private func updateSelected(_ change: (inout ServerConfig) -> Void) {
        guard let index = selectedIndex else { return }
        var server = config.servers[index]
        change(&server)
        guard server != config.servers[index] else { return }
        config.servers[index] = server
        table.reloadData(forRowIndexes: [index], columnIndexes: [0, 1])
        commit()
    }

    @objc func nameEdited() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            nameField.stringValue = selectedServer?.name ?? ""
            return
        }
        updateSelected { $0.name = name }
    }

    @objc func urlEdited() {
        guard let url = PreferencesLogic.validatedURL(urlField.stringValue) else {
            if selectedServer != nil { NSSound.beep() }
            urlField.stringValue = selectedServer?.url.absoluteString ?? ""
            return
        }
        updateSelected { $0.url = url }
    }

    @objc func sshEdited() {
        switch PreferencesLogic.sshEdit(sshField.stringValue) {
        case .clear:
            sshField.stringValue = ""
            updateSelected { $0.sshTarget = nil }
        case .set(let target):
            sshField.stringValue = target
            updateSelected { $0.sshTarget = target }
        case .invalid:
            NSSound.beep()
            sshField.stringValue = selectedServer?.sshTarget ?? ""
        }
    }

    @objc func tokenEdited() {
        guard let id = selectedID, case .set(let token) = PreferencesLogic.tokenInput(tokenField.stringValue) else {
            return
        }
        tokenField.stringValue = ""
        let store = tokens
        Task { [weak self] in
            let saved = await Task.detached { (try? store.setToken(token, for: id)) != nil }.value
            guard let self else { return }
            if saved {
                if self.selectedID == id { self.tokenField.placeholderString = Self.savedTokenPlaceholder }
                self.commit(tokenChanged: [id])
            } else {
                NSSound.beep()
            }
        }
    }

    @objc func testClicked() {
        let typed = PreferencesLogic.tokenInput(tokenField.stringValue) // read before end-editing clears it
        window?.makeFirstResponder(nil)
        guard let server = selectedServer else { return }
        testResult.stringValue = "…"
        let store = tokens
        let client = client
        Task { [weak self] in
            let result: Result<AgentSnapshot, Error> = await Task.detached {
                let token: String?
                if case .set(let value) = typed { token = value } else { token = try? store.token(for: server.id) }
                guard let token else { return .failure(TokenStoreError.denied) }
                do { return .success(try await client.fetch(url: server.url, token: token)) } catch {
                    return .failure(error)
                }
            }.value
            guard let self, self.selectedID == server.id else { return }
            self.testResult.stringValue = PreferencesLogic.testResult(result)
        }
    }

    @objc func addRemoveClicked() {
        window?.makeFirstResponder(nil)
        if addRemove.selectedSegment == 0 { addServer() } else { removeServer() }
    }

    private func reloadTable() {
        let id = selectedID
        isReloading = true
        table.reloadData()
        isReloading = false
        selectedID = id
    }

    private func addServer() {
        let server = PreferencesLogic.newServer(existing: config.servers)
        config.servers.append(server)
        selectedID = server.id
        reloadTable()
        selectRow()
        commit()
        window?.makeFirstResponder(urlField)
    }

    private func removeServer() {
        guard let index = selectedIndex else { return }
        let id = config.servers.remove(at: index).id
        let store = tokens
        Task.detached { try? store.deleteToken(for: id) }
        selectedID = config.servers.indices.contains(index) ? config.servers[index].id : config.servers.last?.id
        reloadTable()
        selectRow()
        commit()
    }

    @objc func generalChanged() {
        config.pollInterval = AppConfig.intervals[max(0, intervalPopup.indexOfSelectedItem)]
        config.diskWarnPct = AppConfig.warnChoices[max(0, diskPopup.indexOfSelectedItem)]
        config.memWarnPct = AppConfig.warnChoices[max(0, memPopup.indexOfSelectedItem)]
        config.notificationsEnabled = notifyCheck.state == .on
        commit()
    }

    @objc func loginToggled() {
        if !loginItem.setEnabled(loginCheck.state == .on) { NSSound.beep() }
        loginCheck.state = loginItem.isEnabled ? .on : .off
    }
}
