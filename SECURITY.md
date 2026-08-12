# Security & privacy: read this before installing

This tool exists to let spoken words drive a coding agent. That is also its
whole risk surface. Nothing here is hidden or unusual for a macOS automation
tool, but you should install it knowing all of it.

## What it can do once installed

- **It types what it hears.** Short spoken answers are typed into the
  frontmost window (guarded to apps matching `FRONT_MATCH`) and sent with
  Enter. Anyone audible near your Mac during a reply window (a TV, a
  roommate) can in principle send words to your coding agent, and your agent
  will act on them within whatever permission mode you run it in. Mitigations:
  the reply window only opens after a briefing you accepted, single stray
  words are dropped, longer replies are read back with a cancel window
  (`CONFIRM_SILENT_SENDS=0` makes silence cancel instead of send), and
  `REPLY_STAGE=0` turns spoken replies off entirely.
- **Overvoice Keys synthesises keystrokes.** It holds the Accessibility grant,
  and macOS grants that to the app, not to this project's scripts, so any
  local process could invoke it to type into the frontmost app. This is true
  of every Accessibility-granted automation tool (including AppleScript), but
  be aware you are adding one to your machine. Remove it in System Settings
  when you stop using this.
- **It never controls other applications.** Media is paused with the hardware
  play/pause key (a system-wide event, not a command aimed at any app), and
  only when sound is genuinely playing (checked via a power assertion, which
  needs no permission). That means no Automation permissions, and no app can
  be launched by accident.
  (An earlier version did script players, and asking a *closed* VLC about its
  state actually opened VLC: AppleScript loads an app's dictionary to
  compile a term, and loading it launches the app.)
- **Overvoice Listen holds Microphone + Speech Recognition.** Recognition is
  forced on-device (`requiresOnDeviceRecognition`); audio never leaves the
  Mac. The microphone is only open during the short windows around a
  briefing; there is no wake word and no always-on listening.

## Where your data goes

- **Summaries**: the text of Claude's finished message is rewritten for
  speech by Claude. By default that happens through your own `claude` CLI,
  the same data path your Claude Code session already uses. If you put an
  API key in `~/.claude/anthropic-key` (see `SUMMARY_ENGINE` in the hook),
  the text is sent directly to `api.anthropic.com` with that key instead.
- **Speech**: the default engine is Apple's `say`, which runs entirely
  on-device. If you opt into `TTS_ENGINE=openai`, each briefing's text is
  sent to `api.openai.com` with your key to be turned into audio.
- **Transcripts**: what the listener heard is logged to
  `~/.claude/menubar/listen.log` (auto-rotated, git-ignored); useful for
  debugging, delete freely. Briefing texts are kept in
  `~/.claude/menubar/briefings.tsv` for the menu bar's replay feature (last
  25).
- Beyond the calls above, nothing is stored or transmitted. No analytics,
  and no network traffic you did not opt into.

## Trust notes

- It changes no system settings, not even the output volume. Briefings play
  through the tool's own small player, which fades its own audio in and out.
  (An earlier version adjusted the system volume; that is gone.)
- `~/.claude/voice.conf` is **sourced by a shell script**. It is your file in
  your home directory; treat it like a dotfile and don't paste settings into
  it from strangers.
- The installer edits `~/.claude/settings.json` via `jq`, validates the
  result, and keeps a backup (`settings.json.backup-overvoice`).
- Everything runs as you; nothing asks for sudo, ever.
