import AppKit

/// Everything the menu can ask the app to do.
struct MenuBarActions {
    var focusSlot: (Int) -> Void
    var pickWindow: (Int) -> Void
    var bindFrontmost: (Int) -> Void
    var saveFrame: (Int) -> Void
    var clearFrame: (Int) -> Void
    var clearSlot: (Int) -> Void
    var applyLayout: (LayoutPosition) -> Void
    var moveToDisplay: (Int) -> Void
    var moveToSpace: (Int) -> Void
    var restoreAll: () -> Void
    var undoLayout: () -> Void
    var saveArrangement: (String) -> Void
    var restoreArrangement: (String) -> Void
    var deleteArrangement: (String) -> Void
    var assignProfileToDisplays: () -> Void
    var preferencesChanged: () -> Void
    var quit: () -> Void
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: BindingStore
    private let preferencesStore: PreferencesStore
    private let arrangementStore: ArrangementStore
    private let windowManager: WindowManager
    private let actions: MenuBarActions
    private var hotkeyConflicts: [String] = []
    private var flashWorkItem: DispatchWorkItem?

    private var preferences: Preferences { preferencesStore.preferences }

    init(
        store: BindingStore,
        preferencesStore: PreferencesStore,
        arrangementStore: ArrangementStore,
        windowManager: WindowManager,
        actions: MenuBarActions
    ) {
        self.store = store
        self.preferencesStore = preferencesStore
        self.arrangementStore = arrangementStore
        self.windowManager = windowManager
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: "ScreenManager"
        )

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func setHotkeyConflicts(_ conflicts: [String]) {
        hotkeyConflicts = conflicts
    }

    /// Briefly shows the slot number in the menu bar, so a keyboard-driven
    /// bind is visibly confirmed.
    func flash(slot: Int, bound: Bool) {
        flash(text: bound ? "\(slot)" : "⌫\(slot)")
    }

    /// Briefly shows a short status string next to the menu bar icon, so
    /// keyboard-driven actions are visibly confirmed.
    func flash(text: String) {
        flashWorkItem?.cancel()
        guard let button = statusItem.button else { return }

        button.title = " \(text)"
        let work = DispatchWorkItem { [weak self] in
            self?.statusItem.button?.title = ""
        }
        flashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    // MARK: - Menu construction

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !WindowManager.isAccessibilityGranted() {
            let warning = NSMenuItem(
                title: "⚠️ Accessibility permission required — open Settings",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        if !hotkeyConflicts.isEmpty {
            let item = NSMenuItem(
                title: "⚠️ \(hotkeyConflicts.count) hotkey\(hotkeyConflicts.count == 1 ? "" : "s") unavailable",
                action: nil,
                keyEquivalent: ""
            )
            item.submenu = conflictSubmenu()
            menu.addItem(item)
            menu.addItem(.separator())
        }

        addSlotItems(to: menu)

        menu.addItem(.separator())

        let restore = menuItem(
            "Restore All Positions  \(preferences.layoutModifiers.display)R",
            #selector(restoreAll)
        )
        restore.isEnabled = store.bindings.contains { $0.savedFrame != nil }
        menu.addItem(restore)

        let undo = menuItem("Undo Layout Change  \(preferences.layoutModifiers.display)Z", #selector(undoLayout))
        undo.isEnabled = windowManager.canUndo
        menu.addItem(undo)

        menu.addItem(.separator())
        menu.addItem(submenuItem(title: "Window Layout", submenu: layoutSubmenu()))
        menu.addItem(submenuItem(title: "Move to Display", submenu: displaySubmenu()))
        menu.addItem(submenuItem(title: "Move to Space", submenu: spacesSubmenu()))
        menu.addItem(submenuItem(title: "Arrangements", submenu: arrangementsSubmenu()))
        menu.addItem(submenuItem(title: "Profiles", submenu: profilesSubmenu()))
        menu.addItem(submenuItem(title: "Settings", submenu: settingsSubmenu()))

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ScreenManager", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addSlotItems(to menu: NSMenu) {
        let focusModifiers = preferences.focusModifiers.nsMask

        for slot in 1...preferences.clampedSlotCount {
            let item: NSMenuItem

            if let binding = store.binding(forSlot: slot) {
                // Show the window's title as it reads right now, not as it read
                // when it was bound. Nil means the window is gone.
                let liveTitle = windowManager.liveTitle(ofBinding: binding)
                let label = liveTitle.map { "\(binding.appName) — \($0)" }
                    ?? "\(binding.displayLabel) (closed)"
                item = NSMenuItem(
                    title: "[\(slot)] \(label)",
                    action: #selector(focusSlot(_:)),
                    keyEquivalent: String(slot)
                )
                if liveTitle == nil {
                    item.attributedTitle = NSAttributedString(
                        string: item.title,
                        attributes: [.foregroundColor: NSColor.secondaryLabelColor]
                    )
                }
            } else {
                item = NSMenuItem(
                    title: "[\(slot)] (empty)",
                    action: #selector(pickWindow(_:)),
                    keyEquivalent: String(slot)
                )
            }

            item.keyEquivalentModifierMask = focusModifiers
            item.tag = slot
            item.target = self
            item.submenu = slotSubmenu(for: slot)
            menu.addItem(item)
        }
    }

    private func slotSubmenu(for slot: Int) -> NSMenu {
        let submenu = NSMenu()
        let bound = store.binding(forSlot: slot)

        if bound != nil {
            submenu.addItem(menuItem("Focus", #selector(focusSlot(_:)), tag: slot))
            submenu.addItem(.separator())
        }

        submenu.addItem(menuItem("Pick Window…", #selector(pickWindow(_:)), tag: slot))
        submenu.addItem(menuItem(
            "Bind Frontmost Window  \(preferences.bindModifiers.display)\(slot)",
            #selector(bindFrontmost(_:)),
            tag: slot
        ))

        if let binding = bound {
            submenu.addItem(.separator())
            submenu.addItem(menuItem("Save Current Position", #selector(saveFrame(_:)), tag: slot))
            if binding.savedFrame != nil {
                let clear = menuItem("Forget Saved Position", #selector(clearFrame(_:)), tag: slot)
                clear.state = .on
                submenu.addItem(clear)
            }
            submenu.addItem(.separator())
            submenu.addItem(menuItem("Clear Slot \(slot)", #selector(clearSlot(_:)), tag: slot))
        }

        return submenu
    }

    private func layoutSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let shortcuts = Dictionary(
            uniqueKeysWithValues: HotkeyPlan.layoutKeys.map { ($0.position, $0.symbol) }
        )

        var previousGroup = 0
        for (index, position) in LayoutPosition.allCases.enumerated() {
            // Separate halves / quarters / thirds / whole-screen groups.
            let group = index < 4 ? 0 : (index < 8 ? 1 : (index < 13 ? 2 : 3))
            if group != previousGroup { submenu.addItem(.separator()) }
            previousGroup = group

            let suffix = shortcuts[position].map { "  \(preferences.layoutModifiers.display)\($0)" } ?? ""
            let item = NSMenuItem(
                title: position.title + suffix,
                action: #selector(applyLayout(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            item.target = self
            submenu.addItem(item)
        }
        return submenu
    }

    private func displaySubmenu() -> NSMenu {
        let submenu = NSMenu()
        let screens = NSScreen.screens

        if screens.count < 2 {
            submenu.addItem(disabledItem("Only one display connected"))
            return submenu
        }

        for (index, screen) in screens.enumerated() {
            let name = screen.localizedName
            let size = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"
            let shortcut = index < 9 ? "  \(preferences.displayModifiers.display)\(index + 1)" : ""
            let item = NSMenuItem(
                title: "\(index + 1). \(name) (\(size))\(shortcut)",
                action: #selector(moveToDisplay(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            item.target = self
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        submenu.addItem(disabledItem(
            "Cycle: \(preferences.displayModifiers.display)← / \(preferences.displayModifiers.display)→"
        ))
        return submenu
    }

    private func spacesSubmenu() -> NSMenu {
        let submenu = NSMenu()

        guard SpacesBridge.isAvailable else {
            submenu.addItem(disabledItem("Spaces control unavailable on this macOS version"))
            return submenu
        }

        let count = SpacesBridge.spaceCount
        guard count > 1 else {
            submenu.addItem(disabledItem("Only one Space — add more in Mission Control"))
            return submenu
        }

        for index in 0..<count {
            let shortcut = index < 9 ? "  \(preferences.spaceModifiers.display)\(index + 1)" : ""
            let item = NSMenuItem(
                title: "Space \(index + 1)\(shortcut)",
                action: #selector(moveToSpace(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            item.target = self
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        submenu.addItem(disabledItem("Uses a private macOS API; may break on major updates"))
        return submenu
    }

    private func arrangementsSubmenu() -> NSMenu {
        let submenu = NSMenu()

        if arrangementStore.names.isEmpty {
            submenu.addItem(disabledItem("No saved arrangements"))
        } else {
            for name in arrangementStore.names {
                let count = arrangementStore.arrangement(named: name)?.snapshots.count ?? 0
                let item = NSMenuItem(
                    title: "\(name) (\(count) windows)",
                    action: #selector(restoreArrangement(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = name
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())
        submenu.addItem(menuItem("Save Current Arrangement…", #selector(saveArrangement)))

        if !arrangementStore.names.isEmpty {
            let delete = NSMenuItem(title: "Delete", action: nil, keyEquivalent: "")
            let deleteMenu = NSMenu()
            for name in arrangementStore.names {
                let item = NSMenuItem(title: name, action: #selector(deleteArrangement(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = name
                deleteMenu.addItem(item)
            }
            delete.submenu = deleteMenu
            submenu.addItem(delete)
        }

        return submenu
    }

    private func profilesSubmenu() -> NSMenu {
        let submenu = NSMenu()

        for name in store.profileNames {
            let item = NSMenuItem(title: name, action: #selector(switchProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = name == store.activeProfile ? .on : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        submenu.addItem(menuItem("New Empty Profile…", #selector(newProfile)))
        submenu.addItem(menuItem("Duplicate Current Profile…", #selector(duplicateProfile)))

        submenu.addItem(.separator())
        let assign = menuItem("Use for This Display Setup", #selector(assignProfileToDisplays))
        let fingerprint = LayoutCalculator.screenFingerprint(windowManager.screenFrames())
        assign.state = preferences.profileByFingerprint[fingerprint] == store.activeProfile ? .on : .off
        submenu.addItem(assign)

        if store.profileNames.count > 1 {
            let delete = NSMenuItem(
                title: "Delete “\(store.activeProfile)”",
                action: #selector(deleteProfile),
                keyEquivalent: ""
            )
            delete.target = self
            submenu.addItem(.separator())
            submenu.addItem(delete)
        }

        return submenu
    }

    private func settingsSubmenu() -> NSMenu {
        let submenu = NSMenu()

        submenu.addItem(submenuItem(
            title: "Focus Shortcut: \(preferences.focusModifiers.display)1–\(preferences.clampedSlotCount)",
            submenu: modifierSubmenu(
                presets: Preferences.focusPresets,
                current: preferences.focusModifiers,
                selector: #selector(setFocusModifiers(_:))
            )
        ))
        submenu.addItem(disabledItem("Bind Shortcut: \(preferences.bindModifiers.display)1–\(preferences.clampedSlotCount)"))
        submenu.addItem(submenuItem(
            title: "Layout Shortcut: \(preferences.layoutModifiers.display)",
            submenu: modifierSubmenu(
                presets: Preferences.layoutPresets,
                current: preferences.layoutModifiers,
                selector: #selector(setLayoutModifiers(_:))
            )
        ))
        submenu.addItem(submenuItem(
            title: "Display Shortcut: \(preferences.displayModifiers.display)",
            submenu: modifierSubmenu(
                presets: Preferences.displayPresets,
                current: preferences.displayModifiers,
                selector: #selector(setDisplayModifiers(_:))
            )
        ))

        if SpacesBridge.isAvailable {
            submenu.addItem(submenuItem(
                title: "Space Shortcut: \(preferences.spaceModifiers.display)",
                submenu: modifierSubmenu(
                    presets: Preferences.spacePresets,
                    current: preferences.spaceModifiers,
                    selector: #selector(setSpaceModifiers(_:))
                )
            ))
        }

        submenu.addItem(.separator())
        submenu.addItem(submenuItem(title: "Slots: \(preferences.clampedSlotCount)", submenu: slotCountSubmenu()))
        submenu.addItem(submenuItem(
            title: "Pressing Again: \(preferences.repeatPress.title)",
            submenu: repeatPressSubmenu()
        ))

        let restore = menuItem("Restore Saved Positions on Focus", #selector(toggleRestoreFrames))
        restore.state = preferences.restoreFramesOnFocus ? .on : .off
        submenu.addItem(restore)

        let autoSwitch = menuItem("Switch Profiles with Display Setup", #selector(toggleAutoSwitchProfiles))
        autoSwitch.state = preferences.autoSwitchProfiles ? .on : .off
        submenu.addItem(autoSwitch)

        submenu.addItem(.separator())
        let dragSnap = menuItem("Snap Windows Dragged to Screen Edges", #selector(toggleDragSnapping))
        dragSnap.state = preferences.dragToEdgeSnapping ? .on : .off
        submenu.addItem(dragSnap)

        let hud = menuItem("Show Slot Overview While Holding \(preferences.focusModifiers.display)", #selector(toggleSlotHUD))
        hud.state = preferences.slotHUDEnabled ? .on : .off
        submenu.addItem(hud)

        submenu.addItem(submenuItem(title: "Hide Apps from Picker", submenu: exclusionsSubmenu()))

        submenu.addItem(.separator())
        let login = menuItem("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        if LoginItem.needsApproval {
            login.title = "Launch at Login (needs approval)"
        }
        submenu.addItem(login)

        return submenu
    }

    private func repeatPressSubmenu() -> NSMenu {
        let submenu = NSMenu()
        for (index, behavior) in RepeatPressBehavior.allCases.enumerated() {
            let item = NSMenuItem(title: behavior.title, action: #selector(setRepeatPress(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = behavior == preferences.repeatPress ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    /// Lists apps that currently have windows, plus anything already excluded
    /// so a hidden app can always be un-hidden even once it has quit.
    private func exclusionsSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let excluded = Set(preferences.excludedBundleIDs)

        var apps: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, let name = app.localizedName else { continue }
            apps[bundleID] = name
        }
        for bundleID in excluded where apps[bundleID] == nil {
            apps[bundleID] = bundleID
        }

        guard !apps.isEmpty else {
            submenu.addItem(disabledItem("No apps running"))
            return submenu
        }

        for (bundleID, name) in apps.sorted(by: { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }) {
            let item = NSMenuItem(title: name, action: #selector(toggleExclusion(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bundleID
            item.state = excluded.contains(bundleID) ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func modifierSubmenu(presets: [ModifierCombo], current: ModifierCombo, selector: Selector) -> NSMenu {
        let submenu = NSMenu()
        for (index, combo) in presets.enumerated() {
            let item = NSMenuItem(title: combo.display, action: selector, keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = combo == current ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func slotCountSubmenu() -> NSMenu {
        let submenu = NSMenu()
        for count in 1...9 {
            let item = NSMenuItem(title: "\(count)", action: #selector(setSlotCount(_:)), keyEquivalent: "")
            item.target = self
            item.tag = count
            item.state = count == preferences.clampedSlotCount ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func conflictSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.addItem(disabledItem("Another app already owns:"))
        for label in hotkeyConflicts {
            submenu.addItem(disabledItem("  \(label)"))
        }
        submenu.addItem(.separator())
        submenu.addItem(disabledItem("Change the modifiers under Settings."))
        return submenu
    }

    // MARK: - Menu item helpers

    private func menuItem(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        return item
    }

    private func submenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Slot actions

    @objc private func focusSlot(_ sender: NSMenuItem) { actions.focusSlot(sender.tag) }
    @objc private func pickWindow(_ sender: NSMenuItem) { actions.pickWindow(sender.tag) }
    @objc private func bindFrontmost(_ sender: NSMenuItem) { actions.bindFrontmost(sender.tag) }
    @objc private func saveFrame(_ sender: NSMenuItem) { actions.saveFrame(sender.tag) }
    @objc private func clearFrame(_ sender: NSMenuItem) { actions.clearFrame(sender.tag) }
    @objc private func clearSlot(_ sender: NSMenuItem) { actions.clearSlot(sender.tag) }

    @objc private func applyLayout(_ sender: NSMenuItem) {
        guard sender.tag < LayoutPosition.allCases.count else { return }
        actions.applyLayout(LayoutPosition.allCases[sender.tag])
    }

    @objc private func moveToDisplay(_ sender: NSMenuItem) { actions.moveToDisplay(sender.tag) }
    @objc private func moveToSpace(_ sender: NSMenuItem) { actions.moveToSpace(sender.tag) }
    @objc private func restoreAll() { actions.restoreAll() }
    @objc private func undoLayout() { actions.undoLayout() }

    // MARK: - Arrangement actions

    @objc private func saveArrangement() {
        guard let name = promptForName(
            title: "Save Arrangement",
            message: "Name for this arrangement of every open window:"
        ) else { return }
        actions.saveArrangement(name)
    }

    @objc private func restoreArrangement(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        actions.restoreArrangement(name)
    }

    @objc private func deleteArrangement(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        actions.deleteArrangement(name)
    }

    @objc private func assignProfileToDisplays() { actions.assignProfileToDisplays() }

    // MARK: - Profile actions

    @objc private func switchProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        store.switchProfile(to: name)
    }

    @objc private func newProfile() {
        guard let name = promptForName(title: "New Profile", message: "Name for the new, empty profile:") else { return }
        store.createEmptyProfile(named: name)
    }

    @objc private func duplicateProfile() {
        guard let name = promptForName(
            title: "Duplicate Profile",
            message: "Name for a copy of “\(store.activeProfile)”:"
        ) else { return }
        store.saveProfile(as: name)
    }

    @objc private func deleteProfile() {
        store.deleteProfile(named: store.activeProfile)
    }

    private func promptForName(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: - Settings actions

    @objc private func setFocusModifiers(_ sender: NSMenuItem) {
        guard sender.tag < Preferences.focusPresets.count else { return }
        preferencesStore.mutate { $0.focusModifiers = Preferences.focusPresets[sender.tag] }
        actions.preferencesChanged()
    }

    @objc private func setLayoutModifiers(_ sender: NSMenuItem) {
        guard sender.tag < Preferences.layoutPresets.count else { return }
        preferencesStore.mutate { $0.layoutModifiers = Preferences.layoutPresets[sender.tag] }
        actions.preferencesChanged()
    }

    @objc private func setDisplayModifiers(_ sender: NSMenuItem) {
        guard sender.tag < Preferences.displayPresets.count else { return }
        preferencesStore.mutate { $0.displayModifiers = Preferences.displayPresets[sender.tag] }
        actions.preferencesChanged()
    }

    @objc private func setSlotCount(_ sender: NSMenuItem) {
        preferencesStore.mutate { $0.slotCount = sender.tag }
        actions.preferencesChanged()
    }

    @objc private func setSpaceModifiers(_ sender: NSMenuItem) {
        guard sender.tag < Preferences.spacePresets.count else { return }
        preferencesStore.mutate { $0.spaceModifiers = Preferences.spacePresets[sender.tag] }
        actions.preferencesChanged()
    }

    @objc private func setRepeatPress(_ sender: NSMenuItem) {
        guard sender.tag < RepeatPressBehavior.allCases.count else { return }
        preferencesStore.mutate { $0.repeatPress = RepeatPressBehavior.allCases[sender.tag] }
    }

    @objc private func toggleRestoreFrames() {
        preferencesStore.mutate { $0.restoreFramesOnFocus.toggle() }
    }

    @objc private func toggleAutoSwitchProfiles() {
        preferencesStore.mutate { $0.autoSwitchProfiles.toggle() }
    }

    @objc private func toggleDragSnapping() {
        preferencesStore.mutate { $0.dragToEdgeSnapping.toggle() }
        actions.preferencesChanged()
    }

    @objc private func toggleSlotHUD() {
        preferencesStore.mutate { $0.slotHUDEnabled.toggle() }
        actions.preferencesChanged()
    }

    @objc private func toggleExclusion(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        preferencesStore.mutate { preferences in
            if let index = preferences.excludedBundleIDs.firstIndex(of: bundleID) {
                preferences.excludedBundleIDs.remove(at: index)
            } else {
                preferences.excludedBundleIDs.append(bundleID)
            }
        }
        actions.preferencesChanged()
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = !LoginItem.isEnabled
        do {
            try LoginItem.setEnabled(enable)
            if enable && LoginItem.needsApproval {
                LoginItem.openLoginItemsSettings()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not \(enable ? "enable" : "disable") Launch at Login"
            alert.informativeText = """
                \(error.localizedDescription)

                This requires ScreenManager to be running from ScreenManager.app \
                rather than directly from the build directory.
                """
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: - Misc

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() { actions.quit() }
}
