// Lexicon.swift — a pure, in-memory English word list plus the decision
// rule that uses it to pick between two spellings at restore time (design
// spec: "restore chooses the composed word when it is the real one", see
// DECISIONS.md).
//
// No I/O here — this is Swift stdlib + Foundation only (same rule as the
// rest of KeystoneEngine, see Engine.swift's header). Loading the real word
// list from disk (and merging the supplementary modern-word list) is
// KeystoneInput's job (`LexiconLoader`), which is not pure.

import Foundation

/// An in-memory, case-insensitive set of English words. Deliberately NOT
/// `Equatable`, and NOT `Codable`: the real system list is ~236k entries,
/// and `EngineConfig` (which IS both, and gets rebuilt from scratch on every
/// unrelated preference change by `AppModel.pushConfig()`) must not carry a
/// field of this size along for that ride — that is exactly why
/// `Engine.lexicon` is a plain stored property outside `EngineConfig` rather
/// than a config field, set independently via `EngineController.setLexicon`.
/// See DECISIONS.md "Restore chooses the composed word when it is the real
/// one".
public struct Lexicon: Sendable {
    private var words: Set<String>

    /// Every word, lowercase, sorted ascending — the data behind `isPrefix` and
    /// `prefixDepth` (binary searches). Only meaningful while
    /// `prefixIndexIsFresh`; see `buildPrefixIndex`.
    private var sortedWords: [String] = []
    /// False from construction (`init()`) and after any `insert` that added a
    /// word, until `buildPrefixIndex()` runs. A stale index answers
    /// `false`/`0` rather than something wrong.
    private var prefixIndexIsFresh = false

    /// An empty lexicon, built up one word at a time via `insert` — the
    /// low-memory path `LexiconLoader` uses to build the real ~236k-entry
    /// list without ever materializing an intermediate `[String]` of every
    /// line (see `insert`'s doc comment).
    public init() {
        words = []
    }

    /// Builds a lexicon from a sequence of words in one pass, inserting
    /// directly into the underlying set as it iterates (no intermediate
    /// `[String]` copy of `words` itself — only the caller's own sequence,
    /// if it already is one, is materialized).
    public init<S: Sequence>(_ words: S) where S.Element == String {
        self.init()
        self.words.reserveCapacity(words.underestimatedCount)
        for w in words { insert(w) }
        buildPrefixIndex()
    }

    /// Inserts one word: trimmed of whitespace, lowercased; a blank/
    /// whitespace-only word is silently ignored. The single primitive both
    /// `init<S: Sequence>` and `parse` build on below, and that
    /// `LexiconLoader` calls directly line-by-line while reading
    /// `/usr/share/dict/words` — so there is exactly one place that defines
    /// what "a word in the lexicon" means, and building a large lexicon
    /// never needs an intermediate array of all its words.
    public mutating func insert(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        // Only a NEW word changes what the index must contain.
        if words.insert(trimmed).inserted { prefixIndexIsFresh = false }
    }

    /// One word per line, built in one pass via `Foundation`'s
    /// `enumerateLines` (no intermediate `[String]`/`[Substring]` of every
    /// line — the same low-memory shape `LexiconLoader` uses for the real
    /// word list). Blank lines are skipped by `insert`.
    public static func parse(_ text: String) -> Lexicon {
        var lex = Lexicon()
        text.enumerateLines { line, _ in lex.insert(line) }
        lex.buildPrefixIndex()
        return lex
    }

    /// Case-insensitive membership test.
    public func contains(_ word: String) -> Bool {
        words.contains(word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public var count: Int { words.count }

    // MARK: - Prefix index
    //
    // "How English-like is this spelling?" asked of a string that is not (yet)
    // a word: how many of its leading letters still begin SOME dictionary
    // word. Used by `RestoreDecision.chooseAfterCancel` to tell a cancelled
    // Telex tone key (`unssuspend` -> `unsuspend`) from a natural double letter
    // (`messages`), see DECISIONS.md "Cancel keeps the literal".

    /// True once `buildPrefixIndex()` has run since the last `insert` that
    /// added a word. `Engine` requires it before using the cancel rule, so a
    /// lexicon that was never indexed behaves exactly as it did before this
    /// feature existed.
    public var isPrefixIndexBuilt: Bool { prefixIndexIsFresh }

    /// Sorts every word into the prefix index. O(n log n) — for the real
    /// ~236k-word list that is a noticeable fraction of a second — so it must
    /// only ever run where the lexicon is built, off the event-tap thread
    /// (`LexiconLoader.load` calls it once after its inserts; `init<S>` and
    /// `parse` call it for the small lists tests and the force-English list
    /// build). Never call it from `Engine` or the per-keystroke path.
    public mutating func buildPrefixIndex() {
        sortedWords = words.sorted()
        prefixIndexIsFresh = true
    }

    /// True iff some word starts with the lowercased `p` (a word is a prefix of
    /// itself). `false` on a stale or never-built index.
    public func isPrefix(_ p: String) -> Bool {
        guard prefixIndexIsFresh else { return false }
        return startsSomeWord(p.lowercased(), searchingFrom: 0).found
    }

    /// The largest k such that the first k characters of lowercased `s` pass
    /// `isPrefix`; 0 for "" and for a stale or never-built index.
    ///
    /// Prefixes are monotone — if a k-letter prefix of `s` starts no word, no
    /// longer one does — so this scans forward and stops at the first miss,
    /// resuming each binary search from where the previous one landed.
    public func prefixDepth(_ s: String) -> Int {
        guard prefixIndexIsFresh else { return 0 }
        let lowered = s.lowercased()
        var depth = 0
        var lowerBound = 0
        var end = lowered.startIndex
        while end < lowered.endIndex {
            end = lowered.index(after: end)
            let result = startsSomeWord(String(lowered[..<end]), searchingFrom: lowerBound)
            guard result.found else { break }
            depth += 1
            lowerBound = result.index
        }
        return depth
    }

    /// Binary search for the first sorted word >= `prefix` (starting at
    /// `searchingFrom`, which the caller guarantees is <= that position), and
    /// whether that word starts with `prefix`. Every word that starts with
    /// `prefix` sorts at or after `prefix` and contiguously, so the first
    /// candidate decides it.
    private func startsSomeWord(_ prefix: String, searchingFrom start: Int) -> (found: Bool, index: Int) {
        var lo = start, hi = sortedWords.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedWords[mid] < prefix { lo = mid + 1 } else { hi = mid }
        }
        return (lo < sortedWords.count && sortedWords[lo].hasPrefix(prefix), lo)
    }
}

/// Which spelling `RestoreDecision.choose` picked.
public enum RestoreChoice: Sendable, Equatable {
    case composed
    case raw
}

/// The restore-time decision between the COMPOSED word (what's on screen,
/// with Vietnamese diacritics applied) and the RAW word (the literal
/// keystrokes) — see `Engine.finalize`'s restore branch.
public enum RestoreDecision {
    /// `.composed` iff `lexicon` is present, contains `composed`, does NOT
    /// contain `raw`, AND `composed` is a SUBSEQUENCE of `raw` (obtainable
    /// from `raw` only by deleting characters, never adding or reordering
    /// them). Otherwise `.raw` — today's exact behavior.
    ///
    /// The subsequence requirement is the principled statement of what a
    /// Telex tone/mark CANCEL actually does: pressing the same key again
    /// removes it from the rendered word, it never introduces a different
    /// letter. That is exactly the nine-row cancel-habit table (`tassk` →
    /// `task` deletes one `s`; `gooogle` → `google` deletes one `o`) and
    /// exactly NOT what the quick-consonant toggles do (`quickTelex`,
    /// `quickStartConsonant`, `quickEndConsonant`): those can turn a raw
    /// consonant into a DIFFERENT, longer spelling (`nn`→`ng`, `tt`→`th`,
    /// `j`→`gi`, `w`→`qu`, `g`→`ng`, `k`→`ch`), so composed can land on an
    /// unrelated real word — `sinning`→`singing`, `nike`→`niche`,
    /// `wilted`→`quilted`, `raged`→`ranged`, `bak`→`bach`. Without this
    /// guard, if the lexicon happened to contain that other word (and not
    /// the raw spelling), `choose` would wrongly rewrite the user's actual
    /// keystrokes into a word they never typed. With it, every one of those
    /// falls back to `.raw`, matching HEAD (pre-lexicon) behavior.
    ///
    /// Deliberately minimal otherwise, and RAW is always the fallback when
    /// any condition above isn't met — so a case this rule doesn't handle
    /// degrades to exactly today's (pre-lexicon) behavior, never to
    /// something worse. That said, this is NOT a claim that natural typing
    /// of a real word always has `raw` in the lexicon: a real English word
    /// missing from BOTH the system list and the supplement can still
    /// collapse the wrong way if typed with a doubled Telex key — a genuine,
    /// accepted known limitation, see DECISIONS.md "Known limitation: a real
    /// word missing from both lists".
    public static func choose(composed: String, raw: String, lexicon: Lexicon?) -> RestoreChoice {
        guard let lexicon else { return .raw }
        let composedLower = composed.lowercased()
        let rawLower = raw.lowercased()
        guard lexicon.contains(composedLower), !lexicon.contains(rawLower) else { return .raw }
        guard isSubsequence(composedLower, of: rawLower) else { return .raw }
        return .composed
    }

    /// How many MORE letters the composed spelling must stay English-like than
    /// the raw one before `chooseAfterCancel` prefers it ("English-like" =
    /// `Lexicon.prefixDepth`).
    ///
    /// WHY 2. Measured on 159,287 words of real English prose (22 man pages +
    /// the repo's docs, 6,977 distinct words), typed naturally and with the
    /// OpenKey cancel habit, against main (no rule): natural typing final output
    /// correct 87.60% -> 87.60% (0 words newly wrong) at margin 2, habit typing
    /// 87.13% -> 89.39% (0 newly wrong, 408 newly right). Margin 1 broke 9
    /// real words (`lesskey`, `onerror`, `nonbootable`, ...): a natural double
    /// letter whose composed form happens to keep matching the dictionary one
    /// letter longer. Adding -s/-ed/-es stem rules instead broke the habit case
    /// (`thiss` read as `this` + `s`). Do not lower this without re-measuring.
    static let englishLikenessMargin = 2

    /// After a Telex CANCEL (`Composition.cancelled`, no tone and no vowel mark
    /// left): which spelling is more ENGLISH-LIKE, the COMPOSED one (the cancel
    /// applied: `unsuspend`) or the RAW keys (cancel key included:
    /// `unssuspend`)? All strings are compared lowercased.
    ///
    /// Why this is not `choose`: `choose` needs the composed word to BE in the
    /// dictionary, but the words the author types this way often are not
    /// (`unsuspend`), and main then commits the cancel key (`unssuspend`). The
    /// first attempt at fixing that (always keep the composed word unless the
    /// raw one is a dictionary word) broke correctly typed English the
    /// 1934-Webster list lacks (`messages` -> `mesages`): about 1 word in 160.
    /// So the dictionary is asked about PREFIXES instead (`Lexicon.prefixDepth`):
    ///
    /// Guard, first and in both modes: unless `composed` is a SUBSEQUENCE of at
    /// least one raw (obtainable by deleting characters only, which is all a
    /// cancel ever does) -> `.raw`. A quick-consonant toggle (`quickTelex`,
    /// `quickStartConsonant`, `quickEndConsonant`) can put letters in the
    /// composed word that were never typed (f -> ph, k -> ch, cc -> ch), and
    /// `choose` refuses those for the same reason (see its doc comment and
    /// `isSubsequence`): a cancelled word that also carries such an expansion
    /// keeps its raw keys.
    ///
    /// `atCommit == true` (the word is being committed):
    ///   1. any raw is a word                      -> `.raw`
    ///   2. composed is a word                     -> `.composed`
    ///   3. depth(composed) >= max depth(raw) + `englishLikenessMargin`
    ///                                             -> `.composed`
    ///   4. otherwise                              -> `.raw`
    ///
    /// `atCommit == false` (the word is still being typed; this only decides
    /// what to DISPLAY): the same, with "is a prefix" in place of "is a word" in
    /// rules 1 and 2, because the word may simply not be finished yet.
    ///
    /// `raws` holds every spelling the raw keys could commit as (the
    /// `ww`/`ddd`-collapsed one and the keys exactly as typed); the deepest
    /// counts. A stale or never-built prefix index gives depth 0 on both
    /// sides, so rule 3 can never fire without it.
    public static func chooseAfterCancel(
        composed: String, raws: [String], lexicon: Lexicon, atCommit: Bool
    ) -> RestoreChoice {
        let composedLower = composed.lowercased()
        let rawsLower = raws.map { $0.lowercased() }
        guard rawsLower.contains(where: { isSubsequence(composedLower, of: $0) }) else { return .raw }
        if atCommit {
            if rawsLower.contains(where: { lexicon.contains($0) }) { return .raw }
            if lexicon.contains(composedLower) { return .composed }
        } else {
            if rawsLower.contains(where: { lexicon.isPrefix($0) }) { return .raw }
            if lexicon.isPrefix(composedLower) { return .composed }
        }
        let rawDepth = rawsLower.map { lexicon.prefixDepth($0) }.max() ?? 0
        return lexicon.prefixDepth(composedLower) >= rawDepth + englishLikenessMargin ? .composed : .raw
    }

    /// True iff `needle` can be produced from `haystack` by deleting zero or
    /// more characters, keeping the remaining ones in the same relative
    /// order (a classic subsequence test) — never adding or reordering
    /// characters. Case-sensitive; `choose` above lowercases both sides
    /// first. Pure and `O(haystack.count)`.
    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var needleIdx = needle.startIndex
        for ch in haystack {
            guard needleIdx < needle.endIndex else { break }
            if ch == needle[needleIdx] {
                needleIdx = needle.index(after: needleIdx)
            }
        }
        return needleIdx == needle.endIndex
    }
}
