# PROJECT MEMORY — living state

> Update this file at the end of every session that changes the project's state.
> Rules and constraints live in `AGENTS.md`; decisions live in `docs/DECISIONS.md`.
> Last updated: **2026-11-10** (session: first vertical slice — scaffolding + release feed).

## Snapshot

| Item | Value |
| --- | --- |
| Stage | **Vertical slice 1 works.** Scaffold + live "Latest releases" feed on the tvOS simulator |
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

## Next steps (ordered)

1. **Prove the rest of the slice by hand**: open a poster → detail screen → episode → playback.
   The detail and player screens compile and are wired, but no remote input has been delivered to the
   simulator yet, so their behaviour is **unverified**. Needs a manual run (simulator + remote) or an
   XCUITest target.
2. App icon (layered tvOS icon: 2 layers + App Icon) and Top Shelf decision (static or none, given the
   free account cannot share app data).
3. Каталог tab (genres + catalogue listing) and Профиль tab (Keychain-stored token, login state).
4. Cache/conditional-request pass on the API client (ETag / `If-None-Match`), per the politeness rule.
5. Pin `xcode-select` in CI if the `macos-26` image starts shipping a different default Xcode.
6. Decide the final product name / bundle identifier **before** the repository goes public (renaming the
   directory means re-registering the DSH workspace).

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
