import AppKit
import ApplicationServices

/// A window found on the system, plus how confidently it was identified.
struct ResolvedWindow {
    let app: NSRunningApplication
    let element: AXUIElement
    let windowID: CGWindowID?
    /// False when the window had to be found by document, title, or position —
    /// a signal that the stored window ID is stale and worth refreshing.
    let matchedByWindowID: Bool
}

final class WindowManager {

    /// Opening our own menu makes ScreenManager frontmost, which would hide the
    /// window the user is actually working in. The app supplies the PID it last
    /// saw activate so menu-driven actions still target that window.
    var externalPIDProvider: (() -> pid_t?)?

    /// Bundle IDs to hide from window enumeration.
    var excludedBundleIDs: Set<String> = []

    /// Frames replaced by a layout or display move, newest last.
    private var undoStack: [(windowID: CGWindowID, frame: CGRect)] = []
    private static let undoLimit = 25

    // MARK: - Permission

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Enumeration

    func enumerateWindows() -> [WindowInfo] {
        var results: [WindowInfo] = []
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for app in NSWorkspace.shared.runningApplications {
            guard
                app.activationPolicy != .prohibited,
                app.processIdentifier != ownPID,
                let bundleID = app.bundleIdentifier,
                !excludedBundleIDs.contains(bundleID),
                let appName = app.localizedName
            else { continue }

            for (index, window) in windows(ofPID: app.processIdentifier).enumerated() {
                // Sheets, drawers and popovers are not places you navigate to.
                guard role(of: window) == kAXWindowRole as String else { continue }

                results.append(WindowInfo(
                    pid: app.processIdentifier,
                    bundleID: bundleID,
                    appName: appName,
                    windowTitle: title(of: window) ?? "(untitled)",
                    windowIndex: index,
                    windowID: identifier(of: window),
                    documentPath: document(of: window),
                    axElement: window
                ))
            }
        }

        return results.sorted {
            $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedSame
                ? $0.windowTitle.localizedCaseInsensitiveCompare($1.windowTitle) == .orderedAscending
                : $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending
        }
    }

    /// The window the user is actually looking at — `kAXFocusedWindow` of the
    /// frontmost app, not merely the first entry in its window list.
    func focusedWindowInfo() -> WindowInfo? {
        guard let pid = targetPID() else { return nil }
        return windowInfo(forPID: pid)
    }

    func windowInfo(forPID pid: pid_t) -> WindowInfo? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              let appName = app.localizedName,
              let window = focusedWindowElement(pid: pid)
        else { return nil }

        let windowIdentifier = identifier(of: window)
        let index = windows(ofPID: pid)
            .firstIndex(where: { identifier(of: $0) == windowIdentifier }) ?? 0

        return WindowInfo(
            pid: pid,
            bundleID: bundleID,
            appName: appName,
            windowTitle: title(of: window) ?? "(untitled)",
            windowIndex: index,
            windowID: windowIdentifier,
            documentPath: document(of: window),
            axElement: window
        )
    }

    /// The app whose window an action should target: whatever is frontmost,
    /// unless that is ScreenManager itself.
    private func targetPID() -> pid_t? {
        let own = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own {
            return front.processIdentifier
        }
        return externalPIDProvider?()
    }

    private func focusedWindowElement(pid: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success,
           let element = ref, CFGetTypeID(element) == AXUIElementGetTypeID() {
            return (element as! AXUIElement)
        }
        // Some apps only expose kAXMainWindow.
        var mainRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &mainRef) == .success,
           let element = mainRef, CFGetTypeID(element) == AXUIElementGetTypeID() {
            return (element as! AXUIElement)
        }
        return windows(ofPID: pid).first
    }

    private func windows(ofPID pid: pid_t) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement]
        else { return [] }
        return windows
    }

    // MARK: - Resolution

    /// Locates the live window a query refers to, trying the most reliable key
    /// first: window ID, then document, then title, then list position.
    func resolve(query: WindowQuery) -> ResolvedWindow? {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == query.bundleID }
        let projectName = Self.vscodeProjectName(from: query.windowTitle)

        for app in apps {
            let candidates = windows(ofPID: app.processIdentifier).filter {
                role(of: $0) == kAXWindowRole as String
            }
            guard !candidates.isEmpty else { continue }

            if let wid = query.windowID,
               let match = candidates.first(where: { identifier(of: $0) == wid }) {
                return resolution(app: app, window: match, matchedByWindowID: true)
            }
            if let path = query.documentPath,
               let match = candidates.first(where: { document(of: $0) == path }) {
                return resolution(app: app, window: match, matchedByWindowID: false)
            }
            if let projectName,
               let match = candidates.first(where: { window in
                   guard let title = title(of: window) else { return false }
                   return Self.vscodeProjectName(from: title) == projectName
               }) {
                return resolution(app: app, window: match, matchedByWindowID: false)
            }
            if let match = candidates.first(where: { title(of: $0) == query.windowTitle }) {
                return resolution(app: app, window: match, matchedByWindowID: false)
            }
            if query.windowIndex < candidates.count {
                return resolution(app: app, window: candidates[query.windowIndex], matchedByWindowID: false)
            }
            return resolution(app: app, window: candidates[0], matchedByWindowID: false)
        }
        return nil
    }

    func resolve(binding: SlotBinding) -> ResolvedWindow? {
        resolve(query: binding.query)
    }

    private func resolution(app: NSRunningApplication, window: AXUIElement, matchedByWindowID: Bool) -> ResolvedWindow {
        ResolvedWindow(
            app: app,
            element: window,
            windowID: identifier(of: window),
            matchedByWindowID: matchedByWindowID
        )
    }

    /// Finds a window anywhere on the system by its ID. Used to undo a layout
    /// change on a window that may no longer be frontmost.
    func window(withID id: CGWindowID) -> ResolvedWindow? {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy != .prohibited && app.processIdentifier != ownPID {
            if let match = windows(ofPID: app.processIdentifier).first(where: { identifier(of: $0) == id }) {
                return resolution(app: app, window: match, matchedByWindowID: true)
            }
        }
        return nil
    }

    /// True when `binding` refers to the window that currently has focus.
    func isFrontmost(binding: SlotBinding) -> Bool {
        guard let front = focusedWindowInfo(),
              front.bundleID == binding.bundleID,
              let resolved = resolve(binding: binding)
        else { return false }

        if let frontID = front.windowID, let resolvedID = resolved.windowID {
            return frontID == resolvedID
        }
        return front.windowTitle == title(of: resolved.element)
    }

    // MARK: - Focus

    /// Raises the bound window, restoring its saved frame when it has one.
    /// Returns the resolution so the caller can refresh a stale window ID, or
    /// nil when the window was gone and a reopen was attempted instead.
    @discardableResult
    func focus(binding: SlotBinding, restoreFrame: Bool = true) -> ResolvedWindow? {
        guard let resolved = resolve(binding: binding) else {
            reopen(binding: binding)
            return nil
        }

        if restoreFrame, let saved = binding.savedFrame {
            setFrame(saved.cgRect, for: resolved.element)
        }
        raise(window: resolved.element, in: resolved.app)
        return resolved
    }

    /// Raises the app's next window after the one that currently has focus,
    /// wrapping around. Returns false when the app has only one window.
    @discardableResult
    func cycleWindows(ofBundleID bundleID: String) -> Bool {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
        let focusedID = focusedWindowInfo()?.windowID

        for app in apps {
            let candidates = windows(ofPID: app.processIdentifier).filter {
                role(of: $0) == kAXWindowRole as String
            }
            guard candidates.count > 1 else { continue }

            let current = candidates.firstIndex { identifier(of: $0) == focusedID } ?? 0
            let next = candidates[(current + 1) % candidates.count]
            raise(window: next, in: app)
            return true
        }
        return false
    }

    /// Moves focus to the nearest window in a direction, across every app and
    /// display. Returns false when nothing lies that way.
    @discardableResult
    func focusWindow(inDirection direction: Direction) -> Bool {
        let windows = enumerateWindows()
        guard let currentID = focusedWindowInfo()?.windowID else { return false }

        var origin: CGRect?
        var candidates: [(info: WindowInfo, frame: CGRect)] = []

        for info in windows {
            guard let frame = frame(of: info.axElement), frame.width > 1, frame.height > 1 else { continue }
            if info.windowID == currentID {
                origin = frame
            } else {
                candidates.append((info, frame))
            }
        }

        guard let origin,
              let index = LayoutCalculator.directionalTarget(
                  from: origin,
                  candidates: candidates.map(\.frame),
                  direction: direction
              )
        else { return false }

        focus(info: candidates[index].info)
        return true
    }

    func focus(info: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: info.pid) else { return }
        raise(window: info.axElement, in: app)
    }

    private func raise(window: AXUIElement, in app: NSRunningApplication) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFBoolean)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFBoolean)
        app.activate(options: [])
    }

    // MARK: - Geometry

    func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// Applies a frame in AX coordinates. Position is set twice because apps
    /// with a minimum size shift themselves when resized.
    func setFrame(_ rect: CGRect, for window: AXUIElement) {
        var origin = rect.origin
        var size = rect.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return }

        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    }

    /// Full frames of every screen, in AX coordinates, in `NSScreen.screens` order.
    func screenFrames() -> [CGRect] {
        let maxY = Self.primaryMaxY
        return NSScreen.screens.map { LayoutCalculator.flipY($0.frame, primaryMaxY: maxY) }
    }

    /// Usable areas (menu bar and Dock excluded), in AX coordinates.
    func visibleScreenFrames() -> [CGRect] {
        let maxY = Self.primaryMaxY
        return NSScreen.screens.map { LayoutCalculator.flipY($0.visibleFrame, primaryMaxY: maxY) }
    }

    private static var primaryMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    // MARK: - Layout actions

    @discardableResult
    func applyLayout(_ position: LayoutPosition) -> Bool {
        guard let (_, window) = currentWindow() else { return false }
        return applyLayout(position, to: window)
    }

    @discardableResult
    func applyLayout(_ position: LayoutPosition, to window: AXUIElement) -> Bool {
        guard let current = frame(of: window),
              let index = LayoutCalculator.screenIndex(containing: current, screens: screenFrames())
        else { return false }

        recordUndo(window: window, frame: current)
        let area = visibleScreenFrames()[index]
        setFrame(LayoutCalculator.frame(for: position, in: area, current: current), for: window)
        return true
    }

    // MARK: - Undo

    private func recordUndo(window: AXUIElement, frame: CGRect) {
        guard let id = identifier(of: window) else { return }
        undoStack.append((id, frame))
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst(undoStack.count - Self.undoLimit)
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// Puts the most recently moved window back where it was. Entries whose
    /// window has since closed are discarded rather than skipped over.
    @discardableResult
    func undoLastFrameChange() -> Bool {
        while let entry = undoStack.popLast() {
            guard let resolved = window(withID: entry.windowID) else { continue }
            setFrame(entry.frame, for: resolved.element)
            raise(window: resolved.element, in: resolved.app)
            return true
        }
        return false
    }

    // MARK: - Bulk placement

    /// Applies every saved frame in `bindings`, without raising anything.
    /// Returns how many windows were actually moved.
    @discardableResult
    func restoreFrames(for bindings: [SlotBinding]) -> Int {
        var moved = 0
        for binding in bindings {
            guard let saved = binding.savedFrame,
                  let resolved = resolve(binding: binding),
                  let current = frame(of: resolved.element)
            else { continue }

            recordUndo(window: resolved.element, frame: current)
            setFrame(saved.cgRect, for: resolved.element)
            moved += 1
        }
        return moved
    }

    /// Captures every visible window's placement for a named arrangement.
    func captureArrangement() -> [WindowSnapshot] {
        enumerateWindows().compactMap { info in
            guard let frame = frame(of: info.axElement), frame.width > 1, frame.height > 1 else { return nil }
            return WindowSnapshot(
                bundleID: info.bundleID,
                appName: info.appName,
                windowTitle: info.windowTitle,
                windowIndex: info.windowIndex,
                windowID: info.windowID,
                documentPath: info.documentPath,
                frame: CodableRect(frame)
            )
        }
    }

    /// Restores a captured arrangement, skipping windows that no longer exist.
    /// Returns how many were placed.
    @discardableResult
    func restore(arrangement: Arrangement) -> Int {
        var restored = 0
        for snapshot in arrangement.snapshots {
            guard let resolved = resolve(query: snapshot.query),
                  let current = frame(of: resolved.element)
            else { continue }

            recordUndo(window: resolved.element, frame: current)
            setFrame(snapshot.frame.cgRect, for: resolved.element)
            restored += 1
        }
        return restored
    }

    /// Moves the focused window to `index`, preserving its relative placement.
    @discardableResult
    func moveFocusedWindow(toDisplay index: Int) -> Bool {
        let visible = visibleScreenFrames()
        guard index >= 0, index < visible.count,
              let (app, window) = currentWindow(),
              let current = frame(of: window),
              let sourceIndex = LayoutCalculator.screenIndex(containing: current, screens: screenFrames())
        else { return false }

        guard sourceIndex != index else { return true }
        recordUndo(window: window, frame: current)
        setFrame(LayoutCalculator.translate(current, from: visible[sourceIndex], to: visible[index]), for: window)
        raise(window: window, in: app)
        return true
    }

    @discardableResult
    func cycleFocusedWindowDisplay(by delta: Int) -> Bool {
        guard let (_, window) = currentWindow(),
              let current = frame(of: window),
              let sourceIndex = LayoutCalculator.screenIndex(containing: current, screens: screenFrames())
        else { return false }

        let count = NSScreen.screens.count
        guard count > 1 else { return false }
        return moveFocusedWindow(toDisplay: LayoutCalculator.stepIndex(sourceIndex, by: delta, count: count))
    }

    private func currentWindow() -> (app: NSRunningApplication, window: AXUIElement)? {
        guard let pid = targetPID(),
              let app = NSRunningApplication(processIdentifier: pid),
              let window = focusedWindowElement(pid: pid)
        else { return nil }
        return (app, window)
    }

    /// The focused window's frame, for saving alongside a binding.
    func focusedWindowFrame() -> CGRect? {
        guard let (_, window) = currentWindow() else { return nil }
        return frame(of: window)
    }

    func frame(ofBinding binding: SlotBinding) -> CGRect? {
        guard let resolved = resolve(binding: binding) else { return nil }
        return frame(of: resolved.element)
    }

    /// The bound window's title as it reads right now, which drifts from the
    /// title recorded at bind time (a VS Code window renames with every tab).
    /// Returns nil only when the window no longer exists, so callers can use it
    /// as the "is this slot still alive?" check.
    func liveTitle(ofBinding binding: SlotBinding) -> String? {
        guard let resolved = resolve(binding: binding) else { return nil }
        return title(of: resolved.element) ?? binding.windowTitle
    }

    // MARK: - Reopening

    /// Best-effort revival of a window whose app or document is gone.
    private func reopen(binding: SlotBinding) {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleID)

        // A document path reopens exactly what was bound, in the right app.
        if let path = binding.documentPath, let url = Self.fileURL(from: path) {
            if let appURL {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                _ = NSWorkspace.shared.open(url)
            }
            return
        }

        if let urlString = binding.reopenURL, let url = URL(string: urlString) {
            if url.scheme == "vscode" {
                // `code --new-window` opens a window instead of hijacking the
                // focused one, which the vscode:// URL scheme would do.
                if let codePath = Self.vscodeCLIPath() {
                    runCommandDetached(codePath, args: ["--new-window", url.path])
                } else {
                    _ = NSWorkspace.shared.open(url)
                }
                return
            }
            if url.isFileURL {
                _ = NSWorkspace.shared.open(url)
                return
            }
        }

        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == binding.bundleID }) {
            app.activate(options: [])
        } else if let appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// A URL that can reopen this window later. VS Code needs its history
    /// database because a folder window exposes no document; every other app
    /// gets its `kAXDocument` value, when it has one.
    func reopenURL(for info: WindowInfo) -> String? {
        if info.bundleID == "com.microsoft.VSCode" {
            return vscodeReopenURL(windowTitle: info.windowTitle)
        }
        return info.documentPath
    }

    static func fileURL(from path: String) -> URL? {
        if path.hasPrefix("file://") { return URL(string: path) }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return nil
    }

    /// The `code` CLI, wherever this machine keeps it.
    static func vscodeCLIPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/code",
            "/usr/local/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            NSHomeDirectory() + "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - AX attribute readers

    private func title(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref)
        return ref as? String
    }

    private func role(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref)
        return ref as? String
    }

    private func document(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDocumentAttribute as CFString, &ref)
        guard let path = ref as? String, !path.isEmpty else { return nil }
        return path
    }

    private func identifier(of element: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &wid) == .success, wid != 0 else { return nil }
        return wid
    }

    // MARK: - VS Code specifics

    /// Extracts the project folder from a VS Code window title.
    /// "tab — folder — Visual Studio Code" → "folder"
    static func vscodeProjectName(from windowTitle: String) -> String? {
        let parts = windowTitle.components(separatedBy: " — ")
        guard parts.count >= 2 else { return nil }
        let trimmed = parts.last == "Visual Studio Code" ? parts.dropLast() : ArraySlice(parts)
        let name = trimmed.last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return name.isEmpty ? nil : name
    }

    /// Finds the folder URI VS Code last opened under this project name.
    static func vscodeFolderPath(inHistoryJSON json: String, projectName: String) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]]
        else { return nil }

        for entry in entries {
            guard let folderURI = entry["folderUri"] as? String,
                  let url = URL(string: folderURI),
                  url.lastPathComponent == projectName
            else { continue }
            return url.path
        }
        return nil
    }

    private func vscodeReopenURL(windowTitle: String) -> String? {
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User/globalStorage/state.vscdb")
            .path

        guard let projectName = Self.vscodeProjectName(from: windowTitle) else { return nil }

        let json = runCommand("/usr/bin/sqlite3", args: [
            dbPath,
            "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList';"
        ])

        guard let path = Self.vscodeFolderPath(inHistoryJSON: json, projectName: projectName) else { return nil }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "vscode://file\(encoded)"
    }

    // MARK: - Subprocesses

    private func runCommand(_ path: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func runCommandDetached(_ path: String, args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
