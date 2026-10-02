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
        words.insert(trimmed)
    }

    /// One word per line, built in one pass via `Foundation`'s
    /// `enumerateLines` (no intermediate `[String]`/`[Substring]` of every
    /// line — the same low-memory shape `LexiconLoader` uses for the real
    /// word list). Blank lines are skipped by `insert`.
    public static func parse(_ text: String) -> Lexicon {
        var lex = Lexicon()
        text.enumerateLines { line, _ in lex.insert(line) }
        return lex
    }

    /// Case-insensitive membership test.
    public func contains(_ word: String) -> Bool {
        words.contains(word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public var count: Int { words.count }
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
