// VNI.swift — the VNI interpreter (design spec Part A §3).
//
// VNI uses digit keys as marks/tones; letters are NEVER transforms (no
// aa→â — that's digit 6). Mirrors Telex's fold structure (`Telex.swift`):
// the composing word is re-derived from scratch on every keystroke by
// folding the raw key list into a `Composition`, reusing the same
// `SyllableOps` shape helpers Telex uses.
//
// Digit map: 1=sắc 2=huyền 3=hỏi 4=ngã 5=nặng; 6=circumflex (a→â,e→ê,o→ô);
// 7=horn (o→ơ,u→ư, uo→ươ); 8=breve (a→ă); 9=đ; 0=remove tone.
// Double-strike: pressing the same digit again undoes and emits the digit
// literally (a1→á, a11→a1; a6→â, a66→a6; d9→đ, d99→d9).
enum VNI {
    private enum Effect: Equatable {
        case start, base, literal
        case tone(Character)
        case removeTone
        case mark(key: Character, targets: [Int])
        case dstroke(index: Int)
    }
    private static let tones: [Character: Tone] = ["1": .sac, "2": .huyen, "3": .hoi, "4": .nga, "5": .nang]

    static func fold(_ keys: [Character], allowFreeToneMark: Bool = true,
                      freeMarkAcrossCoda: Bool = false,
                      literalAfterCancel: Bool = false) -> Composition {
        var cells: [Cell] = []
        var tone: Tone = .ngang
        var prevChar: Character = " "
        var prevEffect: Effect = .start
        // See Telex.fold's matching comment: `Effect.literal` is exactly (and
        // only) what every digit double-strike cancel below already returns,
        // so it doubles as the "a cancel just fired" signal `literalAfterCancel`
        // needs, with no separate bookkeeping. `cancelled` is a plain local,
        // recomputed from `keys` on every call, so backspacing past the
        // cancelling digit naturally drops back out of literal mode.
        var cancelled = false
        for ch in keys {
            let up = ch.isUppercase
            let lo = Character(ch.lowercased())
            let e: Effect
            if literalAfterCancel && cancelled {
                cells.append(SyllableOps.literalCell(lo, upper: up))
                e = .literal
            } else {
                e = apply(lo, upper: up, prevChar: prevChar, prevEffect: prevEffect, cells: &cells, tone: &tone,
                          allowFreeToneMark: allowFreeToneMark, freeMarkAcrossCoda: freeMarkAcrossCoda)
                if literalAfterCancel && e == .literal { cancelled = true }
            }
            prevChar = lo; prevEffect = e
        }
        return Composition(cells: cells, tone: tone)
    }

    private static func apply(_ lo: Character, upper up: Bool, prevChar: Character, prevEffect: Effect,
                              cells: inout [Cell], tone: inout Tone,
                              allowFreeToneMark: Bool = true, freeMarkAcrossCoda: Bool = false) -> Effect {
        // Tone digits 1..5
        if let newTone = tones[lo] {
            guard SyllableOps.hasVowel(cells) else { cells.append(.cons(lo, upper: up)); return .base }
            if case .tone(let k) = prevEffect, k == lo, tone == newTone {
                tone = .ngang; cells.append(.cons(lo, upper: up)); return .literal   // double-strike undo
            }
            if Phonology.toneAllowed(newTone, coda: SyllableOps.currentCoda(cells)) {
                tone = newTone; return .tone(lo)
            }
            cells.append(.cons(lo, upper: up)); return .base
        }
        // 0 = remove tone
        if lo == "0" {
            if SyllableOps.hasVowel(cells), tone != .ngang { tone = .ngang; return .removeTone }
            cells.append(.cons("0", upper: up)); return .base
        }
        // 6 = circumflex (a/e/o -> â/ê/ô)
        if lo == "6" {
            if case .mark(let k, let targets) = prevEffect, k == "6" {
                for t in targets where t < cells.count { cells[t].mark = .none }
                cells.append(.cons("6", upper: up)); return .literal
            }
            if let vi = cells.lastIndex(where: {
                $0.isVowel && $0.mark == .none && ($0.base == .a || $0.base == .e || $0.base == .o)
            }) {
                let adjacent = vi == SyllableOps.lastVowelIndex(cells)
                cells[vi].mark = .circumflex
                if SyllableOps.marksLegal(cells),
                   adjacent || (allowFreeToneMark && Phonology.isNucleusPrefix(SyllableOps.vowelLetters(cells))) {
                    return .mark(key: "6", targets: [vi])
                }
                cells[vi].mark = .none
            }
            cells.append(.cons("6", upper: up)); return .base
        }
        // 7 = horn (o->ơ, u->ư, uo->ươ)
        if lo == "7" {
            if case .mark(let k, let targets) = prevEffect, k == "7" {
                for t in targets where t < cells.count { cells[t].mark = .none }
                cells.append(.cons("7", upper: up)); return .literal
            }
            if let (ui, oi) = SyllableOps.adjacentUO(cells) {
                cells[ui].mark = .horn; cells[oi].mark = .horn
                if SyllableOps.marksLegal(cells) { return .mark(key: "7", targets: [ui, oi]) }
                cells[ui].mark = .none; cells[oi].mark = .none
            }
            if let vi = SyllableOps.lastVowelIndex(cells), cells[vi].mark == .none,
               (cells[vi].base == .o || cells[vi].base == .u) {
                cells[vi].mark = .horn
                if SyllableOps.marksLegal(cells) { return .mark(key: "7", targets: [vi]) }
                cells[vi].mark = .none
            }
            // Last vowel is an offglide with no target of its own — search
            // backward for an earlier eligible vowel (moi71→mới, gui73→gửi).
            // Non-adjacent by construction, so gated by allowFreeToneMark.
            if allowFreeToneMark, let hi = cells.lastIndex(where: {
                $0.isVowel && $0.mark == .none && ($0.base == .o || $0.base == .u)
            }) {
                let isQuGlide = hi > 0 && !cells[hi - 1].isVowel && cells[hi - 1].consonant == "q"
                if !isQuGlide {
                    cells[hi].mark = .horn
                    if SyllableOps.marksLegal(cells),
                       Phonology.isNucleusPrefix(SyllableOps.vowelLetters(cells)) {
                        return .mark(key: "7", targets: [hi])
                    }
                    cells[hi].mark = .none
                }
            }
            cells.append(.cons("7", upper: up)); return .base
        }
        // 8 = breve (a -> ă)
        if lo == "8" {
            if case .mark(let k, let targets) = prevEffect, k == "8" {
                for t in targets where t < cells.count { cells[t].mark = .none }
                cells.append(.cons("8", upper: up)); return .literal
            }
            if let vi = SyllableOps.lastVowelIndex(cells), cells[vi].mark == .none, cells[vi].base == .a {
                cells[vi].mark = .breve
                if SyllableOps.marksLegal(cells) { return .mark(key: "8", targets: [vi]) }
                cells[vi].mark = .none
            }
            // Backward search for consistency with the 6/7 handlers (gated so
            // it never misfires; no known corpus case currently relies on it).
            // Non-adjacent by construction, so also gated by allowFreeToneMark.
            if allowFreeToneMark, let ai = cells.lastIndex(where: { $0.isVowel && $0.mark == .none && $0.base == .a }) {
                cells[ai].mark = .breve
                if SyllableOps.marksLegal(cells),
                   Phonology.isNucleusPrefix(SyllableOps.vowelLetters(cells)) {
                    return .mark(key: "8", targets: [ai])
                }
                cells[ai].mark = .none
            }
            cells.append(.cons("8", upper: up)); return .base
        }
        // 9 = đ
        if lo == "9" {
            if case .dstroke(let idx) = prevEffect, idx < cells.count {
                cells[idx].dStroke = false; cells.append(.cons("9", upper: up)); return .literal
            }
            if let di = SyllableOps.onsetDIndex(cells) {  // d9 / dang9 → đ on the onset d
                // Adjacent (d then 9) or a closed syllable only — mirrors Telex
                // đ. The closed-syllable branch is non-adjacent and gated by
                // allowFreeToneMark. `freeMarkAcrossCoda` extends this to a
                // still-OPEN syllable too, for parity with Telex's open-syllable
                // đ extension (see Telex.swift case 6).
                let adjacent = di == cells.count - 1
                let closedSyllable = !SyllableOps.currentCoda(cells).isEmpty
                if adjacent || (allowFreeToneMark && closedSyllable) || freeMarkAcrossCoda {
                    cells[di].dStroke = true; return .dstroke(index: di)
                }
            }
            cells.append(.cons("9", upper: up)); return .base
        }
        // Vowel letters -> plain base vowel (VNI never uses letters as marks)
        if let bv = BaseVowel(lo) { cells.append(.vowel(bv, .none, upper: up)); return .base }
        // Any other consonant (incl. w, which is literal in VNI)
        cells.append(.cons(lo, upper: up)); return .base
    }
}
