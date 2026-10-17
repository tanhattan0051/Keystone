// SyllableOps.swift — syllable-shape helpers shared by the Telex and VNI
// interpreters (design spec Part A §2, §3).
//
// These operate purely on the folded `[Cell]` buffer and carry no
// input-method-specific logic, so both `Telex.fold` and `VNI.fold` reuse them
// verbatim instead of each re-deriving vowel/coda/mark-legality rules.

enum SyllableOps {

    static func hasVowel(_ cells: [Cell]) -> Bool { cells.contains { $0.isVowel } }

    static func lastVowelIndex(_ cells: [Cell]) -> Int? {
        cells.lastIndex { $0.isVowel }
    }

    /// Trailing consonant cells after the last vowel, as a lowercase string.
    static func currentCoda(_ cells: [Cell]) -> String {
        guard let vi = lastVowelIndex(cells) else { return "" }
        var s = ""
        for c in cells[(vi + 1)...] where !c.isVowel {
            s.append(c.dStroke ? "đ" : c.consonant)
        }
        return s
    }

    /// Indices of an adjacent u(base)+o(base) pair (mark none), for ươ formation.
    static func adjacentUO(_ cells: [Cell]) -> (Int, Int)? {
        for i in cells.indices.dropLast() {
            let a = cells[i], b = cells[i + 1]
            if a.isVowel, b.isVowel, a.base == .u, b.base == .o,
               a.mark == .none, b.mark == .none {
                // A `qu`-glide u must stay `u` (qươ is impossible — q is always
                // followed by u). Skip this pair so only the o gets the horn,
                // yielding quơ/quở rather than a broken qươ.
                let uIsQuGlide = i > 0 && !cells[i - 1].isVowel && cells[i - 1].consonant == "q"
                if uIsQuGlide { continue }
                return (i, i + 1)
            }
        }
        return nil
    }

    /// The index of an onset `d` (a plain d consonant with no vowel before it,
    /// not yet đ) — the target for a đ-stroke whether the trigger key is adjacent
    /// (dd), later in the word (dangd), or mid-word (dadng). Vietnamese đ is only
    /// ever an onset, so a `d` that follows a vowel (e.g. English "add") is left
    /// literal.
    static func onsetDIndex(_ cells: [Cell]) -> Int? {
        guard let di = cells.firstIndex(where: {
            !$0.isVowel && $0.consonant == "d" && !$0.dStroke
        }) else { return nil }
        if cells[..<di].contains(where: { $0.isVowel }) { return nil }
        return di
    }

    /// The written nucleus letters after folding a qu/gi glide out of the vowel
    /// run (the u of qu, the i of gi are onset glides, not nucleus vowels). Used
    /// to validity-gate mark application so `quăng` (glide u → nucleus "ă",
    /// valid) and `nữa` (real u → nucleus "ưa", valid) resolve correctly while
    /// an impossible "uă" is rejected. It is the ONLY form the nucleus-prefix
    /// checks of both interpreters (Telex circumflex/w, VNI 6/7/8) should use:
    /// the unfolded run would include gi's i ("iây" is no nucleus, "ây" is) and
    /// reject giayas/giay61.
    ///
    /// `foldingQu: false` folds only gi's glide. The Telex non-adjacent
    /// circumflex test needs that: it asks "would this repeated vowel be a new
    /// nucleus vowel?", and folding qu's u there turns English `queue` ("u" is
    /// no nucleus vowel, "eu"+"e" is not a prefix) into quêu. No Vietnamese
    /// syllable is lost by leaving qu unfolded in that one test (quaya and the
    /// rest of the qu set already worked on the unfolded run).
    static func foldedNucleusLetters(_ cells: [Cell], foldingQu: Bool = true) -> String {
        let vowelIdx = cells.indices.filter { cells[$0].isVowel }
        guard let first = vowelIdx.first else { return "" }
        let onset = cells[..<first].filter { !$0.isVowel }
        var letters = vowelIdx.map { NFC.qualityLetter(cells[$0].base, cells[$0].mark) }
        if foldingQu, onset.last?.consonant == "q", vowelIdx.count >= 2,
           cells[vowelIdx[0]].base == .u, cells[vowelIdx[0]].mark == .none {
            letters.removeFirst()
        } else if onset.count == 1, onset[0].consonant == "g", vowelIdx.count >= 2,
                  cells[vowelIdx[0]].base == .i, cells[vowelIdx[0]].mark == .none {
            letters.removeFirst()
        }
        return String(letters)
    }

    /// The cell a key produces when Telex/VNI transforms are suppressed (see
    /// `EngineConfig.literalAfterCancel`): a vowel letter (a/e/i/o/u/y)
    /// becomes a plain, unmarked vowel cell; everything else (consonants,
    /// VNI's digit keys, Telex's `[`/`]` direct keys) becomes a plain
    /// consonant-slot cell holding that character verbatim. This is exactly
    /// what every existing double-strike "literal" branch in
    /// `Telex.fold`/`VNI.fold` already builds by hand for the cancelling
    /// keystroke itself; `literalAfterCancel` reuses it for every keystroke
    /// AFTER the cancel too.
    static func literalCell(_ lo: Character, upper: Bool) -> Cell {
        if let bv = BaseVowel(lo) { return .vowel(bv, .none, upper: upper) }
        return .cons(lo, upper: upper)
    }

    /// At most one quality-marked vowel, unless they form the ươ pair.
    static func marksLegal(_ cells: [Cell]) -> Bool {
        let marked = cells.enumerated().filter { $0.element.isVowel && $0.element.mark != .none }
        if marked.count <= 1 { return true }
        if marked.count == 2 {
            let (i0, a) = marked[0], (i1, b) = marked[1]
            if i1 - i0 == 1, a.base == .u, a.mark == .horn, b.base == .o, b.mark == .horn {
                return true   // ươ
            }
        }
        return false
    }
}
