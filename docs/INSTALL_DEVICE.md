# Installing AniTV on a physical Apple TV

> Verified on **2026-11-26** on an Apple TV 4K (3rd generation), tvOS 27.2.1, with Xcode 27.2 and a
> **free** Apple ID (Personal Team). Simulators are covered in `README.md`; this file is only about
> real hardware.

## Requirements

- An Apple TV that can run **tvOS 26.0 or newer** — the app's deployment target (`project.yml`).
  tvOS 26 is the last version for the Apple TV HD and the 4K 1st generation, so every current model
  can be brought to it; the 3rd generation (2012) and older cannot run third-party apps at all.
- macOS with **Xcode 27.2** (or a release with the tvOS 26+ SDK) and an Apple ID added under
  *Xcode ▸ Settings ▸ Accounts*. A free account is enough; paid only changes the limits below.
- The Mac and the Apple TV on the **same network**. Apple requires IPv6 on that network for tvOS
  pairing; a link-local address is sufficient (measured: the Mac had only `fe80::` plus a ULA, no
  global IPv6 and no IPv6 router, and pairing worked).

## 1. Pair the Apple TV (once)

1. On the Apple TV: **Settings ▸ Remotes and Devices ▸ Remote App and Devices**. Leave the screen
   open and keep the TV awake — this is what makes it discoverable.
2. On the Mac: **Xcode ▸ Open Developer Tool ▸ Device Hub** (or *Manage Devices…* in the run
   destination menu). In Xcode 27 the devices window is the separate Device Hub app
   (`com.apple.dt.Devices`); the old "Devices and Simulators" window with a *Discovered* list is
   gone, and waiting for the device to appear in a list is the most common false start.
3. In Device Hub: **Add Device (+) ▸ Pair Nearby Device…**, then choose **Apple TV** at the top of
   the sheet.
4. If macOS asks whether the app may find devices on the local network, click **Allow**. Without
   that permission Device Hub silently finds nothing, even though `ping` and Bonjour work from the
   terminal.
5. Select the Apple TV, click **Next**, and enter the **PIN shown on the TV**.
6. **tvOS has no Developer Mode switch.** Apple: "In tvOS, there's no Developer Mode. Just pair your
   Apple TV using Device Hub and Developer Settings appear on the device."
7. Apple re-pairs are required after a tvOS major upgrade: "If you upgrade the operating system
   later, you'll need to pair the device again."

Check the result:

```bash
xcrun devicectl list devices          # the Apple TV appears with a UDID and state `connected`
```

## 2. Signing: a local team, never committed

The target signs automatically (`CODE_SIGN_STYLE: Automatic` in `project.yml`). The **team ID is
not in the repository**: it identifies a personal developer account. It lives in
`Config/Local.xcconfig`, which is gitignored, and the committed `Config/Base.xcconfig` pulls it in
when it exists:

```
#include? "Local.xcconfig"
```

Create the file once (team ID from *Xcode ▸ Settings ▸ Accounts*, the 10-character string next to
your team):

```
DEVELOPMENT_TEAM = XXXXXXXXXX
```

Without that file `xcodegen generate` still succeeds, simulator builds and CI work, and only device
signing has no team — CI signs nothing (`CODE_SIGNING_ALLOWED=NO`), so the public spec stays clean.
See [ADR 0027](DECISIONS.md).

## 3. Build, install, launch

```bash
xcodegen generate

xcodebuild -project AniTV.xcodeproj -scheme AniTV \
  -destination 'platform=tvOS,id=<UDID>' -configuration Release \
  -allowProvisioningUpdates -derivedDataPath .build/DeviceDerivedData build

xcrun devicectl device install app --device <UDID> \
  .build/DeviceDerivedData/Build/Products/Release-appletvos/AniTV.app

xcrun devicectl device process launch --device <UDID> tv.anitv.client
```

`udid` comes from `xcrun devicectl list devices`. `-allowProvisioningUpdates` lets Xcode create the
development certificate and the team provisioning profile on the first run; afterwards they are
reused. A screenshot of the running app:

```bash
xcrun devicectl device capture screenshot --device <UDID> --destination /tmp/anitv.png
```

In the Xcode UI the same thing is "select the Apple TV as the run destination, ⌘R". The scheme's Run
configuration is Debug; for everyday viewing switch it to Release (*Product ▸ Scheme ▸ Edit Scheme ▸
Run ▸ Build Configuration*), otherwise a debug build is installed.

## Limits of the free account

- **7 days** per provisioning profile: after it expires the app stops launching until it is re-signed
  by running the build again (the Apple TV must be reachable). Expiry itself has not been observed in
  this project yet — the profile was created on 2026-11-26.
- **3 devices** per account, counting every registered UDID, not only Apple TVs.
- **No TestFlight** — see [ADR 0003](DECISIONS.md).

## What was verified on 2026-11-26

- The build produced a signed app: identity *Apple Development* (Personal Team), profile
  *tvOS Team Provisioning Profile: tv.anitv.client*.
- The `keychain-access-groups` entitlement from `App/AniTV.entitlements` survives signing as
  `<TEAM>.tv.anitv.client` — a **free** Personal Team accepts it. The earlier assumption that
  Keychain Sharing is paid-only was wrong for this entitlement.
- The app was installed over Wi-Fi, launched, and loaded the live feed from the AniLiberty API
  (`docs/screenshots/device-feed.jpg`).
- A clean checkout without `Config/Local.xcconfig` still generates and builds for the simulator
  (`CODE_SIGNING_ALLOWED=NO`), so CI is unaffected.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Device Hub finds nothing | *Remote App and Devices* not open, TV asleep, or Device Hub missing the Local Network permission (System Settings ▸ Privacy & Security ▸ Local Network). Restart it with `killall DeviceHub`. |
| No IPv6 on the Mac's interface | `ifconfig en0 \| grep inet6` must show `fe80::…`; pairing does not work with IPv6 disabled. |
| Build fails: "Signing for AniTV requires a development team" | `Config/Local.xcconfig` is missing or empty. |
| App stops launching after a week | The 7-day profile expired; rebuild and reinstall. |
| Device vanished after a tvOS update | Re-pair (Apple requires it after an OS upgrade). |
