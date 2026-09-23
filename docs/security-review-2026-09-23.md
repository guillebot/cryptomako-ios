# CryptoMako iOS security review — 2026-09-23

Focus: **(1) S3 credentials** and **(2) vault passphrase / masterkey**.  
Repo: `guillebot/cryptomako-ios` (review against `e58bd0a` + hardening commit below).  
Scope: iOS sibling only; macOS `cryptomako` not modified.

## Critical

_None found that are exploitable with current architecture without already compromising the device Keychain / App Group entitlements._

## High

### H1 — Cleartext open/preview temps left on disk + path shown in UI
- **Why:** `VaultAppModel.openFile` wrote decrypted bytes under `tmp/cryptomako-open-…-<filename>` and, for binary files, put the **absolute temp path** into `previewText`. Temps survived until OS purge; Lock did not scrub them.
- **Refs:** `Sources/CryptoMakoApp/VaultAppModel.swift` (`openFile`, formerly ~165–185).
- **Impact:** Local attacker / forensic imaging / mis-shared screenshots could recover vault cleartext or learn paths.
- **Fixed:** **Y** — decrypt to anonymous temp, load text into memory, `defer` delete; binary preview no longer shows paths; `lock()` scrubs `cryptomako-open-*` / related temps.

### H2 — ShareInbox cleartext in App Group without backup exclusion / TTL
- **Why:** Share extension stages **plaintext** files into `group.net.gschimmel.cryptomako.ios/ShareInbox/`. App Group containers are eligible for device backup; files remained until successful import.
- **Refs:** `Sources/CryptoMakoShared/ShareInbox.swift`; `Sources/CryptoMakoShare/ShareViewController.swift`.
- **Impact:** Cleartext shared documents could land in iCloud/computer backups; stale shares linger if the host never unlocks.
- **Fixed:** **Y** — `isExcludedFromBackup` on inbox dir/files; `purgeStale(maxAge: 24h)` on app init and unlock; import still deletes on success.

### H3 — S3 error strings appended raw HTTP bodies (log/UI amplification)
- **Why:** `S3ObjectStore.check` embedded up to 512 bytes of response body into thrown `ObjectStoreError.transport` messages; File Provider logs `error.localizedDescription` at `.public`.
- **Refs:** `Sources/CryptoMakoS3/S3ObjectStore.swift` (`check`); `Sources/CryptoMakoFileProvider/*.swift` (`log.error`).
- **Impact:** Unlikely to contain SigV4 secrets (Authorization not in body), but could amplify bucket/key/XML into unified logs.
- **Fixed:** **Y** — status/key only; no body echo. Request signing still never logged (`describe` comment preserved).

## Medium

### M1 — UI “Lock” does not wipe Keychain passphrase / S3 secret
- **Why:** `lock()` nils `VaultSession` (in-process masterkey) and removes the File Provider domain, but **does not** `CredentialStore.delete` and leaves `@Published password` / `secretKey` populated for the connection form.
- **Refs:** `VaultAppModel.lock`; `CredentialStore` accounts `vault-password`, `s3-secret-key`.
- **Impact:** By design for Files remount, but a user who expects “Lock” to forget secrets is wrong. Device unlock after first unlock still allows FP to re-read Keychain (`AfterFirstUnlockThisDeviceOnly`).
- **Fixed:** N — document; recommend optional “Forget credentials” control (follow-up).

### M2 — S3 access key ID stored in App Group `settings.json`
- **Why:** `VaultSettings` persists non-secret fields including `accessKey` to the App Group for the File Provider; **secret key** correctly stays in Keychain.
- **Refs:** `VaultSettings.swift` `save()` / `appGroupConfigURL`; `AppIdentifiers.appGroup`.
- **Impact:** Access key ID is an account identifier (not the secret). Combined with other leaks it aids targeting. Acceptable; do not put secret/passphrase in this JSON.
- **Fixed:** N.

### M3 — Unlocked masterkey lifetime in host + File Provider processes
- **Why:** `VaultSession` holds `private let masterkey: Masterkey` for the session; FP `VaultIndex` caches `VaultSession` until domain invalidate. Swift `String` passphrase copies are not zeroized.
- **Refs:** `VaultSession.swift`; `VaultIndex.swift`.
- **Impact:** Memory disclosure (debugger, JAILBREAK, cold-boot on unlocked device) can expose masterkey material while unlocked. No Secure Enclave wrapping.
- **Fixed:** N — residual; architecture follow-up (lock timing, optional biometric gate before Keychain read).

### M4 — File Provider independently unlocks from Keychain
- **Why:** FP does not receive masterkey over IPC; it reads passphrase + S3 secret from the shared Keychain access group and unlocks in-process. Host “Lock” removes the domain (good) but credentials remain.
- **Refs:** `VaultIndex.unlock`; entitlements `keychain-access-groups`.
- **Impact:** Correct for Files UX; increases value of Keychain compromise. No plaintext masterkey in App Group (positive).
- **Fixed:** N.

### M5 — Backup folder walk reads cleartext from user-chosen trees
- **Why:** M4 backup encrypts via `createOrOverwriteFile` (cipher temp deleted with `defer`); sources remain user files on disk.
- **Refs:** `VaultAppModel.runBackup`; `VaultSession+Writes.createOrOverwriteFile`.
- **Impact:** Expected; metadata (filenames) appear as vault cleartext names under `Backups/`. Excludes reduce junk only.
- **Fixed:** N.

## Low

### L1 — Keychain accessibility `AfterFirstUnlockThisDeviceOnly`
- Needed so File Provider can work after first unlock without prompting. Broader than `WhenUnlockedThisDeviceOnly` (no FP while device locked after boot). Documented tradeoff.
- **Refs:** `CredentialStore.saveDataProtection`.

### L2 — Classic Keychain migration / unsigned fallback paths
- `saveClassicFallback` / `readClassicFallback` for `swift test` without entitlements. On signed device builds, DP + access group path is primary.
- **Refs:** `CredentialStore.swift`.

### L3 — IPA `strings` show Keychain account names / bundle IDs / “masterkey” symbols
- No fixture password, no live secrets, no `http://` endpoints in Release IPA sampled `build/export-ipa/CryptoMako.ipa`.
- **Refs:** binary strings audit 2026-09-23.

### L4 — Share extension temp copies before stage
- Short-lived temps in appex container; staged copy is the durable risk (addressed in H2).

## Positive controls

- Secrets (**S3 secret**, **vault passphrase**, proxy password) in **Keychain**, not App Group JSON.
- `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` + data-protection Keychain + team-prefixed access group shared only with FP.
- **No** `NSAllowsArbitraryLoads` / ATS exceptions; host + `S3ObjectStore` **require `https://`** (precondition + unlock gate).
- `URLSessionConfiguration.ephemeral`, cache disabled for vault objects (avoids stale `masterkey.cryptomator` in URLCache).
- SigV4: comment + `describe(error)` **never** logs `URLRequest` / Authorization.
- FP refuses **local** storage mode (no Files over local cleartext store).
- Write path cipher temps deleted via `defer`; `cat` clears temp cleartext.
- `fixtures/PASSWORD` + `fixtures/vault/` **gitignored**; not in IPA strings.
- Share appex has App Group only — **no** Keychain entitlement (cannot read vault password).
- Fail-closed remote writes (success only after put/delete).

## Residual risk / follow-ups

1. Add **Forget credentials** (Keychain delete + clear UI fields) distinct from Lock.
2. Optional **biometric** (`LAContext`) before Keychain read / unlock.
3. Consider `WhenUnlockedThisDeviceOnly` if product drops background FP unlock (breaks Files when locked).
4. Memory hardening (passphrase as `Data` + explicit overwrite) — limited efficacy in Swift ARC.
5. Cert pinning for S3 endpoint — absent; note only (custom CAs / MinIO break pinning).
6. Redact object **keys** in client-visible errors if vault prefix is sensitive.
7. After ASC ship: verify production entitlements show expected App Group + Keychain groups only.

## Fixes in this pass

| ID | Change |
|----|--------|
| H1 | `openFile` / `lock` temp scrub |
| H2 | ShareInbox backup exclusion + 24h purge |
| H3 | S3 HTTP error bodies not echoed |

