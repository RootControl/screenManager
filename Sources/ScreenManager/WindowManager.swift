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
    /// For VS Code, resolves the workspace folder via lsof and returns a `vscode://file/...` URL.
    /// For other apps, returns nil (launch-by-bundle-ID fallback is used instead).
    func reopenURL(for info: WindowInfo) -> String? {
        guard info.bundleID == "com.microsoft.VSCode" else { return nil }
        return vscodeReopenURL(pid: info.pid, windowTitle: info.windowTitle)
    }

    private func vscodeReopenURL(pid: pid_t, windowTitle: String) -> String? {
        // Ask lsof for all directories this VS Code process has open, then pick
        // the deepest one that looks like a workspace root (contains .git or is
        // the longest non-library path that matches the window title prefix).
        let lsofOutput = runCommand("/usr/sbin/lsof", args: ["-p", "\(pid)", "-Fn", "-a", "-d", "cwd"])
        let cwd = lsofOutput
            .components(separatedBy: "\n")
            .first { $0.hasPrefix("n") && !$0.contains("/Library") }
            .map { String($0.dropFirst()) } // drop leading 'n'

        if let path = cwd, !path.isEmpty {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            return "vscode://file/\(encoded)"
        }

        // Fallback: parse folder name from window title ("folderName — Visual Studio Code")
        if let folderName = windowTitle.components(separatedBy: " — ").first,
           !folderName.isEmpty {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let candidates = [
                "\(home)/\(folderName)",
                "\(home)/Projects/\(folderName)",
                "\(home)/Developer/\(folderName)",
                "\(home)/Documents/\(folderName)",
            ]
            for path in candidates {
                if FileManager.default.fileExists(atPath: path) {
                    let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
                    return "vscode://file/\(encoded)"
                }
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
