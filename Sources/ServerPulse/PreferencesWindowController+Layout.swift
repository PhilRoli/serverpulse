import AppKit

extension PreferencesWindowController {
    func buildLayout() {
        guard let window, let content = window.contentView else { return }
        let stack = NSStackView(views: [
            sectionLabel("Servers"), serverList(), detailGrid(),
            separator(), sectionLabel("General"), generalGrid()
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        window.setContentSize(stack.fittingSize)
    }

    private func serverList() -> NSView {
        for (id, title, width) in [("name", "Name", 140.0), ("url", "URL", 260.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 420).isActive = true

        addRemove.segmentCount = 2
        addRemove.trackingMode = .momentary
        addRemove.setImage(NSImage(named: NSImage.addTemplateName), forSegment: 0)
        addRemove.setImage(NSImage(named: NSImage.removeTemplateName), forSegment: 1)
        addRemove.target = self
        addRemove.action = #selector(addRemoveClicked)

        let column = NSStackView(views: [scroll, addRemove])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        return column
    }

    private func detailGrid() -> NSView {
        configure(nameField, #selector(nameEdited))
        configure(urlField, #selector(urlEdited), placeholder: "https://metrics.example.com/metrics")
        configure(tokenField, #selector(tokenEdited))
        configure(sshField, #selector(sshEdited), placeholder: "user@host")
        lanOnlyCheck.target = self
        lanOnlyCheck.action = #selector(lanOnlyToggled)
        testButton.target = self
        testButton.action = #selector(testClicked)
        testButton.bezelStyle = .rounded
        testResult.textColor = .secondaryLabelColor
        let testRow = NSStackView(views: [testButton, testResult])
        let grid = NSGridView(views: [
            [label("Name"), nameField], [label("URL"), urlField],
            [label("Token"), tokenField], [label("SSH"), sshField],
            [NSGridCell.emptyContentView, lanOnlyCheck],
            [NSGridCell.emptyContentView, testRow]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        return grid
    }

    private func generalGrid() -> NSView {
        intervalPopup.addItems(withTitles: AppConfig.intervals.map { "\(Int($0)) s" })
        diskPopup.addItems(withTitles: AppConfig.warnChoices.map { "\($0)%" })
        memPopup.addItems(withTitles: AppConfig.warnChoices.map { "\($0)%" })
        for control in [intervalPopup, diskPopup, memPopup, notifyCheck] as [NSControl] {
            control.target = self
            control.action = #selector(generalChanged)
        }
        loginCheck.target = self
        loginCheck.action = #selector(loginToggled)
        let grid = NSGridView(views: [
            [label("Interval"), intervalPopup], [label("Disk warn"), diskPopup], [label("RAM warn"), memPopup],
            [NSGridCell.emptyContentView, notifyCheck], [NSGridCell.emptyContentView, loginCheck]
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        return grid
    }

    private func configure(_ field: NSTextField, _ action: Selector, placeholder: String? = nil) {
        field.target = self
        field.action = action
        field.cell?.sendsActionOnEndEditing = true
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 320).isActive = true
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        return label
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        return label
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 420).isActive = true
        return box
    }
}
