// LexiconLoader.swift — reads the system English word list from disk and
// merges `SupplementaryWords` (modern words that list lacks) into a
// `Lexicon`. This is the only I/O-performing piece of the restore-picks-the-
// real-word feature; `Lexicon`/`RestoreDecision` themselves stay pure in
// KeystoneEngine. See DECISIONS.md "Restore chooses the composed word when
// it is the real one".

import Foundation
import KeystoneEngine

public enum LexiconLoader {
    /// Loads `systemWordsPath` (one word per line, as `/usr/share/dict/words`
    /// is formatted — ~236k lines) and merges in `SupplementaryWords.all` and
    /// `.protectedRealWords`. Never throws or crashes: a missing or
    /// unreadable file is LOGGED (path + error, not swallowed silently — same
    /// `NSLog` convention as this target's other integration-only failures,
    /// e.g. `EventTapController`'s tap-creation errors) and the supplement
    /// lists are still returned, so a lexicon-consuming caller always gets a
    /// usable (if smaller) result.
    ///
    /// Builds the `Lexicon`'s underlying `Set` in ONE pass, inserting each
    /// line as it is read via `String.enumerateLines` — never an
    /// intermediate `[String]` holding every line, and never a
    /// `systemWords + supplement` array concatenation (both would double
    /// peak memory for a ~236k-line file for no benefit; `Lexicon.insert`
    /// is the one place, shared with `Lexicon.parse`, that defines what "a
    /// word in the lexicon" means — see its doc comment). The sorted prefix
    /// index is built once at the end (`Lexicon.buildPrefixIndex`).
    public static func load(systemWordsPath: String = "/usr/share/dict/words") -> Lexicon {
        var lexicon = Lexicon()
        do {
            let text = try String(contentsOfFile: systemWordsPath, encoding: .utf8)
            text.enumerateLines { line, _ in lexicon.insert(line) }
        } catch {
            NSLog("Keystone: LexiconLoader could not read system word list at %@: %@",
                  systemWordsPath, error.localizedDescription)
        }
        for w in SupplementaryWords.all { lexicon.insert(w) }
        for w in SupplementaryWords.protectedRealWords { lexicon.insert(w) }
        // Sorted ONCE here, after every insert, because this already runs off
        // the main and event-tap threads (see `AppModel.updateLexiconLoaded`).
        // Without it `isPrefix`/`prefixDepth` answer false/0 and the engine's
        // cancel rule stays off — LexiconLoaderTests pins that it is built.
        lexicon.buildPrefixIndex()
        return lexicon
    }
}
