import AppKit

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let store: BindingStore
    private let windowManager: WindowManager
    private var pendingSlot: Int?

    init(store: BindingStore, windowManager: WindowManager) {
        self.store = store
        self.windowManager = windowManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "ScreenManager")
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        for slot in 1...9 {
            let label: String
            if let binding = store.binding(forSlot: slot) {
                label = "[\(slot)] \(binding.displayLabel)"
            } else {
                label = "[\(slot)] (empty)"
            }
            let item = NSMenuItem(title: label, action: #selector(slotClicked(_:)), keyEquivalent: "")
            item.tag = slot
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ScreenManager", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func slotClicked(_ sender: NSMenuItem) {
        let slot = sender.tag
        pendingSlot = slot
        showWindowPicker(forSlot: slot)
    }

    private func showWindowPicker(forSlot slot: Int) {
        let windows = windowManager.enumerateWindows()
        let picker = NSMenu()

        if store.binding(forSlot: slot) != nil {
            let clear = NSMenuItem(title: "Clear slot \(slot)", action: #selector(clearSlot(_:)), keyEquivalent: "")
            clear.tag = slot
            clear.target = self
            picker.addItem(clear)
            picker.addItem(.separator())
        }

        if windows.isEmpty {
            let msg: String
            if !WindowManager.isAccessibilityGranted() {
                msg = "⚠️ Accessibility permission required — grant in System Settings"
            } else {
                msg = "No accessible windows found"
            }
            let empty = NSMenuItem(title: msg, action: #selector(openAccessibilitySettings), keyEquivalent: "")
            empty.target = self
            picker.addItem(empty)
        } else {
            for (index, info) in windows.enumerated() {
                let title = "\(info.appName) — \(info.windowTitle)"
                let item = NSMenuItem(title: title, action: #selector(windowPicked(_:)), keyEquivalent: "")
                item.tag = index
                item.target = self
                item.representedObject = info
                picker.addItem(item)
            }
        }

        let location = NSEvent.mouseLocation
        picker.popUp(positioning: nil, at: location, in: nil)
    }

    @objc private func windowPicked(_ sender: NSMenuItem) {
        guard let slot = pendingSlot,
              let info = sender.representedObject as? WindowInfo
        else { return }
        store.update(slot: slot, with: info)
        pendingSlot = nil
        buildMenu()
    }

    @objc private func clearSlot(_ sender: NSMenuItem) {
        store.remove(slot: sender.tag)
        pendingSlot = nil
        buildMenu()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
