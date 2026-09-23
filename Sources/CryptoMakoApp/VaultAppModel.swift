import Foundation
import SwiftUI
import CryptoMakoS3
import CryptoMakoShared
import CryptoMakoVault

@MainActor
final class VaultAppModel: ObservableObject {
    enum Phase: Equatable {
        case locked
        case unlocking
        case browsing
        case error(String)
    }

    @Published var settings: VaultSettings
    @Published var secretKey: String = ""
    @Published var password: String = ""
    @Published var phase: Phase = .locked
    @Published var nodes: [VaultNode] = []
    @Published var pathStack: [(name: String, dirId: String)] = []
    @Published var statusMessage: String = ""
    @Published var previewText: String?
    @Published var previewTitle: String?

    /// Writes are fail-closed in M1 — surface this in the UI.
    let writesEnabled = false

    private var session: VaultSession?

    var currentDirId: String {
        pathStack.last?.dirId ?? ""
    }

    var currentPathLabel: String {
        if pathStack.isEmpty { return "/" }
        return "/" + pathStack.map(\.name).joined(separator: "/")
    }

    init() {
        settings = VaultSettings.load() ?? VaultSettings()
        if let secret = try? CredentialStore.readSharedOrLocal(account: AppIdentifiers.secretKeyAccount) {
            secretKey = secret
        }
        if let pw = try? CredentialStore.readSharedOrLocal(account: AppIdentifiers.passwordAccount) {
            password = pw
        }
    }

    func saveConnection() {
        do {
            try settings.save()
            if !secretKey.isEmpty {
                try CredentialStore.saveSharedOrLocal(secretKey, account: AppIdentifiers.secretKeyAccount)
            }
            if !password.isEmpty {
                try CredentialStore.saveSharedOrLocal(password, account: AppIdentifiers.passwordAccount)
            }
            statusMessage = "Connection saved (secrets in Keychain)."
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func unlock() async {
        phase = .unlocking
        statusMessage = "Unlocking…"
        previewText = nil
        do {
            let store = try makeStore()
            let location: VaultLocation
            if settings.isLocal {
                location = .local(prefix: "")
            } else {
                guard let endpoint = URL(string: settings.endpoint),
                      endpoint.scheme?.lowercased() == "https"
                else {
                    throw UnlockError.httpsRequired
                }
                location = VaultLocation(
                    endpoint: endpoint,
                    region: settings.region,
                    bucket: settings.bucket,
                    prefix: settings.normalizedPrefix,
                    accessKey: settings.accessKey
                )
            }
            let session = try await VaultSession.unlock(
                location: location,
                passphrase: password,
                store: store
            )
            self.session = session
            pathStack = []
            try await reloadListing()
            saveConnection()
            phase = .browsing
            statusMessage = "Unlocked (format \(session.config.format))."
        } catch {
            session = nil
            nodes = []
            phase = .error(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func lock() {
        session = nil
        nodes = []
        pathStack = []
        previewText = nil
        phase = .locked
        statusMessage = "Locked."
    }

    func enterDirectory(_ node: VaultNode) async {
        guard node.kind == .directory, let dirId = node.dirId else { return }
        pathStack.append((node.cleartextName, dirId))
        do {
            try await reloadListing()
        } catch {
            statusMessage = error.localizedDescription
            _ = pathStack.popLast()
        }
    }

    func goUp() async {
        guard !pathStack.isEmpty else { return }
        _ = pathStack.popLast()
        do {
            try await reloadListing()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openFile(_ node: VaultNode) async {
        guard let session, node.kind == .file else { return }
        statusMessage = "Decrypting \(node.cleartextName)…"
        do {
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("cryptomako-open-\(UUID().uuidString)-\(node.cleartextName)")
            try await session.fetch(node: node, to: dest)
            if let text = try? String(contentsOf: dest, encoding: .utf8), text.utf8.count < 512_000 {
                previewTitle = node.cleartextName
                previewText = text
                statusMessage = "Opened \(node.cleartextName)"
            } else {
                previewTitle = node.cleartextName
                previewText = "(binary or large file — saved to temp)\n\(dest.path)"
                statusMessage = "Downloaded \(node.cleartextName)"
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func writeStubMessage() -> String {
        "Writes are fail-closed in M1. Create / upload / delete land in M2."
    }

    private func reloadListing() async throws {
        guard let session else { return }
        let listed = try await session.list(dirId: currentDirId)
        nodes = listed.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .directory && rhs.kind != .directory
            }
            return lhs.cleartextName.localizedCaseInsensitiveCompare(rhs.cleartextName) == .orderedAscending
        }
    }

    private func makeStore() throws -> any ObjectStore {
        if settings.isLocal {
            let path = settings.localVaultPath
            guard !path.isEmpty else { throw UnlockError.missingLocalPath }
            return DirectoryObjectStore(root: URL(fileURLWithPath: path))
        }
        guard let endpoint = URL(string: settings.endpoint),
              endpoint.scheme?.lowercased() == "https"
        else {
            throw UnlockError.httpsRequired
        }
        guard !settings.bucket.isEmpty, !settings.accessKey.isEmpty, !secretKey.isEmpty else {
            throw UnlockError.incompleteS3
        }
        return S3ObjectStore(
            settings: S3Settings(
                endpoint: endpoint,
                region: settings.region.isEmpty ? "us-east-1" : settings.region,
                bucket: settings.bucket,
                accessKey: settings.accessKey,
                secretKey: secretKey,
                pathStyle: true
            )
        )
    }
}

enum UnlockError: Error, LocalizedError {
    case httpsRequired
    case incompleteS3
    case missingLocalPath

    var errorDescription: String? {
        switch self {
        case .httpsRequired:
            return "S3 endpoint must be https:// (ATS / HTTPS-only)."
        case .incompleteS3:
            return "Fill endpoint, bucket, access key, and secret key."
        case .missingLocalPath:
            return "Local vault path is empty."
        }
    }
}
