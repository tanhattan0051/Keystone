// Phonology.swift — phonotactic / spelling validation (design spec Part A §5).
//
// Used by restore-if-invalid: when a committed syllable is not a legal Vietnamese
// word, the engine emits the raw keystrokes instead. Also enforces the
// stop-coda tone restriction and the c/k/q · g/gh · ng/ngh orthographic rules.

enum Phonology {

    // MARK: Onsets (§5.1)

    /// Legal onset spellings, including đ (written here as "đ") and the qu/gi
    /// glide onsets. `k`/`c`/`q`, `g`/`gh`, `ng`/`ngh` selection is handled by
    /// `isLegalOnset` against the following nucleus vowel.
    static let onsets: Set<String> = [
        "", // vowel-initial syllables (ăn, uống, yêu)
        "b", "c", "d", "đ", "g", "h", "k", "l", "m", "n", "p", "q", "r", "s", "t", "v", "x",
        "ch", "gh", "gi", "kh", "nh", "ng", "ph", "qu", "th", "tr", "ngh",
    ]

    /// Front vowels select k / gh / ngh.
    private static func isFront(_ base: BaseVowel) -> Bool {
        base == .e || base == .i || base == .y
    }

    /// Validate an onset against the first *real* nucleus vowel.
    static func isLegalOnset(_ onset: String, firstNucleus: BaseVowel?) -> Bool {
        guard onsets.contains(onset) else { return false }
        guard let v = firstNucleus else {
            // No nucleus vowel — only a bare (empty) onset could be valid, and
            // that isn't a syllable. Treated as invalid by the caller anyway.
            return onset.isEmpty
        }
        switch onset {
        case "k", "gh", "ngh":
            return isFront(v)
        case "c", "ng":
            // c/ng may not precede front vowels (that's k/ngh's job).
            return !isFront(v)
        case "g":
            // g needs gh before e/ê, but g + i is the standard "gi" onset
            // collapsed before i (gì, gìn, gỉ) — distinct from ghì. (BaseVowel
            // .e covers both e and ê; g never legally precedes either.)
            return v != .e
        case "q", "qu":
            return true   // qu is followed by a glide; handled at parse time
        default:
            return true
        }
    }

    // MARK: Codas (§5.2)

    /// Legal *consonant* codas. Semivowel offglides (i/y/o/u) live in the
    /// nucleus, not here.
    static let codas: Set<String> = [
        "", "c", "ch", "m", "n", "ng", "nh", "p", "t",
    ]

    static func isLegalCoda(_ coda: String) -> Bool { codas.contains(coda) }

    // MARK: Nucleus inventory (§5.3)

    /// Written nucleus forms (lowercase, with quality marks, no tone).
    /// A generous but non-garbage inventory of Vietnamese nuclei.
    static let nuclei: Set<String> = [
        // monophthongs
        "a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
        // diphthongs
        "ai", "ao", "au", "ay", "âu", "ây",
        "eo", "êu",
        "ia", "iê", "iu",
        "oa", "oă", "oe", "oi", "ôi", "ơi", "oo",
        "ua", "uâ", "ưa", "uê", "ui", "ưi", "uô", "uơ", "uy", "ưu", "ươ",
        "yê",
        // triphthongs
        "iêu", "oai", "oao", "oay", "oeo", "uây", "uôi", "ươi", "ươu",
        "uya", "uyê", "uyu", "yêu",
    ]

    static func isLegalNucleus(_ nucleus: String) -> Bool { nuclei.contains(nucleus) }

    /// Is `s` the start of (or a whole) legal nucleus? Used to decide whether a
    /// repeated vowel letter is a new nucleus vowel or a (possibly non-adjacent)
    /// circumflex signal — e.g. "oi"+"o" = "oio" is not a prefix (so the o is a
    /// mark → rồi), while "oa"+"o" = "oao" is a real triphthong (so append → ngoáo).
    static func isNucleusPrefix(_ s: String) -> Bool {
        if s.isEmpty { return true }
        return nuclei.contains { $0.hasPrefix(s) }
    }

    // MARK: Prefix checks for eager restore (spellCheck / Phase 7)

    /// Is `s` the start of (or a whole) legal onset? (mirrors isNucleusPrefix)
    static func isOnsetPrefix(_ s: String) -> Bool {
        if s.isEmpty { return true }
        return onsets.contains { $0.hasPrefix(s) }
    }

    /// Is `s` the start of (or a whole) legal consonant coda?
    static func isCodaPrefix(_ s: String) -> Bool {
        if s.isEmpty { return true }
        return codas.contains { $0.hasPrefix(s) }
    }

    // MARK: Nucleus × coda legality (§5.3)

    /// Nuclei that end in a semivowel offglide and therefore CANNOT take a true
    /// consonant coda (falling diphthongs/triphthongs: ai, oi, ui, ươi, iêu …).
    /// This is the spec §5.3 rime check, encoded as the offglide-final rule that
    /// protects English words like `coins`, `ruins`, `rains` from becoming
    /// pseudo-Vietnamese. Nuclei like `uy`, `oa`, `oe`, `iê`, `uô`, `ươ`, `uyê`
    /// are intentionally NOT here — they take codas (huỳnh, toán, khoét, tiên,
    /// muốn, được, nguyên).
    static let openOnlyNuclei: Set<String> = [
        "ai", "ao", "au", "ay", "âu", "ây", "eo", "êu", "ia", "iu",
        "oi", "ôi", "ơi", "ua", "ưa", "ui", "ưi", "ưu", "uơ",
        "oai", "oay", "oao", "oeo", "uôi", "ươi", "ươu", "iêu", "yêu", "uya", "uây",
    ]

    /// A nucleus may be closed by a consonant coda only if it is not offglide-final.
    static func isLegalRime(nucleus: String, coda: String) -> Bool {
        if coda.isEmpty { return true }
        return !openOnlyNuclei.contains(nucleus)
    }

    // MARK: Tone restriction (§5.4)

    /// Syllables closed by a stop coda (p t c ch) may bear only sắc or nặng.
    static func toneAllowed(_ tone: Tone, coda: String) -> Bool {
        let stops: Set<String> = ["p", "t", "c", "ch"]
        if stops.contains(coda) {
            return tone == .sac || tone == .nang
        }
        return true
    }
}
