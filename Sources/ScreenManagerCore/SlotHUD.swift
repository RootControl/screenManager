import AppKit

/// An overlay listing the bound slots, shown while the focus modifier is held
/// down on its own — so you can see what ⌥3 will do before pressing 3.
final class SlotHUD {
    private var panel: NSPanel?
    private var showWorkItem: DispatchWorkItem?
    private var flagsMonitor: Any?
    private var keyMonitor: Any?

    /// Held this long before the overlay appears, so ordinary shortcut presses
    /// never flash it.
    private static let revealDelay: TimeInterval = 0.45

    private let rowsProvider: () -> [(slot: Int, label: String?)]
    private var modifiers: NSEvent.ModifierFlags = .option

    init(rowsProvider: @escaping () -> [(slot: Int, label: String?)]) {
        self.rowsProvider = rowsProvider
    }

    var isEnabled: Bool { flagsMonitor != nil }

    func enable(modifiers: NSEvent.ModifierFlags) {
        disable()
        self.modifiers = modifiers

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event.modifierFlags)
        }
        // Pressing an actual key means the user is using the shortcut, not
        // browsing — get out of the way immediately.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.cancel()
        }
    }

    func disable() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        flagsMonitor = nil
        keyMonitor = nil
        cancel()
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]
        let held = flags.intersection(relevant)

        guard held == modifiers.intersection(relevant), !held.isEmpty else {
            cancel()
            return
        }

        showWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.show() }
        showWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealDelay, execute: work)
    }

    private func cancel() {
        showWorkItem?.cancel()
        showWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func show() {
        let rows = rowsProvider()
        guard !rows.isEmpty else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)

        for row in rows {
            let text = NSTextField(labelWithString: "\(row.slot)   \(row.label ?? "—")")
            text.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            text.textColor = row.label == nil ? .tertiaryLabelColor : .labelColor
            text.lineBreakMode = .byTruncatingMiddle
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(text)
        }

        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 14

        stack.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: visual.topAnchor),
            stack.bottomAnchor.constraint(equalTo: visual.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
        ])

        let size = stack.fittingSize
        let width = min(max(size.width, 260), 520)
        let frame = NSRect(x: 0, y: 0, width: width, height: size.height)

        let hud = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.level = .floating
        hud.ignoresMouseEvents = true
        hud.hasShadow = true
        hud.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hud.contentView = visual

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            hud.setFrameOrigin(NSPoint(
                x: visible.midX - width / 2,
                y: visible.midY - size.height / 2
            ))
        }

        hud.orderFrontRegardless()
        panel = hud
    }

    deinit {
        disable()
    }
}
