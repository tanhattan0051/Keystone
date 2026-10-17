// ShippedConfig.swift — the engine exactly as the app ships it, for tests that
// must reproduce what the user sees rather than what a hand-picked config does.
//
// `shippedConfig` mirrors `AppModel.pushConfig()` with every setting at its
// `AppModel` default: Telex, Unicode, restoreIfInvalid + spellCheck +
// freeMarkAcrossCoda + literalAfterCancel ON, macros and auto-capitalize OFF.
// `shippedController()` installs the same word lists the app installs: the
// real lexicon from `LexiconLoader.load()` (system words + SupplementaryWords,
// prefix index built) and the force-English whitelist.
//
// Suites using these need `/usr/share/dict/words`; gate them with
// `.enabled(if: systemDictExists, ...)` like LexiconRealDictionaryTests.

import Testing
import Foundation
@testable import KeystoneInput
@testable import KeystoneEngine

let systemDictExists = FileManager.default.fileExists(atPath: "/usr/share/dict/words")

let shippedConfig = EngineConfig(
    inputMethod: .telex,
    codeTable: .unicode,
    orthography: .modern,
    restoreIfInvalid: true,
    quickTelex: false,
    macrosEnabled: false,
    macrosExpandWhenVietnameseOff: false,
    macroAutoCapitalize: true,
    macros: [],
    quickStartConsonant: false,
    quickEndConsonant: false,
    autoCapitalize: false,
    allowFreeToneMark: true,
    freeMarkAcrossCoda: true,
    literalAfterCancel: true,
    spellCheck: true
)

/// Loaded once per test process: building it reads ~236k lines.
let shippedLexicon: Lexicon = LexiconLoader.load()

let SPACE = RawKey(keyCode: 49, chars: " ")

/// A fresh controller wired like the running app (`AppModel.updateLexiconLoaded`
/// and `updateForceEnglishLoaded` with their defaults on).
func shippedController(config: EngineConfig = shippedConfig) -> EngineController {
    let c = EngineController(config: config)
    c.setLexicon(shippedLexicon)
    c.setForceEnglish(Lexicon(SupplementaryWords.forceEnglishWords))
    return c
}

/// Types `keys` (one `letter` RawKey per character) through a shipped
/// controller, then each of `then` in order, and returns the simulated screen
/// (see `applyRealistically`). The default `then` is a single Space, which
/// commits the word like any boundary.
func typeShipped(_ keys: String, then: [RawKey] = [SPACE],
                 config: EngineConfig = shippedConfig) -> String {
    let c = shippedController(config: config)
    var acc: [Unicode.Scalar] = []
    for ch in keys { applyRealistically(c.handle(letter(ch)), to: &acc) }
    for k in then { applyRealistically(c.handle(k), to: &acc) }
    return String(String.UnicodeScalarView(acc))
}

/// The screen after typing `keys` with no boundary: what the user sees
/// mid-word.
func screenWhileTyping(_ keys: String, config: EngineConfig = shippedConfig) -> String {
    typeShipped(keys, then: [], config: config)
}
