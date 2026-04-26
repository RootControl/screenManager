import Foundation

final class BindingStore {
    private(set) var bindings: [SlotBinding] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("ScreenManager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("bindings.json")
        load()
    }

    func binding(forSlot slot: Int) -> SlotBinding? {
        bindings.first { $0.slot == slot }
    }

    func update(slot: Int, with info: WindowInfo) {
        let binding = SlotBinding(
            slot: slot,
            bundleID: info.bundleID,
            windowTitlePattern: info.windowTitle,
            appName: info.appName
        )
        if let idx = bindings.firstIndex(where: { $0.slot == slot }) {
            bindings[idx] = binding
        } else {
            bindings.append(binding)
        }
        save()
    }

    func remove(slot: Int) {
        bindings.removeAll { $0.slot == slot }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        bindings = (try? JSONDecoder().decode([SlotBinding].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
