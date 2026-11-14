import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []

    private let fileURL: URL

    nonisolated static let defaultFileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeSpaces/profiles.json")

    init(fileURL: URL = ProfileStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    func profile(_ id: Profile.ID) -> Profile? {
        profiles.first { $0.id == id }
    }

    @discardableResult
    func add(name: String) throws -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(profiles.map(\.slug))
        let slug = Profile.makeSlug(from: trimmed, taken: taken)
        let profile = Profile(
            id: UUID(),
            name: trimmed.isEmpty ? slug : trimmed,
            slug: slug,
            isDefault: false,
            isolateClaudeCode: true
        )
        try FileManager.default.createDirectory(at: profile.dataDir, withIntermediateDirectories: true)
        profiles.append(profile)
        persist()
        return profile
    }

    func rename(_ id: Profile.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = index(of: id), profiles[i].name != trimmed else { return }
        profiles[i].name = trimmed
        persist()
    }

    func setIsolation(_ id: Profile.ID, _ on: Bool) {
        guard let i = index(of: id), profiles[i].isolateClaudeCode != on else { return }
        profiles[i].isolateClaudeCode = on
        persist()
    }

    /// Moves the profile's folders to the Trash and forgets it. The Default profile can't be removed.
    func remove(_ id: Profile.ID) throws {
        guard let i = index(of: id), !profiles[i].isDefault else { return }
        let profile = profiles[i]
        let fm = FileManager.default
        for dir in [profile.dataDir, profile.isolatedClaudeCodeDir] where fm.fileExists(atPath: dir.path) {
            try fm.trashItem(at: dir, resultingItemURL: nil)
        }
        profiles.remove(at: i)
        persist()
    }

    private func index(of id: Profile.ID) -> Int? {
        profiles.firstIndex { $0.id == id }
    }

    private func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            profiles = decoded
        }
        if !profiles.contains(where: \.isDefault) {
            profiles.insert(.makeDefault(), at: 0)
            persist()
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(profiles).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Claude Spaces: failed to save profiles: \(error)")
        }
        ShellAliases.refreshManagedFileIfInstalled(profiles)
    }
}
