// Engine.swift — integration glue for the pure Vietnamese input-method engine
// (design spec Part A §1, §7, §8).
//
// The public `Engine` owns the composing word's raw keystrokes and re-derives
// the whole word on every keystroke via `Telex.fold`, then diffs the newly
// rendered text against what is currently on screen to produce a minimal
// (backspaceCount, text) edit. On commit (a non-word boundary character, or
// an explicit flush), the composition is optionally validated against
// `Phonology` and reverted to raw keystrokes if invalid and
// `config.restoreIfInvalid` is set.
//
// Rendering and diffing happen on the active output table's CODE UNITS
// (design spec Part A §6-§7), not on Unicode scalars or `Character`s: a
// legacy/compound table can spell one logical Vietnamese letter as 2-3 code
// units, and `backspaceCount` must count exactly what the input layer will
// delete. For `.unicode` (the live-typing default) a code unit IS a UTF-16
// unit of the NFC string, which for Vietnamese (all-BMP) is byte-for-byte
// identical to the previous scalar-based diff — so this refactor is
// observationally a no-op for the default table (pinned by the full corpus
// suite) while making the legacy tables correct.
//
// Phase 1 supports Telex only; `config.inputMethod` is not yet consulted.

public final class Engine {
    public var config: EngineConfig {
        // Rebuild the macro dictionary only when config changes (off the
        // per-keystroke hot path), not on every keystroke.
        didSet { macroTable = MacroTable(config.macros) }
    }
    private var macroTable: MacroTable

    /// English word list consulted by `finalize`'s restore branch to choose
    /// between the composed and raw spellings (see DECISIONS.md "Restore
    /// chooses the composed word when it is the real one"). Deliberately
    /// OUTSIDE `EngineConfig`: `EngineConfig` is `Codable` (a `Lexicon`
    /// deliberately isn't) and gets rebuilt from scratch on every unrelated
    /// preference change by `AppModel.pushConfig()` — threading a
    /// ~236k-entry word set through that would cost real memory/CPU on every
    /// settings tweak for no benefit, since nothing actually compares two
    /// `EngineConfig` values for equality anywhere in this codebase. `nil`
    /// (the default) keeps every existing restore-if-invalid behavior
    /// byte-identical — this feature is dormant until something (the app)
    /// calls `EngineController.setLexicon`, which the app additionally gates
    /// behind its own `useLexicon` kill switch (see `AppModel`).
    public var lexicon: Lexicon?

    /// Curated force-English whitelist (see SupplementaryWords.forceEnglishWords
    /// and DECISIONS.md "Force-English whitelist (Lớp B)"). When `config.spellCheck`
    /// is on, `finalize` commits the raw English for a word in this list even when
    /// its Vietnamese composition is perfectly valid. Set independently of
    /// `EngineConfig` (like `lexicon`) via `EngineController.setForceEnglish`.
    public var forceEnglish: Lexicon?

    public init(config: EngineConfig) {
        self.config = config
        self.macroTable = MacroTable(config.macros)
    }

    private var rawKeys: [Character] = []   // the composing word's raw keys
    private var prevUnits: [UInt16] = []    // active table's code units currently "on screen"

    /// Whether the engine currently owns an in-progress word (`rawKeys` is
    /// non-empty). `EngineController` reads this, BEFORE calling `process`,
    /// to decide whether a Backspace belongs to the engine (and must be
    /// suppressed even if it turns out to be a no-op edit) or is an ordinary
    /// passthrough Delete with nothing composing (see DECISIONS.md
    /// "Suppress every character the engine took ownership of, even a
    /// no-op one"). Read-only and side-effect free — `Engine` stays pure.
    public var isComposing: Bool { !rawKeys.isEmpty }

    /// Whether the NEXT committed word starts a new sentence — used only by
    /// macro `autoCapitalize` (see `MacroTable.expandedText`). A `.`, `!`,
    /// `?`, or newline boundary starts a new sentence; committing any word
    /// (with any other boundary) means the next one does not.
    private var atSentenceStart = true
    /// Raw keys typed while Vietnamese input is off — the English-mode macro
    /// buffer (see `processInactive`/`flushInactive`), independent of
    /// `rawKeys` above (which only composes while active).
    private var englishRawKeys: [Character] = []

    public func process(_ key: KeyInput) -> EngineResult {
        switch key.kind {
        case .backspace:
            if rawKeys.isEmpty { return .none }
            rawKeys.removeLast()
            return rerender()
        case .character(let ch):
            if isWordChar(ch) {
                rawKeys.append(ch)
                return rerender()
            } else {
                if rawKeys.isEmpty { return EngineResult(backspaceCount: 0, text: String(ch)) }
                return finalize(boundary: ch)   // commit current word, then emit ch literally
            }
        }
    }

    public func flush() -> EngineResult { finalize(boundary: nil) }

    /// Return/KeypadEnter: finalize the current word like `flush()`, but ALSO
    /// force `atSentenceStart = true` — a newline starts a new sentence, even
    /// though the physical Return key (not this method) is what actually
    /// inserts the `\n`. `finalize(boundary: nil)` commits the pending word
    /// without emitting any boundary character, so no `\n` ever ends up in
    /// the returned edit text.
    public func flushNewline() -> EngineResult {
        let r = finalize(boundary: nil)
        atSentenceStart = true
        return r
    }

    public func reset() {
        rawKeys = []; prevUnits = []
        // NOT `true`: a reset fires on a caret move / app switch / nav key,
        // none of which tell the engine it's actually at a sentence start —
        // so the next word must NOT auto-capitalize just because the buffer
        // was cleared. A brand-new `Engine`'s stored-property initial value
        // (above) is left at `true` on purpose: that only affects the very
        // first word of a fresh engine, which existing `AutoCapitalize` tests
        // rely on.
        atSentenceStart = false
        englishRawKeys = []
    }

    // MARK: - English-mode macros (Vietnamese input off)
    //
    // While Vietnamese input is off, keystrokes are never composed/rendered —
    // they pass through physically. But a completed macro trigger can still
    // be replaced at its boundary: this buffer tracks the raw keys of the
    // current word, separately from `rawKeys`/`rerender`.

    /// One keystroke while Vietnamese input is off. Letters/numbers extend
    /// the buffer (always a physical passthrough, `.none`); anything else is
    /// a boundary that may fire a macro.
    public func processInactive(_ key: KeyInput) -> EngineResult {
        switch key.kind {
        case .backspace:
            if !englishRawKeys.isEmpty { englishRawKeys.removeLast() }
            return .none   // the physical Delete always passes through
        case .character(let ch):
            if ch.isLetter || ch.isNumber {
                englishRawKeys.append(ch)
                return .none
            }
            // Boundary key (e.g. space/punctuation) — itself a physical
            // passthrough, so its own text is never part of the edit.
            return matchEnglishMacro(boundary: ch)
        }
    }

    /// Boundary handler for nav/commit keys (Return/Tab/arrows/...), which
    /// carry no character of their own to gate on.
    public func flushInactive() -> EngineResult {
        matchEnglishMacro(boundary: nil)
    }

    /// Return/KeypadEnter counterpart of `flushInactive()` — see
    /// `flushNewline()`'s doc comment for why `atSentenceStart` is forced
    /// `true` here without emitting a `\n` of its own.
    public func flushInactiveNewline() -> EngineResult {
        let r = matchEnglishMacro(boundary: nil)
        atSentenceStart = true
        return r
    }

    public func resetInactive() {
        englishRawKeys = []
    }

    /// Shared match+clear logic for `processInactive`'s boundary case and
    /// `flushInactive`. Always clears the buffer; only returns an edit
    /// (backspace the trigger + insert the expansion) on a hit.
    private func matchEnglishMacro(boundary: Character?) -> EngineResult {
        let raw = String(englishRawKeys)
        let hadWord = !englishRawKeys.isEmpty
        let triggerLength = englishRawKeys.count
        englishRawKeys = []

        guard config.macrosEnabled, let rule = macroTable.match(raw, englishMode: true) else {
            updateSentenceStart(boundary: boundary, hadWord: hadWord)
            return .none
        }
        let expanded = MacroTable.expandedText(
            for: rule, atSentenceStart: atSentenceStart, globalAutoCapitalize: config.macroAutoCapitalize)
        let text = Converter.convert(expanded, from: .unicode, to: config.codeTable)
        updateSentenceStart(boundary: boundary, hadWord: hadWord)
        return EngineResult(backspaceCount: triggerLength, text: text)
    }

    /// Sentence-start tracking for macro `autoCapitalize` only — kept small
    /// and separate from the rest of `finalize`'s logic on purpose.
    private func updateSentenceStart(boundary: Character?, hadWord: Bool) {
        if let b = boundary, isSentenceTerminator(b) {
            atSentenceStart = true
        } else if hadWord {
            atSentenceStart = false
        }
    }

    private func isSentenceTerminator(_ ch: Character) -> Bool {
        ch == "." || ch == "!" || ch == "?" || ch.isNewline
    }

    private func interpret(_ keys: [Character]) -> Composition {
        switch config.inputMethod {
        case .vni: return VNI.fold(keys, allowFreeToneMark: config.allowFreeToneMark,
                                    freeMarkAcrossCoda: config.freeMarkAcrossCoda,
                                    literalAfterCancel: config.literalAfterCancel)
        default:   return Telex.fold(keys, quickTelex: config.quickTelex,
                                      quickStartConsonant: config.quickStartConsonant,
                                      quickEndConsonant: config.quickEndConsonant,
                                      allowFreeToneMark: config.allowFreeToneMark,
                                      freeMarkAcrossCoda: config.freeMarkAcrossCoda,
                                      literalAfterCancel: config.literalAfterCancel)
        }
    }

    // append a word char or handle backspace: re-fold whole word, diff against on-screen
    private func rerender() -> EngineResult {
        let comp = interpret(rawKeys)
        let table = outputTable(for: config.codeTable)
        let newUnits: [UInt16]
        if config.spellCheck && isUnrecoverable(comp) {
            // Eager restore (Phase 7): the composing word can never become a
            // legal Vietnamese syllable, so render the raw keystrokes
            // literally NOW instead of waiting for the word boundary — same
            // raw-rendering `finalize`'s revert-to-raw branch uses, so there
            // is no visual jump when the word boundary is eventually reached
            // (see DECISIONS.md "Eager restore (spellCheck / Phase 7)").
            newUnits = Engine.collapseDoubledLiterals(rawKeys).flatMap { table.plain($0) }
        } else {
            newUnits = encode(comp, table: table)
        }
        let r = diff(prevUnits, newUnits, table: table)
        prevUnits = newUnits
        return r
    }

    /// An OPEN "ươ" (both horns, the u+o pair is the whole nucleus and the o is
    /// the last cell) is not a real Vietnamese nucleus — it is the rare "uơ"
    /// (thuở, huơ, khuơ). We only know the syllable stayed open at commit, so we
    /// downgrade ư→u here; hương/nước/người/rượu keep ươ because they are closed
    /// or carry an offglide (so they never reach this shape).
    private func downgradeOpenUoHorn(_ comp: Composition) -> Composition {
        var comp = comp
        let cells = comp.cells
        let vowels = cells.indices.filter { cells[$0].isVowel }
        guard vowels.count == 2 else { return comp }
        let i = vowels[0], j = vowels[1]
        guard j == i + 1, j == cells.count - 1 else { return comp }
        guard cells[i].base == .u, cells[i].mark == .horn,
              cells[j].base == .o, cells[j].mark == .horn else { return comp }
        if i > 0, !cells[i - 1].isVowel, cells[i - 1].consonant == "q" { return comp }  // qu-glide → keep
        comp.cells[i].mark = .none
        return comp
    }

    // commit: apply macros, then restore-if-invalid, produce the edit that
    // turns on-screen -> final (+ optional boundary char)
    private func finalize(boundary: Character?) -> EngineResult {
        let hadWord = !rawKeys.isEmpty

        // Macros fire at commit against the RAW typed word, before Vietnamese
        // rendering or restore-if-invalid even run — see DECISIONS.md
        // "Macros / gõ tắt". A hit fully replaces whatever is on screen.
        if config.macrosEnabled, let rule = macroTable.match(String(rawKeys), englishMode: false) {
            let expanded = MacroTable.expandedText(
                for: rule, atSentenceStart: atSentenceStart, globalAutoCapitalize: config.macroAutoCapitalize)
            var text = Converter.convert(expanded, from: .unicode, to: config.codeTable)
            if let b = boundary { text.append(b) }
            let bs = prevUnits.count
            rawKeys = []; prevUnits = []
            updateSentenceStart(boundary: boundary, hadWord: hadWord)
            return EngineResult(backspaceCount: bs, text: text)
        }

        let comp = downgradeOpenUoHorn(interpret(rawKeys))
        let table = outputTable(for: config.codeTable)
        // Sentence auto-capitalize (Phase 4): applied at commit, to whichever
        // branch actually wins below, on top of the already-decided isValid
        // result — capitalization never changes validity (see DECISIONS.md).
        let shouldCapitalize = config.autoCapitalize && atSentenceStart && !rawKeys.isEmpty
        // A composition with NO vowel at all (e.g. "w", "tw", "dd" after a
        // double-strike undo) can never be a real Vietnamese syllable, but it
        // also isn't a failed ATTEMPT at one — it's a deliberate literal
        // (standard Telex ww -> w, ddd -> dd). Only a composition that DOES
        // contain a vowel and still fails validity is treated as a failed
        // Vietnamese syllable (i.e. actually an English word) worth
        // protecting via revert-to-raw. See DECISIONS.md "Restore-if-invalid:
        // two layers".
        let compHasVowel = comp.cells.contains { $0.isVowel }
        // Collapse the "doubled-w" habit (ww = one literal w) up front: in
        // Telex `w` is always the ư/horn key, so a "ww" pair is always an
        // escape to a single `w` (the fold already collapses a bare "ww" →
        // "w"). This makes an English word typed with doubled w's revert
        // cleanly — "wwin" → "win", "swwim" → "swim" — while words without a
        // "ww" pair (boss, wrong) are untouched. Shared by both the
        // force-English and restore-if-invalid branches below, and by
        // `revertToRawUnits`.
        let collapsedRawKeys = Engine.collapseDoubledLiterals(rawKeys)
        let rawWord = String(collapsedRawKeys)
        // The composed word is rendered through the UNICODE table regardless
        // of the active code table (a legacy table's ASCII bytes are
        // identical anyway, and this keeps the comparison stable), taken
        // BEFORE capitalization — capitalization is applied after the
        // decision, to whichever branch wins. Shared by both branches below.
        let unicodeTable = outputTable(for: .unicode)
        let composedWordU = unicodeTable.decode(encode(comp, table: unicodeTable))
        // Reverts to the (w-collapsed) raw keystrokes, capitalizing the first
        // one if the word starts a sentence — shared by both branches below.
        func revertToRawUnits() -> [UInt16] {
            var keys = collapsedRawKeys
            if shouldCapitalize, let first = keys.first {
                keys[0] = Character(first.uppercased())
            }
            return keys.flatMap { table.plain($0) }
        }
        let finalUnits: [UInt16]
        if config.spellCheck, !rawKeys.isEmpty, let fe = forceEnglish,
           rawWord.lowercased() != composedWordU.lowercased(),
           fe.contains(rawWord) {
            // Force-English whitelist (Lớp B): the just-typed word composes a
            // VALID Vietnamese syllable (so restore-if-invalid below would
            // never fire for it), but it's a curated English word that must
            // win over that Vietnamese homograph anyway — see DECISIONS.md
            // "Force-English whitelist (Lớp B)". Checked first so it wins
            // over both other branches.
            finalUnits = revertToRawUnits()
        } else if config.restoreIfInvalid && !rawKeys.isEmpty && !isValid(comp) && compHasVowel {
            // Standard Telex tone-CANCEL habit: the user presses the same
            // tone/mark key again once the intended word is showing, so the
            // RAW keystrokes (about to be restored below) include that
            // cancel key and double a letter (task→tassk, google→gooogle).
            // `RestoreDecision` picks the COMPOSED word instead when it is
            // the real one and the raw spelling isn't — see DECISIONS.md
            // "Restore chooses the composed word when it is the real one".
            if RestoreDecision.choose(composed: composedWordU, raw: rawWord, lexicon: lexicon) == .composed {
                finalUnits = encode(capitalized(comp, if: shouldCapitalize), table: table)
            } else {
                finalUnits = revertToRawUnits()
            }
        } else {
            finalUnits = encode(capitalized(comp, if: shouldCapitalize), table: table)
        }
        let common = commonPrefixCount(prevUnits, finalUnits)
        let bs = prevUnits.count - common
        var text = table.decode(Array(finalUnits[common...]))
        if let b = boundary { text.append(b) }
        rawKeys = []; prevUnits = []
        updateSentenceStart(boundary: boundary, hadWord: hadWord)
        return EngineResult(backspaceCount: bs, text: text)
    }

    // A word/transform character for the active method. Everything else is a
    // commit boundary. Telex uses letters + the [ ] direct keys; VNI uses
    // letters + digits (its tone/mark keys), so digits must reach the fold.
    private func isWordChar(_ ch: Character) -> Bool {
        if ch.isLetter { return true }
        switch config.inputMethod {
        case .vni: return ch.isNumber
        default:   return ch == "[" || ch == "]"
        }
    }

    /// Collapse the two Telex "type the transform key extra to get a literal"
    /// escapes, so reverting an invalid word to its raw keystrokes yields the
    /// literal the user actually meant (see `finalize`'s revert-to-raw branch
    /// and `rerender`'s eager restore):
    ///
    ///   - `ww` → `w`: `w` is always the ư/horn transform, so a doubled `w` is
    ///     the escape for one literal `w` — "wwin"/"swwim" revert to "win"/"swim".
    ///   - `ddd` → `dd`: `dd` is the đ transform, so a THIRD `d` undoes the đ and
    ///     leaves two literal `d`s. An English/tech word whose literal starts
    ///     "dd" is therefore typed with a leading "ddd" (its only route, since
    ///     bare "ddos" is the common word "đó" — identical keystrokes). Dropping
    ///     the escape d here reverts "dddos"→"ddos", "dddong"→"ddong". A plain
    ///     "dd" pair (English "add", "buddy") is NOT touched — only a run of
    ///     three. See DECISIONS.md "The ddd→dd escape in raw-restore".
    ///
    /// Case of the kept character(s) is preserved.
    private static func collapseDoubledLiterals(_ keys: [Character]) -> [Character] {
        func isD(_ c: Character) -> Bool { c == "d" || c == "D" }
        func isW(_ c: Character) -> Bool { c == "w" || c == "W" }
        var out: [Character] = []
        var i = 0
        while i < keys.count {
            let ch = keys[i]
            // "ddd" → keep two d's, drop the third (the đ-escape).
            if isD(ch), i + 2 < keys.count, isD(keys[i + 1]), isD(keys[i + 2]) {
                out.append(ch); out.append(keys[i + 1])
                i += 3
                continue
            }
            out.append(ch)
            // "ww" → keep one w, drop the paired second (the horn escape).
            if isW(ch), i + 1 < keys.count, isW(keys[i + 1]) {
                i += 2
                continue
            }
            i += 1
        }
        return out
    }

    /// Sentence-start auto-capitalize (Phase 4): uppercases the first cell,
    /// unless it already is one. Shared by `finalize`'s two composed-output
    /// paths (the ordinary commit, and the restore branch's composed winner)
    /// so capitalization is applied identically either way, always AFTER the
    /// restore decision itself (which compares the un-capitalized forms).
    private func capitalized(_ comp: Composition, if shouldCapitalize: Bool) -> Composition {
        var comp = comp
        if shouldCapitalize, !comp.cells.isEmpty, !comp.cells[0].isUpper {
            comp.cells[0].isUpper = true
        }
        return comp
    }

    private func commonPrefixCount<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        var i = 0; let m = min(a.count, b.count)
        while i < m && a[i] == b[i] { i += 1 }
        return i
    }

    private func diff(_ prev: [UInt16], _ new: [UInt16], table: OutputTable) -> EngineResult {
        let i = commonPrefixCount(prev, new)
        let bs = prev.count - i
        let text = table.decode(Array(new[i...]))
        return EngineResult(backspaceCount: bs, text: text)
    }

    // MARK: - Parse / render / validity

    private struct Parsed {
        var onsetString: String          // "", "ch", "qu", "gi", "đ", "ngh", ...
        var firstNucleus: BaseVowel?
        var nucleusIdx: [Int]            // tone-eligible cell indices (folded qu/gi glide EXCLUDED)
        var glideIndex: Int?
        var nucleusString: String        // written nucleus e.g. "ươ","uyê","iê"
        var codaString: String
        var hasConsonantCoda: Bool
        var trailingVowelAfterCoda: Bool
    }

    private func parse(_ cells: [Cell]) -> Parsed {
        var i = 0
        var onsetCells: [Int] = []
        while i < cells.count && !cells[i].isVowel { onsetCells.append(i); i += 1 }
        var vowelIdx: [Int] = []
        while i < cells.count && cells[i].isVowel { vowelIdx.append(i); i += 1 }
        var codaCells: [Int] = []
        var trailing = false
        while i < cells.count {
            if cells[i].isVowel { trailing = true }        // a vowel after the coda region => malformed
            else if !trailing { codaCells.append(i) }
            i += 1
        }
        func letterOf(_ idx: Int) -> Character { cells[idx].dStroke ? "đ" : cells[idx].consonant }
        let onsetLetters = onsetCells.map { letterOf($0) }   // lowercase chars

        var glideIndex: Int? = nil
        var nucleusIdx = vowelIdx
        // qu fold: onset ends in q, first vowel is bare u, and there is at least one more vowel
        if onsetLetters.last == "q", vowelIdx.count >= 2,
           cells[vowelIdx[0]].base == .u, cells[vowelIdx[0]].mark == .none {
            glideIndex = vowelIdx[0]; nucleusIdx = Array(vowelIdx.dropFirst())
        }
        // gi fold: onset is exactly ["g"], first vowel is bare i, and there is at least one more vowel
        else if onsetLetters == ["g"], vowelIdx.count >= 2,
                cells[vowelIdx[0]].base == .i, cells[vowelIdx[0]].mark == .none {
            glideIndex = vowelIdx[0]; nucleusIdx = Array(vowelIdx.dropFirst())
        }

        var onsetString = String(onsetLetters)
        if glideIndex != nil { onsetString += (onsetLetters.last == "q") ? "u" : "i" }  // "qu" / "gi"

        let firstNucleus = nucleusIdx.first.map { cells[$0].base }
        let nucleusString = String(nucleusIdx.map { NFC.qualityLetter(cells[$0].base, cells[$0].mark) })
        let codaString = String(codaCells.map { letterOf($0) })

        return Parsed(onsetString: onsetString, firstNucleus: firstNucleus,
                      nucleusIdx: nucleusIdx, glideIndex: glideIndex,
                      nucleusString: nucleusString, codaString: codaString,
                      hasConsonantCoda: !codaCells.isEmpty, trailingVowelAfterCoda: trailing)
    }

    // Render a composed word to the active output table's code units
    // (design spec Part A §6). Same tone-placement/cell-walk logic as the
    // old String-returning `render`; only the per-cell emission changed, to
    // go through `OutputTable` instead of hard-coding `NFC`.
    private func encode(_ comp: Composition, table: OutputTable) -> [UInt16] {
        let cells = comp.cells
        if cells.isEmpty { return [] }
        let p = parse(cells)
        var toneIndexInNucleus: Int? = nil
        if !p.nucleusIdx.isEmpty {
            let nvs = p.nucleusIdx.map { TonePlacement.NVowel(base: cells[$0].base, mark: cells[$0].mark) }
            toneIndexInNucleus = TonePlacement.index(nucleus: nvs, hasCoda: p.hasConsonantCoda, style: config.orthography)
        }
        var out: [UInt16] = []
        for (k, cell) in cells.enumerated() {
            if cell.isVowel {
                var t: Tone = .ngang
                if comp.tone != .ngang, let pos = p.nucleusIdx.firstIndex(of: k), pos == toneIndexInNucleus {
                    t = comp.tone
                }
                out += table.vowel(base: cell.base, mark: cell.mark, tone: t, upper: cell.isUpper)
            } else if cell.dStroke {
                out += table.dStroke(upper: cell.isUpper)
            } else {
                let ch: Character = cell.isUpper ? Character(String(cell.consonant).uppercased()) : cell.consonant
                out += table.plain(ch)
            }
        }
        return out
    }

    private func isValid(_ comp: Composition) -> Bool {
        let cells = comp.cells
        if cells.isEmpty { return true }
        let p = parse(cells)
        if p.trailingVowelAfterCoda { return false }
        if p.nucleusIdx.isEmpty {
            // A bare onset with nothing after it is a *pending* syllable still
            // being composed (e.g. "đ" from `dd` before its vowel), not an
            // invalid word — keep it, don't revert to raw keystrokes.
            return p.codaString.isEmpty && Phonology.onsets.contains(p.onsetString)
        }
        guard Phonology.isLegalOnset(p.onsetString, firstNucleus: p.firstNucleus) else { return false }
        guard Phonology.isLegalNucleus(p.nucleusString) else { return false }
        guard Phonology.isLegalCoda(p.codaString) else { return false }
        guard Phonology.isLegalRime(nucleus: p.nucleusString, coda: p.codaString) else { return false }
        guard Phonology.toneAllowed(comp.tone, coda: p.codaString) else { return false }
        return true
    }

    /// Eager restore (Phase 7, `config.spellCheck`): is this composition
    /// DEAD — structurally unable to EVER become a legal Vietnamese syllable
    /// no matter what is typed next? This is deliberately much STRICTER than
    /// `isValid` (merely "not currently valid"): every condition below is
    /// checked to be structurally safe on every prefix of a real Vietnamese
    /// word — see DECISIONS.md "Eager restore (spellCheck / Phase 7)" for the
    /// full reasoning and the corpus sweep that proves it.
    private func isUnrecoverable(_ comp: Composition) -> Bool {
        let cells = comp.cells
        if cells.isEmpty { return false }
        // A composition with NO vowel is never a "dead English word": it is
        // either a still-pending onset (đ from `dd` before its vowel) or a
        // DELIBERATE Telex double-strike literal (ww→w, ddd→dd) that
        // `finalize` keeps as composed rather than reverting — see
        // DECISIONS.md "Restore-if-invalid: two layers". Mirror that guard
        // here (finalize's own restore branch is also `&& compHasVowel`) so
        // eager restore never rewrites those escapes back to raw keystrokes.
        guard cells.contains(where: { $0.isVowel }) else { return false }
        let p = parse(cells)
        // 1) A vowel typed after the coda region — impossible, unrepairable.
        if p.trailingVowelAfterCoda { return true }
        // 2) Onset that is neither a legal onset NOR the prefix of any legal onset
        //    (e.g. "vm", "cl", "br", "st"). Legal single/multi onsets and their
        //    prefixes are all recoverable.
        if !p.onsetString.isEmpty,
           !Phonology.onsets.contains(p.onsetString),
           !Phonology.isOnsetPrefix(p.onsetString) { return true }
        // 4) Coda that is neither a legal coda NOR the prefix of any legal coda
        //    (e.g. "ck", "g", "d", "s", "x", "b"). Legal codas: c ch m n ng nh p t.
        if !p.codaString.isEmpty,
           !Phonology.isLegalCoda(p.codaString),
           !Phonology.isCodaPrefix(p.codaString) { return true }
        // 5) An offglide-final nucleus already closed by a consonant coda — the rime
        //    is impossible and more typing only lengthens the coda (coins, rains).
        if !p.codaString.isEmpty, !p.nucleusString.isEmpty,
           Phonology.isLegalNucleus(p.nucleusString),
           !Phonology.isLegalRime(nucleus: p.nucleusString, coda: p.codaString) { return true }
        // NOTE: a failing toneAllowed (stop coda p/t/c/ch without its sắc/nặng tone,
        //   e.g. "môt") is DELIBERATELY NOT here — the tone key repairs it.
        // NOTE: nucleus-legality is deliberately NOT a condition — an intermediate
        //   plain nucleus like "uo" (before oo→ô in "muốn") is recoverable, and a
        //   safe base-vowel check catches too little to be worth the risk.
        return false
    }
}
