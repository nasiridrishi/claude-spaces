import AppKit
import Darwin

struct RunningInstance: Identifiable {
    let app: NSRunningApplication
    /// The --user-data-dir the process was started with; nil means Claude's default folder.
    let userDataDir: URL?
    let claudeConfigDir: URL?

    var id: pid_t { app.processIdentifier }

    var effectiveDataDir: URL { userDataDir ?? Profile.defaultDataDir }
}

@MainActor
final class InstanceMonitor: ObservableObject {
    nonisolated static let claudeBundleID = "com.anthropic.claudefordesktop"

    @Published private(set) var instances: [RunningInstance] = []

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.claudeBundleID else { return }
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func refresh() {
        instances = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == Self.claudeBundleID && !$0.isTerminated }
            .map { app in
                let info = ProcessInfoReader.read(pid: app.processIdentifier)
                return RunningInstance(
                    app: app,
                    userDataDir: info?.userDataDir,
                    claudeConfigDir: info?.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
                )
            }
    }

    func instance(for profile: Profile) -> RunningInstance? {
        let target = profile.dataDir.comparablePath
        return instances.first { $0.effectiveDataDir.comparablePath == target }
    }

    /// Running instances whose data dir doesn't belong to any profile.
    func unmatched(_ profiles: [Profile]) -> [RunningInstance] {
        let known = Set(profiles.map { $0.dataDir.comparablePath })
        return instances.filter { !known.contains($0.effectiveDataDir.comparablePath) }
    }
}

/// Reads another process's argv and environment through sysctl(KERN_PROCARGS2).
enum ProcessInfoReader {
    struct Info {
        var arguments: [String]
        var environment: [String: String]

        var userDataDir: URL? {
            let flag = "--user-data-dir"
            for (i, arg) in arguments.enumerated() {
                if arg.hasPrefix(flag + "=") {
                    return URL(fileURLWithPath: unquote(String(arg.dropFirst(flag.count + 1))))
                }
                if arg == flag, i + 1 < arguments.count {
                    return URL(fileURLWithPath: unquote(arguments[i + 1]))
                }
            }
            return nil
        }

        private func unquote(_ s: String) -> String {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }

    static func read(pid: pid_t) -> Info? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // Layout: Int32 argc, exec path, NUL padding, argc argv strings, then env strings.
        let argc = buffer.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var pos = MemoryLayout<Int32>.size
        while pos < size, buffer[pos] != 0 { pos += 1 }
        while pos < size, buffer[pos] == 0 { pos += 1 }

        var strings: [String] = []
        while pos < size {
            let start = pos
            while pos < size, buffer[pos] != 0 { pos += 1 }
            if pos == start { break }
            strings.append(String(decoding: buffer[start..<pos], as: UTF8.self))
            pos += 1
        }

        let args = Array(strings.prefix(argc))
        var env: [String: String] = [:]
        for entry in strings.dropFirst(argc) {
            guard let eq = entry.firstIndex(of: "=") else { continue }
            env[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        return Info(arguments: args, environment: env)
    }
}
