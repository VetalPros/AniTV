# OpenChamber — how work is organised in this harness

Written 2026-11-28. `AGENTS.md` holds the rules, `docs/HANDOFF.md` the state; this file only explains
how those rules are carried out when the harness is OpenChamber. It is not a second rulebook.

## Roles

- **Lead session** — owns the shared files (`project.yml`, `Package.swift`, `AGENTS.md`, `docs/`),
  runs the gates, and is the only one that commits. It also owns `docs/PROJECT_MEMORY.md` and the
  ADR log.
- **Child sessions** — one per task, each with a self-contained prompt: the goal, the paths it owns,
  the conventions from `AGENTS.md`, how to verify, and "do not edit files outside your scope". They
  never `git commit`, `git push` or rewrite history.
- A child's "done" is a claim. The lead reads the diff and re-runs the build and tests before
  accepting it.

## Shared board = Project knowledge

OpenChamber has no external task board. The lead records tasks in **Project knowledge**: todos with
dependencies where one task must land before another, and notes for context that does not belong in a
commit. That board is harness state, not repository state — `docs/PROJECT_MEMORY.md` and the ADR log
remain the durable record that survives a harness change.

## Worktrees

Work that needs its own checkout runs in a git worktree branched from the **working branch**:
`startRef = feat/sidebar-navigation`. Never branch from `main` — it is 20 commits behind (19 when
`docs/HANDOFF.md` was written) and has neither the sidebar shell nor the release pipeline. Merging
`feat/sidebar-navigation` into `main` is the owner's decision; agents do not merge.

## Gates and commands

Nothing here is a new rule — the definition of done is `AGENTS.md` §6. The exact commands:

```bash
xcodegen generate
```

```bash
xcodebuild -project AniTV.xcodeproj -scheme AniTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (4th generation)' \
  -derivedDataPath .build/DerivedData build | xcbeautify
```

```bash
swift test --package-path AniLibertyKit
```

```bash
swiftlint --strict
swiftformat .
```

```bash
xcodebuild test -project AniTV.xcodeproj -scheme AniTV \
  -destination 'platform=tvOS Simulator,id=1CEE9693-F8EB-45A4-8223-1679EE0EFC5A' \
  -derivedDataPath .build/DerivedData | xcbeautify
```

The UDID is the stable simulator destination: the tvOS 27.2 runtime installs only
`Apple TV 4K (4th generation)` devices, so a `3rd generation` destination fails to resolve.

## What this environment does not have

- **No `Simulator.app`.** The simulator is headless (`simctl` only), so nothing can be clicked by hand
  and AppleScript cannot drive it: any input has to be an XCUITest in `App/UITests/`. Screenshots come
  from `xcrun simctl io booted screenshot`.
- **No input channel into the physical Apple TV.** `xcrun devicectl` installs, launches and captures
  screenshots; it cannot press the remote. State that needs a key press is produced by the owner on
  the remote or by an XCUITest.
- **No DSH tools** (`team_task_create`, `spawn_teammate`, `wait_agent`, `team_task_list`). They are
  replaced by child sessions, Project knowledge and worktrees, as above.

## Pitfalls

Each of these is already understood — check `docs/HANDOFF.md` §5 before re-debugging one:

- A sandboxed session fails package resolution (`Missing package product 'AniLibertyKit'`); the build
  needs write access to `~/Library/Caches/org.swift.swiftpm`.
- The sidebar rows focus as anonymous containers: walk the panel with `ShellNavigator`, never by
  counting presses.
- `TabView` unloads unselected sections, so `@State`, focus, scroll position and loaded data die with
  them.
- The full-screen player hides the sidebar by design: Back first, then the panel.
- Icon stacks need two layers at 400×240 and 1280×768, plus `2x` top-shelf images.
- Build numbers must be numeric (`yyyymmddHHMM`); `altool` rejects anything else.
- The UI suite is timing-fragile; a test that fails only in a full run may still be hiding a real bug.
