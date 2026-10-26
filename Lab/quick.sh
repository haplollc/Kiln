#!/bin/zsh
# Fast check of a few Kiln Lab scenarios while fixing a bug.
#   Lab/quick.sh AppScenarios/testTipCalculatorKiln [more tests…]
# Prints the labels on screen at each step and leaves the screenshots in
# $KILN_QUICK_OUT (default: a temp folder, printed at the end).
set -e
LAB=${0:A:h}
SIM=$(cat "$LAB/.sim-udid" 2>/dev/null || xcrun simctl list devices available | grep -m1 -E "iPhone" | grep -oE "[0-9A-F-]{36}")
OUT=${KILN_QUICK_OUT:-$(mktemp -d -t kilnquick)}
DERIVED="$LAB/.build-quick"
cd "$LAB"
python3 gen_native.py >/dev/null
xcodegen generate --quiet
xcrun simctl boot "$SIM" 2>/dev/null || true
xcodebuild build-for-testing -project KilnLab.xcodeproj -scheme KilnLab -destination "id=$SIM" \
  -derivedDataPath "$DERIVED" > "$OUT/build.log" 2>&1 || { grep -E "error:" "$OUT/build.log" | head -20; exit 1; }
ONLY=()
for t in "$@"; do ONLY+=("-only-testing:KilnLabUITests/$t"); done
rm -rf "$OUT/run.xcresult"
xcodebuild test-without-building -project KilnLab.xcodeproj -scheme KilnLab -destination "id=$SIM" \
  -derivedDataPath "$DERIVED" "${ONLY[@]}" -resultBundlePath "$OUT/run.xcresult" > "$OUT/test.log" 2>&1 || true
grep -E "Test Case .*(passed|failed)" "$OUT/test.log" | sed 's/^.*Test Case/Test Case/' | cut -c1-120
mkdir -p "$OUT/att"
xcrun xcresulttool export attachments --path "$OUT/run.xcresult" --output-path "$OUT/att" >/dev/null
python3 - "$OUT/att" <<'PY'
import json, os, re, sys
d = sys.argv[1]
for test in json.load(open(os.path.join(d, "manifest.json"))):
    for a in sorted(test.get("attachments", []), key=lambda a: a["suggestedHumanReadableName"]):
        name = re.sub(r"_\d+_[0-9A-F-]{36}\.\w+$", "", a["suggestedHumanReadableName"])
        p = os.path.join(d, a["exportedFileName"])
        if name.endswith("|texts") or name.endswith("|notes"):
            print("--", name)
            print("   " + " · ".join(l.strip() for l in open(p).read().splitlines() if l.strip()))
        else:
            safe = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_") + ".png"
            os.replace(p, os.path.join(d, safe))
PY
echo "$OUT"
