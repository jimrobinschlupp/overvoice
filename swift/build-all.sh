#!/bin/bash
# Builds Overvoice's three helper apps.
#
# WARNING: rebuilding changes each app's ad-hoc signature, so macOS treats it
# as a NEW app and silently drops its permissions. After any rebuild, remove
# and re-add the entries in System Settings > Privacy & Security:
#   Overvoice Listen -> Microphone, Speech Recognition
#   Overvoice Keys   -> Accessibility
# Toggling the checkbox is NOT enough; remove, then add again.
set -euo pipefail
cd "$(dirname "$0")"

# Build the app icon from the logo, once, if the source PNG is newer than the
# result. This is what macOS puts on a notification: with no icon in the bundle
# it falls back to a generic placeholder.
ICON_SRC="overvoice-icon.png"
ICON_ICNS="Overvoice.icns"
build_icon() {
  [ -f "$ICON_SRC" ] || return 0
  [ -f "$ICON_ICNS" ] && [ "$ICON_ICNS" -nt "$ICON_SRC" ] && return 0
  local set_dir="Overvoice.iconset"
  rm -rf "$set_dir"; mkdir -p "$set_dir"
  # iconutil requires this exact set of names and sizes, and fails outright if
  # any one of them is missing.
  while read -r px name; do
    [ -z "$px" ] && continue
    sips -z "$px" "$px" "$ICON_SRC" --out "$set_dir/$name.png" >/dev/null 2>&1
  done <<'SIZES'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
SIZES
  iconutil -c icns "$set_dir" -o "$ICON_ICNS" && echo "built $ICON_ICNS"
  rm -rf "$set_dir"
}
build_icon

# A plain binary, not an app bundle: it only plays audio, so it needs no
# permission and staying outside a bundle keeps it clear of TCC entirely.
# It exists because afplay cannot fade, so a stopped briefing was cut off
# mid-syllable instead of quieting down.
swiftc -O -o overvoice-play OvervoicePlay.swift && echo "built overvoice-play"

# The menu bar app is the only one anyone opens by hand, so it belongs in the
# Applications folder people actually look in. The two helpers stay in the user
# folder: they are never launched directly, and their microphone, speech and
# accessibility grants are tied to where they sit, so moving them would silently
# revoke permissions the user already gave.
APPS_MAIN="${OVERVOICE_APPS_DIR:-/Applications}"
[ -w "$APPS_MAIN" ] || APPS_MAIN="$HOME/Applications"   # no admin rights: fall back
APPS_HELPER="$HOME/Applications"

build_app() {   # $1 display name  $2 bundle id  $3 source  $4 extra plist keys  $5 icon?
  local dest="$APPS_HELPER"
  [ "$1" = "Overvoice" ] && dest="$APPS_MAIN"
  local app="$dest/$1.app"
  local exe; exe=$(basename "$3" .swift)
  local tmp; tmp=$(mktemp)
  local icon_key=""
  if [ "${5:-}" = "icon" ] && [ -f "$ICON_ICNS" ]; then
    icon_key="  <key>CFBundleIconFile</key><string>Overvoice</string>"
  fi
  cat > "$tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$1</string>
  <key>CFBundleIdentifier</key><string>$2</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$exe</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
$icon_key
$4
</dict>
</plist>
PLIST
  mkdir -p "$app/Contents/MacOS"
  if [ -n "$icon_key" ]; then
    mkdir -p "$app/Contents/Resources"
    cp "$ICON_ICNS" "$app/Contents/Resources/Overvoice.icns"
  fi
  cp "$tmp" "$app/Contents/Info.plist"
  # The plist must ALSO be embedded in the binary: on direct exec macOS reads
  # the Mach-O section, not the bundle copy.
  swiftc -O -o "$app/Contents/MacOS/$exe" "$3" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$tmp"
  codesign --force --sign - --identifier "$2" "$app/Contents/MacOS/$exe"
  rm -f "$tmp"
  echo "built $app"
}

MIC_KEYS='  <key>NSMicrophoneUsageDescription</key>
  <string>Overvoice listens for a spoken yes or no after Claude finishes a task.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Overvoice recognises short spoken answers on-device; nothing leaves this Mac.</string>'

build_app "Overvoice Listen" "local.overvoice.listen" OvervoiceListen.swift "$MIC_KEYS" icon
build_app "Overvoice Keys"   "local.overvoice.keys"   OvervoiceKeys.swift   "" icon
build_app "Overvoice"        "local.overvoice.menubar" Overvoice.swift      "" icon
