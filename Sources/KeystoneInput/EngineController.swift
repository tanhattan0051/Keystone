// EngineController.swift — thread-safe wrapper around KeystoneEngine.Engine
// that the tap thread calls directly.
//
// Fully testable via `handle(_:)` alone (no CGEvent needed): feed it RawKey
// values and inspect the returned decision/edit. Guards the engine with an
// OSAllocatedUnfairLock so config updates and resets from other threads
// (e.g. main-thread preference changes) never race the tap thread.

import KeystoneEngine
import os

public final class EngineController: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private let engine: Engine
    private var active = true

    public init(config: EngineConfig) {
        engine = Engine(config: config)
    }

    public func updateConfig(_ config: EngineConfig) {
        lock.withLock { engine.config = config }
    }

    public func setActive(_ a: Bool) {
        lock.withLock {
            active = a
            if !a { engine.reset() }
        }
    }

    public func resetBuffer() {
        lock.withLock { engine.reset() }
    }

    /// Installs (or clears, with `nil`) the English word list `Engine.finalize`
    /// consults when `restoreIfInvalid` fires, to prefer the composed word
    /// over raw keystrokes when it's the real one (see DECISIONS.md "Restore
    /// chooses the composed word when it is the real one"). Under the same
    /// lock as every other engine mutation, so it never races the tap thread.
    public func setLexicon(_ lexicon: Lexicon?) {
        lock.withLock { engine.lexicon = lexicon }
    }

    /// Installs (or clears) the force-English whitelist `Engine.finalize` consults
    /// when `spellCheck` is on. Under the same lock as every engine mutation.
    public func setForceEnglish(_ lexicon: Lexicon?) {
        lock.withLock { engine.forceEnglish = lexicon }
    }

    /// Returns (suppress original event?, edit to execute or nil, decision).
    public func handle(_ k: RawKey) -> (suppress: Bool, edit: EngineResult?, decision: KeyDecision) {
        lock.withLock {
            if !active {
                // English-mode macros (Phase 4, "gõ tắt cả khi tắt tiếng Việt")
                // only route through the engine when BOTH flags are on;
                // otherwise keep the exact pre-Phase-4 passthrough behavior.
                guard engine.config.macrosEnabled && engine.config.macrosExpandWhenVietnameseOff else {
                    return (false, nil, .passthrough)
                }
                let d = KeyTranslator.decide(k)
                switch d {
                case .character(let ch):
                    let r = engine.processInactive(KeyInput(ch))
                    let noop = r.backspaceCount == 0 && r.text.isEmpty
                    return (false, noop ? nil : r, d)   // physical key always passes through
                case .backspace:
                    let r = engine.processInactive(.backspace)
                    let noop = r.backspaceCount == 0 && r.text.isEmpty
                    return (false, noop ? nil : r, d)
                case .commitPassthrough:
                    let r = engine.flushInactive()
                    let noop = r.backspaceCount == 0 && r.text.isEmpty
                    return (false, noop ? nil : r, d)
                case .commitNewline:
                    let r = engine.flushInactiveNewline()
                    let noop = r.backspaceCount == 0 && r.text.isEmpty
                    return (false, noop ? nil : r, d)
                case .resetPassthrough:
                    engine.resetInactive()
                    return (false, nil, d)
                case .passthrough:
                    return (false, nil, d)
                }
            }
            let d = KeyTranslator.decide(k)
            switch d {
            case .character(let ch):
                // The engine ALWAYS takes ownership of a character while
                // active — it either appends to the composing word (and may
                // render nothing new, a no-op edit) or hands back the
                // character embedded in a real edit (empty buffer, or a
                // commit boundary). Suppress unconditionally: a physical
                // passthrough here is exactly what DECISIONS.md's "Do NOT
                // let plain keystrokes bypass the synthetic channel" warns
                // against, and letting a no-op character through desyncs
                // `Engine.prevUnits` from the real screen (see "Suppress
                // every character the engine took ownership of, even a
                // no-op one").
                let r = engine.process(KeyInput(ch))
                let noop = r.backspaceCount == 0 && r.text.isEmpty
                return (true, noop ? nil : r, d)
            case .backspace:
                // Only suppress when the engine actually owns an in-progress
                // word: an empty buffer means this Backspace is an ordinary
                // passthrough Delete the engine never touched. A non-empty
                // buffer means the engine consumed one raw key regardless of
                // whether the re-render is visible — a no-op backspace here
                // deletes an ABSORBED (invisible) key, not a visible
                // character, so it must not fall through as a real Delete.
                let wasComposing = engine.isComposing
                let r = engine.process(.backspace)
                let noop = r.backspaceCount == 0 && r.text.isEmpty
                return (wasComposing, noop ? nil : r, d)
            case .commitPassthrough:
                let r = engine.flush()
                let noop = r.backspaceCount == 0 && r.text.isEmpty
                return (false, noop ? nil : r, d)   // finalize word, but let the nav key pass through
            case .commitNewline:
                let r = engine.flushNewline()
                let noop = r.backspaceCount == 0 && r.text.isEmpty
                return (false, noop ? nil : r, d)   // finalize word + start new sentence, let Return pass through
            case .resetPassthrough:
                engine.reset()
                return (false, nil, d)
            case .passthrough:
                return (false, nil, d)
            }
        }
    }
}
