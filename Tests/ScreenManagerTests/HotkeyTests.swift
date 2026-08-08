import Carbon
import Foundation
import Testing
@testable import ScreenManagerCore

@Suite("Hotkey action encoding")
struct HotkeyActionTests {

    /// Every action the app can trigger, so the ID partitioning is exercised end to end.
    private static let allActions: [HotkeyAction] =
        (1...9).map { HotkeyAction.focus(slot: $0) }
        + (1...9).map { HotkeyAction.bind(slot: $0) }
        + (0..<9).map { HotkeyAction.moveToDisplay(index: $0) }
        + LayoutPosition.allCases.map { HotkeyAction.layout($0) }
        + [.cycleDisplay(delta: -1), .cycleDisplay(delta: 1)]

    @Test func everyActionSurvivesAnIDRoundTrip() {
        for action in Self.allActions {
            #expect(HotkeyAction.from(id: action.id) == action, "\(action) did not round-trip")
        }
    }

    @Test func idsAreUniqueAcrossActionKinds() {
        let ids = Self.allActions.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test func unknownIdsDecodeToNil() {
        #expect(HotkeyAction.from(id: 0) == nil)
        #expect(HotkeyAction.from(id: 200) == nil)
    }

    @Test func focusAndBindShareTheSlotButNotTheID() {
        #expect(HotkeyAction.focus(slot: 3).id != HotkeyAction.bind(slot: 3).id)
        #expect(HotkeyAction.from(id: HotkeyAction.focus(slot: 3).id) == .focus(slot: 3))
        #expect(HotkeyAction.from(id: HotkeyAction.bind(slot: 3).id) == .bind(slot: 3))
    }
}

@Suite("Hotkey plan")
struct HotkeyPlanTests {

    @Test func noTwoHotkeysClaimTheSameChord() {
        let specs = HotkeyPlan.specs(for: Preferences())
        let chords = specs.map { "\($0.keyCode)-\($0.modifiers.carbonMask)" }

        #expect(Set(chords).count == chords.count, "default preferences register a colliding chord")
    }

    @Test func idsAreUnique() {
        let ids = HotkeyPlan.specs(for: Preferences()).map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test func everySpecDecodesBackToAnAction() {
        for spec in HotkeyPlan.specs(for: Preferences()) {
            #expect(HotkeyAction.from(id: spec.id) != nil, "orphan hotkey ID \(spec.id)")
        }
    }

    @Test func slotCountControlsHowManySlotHotkeysExist() {
        var preferences = Preferences()
        preferences.slotCount = 3
        let specs = HotkeyPlan.specs(for: preferences)

        let focusCount = specs.compactMap { HotkeyAction.from(id: $0.id) }.filter {
            if case .focus = $0 { return true }
            return false
        }.count

        #expect(focusCount == 3)
    }

    @Test func layoutShortcutsExistRegardlessOfSlotCount() {
        var preferences = Preferences()
        preferences.slotCount = 1
        let specs = HotkeyPlan.specs(for: preferences)

        let layoutCount = specs.compactMap { HotkeyAction.from(id: $0.id) }.filter {
            if case .layout = $0 { return true }
            return false
        }.count

        #expect(layoutCount == HotkeyPlan.layoutKeys.count)
    }

    @Test func aSlotCountOutOfRangeIsClamped() {
        var preferences = Preferences()
        preferences.slotCount = 42

        #expect(preferences.clampedSlotCount == 9)
        #expect(!HotkeyPlan.specs(for: preferences).isEmpty)

        preferences.slotCount = 0

        #expect(preferences.clampedSlotCount == 1)
    }

    @Test func changingTheFocusModifierMovesTheBindModifierWithIt() {
        var preferences = Preferences()
        preferences.focusModifiers = .controlOption
        let specs = HotkeyPlan.specs(for: preferences)

        let focus = specs.first { HotkeyAction.from(id: $0.id) == .focus(slot: 1) }
        let bind = specs.first { HotkeyAction.from(id: $0.id) == .bind(slot: 1) }

        #expect(focus?.modifiers == .controlOption)
        #expect(bind?.modifiers == ModifierCombo(control: true, option: true, shift: true))
        #expect(focus?.keyCode == bind?.keyCode)
    }

    @Test func labelsNameTheChordSoConflictsAreReadable() {
        let specs = HotkeyPlan.specs(for: Preferences())
        let focus = specs.first { HotkeyAction.from(id: $0.id) == .focus(slot: 1) }

        #expect(focus?.label.contains("⌥1") == true)
    }
}

@Suite("Modifier combos")
struct ModifierComboTests {

    @Test func carbonMaskMatchesTheCarbonConstants() {
        #expect(ModifierCombo.option.carbonMask == UInt32(optionKey))
        #expect(ModifierCombo.controlOption.carbonMask == UInt32(controlKey) | UInt32(optionKey))
        #expect(ModifierCombo().carbonMask == 0)
    }

    @Test func displayUsesTheStandardSymbolOrder() {
        #expect(ModifierCombo.option.display == "⌥")
        #expect(ModifierCombo.controlOption.display == "⌃⌥")
        #expect(ModifierCombo.controlOptionCommand.display == "⌃⌥⌘")
        #expect(ModifierCombo(control: true, option: true, shift: true, command: true).display == "⌃⌥⇧⌘")
    }

    @Test func addingShiftIsIdempotent() {
        let once = ModifierCombo.option.adding(shift: true)

        #expect(once == ModifierCombo(option: true, shift: true))
        #expect(once.adding(shift: true) == once)
    }

    @Test func addingShiftFalseChangesNothing() {
        #expect(ModifierCombo.controlOption.adding(shift: false) == .controlOption)
    }

    @Test func bindIsAlwaysDistinctFromFocus() {
        for preset in Preferences.focusPresets {
            var preferences = Preferences()
            preferences.focusModifiers = preset

            #expect(preferences.bindModifiers != preferences.focusModifiers)
        }
    }

    @Test func survivesJSON() throws {
        let combo = ModifierCombo.controlOptionCommand
        let decoded = try JSONDecoder().decode(ModifierCombo.self, from: JSONEncoder().encode(combo))

        #expect(decoded == combo)
    }
}

@Suite("Digit key codes")
struct KeyCodeTests {

    @Test func everySlotHasADigitKey() {
        for slot in 1...9 {
            #expect(KeyCode.digits[slot] != nil)
        }
    }

    @Test func digitKeyCodesAreDistinct() {
        let codes = (1...9).compactMap { KeyCode.digits[$0] }

        #expect(Set(codes).count == 9)
    }

    @Test func sixAndFiveAreNotInNumericOrder() {
        // The ANSI layout puts 6 below 5; a sequential mapping would be wrong.
        #expect(KeyCode.digits[5] == 0x17)
        #expect(KeyCode.digits[6] == 0x16)
    }
}

@Suite("Preferences")
struct PreferencesTests {

    @Test func defaultsMatchTheDocumentedShortcuts() {
        let preferences = Preferences()

        #expect(preferences.focusModifiers == .option)
        #expect(preferences.bindModifiers.display == "⌥⇧")
        #expect(preferences.layoutModifiers == .controlOption)
        #expect(preferences.displayModifiers == .controlOptionCommand)
        #expect(preferences.slotCount == 9)
        #expect(preferences.toggleBackEnabled)
        #expect(preferences.restoreFramesOnFocus)
    }

    @Test func persistAcrossInstances() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenManagerPrefs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let first = PreferencesStore(directory: directory)
        first.mutate {
            $0.focusModifiers = .controlCommand
            $0.slotCount = 4
            $0.toggleBackEnabled = false
        }

        let second = PreferencesStore(directory: directory)

        #expect(second.preferences.focusModifiers == .controlCommand)
        #expect(second.preferences.slotCount == 4)
        #expect(!second.preferences.toggleBackEnabled)
    }

    @Test func aMissingFileYieldsDefaults() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenManagerPrefs-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        #expect(PreferencesStore(directory: directory).preferences == Preferences())
    }
}
