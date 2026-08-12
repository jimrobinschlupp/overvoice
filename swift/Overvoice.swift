// Menu bar control for the Claude Code spoken-summary hook.
//
// Reads and writes exactly the same two files the shell hook uses —
// ~/.claude/voice.conf and ~/.claude/voice-off — so this UI and the `voice`
// command always agree. Nothing here owns state of its own.
//
// Rebuild:  ~/.claude/menubar/build.sh

import Cocoa
import UserNotifications
import Carbon.HIToolbox

let home = NSHomeDirectory()
let confPath = home + "/.claude/voice.conf"
let offPath = home + "/.claude/voice-off"
let hookPath = home + "/.claude/hooks/speak-summary.sh"
let briefLog = home + "/.claude/menubar/briefings.tsv"

/// Past briefings, newest first. Written by the hook BEFORE the yes/no gate, so
/// a briefing you never listened to is still here — which is the point: you
/// missed it because something else had your attention.
func briefings() -> [(time: String, project: String, text: String)] {
    guard let raw = try? String(contentsOfFile: briefLog, encoding: .utf8) else { return [] }
    return raw.split(separator: "\n").reversed().compactMap { line in
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        // Three columns since the session label was added; two-column lines
        // written before that still replay, just without a label.
        if parts.count >= 3, !parts[2].isEmpty { return (parts[0], parts[1], parts[2]) }
        if parts.count == 2, !parts[1].isEmpty { return (parts[0], "", parts[1]) }
        return nil
    }
}

let logPath = home + "/.claude/menubar/debug.log"

func log(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    } else {
        try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

// ---- shell helpers ------------------------------------------------------

@discardableResult
func run(_ launch: String, _ args: [String], wait: Bool = true) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launch)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    if !wait { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

// ---- settings -----------------------------------------------------------

func conf() -> [String: String] {
    var out: [String: String] = [:]
    guard let text = try? String(contentsOfFile: confPath, encoding: .utf8) else { return out }
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        out[parts[0].trimmingCharacters(in: .whitespaces)] =
            parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }
    return out
}

/// Fall back to the default baked into the hook script, so the menu shows the
/// truth even before anything has been overridden.
func hookDefault(_ key: String) -> String {
    guard let text = try? String(contentsOfFile: hookPath, encoding: .utf8) else { return "" }
    for line in text.split(separator: "\n") where line.hasPrefix(key + "=") {
        let rhs = line.dropFirst(key.count + 1)
        let noComment = rhs.split(separator: "#", maxSplits: 1)[0]
        return noComment.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }
    return ""
}

func setting(_ key: String) -> String {
    if let v = conf()[key], !v.isEmpty { return v }
    return hookDefault(key)
}

func write(_ key: String, _ value: String) {
    var lines = (try? String(contentsOfFile: confPath, encoding: .utf8))?
        .split(separator: "\n").map(String.init) ?? []
    lines.removeAll { $0.hasPrefix(key + "=") }
    lines.append("\(key)=\"\(value)\"")
    try? (lines.joined(separator: "\n") + "\n")
        .write(toFile: confPath, atomically: true, encoding: .utf8)
}

func isMuted() -> Bool { FileManager.default.fileExists(atPath: offPath) }

/// Three states, not two. "Off" used to mean no sound AND no notification,
/// which is right when the alternative is Claude's own notification covering
/// you. Once that is turned off to stop getting two of everything, silencing
/// Overvoice leaves nothing at all, and a briefing can pass unnoticed.
enum VoiceState { case on, notifyOnly, off }

func voiceState() -> VoiceState {
    if !isMuted() { return .on }
    return setting("NOTIFY_WHEN_OFF") == "0" ? .off : .notifyOnly
}

func setVoiceState(_ s: VoiceState) {
    switch s {
    case .on:         setMuted(false); write("NOTIFY_WHEN_OFF", "1")
    case .notifyOnly: setMuted(true);  write("NOTIFY_WHEN_OFF", "1")
    case .off:        setMuted(true);  write("NOTIFY_WHEN_OFF", "0")
    }
}

func setMuted(_ muted: Bool) {
    if muted { FileManager.default.createFile(atPath: offPath, contents: nil) }
    else { try? FileManager.default.removeItem(atPath: offPath) }
}

/// The neural voices, in the order they are worth trying: the calm ones first.
let openAIVoices = ["sage", "ballad", "alloy", "coral", "nova",
                    "ash", "echo", "fable", "onyx", "shimmer"]

/// Is a key in place? Without one the neural engine silently falls back to
/// `say`, so the menu should say as much rather than pretend.
func hasOpenAIKey() -> Bool {
    if ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.isEmpty == false { return true }
    let f = home + "/.claude/openai-key"
    if let t = try? String(contentsOfFile: f, encoding: .utf8) {
        return !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return false
}

/// Voice names contain spaces and nested brackets — "Eddy (German (Germany))" —
/// so split at the run of whitespace before the locale column, not on spaces.
func installedVoices() -> (good: [String], standard: [String]) {
    let out = run("/usr/bin/say", ["-v", "?"])
    var good: [String] = [], standard: [String] = []
    for line in out.split(separator: "\n") {
        let s = String(line)
        guard let r = s.range(of: #"\s{2,}[a-z]{2}_[A-Z]{2}"#, options: .regularExpression)
        else { continue }
        let name = String(s[s.startIndex..<r.lowerBound])
        let lower = name.lowercased()
        if lower.contains("premium") || lower.contains("enhanced") {
            good.append(name)
        } else if s.contains("en_US") || s.contains("en_GB") {
            standard.append(name)
        }
    }
    let keep = ["Samantha", "Alex", "Daniel", "Fred", "Karen", "Moira", "Tessa"]
    return (good, standard.filter { keep.contains($0) })
}

// ---- the mark ------------------------------------------------------------

// The Overvoice logo, cut for the menu bar. At 18pt the gaps that separate
// the V from the O in the full-size mark are thinner than a pixel and close
// up into a blob, so this is an optically opened version of it: same
// geometry, strokes pulled back far enough that the counters survive at 1x.
// How far back is set by the neighbours — the stroke matches wifi and
// control at the same size, since a mark heavier than the icons beside it
// reads as shouting.
// It is embedded rather than dropped in the bundle's Resources because the
// binary is also launched directly, outside the .app, where Bundle.main has
// nothing to hand back. Black with an alpha channel, which is what a
// template image wants — macOS tints it for a light or dark menu bar.
let markPNG = """
iVBORw0KGgoAAAANSUhEUgAAACQAAAAkCAYAAADhAJiYAAAEZUlEQVR42q2YTWhUVxTHf+9lJsmY
UlqlQtJ20UXJolVSiCAqrQFjtaCCEEjdiruu3Il0JxRduhKK3YmRLly4se1CLalKA0W6aDGlGBQq
UqimjDKZjzfd/E85Pdx5zjR5cHl37j3nf847X/fcyVj/8wqwW/MfgPp6wLIBabvAKPAhMAvsAN4B
XhfNU+ABsAR8B3wPNBzvhj25QN+XwG6f44F4MmG89Kn0qZAJeAy8BrSBloTkztJdoNCoivbxRlsn
Kn9hAAtdGPDD+yeUgAz4GvgYWAR+lgWaohkGxoHtwB7RlsXPhsTWEFDrg64m2nVlmWmcKw5SynTc
PCuxZifBExOlKLOSZcFXwFRYi/NswI9N4UxJFqkMNNMekrYnQ4wZw0fApgE8sEk8HsMwT0rWoaAD
mUYNWJYZ77o9I/xMezsiQA/XItpCvNHNd7W3LNmmx78aH5fGLdWZaSdgzqXyuT4y1PbOOb45tz+t
uGpp77jnsyr6kzRuiugTEW0FVrXXBX5Xemc9YsnWh0VrxXJVWAi7K1mFZPsCy5QI2novq9LmwIjq
TeG+aKbEbbY24yxeCGNEmFXJ8DKnfKAd0Lul93XNh4E14LK0b2t/viTbskDT1tplYQ0L+3qQecCD
XJOWDb2PucoLMCnGjvb/AMYSStl8TDRdFyuTAfNYkHnNQKrA/WC+Xc78ZsVF5/cucFgKVEIwZ658
GO2iS31z6a4g8z5QzYHNLthMeN1VXFu7onfHuaQbqqz9/tQFs+fNHX09yNwqXTjhzGaZtM0RG8Pb
wAtH85cBhIzbrD3DeyHeiLctyGwAJ3LgjjutU08hkEfALQluqks86IqnFb2D2mvq9y3x9jof7WkC
d3LgN7WeOHOO9ugYFwLdfKIHmg80Cz06xtFA91S6AHBDG2t6Hwk1xdzxBvDMmboOTDghE1ozN6yK
x2MY5pEg84YPqKUQhB8EkK6A/lTzbhk0pmyraBzWmmXXt+IZcpbIggxTfsmbb19I09uJtsBS+mj4
spuO5mbYO5ooDYZ5O8jc54tZTYFXqC60lQVZwm2vAk+cRZvA5xpN98VPRBvdlQnb5BSSXYun/ZlQ
OS8lTnVT7mI42/yws+ti4rwzrEtB1hm/bxk0DvztSn0B7A1ABj7rjgVTohXWZgOPYex1H9ORzPGY
icZ02sVAAay4Kl4JKbsSzO7dvRJKR8VV4xXRWpydTnUOFisjwL0QmD8CWxxwVfPzJfex8+6cNGW2
CMtj35PM5IXBzPWeqyWWAb+EDjLX6X0VeOgs81BrkyFDp4Xhm7K6ZFF2zfbNfico1QC+AN5KNPLv
asQLwJviaQRlOqnm/mX98JwL1DXnjme6mebOff6xTnO7q+oeo+X664Gv2DOqEda3PNf8bCiW/k8H
4z0r2ueu53nk2t9BrvH/YZjQAemD9lcXiKnb75BoPM+CO/cGVoaEf/cD3zg3ziZoYp1qiWd/D8z/
/S+bz4KdwJfAqRKFTolmZ6KFKX3+AaEXpsh6J+G1AAAAAElFTkSuQmCC
"""

/// The mark as a menu bar image, drawn at `alpha` so the muted state can be
/// the same shape faded rather than a different symbol. Nil if the data ever
/// fails to decode, which the caller answers with a text fallback.
func markImage(alpha: CGFloat) -> NSImage? {
    guard let data = Data(base64Encoded: markPNG, options: .ignoreUnknownCharacters),
          let raw = NSImage(data: data) else { return nil }
    let side: CGFloat = 18
    let img = NSImage(size: NSSize(width: side, height: side))
    img.lockFocus()
    raw.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
             from: .zero, operation: .sourceOver, fraction: alpha)
    img.unlockFocus()
    img.isTemplate = true
    return img
}

// ---- app ----------------------------------------------------------------

// ---- global stop hotkey --------------------------------------------------
//
// Carbon's RegisterEventHotKey, not an NSEvent global monitor. The monitor
// needs Accessibility permission; this does not, so the stop key works the
// moment Overvoice is installed with nothing for the user to approve.
//
// It exists because voice cannot be made reliable on laptop speakers: the
// microphone hears the briefing better than it hears the room, so the
// recogniser spends the window transcribing Overvoice itself. A key press has
// no such problem, and works identically on headphones.

/// Key name to virtual keycode, for the handful worth binding. Names rather
/// than raw numbers so the setting is readable and writable by hand.
func keyCode(for name: String) -> UInt32? {
    let map: [String: Int] = [
        ".": kVK_ANSI_Period, ",": kVK_ANSI_Comma, "/": kVK_ANSI_Slash,
        ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "\\": kVK_ANSI_Backslash,
        "space": kVK_Space, "escape": kVK_Escape, "esc": kVK_Escape,
        "f13": kVK_F13, "f14": kVK_F14, "f15": kVK_F15,
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
        "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
        "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
        "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z
    ]
    return map[name.lowercased()].map { UInt32($0) }
}

/// "cmd+shift+." into a keycode and Carbon modifier mask.
func parseHotkey(_ spec: String) -> (key: UInt32, mods: UInt32)? {
    var mods: UInt32 = 0
    var keyName = ""
    for part in spec.lowercased().split(separator: "+").map({
        $0.trimmingCharacters(in: .whitespaces) }) {
        switch part {
        case "cmd", "command": mods |= UInt32(cmdKey)
        case "shift":          mods |= UInt32(shiftKey)
        case "opt", "option", "alt": mods |= UInt32(optionKey)
        case "ctrl", "control": mods |= UInt32(controlKey)
        default: keyName = part
        }
    }
    guard let k = keyCode(for: keyName) else { return nil }
    return (k, mods)
}

var hotKeyRef: EventHotKeyRef?
/// The Carbon handler is a C function pointer and cannot capture context, so
/// the action it triggers lives here.
var onStopHotKey: (() -> Void)?

class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate,
                  UNUserNotificationCenterDelegate {
    var item: NSStatusItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        log("launched; activationPolicy=\(NSApp.activationPolicy().rawValue)")
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Without an autosave name the item cannot remember where it was put, so
        // every launch macOS drops it in the leftmost slot. On a Mac running a
        // menu bar manager that slot is inside the hidden zone, which is why the
        // icon kept coming back invisible at a large negative x no matter how it
        // was dragged. With a name, its position persists in this app's defaults
        // as "NSStatusItem Preferred Position Overvoice" and a drag sticks.
        item.autosaveName = "Overvoice"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        log("statusItem created; button=\(item.button != nil)")
        startWatchingBriefings()
        installStopHotKey()
        refreshIcon()
        log("visible=\(item.isVisible) length=\(item.length)")

        // Where did the window server actually put it? A frame that is zero,
        // off-screen, or tucked under the notch explains an invisible icon far
        // better than any of the flags above, which all report success anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            let f = self.item.button?.window?.frame
            log("button window frame = \(f.map { NSStringFromRect($0) } ?? "nil")")
            log("menu bar thickness = \(NSStatusBar.system.thickness)")
            for (i, s) in NSScreen.screens.enumerated() {
                log("screen \(i): frame=\(NSStringFromRect(s.frame)) visible=\(NSStringFromRect(s.visibleFrame))")
                if #available(macOS 12.0, *) {
                    log("screen \(i): safeAreaTop=\(s.safeAreaInsets.top) (non-zero means a notch)")
                }
            }
        }
    }

    func refreshIcon() {
        let muted = isMuted()
        // The Overvoice mark itself, so the menu bar carries the same face as
        // the app: full strength when active, faded when muted. An SF Symbol
        // name in ICON_ON / ICON_OFF still wins, so the icon can be swapped
        // for a system one without a rebuild.
        let name = muted ? setting("ICON_OFF") : setting("ICON_ON")
        let img: NSImage?
        if name.isEmpty {
            img = markImage(alpha: muted ? 0.45 : 1)
            log("mark icon resolved=\(img != nil) muted=\(muted)")
        } else {
            img = NSImage(systemSymbolName: name, accessibilityDescription: "Overvoice")
            img?.isTemplate = true
            log("symbol \(name) resolved=\(img != nil)")
        }

        // A status item whose image fails to load and which has no title
        // collapses to zero width and is simply invisible — no error, nothing
        // in the log. Always keep a text fallback so it can't vanish silently.
        if let img = img {
            item.button?.image = img
            item.button?.title = ""
        } else {
            item.button?.image = nil
            item.button?.title = muted ? "Voice off" : "Voice"
        }
        item.isVisible = true
        item.button?.toolTip = muted ? "Overvoice: off" : "Overvoice: on"
    }

    // Rebuilt every time it opens, so changes made with the `voice` command
    // in a terminal show up here without needing a restart.
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let voice = setting("VOICE")
        let rate = setting("RATE")

        // One item rather than a dead status line plus a separate verb. The
        // checkmark is the native macOS idiom for a toggle: the item states
        // what it is, the tick states whether it is on, and clicking flips it.
        // Spelled out rather than one checkbox. With three states a single
        // toggle cannot say which one you are in, and the difference between
        // "silent but still told" and "nothing at all" is the whole point.
        let st = voiceState()
        for (label, want) in [
            ("On", VoiceState.on),
            ("Notifications only", VoiceState.notifyOnly),
            ("Off", VoiceState.off)
        ] {
            let mi = add(menu, label, #selector(pickState(_:)))
            mi.representedObject = want == .on ? "on" : (want == .notifyOnly ? "notify" : "off")
            mi.state = (st == want) ? .on : .off
        }

        // A way to halt a briefing that does not depend on being heard. Speech
        // recognition has to compete with the briefing itself for the
        // microphone, so it will always be the less reliable of the two; this
        // one is a button and cannot fail.
        //
        // Shown only while something is actually speaking. An item that is
        // greyed out most of the time teaches people to ignore it.
        if speakingNow() {
            // Labelled with the GLOBAL key, not a menu-only equivalent. The
            // point of the hotkey is that it works without opening this menu,
            // so the menu is where you learn it exists.
            let spec = setting("STOP_HOTKEY").isEmpty ? "cmd+x" : setting("STOP_HOTKEY")
            let pretty = spec.lowercased() == "none" ? "" :
                "  (" + spec.replacingOccurrences(of: "cmd", with: "⌘")
                            .replacingOccurrences(of: "shift", with: "⇧")
                            .replacingOccurrences(of: "opt", with: "⌥")
                            .replacingOccurrences(of: "ctrl", with: "⌃")
                            .replacingOccurrences(of: "+", with: "") + ")"
            add(menu, "Stop reading briefing" + pretty, #selector(stopSpeaking))
        }
        menu.addItem(.separator())

        // Which engine speaks. Apple's voices need nothing but sound dated;
        // the neural one needs a key and costs fractions of a cent per
        // briefing. Naming both plainly beats hiding the choice in a config.
        let engine = setting("TTS_ENGINE").isEmpty ? "say" : setting("TTS_ENGINE")
        let engineName = engine == "openai" ? "OpenAI" : "Apple"
        let engineItem = NSMenuItem(title: "Engine: \(engineName)", action: nil, keyEquivalent: "")
        let engineMenu = NSMenu()
        for (key, label) in [("say", "Apple: built in, no key"),
                             ("openai", "OpenAI: natural, needs a key")] {
            let mi = NSMenuItem(title: label, action: #selector(pickEngine(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = key
            mi.state = (key == engine) ? .on : .off
            engineMenu.addItem(mi)
        }
        if engine == "openai" && !hasOpenAIKey() {
            engineMenu.addItem(.separator())
            let warn = NSMenuItem(title: "No key found, falling back to Apple",
                                  action: nil, keyEquivalent: "")
            warn.isEnabled = false
            engineMenu.addItem(warn)
        }
        engineItem.submenu = engineMenu
        menu.addItem(engineItem)

        // Voice picker — whichever engine is speaking, those are the voices
        // offered. Showing Apple voices while OpenAI is talking would be a lie.
        let voiceMenu = NSMenu()
        let currentVoice: String
        if engine == "openai" {
            let v = setting("TTS_OPENAI_VOICE").isEmpty ? "sage" : setting("TTS_OPENAI_VOICE")
            currentVoice = v.prefix(1).uppercased() + v.dropFirst()
            for name in openAIVoices {
                let mi = NSMenuItem(title: name.prefix(1).uppercased() + name.dropFirst(),
                                    action: #selector(pickOpenAIVoice(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = name
                mi.state = (name == v) ? .on : .off
                voiceMenu.addItem(mi)
            }
        } else {
            currentVoice = voice
            let (good, standard) = installedVoices()
            if good.isEmpty {
                let none = NSMenuItem(title: "No premium voices installed", action: nil, keyEquivalent: "")
                none.isEnabled = false
                voiceMenu.addItem(none)
            }
            for v in good {
                let mi = NSMenuItem(title: v, action: #selector(pickVoice(_:)), keyEquivalent: "")
                mi.target = self
                mi.state = (v == voice) ? .on : .off
                voiceMenu.addItem(mi)
            }
            if !standard.isEmpty {
                voiceMenu.addItem(.separator())
                let lbl = NSMenuItem(title: "Basic quality", action: nil, keyEquivalent: "")
                lbl.isEnabled = false
                voiceMenu.addItem(lbl)
                for v in standard {
                    let mi = NSMenuItem(title: v, action: #selector(pickVoice(_:)), keyEquivalent: "")
                    mi.target = self
                    mi.state = (v == voice) ? .on : .off
                    voiceMenu.addItem(mi)
                }
            }
            voiceMenu.addItem(.separator())
            let dl = NSMenuItem(title: "Download more voices…", action: #selector(openVoiceSettings),
                                keyEquivalent: "")
            dl.target = self
            voiceMenu.addItem(dl)
        }
        let voiceItem = NSMenuItem(title: "Voice: \(currentVoice)", action: nil, keyEquivalent: "")
        voiceItem.submenu = voiceMenu
        menu.addItem(voiceItem)

        // Speed only means anything to Apple's engine — the neural one takes
        // its pacing from the written delivery brief, so offering a slider
        // that does nothing would be worse than offering none.
        if engine != "openai" {
            let speedItem = NSMenuItem(title: "Speed: \(rate) wpm", action: nil, keyEquivalent: "")
            let speedMenu = NSMenu()
            for (label, wpm) in [("Slowest", "130"), ("Slower", "155"), ("Normal", "185"),
                                 ("Faster", "215"), ("Fastest", "250")] {
                let mi = NSMenuItem(title: "\(label) · \(wpm) wpm",
                                    action: #selector(pickRate(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = wpm
                mi.state = (wpm == rate) ? .on : .off
                speedMenu.addItem(mi)
            }
            speedItem.submenu = speedMenu
            menu.addItem(speedItem)
        }

        // How much detail the spoken briefing carries.
        let depth = setting("DEPTH").isEmpty ? "normal" : setting("DEPTH")
        let depthNames = ["briefing": "Briefing", "full": "Full output",
                          "brief": "Brief", "normal": "Normal",
                          "detailed": "Detailed"]
        let depthItem = NSMenuItem(title: "Detail: \(depthNames[depth] ?? depth)",
                                   action: nil, keyEquivalent: "")
        let depthMenu = NSMenu()
        // The two that cannot quietly drop something you were asked to decide
        // come first, and are named for what they do rather than for how long
        // they are. Below them, one scale described one way: mixing a word
        // count into some entries and prose into others gave no way to compare
        // them.
        for (key, label, blurb) in [
            ("briefing", "Briefing", "your agent's own closing recap"),
            ("full", "Full output", "everything, unedited"),
            ("detailed", "Detailed", "about two thirds"),
            ("normal", "Normal", "about a third"),
            ("brief", "Brief", "about a tenth")
        ] {
            let mi = NSMenuItem(title: "\(label): \(blurb)",
                                action: #selector(pickDepth(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = key
            mi.state = (key == depth) ? .on : .off
            depthMenu.addItem(mi)
        }
        depthItem.submenu = depthMenu
        menu.addItem(depthItem)

        menu.addItem(.separator())

        // The three most recent are replayable in one click, because in practice
        // the one worth hearing again is almost always among them. Five more sit
        // behind a submenu for the rare case, which is what a submenu is for.
        //
        // There is no separate "replay last" entry: it was the first of these
        // three under a different name, and having both meant the same briefing
        // appeared twice in one menu.
        let past = briefings()
        if past.isEmpty {
            let none = NSMenuItem(title: "No briefings yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            // Which session it came from matters more than the words: with
            // several running you need to know what you are about to hear
            // BEFORE playing it.
            // A menu is as wide as its widest row, so these caps set the width
            // of the whole thing. Both are needed: session titles run long on
            // their own, and capping only the preview still left rows the width
            // of the screen. The full text is on the tooltip either way, and
            // the point of the row is recognition, not reading.
            func clip(_ t: String, _ n: Int) -> String {
                t.count > n ? String(t.prefix(n)).trimmingCharacters(in: .whitespaces) + "…" : t
            }
            func entry(_ b: (time: String, project: String, text: String)) -> NSMenuItem {
                // Time and session name only. A briefing's opening words are
                // always the same boilerplate ("I just finished...", "I just
                // checked..."), so a preview spent the row's width saying
                // nothing. The session name is what identifies a briefing; the
                // full text lives on the tooltip for anyone who hovers.
                // Rows from before session labels existed fall back to a
                // snippet, since a bare timestamp identifies nothing.
                let label = b.project.isEmpty
                    ? "\(b.time)  \(clip(b.text, 26))"
                    : "\(b.time)  \(clip(b.project, 34))"
                let mi = NSMenuItem(title: label,
                                    action: #selector(replayOne(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = b.text
                mi.toolTip = b.text
                return mi
            }

            for b in past.prefix(3) { menu.addItem(entry(b)) }

            let older = Array(past.dropFirst(3).prefix(5))
            if !older.isEmpty {
                let earlier = NSMenuItem(title: "Earlier briefings", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for b in older { sub.addItem(entry(b)) }
                earlier.submenu = sub
                menu.addItem(earlier)
            }
        }

        menu.addItem(.separator())
        menu.addItem(.separator())
        add(menu, "Quit Overvoice", #selector(quit))
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        mi.target = self
        menu.addItem(mi)
        return mi
    }

    @objc func toggle() { setMuted(!isMuted()); refreshIcon() }

    @objc func pickState(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case "on":     setVoiceState(.on)
        case "notify": setVoiceState(.notifyOnly)
        default:       setVoiceState(.off)
        }
        refreshIcon()
    }

    /// Is a briefing being spoken right now? The hook records whichever process
    /// owns the voice, so this is the same handle it uses to hand playback over.
    private func speakingNow() -> Bool {
        // -x, not -f. -f matches the whole command line, so ANY process merely
        // mentioning the player counted as playback: a shell running a command
        // with that word in it was enough. While cmd+x is armed only during
        // playback, a false positive there silently steals Cut.
        if !run("/usr/bin/pgrep", ["-x", "overvoice-play"]).trimmingCharacters(
            in: .whitespacesAndNewlines).isEmpty { return true }
        let f = home + "/.claude/menubar/voice.pid"
        guard let raw = try? String(contentsOfFile: f, encoding: .utf8) else { return false }
        let pid = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty, let p = Int32(pid) else { return false }
        return kill(p, 0) == 0
    }

    /// Bind the global stop key, but ONLY while a briefing is speaking.
    ///
    /// A global hotkey outranks every application shortcut, so holding one
    /// permanently means taking that combination away from the whole machine
    /// for the 99% of the time nothing is playing. Binding it only while a
    /// briefing runs makes even ⌘X safe: Cut behaves normally, except during
    /// the seconds when the thing you want to cut short is Overvoice talking.
    ///
    /// The handler is installed once; only the registration comes and goes.
    func installStopHotKey() {
        let spec = stopHotkeySpec()
        if spec.lowercased() == "none" { log("stop hotkey disabled"); return }
        guard parseHotkey(spec) != nil else {
            log("stop hotkey: could not parse '\(spec)'"); return
        }
        onStopHotKey = { [weak self] in self?.stopSpeaking() }

        var evt = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { onStopHotKey?() }
            return noErr
        }, 1, &evt, nil, nil)
        log("stop hotkey armed only while speaking: \(spec)")

        // Faster than the briefing watcher: this decides how quickly the key
        // becomes live once a briefing starts, and how quickly the application
        // gets its own shortcut back afterwards.
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.syncStopHotKey()
        }
    }

    func stopHotkeySpec() -> String {
        let v = setting("STOP_HOTKEY")
        return v.isEmpty ? "cmd+x" : v
    }

    /// Registered exactly when something is speaking, and not otherwise.
    private func syncStopHotKey() {
        let shouldHold = speakingNow()
        if shouldHold && hotKeyRef == nil {
            guard let (key, mods) = parseHotkey(stopHotkeySpec()) else { return }
            let id = EventHotKeyID(signature: OSType(0x4F565354), id: 1)   // 'OVST'
            let st = RegisterEventHotKey(key, mods, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
            if st != noErr {
                hotKeyRef = nil
                log("stop hotkey could not be taken (\(st))")
            } else {
                log("stop hotkey ARMED")
            }
        } else if !shouldHold, let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            log("stop hotkey released")
        }
    }

    @objc func stopSpeaking() {
        // Absolute, not surgical. Everywhere else in Overvoice a single owning
        // pid is killed, so a chime or a second briefing is left alone. Not
        // here: this button exists for the moment when something is speaking
        // that should not be, and stopping only the one process that admitted
        // to owning the voice left a second briefing talking. Someone pressing
        // stop wants silence, not a correctly scoped subset of silence.
        //
        // Order matters. Flows die first so none of them can start a new player
        // after the players have been killed.
        run("/usr/bin/pkill", ["-f", "speak-summary.sh --speak"], wait: true)
        run("/usr/bin/pkill", ["-f", "voice speak"], wait: true)
        let f = home + "/.claude/menubar/voice.pid"
        if let raw = try? String(contentsOfFile: f, encoding: .utf8),
           let p = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(p, SIGTERM)
        }
        // Every player, whoever started it and whether or not it registered.
        // The briefing player first, by signal, so it fades rather than being
        // cut off. killall for everything else: chimes, lead-ins, and any
        // afplay from before the player existed.
        run("/usr/bin/pkill", ["-x", "overvoice-play"], wait: false)
        run("/usr/bin/killall", ["afplay"], wait: false)
        run("/usr/bin/killall", ["say"], wait: false)
        run("/usr/bin/pkill", ["-f", "OvervoiceListen"], wait: false)
        try? "".write(toFile: f, atomically: true, encoding: .utf8)
        log("stopped everything from the menu")
    }

    @objc func pickVoice(_ sender: NSMenuItem) {
        write("VOICE", sender.title)
        run("/usr/bin/say", ["-v", sender.title, "-r", setting("RATE"),
                             "This is \(sender.title). This is how I'll sound."], wait: false)
    }

    @objc func pickRate(_ sender: NSMenuItem) {
        guard let wpm = sender.representedObject as? String else { return }
        write("RATE", wpm)
        run("/usr/bin/say", ["-v", setting("VOICE"), "-r", wpm,
                             "This is how fast I'll speak from now on."], wait: false)
    }

    @objc func pickEngine(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        write("TTS_ENGINE", key)
    }

    @objc func pickOpenAIVoice(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        write("TTS_OPENAI_VOICE", name)
        // No preview: the neural voices are a network call, so hearing one
        // means paying for a render. Replaying a recent briefing from this menu
        // is the honest test, because it goes through the real path.
    }

    @objc func pickDepth(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        write("DEPTH", key)
    }

    /// Stop anything mid-sentence first, so a replay never overlaps a briefing.
    private func speak(_ text: String) {
        // `killall say` was fired without waiting and then `say` was launched
        // immediately, so killall reliably caught the process that had just
        // started: replay was silent every single time, not intermittently.
        // The CLI does the stopping now, in order, before it speaks.
        //
        // Going through the CLI also means replay uses whichever engine is
        // configured. Calling `say` directly here brought a briefing back in an
        // Apple voice even when everything else was speaking as Sage.
        let cli = home + "/.local/bin/voice"
        if FileManager.default.isExecutableFile(atPath: cli) {
            run(cli, ["speak", text], wait: false)
        } else {
            run("/usr/bin/killall", ["say", "afplay"])
            run("/usr/bin/say", ["-v", setting("VOICE"), "-r", setting("RATE"), text], wait: false)
        }
    }

    @objc func replayOne(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        speak(text)
    }

    @objc func openVoiceSettings() {
        run("/usr/bin/open",
            ["x-apple.systempreferences:com.apple.preference.universalaccess?SpeakableItems"],
            wait: false)
    }

    // ---- the briefing banner ---------------------------------------------
    // A briefing is announced by a chime, which says nothing about WHICH session
    // it came from. With several projects running that is the first thing you
    // want to know, and it has to be answerable at a glance, without opening a
    // menu. This drops a small panel out from under the icon naming the project.
    //
    // The hook appends to briefings.tsv BEFORE the gate opens, so watching that
    // file means the banner appears with the chime rather than after the answer.

    private var banner: NSPanel?
    private var bannerHideWork: DispatchWorkItem?
    private var lastSeenStamp: Date?
    private var bannerText = ""

    /// Polls rather than using a vnode source: the hook truncates the log by
    /// writing a temp file and renaming it over the original, which swaps the
    /// inode and silently deafens any watcher holding the old descriptor.
    func startWatchingBriefings() {
        lastSeenStamp = briefLogStamp()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.honourDismissMarker()
            guard let now = self.briefLogStamp() else { return }
            if let was = self.lastSeenStamp, now <= was { return }
            self.lastSeenStamp = now
            // Off means off, on screen as well as out loud. Briefings are still
            // written to the log while muted, deliberately, so a briefing you
            // were not around for is still there to replay later. That is a
            // reason to keep recording them, not a reason to interrupt with
            // them. The stamp is updated above first, so unmuting does not
            // release a backlog of everything that happened in the meantime.
            // Silent does not mean unnotified: that is the middle state.
            if voiceState() == .off { return }
            guard let latest = briefings().first else { return }
            self.notifyBriefing(project: latest.project, text: latest.text)
        }
    }

    /// Saying "no" to a chime should also take the notification away: the
    /// hook heard the no, but only the app that POSTED a notification can
    /// withdraw it, so the hook writes this marker and the watcher acts on it.
    /// The marker holds the briefing text, and only notifications carrying that
    /// exact text are removed, so another session's unread briefing survives.
    private func honourDismissMarker() {
        let marker = home + "/.claude/menubar/dismiss-notification"
        guard let text = try? String(contentsOfFile: marker, encoding: .utf8),
              !text.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: marker)
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let ids = delivered
                .filter { ($0.request.content.userInfo["text"] as? String) == text }
                .map { $0.request.identifier }
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
                log("dismissed \(ids.count) notification(s) after a spoken no")
            }
        }
    }

    private func briefLogStamp() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: briefLog))?[.modificationDate] as? Date
    }

    /// A real macOS notification: it looks native, auto-dismisses on its own,
    /// and lands in Notification Center if you were away from the screen.
    ///
    /// Falls back to the hand-drawn panel below when notifications are
    /// unavailable or refused, so the feature degrades instead of vanishing.
    /// The bundle identifier check is not defensive noise: UNUserNotificationCenter
    /// raises, uncatchably from Swift, when the process has no bundle identity,
    /// and this app is exec'd directly by launchd rather than opened through
    /// LaunchServices. A crash here would take the menu bar icon with it.
    private func notifyBriefing(project: String, text: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            showBanner(project: project, text: text); return
        }
        let title = project.isEmpty ? "Briefing ready" : project
        let snippet = text.count > 140 ? String(text.prefix(140)) + "…" : text
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert]) { [weak self] granted, err in
            if let err = err { log("notification auth error: \(err.localizedDescription)") }
            guard granted else {
                log("notifications not permitted; using the fallback panel")
                DispatchQueue.main.async {
                    self?.showBanner(project: project, text: text)
                }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = snippet
            // Deliberately silent. The chime has already played, and a second
            // sound on top of it is just noise.
            content.userInfo = ["text": text]

            // Time Sensitive, so a Focus can be told to let these through.
            //
            // A Focus swallows notifications while still reporting success to
            // the app that posted them, which looks exactly like a bug: the
            // chime plays, nothing appears, and the log says it was delivered.
            // This level is the only thing macOS offers an app to say "worth
            // interrupting for", and it is honest here: a briefing is waiting
            // on a spoken answer, so it is stale within a minute.
            //
            // It changes nothing on its own. macOS still requires the user to
            // allow Time Sensitive notifications for this app, so with that
            // toggle off it behaves as an ordinary notification. Set
            // NOTIFY_TIME_SENSITIVE=0 in voice.conf to drop back to one.
            if #available(macOS 12.0, *), setting("NOTIFY_TIME_SENSITIVE") != "0" {
                content.interruptionLevel = .timeSensitive
            }
            let req = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
            center.add(req) { e in
                if let e = e { log("notification failed: \(e.localizedDescription)") }
                else { log("notification posted: \(title)") }
            }
        }
    }

    /// Clicking the notification replays that briefing, matching what clicking
    /// the fallback panel does.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if let t = response.notification.request.content.userInfo["text"] as? String,
           !t.isEmpty {
            speak(t)
        }
        done()
    }

    private func showBanner(project: String, text: String) {
        bannerHideWork?.cancel()
        bannerText = text

        let width: CGFloat = 320
        let panel = banner ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            // Never take focus. This can land while the user is typing, and a
            // banner that steals the keyboard mid-sentence is worse than no
            // banner at all.
            p.isFloatingPanel = true
            p.becomesKeyOnlyIfNeeded = true
            p.hidesOnDeactivate = false
            p.level = .statusBar
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.banner = p
            return p
        }()

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 64))
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true

        let title = NSTextField(labelWithString: project.isEmpty ? "Briefing ready" : project)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 44, y: 34, width: width - 56, height: 18)

        let snippet = text.count > 64 ? String(text.prefix(64)) + "…" : text
        let body = NSTextField(labelWithString: snippet)
        body.font = .systemFont(ofSize: 11, weight: .regular)
        body.textColor = .secondaryLabelColor
        body.lineBreakMode = .byTruncatingTail
        body.frame = NSRect(x: 44, y: 12, width: width - 56, height: 18)

        let glyph = NSImageView(frame: NSRect(x: 14, y: 20, width: 22, height: 22))
        glyph.image = NSImage(systemSymbolName: "speaker.wave.2.fill",
                              accessibilityDescription: "Briefing ready")
        glyph.contentTintColor = .controlAccentColor

        // The whole banner is the button: clicking replays this briefing, which
        // is the only thing anyone would want to do with it.
        let hit = NSButton(frame: NSRect(x: 0, y: 0, width: width, height: 64))
        hit.title = ""
        hit.isBordered = false
        hit.target = self
        hit.action = #selector(bannerClicked)

        blur.addSubview(hit)
        blur.addSubview(glyph)
        blur.addSubview(title)
        blur.addSubview(body)
        panel.contentView = blur

        // Anchor under the status item. Falling back to the top right corner
        // matters: when a menu bar manager has parked the icon off-screen, a
        // banner positioned on the icon would be invisible too.
        var x = NSScreen.main.map { $0.frame.maxX - width - 16 } ?? 100
        var y = NSScreen.main.map { $0.frame.maxY - 96 } ?? 100
        if let f = item.button?.window?.frame, f.origin.x > 0 {
            x = min(f.midX - width / 2, (NSScreen.main?.frame.maxX ?? width) - width - 8)
            y = f.origin.y - 72
        }
        log("banner: project=\(project) at x=\(Int(x)) y=\(Int(y))")
        panel.setFrame(NSRect(x: x, y: y + 8, width: width, height: 64), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
            panel.animator().setFrame(NSRect(x: x, y: y, width: width, height: 64),
                                      display: true)
        }

        let hide = DispatchWorkItem { [weak self] in self?.hideBanner() }
        bannerHideWork = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: hide)
    }

    private func hideBanner() {
        guard let panel = banner else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    @objc private func bannerClicked() {
        bannerHideWork?.cancel()
        hideBanner()
        if !bannerText.isEmpty { speak(bannerText) }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// BEFORE NSApplication is touched. AppKit reads this default as the application
// object is set up, so setting it from applicationDidFinishLaunching is already
// too late and the system's ~2s delay stands.
//
// That default is tuned for tooltips explaining a control you can already see.
// Here the tooltip carries the briefing itself, since the row shows only a time
// and a session name, so waiting to read the one thing on offer feels broken.
UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 100])

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.setActivationPolicy(.accessory)   // menu bar only — no Dock icon, no window
app.run()
