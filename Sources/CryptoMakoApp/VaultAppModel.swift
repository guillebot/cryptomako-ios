import Foundation
import SwiftUI
import FileProvider
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
    @Published var isBusy = false
    @Published var lastError: String?

    // M4 backup progress
    @Published var backupActive = false
    @Published var backupDone = 0
    @Published var backupTotal = 0
    @Published var backupCurrentName = ""
    @Published var backupSkipped = 0

    /// M2+: light writes are enabled; success only after remote put/delete.
    let writesEnabled = true

    private var session: VaultSession?
    private var registeredDomainID: String?
    private var backupTask: Task<Void, Never>?

    var currentDirId: String {
        pathStack.last?.dirId ?? ""
    }

    var currentPathLabel: String {
        if pathStack.isEmpty { return "/" }
        return "/" + pathStack.map(\.name).joined(separator: "/")
    }

    var isUnlocked: Bool {
        if case .browsing = phase { return true }
        return false
    }

    init() {
        settings = VaultSettings.load() ?? VaultSettings()
        if let secret = try? CredentialStore.readSharedOrLocal(account: AppIdentifiers.secretKeyAccount) {
            secretKey = secret
        }
        if let pw = try? CredentialStore.readSharedOrLocal(account: AppIdentifiers.passwordAccount) {
            password = pw
        }
        _ = ShareInbox.purgeStale()
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
            lastError = error.localizedDescription
        }
    }

    func unlock() async {
        phase = .unlocking
        statusMessage = "Unlocking…"
        previewText = nil
        lastError = nil
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
            await registerFileProviderDomainIfNeeded()
            _ = ShareInbox.purgeStale()
            await importShareInbox()
        } catch {
            session = nil
            nodes = []
            phase = .error(error.localizedDescription)
            statusMessage = error.localizedDescription
            lastError = error.localizedDescription
        }
    }

    func lock() {
        backupTask?.cancel()
        backupTask = nil
        backupActive = false
        session = nil
        nodes = []
        pathStack = []
        previewText = nil
        previewTitle = nil
        phase = .locked
        statusMessage = "Locked."
        // Drop in-process cleartext leftovers; Keychain secrets stay so Files can remount.
        Self.scrubOpenTemps()
        Task { await removeFileProviderDomains() }
    }

    func enterDirectory(_ node: VaultNode) async {
        guard node.kind == .directory, let dirId = node.dirId else { return }
        pathStack.append((node.cleartextName, dirId))
        do {
            try await reloadListing()
        } catch {
            statusMessage = error.localizedDescription
            lastError = error.localizedDescription
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
            lastError = error.localizedDescription
        }
    }

    func openFile(_ node: VaultNode) async {
        guard let session, node.kind == .file else { return }
        statusMessage = "Decrypting \(node.cleartextName)…"
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("cryptomako-open-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dest) }
        do {
            try await session.fetch(node: node, to: dest)
            // Prefer in-memory text preview; never leave cleartext on disk or show temp paths.
            if let text = try? String(contentsOf: dest, encoding: .utf8), text.utf8.count < 512_000 {
                previewTitle = node.cleartextName
                previewText = text
                statusMessage = "Opened \(node.cleartextName)"
            } else {
                previewTitle = node.cleartextName
                previewText = "(binary or large file — preview not shown; re-open via Files after unlock)"
                statusMessage = "Opened \(node.cleartextName) (binary — not cached)"
            }
        } catch {
            statusMessage = error.localizedDescription
            lastError = error.localizedDescription
        }
    }

    // MARK: - M2 Writes (fail-closed)

    func createFolder(named rawName: String) async {
        guard writesEnabled, let session else { return }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            statusMessage = "Folder name is empty."
            return
        }
        isBusy = true
        statusMessage = "Creating folder \(name)…"
        defer { isBusy = false }
        do {
            _ = try await session.createDirectory(parentDirId: currentDirId, cleartextName: name)
            try await reloadListing()
            await signalFileProviderRefresh()
            statusMessage = "Created folder \(name)."
            lastError = nil
        } catch {
            statusMessage = "Create folder failed: \(error.localizedDescription)"
            lastError = error.localizedDescription
        }
    }

    func uploadFiles(from urls: [URL]) async {
        guard writesEnabled, let session else { return }
        guard !urls.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        var ok = 0
        var failed: [String] = []
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            statusMessage = "Uploading \(name)…"
            do {
                _ = try await session.createOrOverwriteFile(
                    parentDirId: currentDirId,
                    cleartextName: name,
                    contentsURL: url
                )
                ok += 1
            } catch {
                failed.append("\(name): \(error.localizedDescription)")
            }
        }
        do {
            try await reloadListing()
            await signalFileProviderRefresh()
        } catch {
            failed.append(error.localizedDescription)
        }
        if failed.isEmpty {
            statusMessage = "Uploaded \(ok) file(s)."
            lastError = nil
        } else {
            let msg = "Uploaded \(ok); failed: \(failed.joined(separator: "; "))"
            statusMessage = msg
            lastError = msg
        }
    }

    func deleteNode(_ node: VaultNode) async {
        guard writesEnabled, let session else { return }
        isBusy = true
        statusMessage = "Deleting \(node.cleartextName)…"
        defer { isBusy = false }
        do {
            try await session.deleteNode(node)
            try await reloadListing()
            await signalFileProviderRefresh()
            statusMessage = "Deleted \(node.cleartextName)."
            lastError = nil
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
            lastError = error.localizedDescription
        }
    }

    // MARK: - M3 Share inbox

    func importShareInbox() async {
        guard writesEnabled, let session else { return }
        let staged = ShareInbox.listStaged()
        guard !staged.isEmpty else { return }
        isBusy = true
        defer { isBusy = false }
        var ok = 0
        for url in staged {
            // Strip the UUID- prefix added by ShareInbox.stage
            let display = displayNameFromStaged(url)
            statusMessage = "Importing shared \(display)…"
            do {
                _ = try await session.createOrOverwriteFile(
                    parentDirId: currentDirId,
                    cleartextName: display,
                    contentsURL: url
                )
                ShareInbox.remove(url)
                ok += 1
            } catch {
                statusMessage = "Share import failed for \(display): \(error.localizedDescription)"
                lastError = error.localizedDescription
            }
        }
        if ok > 0 {
            do { try await reloadListing() } catch {
                lastError = error.localizedDescription
            }
            await signalFileProviderRefresh()
            statusMessage = "Imported \(ok) shared file(s) into \(currentPathLabel)."
        }
    }

    private func displayNameFromStaged(_ url: URL) -> String {
        let base = url.lastPathComponent
        if let dash = base.firstIndex(of: "-"), dash > base.startIndex {
            let after = base.index(after: dash)
            let rest = String(base[after...])
            if !rest.isEmpty { return rest }
        }
        return base
    }

    // MARK: - M4 On-device backup

    func cancelBackup() {
        backupTask?.cancel()
        backupTask = nil
        backupActive = false
        statusMessage = "Backup cancelled."
    }

    func backupFolder(at rootURL: URL) {
        guard writesEnabled, session != nil else { return }
        backupTask?.cancel()
        backupActive = true
        backupDone = 0
        backupTotal = 0
        backupSkipped = 0
        backupCurrentName = ""
        statusMessage = "Scanning \(rootURL.lastPathComponent)…"

        backupTask = Task { [weak self] in
            guard let self else { return }
            let accessed = rootURL.startAccessingSecurityScopedResource()
            defer { if accessed { rootURL.stopAccessingSecurityScopedResource() } }
            do {
                try await self.runBackup(from: rootURL)
            } catch is CancellationError {
                await MainActor.run {
                    self.backupActive = false
                    self.statusMessage = "Backup cancelled."
                }
            } catch {
                await MainActor.run {
                    self.backupActive = false
                    self.statusMessage = "Backup failed: \(error.localizedDescription)"
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func runBackup(from rootURL: URL) async throws {
        guard let session else { return }
        let excludes = BackupSyncExcludesStore.load()
        let folderName = rootURL.lastPathComponent.isEmpty ? "Backup" : rootURL.lastPathComponent
        let vaultRoot = "Backups/\(folderName)"

        // Collect files first for progress total.
        var files: [(relative: String, url: URL)] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else {
            throw UnlockError.missingLocalPath
        }

        while let item = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            let rel = item.path.replacingOccurrences(of: rootURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if values.isDirectory == true {
                if excludes.shouldSkipDirectory(named: item.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            if excludes.shouldSkipRelativePath(rel) || excludes.shouldSkipFile(named: item.lastPathComponent) {
                backupSkipped += 1
                continue
            }
            files.append((rel, item))
            backupTotal = files.count
            backupCurrentName = rel
        }

        backupTotal = files.count
        if files.isEmpty {
            backupActive = false
            statusMessage = "Nothing to back up (all excluded or empty)."
            return
        }

        // Ensure Backups/<folder>/… directory tree on demand per file parent.
        var dirCache: [String: String] = ["": try await session.ensureDirectoryPath(vaultRoot)]

        for (index, entry) in files.enumerated() {
            try Task.checkCancellation()
            backupCurrentName = entry.relative
            backupDone = index
            statusMessage = "Backing up \(index + 1)/\(files.count): \(entry.relative)"

            let parentRel = (entry.relative as NSString).deletingLastPathComponent
            let parentKey = parentRel == "." ? "" : parentRel
            let parentDirId: String
            if let cached = dirCache[parentKey] {
                parentDirId = cached
            } else {
                let path = parentKey.isEmpty ? vaultRoot : "\(vaultRoot)/\(parentKey)"
                parentDirId = try await session.ensureDirectoryPath(path)
                dirCache[parentKey] = parentDirId
            }

            let name = (entry.relative as NSString).lastPathComponent
            _ = try await session.createOrOverwriteFile(
                parentDirId: parentDirId,
                cleartextName: name,
                contentsURL: entry.url
            )
            backupDone = index + 1
        }

        try await reloadListing()
        await signalFileProviderRefresh()
        backupActive = false
        statusMessage = "Backup done: \(backupDone) file(s), skipped \(backupSkipped)."
        lastError = nil
    }

    // MARK: - File Provider domain (M3)

    private func registerFileProviderDomainIfNeeded() async {
        // Files location is for remote S3 vaults; local fixtures stay in-app only.
        guard !settings.isLocal, let jti = session?.config.jti, !jti.isEmpty else { return }
        let id = AppIdentifiers.domainIdentifier(jti: jti)
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(id),
            displayName: "CryptoMako"
        )
        do {
            let existing = (try? await NSFileProviderManager.domains()) ?? []
            for d in existing where d.identifier.rawValue.hasPrefix("cryptomako.ios.") {
                try? await NSFileProviderManager.remove(d)
            }
            try await NSFileProviderManager.add(domain)
            registeredDomainID = id
            statusMessage += " Files location registered."
        } catch {
            // Non-fatal: unlock still succeeds; Files may need a device build + provisioning.
            statusMessage += " (Files provider: \(error.localizedDescription))"
        }
    }

    private func removeFileProviderDomains() async {
        let existing = (try? await NSFileProviderManager.domains()) ?? []
        for d in existing where d.identifier.rawValue.hasPrefix("cryptomako.ios.") {
            try? await NSFileProviderManager.remove(d)
        }
        registeredDomainID = nil
    }

    private func signalFileProviderRefresh() async {
        guard let id = registeredDomainID else { return }
        let domain = NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(id),
            displayName: "CryptoMako"
        )
        guard let manager = NSFileProviderManager(for: domain) else { return }
        try? await manager.signalEnumerator(for: .rootContainer)
        try? await manager.signalEnumerator(for: .workingSet)
    }

    // MARK: - Internals

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

    /// Best-effort wipe of host temp cleartext from open/preview.
    private static func scrubOpenTemps() {
        let tmp = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }
        for url in items where url.lastPathComponent.hasPrefix("cryptomako-open-")
            || url.lastPathComponent.hasPrefix("cryptomako-enc-")
            || url.lastPathComponent.hasPrefix("cryptomako-") && url.pathExtension == "out"
        {
            try? FileManager.default.removeItem(at: url)
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
