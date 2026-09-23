# CryptoMako iOS — milestones M0–M4

Sibling roadmap for [guillebot/cryptomako](https://github.com/guillebot/cryptomako) on iOS / iPadOS.

## M0 — Shared cores

- Port / share `CryptoMakoS3` (SigV4, `URLSession`, `ObjectStore`, `DirectoryObjectStore`).
- Port / share `CryptoMakoVault` (Cryptomator format 8 via `cryptolib-swift`).
- Port / adapt `CryptoMakoShared` (Keychain `CredentialStore`, `VaultSettings`, prefs) with iOS bundle IDs / App Group:
  - App: `net.gschimmel.cryptomako.ios`
  - Group: `H4K6YW7MQM.group.net.gschimmel.cryptomako.ios`
- SPM `Package.swift` platforms: **iOS 17+** (plus macOS for host `swift test`).
- Golden fixtures copied from macOS `fixtures/` for local unlock+list (gitignored ciphertext + `PASSWORD`, same as macOS).

**Exit:** `swift test` green for SigV4 / vault memory-store tests; libraries compile for iOS.

## M1 — Unlock + browse (current bar)

- SwiftUI connection UI: endpoint, region, bucket, prefix, access key; local fixtures mode.
- Unlock with vault password; list cleartext names; navigate directories; download/open file preview.
- Secrets in Keychain only (`CredentialStore`).
- **HTTPS / ATS only** for S3 (cleartext endpoints rejected). Local mode uses `DirectoryObjectStore`.
- Writes **fail-closed**: UI messaging only; no create/upload/delete yet.

**Exit:** Unlock + list against local `fixtures/vault` matches `fixtures/expected-ls.txt` shapes; S3 unlock works against a real HTTPS endpoint.

## M2 — Light writes

- Create folder, upload small files, delete — only after remote S3 put/delete succeeds (fail-closed).
- Conflict / error surfaces in UI; no silent local-only success.

## M3 — Files provider + share

- `UIDocumentPicker` / Files provider extension (or equivalent) for browse outside the app.
- Share sheet import into vault (encrypt → S3 put).

## M4 — On-device backup

- Select on-device folders / photos subsets and sync into the vault (encrypt → parallel put), with excludes and optional bandwidth caps — analogous to macOS Backup Sync, sized for mobile.

## Non-goals (for now)

- macFUSE / Finder File Provider parity on iOS (different platform APIs).
- Cleartext HTTP / disabling ATS for “convenience” against LAN MinIO.
- Treating local CloudStorage materialization as durable backup.
- Replacing Cryptomator desktop; vaults remain format-8 interoperable.
- Shipping writes before remote commit confirmation (never).
