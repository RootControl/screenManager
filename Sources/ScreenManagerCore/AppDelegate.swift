import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkeyManager = HotkeyManager()
    private let windowManager = WindowManager()
    private let bindingStore = BindingStore()
    private let preferencesStore = PreferencesStore()
    private let arrangementStore = ArrangementStore()
    private let picker = WindowPicker()
    private var menuBarController: MenuBarController?
    private var dragSnap: DragSnapController?
    private var slotHUD: SlotHUD?

    /// Where ⌥N returns you to when pressed on the window you are already on.
    private var previousWindow: WindowInfo?
    /// Last app to activate that was not ScreenManager.
    private var lastExternalPID: pid_t?

    private var preferences: Preferences { preferencesStore.preferences }

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        WindowManager.promptForAccessibility()
        observeActivations()
        observeScreenChanges()

        windowManager.externalPIDProvider = { [weak self] in self?.lastExternalPID }
        windowManager.excludedBundleIDs = Set(preferences.excludedBundleIDs)

        dragSnap = DragSnapController(windowManager: windowManager)
        slotHUD = SlotHUD { [weak self] in self?.hudRows() ?? [] }

        menuBarController = MenuBarController(
            store: bindingStore,
            preferencesStore: preferencesStore,
            arrangementStore: arrangementStore,
            windowManager: windowManager,
            actions: makeActions()
        )

        hotkeyManager.onPressed = { [weak self] id in
            guard let self, let action = HotkeyAction.from(id: id) else { return }
            self.handle(action)
        }

        registerHotkeys()
        applyInteractionSettings()
    }

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregisterAll()
        dragSnap?.disable()
        slotHUD?.disable()
    }

    private func makeActions() -> MenuBarActions {
        MenuBarActions(
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
            moveToSpace: { [weak self] index in
                self?.moveFocusedWindowToSpace(index)
            },
            restoreAll: { [weak self] in self?.restoreAllFrames() },
            undoLayout: { [weak self] in
                self?.windowManager.undoLastFrameChange()
            },
            saveArrangement: { [weak self] name in self?.saveArrangement(named: name) },
            restoreArrangement: { [weak self] name in self?.restoreArrangement(named: name) },
            deleteArrangement: { [weak self] name in self?.arrangementStore.delete(named: name) },
            assignProfileToDisplays: { [weak self] in self?.assignProfileToCurrentDisplays() },
            preferencesChanged: { [weak self] in
                self?.registerHotkeys()
                self?.applyInteractionSettings()
            },
            quit: { NSApplication.shared.terminate(nil) }
        )
    }

    // MARK: - Settings that drive live behaviour

    private func registerHotkeys() {
        hotkeyManager.register(HotkeyPlan.specs(for: preferences))
        menuBarController?.setHotkeyConflicts(hotkeyManager.conflicts)
    }

    /// Re-applies every preference that owns a running resource: event taps,
    /// event monitors, and the picker's exclusion list.
    private func applyInteractionSettings() {
        windowManager.excludedBundleIDs = Set(preferences.excludedBundleIDs)

        if preferences.dragToEdgeSnapping {
            dragSnap?.enable()
        } else {
            dragSnap?.disable()
        }

        if preferences.slotHUDEnabled {
            slotHUD?.enable(modifiers: preferences.focusModifiers.nsMask)
        } else {
            slotHUD?.disable()
        }
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
        case .moveToSpace(let index):
            moveFocusedWindowToSpace(index)
        case .focusDirection(let direction):
            windowManager.focusWindow(inDirection: direction)
        case .restoreAll:
            restoreAllFrames()
        case .undoLayout:
            windowManager.undoLastFrameChange()
        }
    }

    // MARK: - Slot actions

    private func focus(slot: Int) {
        guard let binding = bindingStore.binding(forSlot: slot) else { return }

        if windowManager.isFrontmost(binding: binding) {
            switch preferences.repeatPress {
            case .goBack:
                guard let previous = previousWindow else { return }
                previousWindow = windowManager.focusedWindowInfo()
                windowManager.focus(info: previous)
            case .cycleWindows:
                windowManager.cycleWindows(ofBundleID: binding.bundleID)
            case .doNothing:
                break
            }
            return
        }

        previousWindow = windowManager.focusedWindowInfo()
        let resolved = windowManager.focus(binding: binding, restoreFrame: preferences.restoreFramesOnFocus)

        // The window was found the slow way, so the stored ID is stale — write
        // the current one back and the next lookup takes the fast path.
        if let resolved, !resolved.matchedByWindowID, resolved.windowID != binding.windowID {
            bindingStore.refreshWindowID(resolved.windowID, forSlot: slot)
        }
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

    private func restoreAllFrames() {
        let moved = windowManager.restoreFrames(for: bindingStore.bindings)
        menuBarController?.flash(text: "↺\(moved)")
    }

    private func moveFocusedWindowToSpace(_ index: Int) {
        guard let info = windowManager.focusedWindowInfo(), let id = info.windowID else { return }
        if SpacesBridge.move(windowID: id, toSpaceIndex: index) {
            menuBarController?.flash(text: "⇢\(index + 1)")
        }
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

    // MARK: - Arrangements

    private func saveArrangement(named name: String) {
        let snapshots = windowManager.captureArrangement()
        arrangementStore.save(snapshots, as: name)
        menuBarController?.flash(text: "⛶\(snapshots.count)")
    }

    private func restoreArrangement(named name: String) {
        guard let arrangement = arrangementStore.arrangement(named: name) else { return }
        let restored = windowManager.restore(arrangement: arrangement)
        menuBarController?.flash(text: "⛶\(restored)")
    }

    // MARK: - Profiles that follow the displays

    private func assignProfileToCurrentDisplays() {
        let fingerprint = LayoutCalculator.screenFingerprint(windowManager.screenFrames())
        let profile = bindingStore.activeProfile
        preferencesStore.mutate { $0.profileByFingerprint[fingerprint] = profile }
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.switchProfileForCurrentDisplays()
        }
    }

    private func switchProfileForCurrentDisplays() {
        guard preferences.autoSwitchProfiles else { return }

        let fingerprint = LayoutCalculator.screenFingerprint(windowManager.screenFrames())
        guard let profile = preferences.profileByFingerprint[fingerprint],
              profile != bindingStore.activeProfile
        else { return }

        bindingStore.switchProfile(to: profile)
        menuBarController?.flash(text: "⇄")
    }

    // MARK: - HUD content

    private func hudRows() -> [(slot: Int, label: String?)] {
        (1...preferences.clampedSlotCount).map { slot in
            guard let binding = bindingStore.binding(forSlot: slot) else { return (slot, nil) }
            let title = windowManager.liveTitle(ofBinding: binding) ?? binding.windowTitle
            return (slot, "\(binding.appName) — \(title)")
        }
    }

    // MARK: - Permission

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
