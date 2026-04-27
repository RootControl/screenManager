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

    func focus(binding: SlotBinding) {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == binding.bundleID
        }

        for app in apps {
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
    }
}
