// Telex.swift — the Telex interpreter (design spec Part A §2).
//
// The composing word is re-derived from scratch on every keystroke by folding
// the raw key list into a `Composition` (ordered letter cells + a syllable
// tone). This makes tone re-placement, diacritic restore after backspace, and
// double-strike undo fall out of a deterministic left-to-right fold — never a
// surgical edit of a buffer (spec §1, §8).

/// One letter slot in the composing word.
struct Cell: Equatable {
    var isVowel: Bool
    var base: BaseVowel       // meaningful when isVowel
    var mark: VowelMark       // meaningful when isVowel
    var consonant: Character  // meaningful when !isVowel (lowercase)
    var dStroke: Bool         // consonant 'd' rendered as đ
    var isUpper: Bool

    static func vowel(_ base: BaseVowel, _ mark: VowelMark, upper: Bool) -> Cell {
        Cell(isVowel: true, base: base, mark: mark, consonant: " ", dStroke: false, isUpper: upper)
    }
    static func cons(_ c: Character, upper: Bool, dStroke: Bool = false) -> Cell {
        Cell(isVowel: false, base: .a, mark: .none, consonant: c, dStroke: dStroke, isUpper: upper)
    }
}

/// The derived form of the composing word.
struct Composition: Equatable {
    var cells: [Cell] = []
    var tone: Tone = .ngang
}

/// The effect the previous key produced — used for double-strike detection.
private enum Effect: Equatable {
    case start
    case base                                  // appended a plain base vowel / consonant
    case toneKey(Character)                    // set a tone via this key
    case removeTone
    case mark(key: Character, targets: [Int])  // applied circumflex/breve/horn
    case wInsert(index: Int)                   // bare w inserted a fresh ư vowel
    case dstroke(index: Int)                   // dd -> đ
    case literal                               // a double-strike undo emitted a literal
}

enum Telex {
    private static let toneKeys: [Character: Tone] = [
        "s": .sac, "f": .huyen, "r": .hoi, "x": .nga, "j": .nang,
    ]

    /// Fold the raw key list into a `Composition`.
    static func fold(
        _ keys: [Character], quickTelex: Bool = false,
        quickStartConsonant: Bool = false, quickEndConsonant: Bool = false,
        allowFreeToneMark: Bool = true, freeMarkAcrossCoda: Bool = false,
        literalAfterCancel: Bool = false, committing: Bool = false
    ) -> Composition {
        var cells: [Cell] = []
        var tone: Tone = .ngang
        var prevChar: Character = " "
        var prevEffect: Effect = .start
        // `literalAfterCancel` (OpenKey-compatible cancel semantics, see
        // DECISIONS.md): once a same-key double-strike CANCELS a tone/mark
        // (`Effect.literal` — the same signal every existing double-strike
        // "undo" branch already returns, and only those branches), every
        // LATER key of this word bypasses `apply` entirely and is taken
        // literally. `cancelled` is a plain local — re-derived from `keys`
        // on every fold call like everything else here — so backspacing past
        // the cancelling keystroke naturally re-folds without it (see
        // `Engine.rerender`).
        var cancelled = false

        for ch in keys {
            let up = ch.isUppercase
            let lo = Character(ch.lowercased())
            let effect: Effect
            if literalAfterCancel && cancelled {
                cells.append(SyllableOps.literalCell(lo, upper: up))
                effect = .literal
            } else {
                effect = apply(lo, upper: up, prevChar: prevChar,
                               prevEffect: prevEffect, cells: &cells, tone: &tone,
                               quickTelex: quickTelex,
                               quickStartConsonant: quickStartConsonant,
                               quickEndConsonant: quickEndConsonant,
                               allowFreeToneMark: allowFreeToneMark,
                               freeMarkAcrossCoda: freeMarkAcrossCoda,
                               committing: committing)
                if literalAfterCancel && effect == .literal { cancelled = true }
            }
            prevChar = lo
            prevEffect = effect
        }
        return Composition(cells: cells, tone: tone)
    }

    // MARK: - Per-key application

    private static func apply(
        _ lo: Character, upper up: Bool,
        prevChar: Character, prevEffect: Effect,
        cells: inout [Cell], tone: inout Tone,
        quickTelex: Bool,
        quickStartConsonant: Bool = false,
        quickEndConsonant: Bool = false,
        allowFreeToneMark: Bool = true,
        freeMarkAcrossCoda: Bool = false,
        committing: Bool = false
    ) -> Effect {

        // 0. Start-consonant shortcut (Telex "gõ tắt phụ âm đầu"), onset only.
        // Fires ONLY when this is the word's very first keystroke (cells is
        // still empty) — f/j/w otherwise mean huyền/nặng/horn, so this must
        // run before any of that per-key logic.
        if quickStartConsonant, cells.isEmpty {
            switch lo {
            case "f":
                cells.append(.cons("p", upper: up)); cells.append(.cons("h", upper: false))
                return .base
            case "j":
                cells.append(.cons("g", upper: up)); cells.append(.vowel(.i, .none, upper: false))
                return .base
            case "w":
                cells.append(.cons("q", upper: up)); cells.append(.vowel(.u, .none, upper: false))
                return .base
            default:
                break
            }
        }

        // 1. Tone keys s/f/r/x/j
        if let newTone = toneKeys[lo] {
            guard SyllableOps.hasVowel(cells) else {
                cells.append(.cons(lo, upper: up)); return .base
            }
            // double-strike: same tone key again clears the tone + emits literal
            if case .toneKey(let k) = prevEffect, k == lo, tone == newTone {
                tone = .ngang
                cells.append(.cons(lo, upper: up))
                return .literal
            }
            let coda = SyllableOps.currentCoda(cells)
            if Phonology.toneAllowed(newTone, coda: coda) {
                tone = newTone
                return .toneKey(lo)
            } else {
                cells.append(.cons(lo, upper: up))   // illegal tone here → literal
                return .base
            }
        }

        // 2. z — remove tone (default: does not strip quality marks)
        if lo == "z" {
            if SyllableOps.hasVowel(cells) && tone != .ngang {
                tone = .ngang
                return .removeTone
            }
            cells.append(.cons("z", upper: up)); return .base
        }

        // 3. w — horn / breve / bare ư
        if lo == "w" {
            // Standard Telex double-strike: bare w inserted a fresh ư last
            // time (nothing to horn/breve, so it appended a new vowel rather
            // than marking an existing one) — a second w undoes THAT
            // insertion and leaves one literal w, e.g. ww -> w, tww -> tw.
            // This is distinct from the .mark double-strike right below,
            // which undoes a horn/breve applied to an EXISTING vowel
            // (uww -> uw, aww -> aw).
            if case .wInsert(let idx) = prevEffect, idx < cells.count {
                cells.remove(at: idx)
                cells.append(.cons("w", upper: up))
                return .literal
            }
            // double-strike undo
            if case .mark(let k, let targets) = prevEffect, k == "w" {
                for t in targets where t < cells.count { cells[t].mark = .none }
                cells.append(.cons("w", upper: up)); return .literal
            }
            // uo -> ươ (both horns)
            if let (ui, oi) = SyllableOps.adjacentUO(cells) {
                cells[ui].mark = .horn; cells[oi].mark = .horn
                if SyllableOps.marksLegal(cells) { return .mark(key: "w", targets: [ui, oi]) }
                cells[ui].mark = .none; cells[oi].mark = .none   // revert
            }
            // Apply breve(a) / horn(o,u) to the eligible vowel that keeps the
            // (qu/gi-folded) nucleus valid, trying nearest-to-end first. This
            // resolves the target for marks typed non-adjacently: hoaw→hoă,
            // nuaw→nưa (uă invalid → horn the u instead), toiws→tới (horn the o
            // past the offglide i), quawng→quăng (glide u skipped, breve the a).
            for vi in cells.indices.reversed() where cells[vi].isVowel && cells[vi].mark == .none {
                let m: VowelMark? = (cells[vi].base == .a) ? .breve
                    : (cells[vi].base == .o || cells[vi].base == .u) ? .horn : nil
                guard let mark = m else { continue }
                let isQuGlide = cells[vi].base == .u && vi > 0
                    && !cells[vi - 1].isVowel && cells[vi - 1].consonant == "q"
                if isQuGlide { continue }
                let adjacent = vi == SyllableOps.lastVowelIndex(cells)
                if !adjacent && !allowFreeToneMark { continue }
                cells[vi].mark = mark
                if SyllableOps.marksLegal(cells),
                   Phonology.isNucleusPrefix(SyllableOps.foldedNucleusLetters(cells)) {
                    return .mark(key: "w", targets: [vi])
                }
                cells[vi].mark = .none
            }
            // bare w → insert ư (a fresh vowel, not a mark on an existing
            // one — tracked separately as `.wInsert` so a following w undoes
            // the insertion itself, per standard Telex ww -> w)
            cells.append(.vowel(.u, .horn, upper: up))
            return .wInsert(index: cells.count - 1)
        }

        // 4. [ → ơ direct key
        if lo == "[" {
            if let vi = SyllableOps.lastVowelIndex(cells), cells[vi].base == .o, cells[vi].mark == .none {
                cells[vi].mark = .horn
                if SyllableOps.marksLegal(cells) { return .mark(key: "[", targets: [vi]) }
                cells[vi].mark = .none
            }
            cells.append(.vowel(.o, .horn, upper: up))
            return .mark(key: "[", targets: [cells.count - 1])
        }

        // 5. ] → ư direct key
        if lo == "]" {
            if let vi = SyllableOps.lastVowelIndex(cells), cells[vi].base == .u, cells[vi].mark == .none {
                cells[vi].mark = .horn
                if SyllableOps.marksLegal(cells) { return .mark(key: "]", targets: [vi]) }
                cells[vi].mark = .none
            }
            cells.append(.vowel(.u, .horn, upper: up))
            return .mark(key: "]", targets: [cells.count - 1])
        }

        // 6. d — dd → đ, ddd → dd
        if lo == "d" {
            if case .dstroke(let idx) = prevEffect, idx < cells.count {
                cells[idx].dStroke = false               // undo đ
                cells.append(.cons("d", upper: up))
                return .literal
            }
            if let di = SyllableOps.onsetDIndex(cells) {
                // Fire on adjacent dd, or when the syllable is already closed (a
                // coda exists): dd→đ, dangd→đang, được/đường at commit. A lone d
                // after an OPEN syllable (English "dad", "did", "deed") stays a
                // literal letter so those words aren't turned into đa/đi/đê. The
                // closed-syllable branch is non-adjacent (the d isn't right
                // before the 9/d trigger) and gated by allowFreeToneMark.
                //
                // `freeMarkAcrossCoda` (opt-in, default off) extends this to a
                // still-OPEN syllable too — the onset `d` already exists (the
                // `if let di =` above), so a non-adjacent trigger strokes it
                // regardless of whether a coda has formed yet: dadng→đang.
                // Accepted tradeoff: dad→đa (see DECISIONS.md).
                let adjacent = di == cells.count - 1
                let closedSyllable = !SyllableOps.currentCoda(cells).isEmpty
                if adjacent || (allowFreeToneMark && closedSyllable) || freeMarkAcrossCoda {
                    cells[di].dStroke = true
                    return .dstroke(index: di)
                }
            }
            cells.append(.cons("d", upper: up)); return .base
        }

        // 7. Vowel letters a/e/i/o/u/y
        if let bv = BaseVowel(lo) {
            let canCirc = (bv == .a || bv == .e || bv == .o)   // circumflex only for a/e/o

            // Double-strike undo: the same circumflex key again removes the mark
            // (on whichever vowel it landed on) and emits a literal base vowel.
            if canCirc, case .mark(let k, let targets) = prevEffect, k == lo,
               let ti = targets.first, ti < cells.count,
               cells[ti].isVowel, cells[ti].base == bv, cells[ti].mark == .circumflex {
                cells[ti].mark = .none
                cells.append(.vowel(bv, .none, upper: up))
                return .literal
            }

            // The circumflex target must be in the CURRENT (trailing) nucleus —
            // the matching vowel with no consonant between it and the buffer end.
            // This keeps roiof→rồi, toio→tôi (mark within the same vowel run)
            // while leaving English "mama"/"nana"/"nono" alone (the earlier a/o
            // is across a consonant, so no circumflex is injected).
            var ei: Int? = nil
            if canCirc {
                for i in cells.indices.reversed() {
                    if !cells[i].isVowel { break }
                    if cells[i].base == bv && cells[i].mark == .none { ei = i; break }
                }
            }
            if let ei {
                // Apply when it's the immediately-preceding vowel (adjacent
                // double: oo→ô, aa→â, ee→ê) OR treating this key as a *new*
                // nucleus vowel would not form a legal nucleus (so the user meant
                // a mark: roiof→rồi). Real triphthongs (ngoaos→ngoáo) append.
                let adjacent = ei == SyllableOps.lastVowelIndex(cells)
                let appended = SyllableOps.vowelLetters(cells) + String(bv.letter)
                if adjacent || (allowFreeToneMark && !Phonology.isNucleusPrefix(appended)) {
                    cells[ei].mark = .circumflex
                    if SyllableOps.marksLegal(cells),
                       adjacent || Phonology.isNucleusPrefix(SyllableOps.vowelLetters(cells)) {
                        return .mark(key: lo, targets: [ei])
                    }
                    cells[ei].mark = .none   // reject → fall through to append
                }
            }

            // `freeMarkAcrossCoda` (opt-in) fallback: the search above only
            // looks within the trailing (uninterrupted) vowel run and found
            // nothing. Now search back across ALL cells — crossing a consonant
            // coda on purpose — for the last vowel with the same base and no
            // mark yet, genuinely across a coda (there is at least one
            // consonant between it and the buffer end; otherwise it would
            // already have been found above, so this never overlaps that
            // within-nucleus path). This is what makes `trene`→trên possible.
            //
            // DEFERRED TO COMMIT (`committing`): this across-coda circumflex is
            // applied ONLY at the word boundary (`Engine.finalize`), never in
            // the per-keystroke `Engine.rerender` (which passes committing =
            // false). "tana" and "trene" therefore stay literal WHILE typing
            // and become "tân"/"trên" only when the syllable is committed — so
            // an English word passing through the same V-C-V shape (`manager`)
            // never flashes pseudo-Vietnamese ("mân"/"mâng") mid-word: at
            // commit it folds to "mânger", fails validity, and reverts to raw.
            // The within-nucleus circumflex (aa→â, treen→trên) and the đ-stroke
            // both stay eager — only this across-coda vowel mark waits.
            // See DECISIONS.md "Deferred across-coda circumflex (smooth typing)".
            if ei == nil, canCirc, freeMarkAcrossCoda, committing {
                var acrossCoda: Int? = nil
                for i in cells.indices.reversed() {
                    guard cells[i].isVowel, cells[i].base == bv, cells[i].mark == .none else { continue }
                    let hasConsonantAfter = cells[(i + 1)...].contains { !$0.isVowel }
                    if hasConsonantAfter { acrossCoda = i; break }
                }
                if let ai = acrossCoda {
                    cells[ai].mark = .circumflex
                    if SyllableOps.marksLegal(cells) {
                        return .mark(key: lo, targets: [ai])   // consume the key, no append
                    }
                    cells[ai].mark = .none   // reject → fall through to append
                }
            }

            cells.append(.vowel(bv, .none, upper: up))
            return .base
        }

        // 8. Any other consonant

        // 8a. End-consonant shortcut ("gõ tắt phụ âm cuối"), coda only. Fires
        // ONLY right after a vowel (the nucleus just closed) — this is what
        // keeps ordinary words safe: "tong" (t-o-n-g) stays tong because that
        // g follows "n", not a vowel, while "tog" (t-o-g) expands to "tong".
        if quickEndConsonant, cells.last?.isVowel == true {
            switch lo {
            case "g":
                cells.append(.cons("n", upper: up)); cells.append(.cons("g", upper: false))
                return .base
            case "h":
                cells.append(.cons("n", upper: up)); cells.append(.cons("h", upper: false))
                return .base
            case "k":
                cells.append(.cons("c", upper: up)); cells.append(.cons("h", upper: false))
                return .base
            default:
                break
            }
        }

        if quickTelex, prevChar == lo,
           let last = cells.indices.last, !cells[last].isVowel,
           cells[last].consonant == lo, !cells[last].dStroke {
            switch lo {
            case "c", "k", "p", "t": cells.append(.cons("h", upper: up)); return .base
            case "n":                cells.append(.cons("g", upper: up)); return .base
            case "g":                cells.append(.vowel(.i, .none, upper: up)); return .base
            case "q":                cells.append(.vowel(.u, .none, upper: up)); return .base
            default: break
            }
        }
        cells.append(.cons(lo, upper: up))
        return .base
    }
}
