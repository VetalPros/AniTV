# Releasing to TestFlight

Everything that has to be true before a build can be installed by a tester through the TestFlight app.
Written after the project moved from a free Apple ID to a paid Developer Program membership (ADR 0033).

Two sides to it: **Apple's side** (only the account holder can do it) and **this repository's side**
(`scripts/release-testflight.sh` and the files it uses).

---

## 1. Apple's side, once

| # | Where | What | Notes |
| --- | --- | --- | --- |
| 1 | developer.apple.com → Membership | The paid team is active; note its **Team ID** | The free "Personal Team" is a *different* team. If the ID changed, update `Config/Local.xcconfig` |
| 2 | Xcode → Settings → Accounts | Sign in with the paid Apple ID | `-allowProvisioningUpdates` can then create certificates and profiles |
| 3 | Certificates, Identifiers & Profiles → Identifiers | App ID **`tv.anitv.client`** with the **Keychain Sharing** capability | The entitlement `keychain-access-groups` lives in `App/AniTV.entitlements`; without the capability the profile will not match |
| 4 | App Store Connect → Agreements | Accept the **Free Apps** agreement | A build is refused until the agreements are in place |
| 5 | App Store Connect → My Apps → **+** | New app: platform **tvOS**, name, primary language **Russian**, **SKU** (any unique string), bundle ID `tv.anitv.client` | The bundle ID cannot be changed later without a new app record |
| 6 | App Information | Category, **age rating** (the catalogue is 18+, so 17+), privacy policy URL, support URL | TestFlight shows the rating to testers |
| 7 | App Privacy | "Data Not Collected" plus the note that the app talks to a third-party API itself | Matches `App/Resources/PrivacyInfo.xcprivacy` |
| 8 | App Store Connect → Users and Access | Add internal testers (up to 100) | Internal builds need **no** beta review |

Before the first external build: fill "What to test" and a contact address, and be ready for the **beta
review** — external testing is reviewed by Apple, internal testing is not.

---

## 2. This repository's side

| File | Why it exists |
| --- | --- |
| `App/Resources/PrivacyInfo.xcprivacy` | Declares the only required-reason API the app uses (`UserDefaults`, reason `CA92.1`). Missing it is a delivery warning and a review question |
| `project.yml` → `ITSAppUsesNonExemptEncryption: false` | The app uses HTTPS only; this answers export compliance once instead of on every upload |
| `project.yml` → `CURRENT_PROJECT_VERSION: $(BUILD_NUMBER)` | TestFlight refuses a build number that was already used for the same marketing version |
| `Config/Base.xcconfig` → `BUILD_NUMBER = 1` | Fallback for plain local builds; the release script overrides it |
| `Config/ExportOptions.plist` | `method: app-store-connect`, automatic signing, symbols uploaded, build number left alone |
| `scripts/release-testflight.sh` | Generates, archives, exports, validates and uploads |

### Credentials

Nothing is stored in the repository. Either an **App Store Connect API key** (preferred):

```bash
export APPLE_API_KEY_ID=XXXXXXXXXX
export APPLE_API_ISSUER=00000000-0000-0000-0000-000000000000
export APPLE_P8_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8   # optional if it lives in the default place
```

or the Apple ID plus an **app-specific password**:

```bash
export APPLE_ID=you@example.com
export APPLE_APP_PASSWORD=abcd-efgh-ijkl-mnop
```

### The run

```bash
./scripts/release-testflight.sh                 # archive + export + validate + upload
UPLOAD=0 ./scripts/release-testflight.sh        # stop after the export, inspect the package
BUILD_NUMBER=202611271930 ./scripts/release-testflight.sh
```

After the upload, the build appears in App Store Connect → TestFlight within minutes to an hour. Add
yourself to a group, install the TestFlight app on the Apple TV, sign in with the same Apple ID.

To see whether the upload was accepted without waiting for the UI:

```bash
xcrun altool --list-apps --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER" \
  --p8-file-path "$APPLE_P8_PATH"          # the app record and its App Store version state
xcrun altool --build-status --platform appletvos --apple-id <App Store app id> \
  --bundle-version <build> --bundle-short-version-string <marketing version> \
  --apiKey ... --apiIssuer ... --p8-file-path ...
```

The App Store Connect API works too (`GET /v1/builds?filter[app]=<id>`); the JWT it needs is ES256 and has
to be signed with the same `.p8`.

---

## 3. Versioning

- `MARKETING_VERSION` (currently `0.1.0`) is what a tester sees. Bump it for a new testing round.
- `BUILD_NUMBER` must increase within one marketing version; the script defaults to UTC
  `yyyymmddHHMM`, which is monotonic in practice.
- **TestFlight builds expire after 90 days.** When testers report "build expired", re-run the script.

---

## 4. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `No profiles for 'tv.anitv.client' were found` | The team in `Config/Local.xcconfig` is the old free one, or the App ID lacks a capability. Fix §1 rows 1–3, then re-run — `-allowProvisioningUpdates` creates the profile |
| `The provided entity includes an attribute with a value that has already been used` | Build number reused. Pass a new `BUILD_NUMBER` |
| `Invalid Bundle. The bundle at … does not support the minimum OS Version` | `deploymentTarget.tvOS` is higher than what the App Store Connect record expects — check that the record's platform is **tvOS** and not iOS |
| Upload succeeds but no build appears | Processing takes minutes; a rejected bundle sends a mail with the reason (often a missing privacy manifest or app icon) |
| `ITMS-90471: Missing Image Asset — Top Shelf Image Wide 2x` (a mail, not a rejection) | The Top Shelf slots ship only a `1x` image while Apple looks for a `2x` one. It is informational — the build still goes `VALID` — but the assets now carry `top_shelf@2x.png` (3840×1440) and `top_shelf_wide@2x.png` (4640×1440), upscaled from the originals |
| `Missing Image Asset. Your app is missing the App Store Icon asset` | tvOS wants **two** icons in the brand assets: the home-screen stack (400×240) and the App Store stack (1280×768). Both must be *image stacks with at least two layers* — `actool` rejects a single-layer stack with "must have at least 2 layers". Shipping state: `App Icon - App Store.imagestack` with `Back`/`Front` layers |
| `CFBundleVersion … must be composed of one to three period-separated integers` | The build number has to be numeric. The script's default (`yyyymmddHHMM`) is; a hand-made `BUILD_NUMBER=probe` is not |
| TestFlight asks about export compliance | `ITSAppUsesNonExemptEncryption` did not reach `Info.plist`; check the generated plist in the archive |
| External testers see nothing | External testing needs the beta review; internal testing does not |
| `Failed to create URL for 'CDUploaderStateInfoResumeFilePath'. The file doesn't exist` during upload | A benign altool line on a run that has no resume state yet; the same run ends `UPLOAD SUCCEEDED` with a `Delivery UUID` |
| `resource fork, Finder information, or similar detritus not allowed` when `codesign` runs on an unzipped `.ipa` | `unzip` attaches `com.apple.FinderInfo`/`com.apple.provenance` xattrs; the `.ipa` itself is clean. Run `xattr -cr Payload/AniTV.app` before inspecting |
| `altool` prints nothing for a minute or two | Normal: `--validate-app` uploads the bundle to Apple's validation service first. On 2026-11-28 a 2.4 MB ipa took ~75 s for validation and upload together |
