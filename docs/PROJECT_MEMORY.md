# PROJECT MEMORY — living state

> Update this file at the end of every session that changes the project's state.
> Rules and constraints live in `AGENTS.md`; decisions live in `docs/DECISIONS.md`.
> Last updated: **2026-11-13** (session 4: app icon + static Top Shelf from the upstream Android TV app;
> ADR 0017, provenance in `docs/THIRD_PARTY_ASSETS.md`).

## Snapshot

| Item | Value |
| --- | --- |
| Stage | **Vertical slice 1 is end-to-end verified.** Feed, release detail and player driven by XCUITest on the tvOS simulator |
| Target platform | tvOS 26.0 (single target for now) |
| Distribution | TestFlight / ad-hoc only. App Store out of scope |
| Apple Developer | **Free** account (7-day profiles, 3 devices, no App Groups/CloudKit/Push) |
| License | **MIT** — confirmed 2026-11-10 (`LICENSE`) |
| Product name | Provisional `anitv` — final name and bundle ID decided later |
| Repository | local, `~/Documents/anitv`, `git init` done, no remote yet |
| DSH workspace | `c714b289-7397-4251-b27c-4ce3ce773cf6` (`~/Documents/anitv`) |
| Physical Apple TV | not available yet (expected ~1 week after launch) |

## Environment facts (verified on this machine)

- macOS **27.0.1** (26A434), arm64. Disk: ~104 GB free.
- Xcode **27.2** (27B52) at `/Applications/Xcode.app`; `xcode-select -p` →
  `/Applications/Xcode.app/Contents/Developer`. License accepted, first-launch components installed.
  **Verified working** (`xcodebuild -version`, `xcrun simctl`, `xcodebuild -showsdks`).
- SDKs: `appletvos27.2`, `appletvsimulator27.2`. Runtime: **tvOS 27.2 (24K150)**, id
  `com.apple.CoreSimulator.SimRuntime.tvOS-27-2`. SDKs are 27.x while the deployment target stays
  26.0 — that is fine and intended.
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

## Next steps (ordered)

1. Exercise the favourite toggle against a live account: the add/remove calls and the rollback path have
   never run with a real token (doing it mutates the owner's favourites, so it needs their go-ahead). Same
   for the `views/history` "continue watching" row, which is not built yet.
2. Replace the borrowed app icon with an original mark before publishing anywhere — see
   `docs/THIRD_PARTY_ASSETS.md`; the current one is AniLibria's brand and comes from a GPL-3.0 repo.
3. Capture real profile / favourites fixtures: the Kit's are synthesised from the OpenAPI schema. The Kit's
   favourites ids/add/remove also assume the documented shapes (a `204` without a body would need the
   decode relaxed).
4. Watch the advisory `ui-tests` CI job on a real GitHub runner; only then consider making it required
   (ADR 0013). Also pin `xcode-select` if the `macos-26` image starts shipping a different default Xcode.
5. Decide the final product name / bundle identifier **before** the repository goes public (renaming the
   directory means re-registering the DSH workspace).
6. Nice-to-haves nobody has asked for yet: a disk tier for the catalogue cache (it is memory-only now) and
   a "continue watching" row on «Новинки» from `views/history`.

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

## Publishing (2026-11-17)

The repository is published at <https://github.com/VetalPros/AniTV> (owner's account, public, MIT).
`docs/PROJECT_MEMORY.md` and `AGENTS.md` are committed on purpose: the project is open by design and
`AGENTS.md` §2.2 forbids secrets, so both stay readable. Before the first push the tree was scanned for
personal data (the account holder's nickname and address appear in no file and in no commit) and for
tokens (none). The Kit's `User-Agent` now carries the real repository URL, which is what the politeness
rule in `AGENTS.md` §2.5 asks for — it used to be a placeholder.

**Still to do before this is a real product:** the app icon is AniLibria's mark (see
`docs/THIRD_PARTY_ASSETS.md` and ADR 0017) and has to be replaced by an original one; the bundle id
(`tv.anitv.client`) and the product name are placeholders chosen before the repository existed.

## Open questions for the user

- Final **product name** and **bundle identifier** — deliberately deferred; the working name is
  `anitv` and the bundle id will be `top.<domain>.<name>` once the name is chosen. Renaming the
  directory later means re-registering the DSH workspace, so decide before the repository goes public.
- Whether to enable an Xcode MCP bridge now or after the first successful build.

## Known caveats

- A free Apple ID cannot produce App Groups, so a Top Shelf extension cannot read app data. Plan:
  static Top Shelf imagery or no Top Shelf at all.
- 7-day signing expiry means the app on a physical Apple TV stops launching weekly until re-signed.
- The old `api.anilibria.tv` host is gone (HTTP 410). Only `aniliberty.top` / `anilibria.top` work.
- The tvOS simulator runtime unmounts itself occasionally; `xcrun simctl runtime scan-and-mount` brings it
  back without re-downloading (see Environment facts). A `simctl bootstatus -b` can fail with "cannot
  determine the runtime bundle" on a device that `xcodebuild test` then boots by UDID without trouble.
- DSH loads `AGENTS.md` from the repo root (marked by `.git`) down to the session working directory,
  plus a user-global `$DSH_HOME/AGENTS.md`. Nested `AGENTS.md` files are picked up after the agent
  successfully touches a file in that subtree — they are not preloaded.
- The app's in-memory workspace registry is authoritative at runtime: hand-editing
  `~/.dsh/storages/workspace.json` while the app runs is unreliable — register via the GUI.

## Known tooling options (not installed)

- `dsh-xcode-mcp` (54 `mcp__xcode__*` tools, config-only, wraps Apple's `xcrun mcpbridge`).
- `dsh-xcode` (6 tools; requires Xcode 26.3+ and Xcode ▸ Settings ▸ Intelligence ▸ *Allow external
  agents to use Xcode tools*).
- `xcodebuildmcp@2.7.0` (third-party fallback).
- Decision deferred until the first real build is needed.
