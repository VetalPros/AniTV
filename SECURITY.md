# Security policy

AniTV is an unofficial, open-source client for the public AniLiberty HTTP API. It runs entirely on
the user's device, has no backend of its own, and stores no user data on any server operated by this
project.

## Supported versions

The project is pre-1.0 and distributed through TestFlight only. Security fixes land on `main` and in
the next TestFlight build; there are no maintained release branches yet. Reports against any build
are welcome.

| Version | Supported |
| --- | --- |
| `main` / latest TestFlight build | ✅ |
| Older builds | ❌ — please retest against the latest build |

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting on this repository:
*Security* → *Advisories* → *Report a vulnerability*. That channel is private between you and the
maintainers and is the fastest route.

If private reporting is unavailable for any reason, open a regular issue that contains **only** a
request for a private contact channel — no vulnerability details, no proof-of-concept code, no URLs
that trigger the issue.

Please include, when possible:

- the affected build (TestFlight build number or commit SHA) and tvOS version,
- a description of the impact and who can exploit it,
- reproduction steps, logs with secrets and tokens removed,
- any suggested fix.

We aim to acknowledge a report within 7 days and to ship a fix or publish an advisory within 90
days of triage. This is a volunteer project, so timelines are best effort, not a contractual SLA.

## Secrets and credentials

- **Never commit secrets.** No API keys, `sessionToken` values, credentials, `.p12`, `.mobileprovision`,
  `.env` files or signing material belong in this repository. The repository is public and CI runs on
  GitHub-hosted runners with no secrets configured.
- **Session tokens live in the Keychain.** The AniLiberty session token is stored in the iOS/tvOS
  Keychain (device-only, not synchronised) and is read only by the networking layer in
  `AniLibertyKit`. Tokens are never written to `UserDefaults`, files, logs, crash reports,
  `externalMetadata` or analytics.
- **The networking layer logs no credentials.** Logs go through `Logger` and must not contain
  tokens, cookies, full URLs with embedded credentials or response bodies that carry them.
- **No secrets in the app bundle.** Configuration is compile-time only; nothing sensitive is
  injected at build time or fetched from this repository's CI.

If you find a leaked secret in the repository or in a build artefact, report it privately using the
channel above. Treat it as compromised — deleting it in a later commit does not remove it from git
history or from any clone.

## In scope

- Client-side vulnerabilities in this repository: unsafe handling of API/cached data, credential
  leaks (token written to disk, logs, crash reports), insecure deep-link or URL handling,
  memory-safety issues in hand-written parsing, dependency-free networking code with TLS/certificate
  validation mistakes, denial-of-service via crafted payloads (unbounded memory, infinite loops).
- Privacy issues: user data sent somewhere it should not go, playback history or tokens exposed
  beyond the device.

## Out of scope

- **The AniLiberty service itself.** This project is an unofficial client: server-side issues, account
  problems, content availability, geo-restrictions and billing are handled by the service, not here.
  Report them to AniLiberty directly.
- **DRM, paywall, geo-blocking or access-control bypass.** The client only uses the public API and
  deliberately contains no circumvention code. Reports or contributions that require bypassing
  access controls are rejected — see `AGENTS.md` §2.
- Issues that require a jailbroken device, a modified app binary, or a MITM proxy with an installed
  trusted root certificate, unless they demonstrate a real weakness in the app's own TLS handling.
- Missing security headers, rate limiting or other subjects on hosts this project does not operate.
- Findings that only affect unsupported tvOS versions, or that need physical access to an unlocked
  device combined with an already-compromised OS.
- Automated scanner output with no demonstrated impact on this app.

## Scope of the project's promises

AniTV is a personal, non-commercial project: it provides no uptime guarantee, no data-processing
agreement and no paid support. It requests only the public API, with an identifying `User-Agent`,
conditional requests and caching, and it does not attempt to hide from or overload the upstream
service.
