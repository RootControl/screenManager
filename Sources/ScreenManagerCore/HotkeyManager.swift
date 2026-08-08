import Carbon

/// ANSI virtual key codes. The digits are famously non-sequential.
enum KeyCode {
    static let digits: [Int: UInt32] = [
        1: 0x12, 2: 0x13, 3: 0x14, 4: 0x15, 5: 0x17,
        6: 0x16, 7: 0x1A, 8: 0x1C, 9: 0x19
    ]
    static let leftArrow: UInt32 = 0x7B
    static let rightArrow: UInt32 = 0x7C
    static let downArrow: UInt32 = 0x7D
    static let upArrow: UInt32 = 0x7E
    static let u: UInt32 = 0x20
    static let i: UInt32 = 0x22
    static let j: UInt32 = 0x26
    static let k: UInt32 = 0x28
    static let c: UInt32 = 0x08
    static let ret: UInt32 = 0x24
}

struct HotkeySpec {
    let id: UInt32
    let keyCode: UInt32
    let modifiers: ModifierCombo
    /// Human-readable name, used to report a registration conflict.
    let label: String
}

final class HotkeyManager {
    var onPressed: ((UInt32) -> Void)?

    /// Labels of hotkeys the system refused — almost always because another
    /// app already owns the combination.
    private(set) var conflicts: [String] = []

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private static let signature = OSType(0x534D6770) // 'SMgp'

    /// Replaces every registration with `specs`. Safe to call repeatedly, which
    /// is how a modifier change in Settings takes effect immediately.
    func register(_ specs: [HotkeySpec]) {
        unregisterHotkeys()
        installHandlerIfNeeded()
        conflicts = []

        for spec in specs {
            let hkID = EventHotKeyID(signature: Self.signature, id: spec.id)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                spec.keyCode,
                spec.modifiers.carbonMask,
                hkID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
            } else {
                conflicts.append(spec.label)
            }
        }
    }

    func unregisterAll() {
        unregisterHotkeys()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }

    private func unregisterHotkeys() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = hkID.id
                DispatchQueue.main.async { manager.onPressed?(id) }
                return noErr
            },
            1, &spec, selfPtr, &eventHandlerRef
        )
    }

    deinit {
        unregisterAll()
    }
}

/// Hotkey IDs are partitioned into ranges so a single handler can decode the
/// action from the ID alone.
enum HotkeyAction: Equatable {
    case focus(slot: Int)
    case bind(slot: Int)
    case moveToDisplay(index: Int)
    case layout(LayoutPosition)
    case cycleDisplay(delta: Int)

    private static let focusBase: UInt32 = 1
    private static let bindBase: UInt32 = 11
    private static let displayBase: UInt32 = 21
    private static let layoutBase: UInt32 = 31
    static let previousDisplayID: UInt32 = 61
    static let nextDisplayID: UInt32 = 62

    var id: UInt32 {
        switch self {
        case .focus(let slot): return Self.focusBase + UInt32(slot) - 1
        case .bind(let slot): return Self.bindBase + UInt32(slot) - 1
        case .moveToDisplay(let index): return Self.displayBase + UInt32(index)
        case .layout(let position):
            let index = LayoutPosition.allCases.firstIndex(of: position) ?? 0
            return Self.layoutBase + UInt32(index)
        case .cycleDisplay(let delta): return delta < 0 ? Self.previousDisplayID : Self.nextDisplayID
        }
    }

    static func from(id: UInt32) -> HotkeyAction? {
        switch id {
        case focusBase..<bindBase:
            return .focus(slot: Int(id - focusBase) + 1)
        case bindBase..<displayBase:
            return .bind(slot: Int(id - bindBase) + 1)
        case displayBase..<layoutBase:
            return .moveToDisplay(index: Int(id - displayBase))
        case layoutBase..<(layoutBase + UInt32(LayoutPosition.allCases.count)):
            return .layout(LayoutPosition.allCases[Int(id - layoutBase)])
        case previousDisplayID:
            return .cycleDisplay(delta: -1)
        case nextDisplayID:
            return .cycleDisplay(delta: 1)
        default:
            return nil
        }
    }
}

/// Builds the full hotkey table from the current preferences.
enum HotkeyPlan {
    /// Layout positions that get a keyboard shortcut; the rest are menu-only.
    static let layoutKeys: [(position: LayoutPosition, keyCode: UInt32, symbol: String)] = [
        (.leftHalf, KeyCode.leftArrow, "←"),
        (.rightHalf, KeyCode.rightArrow, "→"),
        (.topHalf, KeyCode.upArrow, "↑"),
        (.bottomHalf, KeyCode.downArrow, "↓"),
        (.topLeft, KeyCode.u, "U"),
        (.topRight, KeyCode.i, "I"),
        (.bottomLeft, KeyCode.j, "J"),
        (.bottomRight, KeyCode.k, "K"),
        (.maximize, KeyCode.ret, "↩"),
        (.center, KeyCode.c, "C"),
    ]

    static func specs(for preferences: Preferences) -> [HotkeySpec] {
        var specs: [HotkeySpec] = []
        let slots = preferences.clampedSlotCount

        for slot in 1...slots {
            guard let code = KeyCode.digits[slot] else { continue }
            specs.append(HotkeySpec(
                id: HotkeyAction.focus(slot: slot).id,
                keyCode: code,
                modifiers: preferences.focusModifiers,
                label: "\(preferences.focusModifiers.display)\(slot) (focus slot \(slot))"
            ))
            specs.append(HotkeySpec(
                id: HotkeyAction.bind(slot: slot).id,
                keyCode: code,
                modifiers: preferences.bindModifiers,
                label: "\(preferences.bindModifiers.display)\(slot) (bind slot \(slot))"
            ))
            specs.append(HotkeySpec(
                id: HotkeyAction.moveToDisplay(index: slot - 1).id,
                keyCode: code,
                modifiers: preferences.displayModifiers,
                label: "\(preferences.displayModifiers.display)\(slot) (move to display \(slot))"
            ))
        }

        for entry in layoutKeys {
            specs.append(HotkeySpec(
                id: HotkeyAction.layout(entry.position).id,
                keyCode: entry.keyCode,
                modifiers: preferences.layoutModifiers,
                label: "\(preferences.layoutModifiers.display)\(entry.symbol) (\(entry.position.title))"
            ))
        }

        specs.append(HotkeySpec(
            id: HotkeyAction.cycleDisplay(delta: -1).id,
            keyCode: KeyCode.leftArrow,
            modifiers: preferences.displayModifiers,
            label: "\(preferences.displayModifiers.display)← (previous display)"
        ))
        specs.append(HotkeySpec(
            id: HotkeyAction.cycleDisplay(delta: 1).id,
            keyCode: KeyCode.rightArrow,
            modifiers: preferences.displayModifiers,
            label: "\(preferences.displayModifiers.display)→ (next display)"
        ))

        return specs
    }
}
