import Foundation

/// Named captures of where every window sat. Distinct from profiles: a profile
/// holds slot bindings, an arrangement holds the placement of the whole screen.
final class ArrangementStore {
    private(set) var arrangements: [Arrangement]
    private let fileURL: URL

    init(directory: URL = AppPaths.supportDirectory) {
        fileURL = directory.appendingPathComponent("arrangements.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Arrangement].self, from: data) {
            arrangements = decoded
        } else {
            arrangements = []
        }
    }

    var names: [String] { arrangements.map(\.name) }

    func arrangement(named name: String) -> Arrangement? {
        arrangements.first { $0.name == name }
    }

    /// Saves under `name`, replacing any existing arrangement with that name.
    func save(_ snapshots: [WindowSnapshot], as name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !snapshots.isEmpty else { return }

        let arrangement = Arrangement(name: trimmed, snapshots: snapshots)
        if let index = arrangements.firstIndex(where: { $0.name == trimmed }) {
            arrangements[index] = arrangement
        } else {
            arrangements.append(arrangement)
            arrangements.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        persist()
    }

    func delete(named name: String) {
        arrangements.removeAll { $0.name == name }
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(arrangements) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
