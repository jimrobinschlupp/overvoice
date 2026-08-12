#!/bin/bash
# Speaks a short summary of what Claude just did, out loud, every time it
# finishes a turn. Wired up as a "Stop" hook in ~/.claude/settings.json.
#
# Turn it off:  touch ~/.claude/voice-off
# Turn it on:   rm ~/.claude/voice-off

# ---- knobs -------------------------------------------------------------
# "chime+speak" | "speak". There was a third, "chime", that played a tone and
# nothing else. It dated from before briefings existed, and Claude Code already
# pings you when it finishes, so it was a worse copy of something you have.
MODE="chime+speak"
# Three sounds, three meanings. Anything more and they stop being learnable:
# Tink previously meant "heard you", "handing to Wispr" AND "say stop now",
# which is three unrelated jobs for one tone.
CHIME="Glass"             # YOUR MOVE - the mic is open. Any name from /System/Library/Sounds
CHIME_VOL=0.55            # the loudest cue, because it is the one you must act on
ACK_SOUND="Tink"          # GOT IT - no action needed
ACK_VOL=0.30
# No sound marks a stop. The briefing going quiet IS the confirmation, and a
# tone on top of it says nothing you did not just hear for yourself.
PLAYER="$HOME/.claude/menubar/overvoice-play"
SPLIT_WORDS=35            # how much of a briefing is rendered before the gate.
                          # Whole sentences, so the join lands on a full stop.
                          # Larger costs more per unanswered briefing; smaller
                          # risks the opening running out before the rest has
                          # finished rendering.
PLAY_GAIN=4.0             # playback gain. Neural speech comes back quiet:
                          # measured on a real briefing, peak amplitude 0.157,
                          # which is 16 dB below full scale and plays as a
                          # mumble. 4x lands near 0.63, loud without clipping.
FADE_SECONDS=0.35         # how quickly a stopped briefing fades out. afplay
                          # cannot fade, so briefings play through the helper
                          # above; it falls back to afplay if that is missing.
# ---- which engine actually speaks -------------------------------------
# macOS `say` is the default because it needs no key, no network and no
# install. It is also the weakest link: Apple's voices sound dated next to
# modern neural TTS. These are the escape hatches.
TTS_ENGINE=say            # say | openai | command
TTS_OPENAI_VOICE=sage     # alloy ash ballad coral echo fable nova onyx sage shimmer
TTS_OPENAI_MODEL=gpt-4o-mini-tts
# The delivery, in plain English. This matters more than the voice: left to
# themselves these voices perform — bright, presenterly, over-warm. What is
# wanted is a colleague telling you something while you get on with your
# morning. Audition changes with `voice tts`.
TTS_OPENAI_STYLE="Speak like a friend talking over their shoulder about something they just finished, half distracted and already onto the next thing. Relaxed and offhand, at an easy everyday pace, closer to thinking out loud than to reporting. Nothing here is an achievement: no pride, no sense of occasion, no weight or triumph on the opening word, no gravitas, no presenter or announcer energy, no dramatic emphasis, no rising finish. Let commas and full stops breathe. Ask any closing question lightly, the way you would ask someone if they want a coffee."
# Your key. Kept in a file rather than the config so it is easy to lock down:
#   printf '%s' 'sk-...' > ~/.claude/openai-key && chmod 600 ~/.claude/openai-key
TTS_KEY_FILE="$HOME/.claude/openai-key"
TTS_CMD=""                # custom engine: gets the text as $1 and a target
                          # file path as $2, and must write audio to it.
                          # This is how you plug in a local neural voice
                          # (Kokoro, Piper) or any other service.
VOICE="Samantha"          # `say -v '?'` lists installed voices
RATE=185                  # words per minute
GATE=1                    # 1 = chime, then wait for a spoken yes before briefing
LISTEN_SECONDS=9          # how long to listen for that answer
DUCK=1                    # 1 = pause whatever is playing while speaking.
                          # No app is ever contacted, controlled or launched:
                          # this sends the hardware play/pause key, which every
                          # media app respects — Spotify, Music, VLC, a podcast
                          # in a browser tab — and needs no Automation
                          # permission. Falls back to dipping the volume only
                          # if something ignores the key.
# Nothing here ever changes your system volume. It used to, as a fallback when
# the play/pause key found no owner: it dropped the volume to a fraction, played
# the briefing at 4x gain to compensate, then walked the volume back up in
# stages. On headphones that lands as a sudden loud briefing followed by your
# audio lurching back, which is worse than the problem it solved. If media
# cannot be paused, the briefing simply plays over it at its own volume.
# Extra players to recognise as media-key catchers, if yours is missing from
# the built-in list (Safari, Chrome, Firefox, Arc, Brave, Spotify, Music, VLC,
# IINA, Podcasts, TV, QuickTime). Matched against the running process path.
# "briefing" | "full" | "detailed" | "normal" | "brief".
#
# "full" reads the actual message out, markdown stripped, with nothing rewritten
# or dropped. It was the default because a summary you cannot rely on is worse
# than a long one: if a turn asks for four things and the briefing mentions one,
# the briefing has to be checked against the real output anyway, which defeats
# the point of listening. Full costs nothing to produce and starts sooner, since
# no summariser runs at all.
#
# "briefing" is full's short form, and the default. It reads the closing recap
# the message wrote for itself under a "Briefing" heading, and falls back to
# full when there isn't one. That recap answers the objection to summarising:
# it is written by the model that did the work, with the whole turn in context
# rather than a rewrite of the finished text, and it is on screen to be checked
# against. Like full, no summariser runs. It needs the writing end to cooperate
# — see BRIEFING CONVENTION below.
#
# The rewritten depths are shorter but lossy. They are told to keep every item
# that needs an answer.
#
# BRIEFING CONVENTION. "briefing" only has something to read if the agent ends
# its messages with one. Put a rule like this in your CLAUDE.md:
#
#   End every substantial response with a short briefing: a "## Briefing"
#   heading, then two or three sentences saying what was done, what it means,
#   and what I need to decide next. Nothing after it. Skip it when the whole
#   response is only a few lines.
#
# Without that rule nothing breaks; every turn simply falls back to full.
DEPTH="briefing"
MODEL="claude-haiku-4-5-20251001"   # small + fast model used to write the summary
# How the summary gets written. "auto" uses the Anthropic API when a key is
# present and falls back to the `claude -p` CLI when it is not.
#
# The API is worth the key. Going through the CLI loads the entire Claude Code
# system prompt and tool set for a job that needs none of it, and it thinks
# before answering: measured over 298 briefings, a median of 22,700 tokens of
# context and 3,700 output tokens to produce three spoken sentences. The API
# carries the prompt alone. It also bills an API key instead of the Claude Code
# subscription, so briefings stop consuming the quota meant for real work.
SUMMARY_ENGINE=auto       # auto | api | cli
# Same shape as the speech key, and locked down the same way:
#   printf '%s' 'sk-ant-...' > ~/.claude/anthropic-key && chmod 600 ~/.claude/anthropic-key
ANTHROPIC_KEY_FILE="$HOME/.claude/anthropic-key"
REPLY_STAGE=1             # 1 = after the briefing, listen for your reply
FRONT_MATCH="Claude"      # replies are only typed when the frontmost app's name
                          # contains this — set to Terminal, iTerm2, or Code if
                          # that is where your Claude Code runs
REPLY_SECONDS=6           # how long to wait for you to START replying. Short on
                          # purpose: if you have nothing to say, this is dead
                          # time you have to sit through in silence. Saying "ok"
                          # ends it instantly, so the window only needs to cover
                          # deciding whether to speak at all, not composing.
SILENCE_GAP=2.5           # quiet needed after you stop before the reply is taken.
                          # 1.5 cut the user off mid-sentence on a normal thinking pause
CONFIRM_SECONDS=5         # window to say "stop" before a long reply is sent
CONFIRM_SILENT_SENDS=1    # 1 = silence after the read-back sends (hands-free);
                          # 0 = silence cancels, only a spoken "yes" sends
# A global key that stops a briefing without needing to be heard. Voice cannot
# be made reliable on laptop speakers: the microphone hears the briefing better
# than it hears the room, so the recogniser spends the window transcribing
# Overvoice itself. A key press has no such problem, and works identically on
# headphones. "none" disables it. Modifiers: cmd, shift, opt, ctrl.
# Held ONLY while a briefing is speaking, then released. A global hotkey
# outranks every application shortcut, so holding one permanently would take
# that combination away from the whole machine for the 99% of the time nothing
# is playing. Arming it only during playback is what makes plain cmd+x safe:
# Cut behaves normally, except in the seconds when the thing worth cutting
# short is Overvoice talking. "none" disables it.
STOP_HOTKEY="cmd+x"
BARGE_IN=1                # say "stop" while it is talking and it stops
BARGE_WORDS="stop,quiet,cancel,enough"
BARGE_MAX_SECONDS=75      # hard ceiling on how long barge-in may hold the mic
GATE_MIN_LEVEL=0.035      # a spoken answer must be at least this loud to count.
                          # Measured on a MacBook mic: a real "yes" lands near
                          # 0.048, silence near 0.004, and a briefing leaking
                          # out of the speakers near 0.026 — which is how one
                          # session's briefing was able to answer ANOTHER
                          # session's chime. Raise if that still happens; lower
                          # if quiet answers get ignored.
BARGE_LEVEL=0.018         # how loud a "stop" must be to count.
                          #
                          # This used to be the ONLY thing stopping a briefing
                          # interrupting itself by reading the word aloud, so it
                          # was set high. It is not any more: those words are
                          # stripped from the briefing text before it is spoken,
                          # so the briefing cannot say them at all. All this
                          # guards now is the recogniser mishearing briefing
                          # audio AS a stop word, which is far rarer and worth
                          # far less strictness.
                          #
                          # Measured: a real "stop" on AirPods was rejected at
                          # 0.028 against the old 0.030 threshold. The comment
                          # here used to claim voices "arrive far louder" on
                          # AirPods; they do not.
READBACK_MIN_WORDS=6      # shorter than this is sent straight out. The read-back
                          # guards against a long sentence being mangled; for
                          # "yes please" it is just ceremony
EARLY_WORDS="reply,dictate,ok,okay,thanks,nothing"   # acted on the instant heard
WISPR_AUTOSTOP=1          # close Wispr dictation for you when you stop talking
WISPR_SECONDS=90          # long dictations are the point of using Wispr
WISPR_SILENCE=6.0         # fallback only. The end phrase is the real signal, so
                          # this can be generous - a long think must not close it
WISPR_END_PHRASE="press enter"   # say this and it closes immediately
SAY_PROJECT=auto          # auto = name the project only when more than one
                          # session has been active recently; always | never
MULTI_WINDOW=30           # minutes; how recently another session must have run
                          # to count as "also going on right now"
# Whichever process is currently speaking a briefing, live or replayed. Exactly
# one voice at a time, across every session and the menu bar app.
VOICE_PID="$HOME/.claude/menubar/voice.pid"
# A moment of silence played immediately before every briefing. On Bluetooth the
# output route takes a few hundred milliseconds to come up from idle, and
# whatever plays during that window is simply lost. With the session name at the
# front of the briefing, the thing being swallowed was the name.
# Rendered briefings, kept so a replay starts instantly instead of waiting on
# another round trip to the speech API for audio that was already paid for.
CLIP_CACHE="$HOME/.claude/menubar/clips"
CLIP_KEEP=40              # how many rendered briefings to keep
BRIEF_FILE="$HOME/.claude/menubar/last-briefing.txt"
BRIEF_LOG="$HOME/.claude/menubar/briefings.tsv"
LISTENER_APP="$HOME/Applications/Overvoice Listen.app"
KEYS_APP="$HOME/Applications/Overvoice Keys.app"
LISTENER="$LISTENER_APP/Contents/MacOS/OvervoiceListen"
# ------------------------------------------------------------------------

# The `voice` command writes overrides here, so it can change settings without
# anyone hand-editing this file. Sourced last, so the file always wins.
[ -f "$HOME/.claude/voice.conf" ] && . "$HOME/.claude/voice.conf"

# Guard: the summariser below runs `claude -p`, which itself fires a Stop hook.
# Without this the script would call itself forever.
[ -n "$CLAUDE_VOICE_HOOK" ] && exit 0

# Checked REPEATEDLY, not once at startup. A briefing flow runs for up to a
# minute — summary, chime, listening, speech, reply window — so a single check
# at the top left anything already in flight chiming away after you switched
# it off. Every stage below asks again.
is_off() { [ -f "$HOME/.claude/voice-off" ]; }

# Muted still writes the briefing to the replay list, so nothing is lost while
# you are heads-down; it just never makes a sound. That does still spend a
# little of your Claude quota per turn — set LOG_WHEN_OFF=0 for true silence.
LOG_WHEN_OFF=${LOG_WHEN_OFF:-1}
if is_off && [ "$LOG_WHEN_OFF" != "1" ]; then exit 0; fi

# Flatten markdown into something speakable. Note the inline-code rule UNWRAPS
# rather than deletes: deleting it ate whole phrases mid-sentence, so a line
# about a setting called "raw" came out as "is now the default", which is
# nonsense. Same for link text — keep the words, drop the URL.
# Typed keystrokes lose non-ASCII along the way: an em-dash arrived as "‚Äî".
# Perl rather than sed — macOS sed treats multibyte characters as separate
# bytes, so one em-dash came out as three hyphens.
to_ascii() {
  perl -CSD -pe 's/[\x{2014}\x{2013}]/-/g; s/[\x{2018}\x{2019}]/\x27/g; s/[\x{201C}\x{201D}]/"/g; s/\x{2026}/.../g; s/[^\x00-\x7F]//g'
}

# Things that are unreadable ALOUD even though they are perfectly fine on screen.
# Reading the full output means reading everything, including git commit hashes,
# which come out as "E7 F C 4 8 6": letter-number soup carrying no meaning to a
# listener, in the middle of an otherwise normal sentence.
#
# Matched as 7 to 40 hex characters containing at least one digit. The digit is
# what keeps ordinary words out: "accede" and "deface" are entirely hex letters,
# and a hash without a digit is rare enough to be worth losing over a false
# positive that eats a real word.
# The opening of a briefing, as whole sentences, at least $2 words long.
#
# A briefing is rendered in two pieces: this opening before the chime, and the
# rest only once someone has said yes. Measured over 88 renders, 85% of the
# audio being paid for was never heard, because the render happens before the
# gate and most gates are never answered.
#
# Split on a SENTENCE, never mid-thought. The join between the two pieces is
# audible as a short gap, and at a full stop that gap is just a pause.
split_head() {   # $1 text  $2 minimum words
  printf '%s' "$1" | perl -e '''
    my $t = do { local $/; <STDIN> };
    my $min = $ARGV[0];
    my @s = ($t =~ /([^.!?]*[.!?]+[\s]*|[^.!?]+$)/g);
    my ($head, $n) = ("", 0);
    for my $x (@s) {
      $head .= $x;
      $n += scalar(() = $x =~ /\S+/g);
      last if $n >= $min;
    }
    $head =~ s/\s+$//;
    print $head;
  ''' "$2"
}

strip_unspeakable() {
  # Take the preposition with the hash, so "committed as e7fc486" becomes
  # "committed" rather than the clipped "committed as". Runs of hashes joined by
  # "and" go as one unit, otherwise "in A and B" leaves a stranded "and".
  #
  # Only artifacts the removal itself created are tidied afterwards: a space
  # before punctuation, a doubled space, a dangling "and" left in front of one.
  # Nothing reaches into surrounding grammar, because guessing at that does more
  # damage than a slightly clipped sentence.
  perl -pe '''
    my $h = qr/(?=[0-9a-f]{7,40}\b)(?=[a-f0-9]*[0-9])[0-9a-f]{7,40}/;
    s/\b(?:as|in|at|to|from|is|was)\s+$h(?:\s*,?\s*and\s+$h)*\b//gi;
    s/\b$h(?:\s*,?\s*and\s+$h)*\b//g;
    s/\s+and\s*([.,;:])/$1/g;
    s/\s+([.,;:])/$1/g;
    s/  +/ /g;
    s/^\s+//;
  '''
}

strip_markdown() {
  sed -E 's/\[([^]]*)\]\([^)]*\)/\1/g' \
    | sed -E 's/`([^`]*)`/\1/g' \
    | tr -d '*#>|' \
    | tr '_' ' ' \
    | tr '\n' ' ' \
    | sed -E 's/  +/ /g'
}

# The closing recap the message wrote for itself, or nothing.
#
# Everything after a final "Briefing" heading, with the heading itself dropped —
# spoken, it is a stray noun with no pause after it, because strip_markdown
# removes the # but keeps the word and flattens the line break.
#
# The LAST matching heading wins, not the first. A turn that discusses this
# feature says the word earlier; the real recap is always the final one.
#
# Nothing is printed when there is no heading, or when what follows is too short
# to be a recap. An empty result is how the caller knows to fall back, so a
# malformed briefing costs the full message rather than silence.
extract_briefing() {
  perl -e '''
    my @lines = split /\n/, do { local $/; <STDIN> }, -1;
    my $at = -1;
    for my $i (0 .. $#lines) {
      $at = $i if $lines[$i] =~
        /^\s{0,3}(?:\#{1,6}\s*\*{0,2}briefing\*{0,2}|\*\*briefing\*\*)\s*:?\s*$/i;
    }
    exit 0 if $at < 0;
    my $body = join "\n", @lines[$at + 1 .. $#lines];
    $body =~ s/^\s+//;
    $body =~ s/\s+$//;
    exit 0 if scalar(() = $body =~ /\S+/g) < 4;
    print $body;
  '''
}

# ---- stage 2: the slow half, re-invoked detached ------------------------
# Reached only via the self-exec at the bottom. The transcript path arrives as
# $1 rather than on stdin, because the detached copy has no stdin to read.
if [ "$1" = "--speak" ]; then
  TRANSCRIPT="$2"

  # Only one flow at a time. A previous turn's reply window can still be open
  # when the next turn begins; the two then fight over the microphone and both
  # write the briefing file, so the wrong question gets read out. Take over
  # from any earlier run rather than running alongside it.
  LOCK="$HOME/.claude/menubar/flow.pid"
  # Do NOT find other flows with `pgrep -f`: every command substitution forks a
  # subshell that inherits this script's command line, so the pattern matches
  # this flow's own transient children and killing them corrupts whatever value
  # was being computed. The pid file is the only safe handle.
  #
  # Claim the lock with an atomic mv, then check the claim survived: if a newer
  # flow has since written its own pid, this one is obsolete and gets out of the
  # way instead of competing for the microphone.
  OLD=$(cat "$LOCK" 2>/dev/null)
  printf '%s' "$$" > "$LOCK.tmp.$$" 2>/dev/null && mv -f "$LOCK.tmp.$$" "$LOCK"
  sleep 0.4
  if [ "$(cat "$LOCK" 2>/dev/null)" != "$$" ]; then
    rm -f "$LOCK.tmp.$$" 2>/dev/null
    exit 0
  fi
  if [ -n "$OLD" ] && [ "$OLD" != "$$" ] && kill -0 "$OLD" 2>/dev/null; then
    kill "$OLD" 2>/dev/null
    # Wait for it to go. Its trap has media and microphone teardown to do, and
    # starting before it finishes puts two flows on the microphone.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$OLD" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$OLD" 2>/dev/null   # wedged in a syscall and ignoring TERM
  fi
  # Any listener still alive here belongs to a flow that is already gone.
  pkill -f OvervoiceListen 2>/dev/null

  # How loud was the utterance behind the verdict just written? The listener
  # records it; reading it back costs nothing and needs no rebuild.
  last_heard_level() {
    grep 'verdict=' "$HOME/.claude/menubar/listen.log" 2>/dev/null \
      | tail -1 | sed -n 's/.*peakInputLevel=\([0-9.]*\).*/\1/p'
  }
  # Reject answers quiet enough to be something other than a person: our own
  # speech leaking into the microphone, a video, another session talking.
  too_quiet_to_be_you() {
    local lvl; lvl=$(last_heard_level)
    [ -z "$lvl" ] && return 1
    awk -v a="$lvl" -v b="$GATE_MIN_LEVEL" 'BEGIN{exit !(a < b)}'
  }

  play_chime() {
    is_off && return 0
    [ -f "/System/Library/Sounds/$CHIME.aiff" ] &&
      afplay -v "$CHIME_VOL" "/System/Library/Sounds/$CHIME.aiff" 2>/dev/null
  }

  # The Stop hook can fire before the final assistant message has been flushed
  # to the transcript. Reading immediately summarised an EARLIER block of the
  # turn and silently dropped the closing question — so the briefing asked
  # nothing while Claude waited on an answer. Wait for the file to settle.
  SETTLE=0
  while [ "$SETTLE" -lt 8 ]; do
    MT1=$(stat -f %m "$TRANSCRIPT" 2>/dev/null)
    sleep 0.4
    MT2=$(stat -f %m "$TRANSCRIPT" 2>/dev/null)
    [ "$MT1" = "$MT2" ] && break
    SETTLE=$((SETTLE + 1))
  done

  # Pull the text of the most recent assistant message. `tail -r` reverses the
  # file so the newest entry comes first; `fromjson? // empty` skips any line
  # that isn't clean JSON so a malformed row can't break the whole thing.
  LAST=$(tail -r "$TRANSCRIPT" \
    | jq -R 'fromjson? // empty' \
    | jq -rs 'map(select(.type == "assistant" and (.isSidechain != true)))
              | map([.message.content[]? | select(.type == "text") | .text] | join(" "))
              | map(select(length > 0))
              | first // ""')

  [ -z "$LAST" ] && exit 0

  # Which session is this? Several sessions routinely share one repo, so the
  # folder name answers "where" when the question is "which one". The name that
  # matters is the one on screen in the Claude app, so it is read from the app's
  # own session store rather than derived or computed anywhere else.
  #
  # There is deliberately NO fallback. An earlier version used titles computed
  # by a separate tool, and those never matched the sidebar, so briefings
  # announced names that did not correspond to anything visible. A missing name
  # is fine; a wrong one is the failure being avoided. If the session cannot be
  # identified, it simply goes unnamed.
  app_session_title() {   # $1 = session id, as passed to hooks
    local d="$HOME/Library/Application Support/Claude/claude-code-sessions" f t
    [ -d "$d" ] || return 0
    # while-read rather than `for f in $(...)`: the store lives under
    # "Application Support" and unquoted word splitting tears the path in half
    # at the space, which silently yields no title at all.
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      # select() so the id has to BE the cliSessionId, not merely appear
      # somewhere in the file.
      t=$(jq -r --arg s "$1" 'select(.cliSessionId == $s) | .title // empty' \
            "$f" 2>/dev/null)
      [ -n "$t" ] && { printf '%s' "$t"; return 0; }
    done < <(grep -rl "$1" "$d" --include='local_*.json' 2>/dev/null | head -5)
    return 0
  }
  SESSION_ID=$(basename "$TRANSCRIPT" .jsonl)
  # cliSessionId goes stale when a session is resumed, so this legitimately
  # comes back empty sometimes. That is the intended outcome, not a failure.
  PROJECT=$(app_session_title "$SESSION_ID")

  # Is more than one session on the go? Project folders are encoded paths and
  # so begin with "-"; that filters out Claude's own internal directories.
  other_sessions() {
    find "$HOME/.claude/projects" -maxdepth 2 -name '*.jsonl' -mmin -"$MULTI_WINDOW" 2>/dev/null \
      | sed 's|/[^/]*$||' | sort -u | grep -c '/-'
  }

  # Drop fenced code blocks — they cost tokens and never belong in speech.
  CLEAN=$(printf '%s' "$LAST" | sed '/^```/,/^```/d')

  # Taken before the windowing below, so the recap survives a message long
  # enough to have its middle cut. The tail is kept and would carry it anyway,
  # but that is a coincidence of the numbers rather than a guarantee.
  BRIEF_SECTION=$(printf '%s' "$CLEAN" | extract_briefing)

  # Send the message as close to whole as possible: a summary should actually
  # cover what happened, so only genuinely huge messages get windowed, and then
  # the middle goes rather than the end. The ending is where any question to
  # the user lives.
  if [ "$(printf '%s' "$CLEAN" | wc -c)" -gt 14000 ]; then
    CLEAN="$(printf '%s' "$CLEAN" | head -c 8000)
[...]
$(printf '%s' "$CLEAN" | tail -c 5000)"
  fi
  [ -z "$CLEAN" ] && exit 0

  # Proportional, not a fixed cap. A word limit is arbitrary against a message
  # of unknown size: it pads a short turn and crushes a long one to the same
  # length, when what is wanted is the same message at a smaller scale.
  #
  # Every one of these carries the same floor, set in the prompt: whatever the
  # proportion works out to, nothing the listener has to respond to is dropped.
  # A short turn that asks four things stays four things long.
  case "$DEPTH" in
    brief)
      LENGTH="roughly a tenth as long as the message. Compress hard: the headline and the open items, nothing else" ;;
    detailed)
      LENGTH="roughly two thirds as long as the message. Walk through each significant thing that was done, in the order it happened, then everything left open. Do not skip steps to save space" ;;
    *)
      LENGTH="roughly a third as long as the message. Cover the main things done, not just the headline" ;;
  esac

  PROMPT="Rewrite the message below to be READ ALOUD to someone walking around with earphones in. Speak in first person past tense, casual: 'I just...' or 'Done -...'.

Length: $LENGTH.

How to structure it:
- Open with what actually changed or happened.
- Then give EVERY item that needs something from the listener: every question, every decision, every choice, every thing being waited on. If there are four, say all four. If there are none, say none.
- Completeness beats brevity, and it beats being easy to answer. A briefing that mentions one of four open items is worse than useless: the listener cannot trust it, so they have to go back and read the real output, and listening bought them nothing. Never reduce several open items to a single question, and never pick the most important one and drop the rest.
- Do NOT force the ending into a yes/no question. If the message asks for several things, list them and let the listener answer in their own words. They can reply at length. An accurate list of four things is far more useful than one tidy question.
- Number them out loud when there are several, so they can be followed and answered one by one: 'First... Second... Third...'.
- If the message contains no question and asks for no decision, end with a plain closing statement. Never invent a question that was not asked.
- Never end on a heading, a sentence fragment, or a trailing clause.
- If the message is too long for the length limit, cut description of work already finished. Never cut anything the listener has to respond to.

Never use the words stop, quiet, cancel or enough. They are the spoken commands that interrupt this briefing, so saying one cuts you off mid-sentence. Use halt, silent, call off or sufficient instead.

Plain spoken English only: no markdown, no bullets, no headings, no file paths, no code, no symbols. Do not describe the shape of the message ('first I explained, then I said'). Say what changed and why it matters, not how. Output only the spoken text, nothing else.

The message may contain a marker where a long middle section was cut. Ignore it and summarise what remains.

<message>
$CLEAN
</message>"

  slog() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$1" \
    >> "$HOME/.claude/menubar/listen.log" 2>/dev/null; }

  # Rewrite the message. Two ways to do it, and the difference is large.
  #
  # `claude -p` loads the whole Claude Code system prompt and every tool
  # definition before running a job that uses none of them. Measured across 298
  # real briefings: a median of 22,700 tokens of context to rewrite three
  # sentences, and a median of 3,700 output tokens to produce about 110 tokens
  # of speech, because it thinks first. Roughly 97% of that is harness.
  #
  # The API call carries the prompt and nothing else, and does not think, so the
  # same work costs a few hundred tokens. It bills to an API key rather than the
  # Claude Code subscription, which is the point: briefings stop eating the
  # quota meant for actual work.
  #
  # No key, or the call fails, and it falls straight back to the CLI. Nothing
  # here is required for Overvoice to work.
  summarise() {   # $1 prompt -> spoken text on stdout
    local key="" resp text
    [ -n "$ANTHROPIC_API_KEY" ] && key="$ANTHROPIC_API_KEY"
    [ -z "$key" ] && [ -r "$ANTHROPIC_KEY_FILE" ] \
      && key=$(tr -d '[:space:]' < "$ANTHROPIC_KEY_FILE")
    if [ "$SUMMARY_ENGINE" != "cli" ] && [ -n "$key" ]; then
      resp=$(curl -sS --max-time 30 https://api.anthropic.com/v1/messages \
        -H "x-api-key: $key" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d "$(jq -n --arg m "$MODEL" --arg p "$1" \
              '{model:$m, max_tokens:600, messages:[{role:"user",content:$p}]}')" \
        2>/dev/null)
      text=$(printf '%s' "$resp" | jq -r '.content[0].text // empty' 2>/dev/null)
      if [ -n "$text" ]; then
        # Record what it cost. The whole reason this exists is the token bill,
        # so every call says what it spent rather than needing a dashboard.
        slog "summary: api $(printf '%s' "$resp" | jq -r \
          '"in=\(.usage.input_tokens) out=\(.usage.output_tokens)"' 2>/dev/null)"
        printf '%s' "$text"
        return 0
      fi
      slog "summary: api FAILED -> claude -p: $(printf '%s' "$resp" \
        | jq -r '.error.message // empty' 2>/dev/null | head -c 120)"
    fi
    slog "summary: claude -p"
    CLAUDE_VOICE_HOOK=1 claude -p --model "$MODEL" "$1" < /dev/null 2>/dev/null
  }

  # Write the summary BEFORE chiming. It used to run in the background so the
  # chime could fire immediately, but that put the wait AFTER the answer — you
  # said yes and then sat in silence. Waiting here is invisible: you are
  # already waiting on Claude. Once you answer, the briefing starts instantly.
  # Time it. A briefing cannot appear in the replay list until it has been
  # written, so this delay IS the answer to "why was it not there yet" — worth
  # having on record rather than guessing at.
  T0=$(date +%s)
  if [ "$DEPTH" = "briefing" ] && [ -n "$BRIEF_SECTION" ]; then
    # Read the recap the message ends with. Not a rewrite of the finished text
    # by a second model, but what the model that did the work said about it, so
    # nothing is inferred back out of prose. No summariser runs.
    SUMMARY=$(printf '%s' "$BRIEF_SECTION" | strip_markdown | strip_unspeakable)
    slog "summary: message briefing, no model ($(printf '%s' "$SUMMARY" | wc -w | tr -d ' ') words)"
  elif [ "$DEPTH" = "full" ] || [ "$DEPTH" = "briefing" ]; then
    # Read the actual message. Nothing is rewritten, so nothing can be dropped:
    # the briefing is exactly what was written, minus the parts that cannot be
    # spoken. No model runs, so this is both the most faithful option and the
    # fastest one to reach the ear.
    #
    # Also where "briefing" lands when a turn wrote no recap — short turns are
    # told to skip it, and the whole message is the right thing to read then.
    SUMMARY=$(printf '%s' "$CLEAN" | strip_markdown | strip_unspeakable)
    slog "summary: full output, no model ($(printf '%s' "$SUMMARY" | wc -w | tr -d ' ') words)"
  else
    SUMMARY=$(summarise "$PROMPT")
    slog "summary: took $(( $(date +%s) - T0 ))s"
  fi

  # Only if the summariser was unreachable — better than going silent.
  if [ -z "$SUMMARY" ]; then
    SUMMARY=$(printf '%s' "$CLEAN" | strip_markdown | cut -c1-280)
  fi

  SPEAK=$(printf '%s' "$SUMMARY" | strip_markdown)
  [ -z "$SPEAK" ] && exit 0

  # A briefing is read aloud with a barge-in listener running, so a briefing
  # that says "stop" interrupts itself. That is not hypothetical: a briefing
  # about barge-in said the word and cut itself off mid-sentence.
  #
  # Only the bare word can do it. The matcher tokenises on letters and compares
  # whole words, so "stopped" and "stopping" are already safe and just the exact
  # tokens need swapping. Doing it here rather than trusting the prompt makes it
  # a guarantee: the model is asked to avoid these words too, but a briefing
  # that silences itself is not something to leave to chance.
  defang_barge_words() {
    local t="$1" w repl
    local OLDIFS="$IFS"; IFS=,
    for w in $BARGE_WORDS; do
      IFS="$OLDIFS"
      case "$w" in
        stop)   repl="halt" ;;
        quiet)  repl="silent" ;;
        cancel) repl="scrap" ;;      # transitive, so "scrap it" reads naturally
        enough) repl="sufficient" ;;
        *)      repl="" ;;      # a custom barge word with no known synonym
      esac
      if [ -n "$repl" ]; then
        t=$(printf '%s' "$t" | W="$w" R="$repl" perl -pe \
          's{\b(\Q$ENV{W}\E)\b}{ $1 =~ m/^[A-Z]/ ? ucfirst($ENV{R}) : $ENV{R} }gie')
      fi
      IFS=,
    done
    IFS="$OLDIFS"
    printf '%s' "$t"
  }
  [ "$BARGE_IN" = "1" ] && SPEAK=$(defang_barge_words "$SPEAK")

  # With several sessions running, the first sentences are otherwise spent
  # working out WHICH project you are being told about — by which point you
  # have stopped listening to the content. Naming it up front costs a second.
  # Session titles carry a scope prefix separated by a middle dot, as in
  # "VOICE · Overvoice logo". That reads fine on screen and badly out loud, so
  # the spoken form turns the separator into a comma and lets it land as a
  # natural pause. The written form keeps the dot.
  SPOKEN_LABEL=$(printf '%s' "$PROJECT" | sed 's/ *· */, /g')
  ANNOUNCE=""
  if [ -n "$SPOKEN_LABEL" ]; then
    case "$SAY_PROJECT" in
      always) ANNOUNCE="$SPOKEN_LABEL. " ;;
      auto)   [ "$(other_sessions)" -gt 1 ] && ANNOUNCE="$SPOKEN_LABEL. " ;;
    esac
  fi

  # Stash the spoken text. A voice reply is an answer to THIS wording, not to
  # whatever Claude originally wrote, and Claude never sees this paraphrase —
  # so a bare "no" would otherwise arrive with nothing to anchor it to.
  printf '%s' "$SPEAK" > "$BRIEF_FILE" 2>/dev/null

  # The row that becomes the replay entry AND raises the notification: the
  # menu bar app watches this file. Written immediately before the chime
  # rather than here, so the notification and the chime land together instead
  # of twenty seconds apart.
  #
  # Still written before the GATE, so a briefing you never answered is in the
  # replay list to catch up on later. Only the render now comes first.
  #
  # time, label, text: the middle column is the session title where one exists.
  log_briefing() {
    printf '%s\t%s\t%s\n' "$(date '+%H:%M')" "$PROJECT" \
      "$(printf '%s' "$SPEAK" | tr '\t\n' '  ')" >> "$BRIEF_LOG" 2>/dev/null
    tail -25 "$BRIEF_LOG" > "$BRIEF_LOG.tmp" 2>/dev/null \
      && mv "$BRIEF_LOG.tmp" "$BRIEF_LOG"
  }


  # Render speech to a file. Every engine goes through here, so swapping one
  # in changes nothing else. Returns 1 if it produced nothing, and callers
  # fall back to `say` — a briefing you can hear beats silence.
  # A failed neural render falls back to `say`, which is right — a briefing you
  # can hear beats silence — but a SILENT fallback leaves you wondering why it
  # still sounds dated. Every render says which engine actually spoke.
  tts_log() { printf '%s tts: %s\n' "$(date '+%H:%M:%S')" "$1" \
    >> "$HOME/.claude/menubar/listen.log" 2>/dev/null; }

  # Take over the voice from whatever holds it, then own it. Only the recorded
  # pid is killed, so chimes and other sounds are left alone.
  claim_voice() {
    local p
    p=$(cat "$VOICE_PID" 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then kill "$p" 2>/dev/null; fi
    : > "$VOICE_PID" 2>/dev/null
  }
  # Only clear the file if we still own it. Otherwise a briefing that took over
  # after us would be de-registered by our exit and lose its own protection.
  release_voice() {
    local p
    p=$(cat "$VOICE_PID" 2>/dev/null)
    [ -n "${player_pid:-}" ] && [ "$p" = "$player_pid" ] && : > "$VOICE_PID" 2>/dev/null
    return 0
  }

  # Identity of a rendered briefing: the same words through the same engine and
  # voice give the same audio, so it can be reused rather than bought again.
  clip_key() {
    printf '%s|%s|%s|%s' "$TTS_ENGINE" "$TTS_OPENAI_VOICE" "$VOICE" "$1" \
      | md5 -q 2>/dev/null
  }

  # Keep the newest CLIP_KEEP renders and drop the rest, so the cache cannot
  # grow without bound. These are spoken summaries of your work, so they are
  # pruned on the same principle as the transcript logs.
  cache_clip() {   # $1 key  $2 file
    [ -n "$1" ] && [ -s "$2" ] || return 0
    mkdir -p "$CLIP_CACHE" 2>/dev/null || return 0
    cp "$2" "$CLIP_CACHE/$1.tmp" 2>/dev/null && mv "$CLIP_CACHE/$1.tmp" "$CLIP_CACHE/$1"
    ls -1t "$CLIP_CACHE" 2>/dev/null | tail -n +$((CLIP_KEEP + 1)) | while read -r old; do
      rm -f "$CLIP_CACHE/$old" 2>/dev/null
    done
    return 0
  }

  synth_to_file() {   # $1 text  $2 outfile
    # Replaying a briefing rendered minutes ago should not wait on the network
    # for audio that was already paid for. This is what makes replay instant.
    local ck cached
    ck=$(clip_key "$1")
    cached="$CLIP_CACHE/$ck"
    if [ -n "$ck" ] && [ -s "$cached" ]; then
      cp "$cached" "$2" 2>/dev/null && { tts_log "clip cache hit"; return 0; }
    fi
    case "$TTS_ENGINE" in
      openai)
        local key="$OPENAI_API_KEY"
        [ -z "$key" ] && [ -r "$TTS_KEY_FILE" ] && key=$(tr -d '[:space:]' < "$TTS_KEY_FILE")
        [ -n "$key" ] || return 1
        curl -sS --max-time 25 https://api.openai.com/v1/audio/speech \
          -H "Authorization: Bearer $key" \
          -H "Content-Type: application/json" \
          -d "$(jq -n --arg m "$TTS_OPENAI_MODEL" --arg v "$TTS_OPENAI_VOICE" \
                      --arg i "$1" --arg s "$TTS_OPENAI_STYLE" \
                      '{model:$m, voice:$v, input:$i, instructions:$s, response_format:"mp3"}')" \
          -o "$2" 2>/dev/null
        if [ ! -s "$2" ]; then tts_log "openai FAILED (no response) -> say"; return 1; fi
        # an error comes back as JSON, not audio — fall back rather than play it
        if head -c 1 "$2" | grep -q '{'; then
          tts_log "openai FAILED: $(head -c 160 "$2" | tr -d '\n') -> say"
          rm -f "$2"; return 1
        fi
        tts_log "openai/$TTS_OPENAI_VOICE ok ($(wc -c < "$2" | tr -d ' ') bytes)"
        cache_clip "$ck" "$2"; return 0 ;;
      command)
        [ -n "$TTS_CMD" ] || return 1
        "$TTS_CMD" "$1" "$2" >/dev/null 2>&1
        [ -s "$2" ] || return 1
        cache_clip "$ck" "$2"; return 0 ;;
      *)
        say -v "$VOICE" -r "$RATE" -o "$2" "$1" 2>/dev/null
        [ -s "$2" ] || return 1
        tts_log "say/$VOICE ok"
        cache_clip "$ck" "$2"; return 0 ;;
    esac
  }

  # Muted: the briefing is already saved to the replay list above, so there is
  # nothing left to do. Nothing is paused, no microphone opens, no sound plays.
  if is_off; then exit 0; fi

  # ---- pausing whatever is playing --------------------------------------
  # A real pause, not a dip: losing twenty seconds of a podcast to a briefing
  # defeats the point. And still without controlling any app.
  #
  # An earlier version asked Spotify, Music and VLC to pause over AppleScript.
  # That needed a permission prompt per app, could not touch browser audio,
  # and LAUNCHED apps — AppleScript loads an app's dictionary to compile a
  # term, so asking a closed VLC for `player state` (which VLC does not even
  # support) opened it, before any `is running` guard ran.
  PAUSED_BY_KEY=0

  # Is sound genuinely coming out right now? Asked of the system, not of any
  # app. coreaudiod holds this power assertion only while audio is actually
  # playing — and unlike the CoreAudio "device is running somewhere" property,
  # it does NOT report true when an app merely holds the device open. Free,
  # instant, no permission.
  audio_playing() {
    pmset -g assertions 2>/dev/null \
      | grep -qi 'coreaudiod.*output\.context\.preventuseridlesleep'
  }

  tap_playpause() { open -n -g -a "$KEYS_APP" --args playpause 2>/dev/null; }

  # WHICH process is producing the sound? macOS says so directly: the
  # coreaudiod assertion carries "Created for PID". That is the difference
  # between knowing and guessing — and guessing is what opened Apple Music.
  audio_pids() {
    pmset -g assertions 2>/dev/null | awk '
      /coreaudiod/ && /output\.context\.preventuseridlesleep/ { want=1; next }
      want && /Created for PID:/ { p=$0; gsub(/[^0-9]/,"",p); if (p != "") print p; want=0 }'
  }

  # Will the play/pause key actually be caught? Only if the thing making the
  # noise is a real media app. macOS routes that key to whichever app is "now
  # playing"; when nothing claims it, macOS opens your default media app
  # instead — which is how a stray press started Apple Music mid-library.
  # A system alert or a command-line player makes sound while claiming
  # nothing, so "audio is playing" was never sufficient evidence.
  media_key_will_land() {
    local pid path
    for pid in $(audio_pids); do
      path=$(ps -p "$pid" -o args= 2>/dev/null)
      case "$path" in
        *WebKit*|*Safari*|*Chrome*|*Chromium*|*Firefox*|*Arc.app*|*Brave*|\
        *Vivaldi*|*Opera*|*Spotify*|*/Music.app/*|*iTunes*|*VLC*|*IINA*|\
        *Podcasts.app*|*/TV.app/*|*QuickTime*)
          return 0 ;;
      esac
    done
    return 1
  }

  pause_media() {
    [ "$DUCK" = "1" ] || return 0
    audio_playing || return 0        # silent Mac: touch nothing whatsoever

    # The hardware play/pause key is one system-wide event that every media
    # app honours. It TOGGLES, which is why it is only ever sent once we have
    # confirmed audio is really playing — firing it blind would START
    # something you had deliberately stopped.
    if [ -d "$KEYS_APP" ] && media_key_will_land; then
      # Belt and braces: if the key still finds no owner (a browser can be
      # running without being the one playing), macOS launches the default
      # media app. Note what was running first, so anything the press starts
      # can be closed again immediately.
      local had_music=0
      pgrep -xq Music 2>/dev/null && had_music=1

      tap_playpause
      sleep 0.8                      # assertions clear within about a second

      if [ "$had_music" = "0" ] && pgrep -xq Music 2>/dev/null; then
        # We opened it. Close it again — with a plain signal rather than
        # AppleScript, which would itself raise an Automation prompt.
        pkill -x Music 2>/dev/null
      elif ! audio_playing; then
        PAUSED_BY_KEY=1; return 0
      else
        tap_playpause                # it did not take — undo the press
        sleep 0.3
      fi
    fi

    # Whatever ignored the key keeps playing, and the briefing goes over the
    # top of it at its own volume. Harder to hear, and a deliberate trade:
    # nothing of yours gets touched.
  }

  # Runs on EVERY exit path, including being killed mid-briefing.
  RESTORED=0
  restore_media() {
    [ "$RESTORED" = "1" ] && return
    RESTORED=1
    # ALWAYS release the microphone. This runs on every exit path including
    # being killed by the next turn's flow — and without it a barge-in
    # listener outlives the flow that started it and holds the mic open for
    # the rest of its window. Interrupted briefings were stacking up
    # orphaned listeners until the mic looked permanently live.
    pkill -f OvervoiceListen 2>/dev/null
    # And ALWAYS stop this flow's own briefing.
    #
    # Killing the listener without the player left an orphan: when the next
    # turn's flow took the lock, the outgoing flow released the microphone and
    # died while its briefing carried on playing, with nothing left listening.
    # Saying "stop" to that briefing could not work, because the thing that
    # hears "stop" had already been shut down. Observed in the log: listener
    # killed 10s into a 16s briefing, which then played on unstoppable.
    #
    # Signalled rather than killed outright, so it fades instead of being cut.
    [ -n "${player_pid:-}" ] && kill "$player_pid" 2>/dev/null
    # A render started at the gate but never played: answering "no" reaches here
    # with a curl still in flight and a temp file nobody will claim.
    release_voice
    [ -n "$PRESYNTH_PID" ] && kill "$PRESYNTH_PID" 2>/dev/null
    [ -n "$TAILSYNTH_PID" ] && kill "$TAILSYNTH_PID" 2>/dev/null
    [ -n "$PRECLIP" ] && rm -f "$PRECLIP" 2>/dev/null
    [ -n "$TAILCLIP" ] && rm -f "$TAILCLIP" 2>/dev/null
    if [ "$PAUSED_BY_KEY" = "1" ]; then tap_playpause; PAUSED_BY_KEY=0; fi
  }
  # The signal traps MUST exit. Bash runs a trap handler and then RESUMES the
  # script where it left off — it does not exit on its own. With a bare
  # `trap restore_media TERM`, killing a flow released the microphone and then
  # let the flow carry on to open a fresh listener, while RESTORED=1 meant its
  # cleanup could never run a second time. That orphaned listener held the mic
  # open with nothing left alive to close it.
  trap restore_media EXIT
  trap 'restore_media; exit 143' TERM
  trap 'restore_media; exit 130' INT

  # Speak, while listening for "stop". Returns 0 if the sentence finished, 1 if
  # it was interrupted. Falls back to a plain, uninterruptible `say` when
  # barge-in is off or the listener is missing, so speech never depends on the
  # microphone working.
  INTERRUPTED=0
  speak_interruptible() {
    is_off && return 0
    local text="$1"
    local clip="" player_pid=""

    # Rendered to a file when a non-default engine is in use, or when
    # something is still audible underneath and we need playback gain —
    # `say` has no volume of its own.
    # Claim the render started back at the gate, if this is the text it was
    # started for. `wait` returns at once when it has already finished, which is
    # the normal case, and otherwise blocks for the remainder only.
    if [ -n "$PRECLIP" ] && [ "$text" = "$PRECLIP_TEXT" ]; then
      [ -n "$PRESYNTH_PID" ] && wait "$PRESYNTH_PID" 2>/dev/null
      [ -s "$PRECLIP" ] && clip="$PRECLIP"
      # The answer was yes, so buy the rest now. It renders while the opening
      # plays, and the player waits for it if it is not ready in time.
      if [ -n "$clip" ] && [ -n "$TAIL_TEXT" ]; then
        ( synth_to_file "$TAIL_TEXT" "$TAILCLIP" || rm -f "$TAILCLIP" ) &
        TAILSYNTH_PID=$!
      else
        TAILCLIP=""
      fi
      PRECLIP=""; PRESYNTH_PID=""    # consumed; later calls render their own
    elif [ "$TTS_ENGINE" != "say" ]; then
      clip="$(mktemp).audio"
      synth_to_file "$text" "$clip" || clip=""
    fi

    # Generated once, by macOS itself, so this needs nothing installed.

    start_speech() {
      # Nothing used to coordinate a live briefing with a replay from the menu,
      # so replaying while a briefing was speaking left two voices talking over
      # each other. They are separate processes, so the handover goes through a
      # file naming whichever process currently owns the voice.
      #
      # It kills that one pid rather than running `killall afplay`: a blanket
      # kill also takes out the acknowledgement chime, and worse, it made the
      # flow believe its own briefing had ended and move on to the reply window.
      claim_voice
      # Claim it provisionally under this flow's own pid, BEFORE the lead-in.
      # claim_voice empties the file, and the lead-in then plays for 0.4s during
      # which the file says nobody owns the voice: a briefing starting in that
      # window killed nothing and both went on to speak at once. Anything that
      # takes over now kills this flow instead, which is the right outcome.
      printf '%s' "$$" > "$VOICE_PID" 2>/dev/null
      # No lead-in here any more: the player warms the output route from inside
      # its own audio engine, which is the path actually about to be used. Doing
      # it out here with afplay warmed a route the engine then reacquired.
      if [ -n "$clip" ] && [ -s "$clip" ]; then
        # gain only matters when talking over something that was dipped
        if [ -x "$PLAYER" ]; then
          OVERVOICE_GAIN="$PLAY_GAIN" \
            "$PLAYER" "$FADE_SECONDS" "$clip" ${TAILCLIP:+"$TAILCLIP"} &
        else afplay "$clip" & fi
      else
        say -v "$VOICE" -r "$RATE" "$text" &
      fi
      player_pid=$!
      printf '%s' "$player_pid" > "$VOICE_PID" 2>/dev/null
    }

    if [ "$BARGE_IN" != "1" ] || [ ! -x "$LISTENER" ]; then
      start_speech
      wait "$player_pid" 2>/dev/null
      release_voice
      [ -n "$clip" ] && rm -f "$clip"
      return 0
    fi

    pkill -f OvervoiceListen 2>/dev/null
    local bfile; bfile=$(mktemp)
    # A generous window: the listener is bounded by the speech, not the clock.
    # Bounded to a ceiling rather than an open-ended window: normal
    # completion kills it immediately, this only caps the damage if that
    # never happens.
    # Keep the microphone open for exactly as long as the briefing lasts, not a
    # fixed window. A full-output briefing runs well past two minutes, so a flat
    # 75s meant the microphone closed partway through and "stop" stopped working
    # for precisely the long briefings most worth stopping.
    #
    # The clip's own duration is the only correct answer, and the file is right
    # here. The margin covers listener startup and the fade. BARGE_MAX_SECONDS
    # remains the fallback for when the duration cannot be read, and for `say`,
    # which speaks without producing a file at all.
    # Sized from the WORD COUNT, not the clip. The clip on disk is only the
    # opening now, so measuring it closed the microphone a few seconds in. The
    # rate comes from real briefings: 340 words came out as 139 seconds, so
    # about 2.4 words a second.
    BARGE_WINDOW="$BARGE_MAX_SECONDS"
    SPOKEN_WORDS=$(printf '%s' "$text" | wc -w | tr -d ' ')
    if [ "${SPOKEN_WORDS:-0}" -gt 0 ]; then
      BARGE_WINDOW=$(awk -v w="$SPOKEN_WORDS" 'BEGIN{printf "%d", w / 2.4 + 12}')
    fi
    slog "barge: window ${BARGE_WINDOW}s for ${SPOKEN_WORDS} words"
    open -n -g -a "$LISTENER_APP" --args "$BARGE_WINDOW" "$bfile" bargein \
      "$BARGE_WORDS" "$BARGE_LEVEL" 2>/dev/null
    start_speech
    while kill -0 "$player_pid" 2>/dev/null; do
      # switched off mid-sentence: go quiet at once
      if is_off; then
        kill "$player_pid" 2>/dev/null
        release_voice
        killall say afplay 2>/dev/null
        pkill -f OvervoiceListen 2>/dev/null
        rm -f "$bfile"; [ -n "$clip" ] && rm -f "$clip"
        INTERRUPTED=1
        return 1
      fi
      # "timeout" is also non-empty, so match the word rather than the file
      if [ "$(tr -d '[:space:]' < "$bfile" 2>/dev/null)" = "stop" ]; then
        # The listener already logs that it HEARD stop. Without this there is no
        # way to tell whether the shell ever read it, which is the difference
        # between a recognition problem and a plumbing one.
        slog "barge: shell acted on stop"
        kill "$player_pid" 2>/dev/null
        release_voice
        # No killall here: that would cut the fade off at the knees. The
        # signal above starts the ramp and the player exits on its own.
        pkill -f OvervoiceListen 2>/dev/null
        rm -f "$bfile"; [ -n "$clip" ] && rm -f "$clip"
        INTERRUPTED=1
        return 1
      fi
      sleep 0.2
    done
    wait "$player_pid" 2>/dev/null
    release_voice
    pkill -f OvervoiceListen 2>/dev/null
    rm -f "$bfile"; [ -n "$clip" ] && rm -f "$clip"
    return 0
  }

  pause_media

  # Start rendering the audio NOW, in parallel with the chime and the gate.
  # A neural engine needs a network round trip, and rendering only after the
  # answer put that entire delay between "yes" and the first word. By the time
  # anyone can say yes, the chime has played and the listener has warmed up, so
  # the render is usually finished before it is wanted and the briefing starts
  # instantly. Nothing here is wasted if the answer turns out to be no: it costs
  # one render of text that was going to be rendered anyway.
  PRECLIP=""; PRESYNTH_PID=""; PRECLIP_TEXT=""
  TAILCLIP=""; TAIL_TEXT=""; TAILSYNTH_PID=""
  if ! is_off && [ "$TTS_ENGINE" != "say" ]; then
    PRECLIP_TEXT="$ANNOUNCE$SPEAK"
    # Only the opening is bought now. The rest is bought when the answer is yes,
    # which is the difference between paying per finished turn and paying per
    # briefing actually listened to. Measured: 88 renders, 13 of them heard.
    HEAD_TEXT=$(split_head "$PRECLIP_TEXT" "$SPLIT_WORDS")
    TAIL_TEXT=${PRECLIP_TEXT#"$HEAD_TEXT"}
    PRECLIP="$(mktemp).audio"
    TAILCLIP="$(mktemp).audio"
    ( synth_to_file "$HEAD_TEXT" "$PRECLIP" || rm -f "$PRECLIP" ) &
    PRESYNTH_PID=$!
  fi

  # ---- the gate: chime, then listen for a spoken yes/no -----------------
  # Runs AFTER the briefing text exists, so a "yes" plays it immediately.
  if [ "$GATE" = "1" ] && [ -x "$LISTENER" ] && ! is_off; then
    # A listener left over from a previous turn keeps hold of the microphone,
    # and the next one then silently never starts — no log, no verdict, looks
    # exactly like a permissions failure. Always clear stragglers first.
    pkill -f OvervoiceListen 2>/dev/null

    # Wait for the audio BEFORE opening the microphone. Order matters more than
    # it looks: the listener runs on a fixed window, so waiting here with the
    # microphone already live spent that window on the render and the gate timed
    # out before the chime had even played. The briefing was then never spoken,
    # every time a render ran long.
    #
    # Holding the chime until the audio is ready is still right: it arrives a
    # moment later, which nobody is timing, and silence after saying yes is
    # glaring by comparison. Bounded, so a hung render means a late chime rather
    # than none.
    if [ -n "$PRESYNTH_PID" ]; then
      WAITED=0
      # 90 half-seconds. Over 15 real renders: mean 18.4s, median 19.5s, and
      # several pinned at exactly the old 20s ceiling, meaning they were cut off
      # and the chime rang over an unfinished render. Full briefings average 361
      # words, so the ceiling has to clear that comfortably.
      while kill -0 "$PRESYNTH_PID" 2>/dev/null && [ "$WAITED" -lt 90 ]; do
        sleep 0.5; WAITED=$((WAITED + 1))
      done
      slog "render: ready after $(awk -v w="$WAITED" 'BEGIN{printf "%.1f", w/2}')s"
    fi

    # Now start the microphone, one second before the chime. On Bluetooth it
    # needs about that long to switch profiles, and that dead zone used to land
    # exactly where you answer. The chime covers the warm-up.
    # Launch via LaunchServices: exec'ing the binary directly gets it killed
    # by TCC, which blames the parent process for the missing usage string.
    VFILE=$(mktemp)
    open -n -g -a "$LISTENER_APP" --args "$LISTEN_SECONDS" "$VFILE" 2>/dev/null
    sleep 1.0
    log_briefing        # raises the notification, so it lands with the chime
    play_chime
    TRIES=$(( (LISTEN_SECONDS + 8) * 10 ))
    while [ "$TRIES" -gt 0 ] && [ ! -s "$VFILE" ]; do
      is_off && { pkill -f OvervoiceListen 2>/dev/null; rm -f "$VFILE"; exit 0; }
      # 0.1s, not 0.5s. This sits directly between the answer and the briefing,
      # so the granularity IS lag: half a second of it, every time.
      sleep 0.1; TRIES=$((TRIES - 1))
    done
    VERDICT=$(tr -d '[:space:]' < "$VFILE" 2>/dev/null)
    rm -f "$VFILE"

    # An answer that arrived too quietly was not you — most likely a briefing
    # playing through the speakers, including one from another session.
    if [ -n "$VERDICT" ] && too_quiet_to_be_you; then
      echo "gate: ignoring '$VERDICT' at $(last_heard_level) — below $GATE_MIN_LEVEL" \
        >> "$HOME/.claude/menubar/listen.log"
      VERDICT="timeout"
    fi

    case "$VERDICT" in
      yes)
        afplay -v "$ACK_VOL" "/System/Library/Sounds/$ACK_SOUND.aiff" 2>/dev/null & ;;
      no)
        # A spoken no should take the notification with it: declined is dealt
        # with, and a notification for a briefing you just refused is clutter.
        # Only the menu bar app can withdraw what it posted, so leave it a
        # marker carrying this briefing's exact text; it removes only matching
        # notifications, so another session's unread one survives. A TIMEOUT
        # deliberately does not do this: unanswered means catch up later, and
        # the notification is how.
        printf '%s' "$SPEAK" | tr '\t\n' '  ' \
          > "$HOME/.claude/menubar/dismiss-notification" 2>/dev/null
        exit 0 ;;
      denied*|unavailable)
        # Mic or speech permission missing. Fail OPEN rather than going
        # permanently silent — an unasked-for briefing beats a feature that
        # quietly does nothing forever.
        ;;
      *)   exit 0 ;;                                    # timeout = no
    esac
  fi

  # With the gate on, the chime already played as the prompt to answer, so
  # don't ring it twice. Without the gate it goes here, immediately before the
  # voice, so there's no dead air between tone and speech.
  if [ "$GATE" != "1" ]; then
    log_briefing
    [ "$MODE" = "chime+speak" ] && play_chime
  fi

  # Interrupting the briefing means "be quiet" — so do not then open a reply
  # window and ask for more talking.
  if ! speak_interruptible "$ANNOUNCE$SPEAK"; then
    restore_media
    exit 0
  fi

  # ---- reply stage: a second, different chime means "your turn" ----------
  # Only ever runs with Claude frontmost. Typing blind into whatever happens to
  # hold focus could dump a stray transcript into any open document.
  if [ "$REPLY_STAGE" = "1" ] && [ -x "$LISTENER" ] && ! is_off; then
    FRONT=$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null)
    case "$FRONT" in
      *"$FRONT_MATCH"*)
        pkill -f OvervoiceListen 2>/dev/null

        # Mic first, chime second — same Bluetooth warm-up reason as the gate.
        RFILE=$(mktemp)
        open -n -g -a "$LISTENER_APP" --args "$REPLY_SECONDS" "$RFILE" transcribe "$SILENCE_GAP" "$EARLY_WORDS" 2>/dev/null
        sleep 1.0
        play_chime
        # Must cover the listener's HARD CAP, not the nominal window. Waiting
        # only (window + 8) meant the hook gave up at 17s while the listener
        # ran to 35 — the reply was captured and then silently discarded.
        # Mirrors the listener's own formula, so the two cannot drift apart.
        HARD_CAP=$(( REPLY_SECONDS * 2 ))
        [ "$HARD_CAP" -lt 15 ] && HARD_CAP=15
        TRIES=$(( (HARD_CAP + 10) * 2 ))
        # Stop as soon as the listener is GONE, not only once it has written
        # something. Saying nothing produces an empty transcript, so the file
        # stays at zero bytes and a content-only test never fires: the flow then
        # sat here long after the microphone had closed, holding the media paused
        # for the whole cap every time there was nothing to say, which is the
        # common case.
        while [ "$TRIES" -gt 0 ] && [ ! -s "$RFILE" ]; do
          pgrep -f OvervoiceListen >/dev/null 2>&1 || break
          sleep 0.5; TRIES=$((TRIES - 1))
        done
        REPLY_TEXT=$(cat "$RFILE" 2>/dev/null)
        rm -f "$RFILE"

        # The prompt instructs the summariser to END with the question, so the
        # tail is the part being answered. Sending the whole briefing back would
        # bury the actual reply.
        ASKED=$(tail -c 240 "$BRIEF_FILE" 2>/dev/null | tr '\n' ' ' | to_ascii)
        CONTEXT=""
        [ -n "$ASKED" ] && CONTEXT="  (spoken reply - the briefing I heard ended: \"...$ASKED\")"

        # Same guard: a leaked "go ahead" here would be typed into Claude and
        # sent, which is worse than a spurious briefing.
        if [ -n "$REPLY_TEXT" ] && too_quiet_to_be_you; then
          echo "reply: ignoring '$REPLY_TEXT' at $(last_heard_level) — below $GATE_MIN_LEVEL" \
            >> "$HOME/.claude/menubar/listen.log"
          REPLY_TEXT=""
        fi

        REPLY_TEXT=$(printf '%s' "$REPLY_TEXT" | to_ascii)
        # The recogniser likes to append punctuation ("Stop.", "Go ahead.").
        # Match without it, or single-word commands fall through and vanish.
        LOWER=$(printf '%s' "$REPLY_TEXT" | tr '[:upper:]' '[:lower:]'                 | sed -E 's/[.,!?]+$//; s/[[:space:]]+$//')
        WORDS=$(printf '%s' "$REPLY_TEXT" | wc -w | tr -d ' ')
        case "$LOWER" in
          "")
            : ;;                                    # silence — say nothing, do nothing
          *reply*|*dictate*|*"let me talk"*|*"let me speak"*)
            if [ "$WORDS" -gt 3 ]; then
              # A long sentence that merely CONTAINS "reply" is an answer,
              # not the handover command. Re-route it to the normal path.
              # Interrupting the read-back is itself a cancel — it is the most
            # natural way to stop something you did not mean to send.
            if ! speak_interruptible "Sending: $(printf '%s' "$REPLY_TEXT" | cut -c1-140)"; then
              say -v "$VOICE" -r "$RATE" "Cancelled."
              restore_media
              exit 0
            fi
              afplay -v "$ACK_VOL" "/System/Library/Sounds/$ACK_SOUND.aiff" 2>/dev/null &
              open -n -g -a "$KEYS_APP" --args send "$REPLY_TEXT$CONTEXT" 2>/dev/null
              restore_media
              exit 0
            fi
            # Two quick ticks = "handing over to Wispr", distinct from the
            # single tick that acknowledges a yes.
            # No acknowledgement tone here on purpose. Wispr plays its own
            # chime when it opens, and that one is more honest: ours fires when
            # the handover is REQUESTED, Wispr's when it is actually ready to
            # listen. Two sounds a moment apart just invites you to start
            # talking on the wrong one.
            open -n -g -a "$KEYS_APP" --args fn2 2>/dev/null

            # Hands-free close. macOS lets two processes hold the microphone at
            # once (verified: our listener transcribed a whole Wispr dictation
            # while Wispr was recording it), so we can watch for you to stop
            # talking and tap Globe for you. End the dictation with the words
            # "press enter" and Wispr sends it once we close it.
            if [ "$WISPR_AUTOSTOP" = "1" ]; then
              sleep 1.5                       # let Wispr actually open
              WFILE=$(mktemp)
              open -n -g -a "$LISTENER_APP" --args "$WISPR_SECONDS" "$WFILE" \
                transcribe "$WISPR_SILENCE" "" "$WISPR_END_PHRASE" 2>/dev/null
              WT=$(( (WISPR_SECONDS * 3 + 15) * 2 ))
              while [ "$WT" -gt 0 ] && [ ! -s "$WFILE" ]; do sleep 0.5; WT=$((WT - 1)); done
              HEARD=$(cat "$WFILE" 2>/dev/null)
              rm -f "$WFILE"
              # Only close it if you actually said something. Tapping Globe
              # after silence would just toggle a fresh dictation open.
              if [ -n "$HEARD" ]; then
                open -n -g -a "$KEYS_APP" --args fn1 2>/dev/null
              fi
            fi ;;
          # Unambiguous commands go straight through — reading "yes" back to
          # you would be slower and more irritating than the risk it removes.
          # Dismiss: shuts the microphone at once and sends nothing. Without
          # this you have to sit out the whole window in silence — which means
          # not talking to anyone else in the room either, in case it gets
          # taken as an answer.
          ok|okay|okey|thanks|"thank you"|"that's all"|"thats all"|"all good"|nothing|nevermind)
            afplay -v "$ACK_VOL" "/System/Library/Sounds/$ACK_SOUND.aiff" 2>/dev/null
            restore_media
            exit 0 ;;

          yes|yeah|yep|yup|sure|"go ahead"|"go for it"|"do it"|\
          no|nope|nah|"not now"|stop|wait|\
          continue|"carry on"|"keep going"|"try again"|"commit it"|push)
            afplay -v "$ACK_VOL" "/System/Library/Sounds/$ACK_SOUND.aiff" 2>/dev/null &
            open -n -g -a "$KEYS_APP" --args send "$REPLY_TEXT$CONTEXT" 2>/dev/null ;;

          *)
            # A single stray word that is not a known command is almost never
            # aimed at Claude - it is a mutter, a cough, or something said to
            # the room. Drop it silently. The readback cannot save you here:
            # blurting happens exactly when your attention is elsewhere.
            if [ "$WORDS" -lt 2 ]; then
              exit 0
            fi

            # Short and unambiguous — send it, no read-back.
            if [ "$WORDS" -lt "$READBACK_MIN_WORDS" ]; then
              afplay -v "$ACK_VOL" "/System/Library/Sounds/$ACK_SOUND.aiff" 2>/dev/null &
              open -n -g -a "$KEYS_APP" --args send "$REPLY_TEXT$CONTEXT" 2>/dev/null
              exit 0
            fi

            # Anything longer gets read back, then a short window to cancel.
            # Still hands-free: silence means send. Nothing is typed until
            # confirmed, so cancelling leaves no half-written text behind.
            # Interrupting the read-back is itself a cancel — it is the most
            # natural way to stop something you did not mean to send.
            if ! speak_interruptible "Sending: $(printf '%s' "$REPLY_TEXT" | cut -c1-140)"; then
              say -v "$VOICE" -r "$RATE" "Cancelled."
              restore_media
              exit 0
            fi

            pkill -f OvervoiceListen 2>/dev/null
            CFILE=$(mktemp)
            # Warm-up again: opening the mic straight after Ava speaks caught
            # the AirPods mid profile-switch and the window recorded nothing at
            # all (peak 0.0001), so "say stop" silently could not work.
            open -n -g -a "$LISTENER_APP" --args "$CONFIRM_SECONDS" "$CFILE" 2>/dev/null
            sleep 0.9
            play_chime
            CTRIES=$(( (CONFIRM_SECONDS + 8) * 2 ))
            while [ "$CTRIES" -gt 0 ] && [ ! -s "$CFILE" ]; do sleep 0.5; CTRIES=$((CTRIES - 1)); done
            CONFIRM=$(tr -d '[:space:]' < "$CFILE" 2>/dev/null)
            rm -f "$CFILE"

            # The gate's own classifier already treats "no", "stop", "cancel"
            # and "nope" as a no — exactly the vocabulary wanted here.
            SEND_IT=1
            [ "$CONFIRM" = "no" ] && SEND_IT=0
            [ "$CONFIRM_SILENT_SENDS" = "0" ] && [ "$CONFIRM" != "yes" ] && SEND_IT=0
            if [ "$SEND_IT" = "0" ]; then
              # No tone. The spoken "Cancelled." already says it, and a chime in
              # front of it carries nothing the word does not.
              say -v "$VOICE" -r "$RATE" "Cancelled."
            else
              afplay -v "$ACK_VOL" "/System/Library/Sounds/$ACK_SOUND.aiff" 2>/dev/null &
              open -n -g -a "$KEYS_APP" --args send "$REPLY_TEXT$CONTEXT" 2>/dev/null
            fi ;;
        esac ;;
    esac
  fi

  restore_media
  exit 0
fi

# ---- stage 1: the hook itself, must return fast -------------------------
INPUT=$(cat)

# Claude Code sets this when a Stop hook has already run for this turn.
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')
[ -f "$TRANSCRIPT" ] || exit 0

# Keep the diagnostic logs from growing forever — they hold speech transcripts,
# so bounding them is privacy hygiene as much as disk hygiene.
for LOG in "$HOME/.claude/menubar/listen.log" "$HOME/.claude/menubar/debug.log"; do
  if [ -f "$LOG" ] && [ "$(stat -f %z "$LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
    tail -c 65536 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
  fi
done

# The API call plus the speech take several seconds. Hand them to a detached
# copy of this script so the terminal isn't blocked waiting to talk.
nohup "$0" --speak "$TRANSCRIPT" >/dev/null 2>&1 &

exit 0
