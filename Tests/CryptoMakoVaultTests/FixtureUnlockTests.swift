import CryptoMakoS3
import Foundation
import XCTest

@testable import CryptoMakoVault

/// Unlocks the golden fixtures vault when `fixtures/vault` + `fixtures/PASSWORD` exist
/// (gitignored; copy from the macOS sibling). Skips cleanly otherwise.
final class FixtureUnlockTests: XCTestCase {
    func testUnlockAndListMatchesExpected() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/CryptoMakoVaultTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let vaultURL = root.appendingPathComponent("fixtures/vault")
        let passwordURL = root.appendingPathComponent("fixtures/PASSWORD")
        let expectedURL = root.appendingPathComponent("fixtures/expected-ls.txt")

        guard FileManager.default.fileExists(atPath: vaultURL.path),
              FileManager.default.fileExists(atPath: passwordURL.path)
        else {
            throw XCTSkip("fixtures/vault + fixtures/PASSWORD not present; copy from ../cryptomako/fixtures")
        }

        let password = try String(contentsOf: passwordURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let store = DirectoryObjectStore(root: vaultURL)
        let session = try await VaultSession.unlock(
            location: .local(),
            passphrase: password,
            store: store
        )
        XCTAssertEqual(session.config.format, 8)

        let listed = try await session.listRecursive(at: "/", maxEntries: 500)
        let paths = Set(listed.map { path, node in
            node.kind == .directory ? (path.hasSuffix("/") ? path : path + "/") : path
        })

        // Always assert core entries from the golden vault.
        XCTAssertTrue(paths.contains("/hello.txt") || listed.contains(where: { $0.0 == "/hello.txt" }))
        XCTAssertTrue(listed.contains(where: { $0.0 == "/notes" || $0.0.hasPrefix("/notes") }))

        if FileManager.default.fileExists(atPath: expectedURL.path),
           let expected = try? String(contentsOf: expectedURL, encoding: .utf8)
        {
            let expectedPaths = Set(
                expected.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            )
            for entry in expectedPaths where entry != "/bin/" {
                // Directory entries in expected-ls use trailing slash; listRecursive may not.
                let bare = entry.hasSuffix("/") ? String(entry.dropLast()) : entry
                let ok = listed.contains { $0.0 == bare || $0.0 == entry || $0.0.hasPrefix(bare + "/") }
                XCTAssertTrue(ok, "missing expected entry \(entry)")
            }
        }
    }
}
