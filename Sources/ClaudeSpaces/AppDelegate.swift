import AppKit
import SwiftUI

/// Owns the status item. The menu is AppKit rather than SwiftUI's MenuBarExtra because
/// NSMenu supports ⌥ alternate items.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store: ProfileStore
    let monitor = InstanceMonitor()
    private(set) lazy var manageModel = ManageModel(store: store)

    private(set) var statusItem: NSStatusItem!
    private(set) var manageWindow: NSWindow?

    init(store: ProfileStore? = nil) {
        self.store = store ?? ProfileStore()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "person.2.circle", accessibilityDescription: "Claude Spaces")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        monitor.refresh()
        menu.removeAllItems()

        let header = NSMenuItem(title: "Claude Profiles", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for (index, profile) in store.profiles.enumerated() {
            let running = monitor.instance(for: profile)
            let key = index < 9 ? "\(index + 1)" : ""

            let item = NSMenuItem(title: profile.name, action: #selector(openProfile(_:)), keyEquivalent: key)
            item.target = self
            item.representedObject = profile.id
            item.state = running == nil ? .off : .on
            item.onStateImage = NSImage(named: NSImage.statusAvailableName)
            item.toolTip = tooltip(for: profile, running: running)
            menu.addItem(item)

            let alternate: NSMenuItem
            if running != nil {
                alternate = NSMenuItem(title: "Quit \(profile.name)", action: #selector(quitProfile(_:)), keyEquivalent: key)
            } else {
                alternate = NSMenuItem(title: "Reveal \(profile.name) Data Folder", action: #selector(revealProfile(_:)), keyEquivalent: key)
            }
            alternate.target = self
            alternate.representedObject = profile.id
            alternate.isAlternate = true
            alternate.keyEquivalentModifierMask = [.command, .option]
            menu.addItem(alternate)
        }

        let strays = monitor.unmatched(store.profiles)
        if !strays.isEmpty {
            menu.addItem(.separator())
            let label = NSMenuItem(title: "Instances Outside Your Profiles", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)
            for stray in strays {
                let item = NSMenuItem(
                    title: "⚠︎ \(stray.effectiveDataDir.lastPathComponent)",
                    action: #selector(focusInstance(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = stray.app
                item.toolTip = stray.effectiveDataDir.tildePath
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("Manage Profiles…", #selector(showManageWindow), key: ","))

        menu.addItem(.separator())
        let login = makeItem("Launch at Login", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(makeItem(
            ShellAliases.isSourcedFromZshrc ? "Update CLI Aliases" : "Install CLI Aliases…",
            #selector(installAliases)
        ))

        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Claude Spaces", #selector(quitSelf), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func tooltip(for profile: Profile, running: RunningInstance?) -> String {
        var lines = ["Desktop data: \(profile.dataDir.tildePath)"]
        lines.append("Claude Code: \((profile.claudeConfigDir ?? Profile.sharedClaudeCodeDir).tildePath)")
        if let running {
            lines.append("Running (pid \(running.id))")
        }
        return lines.joined(separator: "\n")
    }

    private func profile(from sender: NSMenuItem) -> Profile? {
        (sender.representedObject as? UUID).flatMap(store.profile)
    }

    @objc private func openProfile(_ sender: NSMenuItem) {
        guard let profile = profile(from: sender) else { return }
        Task {
            do {
                try await InstanceLauncher.openOrFocus(profile, monitor: monitor)
            } catch {
                presentError(error)
            }
        }
    }

    @objc private func quitProfile(_ sender: NSMenuItem) {
        guard let profile = profile(from: sender), let running = monitor.instance(for: profile) else { return }
        InstanceLauncher.quit(running.app)
    }

    @objc private func revealProfile(_ sender: NSMenuItem) {
        guard let profile = profile(from: sender) else { return }
        try? FileManager.default.createDirectory(at: profile.dataDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([profile.dataDir])
    }

    @objc private func focusInstance(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        InstanceLauncher.focus(app)
    }

    @objc func showManageWindow() {
        if manageWindow == nil {
            let root = ManageProfilesView()
                .environmentObject(store)
                .environmentObject(monitor)
                .environmentObject(manageModel)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Claude Spaces"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 420))
            window.isReleasedWhenClosed = false
            window.center()
            manageWindow = window
        }
        NSApp.activate()
        manageWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLoginItem() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            presentError(error)
        }
    }

    @objc private func installAliases() {
        if !ShellAliases.isSourcedFromZshrc {
            let alert = NSAlert()
            alert.messageText = "Install CLI aliases?"
            alert.informativeText = """
            This writes \(ShellAliases.managedFile.tildePath) with a claude-<profile> alias for every \
            profile that isolates Claude Code, and adds this line to ~/.zshrc:

            \(ShellAliases.sourceLine)

            Open a new terminal afterwards to use the aliases.
            """
            alert.addButton(withTitle: "Install")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try ShellAliases.install(store.profiles)
        } catch {
            presentError(error)
        }
    }

    @objc private func quitSelf() {
        NSApp.terminate(nil)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        NSApp.activate()
        alert.runModal()
    }
}
