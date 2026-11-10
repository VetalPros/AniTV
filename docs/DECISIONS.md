# DECISIONS — append-only log

Format: `## NNNN — Title (YYYY-MM-DD)`, then Context / Decision / Consequences.
Append only. To change a decision, add a new entry that supersedes the old one.

---

## 0001 — tvOS 26.0 as the single minimum target (2026-11-10)

**Context.** The client must look and feel like a first-party Apple TV app, including Liquid Glass.
`glassEffect(_:in:)` and `GlassEffectContainer` exist only on the 26.x SDKs; supporting older tvOS
would require availability branches and two visual languages.

**Decision.** Ship for tvOS 26.0+ only. No `#available` compatibility code, no fallback UI.
The shared Kit declares `platforms: [.macOS(.v14), .tvOS(.v26), .iOS(.v18)]` so that it can be
built and unit-tested with the host toolchain (`swift test`) without a simulator.

**Consequences.** Users on tvOS 18/25 cannot install the app. The codebase stays small and has one
visual language. The Kit's lower iOS/macOS floors keep the CLI test loop fast.

---

## 0002 — Monorepo with a shared `AniLibertyKit` package (2026-11-10)

**Context.** tvOS now, iOS/macOS later. Duplicating models, API client and caching across targets
is the classic way to fork a codebase by accident.

**Decision.** One repository: `AniLibertyKit` (SPM, `Models/`, `API/`, `Cache/`, `Player/`) plus thin
platform targets that only contain UI and platform glue. Business logic never lives in views.

**Consequences.** The Kit is testable without a running app; platform targets stay small; adding
iOS/macOS later means adding a target, not a rewrite. Discipline is required: no networking in
`App/Sources`.

---

## 0003 — TestFlight-only distribution on a free Apple Developer account (2026-11-10)

**Context.** The user owns a free Apple ID and does not intend to publish to the App Store.
Free accounts cannot use App Groups, CloudKit, Push, Sign in with Apple, or TestFlight itself.

**Decision.** Target TestFlight/ad-hoc for the long term, but design so the app works under
free-account limits today: no App Groups, no CloudKit-dependent features, no push. Favourites,
watch history and timecodes are stored **server-side** through the AniLiberty API
(`/accounts/users/me/...`), which is what a paid account would have used CloudKit for.
Top Shelf stays static or absent.

**Consequences.** 7-day provisioning expiry must be documented for testers (and re-signing is a
routine task). Any future "premium" feature must not rely on entitlements the project cannot ship.

---

## 0004 — XcodeGen instead of a committed `.xcodeproj` (2026-11-10)

**Context.** `project.pbxproj` is a merge-conflict generator, and this project expects parallel
work by multiple agents.

**Decision.** `project.yml` is the source of truth; `.xcodeproj` is generated (`xcodegen generate`)
and never committed. Schemes, targets and build settings are declared in YAML.

**Consequences.** Contributors must run `xcodegen generate` before building (documented in README and
`AGENTS.md`). CI generates the project too. Parallel agents never fight over a binary-ish plist.

---

## 0005 — No third-party dependencies (2026-11-10)

**Context.** Typical needs are networking, image loading and caching — all achievable with
Foundation/AVFoundation, and third-party packages are the main source of supply-chain risk in an
open-source project that people will build with a free Apple ID.

**Decision.** `Package.swift` keeps an empty `dependencies` array. API client, image cache
(actor + `URLCache` + in-memory LRU), HLS URL handling and OTP login are written in-house.
Any exception requires its own ADR entry here.

**Consequences.** More code to own, but no dependency churn, no abandoned packages, and a fully
auditable supply chain.

---

## 0006 — Native-only UI, Liquid Glass via system materials (2026-11-10)

**Context.** "Maximum natively, by all Apple canons" is an explicit user requirement.

**Decision.** SwiftUI + Observation (`@Observable`), system components (`TabView`, `NavigationStack`,
`AVPlayerViewController`), Liquid Glass through `glassEffect`/`.ultraThinMaterial`. No custom blur,
no imitations of system chrome, no web views for core UI. Focus handling is implemented with the
focus engine (`prefersDefaultFocus`, `FocusState`, `.onMoveCommand`), not with manual hit testing.

**Consequences.** Some bespoke visual ideas may be impossible or need to be reshaped to Apple's
patterns. In exchange the app feels native, gets system accessibility for free, and survives OS
redesigns.

---

## 0007 — Agent Teams as the default execution model (2026-11-10)

**Context.** The project is developed through DSH sessions; context does not persist between them,
and single-agent work serialises independent chunks.

**Decision.** Non-trivial work is split across DSH Agent Teams ("Команда Агентов"): a shared task
board with disjoint write scopes, teammates for independent chunks, the Lead for integration,
verification and commits. Rules are written down in `AGENTS.md` §3.

**Consequences.** Faster on parallelisable work, but requires discipline: a teammate's report is a
claim, not evidence, and the Lead must run the build and tests itself.

---

## 0008 — MIT license (2026-11-10)

**Context.** The project is fully open source and permissively licensed forks are welcome.

**Decision.** MIT (`LICENSE`, "Copyright (c) 2026 anitv contributors"). Confirmed by the project
owner.

**Consequences.** Forks may ship closed derivatives — accepted. No patent grant (unlike
Apache-2.0); revisit only if patent concerns appear.

---

## 0009 — Build with Xcode 27.2 / tvOS SDK 27.2, deploy to 26.0 (2026-11-10)

**Context.** The only toolchain on the machine is Xcode 27.2 with the tvOS 27.2 SDK and simulator
runtime. Decision 0001 fixed the deployment target at 26.0.

**Decision.** Build and test with the installed 27.2 SDK; keep `IPHONEOS_DEPLOYMENT_TARGET`-style
tvOS deployment target at **26.0**. No second SDK is installed.

**Consequences.** Every API used must be available in tvOS 26.0, not 27.x — the compiler warns but
runtime failures are what matter, so anything newer must be guarded by `#available` or avoided.
The simulator runs 27.2, so 26.0-only behaviour is never exercised directly; that is accepted until
a real device or a 26.x runtime is available.
