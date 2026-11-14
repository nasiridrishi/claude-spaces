import AppKit

/// Shell aliases that start the Claude Code CLI with a profile's CLAUDE_CONFIG_DIR.
enum ShellAliases {
    static let managedFile = Profile.instancesRoot.appendingPathComponent("aliases.zsh")
    static let zshrc = Profile.home.appendingPathComponent(".zshrc")

    static let sourceLine =
        #"[ -f "$HOME/.claude-instances/aliases.zsh" ] && source "$HOME/.claude-instances/aliases.zsh""#

    static func aliasLine(for profile: Profile) -> String {
        #"alias \#(profile.aliasName)='CLAUDE_CONFIG_DIR="$HOME/.claude-\#(profile.slug)" claude'"#
    }

    static func copyAlias(for profile: Profile) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(aliasLine(for: profile), forType: .string)
    }

    static func render(_ profiles: [Profile]) -> String {
        var lines = ["# Managed by Claude Spaces. This file is rewritten whenever profiles change."]
        lines += profiles.filter(\.isolateClaudeCode).map(aliasLine(for:))
        return lines.joined(separator: "\n") + "\n"
    }

    static var isSourcedFromZshrc: Bool {
        guard let contents = try? String(contentsOf: zshrc, encoding: .utf8) else { return false }
        return contents.contains(sourceLine)
    }

    /// Writes the managed alias file and adds the source line to ~/.zshrc once.
    static func install(_ profiles: [Profile]) throws {
        try writeManagedFile(profiles)
        guard !isSourcedFromZshrc else { return }

        let fm = FileManager.default
        if !fm.fileExists(atPath: zshrc.path) {
            fm.createFile(atPath: zshrc.path, contents: nil)
        }
        let existing = (try? String(contentsOf: zshrc, encoding: .utf8)) ?? ""
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let block = "\(separator)\n# Claude Spaces CLI aliases\n\(sourceLine)\n"

        let handle = try FileHandle(forWritingTo: zshrc)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(block.utf8))
    }

    static func refreshManagedFileIfInstalled(_ profiles: [Profile]) {
        guard FileManager.default.fileExists(atPath: managedFile.path) else { return }
        try? writeManagedFile(profiles)
    }

    private static func writeManagedFile(_ profiles: [Profile]) throws {
        try FileManager.default.createDirectory(at: Profile.instancesRoot, withIntermediateDirectories: true)
        try render(profiles).write(to: managedFile, atomically: true, encoding: .utf8)
    }
}
