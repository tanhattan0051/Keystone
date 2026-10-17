// GlideMarksAtEndTests.swift — marks typed AFTER the vowel run of a gi-/qu-
// word, and VNI horn on a `uu` pair. The nucleus-prefix checks in Telex's
// circumflex path and VNI's 6/7/8 handlers must look at the nucleus with the
// gi/qu glide folded out (like the Telex `w` path already did): "iây" is not a
// nucleus prefix but "ây" is, so giayas must give giấy. VNI "luu7" must try
// each eligible o/u from the end instead of retrying the same second u.

import Testing
@testable import KeystoneEngine

private let telexCfg = EngineConfig(restoreIfInvalid: true, allowFreeToneMark: true,
                                 freeMarkAcrossCoda: true, literalAfterCancel: true,
                                 spellCheck: true)
private let vniCfg = EngineConfig(inputMethod: .vni, restoreIfInvalid: true,
                               allowFreeToneMark: true, freeMarkAcrossCoda: true,
                               literalAfterCancel: true, spellCheck: true)

/// Types `keys` and a committing space; returns the simulated screen.
private func type(_ keys: String, _ config: EngineConfig) -> String {
    let engine = Engine(config: config)
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    for ch in keys { apply(engine.process(KeyInput(ch))) }
    apply(engine.process(KeyInput(" ")))
    return String(String.UnicodeScalarView(acc))
}

@Suite("GlideMarksAtEnd")
struct GlideMarksAtEndTests {
    @Test(arguments: [
        ("giayas", "giấy "), ("giaays", "giấy "), ("giuawx", "giữa "),
        ("gieengs", "giếng "), ("quaya", "quây "),
        ("giayaf", "giầy "),
    ])
    func telex(_ keys: String, _ expected: String) {
        #expect(type(keys, telexCfg) == expected)
    }

    @Test(arguments: [
        ("luu7", "lưu "), ("giay61", "giấy "), ("huou7", "hươu "),
        ("giua74", "giữa "), ("quan6", "quân "), ("gieng61", "giếng "),
        ("giay6", "giây "), ("quay6", "quây "),
    ])
    func vniMarks(_ keys: String, _ expected: String) {
        #expect(type(keys, vniCfg) == expected)
    }
}
