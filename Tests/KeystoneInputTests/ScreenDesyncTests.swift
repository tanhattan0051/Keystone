// ScreenDesyncTests.swift — pins the fix for the screen/engine desync bug: a
// keystroke the engine absorbed into its composing word without changing the
// on-screen rendering (a genuine no-op edit) used to reach the app
// unsuppressed, so the real screen silently diverged from `Engine.prevUnits`
// — the engine's own belief of what's on screen. The corruption only became
// visible later, when a later edit's backspace count was computed against
// the WRONG (stale) belief. See DECISIONS.md "Suppress every character the
// engine took ownership of, even a no-op one".
//
// Every suite here is driven through the REALISTIC harness
// (RealisticTyping.swift), which is what actually exposes this bug — a
// harness that only ever replays edits (as `EngineControllerTests`'
// `typeAndFlush` used to) cannot see a physical passthrough key land on
// screen, so it was blind to this bug even though it drives the exact same
// `EngineController.handle`.

import Testing
@testable import KeystoneInput
@testable import KeystoneEngine

@Suite("ScreenDesyncNoopAbsorb")
struct ScreenDesyncNoopAbsorbTests {
    // Each of these types a character mid-word (the second "s" in "tasks",
    // for instance) that the engine absorbs into its raw-key buffer without
    // changing the rendering — a true no-op edit (backspaceCount == 0,
    // text == ""). Confirmed by a per-keystroke trace: right after that
    // keystroke the screen shows "ták" while the engine still composes
    // "task" + a pending "s"; typing the rest of the word and committing
    // used to leave the screen desynced from what the engine actually
    // committed. Default config, restoreIfInvalid on (the default), no
    // lexicon needed — plain restore-to-raw already produces the right word.
    private static let words = ["tasks", "servers", "hashes", "offsets"]

    @Test(arguments: words)
    func absorbedNoopCharacterDoesNotLeakToScreen(_ word: String) {
        #expect(typeAndFlush(word) == word)
    }

    @Test(arguments: words)
    func absorbedNoopCharacterDoesNotLeakToScreenWithLexicon(_ word: String) {
        let lexicon = Lexicon(["tasks", "servers", "hashes", "offsets"])
        #expect(typeAndFlush(word, lexicon: lexicon) == word)
    }

    // Symmetric bug: Backspace deleting an absorbed (invisible) raw key must
    // not fall through as an ordinary passthrough Delete and eat a VISIBLE
    // character instead. E.g. "s e r v e r s" composes to "sẻrver" on screen
    // (the trailing "s" is absorbed invisibly, same shape as above);
    // Backspace then removes that raw "s" — also a no-op edit, since it
    // wasn't rendered — leaving rawKeys == "server", which is what commits
    // (raw revert: "sẻrver" isn't a legal Vietnamese word, and there's no
    // lexicon here to prefer anything else).
    private static let dropLastCases: [(typed: String, expected: String)] = [
        ("servers", "server"),
        ("corners", "corner"),
        ("borders", "border"),
        ("workers", "worker"),
    ]

    @Test(arguments: dropLastCases)
    func backspaceOnAbsorbedNoopCharacterDeletesNoVisibleCharacter(_ c: (typed: String, expected: String)) {
        let controller = EngineController(config: EngineConfig())
        var acc: [Unicode.Scalar] = []
        for ch in c.typed {
            applyRealistically(controller.handle(letter(ch)), to: &acc)
        }
        applyRealistically(controller.handle(BACKSPACE), to: &acc)
        applyRealistically(controller.handle(RETURN), to: &acc)
        #expect(String(String.UnicodeScalarView(acc)) == c.expected)
    }
}

@Suite("ScreenDesyncVietnameseRegression")
struct ScreenDesyncVietnameseRegressionTests {
    // A broad Telex sweep driven through the REALISTIC EngineController
    // harness rather than the pure Engine (Tests/KeystoneEngineTests'
    // corpus suites, which call `Engine.process` directly and so cannot see
    // an EngineController suppression bug at all, no matter how broad).
    // Pulled from the engine's own JSON corpus (Tests/KeystoneEngineTests/
    // Corpus/{words,words2,regressions,tones,placement}.json, telex/modern/
    // single-word entries), re-verified here end-to-end.
    struct Case: CustomTestStringConvertible {
        let keys: String, expected: String
        var testDescription: String { expected }
    }

    static let cases: [Case] = [
        .init(keys: "tooi", expected: "tôi"),
        .init(keys: "yeeu", expected: "yêu"),
        .init(keys: "nguowif", expected: "người"),
        .init(keys: "hocj", expected: "học"),
        .init(keys: "truowngf", expected: "trường"),
        .init(keys: "phowr", expected: "phở"),
        .init(keys: "ddepj", expected: "đẹp"),
        .init(keys: "nuowcs", expected: "nước"),
        .init(keys: "mootj", expected: "một"),
        .init(keys: "anh", expected: "anh"),
        .init(keys: "em", expected: "em"),
        .init(keys: "hai", expected: "hai"),
        .init(keys: "ba", expected: "ba"),
        .init(keys: "ma", expected: "ma"),
        .init(keys: "maf", expected: "mà"),
        .init(keys: "mas", expected: "má"),
        .init(keys: "mar", expected: "mả"),
        .init(keys: "max", expected: "mã"),
        .init(keys: "maj", expected: "mạ"),
        .init(keys: "bee", expected: "bê"),
        .init(keys: "beef", expected: "bề"),
        .init(keys: "bees", expected: "bế"),
        .init(keys: "beer", expected: "bể"),
        .init(keys: "beex", expected: "bễ"),
        .init(keys: "beej", expected: "bệ"),
        .init(keys: "taams", expected: "tấm"),
        .init(keys: "caanr", expected: "cẩn"),
        .init(keys: "suowng", expected: "sương"),
        .init(keys: "lanhj", expected: "lạnh"),
        .init(keys: "taapj", expected: "tập"),
        .init(keys: "taats", expected: "tất"),
        .init(keys: "bacs", expected: "bác"),
        .init(keys: "sachj", expected: "sạch"),
        .init(keys: "sachs", expected: "sách"),
        .init(keys: "hoa", expected: "hoa"),
        .init(keys: "quaf", expected: "quà"),
        .init(keys: "quyeenr", expected: "quyển"),
        .init(keys: "hueej", expected: "huệ"),
        .init(keys: "xoaif", expected: "xoài"),
        .init(keys: "huowu", expected: "hươu"),
        .init(keys: "ruowuj", expected: "rượu"),
        .init(keys: "cuowif", expected: "cười"),
        .init(keys: "muoois", expected: "muối"),
        .init(keys: "chuoois", expected: "chuối"),
        .init(keys: "khuya", expected: "khuya"),
        .init(keys: "tuyeets", expected: "tuyết"),
        .init(keys: "nguyeen", expected: "nguyên"),
        .init(keys: "quyeets", expected: "quyết"),
        .init(keys: "vuownf", expected: "vườn"),
        .init(keys: "muowngf", expected: "mường"),
        .init(keys: "dduowngf", expected: "đường"),
        .init(keys: "myx", expected: "mỹ"),
        .init(keys: "kyx", expected: "kỹ"),
        .init(keys: "quys", expected: "quý"),
        .init(keys: "camr", expected: "cảm"),
        .init(keys: "own", expected: "ơn"),
        .init(keys: "chaof", expected: "chào"),
        .init(keys: "banj", expected: "bạn"),
        .init(keys: "khoong", expected: "không"),
        .init(keys: "trais", expected: "trái"),
        .init(keys: "mays", expected: "máy"),
        .init(keys: "chaus", expected: "cháu"),
        .init(keys: "keoj", expected: "kẹo"),
        .init(keys: "nois", expected: "nói"),
        .init(keys: "nuis", expected: "núi"),
        .init(keys: "chiuj", expected: "chịu"),
        .init(keys: "muaf", expected: "mùa"),
        .init(keys: "kiaf", expected: "kìa"),
        .init(keys: "saauf", expected: "sầu"),
        .init(keys: "thaays", expected: "thấy"),
        .init(keys: "leeuf", expected: "lều"),
        .init(keys: "xoef", expected: "xòe"),
        .init(keys: "suyts", expected: "suýt"),
        .init(keys: "gif", expected: "gì"),
        .init(keys: "ginf", expected: "gìn"),
        .init(keys: "gir", expected: "gỉ"),
        .init(keys: "gieengs", expected: "giếng"),
        .init(keys: "quow", expected: "quơ"),
        .init(keys: "quowr", expected: "quở"),
        .init(keys: "thu[r", expected: "thuở"),
        .init(keys: "hu[", expected: "huơ"),
        .init(keys: "coins", expected: "coins"),
        .init(keys: "ruins", expected: "ruins"),
        .init(keys: "loans", expected: "loán"),
        .init(keys: "a", expected: "a"),
        .init(keys: "as", expected: "á"),
        .init(keys: "af", expected: "à"),
        .init(keys: "ar", expected: "ả"),
        .init(keys: "ax", expected: "ã"),
        .init(keys: "aj", expected: "ạ"),
        .init(keys: "asf", expected: "à"),
        .init(keys: "vieejt", expected: "việt"),
        .init(keys: "tieengs", expected: "tiếng"),
        .init(keys: "tieesng", expected: "tiếng"),
        .init(keys: "tiseeng", expected: "tiếng"),
        .init(keys: "muoons", expected: "muốn"),
        .init(keys: "hoaf", expected: "hòa"),
        .init(keys: "khoer", expected: "khỏe"),
        .init(keys: "thuyr", expected: "thủy"),
        .init(keys: "toans", expected: "toán"),
        .init(keys: "tuaanf", expected: "tuần"),
        .init(keys: "dduowcj", expected: "được"),
        .init(keys: "cuar", expected: "của"),
        .init(keys: "mias", expected: "mía"),
        .init(keys: "quar", expected: "quả"),
        .init(keys: "giayf", expected: "giày"),
        .init(keys: "khuyur", expected: "khuỷu"),
        .init(keys: "nguyeexn", expected: "nguyễn"),
        .init(keys: "hoangf", expected: "hoàng"),
        .init(keys: "quoocs", expected: "quốc"),
        .init(keys: "dduwowcj", expected: "được"),
        .init(keys: "chaof", expected: "chào"),
        .init(keys: "ddaay", expected: "đây"),
        .init(keys: "nguwowif", expected: "người"),
    ]

    @Test(arguments: cases)
    func telexWordCommitsCorrectlyThroughController(_ c: Case) {
        #expect(typeAndFlush(c.keys) == c.expected)
    }
}

@Suite("ScreenDesyncEnglishRegression")
struct ScreenDesyncEnglishRegressionTests {
    // Common English words, typed plainly (no deliberate cancel-key
    // doubling), must commit unchanged through the REALISTIC harness with
    // NO lexicon installed. `RestoreDecision.choose` always returns `.raw`
    // when `lexicon == nil` (see DECISIONS.md), so nothing here depends on
    // the lexicon feature at all — this is purely about the composed vs.
    // raw ARITHMETIC (backspace count / text) staying correct against the
    // REAL screen, which is exactly what the suppression bug corrupted.
    //
    // "coffee"..."missing" were already pinned (against a real dictionary)
    // by LexiconRealDictionaryTests; repeated here with lexicon: nil against
    // the realistic harness, plus a set of plurals/inflections chosen for
    // the same shape as the bug report (an early Telex-special letter
    // followed later by another consonant coda: "masks", "servers"-shaped
    // words, "-shes", "-ets", ...).
    private static let words = [
        // Natural double-letter English spellings (existing coverage,
        // re-verified end-to-end with no lexicon).
        "coffee", "hello", "letter", "success", "access", "address", "message", "glass",
        "grass", "boss", "kiss", "dress", "stress", "express", "possible", "assist",
        "essay", "issue", "across", "stuff", "staff", "office", "effort", "offer",
        "different", "error", "mirror", "sorry", "carry", "worry", "arrow", "tomorrow",
        "free", "agree", "need", "good", "food", "book", "school", "add",
        "odd", "passing", "missing",
        // Words whose COMPOSED collapse coincidentally spells another real
        // word in a big dictionary (existing coverage; trivially safe here
        // since lexicon: nil always picks raw).
        "fussed", "mussed", "mussing", "jarred", "purred", "parring", "riffling",
        "coiffed", "squirreling", "moussing", "suss", "terra", "torr", "barre",
        "lassi", "frisson", "farro", "barrie", "currie", "buffo", "triffid",
        "transsonic", "hassidic", "hassidim", "chassidim", "mycorrhiza", "degass",
        "unbiassed", "poisson", "cassava", "cassaba", "hassan",
        "parramatta", "kerr", "starr", "neff", "foxx",
        // New: plurals/inflections shaped like the bug report ("tasks",
        // "servers", "hashes", "offsets" themselves live in
        // ScreenDesyncNoopAbsorbTests) — an early tone/mark-key letter
        // followed later by a second consonant coda.
        "masks", "disks", "risks", "desks", "flasks", "kiosks", "helmets",
        "corners", "sisters", "masters", "clusters", "filters", "folders",
        "numbers", "borders", "workers", "drivers", "owners", "towers", "players",
        "crashes", "flashes", "dishes", "washes", "brushes",
        "baskets", "tickets", "buckets", "jackets", "markets", "targets",
        "records", "boards", "awards", "guards",
    ]

    @Test(arguments: words)
    func englishWordCommitsUnchangedThroughController(_ w: String) {
        #expect(typeAndFlush(w) == w)
    }

    // Natural `aaa` commits `aa`: the screen already shows "aa" (the third a undid
    // the circumflex); matches OpenKey. The literal AAA is typed a,a,a,a.
    @Test func naturalAaaCommitsAa() {
        #expect(typeAndFlush("aaa") == "aa")
        #expect(typeAndFlush("aaaa") == "aaa")
    }
}
