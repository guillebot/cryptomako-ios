import SwiftUI
import UniformTypeIdentifiers
import CryptoMakoShared
import CryptoMakoVault

struct ContentView: View {
    @EnvironmentObject private var model: VaultAppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .locked, .unlocking, .error:
                    ConnectionView()
                case .browsing:
                    BrowseView()
                }
            }
            .navigationTitle("CryptoMako")
            .toolbar {
                if case .browsing = model.phase {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Lock") { Task { await model.lock() } }
                    }
                }
            }
            .sheet(item: Binding(
                get: { model.previewText.map { PreviewPayload(title: model.previewTitle ?? "File", text: $0) } },
                set: { if $0 == nil { model.previewText = nil; model.previewTitle = nil } }
            )) { payload in
                NavigationStack {
                    ScrollView {
                        Text(payload.text)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(payload.title)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                model.previewText = nil
                                model.previewTitle = nil
                            }
                        }
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, model.isUnlocked {
                    Task { await model.importShareInbox() }
                }
            }
        }
    }
}

private struct PreviewPayload: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

struct ConnectionView: View {
    @EnvironmentObject private var model: VaultAppModel

    private var statusColor: Color {
        if case .error = model.phase { return .red }
        return .secondary
    }

    var body: some View {
        Form {
            Section("Storage") {
                Picker("Mode", selection: $model.settings.storageMode) {
                    Text("S3 (HTTPS)").tag(VaultSettings.StorageMode.s3)
                    Text("Local fixtures").tag(VaultSettings.StorageMode.local)
                }
                .pickerStyle(.segmented)
            }

            if model.settings.isLocal {
                Section("Local vault") {
                    TextField("Absolute path to vault/", text: $model.settings.localVaultPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Simulator: point at this clone’s fixtures/vault. Writes mutate that tree.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("S3 (HTTPS only)") {
                    TextField("Endpoint https://…", text: $model.settings.endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Region", text: $model.settings.region)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Bucket", text: $model.settings.bucket)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Prefix (optional)", text: $model.settings.prefix)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Access key", text: $model.settings.accessKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Secret key", text: $model.secretKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section("Vault password") {
                SecureField("Password", text: $model.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    Task { await model.unlock() }
                } label: {
                    if model.phase == .unlocking {
                        ProgressView()
                    } else {
                        Text("Unlock")
                    }
                }
                .disabled(model.phase == .unlocking || model.password.isEmpty)

                Button("Save connection") {
                    model.saveConnection()
                }
            }

            if !model.statusMessage.isEmpty {
                Section("Status") {
                    Text(model.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(statusColor)
                }
            }

            Section("About") {
                Text("Writes succeed only after remote put/delete. Share → CryptoMako imports into the current folder when unlocked. Files location appears after S3 unlock.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BrowseView: View {
    @EnvironmentObject private var model: VaultAppModel

    @State private var showCreateFolder = false
    @State private var newFolderName = ""
    @State private var showFileImporter = false
    @State private var showFolderPicker = false
    @State private var pendingDelete: VaultNode?
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            Section(model.currentPathLabel) {
                if !model.pathStack.isEmpty {
                    Button {
                        Task { await model.goUp() }
                    } label: {
                        Label("..", systemImage: "arrow.up.left")
                    }
                }
                ForEach(model.nodes, id: \.itemId) { node in
                    HStack {
                        Button {
                            Task {
                                if node.kind == .directory {
                                    await model.enterDirectory(node)
                                } else if node.kind == .file {
                                    await model.openFile(node)
                                }
                            }
                        } label: {
                            Label(node.cleartextName, systemImage: icon(for: node))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button(role: .destructive) {
                            pendingDelete = node
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isBusy || model.backupActive)
                        .accessibilityLabel("Delete \(node.cleartextName)")
                    }
                }
            }

            Section("Backup / Sync") {
                Picker("Transfer mode", selection: Binding(
                    get: { model.backupTransferMode },
                    set: { model.setBackupTransferMode($0) }
                )) {
                    Text("Backup").tag(AppPreferences.BackupTransferMode.backup)
                    Text("Sync").tag(AppPreferences.BackupTransferMode.sync)
                }
                .pickerStyle(.segmented)
                .disabled(model.backupActive)

                if model.backupTransferMode == .backup {
                    Text("Backup copies and updates into Backups/<folder>/. It never deletes the on-device source, and it does not remove vault files that are missing locally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sync copies and updates, then deletes vault ciphertext under Backups/<folder>/ that is missing from the on-device folder. It never deletes the on-device source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let warn = model.backupOverlapWarning {
                    Text(warn)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !model.backupSources.isEmpty {
                    ForEach(model.backupSources) { source in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.displayName)
                                    .font(.body)
                                Text(source.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                model.removeBackupSource(id: source.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.isBusy || model.backupActive)
                            .accessibilityLabel("Remove \(source.displayName)")
                        }
                    }

                    Button {
                        model.backupAllSources()
                    } label: {
                        Label(
                            model.backupTransferMode == .sync ? "Sync all sources" : "Backup all sources",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(model.isBusy || model.backupActive || !model.isUnlocked)
                }

                Button {
                    showFolderPicker = true
                } label: {
                    Label(
                        model.backupTransferMode == .sync
                            ? "Sync folder into vault…"
                            : "Backup folder into vault…",
                        systemImage: "externaldrive.badge.plus"
                    )
                }
                .disabled(model.isBusy || model.backupActive)
            }

            Section("Actions") {
                Button {
                    newFolderName = ""
                    showCreateFolder = true
                } label: {
                    Label("New folder", systemImage: "folder.badge.plus")
                }
                .disabled(model.isBusy || model.backupActive)

                Button {
                    showFileImporter = true
                } label: {
                    Label("Upload files", systemImage: "doc.badge.plus")
                }
                .disabled(model.isBusy || model.backupActive)

                Button {
                    Task { await model.importShareInbox() }
                } label: {
                    Label("Import shared inbox", systemImage: "square.and.arrow.down")
                }
                .disabled(model.isBusy || model.backupActive)
            }

            if model.backupActive {
                Section(model.backupTransferMode == .sync ? "Sync" : "Backup") {
                    ProgressView(value: Double(model.backupDone), total: Double(max(model.backupTotal, 1))) {
                        Text("\(model.backupDone)/\(model.backupTotal)")
                    }
                    if !model.backupCurrentName.isEmpty {
                        Text(model.backupCurrentName)
                            .font(.caption2)
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                    if model.backupTransferMode == .sync && model.backupDeleted > 0 {
                        Text("Removed \(model.backupDeleted) vault-only file(s)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button(model.backupTransferMode == .sync ? "Cancel sync" : "Cancel backup", role: .destructive) {
                        model.cancelBackup()
                    }
                }
            }

            if !model.statusMessage.isEmpty {
                Section("Status") {
                    Text(model.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(model.lastError == nil ? Color.secondary : Color.red)
                }
            }
        }
        .alert("New folder", isPresented: $showCreateFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newFolderName
                Task { await model.createFolder(named: name) }
            }
        } message: {
            Text("Creates a Cryptomator directory after remote put succeeds.")
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.cleartextName ?? "item")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let node = pendingDelete {
                    Task { await model.deleteNode(node) }
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text(
                pendingDelete?.kind == .directory
                    ? "Deletes the folder and its contents from the vault (remote)."
                    : "Deletes the file from the vault (remote)."
            )
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await model.uploadFiles(from: urls) }
            case .failure(let error):
                model.statusMessage = "File picker failed: \(error.localizedDescription)"
                model.lastError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                showFolderPicker = false
                if let url {
                    model.backupFolder(at: url)
                }
            }
        }
    }

    private func icon(for node: VaultNode) -> String {
        switch node.kind {
        case .directory: return "folder"
        case .file: return "doc"
        case .symlink: return "link"
        }
    }
}

/// UIDocumentPicker for folders (security-scoped) — used for M4 backup.
struct FolderPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
