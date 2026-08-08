import CoreGraphics
import Foundation
import Testing
@testable import ScreenManagerCore

/// A throwaway Application Support directory, so tests never touch the real one.
private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenManagerTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeBinding(slot: Int, app: String = "Ghostty", title: String = "zsh") -> SlotBinding {
    SlotBinding(
        slot: slot,
        bundleID: "com.mitchellh.ghostty",
        windowIndex: 0,
        appName: app,
        windowTitle: title
    )
}

@Suite("Binding file decoding")
struct BindingFileTests {

    @Test func migratesTheLegacyFlatArrayIntoADefaultProfile() throws {
        let legacy = """
        [{"slot":1,"bundleID":"com.microsoft.VSCode","windowIndex":2,\
        "appName":"Code","windowTitle":"api — Visual Studio Code"}]
        """
        let file = try #require(BindingFile.decode(from: Data(legacy.utf8)))

        #expect(file.activeProfile == "Default")
        #expect(file.profiles.count == 1)
        #expect(file.profiles["Default"]?.count == 1)
        #expect(file.profiles["Default"]?.first?.windowIndex == 2)
    }

    @Test func legacyBindingsGetNilValuesForTheNewFields() throws {
        let legacy = """
        [{"slot":1,"bundleID":"com.apple.Safari","windowIndex":0,\
        "appName":"Safari","windowTitle":"Start Page"}]
        """
        let file = try #require(BindingFile.decode(from: Data(legacy.utf8)))
        let binding = try #require(file.profiles["Default"]?.first)

        #expect(binding.windowID == nil)
        #expect(binding.documentPath == nil)
        #expect(binding.savedFrame == nil)
    }

    @Test func roundTripsTheCurrentFormat() throws {
        let original = BindingFile(
            activeProfile: "Desk",
            profiles: ["Desk": [makeBinding(slot: 1)], "Laptop": []]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try #require(BindingFile.decode(from: data))

        #expect(decoded == original)
    }

    @Test func savedFramesSurviveTheRoundTrip() throws {
        var binding = makeBinding(slot: 3)
        binding.savedFrame = CodableRect(CGRect(x: 12, y: 34, width: 560, height: 780))
        let data = try JSONEncoder().encode(BindingFile(activeProfile: "Default", profiles: ["Default": [binding]]))
        let decoded = try #require(BindingFile.decode(from: data))

        #expect(decoded.profiles["Default"]?.first?.savedFrame?.cgRect
            == CGRect(x: 12, y: 34, width: 560, height: 780))
    }

    @Test func garbageDecodesToNilRatherThanCrashing() {
        #expect(BindingFile.decode(from: Data("not json".utf8)) == nil)
    }

    @Test func normalizeRepairsAMissingActiveProfile() {
        let broken = BindingFile(activeProfile: "Ghost", profiles: ["Real": []])

        #expect(broken.normalized().activeProfile == "Real")
    }

    @Test func normalizeRepairsAnEmptyProfileSet() {
        let empty = BindingFile(activeProfile: "Ghost", profiles: [:])
        let fixed = empty.normalized()

        #expect(fixed.profiles["Default"] != nil)
        #expect(fixed.activeProfile == "Default")
    }
}

@Suite("Binding store")
struct BindingStoreTests {

    @Test func setAndReadBackASlot() {
        let store = BindingStore(directory: temporaryDirectory())
        store.set(makeBinding(slot: 4))

        #expect(store.binding(forSlot: 4)?.appName == "Ghostty")
        #expect(store.binding(forSlot: 5) == nil)
    }

    @Test func rebindingASlotReplacesRatherThanAppends() {
        let store = BindingStore(directory: temporaryDirectory())
        store.set(makeBinding(slot: 1, app: "Safari"))
        store.set(makeBinding(slot: 1, app: "Ghostty"))

        #expect(store.bindings.count == 1)
        #expect(store.binding(forSlot: 1)?.appName == "Ghostty")
    }

    @Test func bindingsStaySortedBySlot() {
        let store = BindingStore(directory: temporaryDirectory())
        store.set(makeBinding(slot: 7))
        store.set(makeBinding(slot: 2))
        store.set(makeBinding(slot: 5))

        #expect(store.bindings.map(\.slot) == [2, 5, 7])
    }

    @Test func removeClearsOnlyTheNamedSlot() {
        let store = BindingStore(directory: temporaryDirectory())
        store.set(makeBinding(slot: 1))
        store.set(makeBinding(slot: 2))
        store.remove(slot: 1)

        #expect(store.binding(forSlot: 1) == nil)
        #expect(store.binding(forSlot: 2) != nil)
    }

    @Test func bindingsPersistAcrossInstances() {
        let directory = temporaryDirectory()
        let first = BindingStore(directory: directory)
        first.set(makeBinding(slot: 3, app: "Xcode"))

        let second = BindingStore(directory: directory)

        #expect(second.binding(forSlot: 3)?.appName == "Xcode")
    }

    @Test func savingAFrameLeavesTheRestOfTheBindingAlone() {
        let store = BindingStore(directory: temporaryDirectory())
        store.set(makeBinding(slot: 1, app: "Notes"))
        store.saveFrame(CodableRect(CGRect(x: 5, y: 6, width: 700, height: 500)), forSlot: 1)

        #expect(store.binding(forSlot: 1)?.appName == "Notes")
        #expect(store.binding(forSlot: 1)?.savedFrame?.cgRect.width == 700)
    }

    @Test func savingAFrameForAnEmptySlotIsANoOp() {
        let store = BindingStore(directory: temporaryDirectory())
        store.saveFrame(CodableRect(.zero), forSlot: 9)

        #expect(store.bindings.isEmpty)
    }

    @Test func clearingAFramePassesNil() {
        let store = BindingStore(directory: temporaryDirectory())
        store.set(makeBinding(slot: 1))
        store.saveFrame(CodableRect(CGRect(x: 0, y: 0, width: 10, height: 10)), forSlot: 1)
        store.saveFrame(nil, forSlot: 1)

        #expect(store.binding(forSlot: 1)?.savedFrame == nil)
    }
}

@Suite("Profiles")
struct ProfileTests {

    @Test func aFreshStoreHasOneDefaultProfile() {
        let store = BindingStore(directory: temporaryDirectory())

        #expect(store.profileNames == ["Default"])
        #expect(store.activeProfile == "Default")
    }

    @Test func duplicatingCopiesBindingsAndSwitchesToTheCopy() {
        let store = BindingStore(directory: temporaryDirectory())
        store.set(makeBinding(slot: 1))
        store.saveProfile(as: "Desk")

        #expect(store.activeProfile == "Desk")
        #expect(store.binding(forSlot: 1) != nil)
        #expect(store.profileNames == ["Default", "Desk"])
    }

    @Test func profilesHoldIndependentBindings() {
        let store = BindingStore(directory: temporaryDirectory())
        store.set(makeBinding(slot: 1, app: "Safari"))
        store.createEmptyProfile(named: "Laptop")

        #expect(store.bindings.isEmpty)

        store.set(makeBinding(slot: 1, app: "Xcode"))
        store.switchProfile(to: "Default")

        #expect(store.binding(forSlot: 1)?.appName == "Safari")

        store.switchProfile(to: "Laptop")

        #expect(store.binding(forSlot: 1)?.appName == "Xcode")
    }

    @Test func switchingToAnUnknownProfileIsIgnored() {
        let store = BindingStore(directory: temporaryDirectory())
        store.switchProfile(to: "Nope")

        #expect(store.activeProfile == "Default")
    }

    @Test func creatingADuplicateNameDoesNotWipeTheExistingProfile() {
        let store = BindingStore(directory: temporaryDirectory())
        store.set(makeBinding(slot: 1))
        store.createEmptyProfile(named: "Default")

        #expect(store.binding(forSlot: 1) != nil)
    }

    @Test func blankNamesAreRejected() {
        let store = BindingStore(directory: temporaryDirectory())
        store.createEmptyProfile(named: "   ")
        store.saveProfile(as: "")

        #expect(store.profileNames == ["Default"])
    }

    @Test func namesAreTrimmed() {
        let store = BindingStore(directory: temporaryDirectory())
        store.createEmptyProfile(named: "  Desk  ")

        #expect(store.profileNames.contains("Desk"))
    }

    @Test func deletingTheActiveProfileMovesToAnother() {
        let store = BindingStore(directory: temporaryDirectory())
        store.createEmptyProfile(named: "Laptop")
        store.deleteProfile(named: "Laptop")

        #expect(store.profileNames == ["Default"])
        #expect(store.activeProfile == "Default")
    }

    @Test func theLastProfileCannotBeDeleted() {
        let store = BindingStore(directory: temporaryDirectory())
        store.deleteProfile(named: "Default")

        #expect(store.profileNames == ["Default"])
    }

    @Test func theActiveProfileSurvivesARestart() {
        let directory = temporaryDirectory()
        let first = BindingStore(directory: directory)
        first.createEmptyProfile(named: "Desk")
        first.set(makeBinding(slot: 2, app: "Mail"))

        let second = BindingStore(directory: directory)

        #expect(second.activeProfile == "Desk")
        #expect(second.binding(forSlot: 2)?.appName == "Mail")
    }
}
