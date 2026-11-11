// EventTapController.swift — the live CGEventTap (design spec Part B).
//
// Robustness rules this file exists to enforce, all per the spec:
//   (a) re-enable on .tapDisabledByTimeout / .tapDisabledByUserInput inside
//       the callback (§2 Layer A);
//   (b) a DispatchSource watchdog every 1.5s that re-enables if the tap is
//       found disabled (§2 Layer B) — the backstop that guarantees the tap
//       can never stay dead;
//   (c) no heavy system calls in the callback — only engine.handle and event
//       synthesis (§3);
//   (d) a selfTag on every synthetic event so we ignore our own output and
//       never recurse into ourselves (§5);
//   (e) correct CF memory management — .takeRetainedValue() on the Create-rule
//       CFMachPortCreateRunLoopSource, .takeUnretainedValue() on the Get-rule
//       kAXTrustedCheckOptionPrompt constant, never CFRelease by hand (§4).
//
// Runs the tap on a dedicated thread with its own run loop so tap servicing
// is never blocked by AppKit/SwiftUI work on the main thread.

import CoreGraphics
import AppKit
import Foundation
import KeystoneEngine
import os

public final class EventTapController: @unchecked Sendable {
    static let selfTag: Int64 = 0x4B_53_54_4F_4E_45   // "KSTONE"

    private let engine: EngineController
    private let synthSource: CGEventSource?
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var watchdog: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "com.tanta.keystone.watchdog")

    // App-compatibility posting knobs (design spec E.2/E.3), pushed from
    // AppModel off the hot path and read once per edit — same lock/snapshot
    // pattern as EngineController's config.
    private let behaviorLock = OSAllocatedUnfairLock()
    private var behavior = InputBehavior()

    /// How many times the OS has disabled our tap. Logged (once per event, never
    /// per keystroke) because a silently re-enabled tap hides real information:
    /// while chasing the duplicate-key bug this counter is what ruled out
    /// "the tap timed out and the OS re-delivered the key". Tap thread only.
    private var tapDisableCount = 0

    /// The synthetic Backspace and Forward Delete pairs, created ONCE and
    /// re-posted forever (as OpenKey does), instead of allocating fresh
    /// CGEvents per key on the tap hot path — an English word revert used to
    /// cost 2N allocations inside one callback.
    private let backspaceDown: CGEvent?
    private let backspaceUp: CGEvent?
    private let forwardDeleteDown: CGEvent?
    private let forwardDeleteUp: CGEvent?

    public init(engine: EngineController) {
        self.engine = engine
        let src = CGEventSource(stateID: .privateState)
        self.synthSource = src
        // Posting a synthetic event lets macOS suppress the user's REAL hardware
        // events for `localEventsSuppressionInterval` afterwards (0.25s by
        // default). An input method posts on nearly every keystroke, so that
        // window must be zero and local events always permitted, or fast typing
        // right after a tone key could lose keystrokes.
        src?.localEventsSuppressionInterval = 0
        let permitAll: CGEventFilterMask =
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        src?.setLocalEventsFilterDuringSuppressionState(
            permitAll, state: .eventSuppressionStateSuppressionInterval)
        src?.setLocalEventsFilterDuringSuppressionState(
            permitAll, state: .eventSuppressionStateRemoteMouseDrag)
        let backspace = Self.makeKeyPair(virtualKey: Self.backspaceKey, source: src)
        self.backspaceDown = backspace.down
        self.backspaceUp = backspace.up
        let forwardDelete = Self.makeKeyPair(virtualKey: Self.forwardDeleteKey, source: src)
        self.forwardDeleteDown = forwardDelete.down
        self.forwardDeleteUp = forwardDelete.up
    }

    private static let backspaceKey: CGKeyCode = 51
    private static let forwardDeleteKey: CGKeyCode = 117

    private static func makeKeyPair(virtualKey: CGKeyCode, source: CGEventSource?) -> (down: CGEvent?, up: CGEvent?) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        // Flags are left at the source's creation default (0x20000000 on macOS 27)
        // rather than overwritten — the same as OpenKey, and nothing here needs
        // them changed: a private-state source carries no modifier bits.
        for e in [down, up].compactMap({ $0 }) {
            e.setIntegerValueField(.eventSourceUserData, value: selfTag)
        }
        return (down, up)
    }

    /// Updates the posting-behavior snapshot (`sendEachKeystroke`,
    /// `textOnKeyDownOnly`, `inlineSuggestionClearing`) the tap reads on the
    /// next edit. Safe to call from any thread; guarded by `behaviorLock`.
    public func updateBehavior(_ b: InputBehavior) {
        behaviorLock.withLock { behavior = b }
    }

    public var isRunning: Bool { tapPort.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    public func start() {
        let t = Thread { [weak self] in
            guard let self else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            self.createTap()
            CFRunLoopRun()
        }
        t.name = "com.tanta.keystone.tap"
        tapThread = t
        t.start()
        startWatchdog()
    }

    public func stop() {
        watchdog?.cancel(); watchdog = nil
        if let p = tapPort { CGEvent.tapEnable(tap: p, enable: false) }
        if let rl = tapRunLoop {
            if let src = runLoopSource { CFRunLoopRemoveSource(rl, src, .commonModes) }
            CFRunLoopStop(rl)
        }
        tapPort = nil; runLoopSource = nil; tapThread = nil; tapRunLoop = nil
    }

    private func createTap() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: keystoneTapCallback, userInfo: refcon
        ) else {
            NSLog("Keystone: CGEvent.tapCreate returned nil — Accessibility permission missing?")
            return
        }
        tapPort = port
        // Note: on current SDKs CFMachPortCreateRunLoopSource is already
        // bridged to a plain ARC-managed `CFRunLoopSource?` (no `Unmanaged`
        // wrapper to unwrap with `.takeRetainedValue()`); ARC owns the
        // returned reference for us, consistent with the Create-rule
        // ownership this ARC bridging performs on our behalf.
        guard let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            NSLog("Keystone: CFMachPortCreateRunLoopSource returned nil")
            return
        }
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func startWatchdog() {
        let w = DispatchSource.makeTimerSource(queue: watchdogQueue)
        w.schedule(deadline: .now() + 1.5, repeating: 1.5, leeway: .milliseconds(500))
        w.setEventHandler { [weak self] in
            guard let self, let p = self.tapPort else { return }
            if !CGEvent.tapIsEnabled(tap: p) {
                // Reset BEFORE re-enabling: afterwards the tap thread may already
                // be handling the first key of a new word, which the reset would drop.
                self.tapWasInterrupted()
                CGEvent.tapEnable(tap: p, enable: true)
            }
        }
        w.resume()
        watchdog = w
    }

    /// Call whenever the tap was found disabled and re-enabled. Keystrokes typed
    /// during the gap reached the app untransformed, so the engine's composing
    /// word no longer matches the screen; the next edit would backspace over
    /// text it never rendered. Dropping the buffer (no commit: the screen is
    /// not ours to rewrite) resyncs. Safe from the watchdog queue too:
    /// `resetBuffer` takes the controller's lock.
    func tapWasInterrupted() {
        engine.resetBuffer()
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Logging here does not violate spec §3's no-logging-on-the-hot-path
            // rule: this branch fires a handful of times at most, never per
            // keystroke, and a silently re-enabled tap hides a real signal.
            tapDisableCount &+= 1
            NSLog("Keystone: tap disabled (%@) #%d — re-enabling",
                  type == .tapDisabledByTimeout ? "timeout" : "user input", tapDisableCount)
            if let p = tapPort { CGEvent.tapEnable(tap: p, enable: true) }
            tapWasInterrupted()
            return nil
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.selfTag {
            return Unmanaged.passUnretained(event)   // our own synthetic event
        }
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            // The edit is posted BEFORE the click passes through: our
            // synthetic events reach the focused app ahead of the click, so
            // they still land at the old caret, where the word is.
            if let edit = engine.handleMouseDown() {
                post(edit, decision: .commitCaretMove, route: .tap(proxy),
                     backspaceDown: backspaceDown, backspaceUp: backspaceUp,
                     forwardDeleteDown: forwardDeleteDown, forwardDeleteUp: forwardDeleteUp)
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged { return Unmanaged.passUnretained(event) }

        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        // NOTE: there is deliberately no duplicate-key filter here.
        //
        // The "doubled tone key" bug (task→tassk) is not an extra key event at
        // all: it is the user's own Telex tone-CANCEL keystroke (t a s s k, the
        // second `s` undoing the tone so the screen reads "task"), which
        // `restoreIfInvalid` then puts back when it reverts the word to raw keys at
        // commit. It reproduces in the engine alone. See DECISIONS.md,
        // "Duplicate key-down".
        //
        // Four generations of a filter lived here and "fixed" it only by eating
        // that cancel keystroke — which is indistinguishable, at the key level,
        // from the second letter of a real double (`pass`, `class`), so they ate
        // those too, and blocked held-Delete. A visible extra character is
        // recoverable by the user; a silently eaten keystroke is not.
        let raw = makeRawKey(event)
        let (suppress, edit, decision) = engine.handle(raw)
        let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if let edit, RepostPolicy.canRepostOriginal(decision: decision, edit: edit, isAutorepeat: isAutorepeat) {
            // The edit is just the typed character: re-emit the user's own
            // event (keeps keycode, flags, autorepeat) tagged as ours, and
            // swallow the original. This is NOT a physical passthrough: the
            // copy goes through the same ordered tapPostEvent channel as
            // synthetic text (DECISIONS.md, "Do NOT let plain keystrokes
            // bypass the synthetic channel"). No synthetic keyUp: the physical keyUp
            // is outside the tap's mask and passes with the real keycode.
            if let copy = event.copy() {
                copy.setIntegerValueField(.eventSourceUserData, value: Self.selfTag)
                copy.tapPostEvent(proxy)
                return nil
            }
            // Copy failed (resource pressure): fall back to the synthetic path.
        }
        if let edit {
            post(edit, decision: decision, route: .tap(proxy),
                 backspaceDown: backspaceDown, backspaceUp: backspaceUp,
                 forwardDeleteDown: forwardDeleteDown, forwardDeleteUp: forwardDeleteUp)
        }
        return suppress ? nil : Unmanaged.passUnretained(event)
    }

    /// Posts a commit edit from OUTSIDE the tap callback (the modifier-only
    /// switch key is seen by AppKit monitors on the main thread, where there is
    /// no `CGEventTapProxy`), so it goes in at session level. Our own tap sees
    /// these events and passes them through via `selfTag`. The key pairs are
    /// created fresh: the shared one is being re-posted by the tap thread, and
    /// the main thread must not post the same CGEvent objects concurrently. Not
    /// on the per-keystroke hot path, so the two extra allocations are fine.
    public func postFromOutsideTap(_ edit: EngineResult) {
        let backspace = Self.makeKeyPair(virtualKey: Self.backspaceKey, source: synthSource)
        let forwardDelete = Self.makeKeyPair(virtualKey: Self.forwardDeleteKey, source: synthSource)
        post(edit, decision: .commitCaretMove, route: .session,
             backspaceDown: backspace.down, backspaceUp: backspace.up,
             forwardDeleteDown: forwardDelete.down, forwardDeleteUp: forwardDelete.up)
    }

    /// Realizes an engine edit as synthetic events (key path, mouse path and
    /// `postFromOutsideTap`).
    private func post(_ edit: EngineResult, decision: KeyDecision, route: Route,
                      backspaceDown: CGEvent?, backspaceUp: CGEvent?,
                      forwardDeleteDown: CGEvent?, forwardDeleteUp: CGEvent?) {
        // One cheap lock acquire per edit (not per raw keystroke that
        // passes through untouched) — acceptable on the hot path, same
        // cost class as EngineController's config lock.
        let b = behaviorLock.withLock { behavior }
        let sink = TapSink(source: synthSource, route: route,
                           backspaceDown: backspaceDown, backspaceUp: backspaceUp,
                           forwardDeleteDown: forwardDeleteDown, forwardDeleteUp: forwardDeleteUp,
                           textOnKeyDownOnly: b.textOnKeyDownOnly)
        KeystrokeExecutor(sink: sink).execute(
            edit,
            eachGrapheme: b.sendEachKeystroke,
            inlineSuggestionClearing: InlineSuggestionFix.clearing(
                configured: b.inlineSuggestionClearing, decision: decision, edit: edit)
        )
    }

    private func makeRawKey(_ event: CGEvent) -> RawKey {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        var length = 0
        var buf = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buf)
        let chars = length > 0 ? String(utf16CodeUnits: buf, count: length) : ""
        return RawKey(
            keyCode: Int(keyCode),
            command: flags.contains(.maskCommand),
            control: flags.contains(.maskControl),
            option: flags.contains(.maskAlternate),
            shift: flags.contains(.maskShift),
            chars: chars
        )
    }
}

private func keystoneTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
        .handle(proxy: proxy, type: type, event: event)
}

/// Where a synthetic event is injected: back through the tap's own proxy (inside
/// the callback), or at session level (from any other thread).
private enum Route {
    case tap(CGEventTapProxy)
    case session

    func deliver(_ e: CGEvent) {
        switch self {
        case .tap(let proxy): e.tapPostEvent(proxy)
        case .session: e.post(tap: .cgSessionEventTap)
        }
    }
}

private struct TapSink: EventSink {
    let source: CGEventSource?
    let route: Route
    let backspaceDown: CGEvent?
    let backspaceUp: CGEvent?
    let forwardDeleteDown: CGEvent?
    let forwardDeleteUp: CGEvent?
    /// "Sửa lỗi gợi ý" (`autoFixSuggestion`, default OFF): when true, the
    /// Unicode string is set on the keyDown event only — the keyUp is posted
    /// bare — which is the documented remedy for browsers/Excel doubling
    /// synthesized text. When false, both events carry the string (the old
    /// behavior).
    let textOnKeyDownOnly: Bool

    func postBackspace(count: Int) {
        // Re-post the ONE pre-built pair instead of allocating a fresh CGEvent per
        // backspace inside the tap callback.
        guard let down = backspaceDown, let up = backspaceUp else { return }
        for _ in 0..<count { route.deliver(down); route.deliver(up) }
    }

    func postForwardDelete() {
        guard let down = forwardDeleteDown, let up = forwardDeleteUp else { return }
        route.deliver(down); route.deliver(up)
    }

    func postText(_ text: String) {
        // Intentional silent drop: CGEvent allocation only fails under severe
        // resource pressure, and this runs on the tap hot path where logging
        // per keystroke is itself forbidden (spec §3). Dropping one synthesized
        // char is the least-bad outcome.
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }
        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { b in
            guard let base = b.baseAddress else { return }
            down.keyboardSetUnicodeString(stringLength: b.count, unicodeString: base)
            if !textOnKeyDownOnly {
                up.keyboardSetUnicodeString(stringLength: b.count, unicodeString: base)
            }
        }
        for e in [down, up] {
            e.setIntegerValueField(.eventSourceUserData, value: EventTapController.selfTag)
            route.deliver(e)
        }
    }

}
