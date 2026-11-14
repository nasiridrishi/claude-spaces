import Foundation

struct Profile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// Fixed at creation: it names the data folder, the Claude Code config folder and the CLI alias.
    var slug: String
    var isDefault: Bool
    var isolateClaudeCode: Bool

    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let instancesRoot = home.appendingPathComponent(".claude-instances", isDirectory: true)
    static let defaultDataDir = home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
    static let sharedClaudeCodeDir = home.appendingPathComponent(".claude", isDirectory: true)

    static func makeDefault() -> Profile {
        Profile(id: UUID(), name: "Default", slug: "default", isDefault: true, isolateClaudeCode: false)
    }

    var dataDir: URL {
        isDefault ? Self.defaultDataDir : Self.instancesRoot.appendingPathComponent(slug, isDirectory: true)
    }

    var isolatedClaudeCodeDir: URL {
        Self.home.appendingPathComponent(".claude-\(slug)", isDirectory: true)
    }

    /// The CLAUDE_CONFIG_DIR value to launch with, or nil to leave Claude Code on ~/.claude.
    var claudeConfigDir: URL? {
        isolateClaudeCode ? isolatedClaudeCodeDir : nil
    }

    var aliasName: String { "claude-\(slug)" }

    static func makeSlug(from name: String, taken: Set<String>) -> String {
        var slug = ""
        for scalar in name.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
            } else if !slug.hasSuffix("-") {
                slug.append("-")
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "profile" }

        var candidate = slug
        var n = 2
        while taken.contains(candidate) {
            candidate = "\(slug)-\(n)"
            n += 1
        }
        return candidate
    }
}

extension URL {
    /// Path with symlinks and trailing slashes normalised, for comparing data dirs.
    var comparablePath: String {
        standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Path shown to the user, with the home folder written as ~.
    var tildePath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
