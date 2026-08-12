// Synthesises keystrokes, so a spoken reply can reach the Claude Code window.
//
//   OvervoiceKeys check   [out]               -> trusted | untrusted (prompts)
//   OvervoiceKeys type    <text> [out]        -> types into the focused app
//   OvervoiceKeys enter   [out]               -> presses Return
//   OvervoiceKeys send    <text> [out]        -> types, pauses, Return
//   OvervoiceKeys fn2     [out]               -> double-taps Globe/Fn (start Wispr)
//   OvervoiceKeys fn1     [out]               -> single Globe/Fn tap (stop Wispr)
//   OvervoiceKeys playpause [out]             -> hardware play/pause (toggles!)
//   OvervoiceKeys hotkey  <mods> <code> [out] -> e.g. hotkey ctrl,alt 49
//
// `out` is a file to write the result to. It exists because this MUST be
// launched with `open -a`: run straight from a shell the process does not carry
// the Accessibility grant, and every command reports "untrusted".
//
// WARNING: rebuilding changes the ad-hoc signature, so macOS treats it as a
// different app and silently drops the Accessibility permission. After any
// rebuild, remove "Overvoice Keys" in System Settings → Privacy & Security →
// Accessibility and add it back. Avoid rebuilding.

import Cocoa
import ApplicationServices

let args = CommandLine.arguments
guard args.count > 1 else { print("usage"); exit(1) }
let cmd = args[1]
let src = CGEventSource(stateID: .hidSystemState)

func arg(_ i: Int) -> String { args.count > i ? args[i] : "" }

func report(_ s: String, _ outFile: String) {
    if !outFile.isEmpty {
        try? s.write(toFile: outFile, atomically: true, encoding: .utf8)
    }
    print(s)
}

func trusted(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
}

/// Types arbitrary text without needing a keycode for every character.
func type(_ text: String) {
    for chunk in text.chunked(20) {
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        else { continue }
        var utf16 = Array(chunk.utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        usleep(8000)
    }
}

func tap(_ code: CGKeyCode, flags: CGEventFlags = []) {
    let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(12000)
    up?.post(tap: .cghidEventTap)
}

/// Globe/Fn is not an ordinary key: it arrives as a flagsChanged event carrying
/// the secondary-fn mask, so it must be posted that way rather than as a
/// keyDown/keyUp pair. Whether macOS honours a synthetic one is the open
/// question this command exists to answer.
func fnTap() {
    let down = CGEvent(keyboardEventSource: src, virtualKey: 0x3F, keyDown: true)
    down?.type = .flagsChanged
    down?.flags = .maskSecondaryFn
    down?.post(tap: .cghidEventTap)
    usleep(30000)
    let up = CGEvent(keyboardEventSource: src, virtualKey: 0x3F, keyDown: false)
    up?.type = .flagsChanged
    up?.flags = []
    up?.post(tap: .cghidEventTap)
}

/// Hardware play/pause. This is not a normal key — it is a system-defined
/// event with an aux-control subtype, which is why every media app respects it,
/// browsers and Apple Podcasts included, where AppleScript cannot reach.
/// NOTE: it TOGGLES, so only send it when something is known to be playing.
func mediaKey(_ keyCode: Int32) {
    for down in [true, false] {
        let state = down ? 0xA00 : 0xB00
        let data1 = Int((keyCode << 16) | Int32(state))
        if let ev = NSEvent.otherEvent(with: .systemDefined,
                                       location: .zero,
                                       modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
                                       timestamp: 0,
                                       windowNumber: 0,
                                       context: nil,
                                       subtype: 8,
                                       data1: data1,
                                       data2: -1) {
            ev.cgEvent?.post(tap: .cghidEventTap)
        }
        usleep(20000)
    }
}

extension String {
    func chunked(_ n: Int) -> [String] {
        var out: [String] = [], cur = ""
        for ch in self {
            cur.append(ch)
            if cur.count >= n { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

switch cmd {
case "check":
    report(trusted(prompt: true) ? "trusted" : "untrusted", arg(2))

case "type":
    let out = arg(3)
    guard trusted(prompt: false) else { report("untrusted", out); exit(2) }
    type(arg(2))
    report("ok", out)

case "enter":
    let out = arg(2)
    guard trusted(prompt: false) else { report("untrusted", out); exit(2) }
    tap(36)
    report("ok", out)

case "send":
    let out = arg(3)
    guard trusted(prompt: false) else { report("untrusted", out); exit(2) }
    type(arg(2))
    usleep(250000)
    tap(36)
    report("ok", out)

case "fn2":
    let out = arg(2)
    guard trusted(prompt: false) else { report("untrusted", out); exit(2) }
    fnTap()
    usleep(120000)   // stay inside the double-tap window
    fnTap()
    report("posted", out)

case "fn1":
    // Single Globe tap = stop Wispr dictation. Paired with a listener watching
    // for silence, this is what makes dictation hands-free: you stop talking
    // and it closes the dictation for you rather than you reaching for the key.
    let out1 = arg(2)
    guard trusted(prompt: false) else { report("untrusted", out1); exit(2) }
    fnTap()
    report("posted", out1)

case "playpause":
    let out = arg(2)
    guard trusted(prompt: false) else { report("untrusted", out); exit(2) }
    mediaKey(16)          // NX_KEYTYPE_PLAY
    report("ok", out)

case "hotkey":
    let out = arg(4)
    guard trusted(prompt: false) else { report("untrusted", out); exit(2) }
    var flags: CGEventFlags = []
    let mods = arg(2)
    if mods.contains("cmd") { flags.insert(.maskCommand) }
    if mods.contains("alt") || mods.contains("opt") { flags.insert(.maskAlternate) }
    if mods.contains("ctrl") { flags.insert(.maskControl) }
    if mods.contains("shift") { flags.insert(.maskShift) }
    tap(CGKeyCode(UInt16(arg(3)) ?? 49), flags: flags)
    report("ok", out)

default:
    report("unknown", "")
    exit(1)
}
