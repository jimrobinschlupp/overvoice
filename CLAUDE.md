# Agent instructions: installing Overvoice for Claude Code

You are reading this because a user opened this repository in Claude Code (or
a similar agent) and asked you to set it up. The user may be completely
non-technical: do the work, verify each step yourself, and only involve them
for the things macOS reserves for humans: clicking permission prompts.

## The short version

1. Check prerequisites; help the user fix what's missing.
2. Run `./install.sh` and read its output.
3. Verify the install (checklist below).
4. Walk the user through the two permission grants, one at a time.
5. Run a live end-to-end test with the user.

Do not hand the user terminal commands to run if you can run them yourself.
Never ask the user for passwords; nothing here needs one.

## 1 · Prerequisites

Run these checks and report what you find before installing:

- `xcode-select -p` succeeds → Command Line Tools present. If not:
  `xcode-select --install` opens a GUI installer the user must click through.
- `command -v jq`: if missing and Homebrew exists, `brew install jq`.
- `command -v claude`: the Claude Code CLI must be on PATH (it is, if you
  are running inside Claude Code).
- macOS 12 or newer: `sw_vers -productVersion`.

## 2 · Install

Run `./install.sh` from the repo root. It is idempotent and backs up
`~/.claude/settings.json` before merging the hook. If the Swift build fails,
read the compiler error; the usual cause is missing Command Line Tools.

## 3 · Verify before involving the user

- `jq '.hooks.Stop' ~/.claude/settings.json` shows an entry whose command is
  `$HOME/.claude/hooks/speak-summary.sh`.
- The three apps exist under `~/Applications/`: `Overvoice Listen.app`,
  `Overvoice Keys.app`, `Overvoice.app`.
- `launchctl print gui/$(id -u)/local.overvoice.menubar` reports `state = running`
  → the menu bar app is up. Tell the user to look for a round asterisk icon;
  if they run a menu-bar manager (Hidden Bar, Bartender, Ice), the icon may
  be parked off-screen; have them expand it and ⌘-drag the icon out.
- `bash -n ~/.claude/hooks/speak-summary.sh` parses.

## 4 · Permissions: the user must click these (there are two)

Explain each before triggering it, one at a time.

**Microphone + Speech Recognition** (for Overvoice Listen): run `voice listen`,
which starts a listening window; macOS shows two prompts. The user clicks
Allow on both, then says "yes" out loud. The command prints a verdict and a
`peakInputLevel`: near 0.15 means the mic heard them; near 0.005 means it
did not (wrong input device, or the prompt was denied).

**Accessibility** (for Overvoice Keys): System Settings → Privacy & Security →
Accessibility → **+** → add `~/Applications/Overvoice Keys.app` (the user's home
Applications folder, not /Applications). Verify afterwards by running:
`open -n -g -a "$HOME/Applications/Overvoice Keys.app" --args check /tmp/k.txt`
then reading `/tmp/k.txt`; it must say `trusted`.

There is no third prompt. This tool deliberately never scripts other
applications (media is paused with the hardware play/pause key), so no
Automation permissions are requested and nothing can be launched by accident.

## 5 · End-to-end test

Ask the user to put earphones on. Finish any small task so your own Stop hook
fires, or run `voice test` for the audio path alone. The full loop: chime →
user says "yes" → spoken summary → chime → user says "go ahead" → the words
appear in the Claude Code input box and send. If the user's Claude Code runs
in a terminal app rather than the Claude desktop app, set the frontmost-app
match first: `echo 'FRONT_MATCH="Terminal"' >> ~/.claude/voice.conf`
(or iTerm2, or Code).

## 6 · Offer the briefing rule (ask, do not just do it)

The default detail level is `briefing`: it speaks the closing recap a message
wrote for itself under a `## Briefing` heading, and reads the whole message
instead on any turn that has none. So on a fresh install it behaves exactly
like `full` until the user's own agent starts writing one.

Ask whether they want it, and say plainly that it changes how you write to
them, not just what they hear. If yes, append to their `~/.claude/CLAUDE.md`:

```markdown
End every substantial response with a short briefing: a `## Briefing` heading,
then two or three sentences saying what was done, what it means, and what I
need to decide next. Nothing after it. Skip it when the whole response is only
a few lines.
```

Two things to tell them. Anything they must answer has to appear in the
briefing, because on a long turn it is all they will hear. And the closing
question should be the briefing's last sentence, since nothing follows it.

If they decline, run `voice detail full` so the setting matches reality.

## Hard-won macOS facts: do not relearn these by debugging

These cost hours the first time. They are already handled by the code and the
build scripts; this list exists so you do not "fix" them away or trip over
them when modifying things.

- **AppleScript launches apps just by naming them.** To compile a term like
  `player state`, AppleScript loads the target app's scripting dictionary,
  and loading it LAUNCHES the app, before any `if application ... is running`
  guard is evaluated. Asking a closed VLC for `player state` (which VLC does
  not even support) opened VLC and then failed with a syntax error. If you
  ever reintroduce app scripting, gate it behind `pgrep -x` first, and wrap
  every AppleEvent in `with timeout of N seconds`; a pending permission
  dialog will otherwise block the script for minutes.
- **TCC blames the parent.** A permission-needing helper spawned directly
  from a shell is killed with "no usage description" no matter what its
  bundle plist says. Always launch helpers with `open -n -g -a`, and return
  results through a temp file, not stdout.
- **The plist must be embedded in the binary** (`-sectcreate __TEXT
  __info_plist`) as well as in the bundle.
- **Rebuilding a helper invalidates its permission grant.** The ad-hoc
  signature changes; macOS silently treats it as a new app. After a rebuild
  the user must REMOVE and RE-ADD the entry in System Settings; toggling the
  checkbox looks right and does nothing.
- **A menu bar manager will swallow the icon, and expanding it does not help.**
  A status item with no `autosaveName` cannot remember a position, so macOS
  puts it in the leftmost slot on every launch. On a Mac running Hidden Bar,
  Bartender or Ice that slot is inside the hidden zone: measured x was -4026
  with Hidden Bar running and 1022 with it quit, same binary, same launch.
  The app sets `item.autosaveName = "Overvoice"` and the installer pins
  `NSStatusItem Preferred Position Overvoice` to 300, which is distance from
  the right edge (100 landed at x=1507, 300 at x=1362, 700 at x=-3712 back
  inside the hidden zone). If a user reports an invisible icon, read the
  measured frame from `~/.claude/menubar/debug.log` before theorising.
- **A bash trap does not exit; it resumes.** `trap cleanup EXIT TERM INT`
  runs `cleanup` on SIGTERM and then carries on from where the script was
  interrupted. This was the cause of the microphone being held open forever:
  killing a flow ran its teardown, released the mic, and then let the flow
  continue and open a NEW listener, while its `RESTORED=1` guard meant the
  teardown could never fire a second time. Signal traps must exit explicitly:
  `trap cleanup EXIT` plus `trap 'cleanup; exit 143' TERM`.
- **Killing a listener with SIGTERM leaves the microphone lit.** The default
  handler tears the process down without stopping `AVAudioEngine`, so
  coreaudiod keeps the input aggregate device alive and the orange indicator
  stays on with no process to blame. Route the signal through a
  `DispatchSource.makeSignalSource` handler that stops the engine and removes
  the tap. `signal(SIGTERM, SIG_IGN)` first, or the dispatch source never
  sees it.
- **Never block the main thread waiting for a permission callback.** The
  authorisation dialog is drawn on the main run loop; a semaphore wait
  deadlocks and reports as if the user denied it.
- **Open the microphone BEFORE playing the prompt chime.** Bluetooth
  earphones need ~1s to switch profiles; a chime-first order makes the user
  answer into a dead microphone.
- **The play/pause key can LAUNCH an app.** macOS routes it to whichever app
  is "now playing"; when nothing claims it, macOS opens your default media app
  instead: a stray press opened Apple Music. Audio alone is not evidence of a
  catcher: system sounds and command-line players make noise while claiming
  nothing. Send it only when a plausible media app is already running, and
  keep an undo: note whether Music was running before the press and close it
  again if it appears.
- **To know whether audio is really playing, read the power assertion**, not
  the CoreAudio device property: `pmset -g assertions | grep coreaudiod` shows
  `output.context.preventuseridlesleep` only while sound is actually coming
  out. It costs nothing and needs no permission. This is what makes sending
  the play/pause key safe: the key toggles, so it must never be sent blind.
- **There is no reliable "is audio playing?" query via CoreAudio.**
  `kAudioDevicePropertyDeviceIsRunningSomewhere` reports "running" whenever an
  app merely HOLDS the output device: Safari with a paused tab answers yes on
  a silent Mac. Do not gate anything on it, and never send the hardware
  play/pause key on the strength of it: that key TOGGLES, so a false positive
  starts audio the user had deliberately stopped.
- **Wispr Flow's "press enter" command** does not fire mid-dictation; it acts
  when the dictation is CLOSED (single Globe tap). The watcher relies on
  this.
- **The recogniser revises and restarts.** Transcripts may shrink after the
  user stops talking, and long speech arrives as multiple segments. Keep the
  longest text per segment and accumulate segments; do not keep "the latest".

## Uninstall

Run `./uninstall.sh`, then tell the user which two permission entries to
remove by hand (the script prints them; TCC cannot be edited by scripts).
