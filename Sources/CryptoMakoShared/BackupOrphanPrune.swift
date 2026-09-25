import Foundation

/// Pure helpers for Sync-mode vault orphan prune scoping.
///
/// Orphan deletes are always relative to a single source's vault folder
/// (`Backups/<folder>/…`). They never target local / security-scoped source paths.
public enum BackupOrphanPrune {
    /// Cleartext vault prefix for `folderName`, always ending with `/`.
    public static func vaultFolderPrefix(_ folderName: String) -> String {
        let folder = folderName.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        precondition(!folder.isEmpty, "folderName required")
        return "Backups/\(folder)/"
    }

    /// True when `vaultCleartextPath` is exactly `Backups/<folder>` or under `Backups/<folder>/`.
    public static func isWithinVaultFolderScope(_ vaultCleartextPath: String, folderName: String) -> Bool {
        let folder = folderName.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
        guard !folder.isEmpty else { return false }
        let path = vaultCleartextPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let root = "Backups/\(folder)"
        return path == root || path.hasPrefix(root + "/")
    }

    /// Whether any eligible local relative path lives at or under `relDir`.
    /// Empty `relDir` is the folder root and always kept.
    public static func hasLocalUnder(relDir: String, localFiles: Set<String>) -> Bool {
        if relDir.isEmpty { return true }
        let prefix = relDir + "/"
        for path in localFiles where path == relDir || path.hasPrefix(prefix) {
            return true
        }
        return false
    }

    /// Vault-relative file is an orphan when missing from the eligible local set.
    public static func isOrphanFile(relPath: String, localFiles: Set<String>) -> Bool {
        !localFiles.contains(relPath)
    }

    /// Vault-relative file paths (relative to `Backups/<folder>/`) that should be deleted in Sync mode.
    public static func orphanFileRelPaths(
        vaultFileRelPaths: Set<String>,
        localEligibleRelPaths: Set<String>
    ) -> Set<String> {
        Set(vaultFileRelPaths.filter { isOrphanFile(relPath: $0, localFiles: localEligibleRelPaths) })
    }
}
