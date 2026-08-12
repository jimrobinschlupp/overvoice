# Overvoice

**Hands-free Claude Code.** Claude finishes a task, chimes in your earphones,
tells you what it did, and waits for your answer out loud. No keyboard, even
from the next room.

Built by a non-coder, with Claude, for people like me: if you use Claude Code
but don't write code yourself, this was made for you. It is a working setup
rather than a polished product: shell scripts, three small Swift helpers, and
a lot of iterating by using it and fixing whatever felt wrong.

## The loop

1. Claude Code finishes a task → a chime plays (your microphone opens)
2. You say **"yes"** → a spoken briefing of what Claude just did, read by a
   macOS voice
3. Another chime → you answer out loud:
   - short answers (**"go ahead"**, **"carry on"**, **"stop"**) are typed into
     Claude Code and sent immediately
   - longer sentences are read back first, with a moment to say **"stop"**
   - saying **"reply"** hands over to [Wispr Flow](https://wisprflow.ai) for
     proper dictation; end with *"press enter"* and it closes, types and
     sends by itself
   - saying **"ok"** closes the microphone at once and sends nothing

Say "no" or nothing at step 2 and it stays quiet. Every briefing is kept in
the menu bar under **Replay**, so a briefing you ignored isn't lost.

**Muted still remembers.** Switching Overvoice off silences everything (no
chimes, no speech, no microphone, and nothing of yours is paused), but
briefings are still written to the replay list, so you can catch up on what
happened while you were heads-down. Set `LOG_WHEN_OFF=0` if you would rather
it do nothing at all (that also stops it spending your Claude quota).

Speech recognition runs **on-device** (Apple's `SFSpeechRecognizer`); the only
network call is the summary, which goes through your own `claude` CLI.

## What it needs

- **macOS 12+** (Apple Silicon or Intel), with the Xcode Command Line Tools
  (`xcode-select --install`) and [`jq`](https://jqlang.github.io/jq/)
- **[Claude Code](https://claude.com/claude-code)**: the summaries are
  produced by `claude -p`, billed to your own plan
- **[Wispr Flow](https://wisprflow.ai)**: optional but worth it; Apple's
  recogniser is fine for "yes" and mangles anything technical
- **An OpenAI API key**: optional but strongly recommended. It runs out of the
  box on Apple's built-in voices, but those are a generation behind modern
  neural TTS and sound it, and this is a voice you listen to all day.
  `TTS_ENGINE=openai` is a large step up; `TTS_CMD` points at a local engine
  such as Kokoro or Piper instead
- **Bluetooth earphones with a microphone**: this is what makes it work away
  from the screen

## Install: the way this repo is meant to be used

Open this folder in Claude Code and say:

> Set this up for me, then walk me through the permission prompts.

The repo's `CLAUDE.md` contains the full instructions your agent needs,
including the macOS traps that cost hours to find the first time. Your agent
runs the installer, verifies each step, and tells you exactly what to click
when macOS asks for permissions.

### Or by hand

```bash
./install.sh
```

Then grant the two permissions it prints at the end. `./uninstall.sh`
removes everything again and lists the two permission entries to delete.

## Day-to-day controls

A round icon appears in the menu bar: three states, voice picker, speaking
speed, briefing detail, the three most recent briefings replayable in one click
with five more behind a submenu, and a stop button while one is being read. The same knobs exist in the terminal via `voice`
(`voice quiet`, `voice test`, `voice set "Ava (Premium)"`, …).

### How much it reads out

`voice detail`, or the same submenu in the menu bar, sets how much of a
finished turn you hear:

| level | what you hear |
|---|---|
| **briefing** | the closing recap your agent wrote for itself (default) |
| **full** | the whole message, unedited |
| **detailed** / **normal** / **brief** | a rewrite by a small model: roughly two thirds, a third, or a tenth as long |

`briefing` and `full` run no model at all, so they cost nothing and reach your
ear sooner. They are also the only two that cannot quietly drop something you
were asked to decide.

**`briefing` needs one rule in your `CLAUDE.md`.** Without it there is nothing
to read, and every turn falls back to `full`:

> End every substantial response with a short briefing: a `## Briefing`
> heading, then two or three sentences saying what was done, what it means, and
> what I need to decide next. Nothing after it. Skip it when the whole response
> is only a few lines.

It is the shortest setting that is still worth trusting. A summariser works
backwards from finished prose and can miss what mattered; an agent writing its
own closing recap has the whole turn in context, and puts on screen the exact
words you just heard.

### The three states

The three states are worth understanding, because the middle one is the useful
one:

| state | sound | notification |
|---|---|---|
| **On** | chime and spoken briefing | yes |
| **Notifications only** | silent | yes |
| **Off** | silent | none |

**Turn off Claude Code's own notifications.** Overvoice posts a notification
for every finished turn, so alongside Claude's you get two of everything, which
is enough to make you stop reading either. Overvoice's carries the session name
and the opening words of the briefing, and clicking it replays that briefing
aloud, so it is the one worth keeping. Turn Claude's off in System Settings →
Notifications → Claude.

**Stopping a briefing.** Say "stop" while it is playing, press the global
shortcut **⌘X** from anywhere, or use the menu. The shortcut needs no
permission and no recognition, and it is the reliable one on laptop speakers,
where the microphone hears the briefing better than it hears you and the
recogniser spends its window transcribing Overvoice rather than the room. On
headphones nothing leaks into the microphone and voice works fine. Rebind with
`STOP_HOTKEY` in `~/.claude/voice.conf`, or set it to `none`.

**If a Focus mode is on, notifications vanish silently.** macOS accepts them,
reports success to the app, and shows nothing, so it looks exactly like a bug:
the chime plays and no notification appears. Overvoice marks briefings as Time
Sensitive, which is the only thing an app can do about it, but macOS still
requires you to permit that per app. Either allow it in System Settings >
Notifications > Overvoice, or add Overvoice to the Focus itself under System
Settings > Focus > [your Focus] > Allowed Notifications. Set
`NOTIFY_TIME_SENSITIVE="0"` in `~/.claude/voice.conf` if you would rather they
behaved as ordinary notifications.

Do that and "Notifications only" becomes the state you actually live in when
you want quiet: no chime, no voice, but a briefing never passes unnoticed.
"Off" then genuinely means nothing at all, which is only what you want when you
mean it.

Deeper tuning (listening windows, silence thresholds, the wake words) lives as
plain variables at the top of `hooks/speak-summary.sh`, overridable in
`~/.claude/voice.conf`.

Download a **Premium** macOS voice (System Settings → Accessibility → Spoken
Content → Manage Voices); the default compact voices undersell the whole
thing. Note that Siri-branded voices are not available to the `say` command.

## Honest limitations

- **The Claude Code window must stay frontmost** for spoken replies to land:
  replies are typed keystrokes. Set `FRONT_MATCH` in `voice.conf` to
  `Terminal`, `iTerm2` or `Code` if that's where Claude Code runs for you.
- **One session at a time.** Two Claude Code sessions both fire the hook and
  fight over the microphone. Briefings are labelled by project so you know
  which is talking, and an answer has to be loud enough to be a person;
  otherwise one session's briefing, leaking out of the speakers, answers
  another session's chime. But they still interrupt each other.
- **Interrupting works, with a caveat.** Say "stop" and a briefing stops
  mid-sentence. The microphone also hears the briefing, so a briefing
  containing the word "stop" could in principle cut itself off; loudness is
  the discriminator, and `BARGE_LEVEL` sets the bar. Reliable on headphones,
  less so on laptop speakers. `voice bargein` calibrates it, `BARGE_IN=0`
  turns it off.
- **The voice engine is swappable.** `TTS_ENGINE=say` is the default because
  it needs no key, no network and no install, but Apple's voices are a
  generation behind modern neural TTS and sound it. `TTS_ENGINE=openai` (with
  `OPENAI_API_KEY`) is a large step up, and `TTS_CMD` lets you point at a
  local engine such as Kokoro or Piper instead.
- **Whatever is playing is paused**, not just dipped, so you never lose twenty
  seconds of a podcast to a briefing. It works by sending the hardware
  play/pause key (one system event that every media app respects, including
  browser tabs), and only ever when sound is genuinely coming out. No app is
  contacted, controlled or launched, and no Automation permission is asked
  for. **Your volume is never touched.** Anything that ignores the key simply
  keeps playing and the briefing goes over the top of it: harder to hear, and a
  deliberate trade, because dipping the system volume and boosting the briefing
  to compensate is far worse on headphones than the problem it solves. Rare
  edge case: if a media app is open but something else is making the sound, the
  key can briefly open Music, which is closed again automatically.
- **Bluetooth is audible.** When the AirPods microphone opens, macOS switches
  audio profiles and playback quality briefly dips. That is Bluetooth, not
  fixable in code.
- **English only** for the built-in yes/no vocabulary (the words live in
  `swift/OvervoiceListen.swift` if you want to change them).

Read `SECURITY.md` before installing: this tool types what it hears into
your coding agent, and you should understand what that means.

## License

MIT; see `LICENSE`.
