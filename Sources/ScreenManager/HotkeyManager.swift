import Carbon

typealias HotkeyCallback = (Int) -> Void

final class HotkeyManager {
    var onHotkeyPressed: HotkeyCallback?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    // ANSI key codes for 1–9 are non-sequential
    private static let keyCodes: [(slot: Int, code: UInt32)] = [
        (1, 0x12), (2, 0x13), (3, 0x14), (4, 0x15), (5, 0x17),
        (6, 0x16), (7, 0x1A), (8, 0x1C), (9, 0x19)
    ]

    func registerAll() {
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
                let slot = Int(hkID.id)
                DispatchQueue.main.async {
                    manager.onHotkeyPressed?(slot)
                }
                return noErr
            },
            1, &spec, selfPtr, &eventHandlerRef
        )

        for entry in Self.keyCodes {
            let hkID = EventHotKeyID(
                signature: OSType(0x534D6770), // 'SMgp'
                id: UInt32(entry.slot)
            )
            var ref: EventHotKeyRef?
            RegisterEventHotKey(
                entry.code,
                UInt32(controlKey),
                hkID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if let ref { hotKeyRefs.append(ref) }
        }
    }

    func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
    }

    deinit {
        unregisterAll()
    }
}
