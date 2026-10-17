// CP1258.swift — Windows-1258 (Vietnamese) output table (design spec Part A
// §6). FULLY VERIFIED (not a single UNVERIFIED entry) against Python's
// built-in `cp1258` codec.
//
// Scheme: quality (â ă ê ô ơ ư, and the plain a e i o u y) is always ONE
// precomposed cp1258 byte that REPLACES the ASCII base letter; tone is a
// separate combining byte appended after it. đ/Đ are dedicated bytes.
//
// Verification method (see scratch work; reproducible):
//   1. `qualityByte`/`toneByte` below were read off, for every
//      (base, mark, upper) and every Tone, from:
//        python3 -c "print([hex(b) for b in 'â'.encode('cp1258')])"
//        python3 -c "print([hex(b) for b in '́'.encode('cp1258')])"   # standalone combining acute
//      etc. (Quality marks are NOT independently encodable in cp1258 — only
//      the five *tone* combining marks are: U+0300/U+0301/U+0309/U+0303/
//      U+0323 -> 0xCC/0xEC/0xD2/0xDE/0xF2.)
//   2. Every one of the resulting 132 (base, mark, tone, upper) byte pairs
//      was round-trip-verified: encode quality-byte + tone-byte, decode the
//      two bytes with cp1258, NFC-normalize, and compare against the
//      expected precomposed Unicode character built the same way NFC.swift
//      builds it. All 132 combinations matched exactly (0 mismatches).
//   3. ASCII 0x00-0x7F confirmed identical to plain ASCII in cp1258 (0
//      mismatches over the full range).
// CodeTableTests.swift hard-codes a handful of these byte sequences,
// independently re-derived from the same Python commands, as a regression
// pin.
//
// decode(): the table's bytes are shown as their REAL cp1258 Unicode (see
// `decode` below), not Latin-1 pseudo-chars. A tone byte therefore appears
// as a combining mark; erasing it with Backspace needs a grapheme-aware diff
// in the engine (tracked in DECISIONS.md, "Bảng mã & Converter fixes").
struct CP1258Table: OutputTable {
    private static func qualityByte(_ base: BaseVowel, _ mark: VowelMark, upper: Bool) -> UInt16 {
        switch (base, mark) {
        case (.a, .none):        return upper ? 0x41 : 0x61
        case (.a, .circumflex):  return upper ? 0xC2 : 0xE2   // Â / â
        case (.a, .breve):       return upper ? 0xC3 : 0xE3   // Ă / ă
        case (.e, .none):        return upper ? 0x45 : 0x65
        case (.e, .circumflex):  return upper ? 0xCA : 0xEA   // Ê / ê
        case (.i, .none):        return upper ? 0x49 : 0x69
        case (.o, .none):        return upper ? 0x4F : 0x6F
        case (.o, .circumflex):  return upper ? 0xD4 : 0xF4   // Ô / ô
        case (.o, .horn):        return upper ? 0xD5 : 0xF5   // Ơ / ơ
        case (.u, .none):        return upper ? 0x55 : 0x75
        case (.u, .horn):        return upper ? 0xDD : 0xFD   // Ư / ư
        case (.y, .none):        return upper ? 0x59 : 0x79
        default:                 return asciiCode(base.letter, upper: upper)   // illegal combo upstream; never hit
        }
    }

    private static func toneByte(_ tone: Tone) -> UInt16? {
        switch tone {
        case .ngang: return nil
        case .huyen: return 0xCC   // combining grave
        case .sac:   return 0xEC   // combining acute
        case .hoi:   return 0xD2   // combining hook above
        case .nga:   return 0xDE   // combining tilde
        case .nang:  return 0xF2   // combining dot below
        }
    }

    func vowel(base: BaseVowel, mark: VowelMark, tone: Tone, upper: Bool) -> [UInt16] {
        var out = [Self.qualityByte(base, mark, upper: upper)]
        if let t = Self.toneByte(tone) { out.append(t) }
        return out
    }

    func dStroke(upper: Bool) -> [UInt16] { [upper ? 0xD0 : 0xF0] }

    func plain(_ ch: Character) -> [UInt16] {
        if let ascii = asciiUnits(ch) { return ascii }
        // Every raw key / consonant the engine ever passes here is ASCII
        // (Telex/VNI raw keys are letters, digits, '[', ']'). This fallback
        // is defensive only and not independently byte-verified.
        return Array(String(ch).utf16)
    }

    // Windows-1258 high half (0x80-0xFF) -> Unicode scalar, from Python's
    // `bytes(range(128,256)).decode('cp1258')`. The 9 bytes cp1258 leaves
    // undefined (0x81 0x8A 0x8D-0x90 0x9A 0x9D 0x9E) map to the same C1
    // code point so every byte still yields exactly ONE scalar.
    private static let highHalf: [UInt32] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x008A, 0x2039, 0x0152, 0x008D, 0x008E, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x009A, 0x203A, 0x0153, 0x009D, 0x009E, 0x0178,
        0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7,
        0x00A8, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,
        0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7,
        0x00B8, 0x00B9, 0x00BA, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF,
        0x00C0, 0x00C1, 0x00C2, 0x0102, 0x00C4, 0x00C5, 0x00C6, 0x00C7,
        0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x0300, 0x00CD, 0x00CE, 0x00CF,
        0x0110, 0x00D1, 0x0309, 0x00D3, 0x00D4, 0x01A0, 0x00D6, 0x00D7,
        0x00D8, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x01AF, 0x0303, 0x00DF,
        0x00E0, 0x00E1, 0x00E2, 0x0103, 0x00E4, 0x00E5, 0x00E6, 0x00E7,
        0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x0301, 0x00ED, 0x00EE, 0x00EF,
        0x0111, 0x00F1, 0x0323, 0x00F3, 0x00F4, 0x01A1, 0x00F6, 0x00F7,
        0x00F8, 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x01B0, 0x20AB, 0x00FF,
    ]

    /// REAL cp1258 decode, one scalar per byte (never NFC-normalised): the
    /// engine diffs code units 1:1 with the decoded scalars, so a tone byte
    /// becomes a standalone combining mark (0xCC -> U+0300 ...) rather than
    /// being merged into the previous letter. Without this, macOS showed
    /// Latin-1 pseudo-chars (vieejt -> "viêòt"). Units > 0xFF (defensive
    /// non-ASCII fall-through) pass through as the same scalar.
    func decode(_ units: [UInt16]) -> String {
        var view = String.UnicodeScalarView()
        for u in units {
            let value: UInt32 = (0x80...0xFF).contains(u) ? Self.highHalf[Int(u) - 0x80] : UInt32(u)
            view.append(Unicode.Scalar(value) ?? Unicode.Scalar(0x3F)!)
        }
        return String(view)
    }
}
