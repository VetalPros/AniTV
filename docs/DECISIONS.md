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

---

## 0017 — The app icon is the upstream service's mark (2026-11-13)

> **Corrected 2026-11-17 by ADR 0025.** The mark is *AniLiberty's*; «AniLibria» is a different brand that
> belongs to unrelated people. The use is now permitted in writing, so the "risk we knowingly accept"
> framing below is history, kept as written at the time.

**Context.** The build had no icon at all: `Assets.xcassets` contained only `AccentColor`, so actool
warned that no `App Icon & Top Shelf Image` collection existed and the app appeared on the tvOS home
screen as a white placeholder. The user asked for the icon of the official Android TV app, pointing at
<https://github.com/anilibria/anilibria-app>.

Two facts about that source: the repository is **GPL-3.0** while this one is MIT, and the artwork is
the service's brand mark — the very thing `AGENTS.md` §1 forbids using as product identity.

**Decision.** Take it anyway, at the owner's explicit request, and record the trade-off instead of
hiding it: the monogram was extracted from `ic_launcher-playstore.png`, re-composed into tvOS layers
(`Back` plate + `Front` mark, 400×240 and @2x) plus a static Top Shelf image, and
`docs/THIRD_PARTY_ASSETS.md` states the provenance, the GPL-3.0 origin and the trademark caveat with
the instruction to replace the mark before publishing.

**What it cost to make it work** (all found by compiling, not by reading docs):
- A brandassets entry with `size: 1280x768` makes the whole image stack 1280×768, and then the last
  layer must fill it — which contradicts the 400×240/800×480 layer sizes tvOS actually renders. With
  `size: 400x240` every rendition (flattened + radiosity, 1x and 2x) is produced.
- Layers must be named `Back` and `Front` and live in `Content.imageset` folders with both scales.
- The **first** entry in `layers` is the visible one; with the plate listed first the icon rendered as
  a plain red rectangle with no mark (seen on the simulator home screen), so the mark layer comes first.
- A plain `AppIcon.appiconset` is not an option for this SDK: actool reports the image as an
  "unassigned child" and emits nothing.

**Consequences.** The app has a real icon and a static Top Shelf image.
One more property of the format, learned the same way: the system **aspect-fills** the Top Shelf
artwork and cuts the sides, so the first version — mark at 8.5 % of the width — came out clipped on
the home screen. The artwork is now composed inside a safe box (left margin 14.5 %) with the wordmark
and the "неофициальный клиент" note next to the mark.
 Note for future sessions: the
Top Shelf is only drawn while the app tile holds focus on the home screen; with focus elsewhere the
system shows its own wallpaper, so an unfocused screenshot proves nothing about the asset. The licensing and trademark questions are open by design and are tracked in
`docs/THIRD_PARTY_ASSETS.md` — resolving them means commissioning an original mark, which is a
product decision, not a coding one.

---

## 0018 — Playback progress lives in the Kit, one record per release (2026-11-16)

**Context.** The viewer had no way back into an episode: the player forgot the position the moment it
was dismissed. The data is small (a position, a duration, a timestamp), but it sits behind the same
rule as everything else here — logic in the Kit, thin views — and it needs to survive relaunches,
which rules out in-memory state.

**Decision.** `AniLibertyKit/Persistence/` owns it: a `PlaybackProgress` value with the resume rules as
pure logic (resumable only past 15 s and not inside the last 30 s; unknown duration means only the
lower bound applies), a `PlaybackProgressStoring` protocol for injection, and a `PlaybackProgressStore`
writing one JSON object per release alias into `UserDefaults`. The store is a `Sendable` class rather
than an actor: Swift 6 region isolation refuses to hand a non-`Sendable` `UserDefaults` to an actor's
initialiser, and thread safety is `UserDefaults`'s own documented guarantee.

**Consequences.**
- The app stores honestly — even a position the Kit considers unresumable is written — and the UI asks
  `resumableProgress(forReleaseAlias:)`. One place decides what "resumable" means.
- One position per release, not per episode: watching another episode moves the single record, so
  «Продолжить» always returns to the most recently watched episode of that release.
- The detail screen waits for the release before taking focus, so the button it focuses is the one that
  matches the stored progress. Tests that assert "the screen took focus" accept either hero action.

---

## 0019 — Episode cards follow the site, and «Смотреть» asks which episode (2026-11-16)

**Context.** The user compared the release screen with the official site and asked for the site's
episode grid: full-bleed previews in three columns with the title, «N эпизод» and a length pill over
the still. They also asked for «Смотреть» to stop guessing which episode to start and offer a choice.

**Decision.** The card is rebuilt as an overlay (`EpisodeCard`): the preview fills it, a bottom scrim
carries the text, the length sits in a pill, and focus scales and outlines it like every other card.
The eager three-column `Grid` moved into `EpisodeGrid`, the section into `EpisodeSection`. «Смотреть»
presents `EpisodePickerScreen` — a `fullScreenCover` with its own focus engine, default focus on the
episode the player would have chosen (the resumable one first), Menu closing it without playing.
«Продолжить» deliberately does not open the picker: it means "go on with exactly that episode".

**Two parts of the site's UI are consciously not reproduced**, and the report says so rather than
faking them:
- the «⋮» button in the card's corner — on tvOS it needs its own focusable control inside a focusable
  card and a behaviour nobody has defined;
- the «Просмотрено N из M» counter — the progress store keeps one record per release, so the app
  cannot honestly count how many episodes were watched. That becomes possible with the per-episode
  progress listed in the roadmap.

**Consequences.** Episodes are now three per row, so a release with many episodes makes the detail
screen taller; the picker is the quick path. The UI tests that used to assume Select on «Смотреть»
starts playback now assert the picker leg first — the behaviour change is covered, not worked around.

---

## 0020 — The catalogue is a search field over chips, and the grid must not steal focus (2026-11-16)

**Context.** The «Каталог» tab was a placeholder. The API offers one paged endpoint with everything
under an `f` object (`POST /anime/catalog/releases`), plus five reference endpoints for the filter
values; the useful numbers are recorded in `docs/api-notes.md`.

**Decision.**
- **One filter chip per dimension**, single choice each: genre, type, year, sorting. Genres are not
  multi-select because the API *intersects* them — `[25]` returns 147 releases, `[25,24]` returns 10 —
  so a multi-select would quietly produce empty screens.
- **Year is sent as a one-year range** (`from_year = to_year`), because the reference years are not
  contiguous (1997 is missing) and a continuous range would invent values.
- **Search is a real `TextField`** with the system keyboard, debounced 400 ms, and the empty string is
  sent as "no search" rather than as an empty query.
- **Paging appends; filtering replaces.** A filter change resets to page 1, «Показать ещё» appends and
  de-duplicates by release id.
- **The results grid gives up its default focus** (`ReleasePosterGrid(takesDefaultFocus: false)`): with
  it, entering the tab jumped straight into the posters and the search field never got focus. The tab
  now opens on the search field.

**Focus layout, learned the hard way.** With the chips *inside* the grid's scroll view, the focus
engine never reached them: entering the screen landed on the first poster row and Up from the grid
went straight to the tab bar. Moving the controls back out, above the scroll view, produced a working
chain (tab bar → search field → chip row → grid and back). The chips row is one focus section, and
Down from the search field lands on the chip under the field's centre — usually «Год», not «Жанр» — so
the UI test walks that row leftwards instead of pretending the first chip is one press away.

**Verified end to end** by `CatalogUITests`: the tab loads 1946 releases, a genre filter changes the
count and shows on the chip, typing «маска» into the system keyboard narrows the catalogue to 6
results (the same number the API returns when asked directly), reset restores the full count, and a
poster still opens the release screen.

---

## 0021 — Signing in on a TV is a pairing code, not a password form (2026-11-16)

**Context.** The «Профиль» tab needs an account: the service's favourites and history endpoints are
bearer-authenticated. On a ten-foot UI with a directional remote, a login/password form is hostile —
and it would have put a password through our own code path for no reason.

**Decision.** The tab signs in by device pairing: `POST /accounts/otp/get` with a per-install device id
returns a six-digit code that lives five minutes; the viewer enters it on the site or in the mobile
app; the TV polls `POST /accounts/otp/login` every three seconds and trades the accepted code for a
token. The token goes straight into the Keychain (`AuthTokenStoring`/`KeychainTokenStore`), never into
`UserDefaults`, a log line or a view. A rejected token (403 on `profile`) is deleted silently and the
screen returns to pairing instead of showing an error. The password flow exists in the Kit for other
clients but the TV screen does not use it.

**Two behaviours of the live service shaped this.**
- `otp/login` answers **500 `{"message":"Server Error"}`** while the code is not yet accepted. That is
  now a dedicated, documented `otpNotAccepted` case — treating it as a failure would have made the
  polling loop give up immediately.
- Repeating `otp/get` with the **same** device id returns the **same** code and expiry (verified with
  curl). A «Обновить код» button would therefore have done nothing visible, so refreshing rotates the
  stored device id first; the id stays stable across launches and only changes on an explicit refresh.

**Consequences.** Pairing works without ever handling a password, and the app has no login form to
secure. What the tab cannot prove by itself is everything behind the token: the profile view, the
favourites grid, «Выйти» and the dead-token branch have never run against the live service, because
this project has no account to accept a code with. They stay marked 🚧 in the README until someone
with an account completes the pairing once.

---

## 0022 — Pairing works, and the fixes were outside the API (2026-11-17)

ADR 0021 described the pairing design; making it actually work took four separate defects, each one found
from a log rather than a guess. They are recorded because the same shapes will bite again.

1. **The handshake needs a clean session.** `otp/login` answered 403 "This action is unauthorized."
   from the app's shared `URLSession`, while curl — and a macOS test process — got the documented answer
   (500 while pending, 200 with a token once accepted). The pairing and account calls now use
   `URLSessionTransport.ephemeral()`, and the initializer that installs `URLCache.shared` was taught not
   to reinstate it for that session.
2. **Any refusal while polling means "keep waiting".** The endpoint documents 401 for "OTP not bound to a
   user" but answers 403; a 500 is what curl gets. Both map to `otpNotAccepted`, and only 422 (the code
   itself is rejected) stays a real error.
3. **Codes can be re-issued under a new device id.** «Обновить код» rotates the device id because the
   service returns the same code for the same id; rotating orphans whatever was already being typed. The
   screen now remembers every code it asked for, drops expired ones and polls the whole set.
4. **The profile request hung because it ran in a cancelled task.** After the token arrived, the polling
   task cancelled itself and then awaited the profile call from inside; the `URLSession` child it needs
   never started, so the call never returned — no timeout, no error, and the screen kept the pairing
   panel. Loading the profile from a fresh task fixed it, and the call is now also wrapped in a
   watchdog with a shared-session fallback.

**Verified end to end with a real account** on the simulator: pairing → token in the Keychain → profile
200 (472 bytes) → favourites page 1 → the UI shows the display name, the login and the favourites grid →
«Выйти» deletes the token and returns to a fresh pairing code. No screenshot of that state is committed:
it carries the account holder's name and address.

---

## 0023 — Per-episode progress, favourites from the detail screen, and a catalogue cache (2026-11-17)

Three features asked for together; the decisions that are not obvious:

**Progress is stored per episode, in one key per release.** `PlaybackProgress` always carried
`episodeID`, but the store kept a single record per release, so watching episode 5 overwrote episode 3 and
«Продолжить» could only ever offer one position for the whole title. The key
`tv.anitv.playbackProgress.<alias>` now holds a JSON array of records. `progress(forReleaseAlias:)` returns
the most recent one by `updatedAt` (ties go to the further position, the more informative point), and
`progress(forReleaseAlias:episodeID:)` returns one episode. The first `save` after the update rewrites a
legacy single-object payload into the array shape; nothing is lost, and a test writes the old payload by
hand to keep that promise honest. Downgrading is not supported: an older build reads the array as "no
data", which is recorded on the store's documentation.

**Favourites use the documented mutation endpoints.** `GET /accounts/users/me/favorites/ids` answers a
plain array of integers; `POST` and `DELETE /accounts/users/me/favorites` take `[{"release_id": 9023}]`
and answer with the resulting list of identifiers, so the UI can settle the heart without a second request.
The `DELETE` carries a body, which `URLSession` supports but which has to be set on the request explicitly.
These go through the same clean account session as the profile: the shared session is answered with 403 by
this service (ADR 0022). The shape comes from the OpenAPI document — no authenticated call has been
captured yet, and the tests say so.

**The catalogue is cached by query, not by HTTP validator.** Measured on 2026-11-17:
`POST /anime/catalog/releases` replies `cache-control: no-cache, private` and carries **no** `etag`, and a
request that sends `If-None-Match` still gets `200` with the whole body. A conditional request therefore
saves nothing, so the kit keeps its own actor, `CatalogCache`, keyed by page + limit + a fingerprint of the
filter (value order does not matter). Entries live five minutes and the cache holds a bounded number of
pages, dropping the oldest insertion; `catalog(page:limit:filter:refresh:)` bypasses and rewrites the entry
when the viewer asks for a refresh or changes the filter. The cache is in memory only: a relaunch pays for
the first page again, which is acceptable at this size and avoids inventing an eviction policy for a disk
tier nobody asked for.

---

## 0024 — Screens keep themselves fresh, on a policy rather than on guesses (2026-11-17)

The complaint was concrete: a release added to favourites on the website shows up there immediately, but
the app kept the list it had loaded when the tab was first opened, and «Новинки» only ever reloaded on
launch. Both screens now refresh themselves.

**One policy, one timer.** `AutoRefreshPolicy` owns the numbers and the launch-argument overrides;
`RefreshLoop` is the only implementation of "when do we reload". Screens call `setVisible` from
`onAppear`/`onDisappear`/`scenePhase` and nothing else — there is no second timer to drift.

**The numbers.** «Новинки» reloads every 300 s: a feed of fresh episodes does not change faster, and one
request per five minutes per TV is invisible for the service while the grid still feels live. Favourites
reload every 180 s, but the interval is the *secondary* trigger there — coming back to the tab after more
than 60 s away reloads immediately, which is exactly the "added it on the site, went back to the TV" case.
A shorter staleness window would refetch on every quick look at «Каталог».

**Polite by construction.** Nothing runs while a screen is hidden or the app is in the background: the loop
is *cancelled*, not paused, so a TV left on a shelf makes no requests. A background reload never enters the
loading state, and when the payload is unchanged the model keeps the same array, so focus and scroll are not
disturbed (a tvOS grid that rebuilds under the remote is worse than stale data).

**Testability.** A five-minute interval cannot be observed in a UI test, so the two intervals are injectable
with `-uiTestingRefreshInterval` and the staleness window with `-uiTestingStaleAfter`, read through the same
factory pattern as `-uiTestingSignedOut`. Production never passes them. `AutoRefreshUITests` then proves a
real self-refresh in about ten seconds by watching the «Обновлено HH:mm» caption change with the screen
untouched — a caption that exists because the viewer also deserves to see the list is live.

**Not asserted:** the production intervals themselves (only their values in `AutoRefreshPolicy`), the
absence of requests on a hidden tab (there is no request counter in the app), and the "content really
changed → show it" branch, because the live feed does not change within a test run.

### Follow-up (same day) — why the first attempt did not show it

The first version refreshed favourites on a timer and when a tab came back after more than a minute. The
owner still saw a stale list after favouriting a title **from the app itself**, because the profile is
usually reached seconds later, well inside that window, and the initial load cancelled the timer at the
same moment it started it (`refresh()` called `stopAutoRefresh()`).

Three changes, each with its own reason:

- The favourites screen now re-reads on **every** entry, with a three-second floor only to stop a tab
  bounce from firing twice. It is one cheap authenticated request, and the viewer's mental model is
  "I come back, I see it".
- A confirmed toggle in the release screen posts `.anitvFavoritesChanged`; a visible profile re-reads
  immediately instead of waiting for the next tick. The two screens are separate view models in separate
  tabs, so there is no shared state to mutate — a notification is the smallest honest link.
- A screen that reloads itself re-arms the loop (`restartIfVisible()`); cancelling it is reserved for
  teardown. The earlier build left the timer dead after the first load.

Still unverified: whether the service's list endpoint reflects a `POST /favorites` immediately. The POST
itself answers with the resulting identifiers, so the app knows the truth, but the list is read back with
a separate call; if that call lags, the screen will keep showing the old order until the next refresh. The
log now records both numbers (the count the toggle reports and the count the list returns) so one
reproduction answers it.

---

## 0025 — The service team answered, and the answer settles the branding questions (2026-11-17)

We wrote to the AniLiberty team before publishing and they replied in detail. Recorded here because each
point removes a constraint this project had been designing around.

**The icon is allowed.** «Иконка нас устраивает, если это иконка именно AniLiberty (буквы AL в кольце)…
Мы не против, если вы её будете использовать». Ours is exactly that monogram, so the borrowed-mark risk
that ADR 0017 flagged is closed by permission rather than by replacement. The two conditions attached are
already satisfied: the icon must be their mark, and the project must not monetise access to their
releases — AniTV is free, without subscriptions or ads. The GPL-3.0 provenance of the source artwork stays
noted in `docs/THIRD_PARTY_ASSETS.md`: we ship a trademark used with permission, not a GPL derivative.

**The name is ours to choose.** «Можете использовать любое своё название, если оно не пересекается с
официальными названиями и не пытается под них маскироваться». «AniTV» and `tv.anitv.client` stay.

**The `User-Agent` policy was the right call.** «По User-Agent требования уже выполнены, мы действительно
обращаем внимание на этот идентификатор», and there are no strict request limits — they prefer to talk to
a source that loads them before blocking it. Caching and the refresh intervals of ADR 0024 are therefore
politeness, not compliance.

**Streaming restrictions, and the exemption we rely on.** They have banned using their CDN to play their
content on other resources, and an unapproved use of their HLS streams leads to a CDN ban and then an API
block — but: «т.к. приложения на AppleTV — дефицитный товар, то в Вашем случае мы не будем ничего
ограничивать». This is a permission for *this* client, not a general licence, and it depends on the app
staying what it is: a player of the streams the API hands it, nothing re-published, nothing monetised.

**One request we owe them.** «AniLibria больше не наш бренд и принадлежит другим людям, никак с нами не
связанными» — every mention of AniLibria that refers to *this service* has to say AniLiberty. The rename
was applied to `AGENTS.md`, `README.md`, this log and `docs/THIRD_PARTY_ASSETS.md`; web addresses and the
`anilibria/anilibria-app` repository keep their names, because a URL is not a brand statement.

---

## 0026 — The skip hint lives inside the player, and the ending rule lives in the kit (2026-11-17)

The owner could not press the skip control at all, saw it overlap the transport bar, and wanted a way to wave
the hint away. Four things were wrong, and each fix is a general lesson rather than a patch.

**A SwiftUI overlay above `AVPlayerViewController` is not focusable.** The button sat in a `ZStack` over the
player representable and never joined the focus engine, so the remote could not reach it — the worst kind of
bug, because it looks like a rendering issue and is actually a dead control. Custom controls over video on
tvOS belong in `AVPlayerViewController.contentOverlayView`; the hint is now a plain `UIView` with a
`UIStackView` of two `UIButton`s rather than a `UIHostingController`, because a hosted SwiftUI view inside the
overlay gave focus to the first button only.

**`preferredFocusEnvironments` on the overlay pinned focus to the first button.** Returning `[skipButton]`
from the container was consulted on every focus update, so Left/Right moved to «Смотреть» and were pulled
straight back. Removing the override — and granting initial focus once from the controller — made the second
control reachable. The general rule: `preferredFocusEnvironments` is an *initial* target, not a leash.

**"The transport bar is open" has no public signal.** The overlay's view tree exposes only private
`AVNowPlaying*` views whose alpha and bounds do not distinguish the open state, and AVKit has no delegate
callback for it. The honest substitute is focus: the hint asks for focus once when it appears, the transport
bar can then open, focus leaves the overlay and `didUpdateFocus` hides the hint; it comes back when focus
returns and the playhead is still inside the segment. Measured and asserted in
`testHintHidesWhileTheViewerIsInThePlayerControls`. The z-order fix (the hint sits below the system UI inside
the content overlay) means it can no longer overlap the bar even in the moment before focus moves.

**The ending offer depends on what follows the credits, and that rule belongs in the kit.** Some episodes
carry 26, 43 or 120 seconds of content after the `ending` range — an insert or the next-episode preview —
and skipping straight to the next episode would throw it away. `EndingOfferResolver` (five unit tests) decides:
a tail of 15 seconds or less means «Следующая серия», anything longer means «Пропустить эндинг» and a seek to
the end of the range. The threshold sits between the two clusters measured across six releases (0–12 s and
25 s+). The player only *asks* for the next episode; switching stays in the detail screen, which owns the
picker.

**Still not proven by a test:** that «Следующая серия» actually starts the next episode — the UI test needs a
release whose current episode has a short ending, and the feed's first release does not always have one
(`XCTSkip` with that reason). The label and the decision are covered by the unit tests.

### Follow-up to 0026 (same day) — the hint is never hidden, it is moved instead

Hiding the hint while the viewer was in the player controls was the one part of 0026 that did not survive
contact with a real remote. Focus is the only signal available, and focus is exactly what moves when the
viewer presses Right to reach «Смотреть»: the hint disappeared for a frame and the button they were aiming at
went with it. A control that vanishes as you reach for it is worse than one that overlaps something.

So the rule is reversed deliberately: **the hint stays for as long as the playhead is inside the segment**,
whatever focus does, and the layout keeps it clear of the transport bar — it sits 300 pt above the bottom
edge, above the scrubber, the elapsed time and the quality chips. `PlayerSkipUITests` now asserts the
opposite of what it asserted yesterday: with the bar open the hint is still there, and its frame does not
intersect the bar's own time label.

The other lesson from the same round: **Left/Right between the two buttons was not reliable** from layout
alone — a Right press sometimes left the hint for the player's controls. Two one-point-wide `UIFocusGuide`s,
one on each side of the gap between the buttons, pin the direction; two consecutive full-suite runs passed
after that, where before it failed roughly one run in three.

---

## 0027 — Device builds sign automatically, and the team lives in a gitignored xcconfig (2026-11-26)

**Context.** Everything so far was built for the simulator, where ad-hoc signing was enough
(`CODE_SIGN_IDENTITY: "-"`, `CODE_SIGN_STYLE: Manual`). A physical Apple TV appeared (Apple TV 4K,
tvOS 27.2.1) and the only Apple ID available is a **free Personal Team**. A device build cannot proceed
without a development team, and the team ID identifies a personal developer account, so it must not enter
a public repository (AGENTS.md §2.2, §4).

**Decision.** The target signs automatically. `project.yml` pins `CODE_SIGN_STYLE: Automatic` and nothing
else: no team, no identity, no provisioning profile specifier. The team arrives from
`Config/Base.xcconfig` (committed, referenced as the target's configuration file for both build
configurations), which contains a single optional include:

```
#include? "Local.xcconfig"
```

The included file is gitignored and holds one line, `DEVELOPMENT_TEAM = <team>`. `.gitignore` covers it
next to the already-ignored `Config/Secrets.xcconfig`.

**Alternatives rejected.** XcodeGen's environment substitution
(`DEVELOPMENT_TEAM: ${DEVELOPMENT_TEAM}`) writes the literal `${DEVELOPMENT_TEAM}` into the generated
project when the variable is unset, and that string then surfaces in the Xcode UI; a committed team ID
publishes the account identifier; pointing `configFiles` straight at the gitignored file fails spec
validation in CI — verified: *"Target has invalid config file path … for config Debug"*.

**Consequences.** `xcodegen generate` without the local file still succeeds, and the simulator/CI build
with `CODE_SIGNING_ALLOWED=NO` still passes (checked both ways on 2026-11-26). Installing on hardware is a
one-line local setup plus `-allowProvisioningUpdates` in the build. Measured on the first device build: the
free team issued an *Apple Development* certificate and a *tvOS Team Provisioning Profile*, and the
`keychain-access-groups` entitlement from `App/AniTV.entitlements` survived signing as
`<TEAM>.tv.anitv.client` — the earlier assumption that Keychain Sharing requires a paid account was wrong
for this entitlement. The 7-day expiry from ADR 0003 now applies to real hardware; the repeatable
procedure, the free-account limits and the troubleshooting table live in `docs/INSTALL_DEVICE.md`.

---

## 0027 — Skip behaviour becomes a setting, and the hint becomes a single control that expires (2026-11-18)

The two-button hint of ADR 0026 did not survive the owner's remote: «Кнопка "Смотреть" всё также недоступна,
при нажатии вправо просто идёт перемотка». Focus inside `AVPlayerViewController.contentOverlayView` kept
landing on the player's own scrubber, so Right seeked instead of moving to the second control, and every fix
aimed at the second button (focus guides, focus granting, hiding rules) was a crutch around a design that had
one button too many.

His redesign replaces it, and it is better than what we had:

- **«Настройки» is a tab of its own** (fourth, after «Профиль»). Two switches — «Автоматически пропускать
  опенинги» and «Автоматически пропускать эндинги» — both **off** by default, so nothing is ever skipped for a
  viewer who did not ask. Values live in `PlaybackSettingsStore` (`UserDefaults`; these are preferences, not
  secrets) and are saved on every change.
- **One hint, no «Смотреть».** The control appears when the playhead enters a segment and disappears **30
  seconds later if nobody presses it**, and does not come back for that segment. No countdown on the button —
  the owner preferred a quiet disappearance to a ticking number.
- **Auto-skip means silent**: openings seek to `opening.end` with no hint at all; endings seek to `ending.end`
  and *then* offer «Следующая серия» for 30 seconds, because the tail may hold an insert (the reason for the
  15-second rule of ADR 0026, which still decides whether the button says «Пропустить эндинг» or «Следующая
  серия» when auto-skip is off).
- **The crutches are gone**: the second button, the dismiss/`dismissedSkipKey` machinery, the focus guides and
  the mutable appearance. One `UIButton`, the player's own chip look, and it takes focus when it appears — the
  UI test now asserts `hasFocus` and that Select acts on it, which is the check that was failing before.

The settings are read once when a playback session starts. Changing a switch in «Настройки» while the player
is open does not affect the session already running — documented as a known limitation rather than pretended
away.

The 30-second lifetime is injectable through `-uiTestingHintLifetime`, so a test can watch a hint expire in
four seconds instead of thirty; production never passes it.

---

## 0028 — Navigation becomes the system sidebar, not a hand-built shell (2026-11-27)

*The log already carries two `0027` entries (a merge artefact of 2026-11-26). This entry takes the next
free number rather than renumbering history.*

**Context.** The owner asked for a cardinal change of the top-level navigation and pointed at the system
Apple TV app as the reference. The shipped shell is one floating top bar of four `TabView` tabs.

The reference was measured on the owner's own hardware rather than on a mockup: Apple TV 4K
(AppleTV18,1), tvOS 27.2.1 (24K157), `xcrun devicectl device capture screenshot`, 1920×1080 captures in
both the expanded and the collapsed state. It is a floating glass panel — avatar, name, clock, a search
row, icon rows with a white pill on the focused one — that **overlays** a full-bleed hero, and collapses
to a single pill carrying the current section. Width ≈ 340 pt, leading and top insets ≈ 40, radius ≈ 36.
The captures stay out of the repository: they are Apple's UI and this repository is public. The numbers
and the described behaviour are what the redesign is held to. `docs/NAVIGATION.md` holds the full spec.

**Decision.** Build the shell on the system style, not by hand:

- `TabView` + `.tabViewStyle(.sidebarAdaptable)`; sections are `Tab`s, search is
  `Tab(role: .search)` and the system pins it above the rest, exactly as the reference does.
- One `NavigationStack(path:)` per section, as today. The shell owns the selection and the section list
  and nothing else — no networking, no view models.
- No hand-written width animation, no custom collapse logic: the system's state machine, and therefore
  Reduce Motion, come for free.
- Section order: search, «Главная», «Каталог», «Профиль», «Настройки». «Медиатека» joins when the
  favourites / continue-watching screens exist; the row is not shipped dead.

**Evidence, gathered before the decision.** `TabViewStyle.sidebarAdaptable` is `@available(… tvOS 18.0)`
in the AppleTVOS27.2 SDK's `SwiftUI.swiftinterface`; `TabSection` and `Tab(role: .search)` likewise. A
throwaway app (`.build/navspike/`, gitignored, never part of the project) with six tabs was built for the
tvOS 27.2 simulator, installed and captured: the style renders the reference for free — floating rounded
panel, white pill, «Поиск» as its own magnifier row, content dimmed and full-bleed behind it. Its panel
is narrower than the TV app's (≈ 235 vs ≈ 340) and it has no header block, which is the one visible gap.

**The header is deferred, and that is deliberate.** `tabViewSidebarHeader`/`Footer` are
`@available(… tvOS 27.0)`, while the project's baseline is 26.0 (ADR 0009) and AGENTS.md forbids
`#available` fallbacks. So the first shell ships **without** the avatar/clock block: a working sidebar
now, and one decision (`bump the minimum to 27.0?`) instead of one guarded branch. The owner's own box
already runs 27.2.1.

**Consequences.**

- `RootTabView` is deleted; the shell is a new view under `App/Sources/App/`.
- Six UI-test files walk focus into the old tab bar by accessibility identifier (`sparkles.tv`,
  `square.grid.2x2`, `person.crop.circle`, `gearshape`, in `LatestFeedUITests`, `CatalogUITests`,
  `AutoRefreshUITests`, `PlayerSkipUITests`, `DetailResumeUITests`, `DetailEpisodePickerUITests`) — all
  of them are rewritten against the new shell, with the helpers centralised in `UITestSupport.swift`.
- `ScreenHeader`'s `.top` padding of 56 assumed a top bar above it; under a sidebar the title sits in the
  content's own top-left corner, as in the reference.
- New localisation keys `nav.*`; existing `tab.*` wording is reused for row titles.

**Fallback clause.** "The panel collapses when focus leaves it, and Left from content returns to it" is
**unverified**: this session had no input channel into the simulator. The first navigation UI test must
prove it. If it does not hold, this ADR is superseded by a hand-built shell — not patched around it.

**Alternatives rejected.**

- *Hand-built sidebar* (`HStack` + `@FocusState` + `GlassEffectContainer`): we would reimplement the
  panel, its collapse state machine, its scroll behaviour and its accessibility, in the exact area where
  this project has already lost days (ADR 0020's focus chain, the ADR 0026→0027 retreat from a second
  player button). The system style is maintained by Apple and costs a `tabViewStyle` modifier.
- *Keeping the current top bar and only retheming it*: the owner rejected that look; it is a retheme, not
  the asked-for change.
- *Adopting the header now by bumping to tvOS 27*: an irreversible narrowing of the supported audience on
  the strength of one cosmetic row. Left as an open question for the owner.
