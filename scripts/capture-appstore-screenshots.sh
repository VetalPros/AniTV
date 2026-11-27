#!/usr/bin/env bash
#
# Refreshes the App Store screenshots for tvOS: runs AppStoreShotsUITests, exports the attachments and
# writes 1920×1080 JPEGs into docs/appstore/screenshots/.
#
#   ./scripts/capture-appstore-screenshots.sh
#
# Needs the simulator with a signed-in account for the favourites rail to appear on the first shot; without
# one the rail is simply absent.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
SIMULATOR="${SIMULATOR:-1CEE9693-F8EB-45A4-8223-1679EE0EFC5A}"
RESULT="$ROOT/.build/appstore.xcresult"
SHOTS="$ROOT/.build/appstore-shots"
OUT="$ROOT/docs/appstore/screenshots"

rm -rf "$RESULT" "$SHOTS"
mkdir -p "$OUT"

echo "==> running the capture test"
xcodebuild test \
	-project AniTV.xcodeproj \
	-scheme AniTV \
	-destination "platform=tvOS Simulator,id=$SIMULATOR" \
	-derivedDataPath .build/DerivedData \
	-only-testing:AniTVUITests/AppStoreShotsUITests \
	-resultBundlePath "$RESULT" \
	2>&1 | grep -E "Test Case '.*' (passed|failed)|TEST (SUCCEEDED|FAILED)|error:" || true

echo "==> exporting attachments"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$SHOTS" >/dev/null

python3 - "$SHOTS" "$OUT" <<'PY'
import json, os, shutil, subprocess, sys

shots, out = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(shots, "manifest.json"), encoding="utf-8"))
wanted = {"01-home", "02-search", "03-catalog", "04-detail", "05-settings"}
written = []
for entry in manifest[0]["attachments"]:
    name = entry["suggestedHumanReadableName"].split("_")[0]
    if name not in wanted:
        continue
    source = os.path.join(shots, entry["exportedFileName"])
    target = os.path.join(out, f"{name}.jpg")
    # tvOS wants exactly 1920×1080; the simulator captures at 2x. JPEG keeps the repository small and
    # App Store Connect accepts it alongside PNG.
    subprocess.run(["sips", "-z", "1080", "1920", "-s", "format", "jpeg", "-s", "formatOptions", "90",
                    source, "--out", target],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    written.append((name, target))

for name, path in sorted(written):
    size = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
                          capture_output=True, text=True).stdout
    dims = " ".join(part.split(":")[1].strip() for part in size.strip().splitlines()[1:])
    print(f"  {name}: {dims} → {os.path.relpath(path, os.getcwd())}")

missing = wanted - {name for name, _ in written}
if missing:
    raise SystemExit(f"missing screenshots: {sorted(missing)}")
PY

echo "==> done: $OUT"
