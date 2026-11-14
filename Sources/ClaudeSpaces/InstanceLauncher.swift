import AppKit
import CoreGraphics

enum LauncherError: LocalizedError {
    case claudeNotInstalled

    var errorDescription: String? {
        switch self {
        case .claudeNotInstalled:
            return "Claude Desktop isn't installed. Claude Spaces looks for the app with bundle id \(InstanceMonitor.claudeBundleID)."
        }
    }
}

@MainActor
enum InstanceLauncher {
    /// Brings the profile's instance forward if it is running, otherwise starts it.
    static func openOrFocus(_ profile: Profile, monitor: InstanceMonitor) async throws {
        monitor.refresh()
        if let running = monitor.instance(for: profile) {
            focus(running.app)
        } else {
            try await launch(profile)
        }
    }

    static func launch(_ profile: Profile) async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: InstanceMonitor.claudeBundleID) else {
            throw LauncherError.claudeNotInstalled
        }

        let config = NSWorkspace.OpenConfiguration()
        // Electron's single-instance lock is per data dir, so a new process is needed for each profile.
        config.createsNewApplicationInstance = true
        config.activates = true
        if !profile.isDefault {
            try FileManager.default.createDirectory(at: profile.dataDir, withIntermediateDirectories: true)
            config.arguments = ["--user-data-dir=\(profile.dataDir.path)"]
        }
        if let codeDir = profile.claudeConfigDir {
            config.environment = ["CLAUDE_CONFIG_DIR": codeDir.path]
        }

        try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }

    static func focus(_ app: NSRunningApplication) {
        app.unhide()
        NSApp.yieldActivation(to: app)
        app.activate()
        if !hasOnScreenWindow(pid: app.processIdentifier) {
            sendReopen(to: app.processIdentifier)
        }
    }

    static func quit(_ app: NSRunningApplication) {
        app.terminate()
    }

    private static func hasOnScreenWindow(pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return true }
        return list.contains { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid
                && (info[kCGWindowLayer as String] as? Int) == 0
        }
    }

    /// Same event the Dock sends on an icon click; Electron answers it by opening a window.
    private static func sendReopen(to pid: pid_t) {
        let target = NSAppleEventDescriptor(processIdentifier: pid)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        _ = try? event.sendEvent(options: [.noReply], timeout: 2)
    }
}
