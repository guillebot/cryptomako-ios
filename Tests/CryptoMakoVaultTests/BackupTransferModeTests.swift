import XCTest
@testable import CryptoMakoShared

final class BackupTransferModeTests: XCTestCase {
    func testPrefsKeyAndDefaultAreBackup() {
        XCTAssertEqual(AppPreferences.BackupTransferMode.backup.rawValue, "backup")
        XCTAssertEqual(AppPreferences.BackupTransferMode.sync.rawValue, "sync")
        XCTAssertEqual(AppPreferences().backupTransferMode, .backup)
    }

    func testDecodeMissingKeyDefaultsToBackup() throws {
        // Omit backupTransferMode — decoder must default to .backup.
                let json = Data(#"""
        {
          "proxyMode": "system",
          "proxyHost": "",
          "proxyPort": 8080,
          "proxyUsername": "",
          "limitSyncUploadBandwidth": false,
          "syncUploadCapMbps": 50,
          "syncSmallPutConcurrency": 96,
          "syncMediumPutConcurrency": 32,
          "syncLargePutConcurrency": 4
        }
        """#.utf8)
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: json)
        XCTAssertEqual(prefs.backupTransferMode, .backup)
    }

    func testDecodeSyncRoundTrip() throws {
        var prefs = AppPreferences()
        prefs.backupTransferMode = .sync
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(decoded.backupTransferMode, .sync)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(object["backupTransferMode"] as? String, "sync")
    }
}

final class BackupOrphanPruneTests: XCTestCase {
    func testVaultFolderPrefixScopesUnderBackupsFolder() {
        XCTAssertEqual(BackupOrphanPrune.vaultFolderPrefix("Photos"), "Backups/Photos/")
        XCTAssertEqual(BackupOrphanPrune.vaultFolderPrefix(" /Device/ "), "Backups/Device/")
    }

    func testIsWithinVaultFolderScopeAcceptsOnlyThatFolder() {
        XCTAssertTrue(BackupOrphanPrune.isWithinVaultFolderScope("Backups/Photos", folderName: "Photos"))
        XCTAssertTrue(BackupOrphanPrune.isWithinVaultFolderScope("Backups/Photos/a.txt", folderName: "Photos"))
        XCTAssertTrue(BackupOrphanPrune.isWithinVaultFolderScope("Backups/Photos/nested/b.txt", folderName: "Photos"))
        XCTAssertFalse(BackupOrphanPrune.isWithinVaultFolderScope("Backups/Other/a.txt", folderName: "Photos"))
        XCTAssertFalse(BackupOrphanPrune.isWithinVaultFolderScope("Backups/PhotosExtra/a.txt", folderName: "Photos"))
        XCTAssertFalse(BackupOrphanPrune.isWithinVaultFolderScope("hello.txt", folderName: "Photos"))
        // Never treat absolute / URI source paths as in-scope vault orphans.
        XCTAssertFalse(BackupOrphanPrune.isWithinVaultFolderScope("/Users/guille/Photos/a.txt", folderName: "Photos"))
        XCTAssertFalse(BackupOrphanPrune.isWithinVaultFolderScope("file:///tmp/Photos/a.txt", folderName: "Photos"))
    }

    func testHasLocalUnderEmptyRootAlwaysKept() {
        XCTAssertTrue(BackupOrphanPrune.hasLocalUnder(relDir: "", localFiles: []))
        XCTAssertTrue(BackupOrphanPrune.hasLocalUnder(relDir: "", localFiles: ["a.txt"]))
    }

    func testHasLocalUnderDetectsChildren() {
        let local: Set<String> = ["docs/readme.md", "docs/deep/x.txt", "root.txt"]
        XCTAssertTrue(BackupOrphanPrune.hasLocalUnder(relDir: "docs", localFiles: local))
        XCTAssertTrue(BackupOrphanPrune.hasLocalUnder(relDir: "docs/deep", localFiles: local))
        XCTAssertFalse(BackupOrphanPrune.hasLocalUnder(relDir: "docs/missing", localFiles: local))
        XCTAssertFalse(BackupOrphanPrune.hasLocalUnder(relDir: "other", localFiles: local))
        // partial segment must not match
        XCTAssertFalse(BackupOrphanPrune.hasLocalUnder(relDir: "doc", localFiles: local))
    }

    func testOrphanFileRelPathsOnlyVaultRelativesMissingLocally() {
        let vault: Set<String> = ["keep.txt", "gone.txt", "nested/old.txt", "nested/keep.txt"]
        let local: Set<String> = ["keep.txt", "nested/keep.txt", "new-local-only.txt"]
        let orphans = BackupOrphanPrune.orphanFileRelPaths(
            vaultFileRelPaths: vault,
            localEligibleRelPaths: local
        )
        XCTAssertEqual(orphans, ["gone.txt", "nested/old.txt"])
        XCTAssertTrue(orphans.allSatisfy { !$0.hasPrefix("/") })
        XCTAssertTrue(orphans.allSatisfy { !$0.hasPrefix("Backups/") })
    }

    func testBackupModeSemanticsOrphanHelperUnusedImpliesNoDeletes() {
        let vault: Set<String> = ["extra-in-vault.txt"]
        let local: Set<String> = []
        XCTAssertEqual(
            BackupOrphanPrune.orphanFileRelPaths(vaultFileRelPaths: vault, localEligibleRelPaths: local),
            ["extra-in-vault.txt"]
        )
        XCTAssertEqual(AppPreferences.BackupTransferMode.backup, AppPreferences().backupTransferMode)
    }
}

final class BackupPathOverlapTests: XCTestCase {
    private var scratchRoots: [URL] = []

    override func tearDown() {
        let fm = FileManager.default
        for root in scratchRoots {
            try? fm.removeItem(at: root)
        }
        scratchRoots.removeAll()
        super.tearDown()
    }

    private func makeTempDir(_ name: String = "cm-overlap") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        scratchRoots.append(url)
        return url
    }

    func testResolveReturnsAbsolutePath() throws {
        let dir = makeTempDir()
        let resolved = try BackupPathOverlap.resolve(dir.path)
        XCTAssertFalse(resolved.hasSuffix("/"))
        let expected = dir.resolvingSymlinksInPath().standardizedFileURL.path
        XCTAssertEqual(expected.lowercased(), resolved.lowercased())
    }

    func testSoftWarnOnAddWhenNestedUnderExisting() throws {
        let root = makeTempDir("cm-ov-root")
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let existing = [BackupSource(path: root.path, displayName: "Root")]
        let warn = BackupPathOverlap.softWarnOnAdd(existing: existing, candidatePath: child.path)
        XCTAssertNotNil(warn)
        XCTAssertTrue(warn!.localizedCaseInsensitiveContains("overlap"))
    }

    func testSoftWarnOnAddNilWhenDisjoint() throws {
        let a = makeTempDir("cm-ov-a")
        let b = makeTempDir("cm-ov-b")
        let existing = [BackupSource(path: a.path, displayName: "A")]
        XCTAssertNil(BackupPathOverlap.softWarnOnAdd(existing: existing, candidatePath: b.path))
    }

    func testThrowIfOverlappingWhenParentAndChild() throws {
        let root = makeTempDir("cm-ov-hard")
        let child = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let sources = [
            BackupSource(path: root.path, displayName: "Root"),
            BackupSource(path: child.path, displayName: "Child"),
        ]
        XCTAssertThrowsError(try BackupPathOverlap.throwIfOverlapping(sources)) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.localizedCaseInsensitiveContains("refused"))
        }
    }

    func testThrowIfOverlappingAllowsSiblings() throws {
        let root = makeTempDir("cm-ov-sib")
        let a = root.appendingPathComponent("a", isDirectory: true)
        let b = root.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let sources = [
            BackupSource(path: a.path, displayName: "A"),
            BackupSource(path: b.path, displayName: "B"),
        ]
        XCTAssertNoThrow(try BackupPathOverlap.throwIfOverlapping(sources))
    }

    func testIsSameOrPrefixCaseInsensitive() {
        XCTAssertTrue(BackupPathOverlap.isSameOrPrefix(
            ancestor: "/Users/Guille/Docs",
            descendant: "/users/guille/docs/nested"
        ))
        XCTAssertFalse(BackupPathOverlap.isSameOrPrefix(
            ancestor: "/Users/guille/docs",
            descendant: "/Users/guille/docs-other"
        ))
    }

    func testAddSourceSoftWarnStillPersists() {
        let root = makeTempDir("cm-ov-add")
        let child = root.appendingPathComponent("nested", isDirectory: true)
        try! FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        var store = BackupSourcesStore(sources: [BackupSource(path: root.path, displayName: "Root")])
        let result = store.addSource(path: child.path, displayName: "Child")
        XCTAssertFalse(result.alreadyListed)
        XCTAssertNotNil(result.softWarn)
        XCTAssertEqual(store.sources.count, 2)
        XCTAssertEqual(result.source.displayName, "Child")
        XCTAssertFalse(result.source.id.isEmpty)
        XCTAssertNil(result.source.bookmarkData)
    }
}
