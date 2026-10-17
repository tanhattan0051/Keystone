// UnicodeTables.swift — the two Unicode output tables (design spec Part A §6).
//
// `UnicodeNFCTable` is the internal canonical / default-live-typing form:
// one precomposed scalar per logical Vietnamese character, built by `NFC`.
//
// `UnicodeCompoundTable` ("Unicode tổ hợp") is the decomposed form some
// legacy-Windows-era software still expects: base letter + combining marks
// in CANONICAL (NFD) order, i.e. sorted by combining class: horn U+031B
// (ccc 216), then dot-below U+0323 (220), then circumflex/breve and the other
// tone marks (230). So ệ = e U+0323 U+0302, ợ = o U+031B U+0323 — the output
// is byte-for-byte `decomposedStringWithCanonicalMapping` of the NFC form.
// It is canonically EQUIVALENT to the NFC form (Unicode's own
// canonical-ordering + composition algorithm reorders/composes it back to
// the identical precomposed string — verified by CodeTableTests' round-trip
// test), just spelled with more code units.

struct UnicodeNFCTable: OutputTable {
    func vowel(base: BaseVowel, mark: VowelMark, tone: Tone, upper: Bool) -> [UInt16] {
        Array(NFC.vowel(base: base, mark: mark, tone: tone, upper: upper).utf16)
    }
    func dStroke(upper: Bool) -> [UInt16] {
        Array(NFC.dStroke(upper: upper).utf16)
    }
    func plain(_ ch: Character) -> [UInt16] {
        Array(String(ch).utf16)
    }
    func decode(_ units: [UInt16]) -> String {
        String(utf16CodeUnits: units, count: units.count)
    }
}

struct UnicodeCompoundTable: OutputTable {
    // Quality marks. They are emitted together with the tone mark in
    // canonical-combining-class order by `vowel` below, not "quality first".
    private static func qualityMark(_ mark: VowelMark) -> Unicode.Scalar? {
        switch mark {
        case .none:       return nil
        case .circumflex: return "\u{0302}"   // ◌̂
        case .breve:      return "\u{0306}"   // ◌̆
        case .horn:       return "\u{031B}"   // ◌̛
        }
    }

    // Canonical combining class of the marks this table emits (UCD).
    private static func combiningClass(_ m: Unicode.Scalar) -> Int {
        switch m.value {
        case 0x031B: return 216   // horn
        case 0x0323: return 220   // dot below
        default:     return 230   // circumflex, breve, grave, acute, hook, tilde
        }
    }

    func vowel(base: BaseVowel, mark: VowelMark, tone: Tone, upper: Bool) -> [UInt16] {
        var s = String(base.letter)
        if upper { s = s.uppercased() }
        var marks: [Unicode.Scalar] = []
        if let q = Self.qualityMark(mark) { marks.append(q) }
        if let t = tone.combining { marks.append(t) }
        // Stable sort by ccc = canonical ordering (quality stays before an
        // equal-ccc tone mark, e.g. ê + U+0301).
        let ordered = marks.enumerated().sorted {
            let (a, b) = (Self.combiningClass($0.element), Self.combiningClass($1.element))
            return a != b ? a < b : $0.offset < $1.offset
        }.map(\.element)
        var out = Array(s.utf16)
        for m in ordered { out += Array(String(m).utf16) }
        return out
    }

    // đ has no combining-stroke form in common use (spec Part A §6): stays
    // precomposed even in the "compound" table.
    func dStroke(upper: Bool) -> [UInt16] {
        Array(NFC.dStroke(upper: upper).utf16)
    }

    func plain(_ ch: Character) -> [UInt16] {
        Array(String(ch).utf16)
    }

    func decode(_ units: [UInt16]) -> String {
        String(utf16CodeUnits: units, count: units.count)
    }
}
