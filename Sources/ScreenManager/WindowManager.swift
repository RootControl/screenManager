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

    // MARK: - Focus

    func focus(binding: SlotBinding) {
        let matchingApps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == binding.bundleID
        }

        // Try to raise the exact window by index
        for app in matchingApps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windowsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                  let windows = windowsRef as? [AXUIElement],
                  binding.windowIndex < windows.count
            else { continue }

            let window = windows[binding.windowIndex]
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFBoolean)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            app.activate(options: [])
            return
        }

        // Window not found — try reopening via stored URL
        if let urlString = binding.reopenURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return
        }

        // Fallback: activate the app if running, otherwise launch it
        if let app = matchingApps.first {
            app.activate(options: [])
        } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: binding.bundleID) {
            NSWorkspace.shared.openApplication(
                at: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    // MARK: - Reopen URL resolution

    /// Returns a URL string that can reopen the window associated with the given process and window title.
    /// For VS Code, resolves the workspace folder from VS Code's SQLite history and returns a `vscode://file/...` URL.
    /// For other apps, returns nil (launch-by-bundle-ID fallback is used instead).
    func reopenURL(for info: WindowInfo) -> String? {
        guard info.bundleID == "com.microsoft.VSCode" else { return nil }
        return vscodeReopenURL(windowTitle: info.windowTitle)
    }

    private func vscodeReopenURL(windowTitle: String) -> String? {
        // VS Code stores recently opened folders in its globalStorage SQLite DB.
        // Match the folder name from the window title against those entries.
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User/globalStorage/state.vscdb")
            .path

        // Window title format: "tab — folder — Visual Studio Code" or "folder — Visual Studio Code"
        // The folder name is always the last segment before "Visual Studio Code".
        let parts = windowTitle.components(separatedBy: " — ")
        let projectName: String
        if parts.count >= 2 {
            // Drop the trailing "Visual Studio Code" suffix if present, take what's left as the folder
            let trimmed = parts.last == "Visual Studio Code" ? parts.dropLast() : ArraySlice(parts)
            projectName = trimmed.last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        } else {
            projectName = windowTitle.trimmingCharacters(in: .whitespaces)
        }

        guard !projectName.isEmpty else { return nil }

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
}
