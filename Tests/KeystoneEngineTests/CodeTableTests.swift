// CodeTableTests.swift — output-code-table tests (design spec Part A §6-§7).
//
// (a) Unicode compound (tổ hợp) is canonically EQUIVALENT to the NFC form
//     the engine emits by default, for a range of live-typing Telex words.
// (b) CP1258 byte-exact assertions, hard-coded from Python's built-in
//     `cp1258` codec (see CP1258.swift's header for the verification
//     method) — a regression pin independent of the Swift implementation.
// (c) TCVN3 / VNI-Windows byte-exact assertions, hard-coded from the
//     cross-referenced published tables documented in TCVN3.swift /
//     VNIWindows.swift.
// (d) Converter round-trips Unicode -> CP1258 -> Unicode and
//     Unicode -> Compound -> Unicode losslessly.

import Testing
@testable import KeystoneEngine

@Suite("CodeTable") struct CodeTableTests {

    // MARK: - (a) Unicode compound canonical-equivalence

    static let telexWords: [String] = [
        "vieejt",     // việt
        "hoaf",       // hòa
        "nguyeexn",   // nguyễn
        "dduwowcj",   // được
        "tieengs",    // tiếng
        "muoons",     // muốn
        "quoocs",     // quốc
        "thuyr",      // thủy
        "khuyur",     // khuỷu (triphthong u-y-u, middle vowel carries tone)
    ]

    @Test(arguments: CodeTableTests.telexWords)
    func compoundCanonicallyEqualsNFC(_ keys: String) {
        let nfcCase = CorpusCase(name: "nfc-\(keys)", keys: keys, codeTable: "unicode", expected: "")
        let compoundCase = CorpusCase(name: "compound-\(keys)", keys: keys, codeTable: "unicodeCompound", expected: "")
        let nfc = Replayer.run(nfcCase)
        // Compound output has combining marks, so the engine counts Backspaces in
        // graphemes (see GraphemeDiffTests); replay it the way a Cocoa view deletes.
        let compound = Replayer.runDeletingGraphemes(keys: keys, config: compoundCase.engineConfig)

        #expect(
            compound.precomposedStringWithCanonicalMapping == nfc,
            "compound output for keys=\(keys) is not canonically equivalent to NFC: compound=\(Array(compound.unicodeScalars.map { $0.value })) nfc=\(nfc)"
        )
        #expect(
            compound.unicodeScalars.count >= nfc.unicodeScalars.count,
            "compound form should never use FEWER scalars than NFC for keys=\(keys)"
        )
    }

    // MARK: - (b) CP1258 assertions
    //
    // Live CP1258 output is the REAL cp1258 decode of the bytes (one scalar
    // per byte): quality letters are precomposed Unicode (â ă ê ô ơ ư đ) and
    // tone bytes are combining marks (0xCC->U+0300, 0xEC->U+0301,
    // 0xD2->U+0309, 0xDE->U+0303, 0xF2->U+0323). Expected scalars were
    // computed with Python's `cp1258` codec, e.g.
    //   python3 -c "print([hex(ord(c)) for c in bytes([0x76,0x69,0xEA,0xF2,0x74]).decode('cp1258')])"
    // The original bytes are kept in the trailing comments.

    static let cp1258Cases: [(keys: String, scalars: [UInt32])] = [
        ("vieejt",   [0x76, 0x69, 0xEA, 0x0323, 0x74]),                  // việt   76 69 EA F2 74
        ("tieengs",  [0x74, 0x69, 0xEA, 0x0301, 0x6E, 0x67]),            // tiếng  74 69 EA EC 6E 67
        ("hoaf",     [0x68, 0x6F, 0x0300, 0x61]),                        // hòa    68 6F CC 61
        ("muoons",   [0x6D, 0x75, 0xF4, 0x0301, 0x6E]),                  // muốn   6D 75 F4 EC 6E
        ("dduwowcj", [0x0111, 0x01B0, 0x01A1, 0x0323, 0x63]),            // được   F0 FD F5 F2 63
        ("quoocs",   [0x71, 0x75, 0xF4, 0x0301, 0x63]),                  // quốc   71 75 F4 EC 63
        ("nguyeexn", [0x6E, 0x67, 0x75, 0x79, 0xEA, 0x0303, 0x6E]),      // nguyễn 6E 67 75 79 EA DE 6E
    ]

    @Test(arguments: CodeTableTests.cp1258Cases)
    func cp1258Exact(_ c: (keys: String, scalars: [UInt32])) {
        let cc = CorpusCase(name: "cp1258-\(c.keys)", keys: c.keys, codeTable: "cp1258", expected: "")
        let out = Replayer.run(cc)
        let scalars = out.unicodeScalars.map { $0.value }
        #expect(scalars == c.scalars, "keys=\(c.keys) got \(scalars.map { String(format: "0x%04X", $0) })")
    }

    // MARK: - (c) TCVN3 / VNI-Windows byte assertions
    //
    // Expected bytes derived from the cross-referenced published tables in
    // TCVN3.swift / VNIWindows.swift (each independently confirmed against
    // two sources — see those files' headers), via a from-scratch Python
    // re-implementation of the same (base, mark, tone) -> bytes rules, kept
    // separate from the Swift code under test.

    static let tcvn3Cases: [(keys: String, bytes: [UInt8])] = [
        ("vieejt",   [0x76, 0x69, 0xD6, 0x74]),                    // việt
        ("tieengs",  [0x74, 0x69, 0xD5, 0x6E, 0x67]),              // tiếng
        ("hoaf",     [0x68, 0xDF, 0x61]),                          // hòa
        ("muoons",   [0x6D, 0x75, 0xE8, 0x6E]),                    // muốn
        ("dduwowcj", [0xAE, 0xAD, 0xEE, 0x63]),                    // được
        ("quoocs",   [0x71, 0x75, 0xE8, 0x63]),                    // quốc
        ("nguyeexn", [0x6E, 0x67, 0x75, 0x79, 0xD4, 0x6E]),        // nguyễn
    ]

    @Test(arguments: CodeTableTests.tcvn3Cases)
    func tcvn3ByteExact(_ c: (keys: String, bytes: [UInt8])) {
        let cc = CorpusCase(name: "tcvn3-\(c.keys)", keys: c.keys, codeTable: "tcvn3", expected: "")
        let out = Replayer.run(cc)
        let bytes = Array(out.unicodeScalars.map { UInt8($0.value) })
        #expect(bytes == c.bytes, "keys=\(c.keys) got \(bytes.map { String(format: "0x%02X", $0) })")
    }

    static let vniWindowsCases: [(keys: String, bytes: [UInt8])] = [
        ("vieejt",   [0x76, 0x69, 0x65, 0xE4, 0x74]),                    // việt
        ("tieengs",  [0x74, 0x69, 0x65, 0xE1, 0x6E, 0x67]),              // tiếng
        ("hoaf",     [0x68, 0x6F, 0xF8, 0x61]),                          // hòa
        ("muoons",   [0x6D, 0x75, 0x6F, 0xE1, 0x6E]),                    // muốn
        ("dduwowcj", [0xF1, 0xF6, 0xF4, 0xEF, 0x63]),                    // được
        ("quoocs",   [0x71, 0x75, 0x6F, 0xE1, 0x63]),                    // quốc
        ("nguyeexn", [0x6E, 0x67, 0x75, 0x79, 0x65, 0xE3, 0x6E]),        // nguyễn
    ]

    @Test(arguments: CodeTableTests.vniWindowsCases)
    func vniWindowsByteExact(_ c: (keys: String, bytes: [UInt8])) {
        let cc = CorpusCase(name: "vniWindows-\(c.keys)", keys: c.keys, codeTable: "vniWindows", expected: "")
        let out = Replayer.run(cc)
        let bytes = Array(out.unicodeScalars.map { UInt8($0.value) })
        #expect(bytes == c.bytes, "keys=\(c.keys) got \(bytes.map { String(format: "0x%02X", $0) })")
    }

    // MARK: - (d) Converter round-trips

    static let roundTripWords = ["việt", "tiếng", "hòa", "muốn", "được", "quốc", "nguyễn", "xin chào"]

    @Test(arguments: CodeTableTests.roundTripWords)
    func cp1258RoundTrip(_ w: String) {
        let toCp1258 = Converter.convert(w, from: .unicode, to: .cp1258)
        let back = Converter.convert(toCp1258, from: .cp1258, to: .unicode)
        #expect(back == w, "round trip via cp1258 failed for \(w): got \(back)")
    }

    @Test(arguments: CodeTableTests.roundTripWords)
    func compoundRoundTrip(_ w: String) {
        let toCompound = Converter.convert(w, from: .unicode, to: .unicodeCompound)
        let back = Converter.convert(toCompound, from: .unicodeCompound, to: .unicode)
        #expect(back == w, "round trip via unicodeCompound failed for \(w): got \(back)")
    }

    // Converting FROM tcvn3/vniWindows is documented as unsupported (no
    // confident inverse map yet) and must return the input unchanged rather
    // than silently wrong text.
    @Test func unsupportedFromDirectionsReturnInputUnchanged() {
        let text = "anything"
        #expect(Converter.convert(text, from: .tcvn3, to: .unicode) == text)
        #expect(Converter.convert(text, from: .vniWindows, to: .unicode) == text)
    }
}
