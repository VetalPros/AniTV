# AniLiberty API — verified notes

Facts below were verified by hand against the live service (2026-11-10). Anything not marked
`verified` is an assumption and must be re-checked before being relied on.

## Hosts

- API base: `https://aniliberty.top/api/v1` (the OpenAPI document declares `servers: [{url: "/api/v1"}]`).
  Also reachable as `https://anilibria.top/api/v1`.
- The legacy `api.anilibria.tv` host is dead (**HTTP 410 Gone**) — do not use it.
- Health probe: `GET /app/status` → `{ "is_alive": true, "available_api_endpoints": ["https://aniliberty.top"], "request": { …, "country": "FI" } }`.
  Verified. Useful as the first network call on launch and for a "service status" banner.
- HTTP client: `User-Agent: AniTV/0.1 (test)` is accepted (200). No `RateLimit-*` / `X-RateLimit-*`
  response headers were observed — still, cache and throttle by convention.

## Catalog (no auth required)

| Endpoint | Notes |
| --- | --- |
| `GET /anime/releases/latest` | Returns a **bare JSON array** (14 items at the time of checking), not an object. |
| `GET/POST /anime/catalog/releases` | Main catalog with filters/paging. |
| `GET /anime/releases/list` | Paginated list. |
| `GET /anime/releases/random` | Random release. |
| `GET /anime/releases/recommended` | Recommendations. |
| `GET /anime/releases/{idOrAlias}` | Release detail — accepts numeric id **or** alias. |
| `GET /anime/releases/{id}/members` | Voice actors / staff. |
| `GET /anime/releases/{id}/episodes/timecodes` | Skip-timecodes for the whole release. |
| `GET /anime/releases/episodes/{releaseEpisodeId}` | Single episode; `/timecode` for one episode. |
| `GET /anime/releases/{releaseId}/rating`, `POST`, `DELETE` | Rating needs auth for POST/DELETE. |
| `GET /anime/catalog/references/{age-ratings,genres,production-statuses,publish-statuses,seasons,sorting,types,years}` | Reference data for filters. |
| `GET /anime/genres`, `/anime/genres/random`, `/anime/genres/{genreId}`, `/anime/genres/{genreId}/releases` | Genres. |
| `GET /anime/schedule/now`, `GET /anime/schedule/week` | Airing schedule. |
| `GET /anime/torrents`, `/anime/torrents/release/{releaseId}`, `/anime/torrents/rss`, `/anime/torrents/{hashOrId}` (+ `/file`) | Torrents — out of scope for a streaming tvOS client. |
| `GET /anime/franchises[…]` | Franchise grouping. |
| `GET /app/search/releases` | Search. |
| `GET /media/{manifest.xml,promotions,vasts,videos}` | Promos/ads — **do not render ads** in our client. |
| `GET /teams/` | Team info. |

The full OpenAPI document (71 paths) is at
`https://anilibria.top/storage/api/docs/v1?aniliberty-api-v1-docs.json`; browsable docs at
`https://anilibria.top/api/docs/v1`.

## Release DTO (verified keys)

`id, type, year, name{main, english, alternative}, alias, season, shikimori, mal, rating,
poster{src, preview, thumbnail, optimized{...webp}}, fresh_at, created_at, updated_at, is_ongoing,
age_rating, publish_day, description, notification, episodes_total, external_player,
is_in_production, is_blocked_by_geo, is_blocked_by_copyrights, is_comments_closed, comments_count,
added_in_*, average_duration_of_episode, genres, background_covers, members, sponsors, episodes,
torrents`

Geo/copyright flags matter: a blocked release can still be listed, so the UI must handle a
`is_blocked_by_geo: true` release gracefully (badge + explanation, no player).

## Episode DTO (verified keys)

`id` (UUID), `name`, `ordinal`, `opening{start, stop}`, `ending{start, stop}`, `preview{…}`,
`hls_480`, `hls_720`, `hls_1080`, `duration`, `rutube_id`, `youtube_id`, `updated_at`,
`sort_order`, `release_id`

`hls_*` are absolute `.m3u8` URLs. Prefer 1080 → 720 → 480 in that order, degrade on failure.

## HLS playback (verified)

- Example URL shape:
  `https://cache.libria.fun/videos/media/ts/{releaseId}/{episode}/{480|720|1080}/{hash}.m3u8?countryIso=FI&isAuthorized=0&isWithVideoAds=1&isWithVideoAdsAlways=1`
- The playlist is `#EXT-X-VERSION:6`, `#EXT-X-PLAYLIST-TYPE:VOD`, `TARGETDURATION:12`, with
  **absolute** `.ts` segment URLs.
- **No `#EXT-X-KEY`** → plain MPEG-TS, no DRM, no AES. `AVPlayer` plays it as-is.
- Segment responses are `video/mp2t` and may arrive via HTTP redirects; `AVPlayer` follows them.
- The query parameters (`countryIso`, `isAuthorized`, `isWithVideoAds`) are cosmetic for playback:
  they are not needed for the segments themselves. Do not attempt to strip or bypass geo/ads
  policy — the client plays exactly what the API returns.

## Accounts (Bearer `sessionToken`)

- `POST /accounts/users/auth/login`, `POST /accounts/users/auth/logout`.
- OTP device flow (the right choice for tvOS — no `WKWebView`):
  1. `POST /accounts/otp/get` with `{ "device_id": "<uuid>" }` → returns a code + OTP metadata.
  2. User enters the code in the app: `POST /accounts/otp/accept` with `{ "code": <integer> }`.
  3. `POST /accounts/otp/login` → returns the `sessionToken`.
  The code is displayed on the TV and confirmed by the user elsewhere; there is no browser step.
- Password recovery: `/accounts/users/auth/password/forget`, `.../password/reset`.
- Social login exists (`/accounts/users/auth/social/authenticate`, `/auth/social/{provider}/login`)
  but is impractical on tvOS without a web view — keep OTP as the primary path.
- User data: `/accounts/users/me/{profile, collections, favorites, views/history, views/timecodes}`.
- **Timecodes** (skip intro/outro sync): `GET/POST/DELETE /accounts/users/me/views/timecodes`.
  - `POST` body: an **array** of `{ time: number, is_watched: bool, release_episode_id: uuid }`,
    `maxItems: 1000`.
  - `DELETE` body: an array of `{ release_episode_id }`.
  - This is the canonical way to persist watch progress across devices — no CloudKit needed.

## Client design implications

- `sessionToken` belongs in the **Keychain** (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlock`),
  never in `UserDefaults`, never in logs, never in the repository.
- Decode into `Sendable` value types; dates as `Date` via ISO-8601 with fractional seconds tolerance.
- Wrap the API in a typed `AniLibertyClient` actor: `URLSession` + `URLCache` + retry/backoff,
  one place for `User-Agent`, one place for error mapping.
- Cache reference data (genres, years, types) for the session; posters through a disk+memory image
  cache actor.
