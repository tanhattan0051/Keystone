// VNIWindows.swift — VNI-Windows ("VNI ANSI") output table (design spec
// Part A §6). Cross-verified byte-for-byte against TWO independent sources:
//   1. Wikipedia "VNI" article, §"Character encodings" > "VNI Encoding
//      (Windows/Unix)" table (cites the Vietnamese Unicode FAQs,
//      vietunicode.sourceforge.net/charset/vni.html).
//   2. An independent open-source VNI->Unicode converter
//      (gist.github.com/tbvinh/fab60499cfa30dc86a032fcf18bf7063), whose
//      116-entry byte-sequence -> Unicode table was decoded and compared
//      programmatically against source 1: 0 mismatches.
// No entry below is UNVERIFIED.
//
// Scheme (confirmed by both sources):
//   - Points 0x00-0x7F are plain ASCII ("Points 0x00 through 0x7F follow
//     ASCII" — Wikipedia).
//   - a/e/o + circumflex or breve: [ASCII base letter][one mark byte that
//     fuses the quality AND the tone together], e.g. Ấ = 'A' + 0xC1 (both
//     circumflex and sắc in that single byte). The quality-only (ngang-tone)
//     byte is also a dedicated value (e.g. â = 'a' + 0xE2).
//   - o/u + horn: the horn REPLACES the base letter with its own dedicated
//     byte (ơ=0xF4, Ơ=0xD4, ư=0xF6, Ư=0xD6); an optional tone byte (the same
//     5 generic tone-only bytes used for plain a/e/o/u below) is appended
//     after it, e.g. ờ = 0xF4 + 0xF8.
//   - i: irregular — every tone (incl. huyền/sắc, which coincide with
//     standard Windows-1252 Ì/Í) is a single DEDICATED byte with no base 'i'
//     prefix at all (ì=0xEC, í=0xED, ỉ=0xE6, ĩ=0xF3, ị=0xF2, and uppercase
//     equivalents), since i never carries a quality mark.
//   - y: base 'y'/'Y' + a generic tone byte for huyền/sắc/hỏi/ngã, but nặng
//     is ALSO a dedicated single byte (ỵ=0xEE, Ỵ=0xCE) — this mixed
//     behaviour is exactly what both sources show, so it is reproduced
//     faithfully rather than "regularized".
//   - đ/Đ are dedicated single bytes (0xF1 / 0xD1).
struct VNIWindowsTable: OutputTable {
    // The 5 generic tone-only mark bytes, valid after any bare a/e/i/o/u and
    // after the horn-replaced ơ/ư base bytes.
    private static func toneMarkByte(_ tone: Tone, upper: Bool) -> UInt16? {
        switch tone {
        case .ngang: return nil
        case .huyen: return upper ? 0xD8 : 0xF8
        case .sac:   return upper ? 0xD9 : 0xF9
        case .hoi:   return upper ? 0xDB : 0xFB
        case .nga:   return upper ? 0xD5 : 0xF5
        case .nang:  return upper ? 0xCF : 0xEF
        }
    }

    // Fused circumflex-quality+tone byte (â/ê/ô).
    private static func circumflexByte(_ tone: Tone, upper: Bool) -> UInt16 {
        switch tone {
        case .ngang: return upper ? 0xC2 : 0xE2
        case .huyen: return upper ? 0xC0 : 0xE0
        case .sac:   return upper ? 0xC1 : 0xE1
        case .hoi:   return upper ? 0xC5 : 0xE5
        case .nga:   return upper ? 0xC3 : 0xE3
        case .nang:  return upper ? 0xC4 : 0xE4
        }
    }

    // Fused breve-quality+tone byte (ă).
    private static func breveByte(_ tone: Tone, upper: Bool) -> UInt16 {
        switch tone {
        case .ngang: return upper ? 0xCA : 0xEA
        case .huyen: return upper ? 0xC8 : 0xE8
        case .sac:   return upper ? 0xC9 : 0xE9
        case .hoi:   return upper ? 0xDA : 0xFA
        case .nga:   return upper ? 0xDC : 0xFC
        case .nang:  return upper ? 0xCB : 0xEB
        }
    }

    // Dedicated single byte for every i-tone (no base 'i' prefix, ever).
    private static func iToneByte(_ tone: Tone, upper: Bool) -> UInt16 {
        switch tone {
        case .ngang: return asciiCode("i", upper: upper)
        case .huyen: return upper ? 0xCC : 0xEC
        case .sac:   return upper ? 0xCD : 0xED
        case .hoi:   return upper ? 0xC6 : 0xE6
        case .nga:   return upper ? 0xD3 : 0xF3
        case .nang:  return upper ? 0xD2 : 0xF2
        }
    }

    // Horn-quality base-replacement byte (ngang tone), ơ/ư only.
    private static func hornBase(_ base: BaseVowel, upper: Bool) -> UInt16 {
        switch base {
        case .o: return upper ? 0xD4 : 0xF4
        case .u: return upper ? 0xD6 : 0xF6
        default: return asciiCode(base.letter, upper: upper)
        }
    }

    func vowel(base: BaseVowel, mark: VowelMark, tone: Tone, upper: Bool) -> [UInt16] {
        switch (base, mark) {
        case (.a, .circumflex):
            return [asciiCode("a", upper: upper), Self.circumflexByte(tone, upper: upper)]
        case (.a, .breve):
            return [asciiCode("a", upper: upper), Self.breveByte(tone, upper: upper)]
        case (.e, .circumflex):
            return [asciiCode("e", upper: upper), Self.circumflexByte(tone, upper: upper)]
        case (.o, .circumflex):
            return [asciiCode("o", upper: upper), Self.circumflexByte(tone, upper: upper)]
        case (.o, .horn):
            var out = [Self.hornBase(.o, upper: upper)]
            if let t = Self.toneMarkByte(tone, upper: upper) { out.append(t) }
            return out
        case (.u, .horn):
            var out = [Self.hornBase(.u, upper: upper)]
            if let t = Self.toneMarkByte(tone, upper: upper) { out.append(t) }
            return out
        case (.i, _):
            return [Self.iToneByte(tone, upper: upper)]
        case (.y, _):
            if tone == .nang { return [upper ? 0xCE : 0xEE] }
            var out = [asciiCode("y", upper: upper)]
            if let t = Self.toneMarkByte(tone, upper: upper) { out.append(t) }
            return out
        default:
            // plain a/e/o/u, no quality mark
            var out = [asciiCode(base.letter, upper: upper)]
            if let t = Self.toneMarkByte(tone, upper: upper) { out.append(t) }
            return out
        }
    }

    func dStroke(upper: Bool) -> [UInt16] { [upper ? 0xD1 : 0xF1] }

    func plain(_ ch: Character) -> [UInt16] {
        if let ascii = asciiUnits(ch) { return ascii }
        // Every raw key / consonant the engine passes here is ASCII; this
        // fallback is defensive only and not independently byte-verified.
        return Array(String(ch).utf16)
    }

    func decode(_ units: [UInt16]) -> String { decodeLatin1(units) }
}
