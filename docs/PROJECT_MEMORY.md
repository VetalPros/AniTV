# PROJECT MEMORY — living state

> Update this file at the end of every session that changes the project's state.
> Rules and constraints live in `AGENTS.md`; decisions live in `docs/DECISIONS.md`.
> Last updated: **2026-11-10** (session: environment bring-up).

## Snapshot

| Item | Value |
| --- | --- |
| Stage | **Pre-code.** Environment setup. No source files yet |
| Target platform | tvOS 26.0 (single target for now) |
| Distribution | TestFlight / ad-hoc only. App Store out of scope |
| Apple Developer | **Free** account (7-day profiles, 3 devices, no App Groups/CloudKit/Push) |
| License | **MIT** — confirmed 2026-11-10 (`LICENSE`) |
| Product name | Provisional `anitv` — final name and bundle ID decided later |
| Repository | local, `~/Documents/anitv`, `git init` done, no remote yet |
| DSH workspace | **not registered yet** — must be added in the GUI by path |
| Physical Apple TV | not available yet (expected ~1 week after launch) |

## Environment facts (verified on this machine)

- macOS **27.0.1** (26A434), arm64. Disk: ~104 GB free.
- Xcode **27.2** (27B52) installed from the App Store at `/Applications/Xcode.app`.
  - `xcode-select -p` still points to `/Library/Developer/CommandLineTools` → **`xcodebuild` and
    `simctl` do not work yet**. Requires `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
    and `sudo xcodebuild -license accept` (needs the user's password — cannot be automated here).
  - tvOS simulator runtime: **not downloaded yet** (`xcodebuild -downloadPlatform tvOS`).
- Tooling: Homebrew 7.0.11, git 2.54.0, Swift 6.4, Node v24.3.0, npm 11.4.2, python3 3.9.6
  (CommandLineTools one — not a project dependency).
  - Installed via Homebrew and verified: **xcodegen 2.46.0**, **xcbeautify 3.2.1**,
    **swiftlint 0.65.1**, **swiftformat 0.64.6**.
- No standalone "Apple TV emulator" exists: the tvOS **Simulator** ships inside Xcode and is driven
  by `xcrun simctl` / `xcodebuild`.

## Done

- [x] Xcode 27.2 installed from the App Store.
- [x] Researched the environment: what the tvOS simulator is, how it is driven from the CLI.
- [x] Researched the target Apple platforms/APIs (Liquid Glass availability, AVPlayerViewController
      metadata/menu APIs, focus APIs, String Catalogs, layered tvOS icons).
- [x] Verified the AniLiberty public API surface and HLS playback by hand (see `api-notes.md`).
- [x] Created the repository skeleton: `AGENTS.md`, `docs/`, `AniLibertyKit/`, `git init`.
- [x] Wrote the agent working agreement (Agent Teams + memory protocol).
- [x] Added `LICENSE` (MIT), `.gitignore`; installed `xcodegen`/`xcbeautify`/`swiftlint`/`swiftformat`.
- [x] Decisions confirmed by the owner: **MIT**, **tvOS 26.0 minimum**, provisional name `anitv`.

## Next steps (ordered)

1. **User runs in Terminal** (needs password):
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   sudo xcodebuild -runFirstLaunch
   xcodebuild -downloadPlatform tvOS
   ```
   Verify: `xcrun simctl list runtimes` (a tvOS runtime must appear),
   `xcodebuild -showsdks | grep -i appletv`, `xcrun simctl list devices available | grep -i "apple tv"`.
2. Register this directory as a DSH workspace (GUI → add workspace → `~/Documents/anitv`).
3. Scaffold the project: `project.yml` (XcodeGen), `AniLibertyKit` package with `Models/`, `API/`,
   `Cache/`, `Player/`; a tvOS app target with an empty "Latest releases" screen.
4. `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, `.swiftlint.yml`,
   `.swift-format`, CI workflow (`.gitignore` and `LICENSE` already exist).
5. First vertical slice: `GET /anime/releases/latest` → grid of poster cards → release detail →
   episode list → HLS playback in `AVPlayerViewController`.
6. Play the whole slice in the simulator before adding features.

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
