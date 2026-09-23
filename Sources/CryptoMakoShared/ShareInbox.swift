import Foundation

/// Files dropped by the Share extension into the App Group container.
/// The host app imports them into the current vault directory after unlock.
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
        // Security-scoped resources may need coordinated copy.
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: dest)
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
}
