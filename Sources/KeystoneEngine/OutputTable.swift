// OutputTable.swift — the output-code-table abstraction (design spec Part A
// §6 "Encoder"). A pure function from a composed (base, mark, tone) triple —
// or a đ, or any literal character — to the target table's CODE UNITS.
//
// Every downstream consumer (the live-typing Engine and the future Converter
// / "Công cụ chuyển mã" tool, spec Part 2.3) renders through the SAME
// `OutputTable` implementation per code table, so the two paths can never
// disagree on a single byte — that sharing is a hard requirement of the
// design spec ("Công cụ chuyển mã và bộ mã hoá của engine phải dùng chung
// một module bảng mã").
//
// `decode` turns the table's own code units back into a Swift `String` the
// input layer can type (CGEventTap posts UTF-16, so even a legacy table's
// raw bytes are carried as one Unicode scalar per byte, U+0000-U+00FF —
// i.e. Latin-1 — never as an actual CP1258/TCVN3/VNI-Windows *decode*).

protocol OutputTable {
    /// The code units for one composed vowel (base + quality mark + tone).
    func vowel(base: BaseVowel, mark: VowelMark, tone: Tone, upper: Bool) -> [UInt16]
    /// đ / Đ.
    func dStroke(upper: Bool) -> [UInt16]
    /// Any non-vowel character: consonants, and literal fall-through/raw-key
    /// characters (restore-if-invalid, boundary punctuation typed as-is).
    func plain(_ ch: Character) -> [UInt16]
    /// This table's code units -> a String the input layer can type.
    func decode(_ units: [UInt16]) -> String
}

func outputTable(for table: CodeTable) -> OutputTable {
    switch table {
    case .unicode:         return UnicodeNFCTable()
    case .unicodeCompound: return UnicodeCompoundTable()
    case .tcvn3:           return TCVN3Table()
    case .vniWindows:      return VNIWindowsTable()
    case .cp1258:          return CP1258Table()
    }
}

// MARK: - Shared helpers for the 8-bit legacy tables (CP1258 / TCVN3 / VNI-Windows)

/// The ASCII code unit for a letter, cased. All three legacy tables keep
/// 0x00-0x7F identical to ASCII (verified for CP1258 with
/// `python3 -c "print([b for b in range(128) if bytes([b]) != chr(b).encode('cp1258')])"`
/// -> `[]`; TCVN3/VNI-Windows are documented "extended ASCII" / "points 0x00
/// through 0x7F follow ASCII" — see TCVN3.swift / VNIWindows.swift headers).
func asciiCode(_ ch: Character, upper: Bool) -> UInt16 {
    let c = upper ? Character(String(ch).uppercased()) : ch
    return UInt16(c.asciiValue ?? 0x3F)   // '?' fallback; never hit for a-z/A-Z
}

/// Byte value `b` (0-255) -> Unicode scalar U+00`b` (Latin-1), per this
/// file's header note: legacy-table code units are carried as raw bytes
/// disguised as Latin-1 scalars, not as an actual decode of the codepage.
func decodeLatin1(_ units: [UInt16]) -> String {
    var view = String.UnicodeScalarView()
    for u in units {
        view.append(Unicode.Scalar(u) ?? Unicode.Scalar(0x3F)!)   // units are always 0-255 in practice
    }
    return String(view)
}

/// Code units for a Character made only of ASCII scalars, one per scalar.
/// `Character.asciiValue` is NOT enough: "\r\n" is a single Character whose
/// asciiValue is 0x0A, which silently turned CRLF into LF. nil = not pure ASCII.
func asciiUnits(_ ch: Character) -> [UInt16]? {
    let scalars = ch.unicodeScalars
    guard scalars.allSatisfy({ $0.isASCII }) else { return nil }
    return scalars.map { UInt16($0.value) }
}
