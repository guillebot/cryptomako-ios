# CryptoMako for iOS / iPadOS

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-black.svg)](https://github.com/guillebot/cryptomako-ios)
[![Swift](https://img.shields.io/badge/Swift-5.10%2B-orange.svg)](https://swift.org)

**Point CryptoMako at any S3-compatible bucket over HTTPS, unlock a [Cryptomator](https://cryptomator.org) format-8 vault, and browse / open plaintext files on iPhone and iPad.**

Sibling of the macOS app **[guillebot/cryptomako](https://github.com/guillebot/cryptomako)**. Same vault format, same SigV4 object store, AGPLv3. Ciphertext stays on the object store; decryption is in-process. Secrets live in the **Keychain** only.

## Status

| Milestone | Scope |
|-----------|--------|
| **M0** | Shared cores: `CryptoMakoS3`, `CryptoMakoShared`, `CryptoMakoVault` (adapted from macOS) |
| **M1** (this tree) | Unlock + browse + download/open; connection UI; HTTPS/ATS only; writes fail-closed |
| **M2** | Light writes (create / upload / delete) fail-closed against remote S3 |
| **M3** | Files provider + share sheet |
| **M4** | On-device backup into the vault |

See [docs/ios-m0-m1.md](docs/ios-m0-m1.md).

## Open in Xcode

```bash
cd ~/dev/cryptomako-ios
# optional: refresh golden fixtures from the macOS sibling
cp -R ../cryptomako/fixtures/PASSWORD ../cryptomako/fixtures/vault fixtures/
xcodegen generate   # needs brew install xcodegen
open CryptoMako.xcodeproj
```

- **Bundle ID:** `net.gschimmel.cryptomako.ios`
- **Team ID:** `H4K6YW7MQM`
- Select an iOS 17+ Simulator or device, then Run.
- First distribution path: **TestFlight** (not Mac App Store).

### Local fixture unlock (Simulator)

1. In the app, choose **Local fixtures**.
2. Set the vault path to the absolute path of `fixtures/vault` in this clone, e.g.  
   `/Users/guille/dev/cryptomako-ios/fixtures/vault`
3. Password: contents of `fixtures/PASSWORD` (gitignored; copy from the macOS repo).
4. Unlock → you should see `hello.txt`, `notes/`, `bin/`, etc. matching `fixtures/expected-ls.txt`.

### S3 unlock

Endpoint must be `https://…` (ATS). Access key + secret + vault password: secret key and password are stored in Keychain via `CredentialStore`.

## Build libraries / tests without the app target

```bash
cd ~/dev/cryptomako-ios
swift test
```

(`Package.swift` also lists macOS so host-side `swift test` works; the app target is iOS-only via XcodeGen.)

## License

**AGPL-3.0** — same as [guillebot/cryptomako](https://github.com/guillebot/cryptomako). Including paid distribution.
