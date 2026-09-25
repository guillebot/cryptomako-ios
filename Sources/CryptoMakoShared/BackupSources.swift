import Foundation

/// Local folders the user wants synced into the vault (backup sources).
///
/// Persisted as app-group JSON (`backup-sources.json`). iOS keeps a security-scoped
/// bookmark so the folder can be re-accessed later; `displayName` is the cleartext
/// folder name under `Backups/` (Android `displayName` / desktop `vaultFolderName`).
public struct BackupSource: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var path: String
    /// Cleartext folder name under `Backups/` in the vault.
    public var vaultFolderName: String
    public var addedAt: Date
    /// Security-scoped bookmark for the picked folder (optional for legacy entries).
    public var bookmarkData: Data?

    /// Platforms alias for the vault folder label (Android `displayName`).
    public var displayName: String {
        get { vaultFolderName }
        set { vaultFolderName = newValue.isEmpty ? "Backup" : newValue }
    }

    public init(
        id: String = UUID().uuidString,
        path: String,
        vaultFolderName: String? = nil,
        displayName: String? = nil,
        addedAt: Date = Date(),
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.path = path
        let name = displayName ?? vaultFolderName ?? URL(fileURLWithPath: path).lastPathComponent
        self.vaultFolderName = name.isEmpty ? "Backup" : name
        self.addedAt = addedAt
        self.bookmarkData = bookmarkData
    }

    enum CodingKeys: String, CodingKey {
        case id, path, vaultFolderName, addedAt, bookmarkData
        case displayName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        path = try c.decode(String.self, forKey: .path)
        if let v = try c.decodeIfPresent(String.self, forKey: .vaultFolderName), !v.isEmpty {
            vaultFolderName = v
        } else if let d = try c.decodeIfPresent(String.self, forKey: .displayName), !d.isEmpty {
            vaultFolderName = d
        } else {
            let fallback = URL(fileURLWithPath: path).lastPathComponent
            vaultFolderName = fallback.isEmpty ? "Backup" : fallback
        }
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        bookmarkData = try c.decodeIfPresent(Data.self, forKey: .bookmarkData)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(path, forKey: .path)
        try c.encode(vaultFolderName, forKey: .vaultFolderName)
        try c.encode(vaultFolderName, forKey: .displayName)
        try c.encode(addedAt, forKey: .addedAt)
        try c.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
    }
}

public struct BackupSourcesStore: Codable, Equatable, Sendable {
    public var sources: [BackupSource]

    public init(sources: [BackupSource]) {
        self.sources = sources
    }

    public static let empty = BackupSourcesStore(sources: [])

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup)?
            .appendingPathComponent("backup-sources.json")
    }

    public static func load() -> BackupSourcesStore {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(BackupSourcesStore.self, from: data)
        else {
            return .empty
        }
        return store
    }

    public func save() throws {
        guard let url = Self.fileURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Soft-warn on nested overlap; still persists the add (Platforms consensus).
    /// Returns `(source, alreadyListed, softWarn)`.
    public mutating func addSource(
        path: String,
        displayName: String? = nil,
        bookmarkData: Data? = nil
    ) -> (source: BackupSource, alreadyListed: Bool, softWarn: String?) {
        let candidateResolved = (try? BackupPathOverlap.resolve(path)) ?? path
        if let existing = sources.first(where: {
            ((try? BackupPathOverlap.resolve($0.path)) ?? $0.path) == candidateResolved
        }) {
            return (existing, true, nil)
        }
        let candidate = BackupSource(
            path: path,
            displayName: displayName,
            bookmarkData: bookmarkData
        )
        let warn = BackupPathOverlap.softWarnOnAdd(existing: sources, candidatePath: path)
        sources.append(candidate)
        return (candidate, false, warn)
    }

    public mutating func removeSource(id: String) {
        sources.removeAll { $0.id == id }
    }
}
