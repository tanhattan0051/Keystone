// CommitRimeTests.swift — commit-time rime validity (`Phonology.isCompleteRime`)
// versus the mid-word predicate (`Phonology.isLegalRime`). See DECISIONS.md
// "Commit-time rime completeness".

import Testing
@testable import KeystoneEngine

private let cfg = EngineConfig(inputMethod: .telex, restoreIfInvalid: true, allowFreeToneMark: true,
                               freeMarkAcrossCoda: true, literalAfterCancel: true, spellCheck: true)

private func typeThroughEngine(_ keys: String) -> String {
    let engine = Engine(config: cfg)
    var acc: [Unicode.Scalar] = []
    func apply(_ r: EngineResult) {
        if r.backspaceCount > 0 { acc.removeLast(min(r.backspaceCount, acc.count)) }
        acc.append(contentsOf: r.text.unicodeScalars)
    }
    for ch in keys { apply(engine.process(KeyInput(ch))) }
    apply(engine.flush())
    return String(String.UnicodeScalarView(acc))
}

@Suite("CommitRime")
struct CommitRimeTests {
    // MARK: pure predicate

    @Test func closedOnlyNucleiRejectedOpen() {
        for n in ["ă", "â", "oă", "uâ", "iê", "yê", "uô", "uyê"] {
            #expect(!Phonology.isCompleteRime(nucleus: n, coda: ""), "open \(n)")
        }
    }

    @Test func closedOnlyNucleiAcceptedWithCoda() {
        for n in ["ă", "â", "oă", "uâ", "iê", "yê", "uô", "uyê"] {
            #expect(Phonology.isCompleteRime(nucleus: n, coda: "n"), "\(n)+n")
            #expect(Phonology.isCompleteRime(nucleus: n, coda: "t"), "\(n)+t")
        }
    }

    @Test func openNucleiStillAcceptedOpen() {
        for n in ["a", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y", "ai", "âu", "ây", "ia", "ua", "ưa", "oa", "uy", "uơ"] {
            #expect(Phonology.isCompleteRime(nucleus: n, coda: ""), "open \(n)")
        }
    }

    @Test func bareIAndYRejectVelarCodas() {
        for n in ["i", "y"] {
            #expect(!Phonology.isCompleteRime(nucleus: n, coda: "ng"), "\(n)+ng")
            #expect(!Phonology.isCompleteRime(nucleus: n, coda: "c"), "\(n)+c")
        }
    }

    @Test func bareIAndYAcceptOtherCodas() {
        for n in ["i", "y"] {
            for c in ["", "nh", "ch", "n", "m", "t", "p"] {
                #expect(Phonology.isCompleteRime(nucleus: n, coda: c), "\(n)+\(c)")
            }
        }
    }

    @Test func otherNucleiKeepVelarCodas() {
        #expect(Phonology.isCompleteRime(nucleus: "a", coda: "ng"))
        #expect(Phonology.isCompleteRime(nucleus: "e", coda: "c"))
        #expect(Phonology.isCompleteRime(nucleus: "uy", coda: "c"))
    }

    @Test func offglideFinalStillRejectedWithCoda() {
        #expect(!Phonology.isCompleteRime(nucleus: "ai", coda: "n"))
        #expect(!Phonology.isCompleteRime(nucleus: "oi", coda: "ng"))
    }

    @Test func midWordPredicateUnchanged() {
        // isLegalRime stays permissive: an open "ă"/"iê" is a mid-word prefix.
        #expect(Phonology.isLegalRime(nucleus: "ă", coda: ""))
        #expect(Phonology.isLegalRime(nucleus: "iê", coda: ""))
        #expect(Phonology.isLegalRime(nucleus: "i", coda: "ng"))
    }

    // MARK: engine (no lexicon)

    @Test func englishLookalikesRevertAtCommit() {
        #expect(typeThroughEngine("saw ") == "saw ")
        #expect(typeThroughEngine("disc ") == "disc ")
    }

    @Test func vietnameseStillComposes() {
        #expect(typeThroughEngine("awn ") == "ăn ")
        #expect(typeThroughEngine("tieengs ") == "tiếng ")
        #expect(typeThroughEngine("tinhs ") == "tính ")
    }
}
