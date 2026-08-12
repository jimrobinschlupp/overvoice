#!/bin/bash
# Installs Overvoice for Claude Code on this Mac.
#
# Safe to run twice: every step is a copy or an idempotent merge, and your
# existing ~/.claude/settings.json is backed up before it is touched.
#
# What this does NOT do: grant permissions. macOS will prompt for the
# microphone, speech recognition and accessibility the first time each helper
# runs; the script ends by telling you exactly what to click.
set -euo pipefail
cd "$(dirname "$0")"

command -v jq >/dev/null || { echo "jq is required (brew install jq)"; exit 1; }
command -v swiftc >/dev/null || {
  echo "swiftc is required. Install the Xcode Command Line Tools first:"
  echo "  xcode-select --install"
  exit 1
}
command -v claude >/dev/null || echo "note: the 'claude' CLI was not found on PATH; the spoken summaries need it."

echo "==> Building the helper apps (about a minute)"
./swift/build-all.sh

echo "==> Installing the hook and the voice command"
mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/menubar" "$HOME/.local/bin"
cp hooks/speak-summary.sh "$HOME/.claude/hooks/speak-summary.sh"
# the fade/gain player the hook and `voice` look for; without this copy every
# fresh install silently fell back to afplay (no fade on stop)
cp swift/overvoice-play "$HOME/.claude/menubar/overvoice-play"
chmod +x "$HOME/.claude/menubar/overvoice-play"
cp bin/voice "$HOME/.local/bin/voice"
chmod +x "$HOME/.claude/hooks/speak-summary.sh" "$HOME/.local/bin/voice"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "note: add ~/.local/bin to your PATH to use the 'voice' command." ;;
esac

echo "==> Registering the Stop hook in ~/.claude/settings.json"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD="$HOME/.claude/hooks/speak-summary.sh"
[ -f "$SETTINGS" ] || printf '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.backup-overvoice"
jq --arg cmd "$HOOK_CMD" '
  .hooks.Stop = ((.hooks.Stop // [])
    | map(select((.hooks // []) | any(.command == $cmd) | not))
    + [{hooks: [{type: "command", command: $cmd, timeout: 10}]}])
' "$SETTINGS" > "$SETTINGS.tmp"
jq empty "$SETTINGS.tmp"                       # never install a broken settings file
mv "$SETTINGS.tmp" "$SETTINGS"
echo "    (previous settings saved as settings.json.backup-overvoice)"

echo "==> Starting the menu bar app at login"
# Park the icon near the right of the menu bar. Left to itself macOS puts a new
# status item in the leftmost slot, which on any Mac running a menu bar manager
# (Hidden Bar, Bartender, Ice) is inside the hidden zone: the icon then sits at
# a large negative x, invisible, and expanding the manager does not reveal it.
# The value is distance from the right edge, so smaller means further right.
defaults write local.overvoice.menubar \
  "NSStatusItem Preferred Position Overvoice" -float 300

PLIST="$HOME/Library/LaunchAgents/local.overvoice.menubar.plist"
mkdir -p "$HOME/Library/LaunchAgents"
# Wherever the builder actually put it. Hardcoding the home folder here is how
# the agent ended up pointing at a path that did not exist.
APP="${OVERVOICE_APPS_DIR:-/Applications}/Overvoice.app"
[ -d "$APP" ] || APP="$HOME/Applications/Overvoice.app"
sed -e "s|__HOME__|$HOME|g" -e "s|__APP__|$APP|g" \
  launchd/local.overvoice.menubar.plist.template > "$PLIST"
launchctl bootout "gui/$(id -u)/local.overvoice.menubar" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

cat <<'DONE'

Installed. Two permission grants remain; macOS only lets YOU give these:

  1. A briefing will speak after Claude Code's next finished task. When the
     chime plays and you answer, macOS will ask for Microphone and Speech
     Recognition for "Overvoice Listen"; allow both. (Or trigger it now with:
     voice listen)
  2. Spoken replies need Accessibility for "Overvoice Keys": System Settings >
     Privacy & Security > Accessibility > add ~/Applications/Overvoice Keys.app.

Nothing else will be asked: this tool never scripts other applications, and it
never changes your volume. Media is paused with the hardware play/pause key,
which needs no permission and cannot launch anything. If nothing honours that
key, the briefing simply plays over the top rather than touching your audio.

Worth doing now: turn OFF Claude Code's own notifications, in System Settings >
Notifications > Claude. Overvoice posts one per finished turn, so with both on
you get two of everything. Overvoice's names the session, shows the opening
words, and replays the briefing when clicked.

Try it:      voice test
Tune it:     click the round icon in the menu bar
Quiet it:    voice quiet   (silent, still notified)
Mute it:     voice off     (nothing at all)
DONE
