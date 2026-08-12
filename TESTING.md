# Testing checklist

Voice work cannot be verified from a script: loudness, timing and whether an
interruption *feels* responsive are all judgements only a person can make with
headphones on. This is the manual pass.

## Before anything else

- [ ] `voice listen` → allow **Microphone** and **Speech Recognition**, say
      "yes". It prints what it heard and a `peakInputLevel`: near 0.15 means
      your voice arrived, near 0.005 means it did not.

Rebuilding `Overvoice Listen` resets those two permissions every time, so redo
this after any change to `OvervoiceListen.swift`.

## The loop

- [ ] Finish a task → chime → say **"yes"** → briefing plays
- [ ] Say **"no"** or stay silent → it stays quiet
- [ ] After a briefing, say a short command ("go ahead") → typed and sent
- [ ] Say a long sentence → read back, then sent unless you say "stop"
- [ ] Say **"ok"** → microphone closes at once, nothing sent
- [ ] Say **"reply"** → Wispr Flow opens; dictate, end with "press enter"

## Interrupting

- [ ] Say **"stop"** while a briefing is playing → it stops mid-sentence
- [ ] `voice bargein` → speak a "stop" and read the measured level; set
      `BARGE_LEVEL` just below it
- [ ] Confirm a briefing that itself contains the word "stop" does *not* cut
      itself off (this is the echo case; headphones make it much safer)

## Media

- [ ] Spotify playing → briefing **pauses** it, then resumes
- [ ] Podcast in a browser tab → same
- [ ] Nothing playing → volume untouched, nothing opens
- [ ] A system sound playing → **no media app opens** (this was a real bug:
      the play/pause key launched Apple Music when nothing claimed it)

## Voice and pacing

- [ ] Try all five speed steps; each announces itself
- [ ] Stop a long briefing mid-sentence: it fades out quickly instead of
      cutting off mid-syllable
- [ ] Briefing detail: brief / normal / detailed

## Several projects at once

- [ ] Two sessions running → the briefing opens with the project name
- [ ] The replay list shows which project each briefing came from
