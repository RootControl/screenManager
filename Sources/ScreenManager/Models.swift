import AppKit
import ApplicationServices

struct WindowInfo {
    let pid: pid_t
    let bundleID: String
    let appName: String
    let windowTitle: String
    let axElement: AXUIElement
}

struct SlotBinding: Codable, Equatable {
    var slot: Int
    var bundleID: String
    var windowTitlePattern: String
    var appName: String

    var displayLabel: String {
        "\(appName) — \(windowTitlePattern)"
    }
}
