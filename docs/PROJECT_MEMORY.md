# PROJECT MEMORY — living state

> Update this file at the end of every session that changes the project's state.
> Rules and constraints live in `AGENTS.md`; decisions live in `docs/DECISIONS.md`.
> Last updated: **2026-11-27** (session 6: navigation redesign specified — `docs/NAVIGATION.md` and ADR 0028
> — after live captures of the system TV app and a sidebar spike on the owner's Apple TV. Previous,
> session 5: first build, install and launch on a physical Apple TV with a free Apple ID, ADR 0027,
> procedure in `docs/INSTALL_DEVICE.md`).

## Snapshot

| Item | Value |
| --- | --- |
| Stage | **Vertical slice 1 is end-to-end verified.** Feed, release detail and player driven by XCUITest on the tvOS simulator |
| Target platform | tvOS 26.0 (single target for now) |
| Distribution | TestFlight / ad-hoc only. App Store out of scope. A **free-account device install works** (verified 2026-11-26) |
| Apple Developer | **Free** account (7-day profiles, 3 devices, no App Groups/CloudKit/Push) |
| License | **MIT** — confirmed 2026-11-10 (`LICENSE`) |
| Product name | Provisional `anitv` — final name and bundle ID decided later |
| Repository | public, <https://github.com/VetalPros/AniTV>, MIT (published 2026-11-17) |
| DSH workspace | `c714b289-7397-4251-b27c-4ce3ce773cf6` (`~/Documents/anitv`) |
| Physical Apple TV | **paired and in use** since 2026-11-26: Apple TV 4K `AppleTV18,1` (devicectl's marketing name: *4th generation*; session-5 notes said 3rd), name «Гостиная», tvOS 27.2.1 (24K157), UDID `00008150-000C62CA0101401C` |
| Navigation | **System sidebar shipped in P1–P2** (2026-11-27, ADR 0028 + 0029): `RootShellView` with `.sidebarAdaptable`, header, four rows; the old top tab bar is gone; all sections share the `72 / 56` frame and clear the collapsed pill. Test repair (P4) and «Медиатека» (P5) still pending |

## Environment facts (verified on this machine)

- macOS **27.0.1** (26A434), arm64. Disk: ~104 GB free.
- Xcode **27.2** (27B52) at `/Applications/Xcode.app`; `xcode-select -p` →
  `/Applications/Xcode.app/Contents/Developer`. License accepted, first-launch components installed.
  **Verified working** (`xcodebuild -version`, `xcrun simctl`, `xcodebuild -showsdks`).
- SDKs: `appletvos27.2`, `appletvsimulator27.2`. Runtime: **tvOS 27.2 (24K150)**, id
  `com.apple.CoreSimulator.SimRuntime.tvOS-27-2`. SDKs are 27.x and, since 2026-11-27, so is the
  deployment target (**27.0**, ADR 0029 — raised from 26.0 for the sidebar header); a 26.0 runtime is
  not installed, so nothing below 27 can be exercised here.
- Simulators available (both `Apple TV 4K (4th generation)`):
  - `1CEE9693-F8EB-45A4-8223-1679EE0EFC5A` (4K)
  - `A51D0687-F8A5-494D-B199-3AAB94271BFB` (1080p)
- Tooling: Homebrew 7.0.11, git 2.54.0, Swift 6.4, Node v24.3.0, npm 11.4.2, python3 3.9.6
  (CommandLineTools one — not a project dependency).
  - Installed via Homebrew and verified: **xcodegen 2.46.0**, **xcbeautify 3.2.1**,
    **swiftlint 0.65.1**, **swiftformat 0.64.6**.
- No standalone "Apple TV emulator" exists: the tvOS **Simulator** ships inside Xcode and is driven
  by `xcrun simctl` / `xcodebuild`.
- **No `Simulator.app` in this Xcode**: `/Applications/Xcode.app/Contents/Developer/Applications` does
  not exist and `open -a Simulator` fails. The simulator is headless-only (`simctl`), so nothing can be
  clicked by hand and AppleScript/System Events cannot drive it — input has to come from XCUITest
  (`XCUIRemote`). Screenshots come from `xcrun simctl io booted screenshot` or `XCTAttachment`.
- The tvOS runtime is a **patchable cryptex disk image**. It can silently stop being reachable —
  `simctl list runtimes` prints nothing and devices show `unavailable, runtime profile not found
  using "System" match policy`, after which every `xcodebuild test` fails with "The tvOS 27.2 simulator
  runtime is not available. runtime path not found". Recovery, verified 2026-11-11:
  `xcrun simctl runtime scan-and-mount` (the `simctl runtime list` entry still says `Ready` with a
  `mountPath` under `/private/var/run/com.apple.security.cryptexd/mnt/`).
- **The physical Apple TV is reachable from this Mac** (2026-11-26): Apple TV 4K (devicectl reports
  `AppleTV18,1` and the marketing name *4th generation*), tvOS 27.2.1, Bonjour name `Gostinaa.local`.
  `xcrun devicectl list devices` shows it as `available (paired)` next to the two simulators;
  `devicectl device install/process launch/capture screenshot` all work over Wi-Fi.
  - Screen capture command, verified 2026-11-27: `xcrun devicectl device capture screenshot --device
    <udid|name> --destination <file.png>` — 1920×1080 for the TV app, and **one capture pixel is one
    tvOS point**, so captures can be measured directly. There is no `--output` flag.
  - `xcrun devicectl device process launch --device <udid> <bundle-id-or-path>`: user apps by bundle id
    (`tv.anitv.client`), but the **system TV app only by path** `/Applications/AppleTV.app` — its bundle
    id does not resolve (`com.apple.TV`, `com.apple.TVAppleTV`, `com.apple.tvapp`, `com.apple.TVShows`
    all fail with CoreDevice error 10002 / OSStatus -10814). `devicectl device info apps` lists only
    user-installed apps on tvOS.
  - **There is no input channel into either the TV or the simulator**: `devicectl` cannot press the
    remote or inject HID, and there is no `Simulator.app`, so any state that needs a key press must be
    produced by the owner on the remote or by an XCUITest. Screenshots are observation only.
- SwiftUI availability on tvOS, read from the AppleTVOS27.2 SDK's `SwiftUI.swiftinterface` (2026-11-27):
  `.tabViewStyle(.sidebarAdaptable)` **tvOS 18.0+**, `TabSection` tvOS 18.0+, `Tab(role: .search)`
  tvOS 18+ (renders as the pinned «Поиск» row); `tabViewSidebarHeader`/`tabViewSidebarFooter`
  **tvOS 27.0+**; `tabViewSidebarBottomBar` unavailable on tvOS.
- **Building the app needs the session outside the default sandbox.** Under `workspace-write`,
  `xcodebuild` fails at package resolution: SwiftPM writes its manifest cache to
  `~/Library/Caches/org.swift.swiftpm/manifests/ManifestLoading` ("Operation not permitted") and the
  build then reports `Missing package product 'AniLibertyKit'`; `-packageCachePath` and
  `-clonedSourcePackagesDirPath` do not work around it, and a project that uses Swift macros
  (`@State`) also fails with "swift-plugin-server produced malformed response". With the session at
  **danger-full-access** the same command is green (2026-11-27: `BUILD SUCCEEDED`). Note also that
  `xcodebuild -resolvePackageDependencies` rejects `-derivedDataPath` unless `-scheme` is given.

- Pairing flow in **Xcode 27.2** is *Device Hub* (`/Applications/Xcode.app/Contents/Applications/
  DeviceHub.app`, `com.apple.dt.Devices`): `+` → *Pair Nearby Device…* → choose Apple TV → PIN from
  the TV. The old *Devices and Simulators* window with a "Discovered" list is gone, so waiting for
  the device to appear in a list finds nothing. Device Hub needs the macOS **Local Network**
  permission; `tvOS has no Developer Mode switch`, and Apple re-pairs after an OS upgrade.
- The LAN has **IPv6 link-local plus a ULA** (`fd1f:22dd:ac9f:4d65::/64`) but no global IPv6 and no
  IPv6 router (`networksetup -getinfo "Wi-Fi"` → `IPv6 Router: none`). That is enough: `ping6`
  answers on both addresses and tvOS pairing requires IPv6 to exist, not to be routed.
- Free Personal Team details measured: team is `isFreeProvisioningTeam = 1`; the first
  `-allowProvisioningUpdates` device build created the *Apple Development* certificate and the
  *tvOS Team Provisioning Profile: tv.anitv.client*; `App/AniTV.entitlements` keeps
  `keychain-access-groups = <TEAM>.tv.anitv.client` in the signed app, i.e. the free team **does**
  accept that entitlement (the earlier "Keychain Sharing is paid-only" assumption was wrong).

## Done

Environment:
- [x] Xcode 27.2 installed; tvOS 27.2 simulator runtime downloaded and verified.
- [x] Verified the AniLiberty public API surface and HLS playback by hand (see `api-notes.md`).
- [x] `~/Documents/anitv` registered as a DSH workspace (`c714b289-7397-4251-b27c-4ce3ce773cf6`).
- [x] `xcodegen` 2.46.0, `xcbeautify` 3.2.1, `swiftlint` 0.65.1, `swiftformat` 0.64.6 installed.

Scaffold and tooling:
- [x] `project.yml` (XcodeGen) — tvOS app target `AniTV` + shared package dependency; the project is
      generated, `AniTV.xcodeproj` and `App/Info.plist` are generated and never committed.
- [x] `AniLibertyKit` package: `Models/` (Release, Media, Episode, Genre, NamedValue), `API/` (client,
      configuration, typed errors, transport, shared decoder), `Cache/` (image cache), `Player/`
      (stream and timecode resolution). No third-party dependencies.
- [x] Kit tests: 25 tests in 4 suites (`swift test --package-path AniLibertyKit` green), fixture-backed.
- [x] `.swiftlint.yml`, `.swiftformat`, `.github/workflows/ci.yml`, `.gitignore`.
- [x] `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, MIT `LICENSE`.

First vertical slice (feed from the network):
- [x] App shell: `RootTabView` with three Liquid Glass tabs (Новинки / Каталог / Профиль), the last two
      being labelled placeholders.
- [x] "Новинки" screen: `LatestReleasesViewModel` (observed, `@MainActor`) → `GET /anime/releases/latest`,
      six-column poster grid, loading / empty / error states, focus-first button style.
- [x] Design system: background, tokens, glass badge, rating pill, remote image with the Kit cache,
      screen header, `WrapLayout`.
- [x] Detail screen (metadata + episode cards) and player screen (`AVPlayerViewController`,
      `externalMetadata`, resume/timecode plumbing) implemented and compiled.
- [x] Localisation: 44 keys in `Localizable.xcstrings` (en source + ru); assets catalog with
      AccentColor; no app icon yet.
- [x] Verified in the simulator on 2026-11-10: the app launches, the feed loads **real** data from the
      network (14 releases), `Logger` logs `[tv.anitv.client:Latest] Loaded 14 latest releases`;
      screenshot at `/tmp/anitv-latest.png`.
- [x] Gates green: `swiftformat --lint .` → 0/48 files; `swiftlint --strict` → 0 violations in 48 files;
      `xcodebuild … build` → `** BUILD SUCCEEDED **`, no Swift warnings; `swift test` → 25 tests pass.

UI verification (2026-11-11, XCUITest — the only way to deliver input here, ADR 0012):
- [x] `AniTVUITests` target in `project.yml` (`bundle.ui-testing`, `TEST_TARGET_NAME: AniTV`) wired into
      the `AniTV` scheme's test action; `App/UITests/LatestFeedUITests.swift` holds two scenarios.
- [x] Scenario 1 (feed → detail → back): Down presses move focus onto a poster, Select pushes the
      detail screen, the selected title is on it, Menu pops back to the feed.
      `Test Case … testSelectingPosterOpensDetailAndMenuReturnsToFeed passed`.
- [x] Scenario 2 (detail → player → back): Select on the focused play button presents `player.screen`
      (a real HLS stream starts — the first frame and the system transport bar are visible in the
      attachment), Menu dismisses it back to the detail screen.
      `Test Case … testPlayButtonOpensPlayerAndMenuReturnsToDetail passed`.
- [x] Whole suite: `** TEST SUCCEEDED **`, 2 tests, no failures — repeated on 2026-11-11 after a
      simulator reboot and again after the runtime was remounted with `simctl runtime scan-and-mount`.
- [x] Fixed by that work: Menu on the detail screen backgrounded the app instead of popping, because
      the pushed screen had nothing focused (ADR 0012).
- [x] Screenshots taken by the tests themselves (`XCTAttachment` → `xcresulttool export attachments`),
      committed as `docs/screenshots/{feed,detail,player}.jpg` and shown in `README.md`.
- [x] Gates re-run on 2026-11-11: `swiftformat --lint .` → 0/49 files require formatting;
      `swiftlint --strict` → 0 violations in 49 files; `swift test` → 25 tests in 4 suites pass.

Second pass (same day, after the user's own run on the simulator):
- [x] Fixed, with the user's three findings reproduced first: the detail screen never scrolled (so
      genres/synopsis/episodes were unreachable dead content), the hero poster was sliced by a
      width-only frame, and the player drew a permanent title badge that duplicated the system info
      panel (ADR 0015 for the scroll trap, ADR 0014 for the player).
- [x] Episode list is now reachable: Down walks from the hero into genres → synopsis → episodes, and
      choosing an episode starts that episode (`testDetailScrollsToEpisodeListAndPlaysAnEpisode`).
- [x] Quality switching, in the system transport bar: one `UIMenu` entry whose image is the running
      quality ("1080p") opens the native «Качество» popup with 1080p / 720p / 480p; item replaced and
      playhead kept (`testTransportBarQualityMenuSwitchesTheStream`). The entry is only on screen while
      the transport bar is — the floating pill and the modal chooser from ADR 0014 are gone (ADR 0016).
      Confirmed by the user on a manual run: switching works and the position is preserved.
- [x] Full UI suite green on the committed tree: 4 tests, `** TEST SUCCEEDED **`; `swiftformat --lint .`
      → 0/51 files; `swiftlint --strict` → 0 violations in 51 files; `swift test` → 25 tests pass.
- [x] Screenshots in `docs/screenshots/` re-taken from the test attachments (detail, episodes, player,
      quality chooser).
- [x] App icon and static Top Shelf image (ADR 0017): two-layer tvOS brand assets compiled by actool
      (`CFBundleIcons → CFBundlePrimaryIcon = App Icon` in the built `Info.plist`, flattened and
      radiosity renditions present in `Assets.car`), verified on the simulator home screen — the dock
      shows the red plate with the white mark and the Top Shelf area shows the static artwork.
      Provenance and the GPL-3.0/trademark caveat: `docs/THIRD_PARTY_ASSETS.md`.
- [x] Top Shelf artwork carries the wordmark "AniTV" + «неофициальный клиент» and sits inside a safe
      box: the home screen aspect-fills it and cuts the sides (the first version lost the mark's left
      edge). Verified on the simulator; the capture procedure is "leave the app with Menu, then take a
      screen-wide screenshot from a UI test".
- [x] «Профиль» tab works end to end against a real account (ADR 0021, ADR 0022): pairing code → confirmed
      on the site → token in the Keychain → profile loaded (display name, login, avatar) → favourites page
      loaded and rendered → «Выйти» deletes the token and the screen returns to pairing with a fresh code.
      Four separate defects were fixed on the way, all found from logs: the account calls needed a clean
      session, every refusal while polling means "keep waiting", re-issued codes had to be polled as a set,
      and the profile request had to leave the cancelled polling task. `ProfileUITests` covers the pairing
      screen; the signed-in path was verified by hand on the simulator and has no automated test yet.
- [x] Keychain persistence checked on the simulator: a `kSecClassGenericPassword` item written by
      `KeychainTokenStore()` is still there after terminating and relaunching the app and after
      `simctl shutdown` + `boot` (`KEYPROBE present=true`). `xcodebuild test` reinstalls the app and the
      fresh install starts without the item, so the UI-test runs are not evidence either way.
- [x] The app no longer deletes a rejected token on the spot: a 403 from `/profile` shows
      «Сессия истекла → Привязать заново» and keeps the item until the viewer asks for a new pairing.
      This is what made a restart look like "the account disappeared".
- [x] Avatars render: a user picture carries `preview`, not `src` (unlike a release poster), and the
      model read only `src`. Covered by a Kit test with a schema-shaped payload.

- [x] Per-episode playback progress: one record per episode in a per-release key, migrating the legacy
      single-object payload on read; the detail screen shows a bar on watched episodes and marks the one
      «Продолжить» would open.
- [x] Favourites from the release detail screen: heart in the hero block, favourite ids read once per
      release, optimistic toggle with rollback; without a paired TV it explains where to pair. Tested for
      the signed-out path only — the real add/remove on a live account was not exercised (it would mutate
      the owner's favourites).
- [x] Catalogue pages cached by request for five minutes (`CatalogCache`): paging back and forth no longer
      re-hits the service. The endpoint has no `ETag` (measured), so this is a client-side cache, not
      revalidation. The `refresh: true` path is wired to filters/search/retry but not asserted by a test.
- [x] «Настройки» tab (ADR 0027): «Автоматически пропускать опенинги» and «…эндинги», both off by default,
      persisted in `PlaybackSettingsStore`. The player reads them once per session. The skip hint is a single
      control now, expiring 30 s after it appears; auto-skip seeks silently and, for an ending, offers
      «Следующая серия» for the same 30 s. The «Смотреть» button and the focus crutches it needed are gone.
      `SettingsUITests` proves the switches flip and survive a relaunch; `PlayerSkipUITests` proves the hint
      takes focus, Select acts on it, it expires on its own, and auto-skip leaves no hint at all.
- [x] Player skip hint: custom control inside `AVPlayerViewController.contentOverlayView` (SwiftUI overlays
      above the player never receive focus), two buttons — «Пропустить опенинг»/«Пропустить эндинг» and
      «Смотреть», hint never hidden by focus (it sits 300 pt up, clear of the transport bar; hiding it on focus
      made the button vanish while the viewer reached for it), focus guides between the two buttons, and
      `EndingOfferResolver` in the kit
      decides between skipping an ending and offering the next episode (15 s tail threshold, five unit tests).
      `PlayerSkipUITests` covers focus, skipping, dismissing and hiding; the actual next-episode switch is a
      content-dependent `XCTSkip` (see ADR 0026).
- [x] Auto-refresh: `AutoRefreshPolicy` + `RefreshLoop` (one timer for both screens). «Новинки» every
      300 s and on returning to the tab after >60 s, favourites every 180 s plus an immediate re-read on
      entering the tab, and the detail screen re-reads the favourite state on every appear. Hidden screens
      and a backgrounded app run no timer at all. Proven by `AutoRefreshUITests`, which watches the
      «Обновлено HH:mm» caption change on an untouched screen with the intervals shortened by
      `-uiTestingRefreshInterval`; the production numbers themselves are not measured by any test.

- [x] Test seam: `App/Sources/Support/AuthTokenStoreFactory.swift` — the launch argument
      `-uiTestingSignedOut` swaps in an `EmptyTokenStore` so the pairing and signed-out-heart tests are
      deterministic while the simulator's Keychain holds a real session. Production never passes the flag;
      the Keychain stays the only token store.

**Confirmed by the account owner (2026-11-17)** on the simulator: the avatar set on the site is now shown
next to the display name, the favourites poster renders, and the profile is still there after restarting
the simulator — so both reported defects are closed against a real account, not only in tests.
- [x] «Каталог» tab with search and filters (ADR 0020): `CatalogView`/`CatalogViewModel` over the Kit's
      catalogue client, single-choice chips for genre/type/year/sorting behind modal pickers, a result
      counter, «Показать ещё» paging and reset. `CatalogUITests` proves the tab loads 1946 releases, a
      genre filter changes the count, typing «маска» through the tvOS keyboard narrows it to 6, reset
      restores it, and a poster opens the release screen.
- [x] Episode cards look like the official site (three columns, full-bleed previews, «N эпизод»,
      length pill) and «Смотреть» opens a modal episode picker with focus on the episode the player
      would have chosen (ADR 0019). Covered by `DetailEpisodePickerUITests` (picker opens with the same
      number of cards as the list, selection starts that episode, Menu closes it without playing).
- [x] Playback progress: the Kit stores one position per release (`PlaybackProgress`/`Store`, 17 tests),
      the player writes it every 5 s and on dismissal, and the detail screen shows «Продолжить» left of
      «Смотреть» with default focus when the position is resumable (ADR 0018). Verified end to end by
      `DetailResumeUITests`: watch ~20 s → exit → reopen → «Продолжить» → the system timeline starts at
      00:24 instead of 00:00, and the record is visible in the app container's `UserDefaults` plist.
- [x] The static Top Shelf artwork renders on the home screen **only while the app icon holds focus**
      (verified after `simctl erase` + install + launch + terminate: dark plate, red glow, red mark).
      With focus on another tile the system shows its own wallpaper, which is why the earlier screenshot
      looked as if the artwork had been dropped — it was never removed, just not focused.

- [x] Device signing is automatic, and the team is **not** in the repository (ADR 0027):
      `CODE_SIGN_STYLE: Automatic` in `project.yml`, the team ID in the gitignored
      `Config/Local.xcconfig`, which `Config/Base.xcconfig` pulls in with `#include?`. Verified both
      ways: with the file a device build signs with the Personal Team; without it `xcodegen generate`
      succeeds and the simulator build with `CODE_SIGNING_ALLOWED=NO` (the CI command) still passes.
- [x] First install on the physical Apple TV (2026-11-26): `xcodebuild -allowProvisioningUpdates`
      signed the app, `devicectl device install` installed it over Wi-Fi, `devicectl device process
      launch` started it, and the live feed loaded from the API on the TV itself. Screen captured with
      `devicectl device capture screenshot` → `docs/screenshots/device-feed.jpg`. The build installed
      came from the working tree that still holds the uncommitted «Настройки» work, so that screenshot
      shows a fourth tab that `main` does not have yet. Procedure, limits and troubleshooting:
      `docs/INSTALL_DEVICE.md`.
- [x] Navigation redesign specified, no app code touched (2026-11-27): live captures of the system TV
      app on the owner's TV in both the expanded and the collapsed state; a throwaway
      `.tabViewStyle(.sidebarAdaptable)` app built for the tvOS 27.2 simulator (`.build/navspike/`,
      gitignored, outside the project) that reproduced the reference look; `docs/NAVIGATION.md` with the
      spec and ADR 0028 with the decision. Outcome: the shell is the **system sidebar**, not a hand-built
      one, and the avatar/clock header is deferred because it needs tvOS 27.0. Phases P1–P5, write scopes
      and the focus requirements are in the spec; nothing is verified about the collapsed state yet,
      because this session had no input channel into the device.
- [x] Navigation shell, phase P1 (2026-11-27, ADR 0028 + ADR 0029): `RootShellView` replaces
      `RootTabView` — `TabView` with `.tabViewStyle(.sidebarAdaptable)`, a `tabViewSidebarHeader`
      (avatar placeholder, «AniTV», clock), «Поиск» as `Tab(role: .search)`, then «Главная», «Профиль»,
      «Настройки». Minimum target raised to **27.0** for the header. `tab.*` strings replaced by `nav.*`.
      Verified: simulator build green, Kit tests green (91), `NavigationShellUITests` passes on the tvOS
      27.2 simulator (focus leaves the panel into the posters and Left brings it back — attachments show
      the collapsed pill), device build signed and installed, and the shell captured on the owner's Apple
      TV. Not verified: Back semantics and per-section path preservation; the six older UI-test files
      still walk focus into the tab bar that no longer exists (P4).
- [x] Navigation shell, phase P2 (2026-11-27): `DesignTokens.screenTopInset` (56) became the single top
      inset, `ScreenHeader` uses it, and «Настройки» lost its private header plus the hardcoded 80/60
      paddings, so all four sections share one frame. Verified with `NavigationSectionsUITests` — it opens
      each section through the new test-only `-uiTestingSection` argument, captures it with the panel
      expanded and collapsed, and shows no title or control under the pill, backgrounds full-bleed.

## Next steps (ordered)

1. Continue the navigation redesign at P4 (`docs/NAVIGATION.md`): the six UI-test files still walk focus
   into the gone tab bar (`LatestFeedUITests`, `CatalogUITests`, `AutoRefreshUITests`,
   `PlayerSkipUITests`, `DetailResumeUITests`, `DetailEpisodePickerUITests`) and now fail; their helpers
   belong in `UITestSupport.swift`, driven by the shell's rows instead of the tab bar. Then the rest of
   P3: Back semantics and per-section path/scroll preservation. A browsable «Каталог» row returns once
   `CatalogView` splits into search and browse.
2. Re-sign on the Apple TV before the 7-day profile expires and record what happens when it does
   (in-app error? launch refused?). The TV now occupies one of the three free-account device slots;
   `docs/INSTALL_DEVICE.md` is the procedure to repeat.
3. Exercise the favourite toggle against a live account: the add/remove calls and the rollback path have
   never run with a real token (doing it mutates the owner's favourites, so it needs their go-ahead). Same
   for the `views/history` "continue watching" row, which is not built yet — and «Медиатека» (P5 of the
   navigation spec) depends on both.
4. Replace the borrowed app icon with an original mark before publishing anywhere — see
   `docs/THIRD_PARTY_ASSETS.md`; the current one is AniLiberty's mark, used with their written permission
   (ADR 0025) — so this is no longer a blocker for publishing, only a provenance note.
5. Capture real profile / favourites fixtures: the Kit's are synthesised from the OpenAPI schema. The Kit's
   favourites ids/add/remove also assume the documented shapes (a `204` without a body would need the
   decode relaxed).
6. Watch the advisory `ui-tests` CI job on a real GitHub runner; only then consider making it required
   (ADR 0013). Also pin `xcode-select` if the `macos-26` image starts shipping a different default Xcode.
7. Decide the final product name / bundle identifier **before** the repository goes public (renaming the
   directory means re-registering the DSH workspace).
8. Nice-to-haves nobody has asked for yet: a disk tier for the catalogue cache (it is memory-only now) and
   a "continue watching" row on «Новинки» from `views/history` — the latter becomes redundant if
   «Медиатека» lands.

## Deferred ideas (agreed, deliberately not scheduled)

### Dynamic Top Shelf — a carousel of fresh releases instead of the static artwork

**What.** Replace the static `Top Shelf Image` with a carousel: posters of the latest releases,
supplied by a **TV Services extension** (`TVTopShelfContentProvider` returning
`TVTopShelfCarouselContent` with `TVTopShelfCarouselItem`s).

**Why it is not done now.** The shipped Top Shelf is a PNG baked into the bundle: it changes only
with a new build. A live strip is a new target, a new bundle identifier, its own signing and its own
cache — a feature, not a tweak. Agreed with the owner on 2026-11-16 to keep the static artwork and
revisit this later.

**What to verify first (a spike, not a design task).**

1. Does a TV Services extension display at all on tvOS 27.2 in the **simulator**, and with a **free**
   Apple Developer account? Nothing about this has been tested in this project yet.
2. How often does the system actually ask the provider for content (on focus? on a schedule? never
   again after the first fetch)? This decides whether "fresh" is even true.
3. Can the extension fetch `GET /anime/releases/latest` on its own? It cannot read the app's cache or
   any app data (no App Groups on the free account), so it needs its own `AniLibertyClient` instance,
   its own `ImageCache`, its own error handling, and it must honour the politeness rule (one request
   per refresh, conditional requests).
4. What does the system do when the extension fails or the network is down — empty carousel, stale
   content, or nothing at all?

**Consequences to accept if it ships.** `AGENTS.md` §2 ("Top Shelf must be either static imagery or
omitted") must be rewritten: its premise is that an extension cannot read app data, which no longer
blocks a self-fetching extension. CI gains a target that cannot be exercised without a booted
simulator plus network. Budget: roughly half a day for the spike, then the carousel design.

**Fallback that needs no extension.** The "Новинки" tab already is the fresh-releases surface inside
the app; if the system turns out to refresh the Top Shelf too rarely to be worth it, keep the static
artwork and drop this idea.

## Installed on the owner's Apple TV (2026-11-27)

Release build signed with the personal team from `Config/Local.xcconfig`, installed and launched on
`Гостиная` (`00008150-000C62CA0101401C`, Apple TV 4K, tvOS 27.2.1) with the procedure in
`docs/INSTALL_DEVICE.md`:

```
xcodebuild ... -destination 'platform=tvOS,id=00008150-000C62CA0101401C' -configuration Release \
  -allowProvisioningUpdates -derivedDataPath .build/DeviceDerivedData build      → BUILD SUCCEEDED
xcrun devicectl device install app --device 00008150-… AniTV.app               → App installed
xcrun devicectl device process launch --device 00008150-… tv.anitv.client      → Launched
xcrun devicectl device capture screenshot … --destination /tmp/appletv-live.png → 1920×1080
```

The screenshot shows the live feed with the new four-tab bar including «Настройки», so the build on the
device is the current `main` (`c2973d8`). Signing is `Apple Development: vetalirusa@gmail.com`, team
`9KLFP6C3LT`; a free personal team means the profile lives **seven days**, after which the app stops
launching until it is installed again — that is a property of the account, not of the code.

## CI on the real runner (2026-11-17)

The first run on GitHub did two useful things at once. The **advisory UI suite passed on a GitHub-hosted
`macos-26` runner** — 17 XCUITest tests driving a tvOS simulator, which is the item that had been
"untested on a real runner" since the workflow was written. The required check never ran: the job was
still queued when GitHub dropped it with
*"The job was not acquired by Runner of type hosted even after multiple attempts"* plus a capacity notice,
so the run turned red without a single line of our build having executed.

Two changes followed: the UI job now `needs: build-test-lint` (one macOS job queued at a time was the
actual problem — parallel jobs competed for a single slot), and `workflow_dispatch` was added so a
capacity cancellation is re-run with one click instead of an empty commit. The advisory job keeps
`continue-on-error`, so an upstream API outage still cannot block a merge.

**The run after that fix is green end to end** (<https://github.com/VetalPros/AniTV/actions/runs/44110020328>):
`Build, test, format, lint` — XcodeGen generation, tvOS Simulator build, 82 Kit tests, `swiftformat --lint`
and `swiftlint --strict` all succeeded in ~2 minutes, and the advisory `UI tests` job ran the 17 XCUITest
tests on a booted tvOS simulator successfully in ~13 minutes. That closes the two "never seen on a real
runner" caveats the workflow had carried since it was written. The UI job stays advisory until it has a
track record (the comment in `ci.yml` asks for ten consecutive green runs).

## Publishing (2026-11-17)

The repository is published at <https://github.com/VetalPros/AniTV> (owner's account, public, MIT).
`docs/PROJECT_MEMORY.md` and `AGENTS.md` are committed on purpose: the project is open by design and
`AGENTS.md` §2.2 forbids secrets, so both stay readable. Before the first push the tree was scanned for
personal data (the account holder's nickname and address appear in no file and in no commit) and for
tokens (none). The Kit's `User-Agent` now carries the real repository URL, which is what the politeness
rule in `AGENTS.md` §2.5 asks for — it used to be a placeholder.

**Settled by the service team (ADR 0025):** the icon may stay (their «AL» monogram, permission given in
writing), and the name «AniTV» is allowed. The bundle id `tv.anitv.client` is still a development choice,
not a commitment.

## Open questions for the user

- Final **product name** and **bundle identifier** — deliberately deferred; the working name is
  `anitv` and the bundle id will be `top.<domain>.<name>` once the name is chosen. Renaming the
  directory later means re-registering the DSH workspace, so decide before the repository goes public.
- Whether to enable an Xcode MCP bridge now or after the first successful build.
- **Navigation (ADR 0028, spec `docs/NAVIGATION.md`), asked 2026-11-27:**
  - ~~**Minimum target 26.0 → 27.0?**~~ **Answered: yes, raised** (ADR 0029) — the sidebar header ships.
  - ~~**«Медиатека» now or later?**~~ **Answered: later**, together with its screens (P5); four rows today.
  - **«Поиск»** as a separate screen, or «Каталог» opened with the search field focused (what P1 ships).
  - **Hero carousel on «Главная»** — part of this redesign or its own ADR (the reference's most visible
    element).
  - **Collapsed pill wording** — the section name, which is what the system shows today.

## Known caveats

- A free Apple ID cannot produce App Groups, so a Top Shelf extension cannot read app data. Plan:
  static Top Shelf imagery or no Top Shelf at all.
- 7-day signing expiry means the app on a physical Apple TV stops launching weekly until re-signed.
  Not observed yet: the first device profile was created on 2026-11-26, so the expiry behaviour is
  still `unverified`.
- Device Hub is useless without the macOS **Local Network** permission for the app (and for Xcode);
  that, not the network, is the usual reason the device list stays empty while `ping`/Bonjour work
  from the terminal.
- The old `api.anilibria.tv` host is gone (HTTP 410). Only `aniliberty.top` / `anilibria.top` work.
- The tvOS simulator runtime unmounts itself occasionally; `xcrun simctl runtime scan-and-mount` brings it
  back without re-downloading (see Environment facts). A `simctl bootstatus -b` can fail with "cannot
  determine the runtime bundle" on a device that `xcodebuild test` then boots by UDID without trouble.
- DSH loads `AGENTS.md` from the repo root (marked by `.git`) down to the session working directory,
  plus a user-global `$DSH_HOME/AGENTS.md`. Nested `AGENTS.md` files are picked up after the agent
  successfully touches a file in that subtree — they are not preloaded.
- The app's in-memory workspace registry is authoritative at runtime: hand-editing
  `~/.dsh/storages/workspace.json` while the app runs is unreliable — register via the GUI.
- `TabView` + `.sidebarAdaptable` on tvOS: **verified** 2026-11-27 in the simulator — the panel expands
  over the content, collapses to a section pill when focus enters the posters, and Left from the first
  poster column returns focus to the panel (`AniTVUITests/NavigationShellUITests`). Its panel is narrower
  than the TV app's and it draws no chevron in the collapsed pill on tvOS 27.2, which the owner may or may
  not want matched.

## Known tooling options (not installed)

- `dsh-xcode-mcp` (54 `mcp__xcode__*` tools, config-only, wraps Apple's `xcrun mcpbridge`).
- `dsh-xcode` (6 tools; requires Xcode 26.3+ and Xcode ▸ Settings ▸ Intelligence ▸ *Allow external
  agents to use Xcode tools*).
- `xcodebuildmcp@2.7.0` (third-party fallback).
- Decision deferred until the first real build is needed.
