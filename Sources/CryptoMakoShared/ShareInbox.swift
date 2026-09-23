import Foundation

/// Files dropped by the Share extension into the App Group container.
/// The host app imports them into the current vault directory after unlock.
///
/// Security: contents are **cleartext** until imported+encrypted. The inbox is
/// excluded from device/iCloud backup, and stale entries are purged.
public enum ShareInbox {
    public static var directoryURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup)?
            .appendingPathComponent(AppIdentifiers.shareInboxFolderName, isDirectory: true)
    }

    public static func ensureDirectory() throws -> URL {
        guard let url = directoryURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        excludeFromBackup(url)
        return url
    }

    /// Copy a shared file into the inbox. Returns the destination URL.
    @discardableResult
    public static func stage(fileAt source: URL, preferredName: String? = nil) throws -> URL {
        let dir = try ensureDirectory()
        let name = preferredName ?? source.lastPathComponent
        let safe = name.isEmpty ? "shared-\(UUID().uuidString)" : name
        let dest = dir.appendingPathComponent("\(UUID().uuidString)-\(safe)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: dest)
        excludeFromBackup(dest)
        return dest
    }

    public static func listStaged() -> [URL] {
        guard let dir = directoryURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: dir,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              )
        else { return [] }
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    public static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Drop inbox files older than `maxAge` (default 24h). Call on host launch / unlock.
    @discardableResult
    public static func purgeStale(maxAge: TimeInterval = 24 * 60 * 60) -> Int {
        guard let dir = directoryURL else { return 0 }
        excludeFromBackup(dir)
        let cutoff = Date().addingTimeInterval(-maxAge)
        var removed = 0
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let modified = values?.contentModificationDate ?? cutoff
            if modified < cutoff {
                try? FileManager.default.removeItem(at: url)
                removed += 1
            }
        }
        return removed
    }

    private static func excludeFromBackup(_ url: URL) {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }
}
