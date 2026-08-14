import CoreGraphics
import Foundation
import Testing
@testable import ScreenManagerCore

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenManagerArrangements-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeSnapshot(app: String = "Safari", title: String = "Start Page") -> WindowSnapshot {
    WindowSnapshot(
        bundleID: "com.apple.\(app)",
        appName: app,
        windowTitle: title,
        windowIndex: 0,
        windowID: 42,
        documentPath: nil,
        frame: CodableRect(CGRect(x: 10, y: 20, width: 800, height: 600))
    )
}

@Suite("Arrangement store")
struct ArrangementStoreTests {

    @Test func savesAndReadsBackAnArrangement() {
        let store = ArrangementStore(directory: temporaryDirectory())
        store.save([makeSnapshot()], as: "Writing")

        #expect(store.names == ["Writing"])
        #expect(store.arrangement(named: "Writing")?.snapshots.count == 1)
    }

    @Test func savingTheSameNameReplacesRatherThanDuplicates() {
        let store = ArrangementStore(directory: temporaryDirectory())
        store.save([makeSnapshot()], as: "Writing")
        store.save([makeSnapshot(), makeSnapshot(app: "Mail")], as: "Writing")

        #expect(store.names == ["Writing"])
        #expect(store.arrangement(named: "Writing")?.snapshots.count == 2)
    }

    @Test func namesAreTrimmedAndBlanksRejected() {
        let store = ArrangementStore(directory: temporaryDirectory())
        store.save([makeSnapshot()], as: "  Writing  ")
        store.save([makeSnapshot()], as: "   ")

        #expect(store.names == ["Writing"])
    }

    @Test func anEmptyCaptureIsNotSaved() {
        let store = ArrangementStore(directory: temporaryDirectory())
        store.save([], as: "Nothing")

        #expect(store.names.isEmpty)
    }

    @Test func arrangementsStaySortedByName() {
        let store = ArrangementStore(directory: temporaryDirectory())
        store.save([makeSnapshot()], as: "Writing")
        store.save([makeSnapshot()], as: "Coding")
        store.save([makeSnapshot()], as: "Meetings")

        #expect(store.names == ["Coding", "Meetings", "Writing"])
    }

    @Test func deletingRemovesOnlyTheNamedArrangement() {
        let store = ArrangementStore(directory: temporaryDirectory())
        store.save([makeSnapshot()], as: "Writing")
        store.save([makeSnapshot()], as: "Coding")
        store.delete(named: "Writing")

        #expect(store.names == ["Coding"])
    }

    @Test func arrangementsPersistAcrossInstances() {
        let directory = temporaryDirectory()
        let first = ArrangementStore(directory: directory)
        first.save([makeSnapshot(app: "Xcode")], as: "Coding")

        let second = ArrangementStore(directory: directory)

        #expect(second.arrangement(named: "Coding")?.snapshots.first?.appName == "Xcode")
    }

    @Test func framesSurviveTheRoundTrip() {
        let directory = temporaryDirectory()
        ArrangementStore(directory: directory).save([makeSnapshot()], as: "Coding")

        let reloaded = ArrangementStore(directory: directory)

        #expect(reloaded.arrangement(named: "Coding")?.snapshots.first?.frame.cgRect
            == CGRect(x: 10, y: 20, width: 800, height: 600))
    }

    @Test func anUnknownNameReturnsNil() {
        let store = ArrangementStore(directory: temporaryDirectory())

        #expect(store.arrangement(named: "Nope") == nil)
    }
}

@Suite("Window queries")
struct WindowQueryTests {

    @Test func aSnapshotCarriesItsIdentityIntoTheQuery() {
        let query = makeSnapshot().query

        #expect(query.bundleID == "com.apple.Safari")
        #expect(query.windowID == 42)
        #expect(query.windowTitle == "Start Page")
    }

    @Test func aBindingCarriesItsIdentityIntoTheQuery() {
        var binding = SlotBinding(
            slot: 1,
            bundleID: "com.microsoft.VSCode",
            windowIndex: 3,
            appName: "Code",
            windowTitle: "api — Visual Studio Code"
        )
        binding.windowID = 7
        binding.documentPath = "/tmp/x"

        let query = binding.query

        #expect(query.bundleID == "com.microsoft.VSCode")
        #expect(query.windowID == 7)
        #expect(query.documentPath == "/tmp/x")
        #expect(query.windowIndex == 3)
    }
}

@Suite("Preference migration")
struct PreferenceMigrationTests {

    @Test func anUnknownFieldDoesNotResetTheOthers() throws {
        // A file written by a newer build, decoded by this one.
        let json = """
        {"slotCount":4,"someFutureSetting":true}
        """
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))

        #expect(decoded.slotCount == 4)
        #expect(decoded.focusModifiers == .option)
    }

    @Test func aMissingFieldFallsBackToItsDefaultRatherThanFailing() throws {
        let json = """
        {"focusModifiers":{"control":true,"option":false,"shift":false,"command":true}}
        """
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))

        #expect(decoded.focusModifiers == .controlCommand)
        #expect(decoded.slotCount == 9)
        #expect(decoded.restoreFramesOnFocus)
    }

    @Test func theLegacyToggleBackFlagBecomesARepeatBehaviour() throws {
        let on = try JSONDecoder().decode(Preferences.self, from: Data(#"{"toggleBackEnabled":true}"#.utf8))
        let off = try JSONDecoder().decode(Preferences.self, from: Data(#"{"toggleBackEnabled":false}"#.utf8))

        #expect(on.repeatPress == .goBack)
        #expect(off.repeatPress == .doNothing)
    }

    @Test func anExplicitRepeatBehaviourWinsOverTheLegacyFlag() throws {
        let json = #"{"toggleBackEnabled":false,"repeatPress":"cycleWindows"}"#
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))

        #expect(decoded.repeatPress == .cycleWindows)
    }

    @Test func survivesAFullRoundTrip() throws {
        var original = Preferences()
        original.spaceModifiers = .commandOptionShift
        original.excludedBundleIDs = ["com.apple.finder"]
        original.profileByFingerprint = ["1512x982@0,0": "Laptop"]
        original.dragToEdgeSnapping = true

        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(original))

        #expect(decoded == original)
    }
}
