# App Store Connect screenshots (Simulator)

Captured 2026-09-23 ART from Debug CryptoMako on iOS Simulator using local Cryptomator fixtures (`fixtures/vault` + `PASSWORD`). No physical device.

| Prefix | Device | Display | Pixels |
|--------|--------|---------|--------|
| `69-*` | iPhone 16 Pro Max | 6.9″ | **1320 × 2868** |
| `67-*` | iPhone 16 Plus | 6.7″ | **1290 × 2796** |

## Suggested ASC set (per size)

1. `*-01-unlock.png` — connection / unlock (S3 HTTPS form)
2. `*-02-browse.png` — vault root listing + Actions
3. `*-03-folder.png` — `notes/` folder
4. `*-05-preview.png` — plaintext preview (`todo.md`)
5. optional `*-04-actions.png` — root after opening a file (status “Opened …”)

## Drop into Connect

App Store Connect → CryptoMako (`6815413401`) → App Store → iOS prep → Screenshots:

- Previews and Screenshots → **6.9″** ← upload `69-*.png`
- **6.7″** ← upload `67-*.png`

No ASC API key on this Mac; manual drag-drop is fine.

## Regenerate

```bash
cd ~/dev/cryptomako-ios
cp -R ../cryptomako/fixtures/PASSWORD ../cryptomako/fixtures/vault fixtures/  # if needed
xcodegen generate
# Seed optional; UITest also types path/password
xcodebuild test -project CryptoMako.xcodeproj -scheme CryptoMako \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' \
  -derivedDataPath build/DerivedData-sim \
  -only-testing:CryptoMakoASCUITests/ASCScreenshotUITests/testCaptureASCScreenshots
```

Requires `CryptoMakoASCUITests` target in `project.yml`.
