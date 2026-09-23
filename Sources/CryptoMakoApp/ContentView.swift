import SwiftUI
import CryptoMakoShared
import CryptoMakoVault

struct ContentView: View {
    @EnvironmentObject private var model: VaultAppModel

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
                        Button("Lock") { model.lock() }
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
                    Text("On Simulator, point at the repo fixtures/vault (see README).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("S3 connection") {
                    TextField("Endpoint (https://…)", text: $model.settings.endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Region", text: $model.settings.region)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Bucket", text: $model.settings.bucket)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Prefix", text: $model.settings.prefix)
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

            Section("Writes") {
                Text(model.writeStubMessage())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BrowseView: View {
    @EnvironmentObject private var model: VaultAppModel

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
                    Button {
                        Task {
                            if node.kind == .directory {
                                await model.enterDirectory(node)
                            } else if node.kind == .file {
                                await model.openFile(node)
                            }
                        }
                    } label: {
                        Label(
                            node.cleartextName,
                            systemImage: icon(for: node)
                        )
                    }
                }
            }

            if !model.statusMessage.isEmpty {
                Section("Status") {
                    Text(model.statusMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Writes") {
                Text(model.writeStubMessage())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
