# Handoff: starting work on AniTV in another harness

Written 2026-11-28 for the owner to hand this repository to a different coding agent (OpenChamber /
OpenCode, Claude Code, Codex — anything). `AGENTS.md` carries the rules; this file carries the **state**
that no rule file can know: which branch is real, what is finished, what is broken, where the secrets are,
and which failures are already understood.

Read this first, then `AGENTS.md`, then `docs/PROJECT_MEMORY.md`.

---

## 1. Start on the right branch

```
main                        aeb2e3c  ← the old tab-bar UI, 19 commits behind
feat/sidebar-navigation     0160189  ← the real state: sidebar shell, rails on «Главная», TestFlight
```

```bash
git switch feat/sidebar-navigation      # do this before anything else
git pull
```

A new agent that starts on `main` will see a `TabView` with a top bar that has already been replaced.
Everything below describes `feat/sidebar-navigation`.

The branch is pushed; the working tree is clean. Merging into `main` is the owner's decision, not the
agent's — do not merge on your own.

## 2. What is done

- **Navigation**: the system sidebar (`.tabViewSidebarHeader` + `.tabViewStyle(.sidebarAdaptable)`), four
  rows (Поиск, Главная, Каталог, Настройки), the account in the panel header (opens the profile as a
  cover), per-section navigation paths in `ShellNavigationState`.
- **«Главная»**: two rails — fresh releases, and favourites sorted by `fresh_at`.
- **«Поиск» / «Каталог»**: one screen, two modes (`CatalogView.Mode`).
- **Tests**: 31 UI tests (28–31 green depending on the account state, 1 usually skipped), 91 Kit tests.
- **Delivery**: `scripts/release-testflight.sh` archives, exports, validates and uploads; TestFlight build
  `202611280945` reached `VALID`, `202611280951` was uploaded with the 2x top-shelf fix.

## 3. What is open (and what to pick up first)

From `docs/PROJECT_MEMORY.md` → Next steps, most useful first:

1. **Focus and scroll are not restored when a section comes back.** `TabView` unloads an unselected
   section, so it returns to the top and refetches. Fixing it needs an external `FocusState` in
   `ReleasePosterGrid` (pattern already used by `EpisodeGrid`), a `ScrollViewReader`, and the view models
   lifted above the tabs. Lifting the models was tried and **reverted** — the feed stopped loading, so that
   failure is the first thing to understand.
2. **«Медиатека»** (P5): favourites + continue-watching, plus a row in the panel. Blocked on nothing now
   that the account is paid (App Groups are available; not needed for this).
3. **Empty/failed favourites rail** is not covered by tests.
4. **Known product issue**: after auto-skipping the credits the «Следующая серия» chip does not take focus.
   Recorded as an expected failure — investigate as a player bug, not by raising timeouts.
5. **Store listing**: the home screenshot shows the signed-in account name, and the icon in the App Store
   slot is the service's mark (borrowed, ADR 0025). Both need attention before a public listing.

## 4. Environment facts the agent will not guess

| Fact | Value / command |
| --- | --- |
| Project generation | `xcodegen generate` — `project.yml` is the source of truth, `.xcodeproj` is never committed |
| Simulator | UDID `1CEE9693-F8EB-45A4-8223-1679EE0EFC5A`, tvOS 27.2 runtime; **no `Simulator.app`**, so input only through XCUITest |
| Physical Apple TV | paired, reachable over the local network; install/launch/screenshot through `xcrun devicectl` (see `docs/INSTALL_DEVICE.md` and the memory's device section) |
| Signing | automatic; the team comes from the **gitignored** `Config/Local.xcconfig` (`DEVELOPMENT_TEAM = …`). It is already created on this Mac — do not commit it and do not invent a new one |
| App Store Connect | app record **AniTV**, App Store id `6840296537`, bundle id `tv.anitv.client` |
| Upload credentials | **not in the repository, by design.** The owner holds the App Store Connect API key (`.p8` under `~/Downloads/AuthKey_*.p8`) and exports `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, `APPLE_P8_PATH` in the shell before running the release script. Ask the owner; never commit them |

### Commands that must be green before a commit

```bash
swift test --package-path AniLibertyKit
xcodebuild -project AniTV.xcodeproj -scheme AniTV \
  -destination 'platform=tvOS Simulator,id=1CEE9693-F8EB-45A4-8223-1679EE0EFC5A' \
  -derivedDataPath .build/DerivedData build
swiftlint --strict && swiftformat .
```

## 5. Failures already understood — do not re-debug from zero

- **`Missing package product 'AniLibertyKit'`** while the SwiftPM manifest cache cannot be written:
  the build needs write access to `~/Library/Caches/org.swift.swiftpm`. In a sandboxed harness this appears
  as a resolution failure, not as a permissions error. Run the build with normal file access.
- **The sidebar's rows focus as anonymous containers.** Their `Button`s keep the SF Symbol identifiers
  (`house`, `gearshape`, …) but are `Disabled`; the focus engine reports an unnamed row container, and the
  account header sits *above* the rows and is focusable too. `ShellNavigator` in
  `App/UITests/UITestSupport.swift` walks the panel geometrically (Left → clamp Up → step Down, skipping
  the header). Any new test must use it instead of counting presses by hand.
- **`TabView` unloads sections**: `@State` inside a section dies with it. Paths live in
  `ShellNavigationState`; focus, scroll and loaded data do not survive (measured: the freshness caption
  moved 13:38:35 → 13:38:56 across one switch).
- **Full-screen player hides the sidebar by design** — Back first, then the panel.
- **tvOS delivery needs two icon stacks**, each with **at least two layers** (400×240 home screen and
  1280×768 App Store), plus `2x` top-shelf images. `actool` rejects a single-layer stack.
- **Build numbers must be numeric**; `altool` rejects anything else. The release script generates
  `yyyymmddHHMM`.
- **The UI suite is timing-fragile.** The player and catalogue suites poll for state (`UITestWait`); the
  rest still sleep. A full run can fail one test that passes alone — check for a real bug first (the
  "Menu at a section root sends the app Home" bug hid among those flakes for exactly that reason).

## 6. Documentation map

| File | What it holds |
| --- | --- |
| `AGENTS.md` | Rules: constraints, conventions, build/test/run, Agent Teams policy |
| `docs/PROJECT_MEMORY.md` | Living state: what works, environment facts, next steps, open questions, caveats |
| `docs/DECISIONS.md` | 33 ADRs — every architectural choice and why |
| `docs/NAVIGATION.md` | Sidebar/rails design, focus rules, what a section switch keeps |
| `docs/RELEASE.md` | TestFlight checklist, credentials, troubleshooting table |
| `docs/APPSTORE.md` | Store metadata drafts, age rating, review notes, screenshot list |
| `docs/PRIVACY.md` | Published privacy policy (RU/EN) |
| `docs/api-notes.md` | Verified AniLiberty API and HLS facts |
| `docs/INSTALL_DEVICE.md` | Installing on the physical Apple TV |

## 7. Harness differences worth knowing

- `AGENTS.md` §3 mandates DSH **Agent Teams** (`team_task_create`, `spawn_teammate`). Those tools exist only
  in DeepSeek Harness. In any other harness, say so explicitly in the answer and work sequentially — the
  file already allows that; do not silently pretend a team was used.
- The rules in `AGENTS.md`, `docs/PROJECT_MEMORY.md` and the ADRs are harness-neutral. If your harness does
  not preload `AGENTS.md`, read it yourself before touching code.
- Memory is the only handoff channel: update `docs/PROJECT_MEMORY.md` in the same commit as the code, and
  append an ADR when you make an architectural choice. That is what makes the next handoff cheap.
