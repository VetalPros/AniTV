#!/usr/bin/env bash
#
# Builds a signed tvOS archive, exports it for App Store Connect and uploads it to TestFlight.
#
#   1. put the team in Config/Local.xcconfig (gitignored):  DEVELOPMENT_TEAM = ABCDE12345
#   2. sign in with that team in Xcode → Settings → Accounts
#   3. export credentials in the shell (never in the repository):
#        APPLE_API_KEY_ID=XXXXXXXXXX
#        APPLE_API_ISSUER=00000000-0000-0000-0000-000000000000
#        APPLE_P8_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8     # optional, default location otherwise
#      or, for the personal route:
#        APPLE_ID=you@example.com  APPLE_APP_PASSWORD=abcd-efgh-ijkl-mnop
#   4. ./scripts/release-testflight.sh
#
# Useful knobs:
#   BUILD_NUMBER=202611271930   build number to use (default: UTC yyyymmddHHMM)
#   UPLOAD=0                    do everything except the upload
#   VALIDATE=0                  skip the pre-upload validation
#
# See docs/RELEASE.md for what has to exist on the App Store Connect side first.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
ARCHIVE="$ROOT/.build/AniTV.xcarchive"
EXPORT_DIR="$ROOT/.build/export"

fail() {
	echo "error: $*" >&2
	exit 1
}

[[ -f Config/Local.xcconfig ]] ||
	fail "Config/Local.xcconfig is missing; it must set DEVELOPMENT_TEAM (see docs/RELEASE.md)"
command -v xcodegen >/dev/null || fail "xcodegen is not installed (brew install xcodegen)"

MARKETING_VERSION="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)"
[[ -n "$MARKETING_VERSION" ]] || fail "could not read MARKETING_VERSION from project.yml"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"

echo "==> AniTV ${MARKETING_VERSION} (${BUILD_NUMBER})"

echo "==> generating the project"
xcodegen generate

echo "==> archiving"
rm -rf "$ARCHIVE"
xcodebuild archive \
	-project AniTV.xcodeproj \
	-scheme AniTV \
	-configuration Release \
	-destination 'generic/platform=tvOS' \
	-archivePath "$ARCHIVE" \
	-allowProvisioningUpdates \
	BUILD_NUMBER="$BUILD_NUMBER" \
	| tail -5

echo "==> exporting for App Store Connect"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
	-archivePath "$ARCHIVE" \
	-exportOptionsPlist Config/ExportOptions.plist \
	-exportPath "$EXPORT_DIR" \
	-allowProvisioningUpdates \
	| tail -5

IPA="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -1)"
[[ -n "$IPA" ]] || fail "the export produced no .ipa in $EXPORT_DIR"
echo "==> exported $IPA"

# Credentials come from the environment; nothing here is ever written to the repository.
if [[ -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" ]]; then
	AUTH=(--apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER")
	[[ -n "${APPLE_P8_PATH:-}" ]] && AUTH+=(--p8-file-path "$APPLE_P8_PATH")
	echo "==> authenticating with an App Store Connect API key"
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
	AUTH=(-u "$APPLE_ID" -p "$APPLE_APP_PASSWORD")
	echo "==> authenticating as $APPLE_ID with an app-specific password"
else
	fail "no credentials: set APPLE_API_KEY_ID + APPLE_API_ISSUER (preferred) or APPLE_ID + APPLE_APP_PASSWORD"
fi

if [[ "${VALIDATE:-1}" != "0" ]]; then
	echo "==> validating the package"
	xcrun altool --validate-app -f "$IPA" -t appletvos "${AUTH[@]}"
fi

if [[ "${UPLOAD:-1}" == "0" ]]; then
	echo "==> UPLOAD=0: leaving the package in $EXPORT_DIR"
	exit 0
fi

echo "==> uploading to TestFlight"
xcrun altool --upload-app -f "$IPA" -t appletvos "${AUTH[@]}"

cat <<'DONE'

Uploaded. Next:
  1. wait for the build to finish processing in App Store Connect → TestFlight;
  2. answer export compliance only if the build says it is missing (ITSAppUsesNonExemptEncryption is set);
  3. add yourself under Internal Testing and install through the TestFlight app on the Apple TV.

Builds expire after 90 days — re-run this script when TestFlight says "build expired".
DONE
