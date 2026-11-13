# Third-party assets

Everything the app *draws* is either written for this project or fetched from the AniLiberty API at
runtime (posters, covers, episode previews). This file records the few assets that are not ours.

## App icon and Top Shelf image

| Field | Value |
| --- | --- |
| Source | <https://github.com/anilibria/anilibria-app> (`develop`) |
| Files used | `app-tv/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (512 px artwork taken from `app-mobile/src/main/ic_launcher-playstore.png`), same monogram |
| Upstream licence | **GPL-3.0** (`LICENSE` in that repository) |
| What we did | Cropped the white "AL" monogram out of the red plate, then composed tvOS layers (400×240 and 800×480, `Back`/`Front`) and the Top Shelf image in `App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets/` |
| Trademark | The monogram is AniLibria's brand identity |

**This is accepted knowingly, and it is the one place where the project does not follow
`AGENTS.md` §1 ("must not use the AniLibria/Anilibria/Libria trademarks as product identity").**
AniTV is an unofficial client; shipping a build to TestFlight or the App Store with the upstream logo
would misrepresent it as the official app, and the GPL-3.0 provenance of the source artwork is
unresolved for a repository licensed under MIT. Replace the icon with an original mark before the
project is published anywhere, or state the reuse explicitly in the README.

Decision record: `docs/DECISIONS.md` ADR 0017.

## Everything else

- Fonts: system only.
- Icons in the UI: SF Symbols.
- Screenshots in `docs/screenshots/`: taken by this project's own UI tests on the tvOS simulator. They
  show posters and video frames that belong to the rights holders of those works; they are here as
  technical evidence of the UI, not as distributed content.
