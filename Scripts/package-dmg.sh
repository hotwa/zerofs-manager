#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-"$PROJECT_ROOT/dist"}"
APP_PATH="${APP_PATH:-"$DIST_DIR/ZeroFS Manager.app"}"
DMG_PATH="${DMG_PATH:-"$DIST_DIR/ZeroFS-Manager-local-not-notarized.dmg"}"
DMG_BACKGROUND="$PROJECT_ROOT/Resources/DMG/background.png"
VOLUME_NAME="ZeroFS Manager Local"
STAGING="$DIST_DIR/dmg-staging"
RW_DMG="$DIST_DIR/ZeroFS-Manager-local-layout.dmg"
MOUNT_POINT=""

fail() {
  echo "DMG packaging failed: $*" >&2
  exit 1
}

detach_mount() {
  local mount_point="$1"
  for _ in 1 2 3 4 5; do
    if hdiutil detach "$mount_point" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  hdiutil detach -force "$mount_point" >/dev/null 2>&1 || true
}

cleanup() {
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    detach_mount "$MOUNT_POINT"
  fi
  rm -f "$RW_DMG"
}

trap cleanup EXIT

if [[ ! -d "$APP_PATH" || "${BUILD_APP:-1}" == "1" ]]; then
  "$PROJECT_ROOT/Scripts/build-app.sh"
fi

if [[ ! -f "$DMG_BACKGROUND" ]]; then
  python3 "$PROJECT_ROOT/Scripts/generate-visual-assets.py"
fi

"$PROJECT_ROOT/Scripts/verify-bundle.sh" "$APP_PATH"
[[ -f "$DMG_BACKGROUND" ]] || fail "missing DMG background: $DMG_BACKGROUND"

rm -rf "$STAGING"
mkdir -p "$STAGING/.background"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "$DMG_BACKGROUND" "$STAGING/.background/background.png"
cp "$PROJECT_ROOT/LICENSE" "$STAGING/LICENSE.txt"
cat > "$STAGING/LOCAL_NOT_NOTARIZED.txt" <<'MARKER'
This DMG is a local development artifact.
It is not notarized and is not intended for public distribution.
It contains the GUI only. ZeroFS is an external dependency that users install separately.
For release distribution, use Scripts/sign-notarize-staple.sh with Developer ID credentials.
ZeroFS Manager is licensed under Apache License 2.0; see LICENSE.txt.
MARKER

rm -f "$DMG_PATH" "$RW_DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -ov \
  -format UDRW \
  "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
MOUNT_POINT="$(printf "%s\n" "$ATTACH_OUTPUT" | awk -v volume="/Volumes/$VOLUME_NAME" 'index($0, volume) { print substr($0, index($0, volume)) }' | tail -n 1)"
[[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]] || fail "could not locate mounted DMG volume"

if ! osascript <<OSA
set backgroundPicture to POSIX file "$MOUNT_POINT/.background/background.png" as alias
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 840, 560}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set text size of theViewOptions to 12
    set background picture of theViewOptions to backgroundPicture
    set position of item "ZeroFS Manager.app" of container window to {190, 220}
    set position of item "Applications" of container window to {532, 220}
    set position of item "LOCAL_NOT_NOTARIZED.txt" of container window to {360, 350}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
then
  echo "Warning: Finder layout customization failed; continuing with a valid DMG." >&2
fi

chflags hidden "$MOUNT_POINT/.background" || true
sync
detach_mount "$MOUNT_POINT"
MOUNT_POINT=""

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

echo "Created local, not-notarized DMG: $DMG_PATH"
