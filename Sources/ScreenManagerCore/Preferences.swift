import AppKit
import Carbon

/// A set of modifier keys, expressible as both a Carbon hotkey mask and an
/// `NSEvent.ModifierFlags` for menu display.
struct ModifierCombo: Codable, Equatable, Hashable {
    var control: Bool = false
    var option: Bool = false
    var shift: Bool = false
    var command: Bool = false

    static let option = ModifierCombo(option: true)
    static let controlOption = ModifierCombo(control: true, option: true)
    static let commandOption = ModifierCombo(option: true, command: true)
    static let controlCommand = ModifierCombo(control: true, command: true)
    static let controlOptionCommand = ModifierCombo(control: true, option: true, command: true)
    static let controlOptionShift = ModifierCombo(control: true, option: true, shift: true)
    static let commandOptionShift = ModifierCombo(option: true, shift: true, command: true)

    var carbonMask: UInt32 {
        var mask: UInt32 = 0
        if control { mask |= UInt32(controlKey) }
        if option { mask |= UInt32(optionKey) }
        if shift { mask |= UInt32(shiftKey) }
        if command { mask |= UInt32(cmdKey) }
        return mask
    }

    var nsMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if control { flags.insert(.control) }
        if option { flags.insert(.option) }
        if shift { flags.insert(.shift) }
        if command { flags.insert(.command) }
        return flags
    }

    /// Symbols in the order macOS displays them: ⌃⌥⇧⌘.
    var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s
    }

    var isEmpty: Bool { !control && !option && !shift && !command }

    func adding(shift wantsShift: Bool) -> ModifierCombo {
        var copy = self
        copy.shift = copy.shift || wantsShift
        return copy
    }
}

struct Preferences: Codable, Equatable {
    /// ⌥N by default — focus the window bound to slot N.
    var focusModifiers: ModifierCombo = .option
    /// ⌃⌥ + arrows/UIJK — snap the focused window within its screen.
    var layoutModifiers: ModifierCombo = .controlOption
    /// ⌃⌥⌘ + arrows/N — move the focused window between displays.
    var displayModifiers: ModifierCombo = .controlOptionCommand
    /// Number of slots exposed in the menu and bound to hotkeys.
    var slotCount: Int = 9
    /// Pressing a slot's hotkey while already on it returns to the previous window.
    var toggleBackEnabled: Bool = true
    /// Focusing a slot also restores the frame saved with it.
    var restoreFramesOnFocus: Bool = true

    /// Binding is always the focus combo plus Shift, so the two can never collide.
    var bindModifiers: ModifierCombo { focusModifiers.adding(shift: true) }

    var clampedSlotCount: Int { min(max(slotCount, 1), 9) }

    static let focusPresets: [ModifierCombo] = [.option, .controlOption, .commandOption, .controlCommand]
    static let layoutPresets: [ModifierCombo] = [.controlOption, .controlCommand, .controlOptionShift, .commandOptionShift]
    static let displayPresets: [ModifierCombo] = [.controlOptionCommand, .controlOptionShift, .commandOptionShift, .controlCommand]
}

final class PreferencesStore {
    private(set) var preferences: Preferences
    private let fileURL: URL

    init(directory: URL = AppPaths.supportDirectory) {
        fileURL = directory.appendingPathComponent("preferences.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = Preferences()
        }
    }

    func mutate(_ body: (inout Preferences) -> Void) {
        body(&preferences)
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(preferences) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum AppPaths {
    /// ~/Library/Application Support/ScreenManager, created on first access.
    static var supportDirectory: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("ScreenManager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
