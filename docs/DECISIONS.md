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

**Decision.** MIT (`LICENSE`, "Copyright (c) 2026 AniTV contributors"). Confirmed by the project
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

---

## 0010 — Modifier ordering belongs to SwiftFormat, not SwiftLint (2026-11-10)

**Context.** SwiftFormat 0.64.6 and SwiftLint 0.65.1 demand opposite modifier orders for
`nonisolated` members. The formatter writes `private nonisolated static func …`; the linter's
`modifier_order` rule wants `nonisolated private static func …`. SwiftLint 0.65.1 has no
`nonisolated` token in `preferred_modifier_order`, so any attempt to align the order is rejected
with "Invalid configuration" and the rule silently falls back to its default. Running both gates
therefore made the two tools fight over the same two files, with no convergent state.

**Decision.** `modifier_order` is listed in `disabled_rules` of `.swiftlint.yml` (with the reason
written next to it). Modifier ordering is owned by SwiftFormat and still enforced in CI through
`swiftformat --lint .`, which runs before `swiftlint --strict`. No other rule is relaxed.
Additional consequence recorded at the same time: `identifier_name` excludes the geometry
identifiers `x`, `y`, `i`, `j`, `dx`, `dy`, which are meaningful in layout code.

**Consequences.** One gate owns this concern instead of two contradictory ones; anything a
formatter normalises must not also be policed by the linter. Revisit when a SwiftLint release
accepts `nonisolated` in `preferred_modifier_order` — then the rule can be re-enabled in the
formatter's order.

---

## 0011 — Shared error mapping on the Kit type, not per view model (2026-11-10)

**Context.** Two view models (`ReleaseDetailViewModel`, `LatestReleasesViewModel`) each carried an
identical `mapError` helper, and both tripped the SwiftLint/SwiftFormat `nonisolated` modifier-order
conflict (ADR 0010) because the helper needed `nonisolated static func`.

**Decision.** The mapping lives once as an extension on the Kit type
(`AniLibertyError.mapped(_:)` in `App/Sources/Support/AniLibertyError+Mapping.swift`). A non-actor
type's extension is implicitly `nonisolated`, so no attribute — and therefore no ordering conflict —
is involved.

**Consequences.** Duplication removed, and the tool conflict can no longer recur through this path.
The mapping stays in the app (not the Kit) because it converts transport-level errors into the Kit's
error type and would otherwise pull Foundation networking semantics into the Kit's public surface.

---

## 0012 — UI verification goes through XCUITest, and the detail screen claims focus itself (2026-11-11)

**Context.** The first vertical slice was proven only as far as "the feed renders real data": the
installed Xcode ships **no `Simulator.app`** (`find /Applications/Xcode.app -name Simulator.app`
returns nothing, and `open -a Simulator` fails with "there is no such file"), so neither a human click
nor AppleScript/System Events can deliver input to the tvOS simulator. `simctl` has no remote-input
command at all. A `bundle.ui-testing` target (`AniTVUITests`, driven by `XCUIRemote`) is then the only
way to exercise the remote, and it is also the only repeatable one.

Writing that test surfaced a real defect rather than a test problem: after the detail screen was
pushed, nothing on it held focus, so a Menu press was handled by the system and backgrounded the app
instead of popping the navigation stack. A pushed screen that refetches its own data has no focusable
content at push time, and the focus engine does not pick one up when the content arrives.

**Decision.** Keep the end-to-end scenarios as XCUITests in `App/UITests/`, assert on
`accessibilityIdentifier`s rather than on coordinates or Russian strings, and take screenshots as
`XCTAttachment`s so the evidence survives the run (`docs/screenshots/` is exported from them). The
detail screen declares `defaultFocus(_:priority: .userInitiated)` on its primary action (the synopsis
toggle when the release is not playable) and re-requests focus once after the push transition, because
the engine drops requests made during the transition.

**Consequences.** "The screen compiles" and "the screen works" are now separable: `-only-testing:
AniTVUITests` answers the second question, and it is the only path to it in this environment. The test
depends on the live AniLiberty API and a booted simulator, so it is slow and it is advisory in CI
(ADR 0013). Each new interactive surface is expected to come with an identifier and a scenario.

---

## 0013 — The UI test job in CI is advisory, not required (2026-11-11)

**Context.** The `ui-tests` job runs the XCUITest suite on a GitHub-hosted macOS runner. It boots a
tvOS simulator (slow and, on a developer machine, occasionally wedged), waits for the live AniLiberty
API, and had never been executed on a hosted runner when it was written — the only evidence is green
local runs.

**Decision.** Add the job as an **advisory** check: `continue-on-error: true` on the test step, the
failing `.xcresult` uploaded as an artifact and a warning written to the job summary. `build-test-lint`
stays the required gate. The job is not listed in branch protection as required.

**Consequences.** A red UI run is visible but never blocks a pull request, and the failure mode of the
job itself (runner image without a tvOS runtime, tool download failing) cannot turn `main` red. Promote
it to required by deleting `continue-on-error: true` after a track record on that runner; if it turns
out to be flaky only because of simulator boot time, move it to a `schedule:` trigger instead.

---

## 0014 — Quality switching is a modal chooser, not a transport-bar item (2026-11-11)

**Superseded by ADR 0016 (2026-11-13):** a single `UIMenu` in the same API *is* reachable, so the
modal chooser described below no longer exists. The findings about flat `UIAction`s and about a
SwiftUI overlay drawn over the player still hold.

**Context.** The player had no way to change stream quality. The sanctioned hook,
`AVPlayerViewController.transportBarCustomMenuItems`, was implemented first: one `UIAction` per
quality, each carrying a rendered "1080p / 720p / 480p" image (tvOS renders these items from their
image only — the title never appears on screen, it stays the VoiceOver label). The items did appear
in the transport bar and were listed in the accessibility tree as `Cell`s with the right labels. They
were still unusable: with a tree dump taken between remote presses, focus sat on the pill only until
the first arrow press, after which the player view took focus (`Other` covering the whole screen) and
the items could never be reached again — no press sequence found a path back. The same happened to a
SwiftUI row drawn over the player: it received default focus, and the first arrow press handed focus
back to AVKit, whose transport bar owns every direction while the player is on screen.

**Decision.** The player shows one glass pill with the running quality (`player.qualityButton`,
top-trailing, holding default focus when the player opens). Choosing it presents
`QualityPickerScreen` through `fullScreenCover`: a modal that gets the focus engine to itself exactly
like the player does when the detail screen presents it, with one large button per available stream
and the current one checked. Selecting replaces the player item and seeks back to the playhead
(`PlayerModel.selectQuality`).

**Consequences.** Quality switching works with the remote and is covered by a UI test. It is not part
of the system transport bar, which is a departure from "no custom transport UI": the system genuinely
cannot express the choice here, and the alternative — items that render but cannot be focused — is
worse than an honest app-level control. The system timeline, info panel and scrubbing stay
first-party and untouched. Revisit if AVKit starts giving transport-bar items focus.

---

## 0015 — The detail screen must not disable scroll clipping (2026-11-11)

**Context.** The release detail screen pushed from the feed never scrolled: five Down presses left the
screen pixel-identical and `detail.episodeCard` never entered the accessibility tree, so genres, the
synopsis and the whole episode list were unreachable (found by the user on a manual run, reproduced by
an XCUITest probe). Two causes compounded: `.scrollClipDisabled()` on the `ScrollView` makes it report
its entire content as visible, so the focus engine believes everything is already on screen and never
scrolls; and `LazyVGrid` only instantiates cells that intersect the visible area, so the episode list —
whose first row is below the fold — had no cells at all, hence nothing focusable, hence no reason for
anyone to scroll.

**Decision.** Drop `.scrollClipDisabled()` (a comment in the view says why it must not come back), and
build the episode list with the eager `Grid` instead of `LazyVGrid`. A release has a handful of
episodes, so rendering them all costs nothing.

**Consequences.** Down/Up walk the whole screen with the focus engine scrolling it, which the new UI
test asserts by focusing an episode card and playing it. The same trap applies to any future
scrollable screen: `scrollClipDisabled` + lazy containers is a combination that silently disables
remote navigation.

---

## 0016 — Quality is a `UIMenu` in the system transport bar (2026-11-13)

Supersedes ADR 0014, which concluded that the transport bar cannot host a usable quality control.

**Context.** ADR 0014 was written after flat `UIAction`s passed to
`transportBarCustomMenuItems` rendered in the bar but never took focus: with a debug tree dump taken
between remote presses, every arrow press handed focus back to `AVPlayerViewController` and the items
were unreachable. Re-testing that conclusion with the *other* shape of the same API changed it: one
`UIMenu` (title, image, one action per stream) becomes a real transport-bar button that the focus
engine reaches and that opens the system popup menu. The remaining difficulty is only traversal —
the bar's focus order is not "two presses to the right" but a system collection order, so the UI test
walks it instead of assuming a path.

**Decision.** The quality control is one `UIMenu` entry in `transportBarCustomMenuItems` whose image is
the running quality drawn as text ("1080p"), because tvOS renders these entries from the image alone
and never shows the title. It therefore appears and disappears with the transport bar — no permanent
overlay over the video — and the popup is the system one («Качество», 1080p ✓ / 720p / 480p). The
modal `QualityPickerScreen` and the floating pill from ADR 0014 are deleted.

**Consequences.** The player has no custom chrome again: one system entry, the system menu, the
system timeline. The entry is re-applied only when the selected quality or the stream list changes, so
it does not close under the viewer's finger. Cost: the entry has no accessibility identifier (it is a
system element), so the UI test addresses it by its localized title and walks the bar to focus it.
