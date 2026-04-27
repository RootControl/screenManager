import AppKit
import ApplicationServices

struct WindowInfo {
    let pid: pid_t
    let bundleID: String
    let appName: String
    let windowTitle: String
    let windowIndex: Int  // index within this app's AX window list
    let axElement: AXUIElement
}

struct SlotBinding: Codable, Equatable {
    var slot: Int
    var bundleID: String
    var windowIndex: Int  // position in the app's AX window list at bind time
    var appName: String
    var windowTitle: String  // display only, not used for matching

    var displayLabel: String {
        "\(appName) — \(windowTitle)"
    }
}
