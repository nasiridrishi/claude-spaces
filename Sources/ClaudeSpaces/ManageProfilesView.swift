import SwiftUI

/// View state for the Manage window. It lives in an ObservableObject because the Command Line
/// Tools ship without the SwiftUI macro plugin that `@State` needs on this SDK.
@MainActor
final class ManageModel: ObservableObject {
    private let store: ProfileStore

    @Published var newName = ""
    @Published var errorMessage: String?
    @Published var confirmingDelete = false
    @Published var draftName = ""
    @Published var selection: Profile.ID? {
        willSet { commitName() }
        didSet { draftName = selection.flatMap(store.profile)?.name ?? "" }
    }

    init(store: ProfileStore) {
        self.store = store
    }

    func commitName() {
        guard let id = selection else { return }
        store.rename(id, to: draftName)
    }

    func addProfile() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let profile = try store.add(name: name)
            newName = ""
            selection = profile.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ManageProfilesView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var monitor: InstanceMonitor
    @EnvironmentObject private var model: ManageModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    ForEach(store.profiles) { profile in
                        ProfileRow(profile: profile, isRunning: monitor.instance(for: profile) != nil)
                            .tag(profile.id)
                    }
                }
                Divider()
                HStack {
                    TextField("New profile name", text: $model.newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(model.addProfile)
                    Button("Add", action: model.addProfile)
                        .disabled(model.newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(10)
            }
            .frame(width: 230)

            Divider()

            Group {
                if let id = model.selection, let profile = store.profile(id) {
                    ProfileDetail(profile: profile)
                } else {
                    Text("Select a profile")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 360)
        .onAppear {
            if model.selection == nil { model.selection = store.profiles.first?.id }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

}

private struct ProfileRow: View {
    let profile: Profile
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? Color.green : Color.clear)
                .overlay(Circle().strokeBorder(Color.secondary.opacity(isRunning ? 0 : 0.6)))
                .frame(width: 8, height: 8)
            Text(profile.name)
            Spacer()
            if profile.isDefault {
                Text("default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProfileDetail: View {
    let profile: Profile

    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var monitor: InstanceMonitor
    @EnvironmentObject private var model: ManageModel

    private var running: RunningInstance? { monitor.instance(for: profile) }

    /// True when the running instance was launched with a different Claude Code dir than the profile now asks for.
    private var needsRelaunch: Bool {
        guard let running else { return false }
        return running.claudeConfigDir?.comparablePath != profile.claudeConfigDir?.comparablePath
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $model.draftName)
                    .onSubmit(model.commitName)
                LabeledContent("Status") {
                    if let running {
                        Text("Running (pid \(String(running.id)))")
                    } else {
                        Text("Not running").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Claude Desktop") {
                LabeledContent("Data folder") {
                    HStack {
                        Text(profile.dataDir.tildePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button("Reveal") { reveal(profile.dataDir) }
                    }
                }
            }

            Section("Claude Code") {
                Toggle("Isolate Claude Code", isOn: Binding(
                    get: { profile.isolateClaudeCode },
                    set: { store.setIsolation(profile.id, $0) }
                ))
                LabeledContent("Config folder") {
                    Text((profile.claudeConfigDir ?? Profile.sharedClaudeCodeDir).tildePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                if profile.isolateClaudeCode {
                    LabeledContent("CLI alias") {
                        HStack {
                            Text(profile.aliasName).font(.body.monospaced())
                            Button("Copy") { ShellAliases.copyAlias(for: profile) }
                        }
                    }
                }
                if needsRelaunch {
                    Text("Quit and relaunch this instance to apply the Claude Code setting.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                HStack {
                    Button(running == nil ? "Launch" : "Focus") {
                        Task {
                            do {
                                try await InstanceLauncher.openOrFocus(profile, monitor: monitor)
                            } catch {
                                model.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    if let running {
                        Button("Quit") { InstanceLauncher.quit(running.app) }
                    }
                    Spacer()
                    if !profile.isDefault {
                        Button("Delete…", role: .destructive) { model.confirmingDelete = true }
                            .disabled(running != nil)
                            .help(running != nil ? "Quit this instance before deleting the profile." : "")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Delete “\(profile.name)”?", isPresented: $model.confirmingDelete) {
            Button("Move to Trash", role: .destructive) {
                do {
                    model.selection = nil
                    try store.remove(profile.id)
                    model.selection = store.profiles.first?.id
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
            Its Desktop data folder (sign-in, chats, connectors) and its Claude Code config folder, \
            if any, move to the Trash. You can restore them from the Trash until you empty it.
            """)
        }
    }

    private func reveal(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
