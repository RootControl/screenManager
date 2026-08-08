import CoreGraphics
import Testing
@testable import ScreenManagerCore

/// A 1000×800 screen at the origin, in AX coordinates.
private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
private let window = CGRect(x: 120, y: 90, width: 400, height: 300)

@Suite("Layout frames")
struct LayoutFrameTests {

    @Test func halvesTileTheScreen() {
        let left = LayoutCalculator.frame(for: .leftHalf, in: screen, current: window)
        let right = LayoutCalculator.frame(for: .rightHalf, in: screen, current: window)

        #expect(left == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(right == CGRect(x: 500, y: 0, width: 500, height: 800))
        #expect(left.union(right) == screen)
        #expect(left.intersection(right).isEmpty)
    }

    @Test func topAndBottomHalvesTileTheScreen() {
        let top = LayoutCalculator.frame(for: .topHalf, in: screen, current: window)
        let bottom = LayoutCalculator.frame(for: .bottomHalf, in: screen, current: window)

        #expect(top == CGRect(x: 0, y: 0, width: 1000, height: 400))
        #expect(bottom == CGRect(x: 0, y: 400, width: 1000, height: 400))
    }

    @Test func quartersTileTheScreenWithoutOverlap() {
        let quarters: [LayoutPosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let frames = quarters.map { LayoutCalculator.frame(for: $0, in: screen, current: window) }

        // y grows downward in AX space, so "top" sits at the smaller y.
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 500, height: 400))
        #expect(frames[1] == CGRect(x: 500, y: 0, width: 500, height: 400))
        #expect(frames[2] == CGRect(x: 0, y: 400, width: 500, height: 400))
        #expect(frames[3] == CGRect(x: 500, y: 400, width: 500, height: 400))

        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] {
                #expect(a.intersection(b).isEmpty)
            }
        }
        #expect(frames.reduce(CGRect.null) { $0.union($1) } == screen)
    }

    @Test func thirdsPartitionTheWidth() {
        let left = LayoutCalculator.frame(for: .leftThird, in: screen, current: window)
        let center = LayoutCalculator.frame(for: .centerThird, in: screen, current: window)
        let right = LayoutCalculator.frame(for: .rightThird, in: screen, current: window)

        #expect(left.width == center.width)
        #expect(center.width == right.width)
        #expect(left.maxX == center.minX)
        #expect(center.maxX == right.minX)
        #expect(abs(right.maxX - screen.maxX) < 0.001)
    }

    @Test func twoThirdsSpansTwoOfThreeColumns() {
        let left = LayoutCalculator.frame(for: .leftTwoThirds, in: screen, current: window)
        let right = LayoutCalculator.frame(for: .rightTwoThirds, in: screen, current: window)

        #expect(abs(left.width - screen.width * 2 / 3) < 0.001)
        #expect(left.minX == screen.minX)
        #expect(abs(right.maxX - screen.maxX) < 0.001)
    }

    @Test func maximizeFillsTheVisibleArea() {
        #expect(LayoutCalculator.frame(for: .maximize, in: screen, current: window) == screen)
    }

    @Test func centerKeepsSizeAndCentersTheWindow() {
        let result = LayoutCalculator.frame(for: .center, in: screen, current: window)

        #expect(result.size == window.size)
        #expect(result.midX == screen.midX)
        #expect(result.midY == screen.midY)
    }

    @Test func centerShrinksAWindowLargerThanTheScreen() {
        let huge = CGRect(x: -50, y: -50, width: 2000, height: 1600)
        let result = LayoutCalculator.frame(for: .center, in: screen, current: huge)

        #expect(result == screen)
    }

    @Test func everyPositionStaysInsideTheScreen() {
        for position in LayoutPosition.allCases {
            let frame = LayoutCalculator.frame(for: position, in: screen, current: window)
            #expect(screen.contains(frame), "\(position.title) escaped the screen: \(frame)")
        }
    }

    @Test func positionsRespectAnOffsetScreen() {
        // A second display to the right, with a menu bar inset.
        let secondary = CGRect(x: 1000, y: 25, width: 1440, height: 875)
        let frame = LayoutCalculator.frame(for: .rightHalf, in: secondary, current: window)

        #expect(frame == CGRect(x: 1720, y: 25, width: 720, height: 875))
    }
}

@Suite("Cross-display translation")
struct TranslateTests {
    private let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let target = CGRect(x: 1000, y: 0, width: 2000, height: 1600)

    @Test func preservesRelativePositionAndScale() {
        let result = LayoutCalculator.translate(
            CGRect(x: 500, y: 400, width: 250, height: 200),
            from: source,
            to: target
        )

        #expect(result == CGRect(x: 2000, y: 800, width: 500, height: 400))
    }

    @Test func aMaximizedWindowStaysMaximized() {
        #expect(LayoutCalculator.translate(source, from: source, to: target) == target)
    }

    @Test func resultAlwaysFitsInsideTheTarget() {
        let awkward = CGRect(x: 900, y: 700, width: 900, height: 700)
        let result = LayoutCalculator.translate(awkward, from: source, to: target)

        #expect(target.contains(result))
    }

    @Test func degenerateSourceFallsBackToTheWholeTarget() {
        let result = LayoutCalculator.translate(window, from: .zero, to: target)

        #expect(result == target)
    }
}

@Suite("Clamping")
struct ClampTests {
    @Test func aContainedFrameIsUnchanged() {
        #expect(LayoutCalculator.clamp(window, within: screen) == window)
    }

    @Test func anOffscreenFrameSlidesBackIn() {
        let result = LayoutCalculator.clamp(CGRect(x: 900, y: 700, width: 400, height: 300), within: screen)

        #expect(result == CGRect(x: 600, y: 500, width: 400, height: 300))
    }

    @Test func anOversizedFrameShrinksToFit() {
        let result = LayoutCalculator.clamp(CGRect(x: -100, y: -100, width: 3000, height: 2000), within: screen)

        #expect(result == screen)
    }
}

@Suite("Coordinate conversion")
struct FlipTests {
    @Test func cocoaOriginBecomesTheBottomOfAXSpace() {
        // Primary display 1000×800: a window at the Cocoa origin sits at the
        // bottom of the screen, so its AX y is 800 - height.
        let result = LayoutCalculator.flipY(CGRect(x: 0, y: 0, width: 400, height: 300), primaryMaxY: 800)

        #expect(result == CGRect(x: 0, y: 500, width: 400, height: 300))
    }

    @Test func flippingTwiceIsIdentity() {
        let flipped = LayoutCalculator.flipY(window, primaryMaxY: 800)

        #expect(LayoutCalculator.flipY(flipped, primaryMaxY: 800) == window)
    }

    @Test func widthAndHeightSurvive() {
        let result = LayoutCalculator.flipY(window, primaryMaxY: 1200)

        #expect(result.size == window.size)
        #expect(result.minX == window.minX)
    }
}

@Suite("Screen selection")
struct ScreenIndexTests {
    private let screens = [
        CGRect(x: 0, y: 0, width: 1000, height: 800),
        CGRect(x: 1000, y: 0, width: 1440, height: 900),
    ]

    @Test func picksTheScreenHoldingTheWindow() {
        #expect(LayoutCalculator.screenIndex(containing: CGRect(x: 1100, y: 100, width: 300, height: 200), screens: screens) == 1)
        #expect(LayoutCalculator.screenIndex(containing: CGRect(x: 10, y: 10, width: 300, height: 200), screens: screens) == 0)
    }

    @Test func picksTheScreenWithTheLargerOverlap() {
        // Straddles the seam, mostly on the right-hand display.
        let straddling = CGRect(x: 900, y: 100, width: 400, height: 200)

        #expect(LayoutCalculator.screenIndex(containing: straddling, screens: screens) == 1)
    }

    @Test func fallsBackToTheNearestScreenWhenFullyOffscreen() {
        let stray = CGRect(x: 3000, y: 100, width: 100, height: 100)

        #expect(LayoutCalculator.screenIndex(containing: stray, screens: screens) == 1)
    }

    @Test func returnsNilWithNoScreens() {
        #expect(LayoutCalculator.screenIndex(containing: window, screens: []) == nil)
    }
}

@Suite("Display cycling")
struct StepIndexTests {
    @Test func advancesAndWrapsForward() {
        #expect(LayoutCalculator.stepIndex(0, by: 1, count: 3) == 1)
        #expect(LayoutCalculator.stepIndex(2, by: 1, count: 3) == 0)
    }

    @Test func retreatsAndWrapsBackward() {
        #expect(LayoutCalculator.stepIndex(1, by: -1, count: 3) == 0)
        #expect(LayoutCalculator.stepIndex(0, by: -1, count: 3) == 2)
    }

    @Test func aSingleDisplayAlwaysStaysPut() {
        #expect(LayoutCalculator.stepIndex(0, by: 1, count: 1) == 0)
        #expect(LayoutCalculator.stepIndex(0, by: -1, count: 1) == 0)
    }

    @Test func zeroDisplaysDoesNotTrap() {
        #expect(LayoutCalculator.stepIndex(0, by: 1, count: 0) == 0)
    }
}
