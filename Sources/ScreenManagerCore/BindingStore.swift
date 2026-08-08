import Foundation

/// On-disk shape of `bindings.json`. Version 1 was a bare `[SlotBinding]`;
/// `decode` accepts either and migrates the old form into a "Default" profile.
struct BindingFile: Codable, Equatable {
    var activeProfile: String
    var profiles: [String: [SlotBinding]]

    static let defaultProfileName = "Default"

    static func decode(from data: Data) -> BindingFile? {
        let decoder = JSONDecoder()
        if let file = try? decoder.decode(BindingFile.self, from: data) {
            return file.normalized()
        }
        if let legacy = try? decoder.decode([SlotBinding].self, from: data) {
            return BindingFile(
                activeProfile: defaultProfileName,
                profiles: [defaultProfileName: legacy]
            )
        }
        return nil
    }

    /// Guarantees the active profile exists, so callers never face a nil lookup.
    func normalized() -> BindingFile {
        var copy = self
        if copy.profiles.isEmpty {
            copy.profiles = [Self.defaultProfileName: []]
        }
        if copy.profiles[copy.activeProfile] == nil {
            copy.activeProfile = copy.profiles.keys.sorted().first ?? Self.defaultProfileName
            if copy.profiles[copy.activeProfile] == nil {
                copy.profiles[copy.activeProfile] = []
            }
        }
        return copy
    }
}

final class BindingStore {
    private(set) var file: BindingFile
    private let fileURL: URL

    init(directory: URL = AppPaths.supportDirectory) {
        fileURL = directory.appendingPathComponent("bindings.json")
        if let data = try? Data(contentsOf: fileURL), let decoded = BindingFile.decode(from: data) {
            file = decoded
        } else {
            file = BindingFile(
                activeProfile: BindingFile.defaultProfileName,
                profiles: [BindingFile.defaultProfileName: []]
            )
        }
    }

    // MARK: - Bindings in the active profile

    var bindings: [SlotBinding] {
        file.profiles[file.activeProfile] ?? []
    }

    func binding(forSlot slot: Int) -> SlotBinding? {
        bindings.first { $0.slot == slot }
    }

    func set(_ binding: SlotBinding) {
        var current = bindings
        if let index = current.firstIndex(where: { $0.slot == binding.slot }) {
            current[index] = binding
        } else {
            current.append(binding)
        }
        file.profiles[file.activeProfile] = current.sorted { $0.slot < $1.slot }
        save()
    }

    func update(slot: Int, with info: WindowInfo, windowManager: WindowManager) {
        // Keep any frame the user already saved for this slot.
        let existingFrame = binding(forSlot: slot)?.savedFrame
        set(SlotBinding(
            slot: slot,
            info: info,
            reopenURL: windowManager.reopenURL(for: info),
            savedFrame: existingFrame
        ))
    }

    func saveFrame(_ frame: CodableRect?, forSlot slot: Int) {
        guard var binding = binding(forSlot: slot) else { return }
        binding.savedFrame = frame
        set(binding)
    }

    func remove(slot: Int) {
        file.profiles[file.activeProfile] = bindings.filter { $0.slot != slot }
        save()
    }

    // MARK: - Profiles

    var activeProfile: String { file.activeProfile }
    var profileNames: [String] { file.profiles.keys.sorted() }

    func switchProfile(to name: String) {
        guard file.profiles[name] != nil else { return }
        file.activeProfile = name
        save()
    }

    /// Creates `name` (or overwrites it) with a copy of the active profile's
    /// bindings, then switches to it.
    func saveProfile(as name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        file.profiles[trimmed] = bindings
        file.activeProfile = trimmed
        save()
    }

    func createEmptyProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, file.profiles[trimmed] == nil else { return }
        file.profiles[trimmed] = []
        file.activeProfile = trimmed
        save()
    }

    /// Deleting the last profile is a no-op — there is always somewhere to bind.
    func deleteProfile(named name: String) {
        guard file.profiles.count > 1, file.profiles[name] != nil else { return }
        file.profiles.removeValue(forKey: name)
        file = file.normalized()
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
