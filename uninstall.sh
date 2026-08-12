#!/bin/bash
# Removes everything install.sh put on this Mac, and tells you which permission
# entries to delete by hand (scripts cannot edit TCC grants).
set -uo pipefail

launchctl bootout "gui/$(id -u)/local.overvoice.menubar" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/local.overvoice.menubar.plist"
pkill -f "Overvoice.app/Contents/MacOS/Overvoice" 2>/dev/null
pkill -f OvervoiceListen 2>/dev/null

SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD="$HOME/.claude/hooks/speak-summary.sh"
if [ -f "$SETTINGS" ] && command -v jq >/dev/null; then
  jq --arg cmd "$HOOK_CMD" '
    .hooks.Stop = ((.hooks.Stop // [])
      | map(select((.hooks // []) | any(.command == $cmd) | not)))
    | if .hooks.Stop == [] then del(.hooks.Stop) else . end
  ' "$SETTINGS" > "$SETTINGS.tmp" && jq empty "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
fi

rm -f "$HOME/.claude/hooks/speak-summary.sh" "$HOME/.local/bin/voice"
rm -f "$HOME/.claude/voice.conf" "$HOME/.claude/voice-off"
rm -rf "$HOME/Applications/Overvoice Listen.app" "$HOME/Applications/Overvoice Keys.app" \
       "$HOME/Applications/Overvoice.app" "/Applications/Overvoice.app"
rm -rf "$HOME/.claude/menubar"

cat <<'MSG'
Removed. Two manual steps, because macOS does not let scripts edit permissions:
  * System Settings > Privacy & Security > Accessibility: remove "Overvoice Keys"
  * System Settings > Privacy & Security > Microphone and Speech Recognition:
    remove "Overvoice Listen"
MSG
