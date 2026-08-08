import CoreGraphics

/// Where a window should sit within a screen's usable area.
enum LayoutPosition: String, Codable, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case maximize, center

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .maximize: return "Maximize"
        case .center: return "Center"
        }
    }
}

/// Pure frame arithmetic. Every function here works in AX coordinates —
/// origin at the top-left of the primary display, y growing downward — so
/// callers convert once at the boundary and never think about it again.
enum LayoutCalculator {

    /// The frame `position` implies inside `area`. `current` is only consulted
    /// for `.center`, which preserves the window's existing size.
    static func frame(for position: LayoutPosition, in area: CGRect, current: CGRect) -> CGRect {
        let halfW = area.width / 2
        let halfH = area.height / 2
        let thirdW = area.width / 3

        switch position {
        case .leftHalf:
            return CGRect(x: area.minX, y: area.minY, width: halfW, height: area.height)
        case .rightHalf:
            return CGRect(x: area.minX + halfW, y: area.minY, width: halfW, height: area.height)
        case .topHalf:
            return CGRect(x: area.minX, y: area.minY, width: area.width, height: halfH)
        case .bottomHalf:
            return CGRect(x: area.minX, y: area.minY + halfH, width: area.width, height: halfH)
        case .topLeft:
            return CGRect(x: area.minX, y: area.minY, width: halfW, height: halfH)
        case .topRight:
            return CGRect(x: area.minX + halfW, y: area.minY, width: halfW, height: halfH)
        case .bottomLeft:
            return CGRect(x: area.minX, y: area.minY + halfH, width: halfW, height: halfH)
        case .bottomRight:
            return CGRect(x: area.minX + halfW, y: area.minY + halfH, width: halfW, height: halfH)
        case .leftThird:
            return CGRect(x: area.minX, y: area.minY, width: thirdW, height: area.height)
        case .centerThird:
            return CGRect(x: area.minX + thirdW, y: area.minY, width: thirdW, height: area.height)
        case .rightThird:
            return CGRect(x: area.minX + 2 * thirdW, y: area.minY, width: thirdW, height: area.height)
        case .leftTwoThirds:
            return CGRect(x: area.minX, y: area.minY, width: 2 * thirdW, height: area.height)
        case .rightTwoThirds:
            return CGRect(x: area.minX + thirdW, y: area.minY, width: 2 * thirdW, height: area.height)
        case .maximize:
            return area
        case .center:
            let size = CGSize(width: min(current.width, area.width), height: min(current.height, area.height))
            return CGRect(
                x: area.minX + (area.width - size.width) / 2,
                y: area.minY + (area.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    /// Maps a frame from one screen to another, preserving its relative
    /// position and proportional size, then clamps it inside the target.
    static func translate(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return target }

        let relX = (frame.minX - source.minX) / source.width
        let relY = (frame.minY - source.minY) / source.height
        let width = min(frame.width / source.width * target.width, target.width)
        let height = min(frame.height / source.height * target.height, target.height)

        let moved = CGRect(
            x: target.minX + relX * target.width,
            y: target.minY + relY * target.height,
            width: width,
            height: height
        )
        return clamp(moved, within: target)
    }

    /// Slides `frame` until it lies inside `area`, shrinking it only if it
    /// cannot fit otherwise.
    static func clamp(_ frame: CGRect, within area: CGRect) -> CGRect {
        let width = min(frame.width, area.width)
        let height = min(frame.height, area.height)
        let x = min(max(frame.minX, area.minX), area.maxX - width)
        let y = min(max(frame.minY, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Converts a Cocoa rect (origin bottom-left of the primary display, y up)
    /// into AX coordinates (origin top-left, y down). Self-inverse.
    static func flipY(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Index of the screen holding most of `frame`, or the nearest one by
    /// center distance when it overlaps none. Returns nil for an empty list.
    static func screenIndex(containing frame: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }

        var bestIndex = 0
        var bestArea: CGFloat = 0
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        if bestArea > 0 { return bestIndex }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.enumerated().min(by: { lhs, rhs in
            distanceSquared(center, CGPoint(x: lhs.element.midX, y: lhs.element.midY))
                < distanceSquared(center, CGPoint(x: rhs.element.midX, y: rhs.element.midY))
        })?.offset
    }

    /// Wraps around both ends, so "next display" cycles.
    static func stepIndex(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + delta) % count + count) % count
    }

    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
