import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeyManager = HotkeyManager()
    private let windowManager = WindowManager()
    private let bindingStore = BindingStore()
    private let preferencesStore = PreferencesStore()
    private let picker = WindowPicker()
    private var menuBarController: MenuBarController?

    /// Where ⌥N returns you to when pressed on the window you are already on.
    private var previousWindow: WindowInfo?
    /// Last app to activate that was not ScreenManager.
    private var lastExternalPID: pid_t?

    private var preferences: Preferences { preferencesStore.preferences }

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        WindowManager.promptForAccessibility()
        observeActivations()

        windowManager.externalPIDProvider = { [weak self] in self?.lastExternalPID }

        menuBarController = MenuBarController(
            store: bindingStore,
            preferencesStore: preferencesStore,
            windowManager: windowManager,
            actions: MenuBarActions(
                focusSlot: { [weak self] in self?.focus(slot: $0) },
                pickWindow: { [weak self] in self?.showPicker(for: $0) },
                bindFrontmost: { [weak self] in self?.bindFrontmost(to: $0) },
                saveFrame: { [weak self] in self?.saveFrame(for: $0) },
                clearFrame: { [weak self] in self?.bindingStore.saveFrame(nil, forSlot: $0) },
                clearSlot: { [weak self] in self?.bindingStore.remove(slot: $0) },
                applyLayout: { [weak self] position in
                    self?.windowManager.applyLayout(position)
                },
                moveToDisplay: { [weak self] index in
                    self?.windowManager.moveFocusedWindow(toDisplay: index)
                },
                preferencesChanged: { [weak self] in self?.registerHotkeys() },
                quit: { NSApplication.shared.terminate(nil) }
            )
        )

        hotkeyManager.onPressed = { [weak self] id in
            guard let self, let action = HotkeyAction.from(id: id) else { return }
            self.handle(action)
        }
        registerHotkeys()
    }

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregisterAll()
    }

    // MARK: - Hotkeys

    private func registerHotkeys() {
        hotkeyManager.register(HotkeyPlan.specs(for: preferences))
        menuBarController?.setHotkeyConflicts(hotkeyManager.conflicts)
    }

    private func handle(_ action: HotkeyAction) {
        switch action {
        case .focus(let slot):
            focus(slot: slot)
        case .bind(let slot):
            bindFrontmost(to: slot)
        case .layout(let position):
            windowManager.applyLayout(position)
        case .moveToDisplay(let index):
            windowManager.moveFocusedWindow(toDisplay: index)
        case .cycleDisplay(let delta):
            windowManager.cycleFocusedWindowDisplay(by: delta)
        }
    }

    // MARK: - Slot actions

    private func focus(slot: Int) {
        guard let binding = bindingStore.binding(forSlot: slot) else { return }
        let current = windowManager.focusedWindowInfo()

        // Pressing the slot you are already on returns you to where you were.
        if preferences.toggleBackEnabled,
           let previous = previousWindow,
           windowManager.isFrontmost(binding: binding) {
            previousWindow = current
            windowManager.focus(info: previous)
            return
        }

        previousWindow = current
        windowManager.focus(binding: binding, restoreFrame: preferences.restoreFramesOnFocus)
    }

    private func bindFrontmost(to slot: Int) {
        guard let info = windowManager.focusedWindowInfo() else {
            menuBarController?.flash(slot: slot, bound: false)
            return
        }
        bindingStore.update(slot: slot, with: info, windowManager: windowManager)
        menuBarController?.flash(slot: slot, bound: true)
    }

    /// Records where the bound window currently sits, falling back to the
    /// focused window when the binding's own window is gone.
    private func saveFrame(for slot: Int) {
        guard let binding = bindingStore.binding(forSlot: slot),
              let frame = windowManager.frame(ofBinding: binding) ?? windowManager.focusedWindowFrame()
        else { return }
        bindingStore.saveFrame(CodableRect(frame), forSlot: slot)
    }

    private func showPicker(for slot: Int) {
        let windows = windowManager.enumerateWindows()
        guard !windows.isEmpty else {
            presentNoWindowsAlert()
            return
        }
        picker.show(windows: windows, slot: slot) { [weak self] info in
            guard let self else { return }
            self.bindingStore.update(slot: slot, with: info, windowManager: self.windowManager)
            self.menuBarController?.flash(slot: slot, bound: true)
        }
    }

    private func presentNoWindowsAlert() {
        let alert = NSAlert()
        if WindowManager.isAccessibilityGranted() {
            alert.messageText = "No windows found"
            alert.informativeText = "No other app is currently showing a window to bind."
        } else {
            alert.messageText = "Accessibility permission required"
            alert.informativeText = """
                ScreenManager needs Accessibility access to list and focus windows. \
                Grant it in System Settings → Privacy & Security → Accessibility.
                """
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if !WindowManager.isAccessibilityGranted(), response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Activation tracking

    private func observeActivations() {
        let own = ProcessInfo.processInfo.processIdentifier
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != own
            else { return }
            self?.lastExternalPID = app.processIdentifier
        }
    }
}

/// Entry point, kept here so `Sources/ScreenManager/main.swift` stays a stub
/// and every testable type lives in the library target.
public enum ScreenManagerApp {
    /// `NSApplication.delegate` is weak, so the delegate is held here for the
    /// life of the process.
    private static var delegate: AppDelegate?

    public static func main() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()

        exit(0)
    }
}
