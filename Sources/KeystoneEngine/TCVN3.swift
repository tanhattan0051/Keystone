// TCVN3.swift — TCVN3 (ABC / .VnTime-family font encoding) output table
// (design spec Part A §6). Cross-verified byte-for-byte against TWO
// independent published sources that both cite the canonical
// vietunicode.sourceforge.net/charset/ reference:
//   1. github.com/anhskohbo/u-convert (MIT), `TCVN3` parallel character array.
//   2. CRAN package `vietnameseConverter`, `loadEncodingTableVN()`'s
//      `TCVN3_Hex` column (explicitly documented as "adapted from
//      vietunicode.sourceforge.net/charset/").
// All 134 toned-vowel byte sequences in both sources agree exactly. No entry
// below is UNVERIFIED.
//
// Scheme (confirmed by both sources — NOT the same as the "switch to an
// all-caps font" story told for the strict ISO VSCII-3 standard; this is the
// real-world ".VnTime"/ABC byte layout Vietnamese software actually calls
// "TCVN3"):
//   - Points 0x00-0x7F are plain ASCII.
//   - The 6 quality letters (â ă ê ô ơ ư) and đ each get a dedicated
//     "ngang tone" byte, lower AND upper (0xA1-0xAE): e.g. â=0xA9, Â=0xA2.
//   - A LOWERCASE toned vowel (any of a e i o u y, marked or not) is ALWAYS
//     exactly one dedicated byte (0xB0-0xFF), e.g. à=0xB5, ấ=0xCA.
//   - An UPPERCASE toned vowel with NO quality mark is
//     [ASCII uppercase base letter][the *lowercase* toned byte]: e.g.
//     À = 'A' + 0xB5 (2 bytes) — reusing 0xB5, the same byte as à.
//   - An UPPERCASE toned vowel WITH a quality mark is
//     [uppercase quality byte][the *lowercase* toned-quality byte]: e.g.
//     Ấ = 0xA2 ('Â') + 0xCA (the same byte as ấ) — 2 bytes.
//   - đ/Đ are dedicated single bytes (0xAE / 0xA7).
//
// KNOWN LIMITATION: ư is byte 0xAD, which read as Latin-1 is U+00AD SOFT
// HYPHEN. CoreText draws it zero-width, so in a font that is not a real
// .VnTime-family TCVN3 font the letter ư looks missing. 0xAD is the standard
// TCVN3 byte, so it is deliberately NOT changed; see DECISIONS.md
// "Bảng mã & Converter fixes".
struct TCVN3Table: OutputTable {
    private struct Key: Hashable { var base: BaseVowel; var mark: VowelMark; var tone: Tone }

    // Dedicated "ngang" byte for each quality letter (upper, lower).
    private static func qualityByte(_ base: BaseVowel, _ mark: VowelMark, upper: Bool) -> UInt16 {
        switch (base, mark) {
        case (.a, .breve):      return upper ? 0xA1 : 0xA8   // Ă / ă
        case (.a, .circumflex): return upper ? 0xA2 : 0xA9   // Â / â
        case (.e, .circumflex): return upper ? 0xA3 : 0xAA   // Ê / ê
        case (.o, .circumflex): return upper ? 0xA4 : 0xAB   // Ô / ô
        case (.o, .horn):       return upper ? 0xA5 : 0xAC   // Ơ / ơ
        case (.u, .horn):       return upper ? 0xA6 : 0xAD   // Ư / ư
        default:                return asciiCode(base.letter, upper: upper)   // no quality; unreachable here
        }
    }

    // The lowercase-toned dedicated byte for every legal (base, mark, tone)
    // where tone != .ngang. Reused verbatim as the second byte of the
    // uppercase 2-byte form.
    private static let toneByte: [Key: UInt16] = [
        // a (plain)
        Key(base: .a, mark: .none, tone: .huyen): 0xB5,
        Key(base: .a, mark: .none, tone: .sac):   0xB8,
        Key(base: .a, mark: .none, tone: .hoi):   0xB6,
        Key(base: .a, mark: .none, tone: .nga):   0xB7,
        Key(base: .a, mark: .none, tone: .nang):  0xB9,
        // â
        Key(base: .a, mark: .circumflex, tone: .huyen): 0xC7,
        Key(base: .a, mark: .circumflex, tone: .sac):   0xCA,
        Key(base: .a, mark: .circumflex, tone: .hoi):   0xC8,
        Key(base: .a, mark: .circumflex, tone: .nga):   0xC9,
        Key(base: .a, mark: .circumflex, tone: .nang):  0xCB,
        // ă
        Key(base: .a, mark: .breve, tone: .huyen): 0xBB,
        Key(base: .a, mark: .breve, tone: .sac):   0xBE,
        Key(base: .a, mark: .breve, tone: .hoi):   0xBC,
        Key(base: .a, mark: .breve, tone: .nga):   0xBD,
        Key(base: .a, mark: .breve, tone: .nang):  0xC6,
        // e (plain)
        Key(base: .e, mark: .none, tone: .huyen): 0xCC,
        Key(base: .e, mark: .none, tone: .sac):   0xD0,
        Key(base: .e, mark: .none, tone: .hoi):   0xCE,
        Key(base: .e, mark: .none, tone: .nga):   0xCF,
        Key(base: .e, mark: .none, tone: .nang):  0xD1,
        // ê
        Key(base: .e, mark: .circumflex, tone: .huyen): 0xD2,
        Key(base: .e, mark: .circumflex, tone: .sac):   0xD5,
        Key(base: .e, mark: .circumflex, tone: .hoi):   0xD3,
        Key(base: .e, mark: .circumflex, tone: .nga):   0xD4,
        Key(base: .e, mark: .circumflex, tone: .nang):  0xD6,
        // i (plain; i never carries a quality mark)
        Key(base: .i, mark: .none, tone: .huyen): 0xD7,
        Key(base: .i, mark: .none, tone: .sac):   0xDD,
        Key(base: .i, mark: .none, tone: .hoi):   0xD8,
        Key(base: .i, mark: .none, tone: .nga):   0xDC,
        Key(base: .i, mark: .none, tone: .nang):  0xDE,
        // o (plain)
        Key(base: .o, mark: .none, tone: .huyen): 0xDF,
        Key(base: .o, mark: .none, tone: .sac):   0xE3,
        Key(base: .o, mark: .none, tone: .hoi):   0xE1,
        Key(base: .o, mark: .none, tone: .nga):   0xE2,
        Key(base: .o, mark: .none, tone: .nang):  0xE4,
        // ô
        Key(base: .o, mark: .circumflex, tone: .huyen): 0xE5,
        Key(base: .o, mark: .circumflex, tone: .sac):   0xE8,
        Key(base: .o, mark: .circumflex, tone: .hoi):   0xE6,
        Key(base: .o, mark: .circumflex, tone: .nga):   0xE7,
        Key(base: .o, mark: .circumflex, tone: .nang):  0xE9,
        // ơ
        Key(base: .o, mark: .horn, tone: .huyen): 0xEA,
        Key(base: .o, mark: .horn, tone: .sac):   0xED,
        Key(base: .o, mark: .horn, tone: .hoi):   0xEB,
        Key(base: .o, mark: .horn, tone: .nga):   0xEC,
        Key(base: .o, mark: .horn, tone: .nang):  0xEE,
        // u (plain)
        Key(base: .u, mark: .none, tone: .huyen): 0xEF,
        Key(base: .u, mark: .none, tone: .sac):   0xF3,
        Key(base: .u, mark: .none, tone: .hoi):   0xF1,
        Key(base: .u, mark: .none, tone: .nga):   0xF2,
        Key(base: .u, mark: .none, tone: .nang):  0xF4,
        // ư
        Key(base: .u, mark: .horn, tone: .huyen): 0xF5,
        Key(base: .u, mark: .horn, tone: .sac):   0xF8,
        Key(base: .u, mark: .horn, tone: .hoi):   0xF6,
        Key(base: .u, mark: .horn, tone: .nga):   0xF7,
        Key(base: .u, mark: .horn, tone: .nang):  0xF9,
        // y (plain; y never carries a quality mark)
        Key(base: .y, mark: .none, tone: .huyen): 0xFA,
        Key(base: .y, mark: .none, tone: .sac):   0xFD,
        Key(base: .y, mark: .none, tone: .hoi):   0xFB,
        Key(base: .y, mark: .none, tone: .nga):   0xFC,
        Key(base: .y, mark: .none, tone: .nang):  0xFE,
    ]

    func vowel(base: BaseVowel, mark: VowelMark, tone: Tone, upper: Bool) -> [UInt16] {
        let baseCode = asciiCode(base.letter, upper: upper)
        if mark == .none {
            guard tone != .ngang else { return [baseCode] }
            guard let t = Self.toneByte[Key(base: base, mark: mark, tone: tone)] else { return [baseCode] }
            return upper ? [baseCode, t] : [t]
        } else {
            let q = Self.qualityByte(base, mark, upper: upper)
            guard tone != .ngang else { return [q] }
            guard let t = Self.toneByte[Key(base: base, mark: mark, tone: tone)] else { return [q] }
            return upper ? [q, t] : [t]
        }
    }

    func dStroke(upper: Bool) -> [UInt16] { [upper ? 0xA7 : 0xAE] }

    func plain(_ ch: Character) -> [UInt16] {
        if let ascii = asciiUnits(ch) { return ascii }
        // Every raw key / consonant the engine passes here is ASCII; this
        // fallback is defensive only and not independently byte-verified.
        return Array(String(ch).utf16)
    }

    func decode(_ units: [UInt16]) -> String { decodeLatin1(units) }
}
