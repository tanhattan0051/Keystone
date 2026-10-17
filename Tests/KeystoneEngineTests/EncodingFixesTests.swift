// EncodingFixesTests.swift — regression tests for the code-table / Converter
// fixes in DECISIONS.md "Bảng mã & Converter fixes (2026-10-17)".

import Testing
@testable import KeystoneEngine

@Suite("EncodingFixes") struct EncodingFixesTests {

    // MARK: helpers

    static func run(_ keys: String, table: String) -> [UInt32] {
        let cc = CorpusCase(name: "\(table)-\(keys)", keys: keys, codeTable: table, expected: "")
        return Replayer.run(cc).unicodeScalars.map { $0.value }
    }

    // MARK: - 1. CP1258 decode is a real cp1258 decode

    @Test func cp1258DecodeMapsHighHalfLikePython() {
        let t = CP1258Table()
        // Spot checks taken from Python's cp1258 codec.
        let expected: [UInt16: UInt32] = [
            0x80: 0x20AC, 0xC3: 0x0102, 0xCC: 0x0300, 0xD0: 0x0110, 0xD2: 0x0309,
            0xD5: 0x01A0, 0xDD: 0x01AF, 0xDE: 0x0303, 0xE3: 0x0103, 0xEC: 0x0301,
            0xF0: 0x0111, 0xF2: 0x0323, 0xF5: 0x01A1, 0xFD: 0x01B0, 0xFE: 0x20AB,
            0x41: 0x41, 0x7F: 0x7F, 0xA9: 0xA9, 0xFF: 0xFF,
        ]
        for (byte, scalar) in expected {
            #expect(t.decode([byte]).unicodeScalars.map { $0.value } == [scalar], "byte 0x\(String(byte, radix: 16))")
        }
    }

    @Test func cp1258DecodeIsOneScalarPerByte() {
        let all = (0...255).map { UInt16($0) }
        #expect(CP1258Table().decode(all).unicodeScalars.count == 256)
    }

    // MARK: - 2. Unicode compound == NFD of NFC

    static let legalMarks: [(BaseVowel, [VowelMark])] = [
        (.a, [.none, .circumflex, .breve]), (.e, [.none, .circumflex]), (.i, [.none]),
        (.o, [.none, .circumflex, .horn]), (.u, [.none, .horn]), (.y, [.none]),
    ]

    @Test func compoundTableEqualsNFDOfNFCForEveryVowel() {
        let nfc = UnicodeNFCTable()
        let compound = UnicodeCompoundTable()
        let tones: [Tone] = [.ngang, .huyen, .sac, .hoi, .nga, .nang]
        var checked = 0
        for (base, marks) in Self.legalMarks {
            for mark in marks {
                for tone in tones {
                    for upper in [false, true] {
                        let n = nfc.decode(nfc.vowel(base: base, mark: mark, tone: tone, upper: upper))
                        let c = compound.decode(compound.vowel(base: base, mark: mark, tone: tone, upper: upper))
                        let want = n.decomposedStringWithCanonicalMapping
                        #expect(c.unicodeScalars.map { $0.value } == want.unicodeScalars.map { $0.value },
                                "\(base) \(mark) \(tone) upper=\(upper)")
                        checked += 1
                    }
                }
            }
        }
        #expect(checked == 144)
    }

    // MARK: - 1b. Converter CP1258 forms

    @Test func unicodeToCP1258IsRealUnicodeForm() {
        let out = Converter.convert("việt", from: .unicode, to: .cp1258)
        #expect(out.unicodeScalars.map { $0.value } == [0x76, 0x69, 0xEA, 0x0323, 0x74])
        let out2 = Converter.convert("được", from: .unicode, to: .cp1258)
        #expect(out2.unicodeScalars.map { $0.value } == [0x0111, 0x01B0, 0x01A1, 0x0323, 0x63])
    }

    @Test func cp1258DecodeAcceptsRealUnicodeForm() {
        let real = "vi\u{EA}\u{0323}t \u{0103}n \u{01B0}\u{0301}c"
        #expect(Converter.convert(real, from: .cp1258, to: .unicode) == "việt ăn ức")
    }

    @Test func cp1258DecodeAcceptsOldLatin1PseudoForm() {
        // Old convention: each scalar IS the byte. ă=0xE3, ư=0xFD, tone dot=0xF2.
        let old = "vi\u{EA}\u{F2}t \u{E3}n \u{FD}\u{EC}c \u{F0}"
        #expect(Converter.convert(old, from: .cp1258, to: .unicode) == "việt ăn ức đ")
    }

    @Test func cp1258TargetKeepsNonVietnameseCharacters() {
        #expect(Converter.convert("© €", from: .unicode, to: .cp1258) == "© €")
    }

    // MARK: - 3. Case transforms

    @Test func sentenceCaseCapitalizesEachSentenceAndKeepsRest() {
        let r = Converter.convert("xin chào. tôi là Tân ở Hà Nội", from: .unicode, to: .unicode, caseTransform: .sentence)
        #expect(r == "Xin chào. Tôi là Tân ở Hà Nội")
    }

    @Test func sentenceCaseHandlesTerminatorsQuotesAndNewlines() {
        let r = Converter.convert("a! \"b?\" (c)\nd.e\r\nf", from: .unicode, to: .unicode, caseTransform: .sentence)
        #expect(r == "A! \"B?\" (C)\nD.e\r\nF")
    }

    @Test func sentenceCaseLeavesUrlsEmailsAndFileNamesAlone() {
        func sc(_ t: String) -> String { Converter.convert(t, from: .unicode, to: .unicode, caseTransform: .sentence) }
        #expect(sc("xem vietnix.vn hoặc file.txt. ok") == "Xem vietnix.vn hoặc file.txt. Ok")
        #expect(sc("tan@vietnix.vn") == "Tan@vietnix.vn")
        #expect(sc("v.v. xong") == "V.v. Xong")
    }

    @Test func cp1258DecodeDoesNotTrapOnEmoji() {
        #expect(Converter.convert("ok 😀", from: .cp1258, to: .unicode) == "ok 😀")
        #expect(Converter.convert("😀a", from: .cp1258, to: .unicode) == "😀a")
    }

    @Test func sentenceCaseDoesNotLowercase() {
        #expect(Converter.convert("iPhone HTML", from: .unicode, to: .unicode, caseTransform: .sentence) == "IPhone HTML")
    }

    @Test func titleCaseOnlyRaisesFirstLetterOfEachWord() {
        let r = Converter.convert("iphone và HTML xin chào", from: .unicode, to: .unicode, caseTransform: .title)
        #expect(r == "Iphone Và HTML Xin Chào")
        #expect(Converter.convert("don't stop", from: .unicode, to: .unicode, caseTransform: .title) == "Don't Stop")
        #expect(Converter.convert("đường  ưu\ttiên", from: .unicode, to: .unicode, caseTransform: .title) == "Đường  Ưu\tTiên")
    }

    @Test func lowerAndUpperUnchanged() {
        #expect(Converter.convert("Xin Chào", from: .unicode, to: .unicode, caseTransform: .lower) == "xin chào")
        #expect(Converter.convert("Xin Chào", from: .unicode, to: .unicode, caseTransform: .upper) == "XIN CHÀO")
    }

    // MARK: - 4. CRLF

    @Test(arguments: [CodeTable.unicode, .unicodeCompound, .tcvn3, .vniWindows, .cp1258])
    func crlfIsPreserved(_ table: CodeTable) {
        let out = Converter.convert("a\r\nb\nc\rd", from: .unicode, to: table)
        #expect(out.unicodeScalars.map { $0.value } == [0x61, 0x0D, 0x0A, 0x62, 0x0A, 0x63, 0x0D, 0x64])
    }

    // MARK: - 5. Unencodable characters in TCVN3 / VNI

    @Test(arguments: [CodeTable.tcvn3, .vniWindows])
    func nonVietnameseNonAsciiBecomesSingleQuestionMark(_ table: CodeTable) {
        let r = Converter.convertDetailed("a©°½ü€😀👨‍👩‍👧b", from: .unicode, to: table)
        #expect(r.text == "a???????b")
        #expect(r.substitutedCount == 7)
        // The plain API gives the same text.
        #expect(Converter.convert("a©b", from: .unicode, to: table) == "a?b")
    }

    @Test func vietnameseLettersAreNotSubstituted() {
        let r = Converter.convertDetailed("Tiếng Việt đẹp", from: .unicode, to: .tcvn3)
        #expect(r.substitutedCount == 0)
        #expect(!r.text.contains("?"))
    }

    @Test func unicodeTargetsDoNotSubstitute() {
        let r = Converter.convertDetailed("©😀", from: .unicode, to: .unicodeCompound)
        #expect(r.text == "©😀")
        #expect(r.substitutedCount == 0)
    }

    // MARK: - 7. Engine coverage: uppercase, y-nặng, edit sequences

    static let upperCases: [(table: String, keys: String, want: [UInt32])] = [
        ("tcvn3", "VIEEJT", [0x56, 0x49, 0xA3, 0xD6, 0x54]),
        ("tcvn3", "DDUWOWCJ", [0xA7, 0xA6, 0xA5, 0xEE, 0x43]),
        ("tcvn3", "NGUYEENX", [0x4E, 0x47, 0x55, 0x59, 0xA3, 0xD4, 0x4E]),
        ("tcvn3", "yj", [0xFE]),
        ("tcvn3", "YJ", [0x59, 0xFE]),
        ("tcvn3", "thuyj", [0x74, 0x68, 0xF4, 0x79]),
        ("vniWindows", "VIEEJT", [0x56, 0x49, 0x45, 0xC4, 0x54]),
        ("vniWindows", "DDUWOWCJ", [0xD1, 0xD6, 0xD4, 0xCF, 0x43]),
        ("vniWindows", "NGUYEENX", [0x4E, 0x47, 0x55, 0x59, 0x45, 0xC3, 0x4E]),
        ("vniWindows", "yj", [0xEE]),
        ("vniWindows", "YJ", [0xCE]),
        ("vniWindows", "thuyj", [0x74, 0x68, 0x75, 0xEF, 0x79]),
        ("cp1258", "VIEEJT", [0x56, 0x49, 0xCA, 0x0323, 0x54]),
        ("cp1258", "DDUWOWCJ", [0x0110, 0x01AF, 0x01A0, 0x0323, 0x43]),
        ("cp1258", "NGUYEENX", [0x4E, 0x47, 0x55, 0x59, 0xCA, 0x0303, 0x4E]),
        ("cp1258", "yj", [0x79, 0x0323]),
        ("cp1258", "YJ", [0x59, 0x0323]),
        ("cp1258", "thuyj", [0x74, 0x68, 0x75, 0x0323, 0x79]),
    ]

    @Test(arguments: EncodingFixesTests.upperCases)
    func uppercaseAndYNang(_ c: (table: String, keys: String, want: [UInt32])) {
        #expect(Self.run(c.keys, table: c.table) == c.want, "\(c.table) \(c.keys)")
    }

    static let editCases: [(table: String, keys: String, want: [UInt32])] = [
        // tosf: tó then f changes the tone to huyền -> tò
        ("tcvn3", "tosf", [0x74, 0xDF]),
        ("vniWindows", "tosf", [0x74, 0x6F, 0xF8]),
        ("cp1258", "tosf", [0x74, 0x6F, 0x0300]),
        // tosf then Backspace drops the f -> tó again
        ("tcvn3", "tosf\u{8}", [0x74, 0xE3]),
        ("vniWindows", "tosf\u{8}", [0x74, 0x6F, 0xF9]),
        ("cp1258", "tosf\u{8}", [0x74, 0x6F, 0x0301]),
        // vieetj, Backspace drops the j, then s -> viết
        ("tcvn3", "vieetj\u{8}s", [0x76, 0x69, 0xD5, 0x74]),
        ("vniWindows", "vieetj\u{8}s", [0x76, 0x69, 0x65, 0xE1, 0x74]),
        ("cp1258", "vieetj\u{8}s", [0x76, 0x69, 0xEA, 0x0301, 0x74]),
    ]

    @Test(arguments: EncodingFixesTests.editCases)
    func editSequences(_ c: (table: String, keys: String, want: [UInt32])) {
        #expect(Self.run(c.keys, table: c.table) == c.want, "\(c.table) \(c.keys.debugDescription)")
    }
}
