# CryptoMako iOS — milestones M0–M4

Sibling roadmap for [guillebot/cryptomako](https://github.com/guillebot/cryptomako) on iOS / iPadOS.

## M0 — Shared cores

- Port / share `CryptoMakoS3`, `CryptoMakoVault`, `CryptoMakoShared` with iOS bundle IDs / App Group:
  - App: `net.gschimmel.cryptomako.ios`
  - Group: `group.net.gschimmel.cryptomako.ios` (Swift `AppIdentifiers.appGroup`)
  - Keychain access group: `H4K6YW7MQM.group.net.gschimmel.cryptomako.ios`
- SPM platforms: **iOS 17+** (+ macOS for host `swift test`).

## M1 — Unlock + browse

- SwiftUI connection UI; unlock; list; navigate; download/open preview.
- Secrets in Keychain; HTTPS / ATS only for S3.

## M2 — Light writes ✅

- Create folder, upload files (`fileImporter`), delete with confirm.
- Success only after remote `putObject` / `deleteObject` (or DirectoryObjectStore commit in local mode).
- Listing refresh after each write.

## M3 — Files provider + share ✅

- `CryptoMakoFileProvider` appex: enumerate unlocked vault, download on demand, fail-closed create/modify/delete (same remote-commit model as macOS).
- Domain registered after S3 unlock (`cryptomako.ios.<jti>`).
- Share extension stages into App Group `ShareInbox/`; host imports into current directory.

## M4 — On-device backup ✅

- Folder picker → walk → encrypt+put under `Backups/<name>/` with progress UI.
- Reuses `BackupSyncExcludes` (`.DS_Store`, `node_modules`, …). Not full macOS Backup Sync parity.

## Polish ✅

- App icon (from macOS Brand 1024).
- Privacy usage string + `PrivacyInfo.xcprivacy`.
- Marketing version **1.0.0**.
- Entitlements: App Groups + Keychain for app + File Provider; App Groups for Share.

## Non-goals

- Cleartext HTTP / disabling ATS.
- Treating local CloudStorage / Files materialization as durable backup.
- Inventing new `VaultSettings` JSON keys without Platforms review.

## App Store Connect (later run)

- Screenshots, ASC app record, distribution cert / profiles, privacy nutrition labels, export compliance.
