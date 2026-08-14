import AppKit

/// Access to macOS Spaces (virtual desktops).
///
/// There is no public API for this, so the SkyLight functions are looked up at
/// runtime with `dlsym` rather than linked against. If Apple renames or removes
/// them, `isAvailable` simply goes false and the Spaces features hide
/// themselves — the app still launches and everything else keeps working.
enum SpacesBridge {

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias MoveWindowsToManagedSpace = @convention(c) (Int32, CFArray, UInt64) -> Void

    private struct Symbols {
        let connection: Int32
        let copySpaces: CopyManagedDisplaySpaces
        let moveWindows: MoveWindowsToManagedSpace
    }

    private static let symbols: Symbols? = loadSymbols()

    private static func loadSymbols() -> Symbols? {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }

        func lookup(_ name: String) -> UnsafeMutableRawPointer? {
            dlsym(handle, name)
        }

        // SLS* is the modern spelling; CGS* is the older alias.
        guard let mainConnection = lookup("SLSMainConnectionID") ?? lookup("_CGSDefaultConnection"),
              let copy = lookup("SLSCopyManagedDisplaySpaces") ?? lookup("CGSCopyManagedDisplaySpaces"),
              let move = lookup("SLSMoveWindowsToManagedSpace") ?? lookup("CGSMoveWindowsToManagedSpace")
        else { return nil }

        let connectionID = unsafeBitCast(mainConnection, to: MainConnectionID.self)()
        guard connectionID != 0 else { return nil }

        return Symbols(
            connection: connectionID,
            copySpaces: unsafeBitCast(copy, to: CopyManagedDisplaySpaces.self),
            moveWindows: unsafeBitCast(move, to: MoveWindowsToManagedSpace.self)
        )
    }

    static var isAvailable: Bool { symbols != nil }

    /// User-facing Spaces in display order, excluding fullscreen Spaces (which
    /// cannot receive a moved window).
    static func userSpaceIDs() -> [UInt64] {
        guard let symbols,
              let displays = symbols.copySpaces(symbols.connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        var ids: [UInt64] = []
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                // type 0 is a normal user Space; 4 is a fullscreen app.
                let type = (space["type"] as? Int) ?? 0
                guard type == 0, let id = space["id64"] as? UInt64 else { continue }
                ids.append(id)
            }
        }
        return ids
    }

    static var spaceCount: Int { userSpaceIDs().count }

    /// Sends a window to the Space at `index` (0-based). Returns false when
    /// Spaces are unavailable or the index does not exist.
    @discardableResult
    static func move(windowID: CGWindowID, toSpaceIndex index: Int) -> Bool {
        guard let symbols else { return false }
        let spaces = userSpaceIDs()
        guard index >= 0, index < spaces.count else { return false }

        symbols.moveWindows(symbols.connection, [windowID] as CFArray, spaces[index])
        return true
    }
}
