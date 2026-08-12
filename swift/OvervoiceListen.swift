// Listens for a spoken yes/no, writes the verdict to a file, then exits.
//
//   OvervoiceListen <seconds> <verdict-file>
//        -> yes | no | timeout | denied-speech | denied-mic | unavailable
//
// Recognition is forced on-device: nothing leaves the machine and it works with
// no network.
//
// Two hard-won constraints, both of which caused silent failures:
//
//  1. Launch it with `open -a`, never by exec'ing the binary. Spawned from a
//     shell, TCC holds the PARENT process responsible and kills this one for
//     having no usage description, whatever its own Info.plist says.
//  2. Never block the main thread waiting for permission. The authorisation
//     dialog is drawn on the main run loop, so a semaphore wait there
//     deadlocks: no dialog appears, the callback never fires, and it looks
//     exactly like the user denied it.

import Foundation
import AVFoundation
import Speech

let seconds = CommandLine.arguments.count > 1
    ? (Double(CommandLine.arguments[1]) ?? 6.0) : 6.0
let outPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

// "transcribe" returns whatever was said, for the reply stage. Default is the
// gate: classify to yes/no and stop the instant either is heard.
let transcribeMode = CommandLine.arguments.count > 3
    && CommandLine.arguments[3] == "transcribe"
var latestTranscript = ""
var finishedSegments: [String] = []   // recogniser restarts mid-speech; keep them all

func fullText() -> String {
    (finishedSegments + [latestTranscript])
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

// Seconds of quiet after you stop talking before the reply is accepted.
// Tunable as the 5th argument so tweaking it never needs a rebuild — a rebuild
// costs the user re-granting microphone and speech permissions.
let silenceGap = CommandLine.arguments.count > 4
    ? (Double(CommandLine.arguments[4]) ?? 1.5) : 1.5
var lastHeardAt = ProcessInfo.processInfo.systemUptime

// Words that end the window the instant they are heard, instead of waiting out
// the silence gap. "reply" is a handover command, not a sentence — making the
// user sit through 2.5s of silence before Wispr opens is pure dead time.
// Comma-separated 6th argument, so the list is tunable without a rebuild.
// Ends the window the moment the transcript ENDS with this phrase. Far better
// than guessing from silence: "press enter" is the user's own deliberate signal
// that they have finished, so a long thinking pause can never close it early.
let endPhrase = CommandLine.arguments.count > 6
    ? CommandLine.arguments[6].lowercased() : ""
var listeningStarted = false

// ---- barge-in ------------------------------------------------------------
// "stop" spoken WHILE something is being read aloud.
//
// Echo used to be the hard part: the microphone hears the briefing too, and a
// briefing whose own text contained "stop" would cut itself off. That is now
// handled at the source, by stripping those words from the briefing before it
// is ever spoken, so the microphone can only hear one from the room.
//
// `bargeLevel` is therefore a backstop against the recogniser MISHEARING
// briefing audio as a stop word, not the primary defence, and is set low
// accordingly. It was previously high enough to reject a real "stop" measured
// at 0.028. Every near-miss is logged with its level (see `voice bargein`).
let bargeInMode = CommandLine.arguments.count > 3
    && CommandLine.arguments[3] == "bargein"
let bargeWords: [String] = CommandLine.arguments.count > 4
    && !CommandLine.arguments[4].isEmpty
    ? CommandLine.arguments[4].lowercased().split(separator: ",").map(String.init)
    : ["stop", "quiet", "cancel", "enough"]
let bargeLevel: Float = CommandLine.arguments.count > 5
    ? (Float(CommandLine.arguments[5]) ?? 0.12) : 0.12

let earlyExit: [String] = CommandLine.arguments.count > 5
    ? CommandLine.arguments[5].lowercased().split(separator: ",").map(String.init)
    : []

// Whole-word matching: "no" must not fire on "now", "know" or "nothing", which
// is exactly what a naive substring check would do.
// Only words nobody starts a dictation to ANOTHER session with. "ok", "okay",
// "please", "sure" and "go" were all yes-words once, and ordinary speech tripped
// them: a briefing played off the word "please" in the middle of a sentence
// addressed to a different session entirely.
let yesWords: Set<String> = ["yes", "yeah", "yep", "yup"]
let noWords: Set<String> = ["no", "nope", "nah", "later", "skip", "stop",
                            "quiet", "cancel", "nevermind"]
let yesPhrases = ["go ahead", "tell me", "let's hear", "lets hear",
                  "hit me", "carry on", "go on", "play it"]
let noPhrases = ["not now", "no thanks", "no thank you", "never mind", "shut up",
                 "leave it", "another time"]

let logPath = NSHomeDirectory() + "/.claude/menubar/listen.log"
func llog(_ m: String) {
    let line = "\(Date()) \(m)\n"
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    } else { try? line.write(toFile: logPath, atomically: true, encoding: .utf8) }
}

let engine = AVAudioEngine()
var peakLevel: Float = 0
var runningPeak: Float = 0        // max since the last check, then reset
// Barge-in judges loudness over a window rather than an instant, because the
// recogniser reports a word well after the sound that produced it.
// 16 buckets at one 0.25s tick each is 4 seconds. Was 2s, which assumed the
// recogniser reports a word within about 1.5s of the sound. Measured against a
// real rejection: a "stop" arrived with recentMax=0.028 while the same session
// was reaching 0.093, meaning the loudness that produced the word had already
// aged out of the window before the word was examined.
let levelWindowSize = 16
var levelWindow: [Float] = []
var recentMax: Float = 0
var lastBargeHeard = ""   // throttles the barge-in log to actual changes
var lastBargeHit = ""     // so one spoken word cannot fire on every partial result
func earlyOrBarge(_ w: String) -> Bool { bargeWords.contains(w) }
let speechLevel: Float = 0.02     // silence sits near 0.005, speech near 0.15
var finished = false
let lock = NSLock()

func finish(_ verdict: String) {
    lock.lock()
    if finished { lock.unlock(); return }
    finished = true
    lock.unlock()
    if engine.isRunning {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }
    // Peak input level distinguishes "heard nothing because you were silent"
    // from "heard nothing because no audio ever arrived" — otherwise both look
    // identical and send you hunting in the wrong place.
    llog("verdict=\(verdict) peakInputLevel=\(String(format: "%.4f", peakLevel))")
    if !outPath.isEmpty {
        try? verdict.write(toFile: outPath, atomically: true, encoding: .utf8)
    }
    print(verdict)
    exit(0)
}

func classify(_ text: String) -> String? {
    // The answer must START the utterance. Matching anywhere meant any speech
    // in range of the microphone could answer the gate: dictation to another
    // session, another person in the room, a video. An answer addressed to
    // Overvoice is the first thing said, not a word buried mid-sentence.
    //
    // The transcript accumulates from microphone-open, so someone already
    // mid-sentence at the chime never matches. That is correct: they are
    // talking to someone else, and the briefing stays in the replay list.
    let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    for p in noPhrases where t.hasPrefix(p) { return "no" }
    for p in yesPhrases where t.hasPrefix(p) { return "yes" }
    let first = t.split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
    if noWords.contains(first) { return "no" }
    if yesWords.contains(first) { return "yes" }
    return nil
}

func startListening() {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
          recognizer.isAvailable else { finish("unavailable"); return }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true   // decide the moment a word lands
    if recognizer.supportsOnDeviceRecognition {
        request.requiresOnDeviceRecognition = true
    }

    llog("onDevice=\(recognizer.supportsOnDeviceRecognition) available=\(recognizer.isAvailable)")
    let task = recognizer.recognitionTask(with: request) { result, error in
        if let r = result {
            let heard = r.bestTranscription.formattedString

            if bargeInMode {
                let w = heard.lowercased()
                    .split(whereSeparator: { !$0.isLetter }).map(String.init)
                // Match anywhere in the transcript, not just at the end.
                //
                // The tail rules kept failing for a structural reason: while a
                // briefing plays, the recogniser transcribes the briefing too,
                // so an interruption stops being the last word almost as soon
                // as it lands and never gets examined.
                //
                // Those rules existed to stop a briefing interrupting itself by
                // reading the word "stop" aloud. That cannot happen any more:
                // the words are stripped out of the briefing text before it is
                // ever spoken, so anything the microphone hears one of came
                // from the room, not the speaker.
                //
                // Only ever fires once per word: without that, a match sitting
                // in the transcript would re-fire on every partial result.
                if let hit = w.first(where: { earlyOrBarge($0) }), hit != lastBargeHit {
                    lastBargeHit = hit
                    llog(String(format: "barge candidate '%@' recentMax=%.3f threshold=%.3f",
                                hit, recentMax, bargeLevel))
                    if recentMax > bargeLevel { finish("stop") }
                    else { llog("barge REJECTED as too quiet") }
                }
                if heard != lastBargeHeard {
                    lastBargeHeard = heard
                    llog(String(format: "barge hears: %@ | recentMax=%.3f threshold=%.3f",
                                String(heard.suffix(60)), recentMax, bargeLevel))
                }
                return
            }

            if !heard.isEmpty {
                llog("heard: \(heard)")
                // Keep the LONGEST transcript, not the most recent. Partial
                // results grow as you speak, so the longest is the most
                // complete — and the recogniser sometimes revises a correct
                // sentence into a shorter, wrong one after you stop talking.
                // The recogniser sometimes ends one segment and starts another
                // mid-sentence. A restart arrives as a very short string after a
                // long one — keep the old segment instead of discarding it,
                // which used to lose everything said after the restart.
                if latestTranscript.count > 20 && heard.count * 3 < latestTranscript.count {
                    finishedSegments.append(latestTranscript)
                    latestTranscript = heard
                    lastHeardAt = ProcessInfo.processInfo.systemUptime
                } else if heard.count > latestTranscript.count {
                    latestTranscript = heard
                    lastHeardAt = ProcessInfo.processInfo.systemUptime
                }
            }
            // A bare command word can be acted on at once. Only when it is
            // effectively the WHOLE utterance — saying "reply" inside a longer
            // sentence must not cut that sentence off.
            if transcribeMode && !endPhrase.isEmpty {
                let t = fullText().lowercased()
                    .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
                if t.hasSuffix(endPhrase) {
                    llog("end phrase heard - closing")
                    finish(fullText())
                }
            }

            if transcribeMode && !earlyExit.isEmpty {
                let t = fullText().lowercased()
                let w = t.split(whereSeparator: { !$0.isLetter }).map(String.init)
                // Fire when the transcript ENDS with a command word, rather than
                // when the whole transcript is one. The old rule needed two
                // words or fewer in total, so anything picked up first, a
                // passing remark or another room, permanently blocked "ok" from
                // dismissing: observed in testing with a transcript full of
                // unrelated speech.
                //
                // Ending-with is also gentler about someone who is still
                // talking. "Okay so I want" does not end on a command word and
                // keeps listening, where the old rule cut them off at "okay so".
                //
                // Safe to be liberal here: this only stops LISTENING sooner. The
                // hook still classifies the words and decides what to do, so a
                // sentence that happens to end in "ok" is read back like any
                // other reply rather than being treated as a dismissal.
                if let last = w.last, earlyExit.contains(last) {
                    llog("early exit on trailing command word: \(last)")
                    finish(fullText())
                }
            }

            // Otherwise transcribe mode keeps listening to the end of the
            // window — stopping at the first word would truncate the sentence.
            if !transcribeMode, let verdict = classify(heard) { finish(verdict) }
        }
        if let e = error {
            llog("recognition error: \(e.localizedDescription)")
            finish("timeout")
        }
    }
    _ = task

    let input = engine.inputNode

    // No voice processing here. Apple's echo canceller removed the briefing
    // from the microphone beautifully (peak 0.45 down to 0.009) but its output
    // was unintelligible to the speech recogniser: a live test showed voice
    // arriving at the tap (peak 0.0678) and a completely empty transcript. A
    // canceller that also cancels the person is worse than no canceller.
    //
    // Echo is instead handled at the SOURCE: the stop words are stripped from
    // briefing text before synthesis, so a briefing can never speak one. On
    // headphones, the normal use, the briefing never reaches the microphone at
    // all. On speakers a long briefing can still saturate the recogniser and
    // drown an interruption, and the menu's Stop button is the reliable path
    // there.
    let format = input.outputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
        request.append(buffer)
        if let ch = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = (sum / Float(max(n, 1))).squareRoot()
            if rms > peakLevel { peakLevel = rms }
            if rms > runningPeak { runningPeak = rms }
        }
    }
    listeningStarted = true
    engine.prepare()
    do { try engine.start() } catch { llog("engine failed: \(error)"); finish("unavailable"); return }
    let devName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown"
    llog("listening; input=\(devName) \(format.sampleRate)Hz \(format.channelCount)ch")

    // Timing, all decided here rather than by a fixed timer:
    //
    //  * Nothing said at all      -> give up after `seconds`.
    //  * You are still talking    -> keep going, up to a generous hard cap.
    //  * You have clearly stopped -> accept shortly after.
    //
    // "Stopped" means BOTH no new words AND the microphone has gone quiet.
    // Words alone were not enough: the recogniser stalls mid-sentence, which
    // looked exactly like finishing and cut the user off. A fixed window was not
    // enough either — it expired while he was still speaking.
    let startedAt = ProcessInfo.processInfo.systemUptime
    // Once anything at all has been recognised, this is the ceiling. The old
    // floor of 35s was the real reason the microphone felt like it hung around:
    // one cough or a bit of room noise counts as "heard something", and then it
    // sat there for half a minute. A reply you keep talking through still gets
    // 15s, and the silence gap ends it 2.5s after you actually stop.
    let hardCap = max(15.0, seconds * 2)

    func tick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if finished { return }
            let now = ProcessInfo.processInfo.systemUptime

            // Audible sound counts as still-speaking even when no new words
            // have been recognised.
            let lvl = runningPeak
            // Barge-in used to decay this by 0.6 per 0.25s tick so a late match
            // could still see the loudness that caused it. That decays far too
            // fast: recognition lags the audio by roughly 0.5 to 1.5s, by which
            // point an 0.05 utterance has fallen to 0.011 or below and the
            // threshold rejects it. "Stop" was being heard and then discarded.
            // Keep a rolling window of recent buckets instead and test against
            // the loudest moment in it, which is the real question: was there
            // loud speech shortly before this word was recognised.
            if bargeInMode {
                levelWindow.append(lvl)
                if levelWindow.count > levelWindowSize { levelWindow.removeFirst() }
                recentMax = levelWindow.max() ?? 0
            }
            runningPeak = 0
            if lvl > speechLevel { lastHeardAt = now }

            if bargeInMode {
                if now - startedAt > seconds {
                    llog("barge-in window ended, nothing said")
                    finish("timeout")
                    return
                }
                tick()
                return
            }

            if fullText().isEmpty {
                if now - startedAt > seconds {
                    llog("nothing heard in \(seconds)s")
                    finish(transcribeMode ? "" : "timeout")
                    return
                }
            } else {
                if now - lastHeardAt > silenceGap {
                    llog("quiet for \(silenceGap)s (level \(String(format: "%.3f", lvl))) - accepting")
                    finish(transcribeMode ? fullText() : "timeout")
                    return
                }
                if now - startedAt > hardCap {
                    llog("hard cap \(hardCap)s reached")
                    finish(transcribeMode ? fullText() : "timeout")
                    return
                }
            }
            tick()
        }
    }
    tick()
}

// ---- permissions, never blocking the main thread -------------------------

SFSpeechRecognizer.requestAuthorization { status in
    DispatchQueue.main.async {
        guard status == .authorized else {
            let name: String
            switch status {
            case .denied: name = "denied-speech"
            case .restricted: name = "denied-speech-restricted"
            case .notDetermined: name = "denied-speech-notdetermined"
            default: name = "denied-speech"
            }
            finish(name)
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                guard granted else { finish("denied-mic"); return }
                startListening()
            }
        }
    }
}

// Backstop for a permission dialog left sitting on screen. It must NOT apply
// once listening has begun: it used to fire mid-dictation and return "timeout",
// silently discarding 90 seconds of speech. The tick() logic owns all timing
// from the moment the microphone is live.
DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
    if !listeningStarted { finish("timeout") }
}

// Exit cleanly when the flow kills us. Default SIGTERM handling tears the
// process down without ever stopping the audio engine, so coreaudiod keeps the
// input device alive and the orange microphone indicator stays lit long after
// the listener is gone. Routing the signal through finish() closes the tap
// first. SIG_IGN is required: the dispatch source only sees signals the default
// handler no longer swallows.
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler { finish("killed") }
termSource.resume()
let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
intSource.setEventHandler { finish("killed") }
intSource.resume()

RunLoop.main.run()
