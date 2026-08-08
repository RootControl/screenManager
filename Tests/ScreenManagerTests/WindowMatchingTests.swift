import CoreGraphics
import Foundation
import Testing
@testable import ScreenManagerCore

@Suite("Window search")
struct WindowFilterTests {

    @Test func anEmptyQueryMatchesEverything() {
        #expect(WindowFilter.matches(appName: "Safari", title: "Start Page", query: ""))
        #expect(WindowFilter.matches(appName: "Safari", title: "Start Page", query: "   "))
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(WindowFilter.matches(appName: "Safari", title: "Start Page", query: "SAFARI"))
        #expect(WindowFilter.matches(appName: "Safari", title: "Start Page", query: "start"))
    }

    @Test func matchesOnAppNameOrTitle() {
        #expect(WindowFilter.matches(appName: "Code", title: "screenManager", query: "screen"))
        #expect(!WindowFilter.matches(appName: "Code", title: "screenManager", query: "safari"))
    }

    @Test func everyTermMustMatch() {
        #expect(WindowFilter.matches(appName: "Code", title: "screenManager", query: "code screen"))
        #expect(!WindowFilter.matches(appName: "Code", title: "screenManager", query: "code safari"))
    }

    @Test func termOrderDoesNotMatter() {
        #expect(WindowFilter.matches(appName: "Code", title: "screenManager", query: "screen code"))
    }

    @Test func substringsMatchMidWord() {
        #expect(WindowFilter.matches(appName: "Visual Studio Code", title: "main.swift", query: "swift"))
    }
}

@Suite("VS Code window titles")
struct VSCodeTitleTests {

    @Test func extractsTheProjectFromAFullTitle() {
        #expect(WindowManager.vscodeProjectName(from: "main.swift — screenManager — Visual Studio Code")
            == "screenManager")
    }

    @Test func handlesATitleWithoutTheTrailingAppName() {
        #expect(WindowManager.vscodeProjectName(from: "main.swift — screenManager") == "screenManager")
    }

    @Test func aTitleWithNoSeparatorHasNoProject() {
        #expect(WindowManager.vscodeProjectName(from: "Welcome") == nil)
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(WindowManager.vscodeProjectName(from: "file.ts —  api  — Visual Studio Code") == "api")
    }

    @Test func aDirtyEditorMarkerDoesNotLeakIntoTheProjectName() {
        #expect(WindowManager.vscodeProjectName(from: "● main.swift — screenManager — Visual Studio Code")
            == "screenManager")
    }

    @Test func anEmptyProjectSegmentIsRejected() {
        #expect(WindowManager.vscodeProjectName(from: "file.ts —  — Visual Studio Code") == nil)
    }
}

@Suite("VS Code history lookup")
struct VSCodeHistoryTests {
    private let history = """
    {"entries":[
      {"folderUri":"file:///Users/dev/projects/twitch"},
      {"folderUri":"file:///Users/dev/projects/screenManager"},
      {"fileUri":"file:///Users/dev/notes.md"}
    ]}
    """

    @Test func findsTheFolderMatchingTheProjectName() {
        #expect(WindowManager.vscodeFolderPath(inHistoryJSON: history, projectName: "screenManager")
            == "/Users/dev/projects/screenManager")
    }

    @Test func returnsNilForAnUnknownProject() {
        #expect(WindowManager.vscodeFolderPath(inHistoryJSON: history, projectName: "nope") == nil)
    }

    @Test func ignoresFileEntriesThatHaveNoFolder() {
        #expect(WindowManager.vscodeFolderPath(inHistoryJSON: history, projectName: "notes.md") == nil)
    }

    @Test func malformedJSONReturnsNil() {
        #expect(WindowManager.vscodeFolderPath(inHistoryJSON: "", projectName: "x") == nil)
        #expect(WindowManager.vscodeFolderPath(inHistoryJSON: "{}", projectName: "x") == nil)
    }
}

@Suite("Reopen URLs")
struct ReopenURLTests {

    @Test func acceptsAFileURLString() {
        #expect(WindowManager.fileURL(from: "file:///Users/dev/notes.md")?.path == "/Users/dev/notes.md")
    }

    @Test func acceptsABarePath() {
        #expect(WindowManager.fileURL(from: "/Users/dev/notes.md")?.path == "/Users/dev/notes.md")
    }

    @Test func rejectsAnythingElse() {
        #expect(WindowManager.fileURL(from: "vscode://file/Users/dev") == nil)
        #expect(WindowManager.fileURL(from: "") == nil)
    }
}

@Suite("Slot bindings")
struct SlotBindingTests {

    @Test func displayLabelJoinsAppAndTitle() {
        let binding = SlotBinding(
            slot: 1,
            bundleID: "com.apple.Safari",
            windowIndex: 0,
            appName: "Safari",
            windowTitle: "Start Page"
        )

        #expect(binding.displayLabel == "Safari — Start Page")
    }

    @Test func codableRectSurvivesAJSONRoundTrip() throws {
        let rect = CGRect(x: 1.5, y: -2.5, width: 300, height: 200)
        let decoded = try JSONDecoder().decode(CodableRect.self, from: JSONEncoder().encode(CodableRect(rect)))

        #expect(decoded.cgRect == rect)
    }
}
