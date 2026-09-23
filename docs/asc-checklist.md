# App Store Connect / TestFlight checklist (CryptoMako iOS)

Team **H4K6YW7MQM**. Bundles:

| Target | Bundle ID |
|--------|-----------|
| App | `net.gschimmel.cryptomako.ios` |
| File Provider | `net.gschimmel.cryptomako.ios.FileProvider` |
| Share | `net.gschimmel.cryptomako.ios.Share` |
| App Group | `group.net.gschimmel.cryptomako.ios` |

Marketing version **1.0.0**, build **100**.

## Status on this Mac (2026-09-23)

| Item | Status |
|------|--------|
| Checkout | `88cd3c0` (+ ASC docs commit if present) |
| Schemes | `CryptoMako` embeds FileProvider + Share |
| Release **archive** | **SUCCEEDED** → `build/CryptoMako.xcarchive` (Development signing on archive) |
| App Store **IPA export** | **SUCCEEDED** → `build/export-ipa/CryptoMako.ipa` (~1.8 MB) |
| IPA signing | **Cloud Managed Apple Distribution** (team `H4K6YW7MQM`) for app + both appexes |
| Store provisioning profiles | Auto-created for all three bundle IDs |
| Dev provisioning profiles | Auto-created for all three bundle IDs |
| ASC app record | **MISSING** — ASC API returned 0 apps for this bundle ID |
| ASC upload (`destination=upload`) | **FAILED**: *App record with bundle identifier "net.gschimmel.cryptomako.ios" not found on App Store Connect* |
| Local `AuthKey_*.p8` | Not found (Xcode cloud-managed session was enough to query ASC / cloud-sign) |
| Physical device | None connected |
| TestFlight build | **Not uploaded** — not processing |

### Key log lines

```
error: exportArchive Error Downloading App Information
  App record with bundle identifier "net.gschimmel.cryptomako.ios" not found on App Store Connect.
```

Logs (local, gitignored under `build/logs/`):

- `build/logs/archive-20260923-155858.log` — ARCHIVE SUCCEEDED  
- `build/logs/export-20260923-155957.log` — upload export failed (no ASC app)  
- `build/logs/export-ipa-20260923-160007.log` — EXPORT SUCCEEDED (IPA on disk)

## Exact Guillermo-only steps (minimal)

1. **Create the App Store Connect app record** (this is the hard blocker for upload):  
   https://appstoreconnect.apple.com → My Apps → **+** → New App  
   - Platforms: iOS  
   - Name: CryptoMako (or your preferred listing name)  
   - Primary Language: as you prefer  
   - Bundle ID: **net.gschimmel.cryptomako.ios** (must already appear after today’s automatic ID registration; if missing, create it under Certificates, Identifiers & Profiles first)  
   - SKU: e.g. `cryptomako-ios`  
   - User Access: Full Access  
2. **(If paid-apps / agreements pending)** Accept any outstanding Apple Developer / Paid Applications agreements in ASC or developer.apple.com so uploads are allowed.
3. **Tell the agent (or run yourself)** after the app exists:

```bash
cd ~/dev/cryptomako-ios
# Re-export with upload, or upload the IPA already on disk:
xcodebuild -exportArchive \
  -archivePath build/CryptoMako.xcarchive \
  -exportOptionsPlist Support/ASC/ExportOptions-AppStore.plist \
  -exportPath build/export-upload \
  -allowProvisioningUpdates
# OR open Xcode → Window → Organizer → Archives → Distribute App → App Store Connect → Upload
# OR: ./scripts/archive-and-upload.sh
```

4. **Privacy policy URL** — required before App Store *submit* (and often for external TestFlight). Host a short page and paste into ASC App Privacy / Review Information.  
5. **Screenshots** — required for App Store submit; optional for internal TestFlight. Approve Simulator captures or provide marketing shots.  
6. **(Optional but recommended)** Create an App Store Connect API key (`AuthKey_<KEYID>.p8`) under Users and Access → Integrations, save under `~/.appstoreconnect/private_keys/`, note Issuer ID + Key ID — enables fully unattended uploads later.

## Already prepared in-repo

- `Support/ASC/ExportOptions-AppStore.plist` — export + **upload**  
- `Support/ASC/ExportOptions-AppStore-IPA.plist` — IPA only  
- `scripts/archive-and-upload.sh` — archive then upload (checks for Distribution identity; cloud-managed signing may still work via `xcodebuild -allowProvisioningUpdates`)  
- Local IPA: `build/export-ipa/CryptoMako.ipa` (gitignored)

## After upload

Watch TestFlight → iOS builds for **Processing** → **Ready to Test**. Internal testers can install without Beta App Review; external / App Store submit needs privacy URL + screenshots + review.


## TestFlight upload (2026-09-23)

- ASC app **Cryptomako** exists (`Adam ID` / ASC id `6815413401`, bundle `net.gschimmel.cryptomako.ios`).
- First upload attempt (build **100**) rejected: missing `NSExtensionFileProviderDocumentGroup` (ITMS) — fixed by ensuring the key is present at Info.plist root **and** under `NSExtension`, plus `INFOPLIST_KEY_…`.
- Upload **succeeded** for version **1.0.0** build **101** — “Uploaded package is processing.”
- TestFlight: https://appstoreconnect.apple.com/apps/6815413401/testflight/ios
