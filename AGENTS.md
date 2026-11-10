# AGENTS.md — working agreement for AI agents in this repository

This file is the entry point for every AI agent (DSH sessions, subagents, teammates) working
on this project. Read it fully before the first action. It is loaded automatically by DSH from
the repository root.

Repository root: this directory. Session working directory MUST be inside it.

---

## 1. What this project is

A **native Apple TV (tvOS) client for AniLiberty / Anilibria** — a Russian anime streaming service.
Later milestones add iOS and macOS targets that share the same core.

Traits that define the project:

- **Fully open source.** The repository is public. Everything written here is world-readable.
- **Native by the book.** SwiftUI, Swift 6 strict concurrency, system components only
  (`AVPlayerViewController`, `TabView`, `NavigationStack`, focus engine). No web views for core UI,
  no cross-platform UI frameworks, no third-party Swift packages without an ADR.
- **tvOS 26.0 as the minimum target.** Liquid Glass (`glassEffect`, `GlassEffectContainer`) is used
  unconditionally — no `#available` branches for older OS versions.
- **Distribution: TestFlight only** (and ad-hoc/simulator during development). The App Store is out
  of scope. Signing uses a **free** Apple Developer account — see constraints in §2.
- **Unofficial.** The project name, bundle identifier and branding must never claim to be official
  and must not use the "AniLiberty"/"Anilibria"/"Libria" trademarks as product identity.

Read `docs/PROJECT_MEMORY.md` for current state and `docs/DECISIONS.md` for the decision log.

---

## 2. Hard constraints (never violate)

1. **Free Apple Developer account.** Consequences that shape design, not a temporary annoyance:
   - No App Groups → Top Shelf extension cannot read app data; Top Shelf must be either static
     imagery or omitted.
   - No CloudKit, no Push Notifications, no Sign in with Apple.
   - Provisioning profiles expire in 7 days; at most 3 devices. Builds must be re-signed regularly.
   - Never write code that silently depends on a paid entitlement.
2. **No secrets in the repository, ever.** No API keys, no `sessionToken`, no credentials, no
   `.p12`, no `.mobileprovision`. The user's session token lives in the **Keychain** only.
   CI runs on public runners with no secrets.
3. **No third-party dependencies** (`Package.swift` dependencies list stays empty) unless an ADR in
   `docs/DECISIONS.md` justifies it. The API client, image cache and HLS handling are hand-written
   on top of Foundation/AVFoundation.
4. **No reverse engineering of paid/protected content.** The client only uses the public
   AniLiberty HTTP API. Do not attempt to bypass geo-blocking, ads or any access control.
5. **Politeness to the upstream service.** One `User-Agent` with the repository URL, conditional
   requests / caching, no request storms, no scraping of unrelated endpoints.
6. **Do not rename or restructure top-level directories** without an ADR — the DSH workspace is
   registered by path.

---

## 3. Agent Teams — mandatory working mode

This project is built with DSH **Agent Teams** ("Команда Агентов"). Using it is not optional for
non-trivial work.

**Use Agent Teams (Lead + teammates + shared task board) whenever a task:**

- touches more than ~2 source files, or
- spans more than one module (Kit / tvOS app / docs / CI), or
- can be split into independent, verifiable chunks (screens, API endpoints, localisations, tests).

**Procedure for the Lead:**

1. Restate the goal, then split it into tasks with **disjoint write scopes**
   (`team_task_create` with `write_scopes`, e.g. `Sources/App/Player/`, `AniLibertyKit/Sources/API/`).
2. Add dependencies (`blocked_by`) when one task must land before another.
3. Spawn teammates with self-contained prompts (`spawn_teammate`): goal, paths they own, the
   conventions from this file, how to verify, and the rule "do not edit files outside your scope".
4. Keep the write scopes disjoint. Two agents never edit the same file concurrently. The Lead
   owns shared files (`project.yml`, `Package.swift`, `AGENTS.md`, `docs/`).
5. Wait for results (`wait_agent`, `team_task_list`), then **verify**: read the diff, run the build
   and tests yourself. A teammate's "done" is a claim, not evidence.
6. Report to the user in Russian: what changed, what was verified, what stayed unverified.

**Hard rules:**

- No teammate starts a task without claiming it on the shared board first.
- No teammate runs `git commit`, `git push`, or history rewriting. Only the Lead commits, and only
  after a green build.
- The Lead is responsible for the final state of `main`. Never leave the repository non-building.
- If Agent Teams tools are unavailable in the current session, say so explicitly in the answer and
  fall back to sequential work — do not silently pretend a team was used.

Small single-file edits, one-line fixes and pure Q&A do not need a team.

---

## 4. Project memory — mandatory protocol

Context does not survive between sessions. Memory is therefore explicit and versioned:

| File | Role | Update policy |
| --- | --- | --- |
| `docs/PROJECT_MEMORY.md` | Living state: what exists, what works, environment facts, next steps, open questions | **Update in every session that changes state** |
| `docs/DECISIONS.md` | Append-only decision log (ADR-lite): decision, date, context, consequences | Append a new entry whenever an architectural choice is made |
| `docs/api-notes.md` | Verified facts about the AniLiberty HTTP API and HLS playback | Update when a new endpoint/behaviour is verified |
| `AGENTS.md` (this file) | Stable rules, constraints, conventions | Change only via a deliberate, reviewed edit |

**Session bootstrap (do this first, before writing code):**

1. Read `docs/PROJECT_MEMORY.md` — especially "Current state", "Next steps", "Open questions".
2. Read the tail of `docs/DECISIONS.md` — do not contradict an accepted decision; if you must,
   write a superseding entry.
3. Skim `docs/api-notes.md` before touching anything network-related.
4. Check the environment section of `PROJECT_MEMORY.md` (Xcode version, simulator availability,
   tooling) and verify anything you depend on — do not trust stale facts blindly.

**Session wrap-up (before the final answer):**

1. Update `PROJECT_MEMORY.md`: move finished items to "Done", rewrite "Next steps", record new
   environment facts and any newly discovered caveats.
2. Append decisions you made on your own to `docs/DECISIONS.md`.
3. If you learned something surprising about the API or playback, write it to `docs/api-notes.md`.
4. Only then commit — memory updates travel in the same commit as the code change.

Never record secrets, tokens, personal data or unverified guesses in memory files. Mark uncertain
statements as `unverified`.

---

## 5. Repository layout

```
AGENTS.md                  this agreement
docs/                      memory, decisions, API notes, ADRs
project.yml                XcodeGen project definition (source of truth, not .xcodeproj)
AniLibertyKit/             shared SPM package: models, API client, caching, HLS helpers
  Package.swift
  Sources/AniLibertyKit/
    Models/                Codable DTOs mirroring the API
    API/                   endpoint definitions, transport, error mapping
    Cache/                 actors: image cache, response cache
    Player/                HLS URL building, timecode, resume state
App/                       tvOS application target (later: iOS/macOS targets)
  Sources/
  Resources/               Assets.xcassets, Localizable.xcstrings, Info.plist
Tests/                     unit tests for the Kit
.github/workflows/         CI (build + test on macOS runners)
```

Rules: business logic belongs in `AniLibertyKit`, never in views. Views are declarative and thin.
`App/Sources` may not import anything from the network layer directly other than through the Kit's
public API.

---

## 6. Build, test, run

Generate the Xcode project (never edit `.xcodeproj` by hand, never commit it):

```bash
xcodegen generate
```

Build the Kit + app for the tvOS simulator:

```bash
xcodebuild -project AniTV.xcodeproj -scheme AniTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -derivedDataPath .build/DerivedData build | xcbeautify
```

Test the Kit with the host toolchain (fast loop, no simulator):

```bash
swift test --package-path AniLibertyKit
```

Install / launch in the simulator:

```bash
xcrun simctl boot "Apple TV 4K (3rd generation)"
xcrun simctl install booted .build/DerivedData/Build/Products/Debug-appletvsimulator/AniTV.app
xcrun simctl launch --console-pty booted <bundle-id>
```

Definition of done for any code change: `swift test` green, simulator build green, no new warnings,
formatted with `swiftformat .` and linted with `swiftlint --strict`.

---

## 7. Coding conventions

- **Swift 6 language mode**, strict concurrency, zero data-race warnings. Shared mutable state only
  inside `actor`s or `@MainActor` types.
- **SwiftUI + Observation**: `@Observable` models, `@State`/`@Environment` plumbing. No
  `ObservableObject`/`@Published` in new code.
- **Availability**: target tvOS 26.0 outright. No `if #available` fallbacks for older systems.
- **Liquid Glass**: use system materials and `glassEffect`/`GlassEffectContainer`. Never recreate
  blur with custom `visualEffect` or gradients that imitate the system.
- **Focus is a first-class citizen** on tvOS: `prefersDefaultFocus`, `.defaultFocus`, `FocusState`,
  `.focusable`, `.onMoveCommand`, `.onExitCommand`. Every screen must be fully navigable with the
  remote, with a predictable back path.
- **Player**: `AVPlayerViewController` with `externalMetadata`, `transportBarCustomMenuItems`,
  delegate-driven full-screen transitions and timecode/resume handling. No custom transport UI
  unless the system one genuinely cannot express the feature.
- **Accessibility**: every poster/card carries `accessibilityLabel` (title + year); support
  VoiceOver ordering and Dynamic Type where the platform allows.
- **Localisation**: String Catalogs (`Localizable.xcstrings`), Russian and English. No hard-coded
  user-facing strings in views.
- **Naming**: types and files in English, `UpperCamelCase` types, `lowerCamelCase` members. UI copy
  in Russian.
- **Errors**: typed errors mapped from HTTP status + payload; user-facing messages are localised,
  logs go through `Logger` (never `print` in shipping code).
- **Tests**: Kit logic covered by `swift test`; decode real API fixtures, no network in CI.

---

## 8. Git and review

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`), subject in
  English, imperative mood.
- One logical change per commit; code + memory + changelog in the same commit.
- Never commit: `*.xcodeproj`, `DerivedData/`, `.build/`, secrets, user-specific schemes.
- The Lead runs the build before committing. If the tree is red, fix it or revert — do not commit.

---

## 9. Answering the user

- The user writes in **Russian**. All chat answers, plans and summaries are in Russian.
- Code, identifiers, commit messages, docs in the repository: English.
- Report honestly: what was executed, what was verified by a real command, what is assumed, what is
  blocked (with the exact command or permission the user must provide).
- Never claim a build/test/API result that was not actually observed in this session.
