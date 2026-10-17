// Replayer.swift — drives a CorpusCase's key sequence through a fresh Engine
// and reconstructs the resulting on-screen text.
//
// Each EngineResult carries a backspaceCount (delete that many trailing
// Unicode scalars from the accumulator) and text (append it). `run` deletes
// scalars; `runDeletingGraphemes` deletes grapheme clusters like a Cocoa view.
// Replaying every keystroke this way mirrors exactly what a real input-layer
// consumer would show on screen.

import Foundation
@testable import KeystoneEngine

enum Replayer {
    /// Replay a case's keys through the engine, applying each EngineResult to an
    /// accumulator of Unicode scalars, then flush. Returns the final string.
    static func run(_ c: CorpusCase) -> String {
        let engine = Engine(config: c.engineConfig)
        var acc: [Unicode.Scalar] = []
        func apply(_ r: EngineResult) {
            if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
            acc.append(contentsOf: r.text.unicodeScalars)
        }
        for ch in c.keys {
            if ch == "\u{8}" { apply(engine.process(.backspace)) }
            else { apply(engine.process(KeyInput(ch))) }
        }
        apply(engine.flush())
        return String(String.UnicodeScalarView(acc))
    }

    /// Like `run`, but models a Cocoa text view: each Backspace the engine asks
    /// for deletes one whole grapheme cluster (a base letter together with its
    /// combining marks), not one UTF-16 unit or scalar. This is the screen a
    /// user sees in an app that deletes per grapheme when the engine's output
    /// contains combining marks (.unicodeCompound).
    static func runDeletingGraphemes(keys: String, config: EngineConfig) -> String {
        let engine = Engine(config: config)
        var screen = ""
        func apply(_ r: EngineResult) {
            screen.removeLast(min(r.backspaceCount, screen.count))
            screen += r.text
        }
        for ch in keys {
            if ch == "\u{8}" { apply(engine.process(.backspace)) }
            else { apply(engine.process(KeyInput(ch))) }
        }
        apply(engine.flush())
        return screen
    }
}
