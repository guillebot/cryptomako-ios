import Foundation

/// Nested / overlapping Backup Sync sources (Platforms consensus with Windows / Android):
/// soft-warn on add; hard-fail on Sync start when one resolved path prefixes another.
///
/// Comparison uses absolute + symlink-resolved paths. On iOS, bookmarks restore access;
/// overlap checks still use the stored `path` / resolved URL path (id + displayName identify rows).
public enum BackupPathOverlap {
    public struct OverlapPair: Equatable, Sendable {
        public let resolvedA: String
        public let resolvedB: String
        public let displayNameA: String
        public let displayNameB: String

        public init(resolvedA: String, resolvedB: String, displayNameA: String, displayNameB: String) {
            self.resolvedA = resolvedA
            self.resolvedB = resolvedB
            self.displayNameA = displayNameA
            self.displayNameB = displayNameB
        }
    }

    public enum OverlapError: Error, LocalizedError, Equatable {
        case overlapping(resolvedA: String, resolvedB: String)

        public var errorDescription: String? {
            switch self {
            case .overlapping(let a, let b):
                return "Backup Sync refused: nested/overlapping sources. '\(a)' overlaps '\(b)'. Remove or change one source before syncing."
            }
        }
    }

    /// Resolve to a comparable absolute path (standardized + final symlink target when available).
    public static func resolve(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }
        var url = URL(fileURLWithPath: trimmed, isDirectory: true)
        url = url.resolvingSymlinksInPath().standardizedFileURL
        return trimTrailingSeparators(url.path)
    }

    public static func isSameOrPrefix(ancestor: String, descendant: String) -> Bool {
        let a = trimTrailingSeparators(ancestor)
        let b = trimTrailingSeparators(descendant)
        if a.caseInsensitiveCompare(b) == .orderedSame {
            return true
        }
        // Require a path-separator boundary so /Doc does not prefix /Documents.
        let prefix = a.hasSuffix("/") ? a : a + "/"
        return b.lowercased().hasPrefix(prefix.lowercased())
    }

    public static func findOverlaps(_ sources: [BackupSource]) -> [OverlapPair] {
        var resolved: [(BackupSource, String)] = []
        for source in sources {
            let path = source.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            do {
                resolved.append((source, try resolve(path)))
            } catch {
                // Skip unresolvable for soft paths; Sync will fail separately on missing folders.
            }
        }

        var pairs: [OverlapPair] = []
        for i in 0..<resolved.count {
            for j in (i + 1)..<resolved.count {
                let (sa, pa) = resolved[i]
                let (sb, pb) = resolved[j]
                if isSameOrPrefix(ancestor: pa, descendant: pb)
                    || isSameOrPrefix(ancestor: pb, descendant: pa)
                {
                    pairs.append(
                        OverlapPair(
                            resolvedA: pa,
                            resolvedB: pb,
                            displayNameA: sa.displayName,
                            displayNameB: sb.displayName
                        )
                    )
                }
            }
        }
        return pairs
    }

    /// Human soft-warn when adding `candidatePath` beside existing sources. Still allow the add.
    public static func softWarnOnAdd(existing: [BackupSource], candidatePath: String) -> String? {
        let candidate = BackupSource(path: candidatePath)
        guard let first = findOverlaps(existing + [candidate]).first else { return nil }
        return "Warning: backup source overlaps another (nested paths). '\(first.resolvedA)' ↔ '\(first.resolvedB)'. Sync will refuse to start until resolved."
    }

    /// Hard-fail before Sync when any pair overlaps.
    public static func throwIfOverlapping(_ sources: [BackupSource]) throws {
        guard let first = findOverlaps(sources).first else { return }
        throw OverlapError.overlapping(resolvedA: first.resolvedA, resolvedB: first.resolvedB)
    }

    public static func overlapErrorMessage(_ sources: [BackupSource]) -> String? {
        guard let first = findOverlaps(sources).first else { return nil }
        return OverlapError.overlapping(resolvedA: first.resolvedA, resolvedB: first.resolvedB).errorDescription
    }

    private static func trimTrailingSeparators(_ path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") {
            p.removeLast()
        }
        return p
    }
}
