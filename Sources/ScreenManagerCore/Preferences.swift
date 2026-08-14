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
    static let controlCommandShift = ModifierCombo(control: true, shift: true, command: true)

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

/// What pressing a slot's hotkey does when you are already on that window.
enum RepeatPressBehavior: String, Codable, CaseIterable {
    case goBack
    case cycleWindows
    case doNothing

    var title: String {
        switch self {
        case .goBack: return "Return to Previous Window"
        case .cycleWindows: return "Cycle the App's Windows"
        case .doNothing: return "Do Nothing"
        }
    }
}

struct Preferences: Codable, Equatable {
    /// ⌥N by default — focus the window bound to slot N.
    var focusModifiers: ModifierCombo = .option
    /// ⌃⌥ + arrows/UIJK — snap the focused window within its screen.
    var layoutModifiers: ModifierCombo = .controlOption
    /// ⌃⌥⌘ + arrows/N — move the focused window between displays.
    var displayModifiers: ModifierCombo = .controlOptionCommand
    /// ⌃⌥⇧ + N — move the focused window between Spaces.
    var spaceModifiers: ModifierCombo = .controlOptionShift
    /// Number of slots exposed in the menu and bound to hotkeys.
    var slotCount: Int = 9
    /// What a second press of the same slot hotkey does.
    var repeatPress: RepeatPressBehavior = .goBack
    /// Focusing a slot also restores the frame saved with it.
    var restoreFramesOnFocus: Bool = true
    /// Switch profiles automatically when the display arrangement changes.
    var autoSwitchProfiles: Bool = true
    /// Display-arrangement fingerprint → profile name.
    var profileByFingerprint: [String: String] = [:]
    /// Apps hidden from the window picker.
    var excludedBundleIDs: [String] = []
    /// Snap a window by dragging it to a screen edge.
    var dragToEdgeSnapping: Bool = false
    /// Show the slot overview while the focus modifier is held down.
    var slotHUDEnabled: Bool = false

    /// Binding is always the focus combo plus Shift, so the two can never collide.
    var bindModifiers: ModifierCombo { focusModifiers.adding(shift: true) }

    var clampedSlotCount: Int { min(max(slotCount, 1), 9) }

    static let focusPresets: [ModifierCombo] = [.option, .controlOption, .commandOption, .controlCommand]
    static let layoutPresets: [ModifierCombo] = [.controlOption, .controlCommand, .controlOptionShift, .commandOptionShift]
    static let displayPresets: [ModifierCombo] = [.controlOptionCommand, .controlOptionShift, .commandOptionShift, .controlCommand]
    static let spacePresets: [ModifierCombo] = [.controlOptionShift, .commandOptionShift, .controlCommandShift, .controlOptionCommand]

    init() {}

    /// Every field is decoded leniently so that adding a setting never
    /// invalidates an existing preferences file (which would silently reset
    /// every other setting back to its default).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()

        focusModifiers = try container.decodeIfPresent(ModifierCombo.self, forKey: .focusModifiers) ?? defaults.focusModifiers
        layoutModifiers = try container.decodeIfPresent(ModifierCombo.self, forKey: .layoutModifiers) ?? defaults.layoutModifiers
        displayModifiers = try container.decodeIfPresent(ModifierCombo.self, forKey: .displayModifiers) ?? defaults.displayModifiers
        spaceModifiers = try container.decodeIfPresent(ModifierCombo.self, forKey: .spaceModifiers) ?? defaults.spaceModifiers
        slotCount = try container.decodeIfPresent(Int.self, forKey: .slotCount) ?? defaults.slotCount
        restoreFramesOnFocus = try container.decodeIfPresent(Bool.self, forKey: .restoreFramesOnFocus) ?? defaults.restoreFramesOnFocus
        autoSwitchProfiles = try container.decodeIfPresent(Bool.self, forKey: .autoSwitchProfiles) ?? defaults.autoSwitchProfiles
        profileByFingerprint = try container.decodeIfPresent([String: String].self, forKey: .profileByFingerprint) ?? defaults.profileByFingerprint
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? defaults.excludedBundleIDs
        dragToEdgeSnapping = try container.decodeIfPresent(Bool.self, forKey: .dragToEdgeSnapping) ?? defaults.dragToEdgeSnapping
        slotHUDEnabled = try container.decodeIfPresent(Bool.self, forKey: .slotHUDEnabled) ?? defaults.slotHUDEnabled

        if let behavior = try container.decodeIfPresent(RepeatPressBehavior.self, forKey: .repeatPress) {
            repeatPress = behavior
        } else if let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            .decodeIfPresent(Bool.self, forKey: .toggleBackEnabled) {
            // Pre-1.1 files stored this as a plain on/off switch.
            repeatPress = legacy ? .goBack : .doNothing
        } else {
            repeatPress = defaults.repeatPress
        }
    }

    private enum CodingKeys: String, CodingKey {
        case focusModifiers, layoutModifiers, displayModifiers, spaceModifiers
        case slotCount, repeatPress, restoreFramesOnFocus
        case autoSwitchProfiles, profileByFingerprint, excludedBundleIDs
        case dragToEdgeSnapping, slotHUDEnabled
    }

    /// Keys that no longer map to a property, read only for migration.
    private enum LegacyKeys: String, CodingKey {
        case toggleBackEnabled
    }
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
