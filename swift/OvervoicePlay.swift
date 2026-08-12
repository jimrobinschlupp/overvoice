// Plays audio files in order, louder than they were recorded, waiting for ones
// not written yet, and fading out instead of stopping dead when killed.
//
//   overvoice-play <fade-seconds> <file> [file...]
//   OVERVOICE_GAIN=4.0   playback gain, 1.0 = as recorded
//
// Three jobs, none of which afplay or AVAudioPlayer can do.
//
// Gain: neural speech comes back quiet. Measured on a real briefing, peak
// amplitude 0.157, which is 16 dB below full scale, so it plays as a mumble at
// normal system volume. AVAudioPlayer's volume is capped at 1.0 and cannot
// amplify past what is in the file, so playback goes through a mixer, whose
// output volume can exceed 1.0.
//
// Fading: ending a briefing early used to mean killing the process, which cuts
// the voice off mid-syllable. Saying "stop" and having the tool flinch reads as
// being startled.
//
// Waiting: a briefing is rendered in two pieces so the expensive half is only
// bought when someone is listening. The opening is rendered before the chime,
// the rest while the opening plays. Blocking on a part that has not arrived is
// what makes the split inaudible.
//
// Deliberately NOT an .app bundle: it only plays audio, needs no permission of
// any kind, and staying a plain binary keeps it out of TCC entirely.

import Foundation
import AVFoundation

let argv = CommandLine.arguments
guard argv.count > 2 else {
    FileHandle.standardError.write(
        "usage: overvoice-play <fade-seconds> <file> [file...]\n".data(using: .utf8)!)
    exit(2)
}

let fadeSeconds = Double(argv[1]) ?? 0.35
let files = Array(argv.dropFirst(2))

// 4.0 restores roughly what the old boosted path sounded like. On a clip peaking
// at 0.157 that lands near 0.63, which is loud without approaching clipping.
// Passed as an environment variable rather than an argument: the argument order
// has already been got wrong once, and a silent misparse there costs a briefing.
let gain = Float(ProcessInfo.processInfo.environment["OVERVOICE_GAIN"] ?? "") ?? 4.0

// How long to wait for a file still being rendered. Only later parts are worth
// waiting for; a missing first part means something is wrong.
let waitLimit = 60.0

let logPath = NSHomeDirectory() + "/.claude/menubar/listen.log"
func plog(_ m: String) {
    let line = "\(Date()) play: \(m)\n"
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    }
}

let engine = AVAudioEngine()
let node = AVAudioPlayerNode()
engine.attach(node)
engine.connect(node, to: engine.mainMixerNode, format: nil)
engine.mainMixerNode.outputVolume = gain

let lock = NSLock()
var stopping = false

func fadeAndExit() {
    lock.lock()
    if stopping { lock.unlock(); return }
    stopping = true
    lock.unlock()
    // Ramped by hand: a mixer has no fade API, and jumping to zero is the click
    // this exists to avoid. 25 steps over the fade is smooth to the ear.
    let steps = 25
    let start = engine.mainMixerNode.outputVolume
    for i in 1...steps {
        engine.mainMixerNode.outputVolume = start * Float(steps - i) / Float(steps)
        Thread.sleep(forTimeInterval: fadeSeconds / Double(steps))
    }
    node.stop()
    engine.stop()
    exit(0)
}

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
term.setEventHandler { DispatchQueue.global().async { fadeAndExit() } }
term.resume()
let intr = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
intr.setEventHandler { DispatchQueue.global().async { fadeAndExit() } }
intr.resume()

/// Exists and, if it might still be growing, has stopped.
///
/// `settle` is the cost of proving a file is complete, and it is only worth
/// paying for a file that could still be mid-render. The first part is written
/// before playback begins, so checking it twice with a sleep in between spent
/// 0.3s of silence before every single briefing.
func ready(_ path: String, settle: Bool) -> Bool {
    let fm = FileManager.default
    guard let a = try? fm.attributesOfItem(atPath: path),
          let size = a[.size] as? Int, size > 0 else { return false }
    if !settle { return true }
    Thread.sleep(forTimeInterval: 0.15)
    guard let b = try? fm.attributesOfItem(atPath: path),
          let size2 = b[.size] as? Int else { return false }
    return size == size2
}

do { try engine.start() } catch {
    plog("engine failed: \(error.localizedDescription)")
    exit(1)
}
plog("gain \(gain)x")

// Wake the output route before the first word, from inside this engine.
//
// On Bluetooth the route takes a few hundred milliseconds to come up from idle
// and whatever plays during that window is lost, which is why the opening of a
// briefing kept getting clipped. This used to be a separate silent file played
// with afplay, which warmed a route this engine then had to acquire all over
// again. Half a second of silence through the same engine warms the path that
// is actually about to be used.
//
// 0.2s, not 0.5s: this silence is itself a delay before the first word, and the
// engine has already acquired the device by the time it plays.
if let fmt = AVAudioFormat(standardFormatWithSampleRate:
                           engine.mainMixerNode.outputFormat(forBus: 0).sampleRate,
                           channels: 2),
   let silence = AVAudioPCMBuffer(pcmFormat: fmt,
                                  frameCapacity: AVAudioFrameCount(fmt.sampleRate / 5)) {
    silence.frameLength = silence.frameCapacity
    node.scheduleBuffer(silence, at: nil)
    node.play()
}

DispatchQueue.global().async {
    for (i, path) in files.enumerated() {
        let limit = (i == 0) ? 2.0 : waitLimit
        let settle = (i > 0)          // only later parts can be mid-render
        var waited = 0.0
        while !ready(path, settle: settle) && waited < limit {
            if stopping { return }
            Thread.sleep(forTimeInterval: 0.1)
            waited += 0.25
        }
        if !ready(path, settle: false) {
            plog("gave up after \(String(format: "%.1f", waited))s waiting for part \(i + 1)")
            break
        }
        if waited > 0.5 { plog("waited \(String(format: "%.1f", waited))s for part \(i + 1)") }

        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else {
            plog("could not open part \(i + 1)")
            continue
        }
        let done = DispatchSemaphore(value: 0)
        node.scheduleFile(file, at: nil) { done.signal() }
        node.play()
        // Wake periodically rather than blocking outright, so a stop mid-part
        // is not held up until the part finishes.
        while done.wait(timeout: .now() + 0.1) == .timedOut {
            if stopping { return }
        }
        if stopping { return }
    }
    // The completion handler fires when the last buffer is SCHEDULED out, a
    // moment before it has actually been heard. Without this the tail of every
    // briefing is clipped off.
    Thread.sleep(forTimeInterval: 0.4)
    exit(0)
}

RunLoop.main.run()
