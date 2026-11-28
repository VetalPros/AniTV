# Navigation shell — design note (for ADR 0028)

Status: **proposal**, waiting on the owner's answers in §10. No code has been written against this
document yet; the only artefact is the throwaway spike described in §2.3.

Scope: the top-level navigation of the tvOS app — how the viewer moves between «Главная», «Каталог»,
«Медиатека», «Профиль» and «Настройки». Player internals, the detail screen's own focus map and the
catalogue's filter behaviour are out of scope and stay as they are (ADR 0014, 0016, 0020, 0027).

---

## 1. Why this exists

The shipped shell is a system `TabView` with four tabs rendered as one floating top bar
(`App/Sources/App/RootTabView.swift`, ADR 0027-era layout). The owner asked for a *cardinal* change of
navigation and pointed at the system Apple TV app as the reference: a floating sidebar instead of a top
bar, content full-bleed beneath it.

Measured on the owner's own hardware, not on a mockup — see §2.

## 2. Evidence

### 2.1 The reference: the system TV app on the owner's Apple TV

Device: **Apple TV 4K (4th generation, AppleTV18,1)**, UDID `00008150-000C62CA0101401C`, name
«Гостиная», tvOS **27.2.1 (24K157)**, paired over the local network, Developer Mode enabled.
Captures were taken on 2026-11-27 with

```
xcrun devicectl device capture screenshot --device 00008150-000C62CA0101401C --destination <file>
```

at 1920×1080, i.e. one capture pixel is one tvOS point.

Observed, expanded state:

- A floating panel of dark glass, inset from the leading, top and bottom edges, with large corner radii.
  It **overlays** the hero; the content behind it is dimmed rather than reflowed.
- Header block inside the panel: round profile avatar, the account name, a clock.
- Then a search row (magnifier, no background), then the sections with icons — «Главная» (house),
  «Apple TV», «MLS», «Магазин» (bag), «Медиатека».
- The focused/selected row is a **white pill with black text**; the rest is grey text on transparency.
- The panel scrolls independently when it holds more rows than fit.

Observed, collapsed state (owner pressed Back on the remote):

- No tab bar and no rail. A single compact pill top-left — «‹ Главная» — carries the current section and
  is the way back into the panel.
- The hero occupies the whole frame: backdrop, «Новое» badge, title logo, metadata line with an age
  badge, a two-to-three line synopsis, then the action row — a white pill «▶ Воспроизвести», two round
  buttons («+», «ⓘ»), a «›» chevron — page dots, and a «Продолжить просмотр» rail of posters below.

Approximate geometry read off the capture (±5 pt): panel leading inset 40, top inset 40, width ≈ 340,
corner radius ≈ 36, row height ≈ 64.

The captures themselves are **not committed**: they show Apple's own UI and this repository is public.
The numbers above are the durable part.

### 2.2 The shipped shell, for comparison

Same device, our app (`tv.anitv.client` 0.1.0) launched with `devicectl device process launch`:
a centred floating top bar, ~915 pt wide, four items, white pill on the focused item, then a large
`ScreenHeader` («Новинки» + subtitle) and a six-column poster grid.

### 2.3 The spike: does the system sidebar exist on tvOS, and does it look like that?

This decides whether we hand-build a shell or configure the system one, so it was checked before
writing the ADR rather than after.

- `TabViewStyle.sidebarAdaptable` — **available from tvOS 18.0** (`SwiftUI.swiftinterface` of the
  AppleTVOS27.2 SDK).
- `tabViewSidebarHeader` / `tabViewSidebarFooter` — **tvOS 27.0+**, `tabViewSidebarBottomBar` —
  unavailable on tvOS. Our minimum is 26.0, so the avatar/clock header is the one part we cannot take
  unconditionally.
- `Tab(_:systemImage:role:.search)` and `TabSection` — tvOS 18.0+.

A throwaway app (`.build/navspike/`, gitignored, **not** part of the project) with six `Tab`s —
search first with `role: .search`, then Главная, Каталог, Медиатека, Профиль, Настройки — and
`.tabViewStyle(.sidebarAdaptable)` was built for the tvOS 27.2 simulator, installed and captured with
`xcrun simctl io <udid> screenshot`.

Result: the system style renders the reference essentially for free — floating rounded glass panel,
white pill on the focused row, «Поиск» as its own top row with the magnifier, content dimmed and
full-bleed behind the panel. Measured there: leading inset 40, top inset ≈ 28, width ≈ 235, corner
radius ≈ 34. The system panel is therefore **narrower** than the TV app's (~235 vs ~340) and has no
header block on tvOS 26.

What the spike could **not** show: the collapsed state and the focus transitions. The spike has no
selection binding (it avoids `@State`), so it demonstrates the chrome, not the state machine. The
simulator has no input channel in this session (no `Simulator.app`, no pointer, no HID injection through
`simctl`), so "focus leaves the panel → it collapses to the current-section pill" remains **unverified**
and is the first thing P1's UI test must prove.

## 3. Decision in one paragraph

Use the **system** sidebar — `TabView` + `.tabViewStyle(.sidebarAdaptable)` + `Tab(role: .search)` —
instead of hand-building a focus-driven panel. It produces the reference behaviour, it is maintained by
Apple, and it deletes the hand-written focus plumbing that a custom shell would need (an area where this
project already has scars: ADR 0020, ADR 0026→0027). What we keep: one `NavigationStack` per section, so
every section keeps its own back path; what changes: `RootTabView` becomes a shell that owns sections,
not a tab bar.

Full rationale and the rejected alternatives: ADR 0028 in `docs/DECISIONS.md`.

## 4. Information architecture

| Section | Value | Icon | Content today | Notes |
| --- | --- | --- | --- | --- |
| Поиск | `search` (role `.search`) | `magnifyingglass` | `CatalogView(mode: .search)` | The system pins it above the sections, as in the TV app. Field only, no chips (ADR 0030). |
| Главная | `home` | `house` | `HomeView` | Two rails: «Новинки» and «Обновления в избранном» (ADR 0031). The favourites rail is drawn only for a signed-in viewer. |
| Каталог | `catalog` | `square.grid.2x2` | `CatalogView(mode: .browse)` | Chips only, no field (ADR 0030). Returns to the panel with this ADR. |
| Медиатека | `library` | `rectangle.stack` | **does not exist yet** | Needs «Избранное» + «Продолжить просмотр»; blocked on memory Next steps 3 and 8 |
| — (header) | account | avatar | `ProfileView` as a cover | The panel header **is** the profile entry (ADR 0032): avatar, name, clock; selecting it opens the cover. There is no «Профиль» row. |
| Настройки | `settings` | `gearshape` | `SettingsView` | Playback switches |

Order matters: search first, content second, account in the header — the reference's order and the one the
`ShellSection` order in the tests follows, because the panel is walked top-down. The header is focusable
and comes *before* the first row, which any press-counting helper has to account for.

«Поиск» and «Каталог» are **two shapes of one screen**, not two screens: `CatalogView.Mode` decides
whether the field or the chips are on display, and both keep their own navigation path. That is how the
row, the pill and the screen title finally agree — before ADR 0030 the only row was labelled «Поиск»
while the screen behind it said «Каталог».

Until «Медиатека» has a screen, the shell ships **without** that row rather than with a dead one. That is
a one-line change either way.

## 5. States, geometry, motion

The system owns the two states; we own what is inside them.

- **Expanded** — panel overlaid on the section content, content dimmed. Present only while focus is in
  the panel.
- **Collapsed** — a small pill with the current section's icon and name; content full-bleed.

Constraints we control:

- Content must not assume a top bar. `ScreenHeader` pads `.top` by 40 on top of the `TabView`'s safe area
  (56 until ADR 0035); under the sidebar the section title sits in the content's own top-left corner, as
  the reference does.
- Content must stay full-bleed (`.ignoresSafeArea()` on backgrounds, hero artwork under any overlay) or
  the reference look collapses to a boxed layout.
- Nothing may be placed in the panel's leading 40 pt except through the panel itself.
- Motion is the system's; we must not add our own width animation. `Reduce Motion` therefore comes for
  free.

## 6. Focus and the remote

The focus engine is the product here; everything below is a requirement, not a nicety.

1. **Entry.** Launch lands on the *current sidebar row*, with the panel expanded — the same state the
   system TV app opens in. A directional press into the content collapses the panel, and content then
   keeps the default focus of its own screen (ADR 0012 — the detail screen claims focus itself).
   Observed on 2026-11-27, not assumed: at launch the focused element is a row container, not a poster.
2. **Collapse on leaving.** Moving right into content collapses the panel. Must be proven by UI test.
3. **Return.** From the leftmost focusable column of a section, Left must reach the panel — including
   from inside a horizontal rail and from a `ScrollView`. History: ADR 0020 had to move controls out of
   the grid's scroll view to make this work.
4. **Back path.** Back inside a section pops its `NavigationStack`; a second Back at the section root
   must collapse the panel (or leave it collapsed), never silently change section; at the outermost level
   Back is the system's (Home).
5. **Player.** The player is a `fullScreenCover` and must not show the panel at all — which also means the
   sidebar is **unreachable while it is up**: a test (or a viewer) that wants another section closes the
   player first. `PlayerSkipUITests` learned this the hard way on 2026-11-27, when a previously skipped
   branch tried to open «Настройки» from inside the player.
6. **The pill is focusable** and shows the current section — it is the only visible navigation affordance
   in the collapsed state, so it needs an accessibility label, not just an icon.

**How a UI test drives the panel** (learned the hard way in P4, and worth knowing before writing another
test): the rows expose ordinary `Button`s whose accessibility identifiers are the SF Symbol names
(`house`, `gearshape`, …), **but those buttons are `Disabled` and are not what the focus engine reports**.
The focused element is an unnamed container, one row tall, pinned to the leading edge, whose `frame.minY`
identifies the row. So a test cannot ask "which row is focused"; it must:

1. press Left until the focused element is that unnamed container (`ShellNavigator.enterPanel`),
2. press Up a few times to clamp to the first row — Up stops there instead of wrapping,
3. press Down once per row (`ShellSection.allCases` order matches the vertical order),
4. press Select and wait for the section's own marker.

All of that lives in `ShellNavigator` in `App/UITests/UITestSupport.swift`; the eight older test files call
it instead of walking a tab bar that no longer exists.

## 7. Routing

One `NavigationStack(path:)` per section. The paths are **owned by the shell**, in
`ShellNavigationState`, and handed to the sections as `@Binding`s — they are not `@State` inside the
section views.

That is not a style preference. `TabView` unloads the content of a section that is not selected, and a
`@State` path dies with it: measured on 2026-11-27, opening a release, visiting «Настройки» and coming
back landed on the grid instead of the release. With the path lifted into the shell the same walk returns
to the open release, which `NavigationStateUITests` now asserts.

**What survives a section switch, and what does not** (all measured, not assumed):

| Thing | Survives? | Why |
| --- | --- | --- |
| Navigation path (pushed release) | **yes** | lives in `ShellNavigationState` |
| Selected section | yes | the shell's own state |
| Grid focus and scroll position | **no** | the section's view is unloaded; it comes back at the top |
| Loaded data | **no** | the view model is `@State` inside the section, so it refetches: the freshness caption moved 13:38:35 → 13:38:56 across one switch (the caption has since left the UI, ADR 0035 — the test probe carries the same instant) |
| Catalogue filters (ADR 0020) | **no** | same reason — the filter state lives in the section's view model |

Restoring focus and scroll is a known limitation, encoded as an expected failure in
`NavigationStateUITests.testGridFocusIsNotPreservedBecauseTheSectionIsUnloaded`. The fix is not a
one-liner: it needs the grid to take an external `FocusState` (the pattern `EpisodeGrid` already uses for
episodes), a `ScrollViewReader` to bring the remembered card back, and the view models lifted above the
tabs so the list does not re-order underneath the remembered id. Lifting the models alone was tried and
**reverted**: with the models owned by the shell the feed never left its loading state, so that path needs
its own investigation before it is attempted again.

The shell owns: the selection, the section list, the section paths, and nothing else. No networking, no
view models.

## 8. Accessibility and localisation

- Panel rows carry `accessibilityLabel` = section name; the current section is exposed as selected.
- The collapsed pill announces "current section: <name>".
- VoiceOver order: panel rows in display order, then content; the panel is one accessibility container.
- Focus order inside a section is unchanged from today's per-screen contracts.
- Keys shipped in `Localizable.xcstrings` (ru + en) in P1: `nav.search`, `nav.home`, `nav.profile`,
  `nav.settings`, `nav.header.title`. The four `tab.*` keys were deleted with the tab bar. `nav.catalog`
  and `nav.library` arrive with their rows (P2's browse surface, P5).

## 9. Phases and write scopes

Every phase is one commit, green before the next. Two agents never own the same file.

| Phase | What | Write scope | Verification |
| --- | --- | --- | --- |
| P1 ✅ | Shell: sections enum, `RootShellView`, search role, sidebar header, localisation keys; `RootTabView` deleted; minimum target raised to 27.0 (ADR 0029) | `App/Sources/App/`, `App/Resources/Localizable.xcstrings`, `project.yml` | **done 2026-11-27**: simulator build green, app launches, panel and pill captured, focus proven by `NavigationShellUITests` |
| P2 ✅ | Content adaptation: one token for the top inset (`DesignTokens.screenTopInset`), `ScreenHeader` uses it, «Настройки» dropped its private header and its hardcoded 80/60 paddings | `App/Sources/Design/`, `App/Sources/Features/Settings/` | **done 2026-11-27**: every section captured in both states by `NavigationSectionsUITests` |
| P3 ◑ | Navigation UI tests: focus leaves the panel and comes back; Back pops the section stack; a section switch keeps the pushed release | `App/UITests/NavigationShellUITests.swift`, `NavigationStateUITests.swift` | **partly done 2026-11-27**: focus round trip, Back semantics and path preservation pass; focus/scroll restoration is a documented limitation (§7) |
| P4 ✅ | Existing UI tests repaired for the new shell: eight files walked focus into the old tab bar, all of them now go through `ShellNavigator` | `App/UITests/` | **done 2026-11-27**: full UI suite on the tvOS 27.2 simulator |
| P5 | «Медиатека» screen, once favourites and continue-watching exist | `App/Sources/Features/Library/` | separate ADR |

What P1 verified, and how: the panel's expanded state, its collapsed state (a pill carrying «Главная»)
and the focus round trip were all exercised on the tvOS 27.2 simulator by
`AniTVUITests/NavigationShellUITests`, which presses the remote through `XCUIRemote` and asserts on
`hasFocus`; its two attachments are the only images of the collapsed state we have. Still open: Back
semantics and per-section path preservation (P3's remainder), and the existing six test files (P4).

What P2 verified: `NavigationSectionsUITests` opens each section through the test-only
`-uiTestingSection` launch argument (`RootShellView.initialSection`), captures it twice — once with the
panel expanded on entry, once after a directional press collapses it — and asserts the screen is on
display. Result: in the collapsed state no section title or control lands under the pill, every screen's
background is full-bleed, and all four sections start at the same `72 / 40` insets. The expanded state
still covers the left third of the content, exactly as the reference does when its panel is open — the
difference is that Apple's content there is artwork and ours is text, so the earlier screenshots looked
worse than they are.

`DesignTokens.screenTopInset` (40 since ADR 0035, 56 before) and `DesignTokens.screenInset` (72) are the
only two numbers any section uses for its frame. Measured on 2026-11-28: the collapsed pill ends at
y ≈ 94 and the first rail title starts at 165.5, so the title clears it by ~70 pt although the inset adds
only 40 — the rest is two stacked safe areas (see `docs/PROJECT_MEMORY.md`). The remaining visual gap to
the reference is not spacing — it is that the reference puts artwork where we put a section title, which
is P5's hero question, not P2's.

## 10. Open questions for the owner (answered 2026-11-27)

1. ~~Minimum target~~ — **answered: raise it to 27.0** (ADR 0029), so the header ships from P1.
2. ~~«Медиатека» now or later~~ — **answered: later**, together with its screens (P5). The panel has four
   rows today.
3. ~~**Search row semantics**~~ — **answered and shipped 2026-11-27** (ADR 0030): «Поиск» and «Каталог»
   are two modes of `CatalogView`, with their own rows, titles and paths.
4. **Hero carousel on «Главная»** — still open; a separate feature with its own ADR.
5. **Collapsed pill wording** — still open; P1 ships the system's own pill with the section name
   («Главная»), which needs no extra work.

1. **Minimum target.** The avatar/clock header inside the panel needs tvOS **27.0**, and the project's
   baseline is 26.0 (ADR 0009; AGENTS.md forbids `#available` fallbacks). Options: ship without the
   header, bump the minimum to 27.0, or accept one guarded branch. The owner's own box runs 27.2.1.
2. **«Медиатека» now or later?** It needs two screens that do not exist. A five-row panel (search,
   Главная, Каталог, Профиль, Настройки) is shippable now; the row appears when the screens do.
3. **Search row semantics.** «Поиск» opening «Каталог» with the field focused (proposed, no duplicate
   state), or a separate screen.
4. **Hero carousel on «Главная».** The reference's most visible element. A separate feature with its own
   ADR — confirm it is not part of this change.
5. **Collapsed pill wording.** «Главная» like the reference, or a neutral «Меню».

## 11. Risks

| # | Risk | Mitigation |
| --- | --- | --- |
| R1 ✅ | Collapsed/focus behaviour of `sidebarAdaptable` was **unverified** — no input channel this session | **closed 2026-11-27** by `NavigationShellUITests`: focus leaves the panel for the posters on a directional press, and Left from the first column returns it. Attachments show both states |
| R2 ✅ | System panel is narrower than the TV app's (~235 vs ~340) and its header is tvOS 27-only | header ships from P1 after the bump to 27.0 (ADR 0029); the width difference is accepted |
| R3 ✅ | UI tests walked focus into the old tab bar by accessibility identifier | **closed 2026-11-27** in P4: eleven test files now call `ShellNavigator`; the panel's rows focus as anonymous containers, which the helper handles (see §6) |
| R4 | White pill over bright hero artwork loses contrast | scrim behind the panel, checked on real artwork |
| R5 | Free account: 7-day profiles, 3 devices — device iteration is slow | simulator first, device captures per phase |
| R7 ✅ | The UI suite drove the remote by sleeping, so a full run could fail tests that pass alone | **closed 2026-11-27**: `UITestWait` + polled focus in the player and catalogue suites; three consecutive full runs green |
| R6 | Building the app requires the DSH session to run with full file access: under the default `workspace-write` policy SwiftPM cannot write its manifest cache to `~/Library/Caches/org.swift.swiftpm` and the build dies with `Missing package product 'AniLibertyKit'` (observed 2026-11-27; same command green once the session was widened) | run P1–P5 builds with the wider policy, then build and `swift test` as the definition of done |

## 12. What this document does not decide

The detail screen, the catalogue's filters, the player's transport UI, the Top Shelf, and the app icon.
Those keep their own ADRs.
