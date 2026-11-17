# Third-party assets

Everything the app *draws* is either written for this project or fetched from the AniLiberty API at
runtime (posters, covers, episode previews). This file records the few assets that are not ours.

## App icon and Top Shelf image

| Field | Value |
| --- | --- |
| Source | <https://github.com/anilibria/anilibria-app> (`develop`) |
| Files used | `app-tv/src/main/res/mipmap-xxxhdpi/ic_launcher.png` (512 px artwork taken from `app-mobile/src/main/ic_launcher-playstore.png`), same monogram |
| Upstream licence | **GPL-3.0** (`LICENSE` in that repository) |
| What we did | Cropped the white "AL" monogram out of the red plate, then composed tvOS layers (400×240 and 800×480, `Back`/`Front`) and the Top Shelf artwork (wordmark "AniTV" + "неофициальный клиент") in `App/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets/` |
| Trademark | The monogram is AniLiberty's brand identity (the letters «AL» in a ring) |

**The service team has allowed this use in writing (2026-11-17).** Their reply: «Иконка нас устраивает,
если это иконка именно AniLiberty (буквы AL в кольце)… Мы не против, если вы её будете использовать».
Two conditions come with it, and both are already true of this project: the icon must be *their* mark
(it is — the «AL» monogram), and the project must not monetise access to the service's releases. They
also explicitly allowed our own product name as long as it does not imitate an official one, and
approved the `User-Agent` policy of `AGENTS.md` §2.5.

The GPL-3.0 provenance of the *source artwork* is still worth remembering: what we ship is the brand
mark used with permission, not a GPL-licensed derived work, so the MIT licence of this repository is not
extended to cover the monogram.

Decision record: `docs/DECISIONS.md` ADR 0017 (the original, cautious entry) and ADR 0025 (the
permission and the terms).

## Everything else

- Fonts: system only.
- Icons in the UI: SF Symbols.
- Screenshots in `docs/screenshots/`: taken by this project's own UI tests on the tvOS simulator. They
  show posters and video frames that belong to the rights holders of those works; they are here as
  technical evidence of the UI, not as distributed content.
