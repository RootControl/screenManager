import AppKit

/// Snaps a window when it is dragged to a screen edge, with a translucent
/// preview of where it will land.
///
/// Uses a listen-only event tap, so it observes mouse events without being able
/// to alter or swallow them — a dropped tap degrades to "snapping stops
/// working", never to "the mouse stops working".
final class DragSnapController {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let windowManager: WindowManager
    private var preview: NSWindow?

    /// The window under the cursor when the drag began.
    private var draggedWindow: AXUIElement?
    private var draggedWindowScreenIndex: Int?
    private var pendingLayout: LayoutPosition?
    private var isDragging = false

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    var isEnabled: Bool { eventTap != nil }

    func enable() {
        guard eventTap == nil else { return }

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userData in
                guard let userData else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<DragSnapController>.fromOpaque(userData).takeUnretainedValue()
                let location = event.location
                DispatchQueue.main.async {
                    controller.handle(type: type, location: location)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    func disable() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        clearPreview()
        draggedWindow = nil
        isDragging = false
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, location: CGPoint) {
        switch type {
        case .leftMouseDown:
            // Remember the focused window now; by mouse-up the cursor may be
            // over a different screen entirely.
            draggedWindow = windowManager.focusedWindowInfo()?.axElement
            draggedWindowScreenIndex = nil
            isDragging = false

        case .leftMouseDragged:
            guard draggedWindow != nil else { return }
            isDragging = true
            updatePreview(at: location)

        case .leftMouseUp:
            defer {
                clearPreview()
                draggedWindow = nil
                pendingLayout = nil
                isDragging = false
            }
            guard isDragging, let window = draggedWindow, let layout = pendingLayout else { return }
            windowManager.applyLayout(layout, to: window)

        default:
            return
        }
    }

    private func updatePreview(at location: CGPoint) {
        let screens = windowManager.visibleScreenFrames()
        guard let index = LayoutCalculator.screenIndex(containing: CGRect(origin: location, size: .zero), screens: windowManager.screenFrames()),
              index < screens.count,
              let layout = LayoutCalculator.edgeLayout(for: location, in: screens[index])
        else {
            pendingLayout = nil
            clearPreview()
            return
        }

        pendingLayout = layout
        let target = LayoutCalculator.frame(for: layout, in: screens[index], current: screens[index])
        showPreview(axFrame: target)
    }

    // MARK: - Preview overlay

    private func showPreview(axFrame: CGRect) {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let cocoaFrame = LayoutCalculator.flipY(axFrame, primaryMaxY: primaryMaxY)

        if preview == nil {
            let panel = NSPanel(
                contentRect: cocoaFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

            let view = NSView(frame: NSRect(origin: .zero, size: cocoaFrame.size))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
            view.layer?.borderWidth = 2
            view.layer?.cornerRadius = 8
            panel.contentView = view

            preview = panel
        }

        preview?.setFrame(cocoaFrame, display: true)
        preview?.orderFront(nil)
    }

    private func clearPreview() {
        preview?.orderOut(nil)
    }

    deinit {
        disable()
    }
}
