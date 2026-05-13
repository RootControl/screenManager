import AppKit
import ApplicationServices

final class WindowManager {
    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func enumerateWindows() -> [WindowInfo] {
        var results: [WindowInfo] = []
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            guard
                app.activationPolicy != .prohibited,
                let bundleID = app.bundleIdentifier,
                let appName = app.localizedName
            else { continue }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let windows = windowsRef as? [AXUIElement] else { continue }

            for (idx, window) in windows.enumerated() {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String) ?? "(untitled)"

                results.append(WindowInfo(
                    pid: app.processIdentifier,
                    bundleID: bundleID,
                    appName: appName,
                    windowTitle: title,
                    windowIndex: idx,
                    axElement: window
                ))
            }
        }

        return results
    }

    func frontmostWindowInfo() -> WindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              let appName = app.localizedName
        else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first
        else { return nil }

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? "(untitled)"

        return WindowInfo(pid: app.processIdentifier, bundleID: bundleID, appName: appName,
                          windowTitle: title, windowIndex: 0, axElement: window)
    }

    // MARK: - Focus

    func focus(binding: SlotBinding) {
        let matchingApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == binding.bundleID
        }

        if raiseWindow(in: matchingApps, matching: binding) { return }

        // Window not found — reopen the project
        if let urlString = binding.reopenURL,
           let url = URL(string: urlString),
           url.scheme == "vscode" {
            // Use `code --new-window` so VS Code always opens a new window
            // rather than reusing the currently focused one.
            let path = url.path // vscode://file/Users/dev/... → /Users/dev/...
            runCommandDetached("/opt/homebrew/bin/code", args: ["--new-window", path])
            return
        }

        // Fallback: activate the app if running, otherwise cold-launch it
        if let app = matchingApps.first {
            app.activate(options: [])
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleID) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Finds and raises the window described by `binding`. Returns true if a window was raised.
    private func raiseWindow(in apps: [NSRunningApplication], matching binding: SlotBinding) -> Bool {
        let folderName = vscodeProjectName(from: binding.windowTitle)

        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement]
            else { continue }

            // For apps where each window has a meaningful title (e.g. VS Code),
            // match by title rather than index — index shifts as windows open/close.
            let target: AXUIElement?
            if let folder = folderName {
                target = windows.first { axTitle($0).map { vscodeProjectName(from: $0) == folder } ?? false }
                    ?? (binding.windowIndex < windows.count ? windows[binding.windowIndex] : nil)
            } else {
                target = binding.windowIndex < windows.count ? windows[binding.windowIndex] : windows.first
            }

            guard let window = target else { continue }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFBoolean)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            app.activate(options: [])
            return true
        }
        return false
    }

    private func axTitle(_ element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref)
        return ref as? String
    }

    // MARK: - Reopen URL resolution

    /// Returns a URL string that can reopen the window associated with the given process and window title.
    /// For VS Code, resolves the workspace folder from VS Code's SQLite history and returns a `vscode://file/...` URL.
    /// For other apps, returns nil (launch-by-bundle-ID fallback is used instead).
    func reopenURL(for info: WindowInfo) -> String? {
        guard info.bundleID == "com.microsoft.VSCode" else { return nil }
        return vscodeReopenURL(windowTitle: info.windowTitle)
    }

    /// Extracts the VS Code project folder name from a window title.
    /// Title format: "tab — folder — Visual Studio Code" → "folder"
    private func vscodeProjectName(from windowTitle: String) -> String? {
        let parts = windowTitle.components(separatedBy: " — ")
        guard parts.count >= 2 else { return nil }
        let trimmed = parts.last == "Visual Studio Code" ? parts.dropLast() : ArraySlice(parts)
        let name = trimmed.last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return name.isEmpty ? nil : name
    }

    private func vscodeReopenURL(windowTitle: String) -> String? {
        // VS Code stores recently opened folders in its globalStorage SQLite DB.
        // Match the folder name from the window title against those entries.
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User/globalStorage/state.vscdb")
            .path

        guard let projectName = vscodeProjectName(from: windowTitle) else { return nil }

        // Query the SQLite DB for recently opened folder URIs
        let json = runCommand("/usr/bin/sqlite3", args: [
            dbPath,
            "SELECT value FROM ItemTable WHERE key = 'history.recentlyOpenedPathsList';"
        ])

        if let data = json.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let entries = root["entries"] as? [[String: Any]] {

            // Find the entry whose last path component matches the project name
            for entry in entries {
                guard let folderURI = entry["folderUri"] as? String,
                      let url = URL(string: folderURI),
                      url.lastPathComponent == projectName
                else { continue }

                // Convert file:///path to vscode://file/path
                let path = url.path
                let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
                return "vscode://file\(encoded)"
            }
        }

        return nil
    }

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
