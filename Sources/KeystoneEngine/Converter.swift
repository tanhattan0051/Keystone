// Converter.swift — pure Unicode Vietnamese text conversion between code
// tables (design spec Part 2.3 "Công cụ chuyển mã"), sharing the exact same
// `OutputTable` the live-typing `Engine` uses (Engine.swift), so the two
// paths can never disagree on a single byte (a hard requirement of the
// design spec).
//
// Legacy table conventions (what the input layer types, and what this file
// converts to/from):
//   - `.cp1258` is the REAL Windows-1258 decode: precomposed quality letters
//     (â ă ê ô ơ ư đ) followed by a combining tone mark (U+0300/0301/0309/
//     0303/0323). Converting FROM cp1258 also accepts the older "Latin-1
//     pseudo-byte" form (each scalar's value IS the cp1258 byte).
//   - `.tcvn3` / `.vniWindows` output carries raw table bytes as Latin-1
//     scalars (U+0000-U+00FF), because the .VnTime / VNI fonts read those
//     code points directly. Any other character cannot be represented and
//     becomes '?' (counted in `ConversionResult.substitutedCount`).

public enum CaseTransform: Sendable {
    case none
    case lower       // chữ thường
    case upper       // chữ HOA
    case title       // Hoa Sau Mỗi Từ
    case sentence    // Hoa đầu câu
}

public struct ConversionResult: Sendable, Equatable {
    public let text: String
    /// Characters replaced by '?' (one per Character, e.g. one emoji = 1).
    public let substitutedCount: Int
}

public enum Converter {
    /// Convert Vietnamese text between code tables, with an optional case
    /// transform applied in between.
    ///
    /// Pipeline: decode `from` to internal Unicode NFC -> apply
    /// `caseTransform` -> re-encode to `to` via the same `OutputTable` the
    /// live-typing engine uses.
    ///
    /// Supported `from` directions (first version — design spec Part A §6
    /// Open Question #4 flags the legacy inverse maps as the risky part):
    /// `.unicode` and `.unicodeCompound` fully (compound is just NFD-ish
    /// combining order, so canonical composition recovers NFC exactly), and
    /// `.cp1258` via a verified inverse of CP1258Table's byte map. `.tcvn3`
    /// and `.vniWindows` do not yet have a confident inverse map — TCVN3's
    /// uppercase byte reuse in particular is only unambiguous going
    /// forward — so converting FROM those two tables is UNSUPPORTED for now
    /// and returns `text` unchanged rather than risk silently wrong output.
    public static func convert(_ text: String, from: CodeTable, to: CodeTable, caseTransform: CaseTransform = .none) -> String {
        convertDetailed(text, from: from, to: to, caseTransform: caseTransform).text
    }

    /// Same as `convert`, plus how many characters had to be replaced by '?'
    /// because the target table (TCVN3 / VNI-Windows) cannot represent them.
    public static func convertDetailed(_ text: String, from: CodeTable, to: CodeTable, caseTransform: CaseTransform = .none) -> ConversionResult {
        guard let nfc = decodeToNFC(text, from: from) else {
            return ConversionResult(text: text, substitutedCount: 0)   // unsupported `from` direction — see doc comment above
        }
        let cased = applyCase(nfc, caseTransform)
        return encode(cased, to: to)
    }

    // MARK: - Decode `from` table to internal NFC

    private static func decodeToNFC(_ text: String, from: CodeTable) -> String? {
        switch from {
        case .unicode:
            return text.precomposedStringWithCanonicalMapping
        case .unicodeCompound:
            return text.precomposedStringWithCanonicalMapping
        case .cp1258:
            return decodeCP1258(text)
        case .tcvn3, .vniWindows:
            return nil   // UNSUPPORTED — no confident inverse map yet
        }
    }

    private static func applyCase(_ text: String, _ transform: CaseTransform) -> String {
        switch transform {
        case .none: return text
        case .lower: return text.lowercased()
        case .upper: return text.uppercased()
        case .title: return capitalizeWords(text)
        case .sentence: return capitalizeSentences(text)
        }
    }

    /// Uppercase the first letter of each word; every other letter is left as
    /// typed (`capitalized` would lowercase the rest: iPhone -> Iphone).
    /// An apostrophe inside a word does not start a new one (don't -> Don't).
    private static func capitalizeWords(_ text: String) -> String {
        var out = ""
        var inWord = false
        for ch in text {
            if ch.isLetter || ch.isNumber {
                out += (!inWord && ch.isLetter) ? ch.uppercased() : String(ch)
                inWord = true
            } else if inWord && (ch == "'" || ch == "\u{2019}") {
                out.append(ch)
            } else {
                out.append(ch)
                inWord = false
            }
        }
        return out
    }

    /// Uppercase the first letter of the text and of every sentence (after
    /// . ! ? … or a line break), skipping spaces, quotes and opening
    /// brackets in between. Nothing else changes.
    private static func capitalizeSentences(_ text: String) -> String {
        let skipped: Set<Character> = ["\"", "'", "\u{201C}", "\u{2018}", "\u{00AB}", "(", "[", "{"]
        var out = ""
        var atStart = true
        for ch in text {
            if atStart && ch.isLetter {
                out += ch.uppercased()
                atStart = false
            } else {
                out.append(ch)
                if ch == "." || ch == "!" || ch == "?" || ch == "\u{2026}" || ch.isNewline {
                    atStart = true
                } else if atStart && !(ch.isWhitespace || skipped.contains(ch)) {
                    atStart = false   // digit, symbol or closing quote: not a sentence start
                }
            }
        }
        return out
    }

    // MARK: - Encode internal NFC to any OutputTable

    /// Reverse map: NFC precomposed vowel Character -> the (base, mark,
    /// tone, upper) tuple that produces it via `NFC.vowel`. Built once from
    /// every legal (base, mark) combination (the same legality list
    /// CP1258Table's Python verification harness used).
    private static let vowelReverse: [Character: (BaseVowel, VowelMark, Tone, Bool)] = {
        let marksByBase: [BaseVowel: [VowelMark]] = [
            .a: [.none, .circumflex, .breve],
            .e: [.none, .circumflex],
            .i: [.none],
            .o: [.none, .circumflex, .horn],
            .u: [.none, .horn],
            .y: [.none],
        ]
        let tones: [Tone] = [.ngang, .huyen, .sac, .hoi, .nga, .nang]
        var map: [Character: (BaseVowel, VowelMark, Tone, Bool)] = [:]
        for (base, marks) in marksByBase {
            for mark in marks {
                for tone in tones {
                    for upper in [false, true] {
                        let s = NFC.vowel(base: base, mark: mark, tone: tone, upper: upper)
                        if s.count == 1, let ch = s.first {
                            map[ch] = (base, mark, tone, upper)
                        }
                    }
                }
            }
        }
        return map
    }()

    private static func encode(_ text: String, to code: CodeTable) -> ConversionResult {
        let table = outputTable(for: code)
        // TCVN3 / VNI-Windows bytes are read as Latin-1 code points by their
        // fonts, so a stray ©/°/ü/€ would print as another Vietnamese letter.
        let substitutes = (code == .tcvn3 || code == .vniWindows)
        var out = ""
        var substituted = 0
        for ch in text {
            if let (base, mark, tone, upper) = vowelReverse[ch] {
                out += table.decode(table.vowel(base: base, mark: mark, tone: tone, upper: upper))
            } else if ch == "đ" {
                out += table.decode(table.dStroke(upper: false))
            } else if ch == "Đ" {
                out += table.decode(table.dStroke(upper: true))
            } else if let ascii = asciiUnits(ch) {
                out += table.decode(ascii)   // keeps "\r\n" as two units
            } else if substitutes {
                out += "?"
                substituted += 1
            } else {
                out.append(ch)   // Unicode / cp1258 targets carry any other character as-is
            }
        }
        return ConversionResult(text: out, substitutedCount: substituted)
    }

    // MARK: - CP1258 inverse (byte -> NFC)

    /// Scalars that only occur in the real-Unicode cp1258 form: combining
    /// marks, and the precomposed letters whose Latin-1 byte value would be a
    /// different character (ă ơ ư đ and capitals).
    private static func looksLikeRealCP1258(_ scalars: [Unicode.Scalar]) -> Bool {
        scalars.contains {
            switch $0.value {
            case 0x0300...0x036F, 0x0102, 0x0103, 0x0110, 0x0111, 0x01A0, 0x01A1, 0x01AF, 0x01B0: return true
            default: return false
            }
        }
    }

    /// Decode cp1258 text back to Unicode NFC. Accepts both the real form
    /// (precomposed quality letter + combining tone: NFC composes it) and the
    /// older Latin-1 pseudo-byte form (see header), told apart by
    /// `looksLikeRealCP1258`. Text with neither marker (plain ASCII, â ê ô
    /// without tone) decodes identically under both readings.
    private static func decodeCP1258(_ text: String) -> String {
        if looksLikeRealCP1258(Array(text.unicodeScalars)) {
            return text.precomposedStringWithCanonicalMapping
        }
        return decodeCP1258PseudoBytes(text)
    }

    /// Inverse of the old convention, using CP1258Table's verified
    /// quality-byte / tone-byte tables.
    private static func decodeCP1258PseudoBytes(_ text: String) -> String {
        let qualityBytes: [UInt16: (BaseVowel, VowelMark, Bool)] = [
            0x61: (.a, .none, false), 0x41: (.a, .none, true),
            0xE2: (.a, .circumflex, false), 0xC2: (.a, .circumflex, true),
            0xE3: (.a, .breve, false), 0xC3: (.a, .breve, true),
            0x65: (.e, .none, false), 0x45: (.e, .none, true),
            0xEA: (.e, .circumflex, false), 0xCA: (.e, .circumflex, true),
            0x69: (.i, .none, false), 0x49: (.i, .none, true),
            0x6F: (.o, .none, false), 0x4F: (.o, .none, true),
            0xF4: (.o, .circumflex, false), 0xD4: (.o, .circumflex, true),
            0xF5: (.o, .horn, false), 0xD5: (.o, .horn, true),
            0x75: (.u, .none, false), 0x55: (.u, .none, true),
            0xFD: (.u, .horn, false), 0xDD: (.u, .horn, true),
            0x79: (.y, .none, false), 0x59: (.y, .none, true),
        ]
        let toneBytes: [UInt16: Tone] = [0xCC: .huyen, 0xEC: .sac, 0xD2: .hoi, 0xDE: .nga, 0xF2: .nang]

        let scalars = Array(text.unicodeScalars)
        var out = ""
        var i = 0
        while i < scalars.count {
            let b = UInt16(scalars[i].value)
            if b == 0xF0 { out.append("đ"); i += 1; continue }
            if b == 0xD0 { out.append("Đ"); i += 1; continue }
            if let (base, mark, upper) = qualityBytes[b] {
                var tone: Tone = .ngang
                var consumed = 1
                if i + 1 < scalars.count, let t = toneBytes[UInt16(scalars[i + 1].value)] {
                    tone = t
                    consumed = 2
                }
                out += NFC.vowel(base: base, mark: mark, tone: tone, upper: upper)
                i += consumed
                continue
            }
            out.unicodeScalars.append(scalars[i])
            i += 1
        }
        return out.precomposedStringWithCanonicalMapping
    }
}
