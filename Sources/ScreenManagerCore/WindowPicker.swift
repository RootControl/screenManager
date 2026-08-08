import AppKit

/// Filters a window list by a free-text query, matching app name or title.
enum WindowFilter {
    static func matches(appName: String, title: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        // Every whitespace-separated term must appear somewhere in the row.
        let haystack = "\(appName) \(title)".lowercased()
        return trimmed.lowercased()
            .split(separator: " ")
            .allSatisfy { haystack.contains($0) }
    }

    static func matches(_ info: WindowInfo, query: String) -> Bool {
        matches(appName: info.appName, title: info.windowTitle, query: query)
    }

    static func apply(_ windows: [WindowInfo], query: String) -> [WindowInfo] {
        windows.filter { matches($0, query: query) }
    }
}

/// A searchable floating list of open windows. Replaces the flat `NSMenu`,
/// which grew past a screen's height on a busy machine.
final class WindowPicker: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private var panel: NSPanel?
    private var searchField: NSTextField?
    private var tableView: NSTableView?
    private var allWindows: [WindowInfo] = []
    private var filtered: [WindowInfo] = []
    private var onPick: ((WindowInfo) -> Void)?

    func show(windows: [WindowInfo], slot: Int, onPick: @escaping (WindowInfo) -> Void) {
        close()

        allWindows = windows
        filtered = windows
        self.onPick = onPick

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Bind a window to slot \(slot)"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.center()

        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))

        let field = NSTextField(frame: .zero)
        field.placeholderString = "Search windows…"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)

        let table = NSTableView(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        column.title = "Window"
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 24
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(pickSelected)
        table.allowsEmptySelection = false

        let scroll = NSScrollView(frame: .zero)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(field)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])

        panel.contentView = content
        self.panel = panel
        searchField = field
        tableView = table

        if !filtered.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        // An accessory app has to activate before its panel can take key focus.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        searchField = nil
        tableView = nil
        onPick = nil
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView

        if cell == nil {
            let view = NSTableCellView()
            view.identifier = identifier

            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            text.lineBreakMode = .byTruncatingMiddle
            view.addSubview(text)
            view.textField = text

            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            cell = view
        }

        cell?.textField?.stringValue = filtered[row].displayLabel
        return cell
    }

    @objc private func pickSelected() {
        guard let row = tableView?.selectedRow, row >= 0, row < filtered.count else { return }
        let info = filtered[row]
        let handler = onPick
        close()
        handler?(info)
    }

    // MARK: - Search field

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        filtered = WindowFilter.apply(allWindows, query: field.stringValue)
        tableView?.reloadData()
        if !filtered.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    /// Keeps the caret in the search field while the arrows drive the list.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let table = tableView else { return false }

        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1, in: table)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1, in: table)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            pickSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int, in table: NSTableView) {
        guard !filtered.isEmpty else { return }
        let next = min(max(table.selectedRow + delta, 0), filtered.count - 1)
        table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }
}
