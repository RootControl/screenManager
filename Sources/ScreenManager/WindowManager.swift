import AppKit
import ApplicationServices

final class WindowManager {
    static func isAccessibilityGranted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
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

            for window in windows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                guard let title = titleRef as? String, !title.isEmpty else { continue }

                results.append(WindowInfo(
                    pid: app.processIdentifier,
                    bundleID: bundleID,
                    appName: appName,
                    windowTitle: title,
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
                  let windows = windowsRef as? [AXUIElement]
            else { continue }

            for window in windows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                guard let title = titleRef as? String,
                      title.hasPrefix(binding.windowTitlePattern)
                else { continue }

                // Un-minimize if needed
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFBoolean)
                // Bring window to front within its app
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                // Bring the app's process to the foreground
                app.activate(options: [])
                return
            }
        }
    }
}
