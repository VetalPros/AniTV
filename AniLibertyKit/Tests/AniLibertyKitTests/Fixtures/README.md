# Test fixtures — provenance

Every file here is read through `Bundle.module`, so the tests never touch the network.
This note records where each payload comes from, because «looks like the API» is not the
same thing as «recorded from the API».

## Recorded from the live service

| File | Request | Recorded |
| --- | --- | --- |
| `releases_latest.json` | `GET /api/v1/anime/releases/latest` | 2026-11-10 |
| `release_detail.json` | `GET /api/v1/anime/releases/10308` | 2026-11-10 |
| `catalog_page.json` | `POST /api/v1/anime/catalog/releases` `{"page":1,"limit":3}` | 2026-11-16 |
| `catalog_search.json` | `POST …/catalog/releases` `{"page":1,"limit":2,"f":{"search":"маска"}}` | 2026-11-16 |
| `reference_*.json` | `GET …/catalog/references/{genres,types,seasons,sorting,years}` | 2026-11-16 |
| `otp_get.json` | `POST /api/v1/accounts/otp/get` (anonymous) | 2026-11-16 |
| `otp_login_pending.json` | `POST /api/v1/accounts/otp/login` for a code nobody had accepted yet — the service answers **HTTP 500** `{"message":"Server Error"}`; the body is recorded as-is | 2026-11-16 |

`otp_get.json` carries a real one-time code. It is expired, tied to a throwaway device
identifier, and was never accepted, so it is not a credential — it is kept verbatim
because the shape (`code` as a *string*, `remaining_time` as a *float*) is exactly what
the decoder has to survive.

## Synthesized — **not** recorded, because no account exists

| File | Source of the shape |
| --- | --- |
| `user_profile.json` | OpenAPI `models.users.v1.user`; every value is fictional. The `torrents.passkey` value is a placeholder — the model deliberately never exposes it |
| `favorites_releases.json` | OpenAPI `responses.v1.accounts.users.me.favorites.releases`; the release objects are copied verbatim from the recorded catalogue payload, the envelope and pagination are hand-written |

Both files start with a `_provenance` key that says the same thing inside the JSON
itself. The Kit's decoders ignore unknown keys, so the marker costs nothing at runtime.

**What this means:** no authenticated call (`profile`, `favorites`, password login) has
ever been executed against the live service. Their decoders are tested against schemas,
not against reality; field names could still differ in practice.
