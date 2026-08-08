import AppKit
import ApplicationServices

struct WindowInfo {
    let pid: pid_t
    let bundleID: String
    let appName: String
    let windowTitle: String
    let windowIndex: Int          // index within this app's AX window list
    let windowID: CGWindowID?     // stable identity for the window's lifetime
    let documentPath: String?     // kAXDocument, when the app exposes one
    let axElement: AXUIElement

    var displayLabel: String {
        "\(appName) — \(windowTitle)"
    }
}

/// A `CGRect` that survives a round trip through JSON.
struct CodableRect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct SlotBinding: Codable, Equatable {
    var slot: Int
    var bundleID: String
    var windowIndex: Int         // position in the app's AX window list at bind time
    var appName: String
    var windowTitle: String      // display, and a last-resort matching key
    var reopenURL: String?       // URL to reopen the window if the app/window is gone
    var windowID: UInt32?        // preferred matching key while the window lives
    var documentPath: String?    // file the window represents, if any
    var savedFrame: CodableRect? // AX-space frame to restore on focus; nil = leave alone

    init(
        slot: Int,
        bundleID: String,
        windowIndex: Int,
        appName: String,
        windowTitle: String,
        reopenURL: String? = nil,
        windowID: UInt32? = nil,
        documentPath: String? = nil,
        savedFrame: CodableRect? = nil
    ) {
        self.slot = slot
        self.bundleID = bundleID
        self.windowIndex = windowIndex
        self.appName = appName
        self.windowTitle = windowTitle
        self.reopenURL = reopenURL
        self.windowID = windowID
        self.documentPath = documentPath
        self.savedFrame = savedFrame
    }

    init(slot: Int, info: WindowInfo, reopenURL: String?, savedFrame: CodableRect? = nil) {
        self.init(
            slot: slot,
            bundleID: info.bundleID,
            windowIndex: info.windowIndex,
            appName: info.appName,
            windowTitle: info.windowTitle,
            reopenURL: reopenURL,
            windowID: info.windowID,
            documentPath: info.documentPath,
            savedFrame: savedFrame
        )
    }

    var displayLabel: String {
        "\(appName) — \(windowTitle)"
    }
}
