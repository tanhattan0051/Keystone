// AcrossCodaPalatalCodaTests.swift — the Telex across-coda circumflex
// (`freeMarkAcrossCoda`) must not build a rime Vietnamese does not have.
//
// The palatal codas nh/ch close only the nuclei a, ê, i, y, oa, uê and uy
// (anh, ach, ênh, êch, inh, ich, oanh, khuếch, huỳnh); ch also closes uyê in
// the common variant spelling khuyếch. Before this fix `tanha`
// showed "tânh" and even committed it, and `sacha` flashed "sâch" before
// reverting. OpenKey never applies the circumflex there (compiled-driver
// differential, 2026-11-10), and the expected screens below are OpenKey's.
// See DECISIONS.md "Across-coda circumflex refuses illegal nh/ch rimes".

import Testing
@testable import KeystoneEngine

/// The shipped Telex settings that matter here (no lexicon in engine tests).
private let shippedLike = EngineConfig(
    restoreIfInvalid: true, allowFreeToneMark: true, freeMarkAcrossCoda: true,
    literalAfterCancel: true, spellCheck: true)

/// The screen after every keystroke, then the screen after a trailing Space.
private func screens(_ keys: String, config: EngineConfig = shippedLike) -> (steps: [String], committed: String) {
    let engine = Engine(config: config)
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    var steps: [String] = []
    for ch in keys {
        apply(engine.process(KeyInput(ch)))
        steps.append(String(String.UnicodeScalarView(acc)))
    }
    apply(engine.process(KeyInput(" ")))
    return (steps, String(String.UnicodeScalarView(acc)))
}

@Suite("Phonology.palatalCodaAllowed")
struct PalatalCodaRuleTests {
    @Test(arguments: ["a", "ê", "i", "y", "oa", "uê", "uy"])
    func nhAndChFollowTheseNuclei(_ nucleus: String) {
        #expect(Phonology.palatalCodaAllowed(nucleus: nucleus, coda: "nh"))
        #expect(Phonology.palatalCodaAllowed(nucleus: nucleus, coda: "ch"))
    }

    @Test func chAlsoFollowsUyeForKhuyech() {
        #expect(Phonology.palatalCodaAllowed(nucleus: "uyê", coda: "ch"))
        #expect(!Phonology.palatalCodaAllowed(nucleus: "uyê", coda: "nh"))
    }

    @Test(arguments: ["â", "ô", "ă", "e", "o", "ơ", "u", "ư", "oâ", "uâ", "uô", "iê", "yê", "ia", "ua", "ưa", "ai", "ôi"])
    func nhAndChNeverFollowTheseNuclei(_ nucleus: String) {
        #expect(!Phonology.palatalCodaAllowed(nucleus: nucleus, coda: "nh"))
        #expect(!Phonology.palatalCodaAllowed(nucleus: nucleus, coda: "ch"))
    }

    @Test(arguments: ["", "n", "c", "ng", "m", "p", "t"])
    func otherCodasAreNotThisRulesBusiness(_ coda: String) {
        #expect(Phonology.palatalCodaAllowed(nucleus: "â", coda: coda))
        #expect(Phonology.palatalCodaAllowed(nucleus: "ô", coda: coda))
    }
}

@Suite("AcrossCodaPalatalCoda")
struct AcrossCodaPalatalCodaTests {

    // MARK: Refused: â/ô across nh/ch (screens match OpenKey)

    @Test func tanhaNeverShowsTanhWithCircumflex() {
        let r = screens("tanha")
        #expect(r.steps == ["t", "ta", "tan", "tanh", "tanha"])
        #expect(r.committed == "tanha ")
    }

    @Test func tanhaaKeepsTheRawKeys() {
        let r = screens("tanhaa")
        #expect(r.steps == ["t", "ta", "tan", "tanh", "tanha", "tanhaa"])
        #expect(r.committed == "tanhaa ")
    }

    @Test func tanhaaaKeepsTheRawKeys() {
        let r = screens("tanhaaa")
        #expect(r.steps.allSatisfy { !$0.contains("â") })
        #expect(r.committed == "tanhaaa ")
    }

    @Test func sachaNeverFlashesSach() {
        let r = screens("sacha")
        #expect(r.steps == ["s", "sa", "sac", "sach", "sacha"])
        #expect(r.committed == "sacha ")
    }

    @Test func sachaaKeepsTheRawKeys() {
        let r = screens("sachaa")
        #expect(r.steps == ["s", "sa", "sac", "sach", "sacha", "sachaa"])
        #expect(r.committed == "sachaa ")
    }

    @Test(arguments: ["anha", "acha", "onho", "ocho", "conho", "tocho", "hocho",
                      "thanha", "khanha", "nhanhaj", "toanha", "quanha"])
    func noCircumflexAcrossPalatalCoda(_ keys: String) {
        let r = screens(keys)
        for step in r.steps {
            #expect(!step.contains("â") && !step.contains("ô") && !step.contains("ậ"),
                    "\(keys): step \(step)")
        }
        #expect(r.committed == keys + " ")
    }

    // MARK: Kept: legal across-coda circumflex and nh/ch words

    @Test(arguments: [
        ("tenhe", "tênh "), ("benhe", "bênh "), ("khuechse", "khuếch "),
        ("khuyechse", "khuyếch "), ("quenhfe", "quềnh "), ("quechje", "quệch "),
        ("ghenhfe", "ghềnh "), ("nghenhe", "nghênh "),
        ("tana", "tân "), ("cana", "cân "), ("nhanaj", "nhận "), ("hopoj", "hộp "),
        ("tocos", "tốc "), ("tacas", "tấc "), ("trene", "trên "),
        ("canhs", "cánh "), ("sachs", "sách "), ("thanhf", "thành "),
        ("toanhs", "toánh "), ("huynhf", "huỳnh "), ("tinhs", "tính "),
    ])
    func legalWordsUnchanged(_ keys: String, _ expected: String) {
        #expect(screens(keys).committed == expected)
    }

    @Test func managerStillRevertsAtTheEnd() {
        #expect(screens("manager").committed == "manager ")
    }

    @Test func uyenhIsStillRefused() {
        // uyê takes ch (khuyếch) but never nh.
        #expect(screens("khuyenhe").committed == "khuyenhe ")
    }

    /// Without restore, nothing reverts the composed text, so the fold itself is
    /// what the user keeps: this pins the gate, not the restore.
    private let noRestore = EngineConfig(
        restoreIfInvalid: false, allowFreeToneMark: true, freeMarkAcrossCoda: true,
        spellCheck: false)

    @Test func palatalRefusalHoldsWithoutRestore() {
        #expect(screens("tanha", config: noRestore).committed == "tanha ")
        #expect(screens("tenhe", config: noRestore).committed == "tênh ")
    }

    @Test(arguments: [("tauna", "tauna "), ("toino", "toino "), ("teune", "teune ")])
    func offglideNucleusIsNotClosedAcrossTheCoda(_ keys: String, _ expected: String) {
        // isLegalRime: âu, ôi, êu never take a consonant coda (main built tâun).
        #expect(screens(keys, config: noRestore).committed == expected)
    }
}
