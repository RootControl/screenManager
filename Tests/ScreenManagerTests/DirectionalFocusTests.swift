import CoreGraphics
import Foundation
import Testing
@testable import ScreenManagerCore

/// A tiled 2×2 grid on a 1000×800 screen, in AX coordinates.
private let topLeft = CGRect(x: 0, y: 0, width: 500, height: 400)
private let topRight = CGRect(x: 500, y: 0, width: 500, height: 400)
private let bottomLeft = CGRect(x: 0, y: 400, width: 500, height: 400)
private let bottomRight = CGRect(x: 500, y: 400, width: 500, height: 400)

@Suite("Directional focus")
struct DirectionalFocusTests {

    @Test func movesAcrossAndBackAlongARow() {
        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: [topRight], direction: .right) == 0)
        #expect(LayoutCalculator.directionalTarget(from: topRight, candidates: [topLeft], direction: .left) == 0)
    }

    @Test func upMeansSmallerYInAXSpace() {
        #expect(LayoutCalculator.directionalTarget(from: bottomLeft, candidates: [topLeft], direction: .up) == 0)
        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: [bottomLeft], direction: .down) == 0)
    }

    @Test func nothingInThatDirectionYieldsNil() {
        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: [topRight], direction: .left) == nil)
        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: [bottomLeft], direction: .up) == nil)
    }

    @Test func anEmptyCandidateListYieldsNil() {
        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: [], direction: .right) == nil)
    }

    @Test func prefersTheWindowInTheSameRowOverACloserDiagonal() {
        // bottomRight is nearer by raw centre distance, but topRight shares the
        // row, and focus should travel along the row.
        let candidates = [bottomRight, topRight]

        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: candidates, direction: .right) == 1)
    }

    @Test func picksTheNearestOfSeveralInLine() {
        let near = CGRect(x: 520, y: 0, width: 200, height: 400)
        let far = CGRect(x: 900, y: 0, width: 100, height: 400)

        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: [far, near], direction: .right) == 1)
    }

    @Test func aWindowAtTheSamePositionIsNotATarget() {
        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: [topLeft], direction: .right) == nil)
    }

    @Test func reachesADiagonalWhenNothingSharesTheRow() {
        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: [bottomRight], direction: .right) == 0)
    }

    @Test func everyDirectionFindsItsNeighbourInAGrid() {
        let all = [topLeft, topRight, bottomLeft, bottomRight]

        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: all, direction: .right) == 1)
        #expect(LayoutCalculator.directionalTarget(from: topLeft, candidates: all, direction: .down) == 2)
        #expect(LayoutCalculator.directionalTarget(from: bottomRight, candidates: all, direction: .left) == 2)
        #expect(LayoutCalculator.directionalTarget(from: bottomRight, candidates: all, direction: .up) == 1)
    }
}

@Suite("Display fingerprint")
struct ScreenFingerprintTests {

    @Test func differsBetweenSetups() {
        let laptop = [CGRect(x: 0, y: 0, width: 1512, height: 982)]
        let docked = laptop + [CGRect(x: 1512, y: 0, width: 2560, height: 1440)]

        #expect(LayoutCalculator.screenFingerprint(laptop) != LayoutCalculator.screenFingerprint(docked))
    }

    @Test func isStableAcrossEnumerationOrder() {
        let a = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let b = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

        #expect(LayoutCalculator.screenFingerprint([a, b]) == LayoutCalculator.screenFingerprint([b, a]))
    }

    @Test func changesWhenAScreenMoves() {
        let a = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)]
        let b = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -2560, y: 0, width: 2560, height: 1440)]

        #expect(LayoutCalculator.screenFingerprint(a) != LayoutCalculator.screenFingerprint(b))
    }

    @Test func noScreensIsEmptyRatherThanACrash() {
        #expect(LayoutCalculator.screenFingerprint([]) == "")
    }
}

@Suite("Drag-to-edge layouts")
struct EdgeLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func sideEdgesGiveHalves() {
        #expect(LayoutCalculator.edgeLayout(for: CGPoint(x: 2, y: 400), in: screen) == .leftHalf)
        #expect(LayoutCalculator.edgeLayout(for: CGPoint(x: 998, y: 400), in: screen) == .rightHalf)
    }

    @Test func theTopEdgeMaximizes() {
        #expect(LayoutCalculator.edgeLayout(for: CGPoint(x: 500, y: 2), in: screen) == .maximize)
    }

    @Test func cornersGiveQuarters() {
        #expect(LayoutCalculator.edgeLayout(for: CGPoint(x: 2, y: 2), in: screen) == .topLeft)
        #expect(LayoutCalculator.edgeLayout(for: CGPoint(x: 998, y: 2), in: screen) == .topRight)
        #expect(LayoutCalculator.edgeLayout(for: CGPoint(x: 2, y: 798), in: screen) == .bottomLeft)
        #expect(LayoutCalculator.edgeLayout(for: CGPoint(x: 998, y: 798), in: screen) == .bottomRight)
    }

    @Test func theMiddleOfTheScreenSnapsToNothing() {
        #expect(LayoutCalculator.edgeLayout(for: CGPoint(x: 500, y: 400), in: screen) == nil)
    }

    @Test func aSideEdgeNearTheTopGivesAQuarter() {
        // Within the top quarter band of the left edge.
        #expect(LayoutCalculator.edgeLayout(for: CGPoint(x: 2, y: 60), in: screen) == .topLeft)
    }

    @Test func pointsFarOutsideTheScreenSnapToNothing() {
        #expect(LayoutCalculator.edgeLayout(for: CGPoint(x: -500, y: 400), in: screen) == nil)
    }
}
